#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>

//Models for the mortar
//SENTRYHULL is used for collision/hitboxes
//SENTRYBASE is just the base of the sentry
//SENTRYTURRET is the turret that moves and tracks players
#define SENTRYHULL "models/sentrybot/sentrybot_capsule_hull.mdl"
#define SENTRYTURRET "models/sentrybot/sentrybot_turret.mdl"
#define SENTRYBASE "models/sentrybot/sentrybot_capsule_hull.mdl" //don't have a base model, so just using the hull

#define SOUND_SAPPER_NOISE      "weapons/sapper_timer.wav"
#define SOUND_SAPPER_PLANT      "weapons/sapper_plant.wav"

#define SENTRY_FIRERATE 0.5
#define GRENADE_SPEED 950.0
#define SENTRY_RANGE 1100.0

Handle gravscale;
bool bPipeContact[2048];

float vecEPosR[3] = {5555.0, 5555.0, 5555.0}; //Location to teleport current sentry to
float vecEPosB[3] = {-5555.0, -5555.0, 5555.0}; //Location to teleport blue sentries

int gHalo1;
int gLaser1;

//Sentry variables
int SentryOwner[2048];
int SentrySapper[2048];
int SentryTarget[2048]; 		//Current target for this sentry
int SentryHealth[2048];
int SentryBase[2048]; 			//Physcial base of the turret
int SentryTurret[2048];			//Barrels/turret head
float SentryFireDelay[2048];
float ClosestDistance[2048];
float SentrySpawnPos[2048][3];

//Player Variables
int PlayerSentry[MAXPLAYERS+1];
bool HasCustomSentry[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "Mortar Sentry",
	author = "IvoryPal",
	description = "Custom Mortar Sentry",
	version = "1.00",
	url = "https://creators.tf"
};

public void OnPluginStart()
{
	RegAdminCmd("sm_useturret", ToggleTurret, ADMFLAG_ROOT);
	
	//Building hooks
	HookEvent("player_builtobject", EventObjectBuilt);
	HookEvent("object_destroyed", EventObjectDestroyed);
	HookEvent("object_detonated", EventObjectDetonate);
	
	//Visuals for projectile indicator
	gLaser1 = PrecacheModel("materials/sprites/laser.vmt");
	gHalo1 = PrecacheModel("materials/sprites/halo01.vmt");
	
	//Get our gravity scale
	gravscale = FindConVar("sv_gravity");
}

public void OnMapStart()
{
	PrecacheModel(SENTRYBASE);
	PrecacheModel(SENTRYTURRET);
	PrecacheSound(SOUND_SAPPER_NOISE);
	PrecacheSound(SOUND_SAPPER_PLANT);
	
	gLaser1 = PrecacheModel("materials/sprites/laser.vmt");
	gHalo1 = PrecacheModel("materials/sprites/halo01.vmt");
}

//Just a simple toggle for the mortar
public Action ToggleTurret(int client, int args)
{
	HasCustomSentry[client] = !HasCustomSentry[client];
}

//Begin the process of setting up the mortar
//TODO - Use an SDKCall to actually allow this mortar to have a build time
public Action EventObjectBuilt(Event hEvent, const char[] name, bool dBroad)
{
	int building = GetEventInt(hEvent, "object");
	int player = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	//LogMessage("Object: %i", building);
	switch (building)
	{
		case 2:
		{
			int sentry = GetEventInt(hEvent, "index");
			//LogMessage("Sentry built with index: %i", sentry);
			SentryCreated(sentry, player);
		}
	}
}

//Any other time a sentry is destroyed.. will probably never be used but leaving just in case
public Action EventObjectDestroyed(Event eEvent, const char[] name, bool dBroad)
{
	int building = GetEventInt(eEvent, "objecttype");
	int owner = GetClientOfUserId(GetEventInt(eEvent, "userid"));
	
	switch (building)
	{
		case 2:
		{
			if (HasValidSentry(owner))
				DestroySentry(PlayerSentry[owner]);
		}
	}
}

//Used to allow engineers to destroy their own mortar with the destruction PDA
public Action EventObjectDetonate(Event bEvent, const char[] name, bool dBroad)
{
	int building = GetEventInt(bEvent, "objecttype");
	int owner = GetClientOfUserId(GetEventInt(bEvent, "userid"));
	
	switch (building)
	{
		case 2:
		{
			if (HasValidSentry(owner))
				DestroySentry(PlayerSentry[owner]);
		}
	}
} 

public void SentryCreated(int sentry, int owner)
{
	//LogMessage("Step 1");
	if (HasCustomSentry[owner])
		DeployCustomTurret(sentry, owner);
}

public void DeployCustomTurret(int sentry, int owner)
{
	if (IsValidClient(owner) && IsValidEntity(sentry))
	{
		float spawnAng[3], spawnPos[3];
		GetEntPropVector(sentry, Prop_Send, "m_vecOrigin", spawnPos);
		GetEntPropVector(sentry, Prop_Send, "m_angRotation", spawnAng);
		
		//Teleport our real sentry outside the map instead of removing it
		switch (GetClientTeam(owner))
		{
			case 2: TeleportEntity(sentry, vecEPosR, NULL_VECTOR, NULL_VECTOR);
			case 3: TeleportEntity(sentry, vecEPosB, NULL_VECTOR, NULL_VECTOR);
		}
		
		//initialize sentry
		int turret = CreateSentryBot();
		SentryOwner[turret] = owner;
		PlayerSentry[owner] = turret;
		
		SentrySpawnPos[turret] = spawnPos;
		
		//set locations
		TeleportEntity(turret, spawnPos, spawnAng, NULL_VECTOR);
		TeleportEntity(SentryBase[turret], spawnPos, spawnAng, NULL_VECTOR);
		spawnPos[2] += 30.0;
		TeleportEntity(SentryTurret[turret], spawnPos, spawnAng, NULL_VECTOR);
		SetEntProp(turret, Prop_Data, "m_takedamage", 1);
		SetEntProp(SentryTurret[turret], Prop_Data, "m_takedamage", 1);
		SentryHealth[turret] = GetEntProp(sentry, Prop_Send, "m_iMaxHealth");
		SDKHook(turret, SDKHook_OnTakeDamage, SentryTakeDamage);
		SentryFireDelay[turret] = 0.0;
	}
}


public Action SentryTakeDamage(int mortar, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (IsValidEntity(mortar))
	{
		int owner = SentryOwner[mortar];
		int oldSentry = FindSentryGun(owner);
		if (GetClientTeam(attacker) != GetClientTeam(owner))
		{
			SentryHealth[mortar] -= RoundToFloor(damage);
			
			//Send damage event to attacker
			SendDamageEvent(mortar, attacker, RoundToFloor(damage), weapon);
			
			if (SentryHealth[mortar] <= 0)
			{
				//Destroy our custom sentry
				DestroySentry(mortar);
				
				//Destroy our real sentry and set the proper attacker
				SDKHooks_TakeDamage(oldSentry, attacker, inflictor, 300.0, DMG_ENERGYBEAM);
				
				//Send destroy event
				//SendDestroyEvent(owner, attacker, weapon, mortar);
			}
			else
			{
				//Only remove health from sentry if mortar is still alive
				SetVariantInt(RoundToFloor(damage));
				AcceptEntityInput(oldSentry, "RemoveHealth");
			}
		}

		//Check if the attacking player is the owner
		//This is used to repair/reload the sentry
		else if (attacker == owner)
		{
			//int hWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
			int iWrenchSlot = GetPlayerWeaponSlot(attacker, 2);
			if (weapon == iWrenchSlot)
			{
				if (!SentryDisabled(oldSentry))
					RepairSentry(oldSentry, mortar, owner);
				else
					TryRemoveSapper(oldSentry, mortar, owner);
			}
		}
	}
}

public void RepairSentry(int oldSentry, int mortar, int owner)
{
	//Get sentry HP and player metal
	int maxHP = GetEntProp(oldSentry, Prop_Send, "m_iMaxHealth");
	int maxShells2 = GetSentryMaxShells(oldSentry);
	int iMetal = GetEntProp(owner, Prop_Send, "m_iAmmo", _, 3);

	//Make sure the player has metal to repair
	if (iMetal > 0)
	{
		//get metal to remove
		int RepairAmount, remainder, addAmmo, metalDecrement;
		remainder = iMetal;
		
		//repair HP if less than max
		if (SentryHealth[mortar] < maxHP)
		{
			RepairAmount = (iMetal >= 34) ? 102 : RoundFloat((float(iMetal) / 34.0) * 102.0);
			remainder = (iMetal > 34) ? iMetal - 34 : 0;
		}
		
		//If we still have metal left over, add ammo to the sentry
		if (remainder > 0)
			addAmmo = (remainder >= 40) ? 40 : remainder; //Adding ammo to a sentry costs 1 metal per bullet, up to a max of 40 bullets per wrench swing

		metalDecrement = addAmmo + 34;
		
		//repair sentrygun
		SentryHealth[mortar] += RepairAmount;
		SetVariantInt(RepairAmount);
		AcceptEntityInput(oldSentry, "AddHealth");
		int rounds = GetEntProp(oldSentry, Prop_Send, "m_iAmmoShells");
		rounds += addAmmo;
		if (rounds >= maxShells2) rounds = maxShells2;
		SetEntProp(oldSentry, Prop_Send, "m_iAmmoShells", rounds);
		
		//Remove metal from player
		iMetal -= metalDecrement;
		if (iMetal <= 0) iMetal = 0;
		SetEntProp(owner, Prop_Send, "m_iAmmo", iMetal, _, 3); 
	}
}

//Will be used to get total ammo from sentry based on level
//For now just return level 1 amount
public int GetSentryMaxShells(int sentry)
{
	return 150;
}

public void TryRemoveSapper(int oldSentry, int mortar, int owner)
{
	//Just a single swing for now
	RemoveSapper(oldSentry, mortar);
}

public void SendDamageEvent(int victim, int attacker, int damage, int weapon)
{
	//Don't send damage event if the attacker is not a client, or the attacker is sapping the sentry
	if (IsValidClient(attacker) && attacker != SentrySapper[victim])
	{
		Handle SentryHurt = CreateEvent("npc_hurt", true);
		
		//setup components for event
		SetEventInt(SentryHurt, "entindex", victim);
		SetEventInt(SentryHurt, "weaponid", weapon);
		
		SetEventInt(SentryHurt, "attacker_player", GetClientUserId(attacker));
		SetEventInt(SentryHurt, "damageamount", damage);
		FireEvent(SentryHurt, false);
	}
}

stock int CreateSentryBot()
{
	int sentry;
	//PrintToChatAll("Creating Sentry...");
	
	//create root component:
	//	- This will be the entity the rest of the sentry is connected to
	
	sentry = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(sentry, "model", SENTRYHULL);
	DispatchKeyValue(sentry, "solid", "6");
	DispatchSpawn(sentry);
	ActivateEntity(sentry);
	AcceptEntityInput(sentry, "Disable");
	SetEntProp(sentry, Prop_Send, "m_usSolidFlags", 0x0100);
	SetEntProp(sentry, Prop_Data, "m_nSolidType", 6);
	SetEntProp(sentry, Prop_Send, "m_CollisionGroup", 2);
	
	//Create Sentry base, parent to capsule, change targetname:
	//	- This is the physical base to the turret
	
	SentryBase[sentry] = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(SentryBase[sentry], "model", SENTRYBASE);
	DispatchSpawn(SentryBase[sentry]);
	ActivateEntity(SentryBase[sentry]);
	
	//Create Turret and parent to base:
	//	- Barrels of the turret/turet head
	//	- This entity will be what actively rotates to track and fire at players
	
	SentryTurret[sentry] = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(SentryTurret[sentry], "model", SENTRYTURRET);
	DispatchSpawn(SentryTurret[sentry]);
	ActivateEntity(SentryTurret[sentry]);
	//PrintToChatAll("Sentry Turret created with ID: %i", SentryTurret[sentry]);
	
	ClosestDistance[sentry] = SENTRY_RANGE;
	SentryTarget[sentry] = 0;
	CreateTimer(0.8, SentryTargetTick, sentry, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	return sentry;
}

//This controls how the sentry picks its targets
public Action SentryTargetTick(Handle Timer, int mortar)
{
	//PrintToServer("sentry target tick");
	if (!IsValidEntity(mortar)) return Plugin_Stop;
	
	int sentryOwner = SentryOwner[mortar];
	float playerpos[3], distance;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsValidTarget(sentryOwner, client, mortar))
		{
			if (client == SentryTarget[mortar])
			{
				if (!IsPlayerAlive(client))
				{
					ClosestDistance[mortar] = SENTRY_RANGE;
				}
				GetClientEyePosition(client, playerpos);
				distance = GetVectorDistance(SentrySpawnPos[mortar], playerpos);
				ClosestDistance[mortar] = distance;
				return Plugin_Continue;
			}
			if (IsPlayerAlive(client))
			{
				GetClientEyePosition(client, playerpos);
				distance = GetVectorDistance(SentrySpawnPos[mortar], playerpos);
				if (distance < ClosestDistance[mortar])
				{
					ClosestDistance[mortar] = distance;
					SentryTarget[mortar] = client;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (HasValidSentry(client))
	{
		int mortar = PlayerSentry[client];
		int oldSentry = FindSentryGun(client);
		
		float targetpos[3], sentryrot[3], aimangle[3];
		if (ClosestDistance[mortar] <= SENTRY_RANGE && !SentryDisabled(oldSentry) && oldSentry > MaxClients)
		{
			if (IsValidClient(SentryTarget[mortar]) && IsPlayerAlive(SentryTarget[mortar]))
			{
				GetEntPropVector(SentryTurret[mortar], Prop_Send, "m_angRotation", sentryrot);
				GetClientEyePosition(SentryTarget[mortar], targetpos);
				targetpos[2] -= 46.0;
				
				//Get predicted location and aim towards it
				GetAimPos(mortar, SentryTurret[mortar], SentryTarget[mortar], targetpos, sentryrot, GRENADE_SPEED, aimangle, true); //This function updates aimangle AND targetpos vectors
				TeleportEntity(SentryTurret[mortar], NULL_VECTOR, aimangle, NULL_VECTOR);
				if (SentryFireDelay[mortar] <= GetEngineTime())
				{
					SentryFireProjectile(mortar, sentryrot, GRENADE_SPEED, targetpos);
					SentryFireDelay[mortar] = (1 / SENTRY_FIRERATE) + GetEngineTime();
				}
			}
		}
	}

	//Possible attempt at sapper support... no idea if this will work
	if (TF2_GetPlayerClass(client) == TFClass_Spy)
	{
		int hWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		int iSapperSlot = GetPlayerWeaponSlot(client, 1);
		if (hWeapon == iSapperSlot && buttons & IN_ATTACK && !TF2_IsPlayerInCondition(client, TFCond_Cloaked))
		{
			int sent_owner;
			//int wIndex = GetEntProp(hWeapon, Prop_Send, "m_iItemDefinitionIndex");
			int customSentry = FindSentryLookTarget(client);
			if (customSentry > MaxClients)
				sent_owner = SentryOwner[customSentry];
				
			if (IsValidClient(sent_owner))
			{
				int oldSentry = FindSentryGun(sent_owner);
				if (!SentryDisabled(oldSentry))
				{
					//Play sapping animation
					TE_Start("PlayerAnimEvent");
					TE_WriteNum("m_iPlayerIndex", client);
					TE_WriteNum("m_iEvent", 2);
					TE_SendToAll();
					EmitSoundToAll(SOUND_SAPPER_NOISE, customSentry, _, _, _, 0.6);
					EmitSoundToAll(SOUND_SAPPER_PLANT, customSentry, _, _, _, 0.7);
					SapSentry(customSentry, client);
				}
			}
		}
	}
}

//Initial sapping
public void SapSentry(int mortar, int attacker)
{
	int owner = SentryOwner[mortar];
	int oldSentry = FindSentryGun(owner);
	if (HasEntProp(oldSentry, Prop_Send, "m_bDisabled") && !SentryDisabled(oldSentry))
	{
		SetEntProp(oldSentry, Prop_Send, "m_bDisabled", 1);
		SetEntProp(oldSentry, Prop_Send, "m_bHasSapper", 1); //Might be needed, not sure
		CreateTimer(0.1, PerformSap, mortar, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

		//We set the player sapping the sentry so that we can tell the damage event to not spam the player with hitsounds
		SentrySapper[mortar] = attacker;
	}
}

//Try sapping the sentry
public Action PerformSap(Handle Timer, int mortar)
{
	int owner = SentryOwner[mortar];
	int oldSentry = FindSentryGun(owner);
	if (!SentryDisabled(oldSentry))
		return Plugin_Stop;
		
	SDKHooks_TakeDamage(mortar, SentrySapper[mortar], SentrySapper[mortar], 2.0, DMG_ENERGYBEAM);
	return Plugin_Continue;
}

//Check if the sentry is already sapped
public bool SentryDisabled(int sentrygun)
{
	if (GetEntProp(sentrygun, Prop_Send, "m_bDisabled") == 1 && GetEntProp(sentrygun, Prop_Send, "m_bHasSapper") == 1)
		return true;
	
	return false;
}

//Not sure if this works but trying anyway
public void RemoveSapper(int sentrygun, int mortar)
{
	if (SentryDisabled(sentrygun))
	{
		SetEntProp(sentrygun, Prop_Send, "m_bDisabled", 0);
		SetEntProp(sentrygun, Prop_Send, "m_bHasSapper", 0);
		SentrySapper[mortar] = -1;
	}
}

//Try and predict where the target will be based on the projectile's speed and distance to target
stock float[] GetAimPos(int sentry, int turret, int target, float TargetLocation[3], float rot[3], float ProjSpeed, float aim[3], bool Arc = false)
{
	float TurretLocation[3], AimVector[3], flDistance, TargetVelocity[3], flTravelTime;
	GetEntPropVector(turret, Prop_Data, "m_vecAbsOrigin", TurretLocation);
	
	//Get target's velocity and distance to determine the travel time
	GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", TargetVelocity);
	flDistance = GetVectorDistance(TurretLocation, TargetLocation);
	flTravelTime = flDistance / ProjSpeed;
	
	//Setup gravity scale
	float flGravScale = GetConVarFloat(gravscale) / 100.0; //divide by 100 to get gravity in hu/s
	flGravScale = TargetVelocity[2] > 0.0 ? -flGravScale : flGravScale; //make sure to always adjust position downwards (subtract from positive movement, add to negative movement)
	
	//adjust to predicted position based on travel time
	//We shorten the distance by only accounting for half the travel time, this way it's a bit easier to dodge
	//This can be made variable based on the turret's level if so decided
	TargetLocation[0] += TargetVelocity[0] * (flTravelTime * 0.5);
	TargetLocation[1] += TargetVelocity[1] * (flTravelTime * 0.5);
	
	//Always target the ground position of the player
	TargetLocation[2] = GetGroundPosition(target, TargetLocation);
	
	//Apply gravity only if player is not on the ground
	//We actually don't need this since we will always be aiming at the ground position... keeping as a reference if needed
	//if (!(GetEntityFlags(target) & FL_ONGROUND))
	//	TargetLocation[2] += TargetVelocity[2] * flTravelTime + (flGravScale + Pow(flTravelTime, 2.0)) - 10.0; //gravity is quadratic and not constant, this isn't perfect but it's good enough
	
	MakeVectorFromPoints(TurretLocation, TargetLocation, AimVector);
	NormalizeVector(AimVector, AimVector);
	GetVectorAngles(AimVector, rot);
	
	//Try and adjust aim based on the angle needed to reach location
	if (Arc)
		rot[0] -= FindAngleForTrajectory(TurretLocation, TargetLocation, ProjSpeed, GetConVarFloat(gravscale), flDistance);
	
	for (int axis = 0; axis <= 2; axis++)
	{
		if (axis == 0)
		{
			if (rot[axis] <= -89.0)
			{
				rot[axis] = -89.0; //Do not allow sentry to aim more than 70 degrees up
			}
		}
		aim[axis] = rot[axis];
	}
}

public float GetGroundPosition(int target, float beginPos[3])
{
	float DownAngle[3] = {89.0, 0.0, 0.0};
	float endpos[3];
	beginPos[2] += 40.0;
	
	Handle position_trace = TR_TraceRayFilterEx(beginPos, DownAngle, MASK_PLAYERSOLID, RayType_Infinite, FilterSelf, target);
	if (TR_DidHit(position_trace))
	{
		TR_GetEndPosition(endpos, position_trace);
		CloseHandle(position_trace);
		return endpos[2];
	}
	return beginPos[2];
}

public bool FilterSelf(int entity, int contentsMask, any iExclude)
{
	char class[64];
	GetEntityClassname(entity, class, sizeof(class));
	
	if (StrEqual(class, "entity_medigun_shield"))
	{
		if (GetEntProp(entity, Prop_Send, "m_iTeamNum") == GetClientTeam(iExclude))
		{
			return false;
		}
	}
	else if (StrEqual(class, "func_respawnroomvisualizer"))
	{
		return false;
	}
	else if (StrContains(class, "tf_projectile_", false) != -1)
	{
		return false;
	}
	
	return !(entity == iExclude);
}

public float FindAngleForTrajectory(float vecPos[3], float vecTarget[3], float flSpeed, float flGravity, float flDistance)
{
	float angPredict[3];
	
	//Determine whether or not we can even reach our target; if we can't reach the target, return maximum turret angle
	float factor = ((flGravity * flDistance) / Pow(flSpeed, 2.0));
	if (factor >= 1.0) //can't take the arcsine of >1.0 so this distance is impossible to reach with our given projectile speed
	{
		//PrintCenterTextAll("Invalid Distance");
		return 70.0;
	}

	//If we can reach the target, calculate the angle needed
	angPredict[0] = RadToDeg((ArcSine(factor) * 0.5));
	
	//PrintCenterTextAll("Sentry Angle: %.1f\nFactor: %.1f\nGrav: %.1f\nDist: %.1f\nSpeed: %.1f", angPredict[0], factor, flGravity, flDistance, flSpeed);
	return angPredict[0];
}


//Fire projectile
stock void SentryFireProjectile(int mortar, float rot[3], float speed, float vecLocation[3])
{
	if (IsTargetVisible(mortar, SentryTarget[mortar])) //Make sure we can still see our target
	{
		int client = SentryOwner[mortar];
		int oldSentry = FindSentryGun(client);
		int iShells = GetEntProp(oldSentry, Prop_Send, "m_iAmmoShells");
		
		//Only fire if the mortar has ammo
		if (iShells > 0)
		{
			float vecForward[3], angRot[3], vecPos[3], vecVel[3];
			GetEntPropVector(SentryTurret[mortar], Prop_Send, "m_vecOrigin", vecPos);
			GetEntPropVector(SentryTurret[mortar], Prop_Send, "m_angRotation", angRot);
			int iTeam = GetClientTeam(client);
			
			float flGravScale = GetConVarFloat(gravscale);
			
			//Setup ring for where projectile is predicted to land [WIP]
			//This isn't perfect because of how VPhysics objects behave with damping/air resistance but it's a good approximation
			//This can be made almost perfect with a VPhysics extension, but we want to minimize the use of extensions as much as possible

			//Make sure angle is always positive for calculation
			float dAngle = (rot[0] < 0.0) ? rot[0] * -1 : rot[0];

			//Convert angle to radians for sine function
			float rAngle = DegToRad(dAngle);
			float SineAngle = Sine(rAngle);
			
			//Try and predict how long this projectile will take to reach its destination
			float flFlightTime = ((2.0 * speed * SineAngle) / flGravScale);

			//If for whatever reason the flight time is 0, set it to 1.0 to prevent lingering rings
			if (flFlightTime <= 0.0) flFlightTime = 1.0;
			
			//LogMessage("Predicted Flight Time: %.1f\nAngle: %.1f\nSine: %.1f", flFlightTime, dAngle, SineAngle);
			
			int rColor[4];
			switch (iTeam)
			{
				case 2: rColor = {100, 0, 0, 255};
				case 3: rColor = {0, 0, 100, 255};
				default: rColor = {70, 70, 70, 255};
			}
			
			//Values can be fiddled around with to get desired results, but these seem to be good for now
			//Starting Radius of Ring = 250
			//Ending Radius = 10
			//Width of beam = 45
			TE_SetupBeamRingPoint(vecLocation, 250.0, 10.0, gLaser1, gHalo1, 0, 0, flFlightTime, 45.0, 1.0, rColor, 50, 0);
			TE_SendToAll();
			

			//TODO - Perform a collision check so that the forward position cannot pass through walls
			GetForwardPos(vecPos, angRot, 40.0, _, vecForward);
			GetAngleVectors(angRot, vecVel, NULL_VECTOR, NULL_VECTOR);
			ScaleVector(vecVel, GRENADE_SPEED);
			
			// Create a pipe bomb.
			int iEntity = CreateEntityByName("tf_projectile_pipe");
			
			//Set necessary netprops for grenade to function
			SetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity", client);
			SetEntProp(iEntity, Prop_Send, "m_bIsLive", 1);

			//Lower friction as much as possible... this is the best we can do without an extension
			SetEntPropFloat(iEntity, Prop_Data, "m_flFriction", 0.0);
			
			//Set team values
			SetVariantInt(iTeam);
			AcceptEntityInput(iEntity, "TeamNum", -1, -1, 0);

			SetVariantInt(iTeam);
			AcceptEntityInput(iEntity, "SetTeam", -1, -1, 0);
			
			//Set netprops for damage values
			/* Commenting out for now because pipes are weird and refuse to work with impact damage
			SetEntPropFloat(iEntity, Prop_Send, "m_flDamage", 60.0); //sets damage after touching a surface... not sure if this will be necessary but setting it anyways
			SetEntPropFloat(iEntity, Prop_Send, "m_DmgRadius", 146.0); //sets blast AoE
			SetEntDataFloat(iEntity, FindSendPropInfo("CTFGrenadePipebombProjectile", "m_iDeflected"), 100.0, true); //should set impact damage (i.e damage from hitting a player)
			SDKCall(g_hGrenadeDamage, iEntity, 100.0); //Only works for damage after a bounce... may as well just use m_flDamage
			*/
			
			DispatchSpawn(iEntity);
			TeleportEntity(iEntity, vecForward, angRot, vecVel);
			
			//Hook pipe's physics update to check when it makes contact with a surface
			SDKHook(iEntity, SDKHook_VPhysicsUpdate, OnPipeUpdate);
			SDKHook(iEntity, SDKHook_Touch, OnPipeHit);
			bPipeContact[iEntity] = false;
			
			iShells -= 5;
			SetEntProp(oldSentry, Prop_Send, "m_iAmmoShells", iShells);
		}
	}
}

stock void GetForwardPos(float flOrigin[3], float vAngles[3], float flDistance, float flSideDistance = 0.0, float flBuffer[3])
{
	float flDir[3];

	GetAngleVectors(vAngles, flDir, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(flDir, flDistance);
	AddVectors(flOrigin, flDir, flBuffer);

	GetAngleVectors(vAngles, NULL_VECTOR, flDir, NULL_VECTOR);
	NegateVector(flDir);
	ScaleVector(flDir, flSideDistance);
	AddVectors(flBuffer, flDir, flBuffer);
}


//This only works when hitting a non-player/non-building entity...
public Action OnPipeUpdate(int pipe)
{
	//Only do this if the pipe has not made contact with a surface
	if (!bPipeContact[pipe])
	{
		//has this pipe made contact with a surface?
		if (GetEntProp(pipe, Prop_Send, "m_bTouched") == 1)
		{
			//Because m_bTouched is permanently set to 1 and never resets, we need to manually tell the plugin that this pipe can no longer detonate
			bPipeContact[pipe] = true;
			
			//Call our Pipe Detonate handle
			//SDKCall(g_hGrenadeDetonate, pipe);
			
			//We will be using our own explosion function for now
			SetupExplosion(pipe, 60, 146); //default pipe damage
			AcceptEntityInput(pipe, "Kill");
		}
	}
}

//Because m_bTouched does NOT update when hitting a player we need to check if we ever come into contact with a player manually... and then just do the same thing
public Action OnPipeHit(int pipe, int victim)
{	
	//Make sure the victim is a valid player
	if (IsValidClient(victim))
	{
		//at least this way we can make the damage different on impact... yay?
		SetupExplosion(pipe, 100, 146); //default pipe damage
		AcceptEntityInput(pipe, "Kill"); //delete the pipe so it doesn't detonate again
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

//Setup a custom explosion because grenade impacts are stupid
public void SetupExplosion(int pipe, int damage, int radius)
{
	char sDamage[64], sRadius[64];
	float pos[3];
	
	//Get values from the projectile
	int owner = GetEntPropEnt(pipe, Prop_Send, "m_hOwnerEntity");
	GetEntPropVector(pipe, Prop_Send, "m_vecOrigin", pos);
	IntToString(damage, sDamage, sizeof sDamage);
	IntToString(radius, sRadius, sizeof sRadius);
	
	//Setup the actual explosion
	int explode = CreateEntityByName("env_explosion");
	SetEntPropEnt(explode, Prop_Send, "m_hOwnerEntity", owner);
	//DispatchKeyValue(explode, "spawnflags", "64");
	DispatchKeyValue(explode, "iMagnitude", sDamage);
	DispatchKeyValue(explode, "iRadiusOverride", sRadius);
	TeleportEntity(explode, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchSpawn(explode);
	ActivateEntity(explode);
	AcceptEntityInput(explode, "Explode");
}

//This finds our current real sentry gun that was moved outside the map
stock int FindSentryGun(int owner)
{
	int sentry = MaxClients+1;
	while((sentry = FindEntityByClassname(sentry, "obj_sentrygun")) != -1)
	{
		if (IsValidEntity(sentry))
		{
			if(GetEntPropEnt(sentry, Prop_Send, "m_hBuilder") == owner)
				return sentry;
		}
	}
	return -1;
}


// sigh..
stock bool IsValidTarget(int attacker, int target, int mortar)
{
	if (!IsValidClient(attacker) || !IsValidClient(target)) return false;
	
	//If we don't have a line of sight to the target, don't even bother checking anything about them
	//PrintToServer("Checking LOS to target: %i", target);
	if (!IsTargetVisible(mortar, target)) return false;
	
	//Now check if the target is valid
	if (target > MaxClients)
	{
		//Check if target is an engineer building
		char classname[64];
		GetEntityClassname(target, classname, sizeof classname);
		if (StrContains(classname, "obj_") != -1)
		{
			int iTeam = GetEntProp(target, Prop_Send, "m_iTeamNum");
			if (iTeam != GetClientTeam(attacker))
				return true;
		}
	}
	else if (!IsValidClient(target)) return false;
	
	// if target is a player, make sure they are on the opposing team
	if (GetClientTeam(target) != GetClientTeam(attacker))
	{
		// if the target is on the opposing team, ignore the fact that they're disguised
		if (TF2_IsPlayerInCondition(target, TFCond_Disguised) || TF2_IsPlayerInCondition(target, TFCond_Cloaked))
		{
			return false;
		}
		return true;
	}
	
	//if none of these checks occur, just return false because then something isn't valid
	return false;
}

stock bool IsTargetVisible(int mortar, int target)
{
	bool pass = false;
	float vecStart[3], vecEnd[3];
	GetClientEyePosition(target, vecEnd);
	GetEntPropVector(mortar, Prop_Send, "m_vecOrigin", vecStart);
	vecEnd[2] -= 24.0;
	vecStart[2] += 25.0;
	int hHitEnt;
	
	Handle trace1 = TR_TraceRayFilterEx(vecStart, vecEnd, MASK_PLAYERSOLID, RayType_EndPoint, MortarTargetFilter, mortar);
	if (TR_DidHit(trace1))
	{
		hHitEnt = TR_GetEntityIndex(trace1);
		//PrintToServer("Hit Ent: %i", hHitEnt);
		if (hHitEnt == target)
			pass = true;
	}
	CloseHandle(trace1);
	return pass;
}

/*
 * Most props can be fired over, an advantage to using this over a normal sentry could be that small props will not protect enemies
 * Also sort of necessary to prevent the trace from hitting the mortar itself and always returning false
 */
public bool MortarTargetFilter(int entity, int contentsMask, any iExclude)
{
	int hOwner = SentryOwner[iExclude];
	int iTeam = GetClientTeam(hOwner);
	bool hit = false;
	char classname[64];
	GetEntityClassname(entity, classname, sizeof classname);
	
	//Return hit results on enemy players
	if (IsValidClient(entity))
	{
		//PrintToServer("Hit Player");
		if (GetClientTeam(entity) != iTeam)
			hit = true;
	}
	
	//Return hit results on spawn doors and the world itself
	else if (entity == 0 || StrEqual(classname, "func_door"))
		hit = true;
		
	//return our hit result
	return hit;
}

stock void DestroySentry(int mortar)
{
	float vecPos[3];
	GetEntPropVector(mortar, Prop_Send, "m_vecOrigin", vecPos);
	int owner = SentryOwner[mortar];
	int oldSentry = FindSentryGun(owner);
	if (IsValidEntity(oldSentry))
		TeleportEntity(oldSentry, vecPos, NULL_VECTOR, NULL_VECTOR);
	PlayerSentry[owner] = 0;
	SentryHealth[mortar] = 0;
	AcceptEntityInput(SentryBase[mortar], "Kill");
	AcceptEntityInput(SentryTurret[mortar], "Kill");
	SentryBase[mortar] = 0;
	SentryTurret[mortar] = 0;
	
	AcceptEntityInput(mortar, "Kill");
}

stock bool IsValidClient(int iClient)
{
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
	{
		return false;
	}
	if (IsClientSourceTV(iClient) || IsClientReplay(iClient))
	{
		return false;
	}
	return true;
}

stock bool HasValidSentry(int client)
{
	if (IsValidEntity(PlayerSentry[client]) && PlayerSentry[client] > MaxClients)
		return true;
	return false;
}

stock bool IsWeaponSlotActive(int iClient, int iSlot)
{
    return GetPlayerWeaponSlot(iClient, iSlot) == GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
}

stock int FindSentryLookTarget(int client)
{
	int entity = GetClientAimTarget(client, false);
	if (entity > MaxClients)
		return entity;
		
	return -1;
}
