#pragma semicolon 1
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <sdktools>
#include <tf2attributes>

#define FAR_FUTURE 99999999999.0

bool bGrenadePrimed[2048];
bool bPipeContact[2048];
bool bEMP[2048];
bool bActive[2048];
float flFuseTime[2048];
int hPrimeParticle[2048];

Handle g_disableTime;
Handle g_pipeDamage;
Handle g_fuseTime;

bool bGrenadeLauncher[MAXPLAYERS+1];

int hActiveGrenade[MAXPLAYERS+1];

public Plugin MyInfo = {
	name 			= 	"Controlled Grenades",
	author 			=	"Ivory",
	description		= 	"Allows demos to hold the fuse on pipes and detonate manually",
	version 		= 	"1.0"
};


Handle g_hGrenadeDetonate;
Handle g_hGrenadeDamage;
public void OnPluginStart()
{
	//Event hooks
	HookEvent("player_builtobject", EventObjectBuilt);
	
	//Set ConVars
	
	g_disableTime = CreateConVar("grenade_building_disable_time", "2.0", "How long an EMP grenade will disable buildings for");
	g_pipeDamage = CreateConVar("grenade_damage", "75.0", "How much damage controlled grenades deal");
	g_fuseTime = CreateConVar("grenade_fuse_time", "0.35", "Grenade fuse timer after touching a surface and not primed");
	
	//Toggle for grenades
	RegConsoleCmd("sm_grenade", CMDToggleGrenade);
	
	//Setup our SDKCalls
	GameData data = new GameData("GrenadeData");
	if (!data)
		SetFailState("Failed to find GrenadeData.txt gamedata! Unable to continue.");

	//Sets up SDKCall for detonating a grenade on demand
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(data, SDKConf_Virtual, "GrenadeDetonate");
	g_hGrenadeDetonate = EndPrepSDKCall();
	
	//Allows us to set damage of a grenade whenever we want
	//Note: This does nothing for direct hits
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(data, SDKConf_Virtual, "SetDamage");
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_ByValue);
	g_hGrenadeDamage = EndPrepSDKCall();
	
	delete data;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public Action EventObjectBuilt(Handle hEvent, const char[] name, bool dBroad)
{
	int building = GetEventInt(hEvent, "index");
	
	//Hook when this building takes damage so we can EMP it if needed
	SDKHook(building, SDKHook_OnTakeDamage, OnBuildingDamaged);
}

public Action OnBuildingDamaged(int building, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsValidEntity(building) || !HasEntProp(building, Prop_send, "m_iTeamNum") return Plugin_Conitnue;
	if (!IsValidClient(attacker)) return Plugin_Continue;
	
	//OnTakeDamage fires for explosions even if the attacker and victim are on the same team, so let's make sure we can't EMP friendly buildings
	
	int iTeam = GetEntProp(building, Prop_Send, "m_iTeamNum");
	if (iTeam != GetClientTeam(attacker))
	{		
		//Is the inflictor a grenade that can EMP?
		if (bEMP[inflictor])
		{
			//Disable the building
			SetEntProp(building, Prop_Send, "m_bDisabled", 1);
			//PrintToChatAll("Building disabled");
			
			//We want to scale the stun duration based on distance between the grenade and the building
			//This way a demo can't just mindlessly spam and keep a nest completely disabled
			float gPos[3], bPos[3];
			GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", gPos);	//Grenade position
			GetEntPropVector(building, Prop_Send, "m_vecOrigin", bPos);		//Building position
		
			//If the pipe is 35hu or further from the building, begin scaling the stun duration
			//This will be clamped so that the duration does not exceed the convar value
			float flMod = 35.0 / GetVectorDistance(bPos, gPos);
		
			//Apply the modifier to stun duration
			float flDuration = flMod * GetConVarFloat(g_disableTime);
		
			//Now clamp the duration (minimum of 0.2 seconds, capped at convar value)
			flDuration = ClampFloat(flDuration, 0.2, GetConVarFloat(g_disableTime));
			
			//Store our building's entity reference so we can check it later
			int buildRef = EntIndexToEntRef(building);
			CreateTimer(flDuration, TimerDisableBuilding, buildRef, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action TimerDisableBuilding(Handle tTimer, int ref)
{
	int building = EntRefToEntIndex(ref);
	if (IsValidEntity(building) && building > MaxClients)
	{
		SetEntProp(building, Prop_Send, "m_bDisabled", 0);
	}
}

public Action CMDToggleGrenade(int client, int args)
{
	bGrenadeLauncher[client] = !bGrenadeLauncher[client];
	PrintToChat(client, "EMP Grenades %s.", bGrenadeLauncher[client] ? "enabled" : "disabled");
}

public void OnClientPutInServer(int client)
{
	bGrenadeLauncher[client] = false;
}

public void DetonateGrenade(int pipe, bool emp)
{
	float flDamage = GetConVarFloat(g_pipeDamage);
	//reset variables
	bPipeContact[pipe] = false;
	flFuseTime[pipe] = FAR_FUTURE;
	
	//If our grenade is detonated while primed, give the explosion a different look and disable buildings hit by it
	if (emp)
	{
		//PrintToChatAll("emp grenade");
		float gPos[3];
		GetEntPropVector(pipe, Prop_Send, "m_vecOrigin", gPos);
		int iTeam = GetEntProp(pipe, Prop_Send, "m_iTeamNum");
		switch (iTeam)
		{
			case 2: CreateParticle(_, "drg_cow_explosioncore_charged", _, gPos);
			default: CreateParticle(_, "drg_cow_explosioncore_charged_blue", _, gPos);
		}
		bEMP[pipe] = true;
		flDamage *= 0.5;
	}
	
	//Set damage and then detonate the pipe
	SDKCall(g_hGrenadeDamage, pipe, flDamage);
	SDKCall(g_hGrenadeDetonate, pipe);
}

public Action OnPipeUpdate(int pipe)
{
	if (!bPipeContact[pipe])
	{
		//has this pipe made contact with a surface?
		if (GetEntProp(pipe, Prop_Send, "m_bTouched") && !bGrenadePrimed[pipe])
		{
			//Because m_bTouched is set and then forgotten, we need to tell the plugin to only do this once after a short delay
			//Otherwise after touching a surface, this will be called every physics update for the pipe
			bPipeContact[pipe] = true;
			flFuseTime[pipe] = GetEngineTime() + GetConVarFloat(g_fuseTime);
		}
	}
	if (flFuseTime[pipe] <= GetEngineTime())
	{
		DetonateGrenade(pipe, false);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_projectile_pipe"))
		SDKHook(entity, SDKHook_SpawnPost, OnPipeSpawn);
}

public Action OnPipeSpawn(int pipe)
{
	int owner = GetEntPropEnt(pipe, Prop_Send, "m_hOwnerEntity");
	if (IsValidClient(owner) && bGrenadeLauncher[owner])
	{
		//Disable pipe's think to prevent it from automatically detonating
		SetEntProp(pipe, Prop_Data, "m_nNextThinkTick", -1);
		
		bGrenadePrimed[pipe] = false;
		bEMP[pipe] = false;
		
		//if we already have an active grenade, make sure it is no longer primed and behaves normally
		if (IsValidEntity(hActiveGrenade[owner]))
		{
			bGrenadePrimed[hActiveGrenade[owner]] = false;
			
			//disable fuse timer if we have no made contact with a surface
			if (!bPipeContact[hActiveGrenade[owner]])
				flFuseTime[hActiveGrenade[owner]] = FAR_FUTURE;
		}
		
		//Set most recent pipe as active pipe
		hActiveGrenade[owner] = pipe;
		
		//Hook physics update of pipe and touch event
		SDKHook(pipe, SDKHook_VPhysicsUpdate, OnPipeUpdate);
		SDKHook(pipe, SDKHook_Touch, OnPipeTouch);
		flFuseTime[pipe] = FAR_FUTURE;
	}
}

//Pipe touch event fires whenever it hits an entity that is not the world... but also sometimes when it hits the world, vphysics touch results are very unreliable when checking against the world
//Luckily it is almost perfectly reliable when hitting an entity that is NOT the world
//We want to disable the explosion upon hitting a player/building, so we tell this function to never finish
public Action OnPipeTouch(int pipe, int victim)
{	
	//Never detonate on touch and do not count a touch as hitting a surface
	//We don't want it to enable the fuse timer because hitting a player's collision hull will not cause a bounce, but will still trigger this touch event
	//So the pipe should travel right through and not be interrupted
	
	//However, hitting a player's complex collision (model's defined collision mesh) WILL cause a bounce
	//Unfortunately, there is no way to distinguish between the two, so we will just have it be completely ignored
	//The exact same applies to buildings
	
	return Plugin_Handled;
}

public Action OnPlayerResupply(Handle rEvent, const char[] name, bool dBroad)
{
	int client = GetClientOfUserId(GetEventInt(rEvent, "userid"));
	if (IsValidClient(client) && TF2_GetPlayerClass(client) == TFClass_DemoMan && bGrenadeLauncher[client])
	{
		int pWeapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
		int pIndex = GetEntProp(pWeapon, Prop_Send, "m_iItemDefinitionIndex");
		switch (pIndex)
		{
			case 308, 996, 1101: return;
			default:
			{
				TF2Attrib_SetByDefIndex(pWeapon, 1, 0.8);
			}
		}
	}
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool& result)
{
	//
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsValidClient(client))
	{
		if (IsPlayerAlive(client) && TF2_GetPlayerClass(client) == TFClass_DemoMan)
		{
			int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if (!IsValidEntity(iActiveWeapon)) return;
			
			char sWeaponName[64];
			GetEntityClassname(iActiveWeapon, sWeaponName, sizeof sWeaponName);
			
			if (StrEqual(sWeaponName, "tf_weapon_grenadelauncher") && IsValidPipe(hActiveGrenade[client]))
			{
				bool primed = (buttons & IN_ATTACK2) != 0;
				int hudType = 0;
				
				//We are manually priming the grenade 
				if (primed)
				{
					SetHudTextParams(0.6, -1.0, 0.01, 255, 25, 50, 255);
					hudType = 1;
				}

				//Grenade is not primed
				else
				{	
					//about to detonate
					if (bPipeContact[hActiveGrenade[client]])
					{
						SetHudTextParams(0.6, -1.0, 0.01, 255, 255, 20, 255);
						hudType = 2;
					}
					else
					{
						SetHudTextParams(0.6, -1.0, 0.01, 255, 255, 255, 255);
						hudType = 0;
					}
				}				
				
				char sGrenade[64];
				Format(sGrenade, sizeof sGrenade, "Grenade %s", hudType == 0 ? "Idle" : hudType == 1 ? "Primed!" : "LIVE");
				ShowHudText(client, -1, "%s", sGrenade);
				
				//If we have an active grenade, allow us to delay the detonation by holding alt-fire
				if (primed && flFuseTime[hActiveGrenade[client]] == FAR_FUTURE)
					bGrenadePrimed[hActiveGrenade[client]] = true;
					
				//If we are no longer holding alt-fire, set our grenade to detonate
				else if (bGrenadePrimed[hActiveGrenade[client]])
				{
					bGrenadePrimed[hActiveGrenade[client]] = false;
					bPipeContact[hActiveGrenade[client]] = true;
					
					//Store our pipe as a reference
					int grenadeRef = EntIndexToEntRef(hActiveGrenade[client]);
					
					//We use a timer here because the physics update will not be called on the pipe if it is not moving
					//However, we still want the pipe to detonate once we release alt-fire, even if it is not moving
					CreateTimer(0.05, TimerDetonatePipe, grenadeRef, TIMER_FLAG_NO_MAPCHANGE);
				}
			}
			else if (bGrenadePrimed[hActiveGrenade[client]])
			{
				bGrenadePrimed[hActiveGrenade[client]] = false;
				flFuseTime[hActiveGrenade[client]] = GetEngineTime() + 0.05;
			}
		}
	}
}

public Action TimerDetonatePipe(Handle Timer, int ref)
{
	int pipe = EntRefToEntIndex(ref);
	if (IsValidPipe(pipe))
	{
		DetonateGrenade(pipe, true);
	}
}

public void OnEntityDestroyed(int entity)
{
	if (IsValidEntity(entity) && entity > MaxClients)
	{
		bGrenadePrimed[entity] = false;
		flFuseTime[entity] = FAR_FUTURE;
		
		//Check if the entity destroyed is the active grenade of a client
		if (HasEntProp(entity, Prop_Send, "m_hOwnerEntity"))
		{
			int owner = GetEntProp(entity, Prop_Send, "m_hOwnerEntity");
			
			//if not a client, or client does not have this enabled, then ignore
			if (!IsValidClient(owner) || !bGrenadeLauncher[owner]) return;
			
			RequestFrame(DelayPipeDestroyed, entity);
			
			//Reset the client's active grenade
			if (hActiveGrenade[owner] == entity)
				hActiveGrenade[owner] = -1;
		}
	}
}

public void DelayPipeDestroyed(int pipe)
{
	bEMP[pipe] = false;
}

stock float ClampFloat(float value, float min, float max)
{
	return ((value < min) ? min : ((value > max) ? max : value));
}

stock int CreateParticle(int iEntity = 0, char[] sParticle, bool bAttach = false, float pos[3]={0.0, 0.0, 0.0})
{
	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEntity(iParticle))
	{
		if (iEntity > 0)
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", pos);

		TeleportEntity(iParticle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(iParticle, "effect_name", sParticle);

		if (bAttach)
		{
			SetVariantString("!activator");
			AcceptEntityInput(iParticle, "SetParent", iEntity, iParticle, 0);
		}

		DispatchSpawn(iParticle);
		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "Start");
	}
	return iParticle;
}

stock bool IsValidClient(int client)
{
    if (!( 1 <= client <= MaxClients ) || !IsClientInGame(client))
        return false;

    return true;
}

stock bool IsValidPipe(int pipe)
{
	if (IsValidEntity(pipe) && pipe > MaxClients)
	{
		char sName[64];
		GetEntityClassname(pipe, sName, sizeof sName);
		if (StrEqual(sName, "tf_projectile_pipe"))
			return true;
	}
	
	return false;
}

stock bool IsPlayerOrBuilding(int entity)
{
	bool result = false;
	char classname2[64];
	GetEntityClassname(entity, classname2, sizeof classname2);
	
	//Check if classname is a building
	if (StrContains(classname2, "obj_") != -1)
		result = true;
		
	//If the entity is not a building, check if it is a valid client
	else if (IsValidClient(entity))
		result = true;
		
	return result;
}
