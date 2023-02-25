#include <sdkhooks>
#include <sdktools>

float HealthMult[MAXPLAYERS+1] = {1.0, ...};
float DamageMult[MAXPLAYERS+1] = {1.0, ...};
float OldMult[MAXPLAYERS+1];

int MaxHealth[MAXPLAYERS+1];
ConVar Enabled;

bool IsEnabled = false;

/*
 * This plugin simply just increases player health on death by +10%
 * Kills increase health by +3% and damage by +2%
*/

public void OnPluginStart()
{
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("teamplay_round_start", OnRoundStart);
	Enabled = CreateConVar("tf_increase_health_on_death", "0", "Increase player health on death", _, true, 0.0, true, 1.0);
	IsEnabled = Enabled.BoolValue;

	HookConVarChange(Enabled, OnEnabledChanged);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPostAdminCheck(i);
	}
}

void OnRoundStart(Event event, const char[] name, bool dBroad)
{
	// Reset values on round start - Clients do not need to be in-game for this
	for (int i = 1; i <= MaxClients; i++)
	{
		HealthMult[i] = 1.0;
		DamageMult[i] = 1.0;

		// Except for this part :)
		if (IsClientInGame(i))
			SetEntityHealth(i, MaxHealth[i]);
	}
}

void OnEnabledChanged(ConVar convar, const char[] old, const char[] newVal)
{
	IsEnabled = view_as<bool>(StringToInt(newVal));
}

public void OnClientPostAdminCheck(int client)
{
	HealthMult[client] = 1.0;
	DamageMult[client] = 1.0;
	SDKHook(client, SDKHook_GetMaxHealth, OnSetMaxHealth);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}

void OnPlayerDeath(Event event, const char[] name, bool dBroad)
{
	if (IsEnabled)
	{
		int victim = GetClientOfUserId(event.GetInt("userid"));
		int attacker = GetClientOfUserId(event.GetInt("attacker"));

		// Make sure the player is actually killed by another player
		if (attacker > 0 && attacker <= MaxClients && victim != attacker)
		{
			HealthMult[victim] += 0.1;
			DamageMult[victim] -= 0.03;

			OldMult[attacker] = HealthMult[attacker];
			HealthMult[attacker] += 0.03;
			DamageMult[attacker] += 0.02;

			// Increase the attacker's health to match the increase
			RequestFrame(UpdateHealth, attacker);
		}
	}
}

void UpdateHealth(int client)
{
	// Find our actual difference in health then increase accordingly
	int health = GetEntProp(client, Prop_Data, "m_iHealth");
	float difference = HealthMult[client] - OldMult[client];

	int absMax = RoundFloat(MaxHealth[client] * HealthMult[client]);
	int newHealth = health + RoundFloat(MaxHealth[client] * difference);

	// Do nothing if already overhealed
	if (health > absMax)
		return;

	// Don't allow this health to overheal.. shouldn't ever happen but you never know
	if (newHealth > absMax)
		health = absMax;
	
	SetEntityHealth(client, newHealth);
}

Action OnSetMaxHealth(int client, int& health)
{
	if (IsEnabled)
	{
		MaxHealth[client] = health;
		health = RoundFloat(health * HealthMult[client]);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

Action OnTakeDamage(int client, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if (IsEnabled)
	{
		if (attacker > 0 && attacker <= MaxClients)
		{
			damage *= DamageMult[attacker];
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}
