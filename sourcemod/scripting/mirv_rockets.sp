#pragma semicolon 1
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools>

public Plugin MyInfo =
{
	name = "MIRV Rockets",
	author = "IvoryPal",
	description = "Rockets split into smaller rockets after a short delay."
};

#define ExplodeSound	"ambient/explosions/explode_8.wav"

bool PlayerHasMirv[MAXPLAYERS+1];
bool RocketOverride[2049];
bool MirvRocket[2049];
bool MirvConverge[2049];

float ConvergePoint[2049][3];
float MinFlightTime[2049];

int ExplodeSprite;
int glow;

ConVar g_rocketDelay;
ConVar g_rocketCount;
ConVar g_rocketCurve;

public void OnPluginStart()
{
	g_rocketDelay = CreateConVar("mirv_rocket_delay", "0.8", "Delay before a mirv rocket splits into other rockets");
	g_rocketCount = CreateConVar("mirv_rocket_count", "3", "How many rockets a mirv rocket splits into", _, true, 2.0, true, 6.0);
	g_rocketCurve = CreateConVar("mirv_converge_rockets", "0", "Do rockets converge on a single point after splitting", _, true, 0.0, true, 1.0);

	ExplodeSprite = PrecacheModel("sprites/sprite_fire01.vmt");
	PrecacheSound(ExplodeSound);

	//Events
	AddCommandListener(PlayerJoinClass, "joinclass");

	RegConsoleCmd("sm_mirv", CmdControl);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client))
		{
			OnClientPostAdminCheck(client);
		}
	}
}

public void OnMapStart()
{
	ExplodeSprite = PrecacheModel("sprites/sprite_fire01.vmt");
	glow = PrecacheModel("materials/sprites/laser.vmt");
	PrecacheSound(ExplodeSound);
}

public Action PlayerJoinClass(int client, const char[] command, int argc)
{
	if (TF2_GetPlayerClass(client) == TFClass_Soldier && PlayerHasMirv[client])
	{
		PlayerHasMirv[client] = false;
		PrintToChat(client, "[SM] Disabling MIRV rockets due to class change.");
	}
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	PlayerHasMirv[client] = false;
}

Action CmdControl(int client, int args)
{
	if (TF2_GetPlayerClass(client) != TFClass_Soldier)
	{
		PrintToChat(client, "[SM] You must be a soldier to use this command!");
	}
	else
	{
		PlayerHasMirv[client] = !PlayerHasMirv[client];
		PrintToChat(client, "[SM] MIRV Rockets %s!", PlayerHasMirv[client] ? "enabled" : "disabled");
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!(StrContains(classname, "tf_projectile_rocket")))
	{
		//SDKHook(entity, SDKHook_SpawnPost, OnRocketSpawned);
		RequestFrame(OnRocketSpawned, entity);
		SDKHook(entity, SDKHook_Touch, OnRocketEnd);
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || entity > 2048) return; //prevent ent refs being used
	if (IsValidEntity(entity))
	{
		RocketOverride[entity] = false;
		MirvRocket[entity] = false;
		MirvConverge[entity] = false;
	}
}

public void OnRocketSpawned(int rocket)
{
	int owner = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClient(owner)) return;

	if (PlayerHasMirv[owner] && !MirvRocket[rocket])
	{
		//PrintToChat(owner, "Rocket Spawned");
		RocketOverride[rocket] = true;
		int ref = EntIndexToEntRef(rocket);
		CreateTimer(GetConVarFloat(g_rocketDelay), RocketTimer, ref, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action RocketTimer(Handle timer, any ref)
{
	int rocket = EntRefToEntIndex(ref);
	//PrintToChatAll("Rocket: %i", rocket);
	if (IsValidRocket(rocket) && RocketOverride[rocket])
	{
		SplitRocket(rocket, GetConVarBool(g_rocketCurve));
	}
}

void SplitRocket(int rocket, bool converge)
{
	float pos[3], rocketAngle[3], convergePos[3];
	int owner = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (!IsValidClient(owner)) return;
	if (!IsValidEntity(rocket) || rocket < MaxClients) return;

	GetEntPropVector(rocket, Prop_Data, "m_vecOrigin", pos);
	GetEntPropVector(rocket, Prop_Send, "m_angRotation", rocketAngle);
	int crit = GetEntProp(rocket, Prop_Send, "m_bCritical");
	RocketOverride[rocket] = false;
	AcceptEntityInput(rocket, "Kill");

	//converge
	if (converge)
	{
		SetupConvergePoint(pos, rocketAngle, 1500.0, convergePos, owner);
	}
	else
		rocketAngle[0] += GetRandomFloat(1.0, 10.0);
	EmitSoundToAll(ExplodeSound, rocket);
	TE_SetupExplosion(pos, ExplodeSprite, 3.0, 1, 0, 100, 10);
	TE_SendToAll();
	int count = GetConVarInt(g_rocketCount);
	//PrintToChat(owner, "Mirv count: %i", count);
	for (int i = 1; i <= count; i++)
	{
		float angles[3], newPos[3];
		for (int axis = 0; axis <= 2; axis++)
		{
			newPos[axis] = pos[axis] + GetRandomFloat(-3.0, 3.0); //prevent rockets from colliding with each other
			if (converge) //much larger spread if rockets converge on a point
				angles[axis] = rocketAngle[axis] + GetRandomFloat(-35.0, 35.0);
			else
				angles[axis] = rocketAngle[axis] + GetRandomFloat(-5.0, 5.0);
		}

		int mirv = CreateEntityByName("tf_projectile_rocket");
		//PrintToChat(owner, "Mirv spawned: %i", mirv);
		MirvRocket[mirv] = true;
		int team = GetClientTeam(owner);
		SetVariantInt(team);
		AcceptEntityInput(mirv, "TeamNum");
		AcceptEntityInput(mirv, "SetTeam");
		SetEntPropEnt(mirv, Prop_Send, "m_hOwnerEntity", owner);
		float vel[3];
		GetAngleVectors(angles, vel, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(vel, 1100.0);
		TeleportEntity(mirv, newPos, angles, vel);
		DispatchSpawn(mirv);
		SetEntProp(mirv, Prop_Send, "m_bCritical", crit);
		SetEntDataFloat(mirv, FindSendPropInfo("CTFProjectile_Rocket", "m_iDeflected") + 4, 50.0);

		if (converge)
		{
			MirvConverge[mirv] = true;
			MinFlightTime[mirv] = GetEngineTime() + 0.1;
			ConvergePoint[mirv][0] = convergePos[0] += GetRandomFloat(-50.0, 50.0);
			ConvergePoint[mirv][1] = convergePos[1] += GetRandomFloat(-50.0, 50.0);
			ConvergePoint[mirv][2] = convergePos[2] += GetRandomFloat(-50.0, 50.0);
		}
		continue;
	}
}

public bool FilterCollision(int entity, int ContentsMask)
{
	if (entity == 0)
	{
		return true;
	}
	return false;
}

void SetupConvergePoint(float pos[3], float angle[3], float range, float bufferPos[3], int owner)
{
	float forwardPos[3];
	GetAngleVectors(angle, forwardPos, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(forwardPos, range);
	AddVectors(pos, forwardPos, forwardPos);
	Handle trace = TR_TraceRayFilterEx(pos, forwardPos, MASK_PLAYERSOLID, RayType_EndPoint, FilterCollision);
	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(bufferPos, trace);
		//TE_SetupBeamPoints(pos, bufferPos, glow, glow, 0, 1, 5.0, 5.0, 5.0, 10, 0.0, {0, 255, 0, 255}, 10);
		//TE_SendToClient(owner);
		CloseHandle(trace);
		return;
	}
	//TE_SetupBeamPoints(pos, forwardPos, glow, glow, 0, 1, 5.0, 5.0, 5.0, 10, 0.0, {255, 0, 0, 255}, 10);
	//TE_SendToClient(owner);
	CloseHandle(trace);
	bufferPos = forwardPos;
	return;
}

public void OnGameFrame()
{
	int rocket = MaxClients + 1;
	while ((rocket = FindEntityByClassname(rocket, "tf_projectile_rocket")) != -1)
	{
		if (MirvConverge[rocket])
		{
			ConvergeRocket(rocket);
		}
	}
}

void ConvergeRocket(int rocket)
{
	if (IsValidEntity(rocket) && MirvConverge[rocket])
	{
		float curPos[3], curAngle[3], trajectory[3], vel[3], speed;
		GetEntPropVector(rocket, Prop_Data, "m_vecOrigin", curPos);
		GetEntPropVector(rocket, Prop_Data, "m_angRotation", curAngle);
		GetEntPropVector(rocket, Prop_Data, "m_vecAbsVelocity", vel);
		speed = GetVectorLength(vel);

		MakeVectorFromPoints(curPos, ConvergePoint[rocket], trajectory);
		NormalizeVector(trajectory, trajectory);
		float distance = ClampFloat(GetVectorDistance(curPos, ConvergePoint[rocket]), 0.0, 70.0);
		ScaleVector(trajectory, distance);
		AddVectors(curPos, trajectory, trajectory);

		AddVectors(vel, trajectory, vel);
		NormalizeVector(vel, vel);
		GetVectorAngles(vel, curAngle);
		ScaleVector(vel, speed);
		TeleportEntity(rocket, NULL_VECTOR, curAngle, vel);

		//Debug for trajectory and angle
		float forwardVec[3], angleVec[3];
		GetAngleVectors(curAngle, forwardVec, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(forwardVec, 150.0);
		AddVectors(curPos, forwardVec, forwardVec);
		angleVec = trajectory;
		NormalizeVector(angleVec, angleVec);
		ScaleVector(angleVec, 150.0);
		AddVectors(curPos, angleVec, angleVec);
		//forward visual
		//TE_SetupBeamPoints(curPos, forwardVec, glow, glow, 0, 1, 5.0, 5.0, 5.0, 10, 0.0, {100, 0, 200, 255}, 10);
		//TE_SendToAll();
		//angle visual
		//TE_SetupBeamPoints(curPos, angleVec, glow, glow, 0, 1, 5.0, 5.0, 5.0, 10, 0.0, {255, 255, 0, 255}, 10);
		//TE_SendToAll();

		//Check angle between rocket forward vector and position
		NormalizeVector(forwardVec, forwardVec);
		NormalizeVector(angleVec, angleVec);
		float dot = GetVectorDotProduct(forwardVec, angleVec) / GetVectorLength(forwardVec, true);
		float rad = ArcCosine(dot);
		float deg = RadToDeg(rad);
		if (deg <= 1.0 && MinFlightTime[rocket] <= GetEngineTime()) //stop converging once the angle is small enough
		{
			//PrintToChatAll("Final Angle: %.1f", deg);
			MirvConverge[rocket] = false;
			PrintToChatAll("Converge End");
		}
	}
}

//Make sure to take the player out of the remote control state upon a rocket hitting something
public Action OnRocketEnd(int rocket, int victim)
{
	if (RocketOverride[rocket])
	{
		int owner = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
		if (!IsValidClient(victim))
		{
	    	char classname[64];
	    	GetEntityClassname(victim, classname, sizeof classname);
	    	if (victim == 0 || !StrContains(classname, "prop_", false) || !StrContains(classname, "obj_", false) || !StrContains(classname, "func_door")) //solid props
	    	{
				RocketOverride[rocket] = false;
			}
		}
	}
	return Plugin_Continue;
}

bool IsValidClient(int bot)
{
    if ( !( 1 <= bot <= MaxClients ) || !IsClientInGame(bot) )
        return false;

    return true;
}

bool IsValidRocket(int rocket)
{
	if (!IsValidEntity(rocket))
		return false;
	if (RocketOverride[rocket] && rocket > MaxClients)
		return true;

	return false;
}

float ClampFloat(float value, float min, float max)
{
	if (value > max) return max;
	if (value < min) return min;
	return value;
}
