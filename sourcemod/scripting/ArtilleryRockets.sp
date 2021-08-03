#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>

public Plugin MyInfo =
{
	name = "[TF2] Artillery Rocket Launcher",
	author = "IvoryPal",
	description = "Rocket launcher that fires volleys of rockets.",
	version = "1.0"
}

ConVar g_arcDelay;
ConVar g_arcGrav;
bool arcRockets[MAXPLAYERS+1];
bool weaponArc[2049];
bool shouldArc[2049];
float arcDelay[2049];

public void OnPluginStart()
{
	RegConsoleCommand("sm_arcrocket", CmdToggleArc);
	
	HookEvent("post_inventory_application", Event_PlayerResupply);
	
	g_arcDelay = CreateConVar("tf_rocket_arc_delay", "1.0", "Delay in seconds before a rocket is affected by gravity");
	g_arcGrav = CreateConVar("tf_rocket_arc_gravity", "2.75", "Gravity to apply to arcing rockets");
}

public void OnClientPutInServer(int client)
{
	arcRockets[client] = false;
}

public Action CmdToggleArc(int client, int args)
{
	arcRockets[client] = !arcRockets[client];
	PrintToChat(client, "Artillery Launcher %s", arcRockets[client] ? "Enabled. Resupply to obtain it." : "Removed.");
}

public Action Event_PlayerResupply(Handle event, const char[] name, bool dbroad)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (0 < client <= MaxClients && IsClientInGame(client))
	{
		int launcher = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
		if (IsValidEntity(launcher) && launcher > MaxClients && arcRockets[client])
		{
			weaponArc[launcher] = true;
			TF2Attrib_SetByName(launcher, "clip size bonus", 5.0);
		}
	}
	return Plugin_Continue;
}

public void OnEntityDestroyed(int ent)
{
	if (IsValidEntity(ent) && ent > MaxClients && weaponArc[ent])
	{
		weaponArc[ent] = false;
	}
}

public void OnEntityCreated(int ent, const char[] classname)
{
	if (StrEqual(classname, "tf_projectile_rocket") || StrEqual(classname, "tf_projectile_energy_rocket"))
	{
		SDKHook(ent, SDKHook_SpawnPost, OnProjSpawn);
	}
}

public void OnGameFrame()
{
	int ent = MaxClients + 1;
	while ((ent = FindEntityByClassname(ent, "tf_projectile_rocket")) != -1 || (ent = FindEntityByClassname(ent, "tf_projectile_energy_rocket")) != -1)
	{
		if (shouldArc[ent] && arcDelay[proj] <= GetEngineTime())
		{
			ArcRocket(ent);
		}
	}
}

public Action OnProjSpawn(int proj)
{
	int owner = GetEntPropEnt(proj, Prop_Send, "m_hOwnerEntity");
	int launcher = GetEntPropEnt(proj, Prop_Send, "m_hLauncher");
	if (IsClientInGame(owner) && weaponArc[launcher])
	{
		shouldArc[proj] = true;
		arcDelay[proj] = GetEngineTime() + GetConVarFloat(g_arcDelay);
	}
	else
		shouldArc[proj] = false;
}

public void ArcRocket(int rocket)
{
	float vel[3], rot[3];
	float grav = GetConVarFloat(g_arcGrav);
	
	GetEntPropVector(rocket, Prop_Data, "m_vecVelocity", vel);
	GetEntPropVector(rocket, Prop_Send, "m_angRotation", rot);
	
	vel[2] -= Pow(grav, 2.0);
	
	GetVectorAngles(vel, rot);
	ClampAngle(rot);
	
	SetEntPropVector(rocket, Prop_Data, "m_vecVelocity", vel);
	SetEntPropVector(rocket, Prop_Send, "m_angRotation", rot);
	TeleportEntity(rocket, NULL_VECTOR, rot, vel);
}

stock void ClampAngle(float fAngles[3])
{
	while(fAngles[0] > 89.0)  fAngles[0]-=360.0;
	while(fAngles[0] < -89.0) fAngles[0]+=360.0;
	while(fAngles[1] > 180.0) fAngles[1]-=360.0;
	while(fAngles[1] <-180.0) fAngles[1]+=360.0;
}
