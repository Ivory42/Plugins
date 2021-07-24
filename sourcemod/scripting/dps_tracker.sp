#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public Plugin myinfo =
{
	name = "[TF2] DPS Tracker",
	author = "IvoryPal",
	version = "1.0",
}

ConVar g_enabled;
ConVar g_timeFrame;

float curDamage[MAXPLAYERS+1];
float initialDamageTime[MAXPLAYERS+1];

public void OnPluginStart()
{
	g_enabled = CreateConVar("tf_track_dps", "0", "Enable tracking average DPS | 1 = between kills, 2 = set timeframe");
	g_timeFrame = CreateConVar("tf_dps_timeframe", "1.0", "If tf_track_dps is set to 2, this will be the time frame used for DPS checks");
	HookEvent("player_death", Event_PlayerDeath);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			SDKHook(i, SDKHook_OnTakeDamageAlive, Event_TakeDamage);
		}
	}
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_OnTakeDamageAlive, Event_TakeDamage);
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dbroad)
{
	if (GetConVarInt(g_enabled) == 1)
	{
		int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

		if (initialDamageTime[attacker])
		{
			//Get time since last initial damage event
			float curTime = GetEngineTime() - initialDamageTime[attacker];
			float dps = curDamage[attacker] / curTime;

			PrintToChat(attacker, "[DPS] Average DPS since last kill: %.1f", dps);
			initialDamageTime[attacker] = 0.0;
			curDamage[attacker] = 0.0;
		}
	}
}

public Action Event_TakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	int dpsValue = GetConVarInt(g_enabled);
	if (dpsValue)
	{
		if (!initialDamageTime[attacker])
		{
			initialDamageTime[attacker] = GetEngineTime();
			curDamage[attacker] = 0.0;
		}
		curDamage[attacker] += damage;
	}
}

public Action OnPlayerRunCmd(int client)
{
	int dpsValue = GetConVarInt(g_enabled);
	switch (dpsValue)
	{
		case 2:
		{
			float timeSinceLast = GetEngineTime() - initialDamageTime[client];
			if (timeSinceLast >= GetConVarFloat(g_timeFrame) && curDamage[client])
			{
				float dps = curDamage[client] / GetConVarFloat(g_timeFrame);

				PrintToChat(client, "[DPS] Average DPS in the last %.1f seconds: %.1f", GetConVarFloat(g_timeFrame), dps);
				initialDamageTime[client] = 0.0;
				curDamage[client] = 0.0;
			}
		}
	}
}
