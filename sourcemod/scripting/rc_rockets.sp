#pragma semicolon 1
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools>

public Plugin MyInfo =
{
	name = "Remote Controlled Rockets",
	author = "IvoryPal",
	description = "Control rockets remotely from the rocket's pov."
};

bool ControllingRocket[MAXPLAYERS+1];
bool PlayerControlRockets[MAXPLAYERS+1];
bool RocketOverride[2049];
int RocketID[MAXPLAYERS+1];

//rocket settings
int AimType;
float RotRate;

ConVar g_rocketTurnRate;
ConVar g_rocketAimType;

public void OnPluginStart()
{
	g_rocketTurnRate = CreateConVar("rc_rocket_turn_rate", "100.0", "Degrees per second at which rockets rotate when being controlled by player movement");
	g_rocketAimType = CreateConVar("rc_rocket_aim_type", "1", "Method for aiming rockets. 0 = player movement | 1 = player aim");
	HookConVarChange(g_rocketAimType, OnRocketAimChanged);

	//Events
	AddCommandListener(PlayerJoinClass, "joinclass");
	HookEvent("player_death", PlayerDeath);

	RegConsoleCmd("sm_rc", CmdControl);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client))
		{
			OnClientPostAdminCheck(client);
		}
	}
}

public void OnRocketAimChanged(ConVar convar, char[] oldVal, char[] newVal)
{
	AimType = StringToInt(newVal);
}

public void OnRocketRateChanged(ConVar convar, char[] oldVal, char[] newVal)
{
	RotRate = StringToFloat(newVal);
}

public Action PlayerDeath(Handle event, const char[] name, bool dBroad)
{
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (ControllingRocket[victim])
	{
		SetPlayerRCMode(victim, false);
	}
}

public Action PlayerJoinClass(int client, const char[] command, int argc)
{
	if (TF2_GetPlayerClass(client) == TFClass_Soldier && PlayerControlRockets[client])
	{
		PlayerControlRockets[client] = false;
		PrintToChat(client, "[SM] Disabling RC rockets due to class change.");
	}
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	//clear variables
	ControllingRocket[client] = false;
	PlayerControlRockets[client] = false;
	RocketID[client] = INVALID_ENT_REFERENCE;
}

Action CmdControl(int client, int args)
{
	if (TF2_GetPlayerClass(client) != TFClass_Soldier)
	{
		PrintToChat(client, "[SM] You must be a soldier to use this command!");
	}
	else
	{
		PlayerControlRockets[client] = !PlayerControlRockets[client];
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
	}
}

public void OnRocketSpawned(int rocket)
{
	int owner = GetEntPropEnt(rocket, Prop_Send, "m_hOwnerEntity");
	if (PlayerControlRockets[owner])
	{
		RocketID[owner] = rocket;
		RocketOverride[rocket] = true;
		SetPlayerRCMode(owner, true);
	}
}

void SetPlayerRCMode(int client, bool status)
{
	ControllingRocket[client] = status;
	if (status && IsValidRocket(RocketID[client]))
	{
		SetClientViewEntity(client, RocketID[client]);
		SetEntityMoveType(client, MOVETYPE_NONE);
	}
	else
	{
		SetClientViewEntity(client, client);
		SetEntityMoveType(client, MOVETYPE_WALK);
		RocketID[client] = INVALID_ENT_REFERENCE;
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
				SetPlayerRCMode(owner, false);
			}
		}
		else if (IsValidClient(victim))
		{
			bool sameTeam = (GetClientTeam(owner) == GetClientTeam(victim)); //check if the player we hit is an enemy player
			if (sameTeam)
			{
				//return Plugin_Handled; //pass through teammates to prevent control being lost on player overlap - DOESNT WORK NEED A BETTER METHOD
			}
			else
			{
				SetPlayerRCMode(owner, false);
			}
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (ControllingRocket[client] && IsValidRocket(RocketID[client]))
	{
		buttons &= ~IN_ATTACK;
		int rocket = RocketID[client];
		float rocketAngle[3], forwardVec[3], velocity[3], speed;
		float rate = RotRate / 67.0; //this function executes ~67 times per second, so divide by 67 to get our turn rate in degrees per second.
		GetEntPropVector(rocket, Prop_Data, "m_vecVelocity", velocity);
		GetEntPropVector(rocket, Prop_Send, "m_angRotation", rocketAngle);
		speed = GetVectorLength(velocity);
		//movement
		switch (AimType)
		{
			case 0: //player movement
			{
				if (buttons & IN_FORWARD) //angle down
				{
					rocketAngle[0] += rate;
				}
				if (buttons & IN_BACK) //angle up
				{
					rocketAngle[0] -= rate;
				}
				if (buttons & IN_MOVERIGHT)
				{
					rocketAngle[1] -= rate;
				}
				if (buttons & IN_MOVELEFT)
				{
					rocketAngle[1] += rate;
				}
			}
			case 1:
			{
				GetClientEyeAngles(client, rocketAngle);
			}
		}
		GetAngleVectors(rocketAngle, forwardVec, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(forwardVec, speed);
		TeleportEntity(rocket, NULL_VECTOR, rocketAngle, forwardVec);
	}
}

bool IsValidClient(int bot)
{
    if ( !( 1 <= bot <= MaxClients ) || !IsClientInGame(bot) )
        return false;

    return true;
}

bool IsValidRocket(int rocket)
{
	if (RocketOverride[rocket] && IsValidEntity(rocket) && rocket > MaxClients)
		return true;

	return false;
}
