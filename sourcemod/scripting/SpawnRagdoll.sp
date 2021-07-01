#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <tf2>

bool bRagdoll[MAXPLAYERS+1];
int ragdoll[MAXPLAYERS+1];
int LastHealth[MAXPLAYERS+1];

public Plugin myinfo =
{
    name    = "SpawnRagoll",
    author  = "IvoryPal",
    description = "Allows players to ragdoll their characters",
    version = "1.0"
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_ragdoll", CMDRag);
}

public Action CMDRag(int client, int args)
{
	if (bRagdoll[client])
	{
		float pos[3];
		GetEntPropVector(ragdoll[client], Prop_Data, "m_vecOrigin", pos);
		if (ragdoll[client] > MaxClients)
		{
			AcceptEntityInput(ragdoll[client], "Kill");
		}
		TeleportEntity(client, pos, NULL_VECTOR, NULL_VECTOR);
		SetClientViewEntity(client, client);
		bRagdoll[client] = false;
		SetEntityRenderMode(client, RENDER_NORMAL);
		LastHealth[client] = GetClientHealth(client);
		TF2_RegeneratePlayer(client);
		RequestFrame(ResetHealth, client);
		SetWearables(client, false);
	}
	else
	{
		int team = GetClientTeam(client);
		int class = view_as<int>(TF2_GetPlayerClass(client));
		float pos[3], ang[3], vel[3];
		GetClientAbsOrigin(client, pos);
		GetClientAbsAngles(client, ang);
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
		ragdoll[client] = CreateEntityByName("tf_ragdoll");

		TeleportEntity(ragdoll[client], pos, ang, vel);

		SetEntProp(ragdoll[client], Prop_Send, "m_iPlayerIndex", client);
		SetEntProp(ragdoll[client], Prop_Send, "m_iTeam", team);
		SetEntProp(ragdoll[client], Prop_Send, "m_iClass", class);
		SetEntProp(ragdoll[client], Prop_Send, "m_nForceBone", 1);
		SetEntProp(ragdoll[client], Prop_Send, "m_bOnGround", 1);

		SetEntPropFloat(ragdoll[client], Prop_Send, "m_flHeadScale", 1.0);
		SetEntPropFloat(ragdoll[client], Prop_Send, "m_flTorsoScale", 1.0);
		SetEntPropFloat(ragdoll[client], Prop_Send, "m_flHandScale", 1.0);
		
		bRagdoll[client] = true;
		
		DispatchSpawn(ragdoll[client]);
		ActivateEntity(ragdoll[client]);
		SetEntPropEnt(client, Prop_Send, "m_hRagdoll", ragdoll[client]);
		SetClientViewEntity(client, ragdoll[client]);
		SetEntityRenderMode(client, RENDER_NONE);
		SetWearables(client, true);
	}
}

stock void SetWearables(int client, bool disable)
{
	if (disable)
		TF2_RemoveAllWeapons(client);
	int entity = MaxClients + 1;
	while ((entity = FindEntityByClassname(entity, "tf_wearable")) != -1)
	{
		if (GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
		{
			if (disable)
			{
				SetEntityRenderMode(entity, RENDER_NONE);
			}
			else
			{
				SetEntityRenderMode(entity, RENDER_NORMAL);
			}
		}
	}
}

public void ResetHealth(int client)
{
	SetEntityHealth(client, LastHealth[client]);
}
