#pragma semicolon 1
#include <tf2_stocks>
#include <tf2attributes>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"
#define SOUND_STICKYATTACH "weapons/custom/sticky/attach.mp3"
#define SOUND_STICKYDETONATE "weapons/custom/sticky/detonate.mp3"
#define SOUND_STICKYDETONATEPRE "weapons/custom/sticky/detonate_pre.mp3"

public Plugin myinfo = {
    name = "[TF2] Sticky Grenades",
    author = "IvoryPal",
    description = "Grenade Launcher grenades that stick to enemies",
    version = PLUGIN_VERSION,
    url = ""
};

float StickyFuseTime = 1.5;

enum struct Grenade
{
	int stucktarget;
	int owner;
	bool stuck;
	bool armed;
	bool detonate;
	float damage;
	float fuse;

	void PrimeGrenade(int target, float delay, bool stick)
	{
		this.stuck = stick;
		this.stucktarget = target;
		this.fuse = GetGameTime() + delay;
		this.armed = true;
		this.detonate = true;
	}
	void Detonate(float pos[3], int inflictor)
	{
		char dmg[8], rad[8];
		int soundtarget = inflictor;
		this.damage = GetEntPropFloat(inflictor, Prop_Send, "m_flDamage");
		FloatToString(this.damage, dmg, sizeof dmg);
		FloatToString(GetEntPropFloat(inflictor, Prop_Send, "m_DmgRadius"), rad, sizeof rad);
		switch (GetClientTeam(this.owner))
		{
			case 2: CreateParticle(_, "drg_cow_explosioncore_charged", _, pos, 3.0);
			case 3: CreateParticle(_, "drg_cow_explosioncore_charged_blue", _, pos, 3.0);
			default: CreateParticle(_, "drg_cow_explosioncore_charged_blue", _, pos, 3.0);
		}
		if (this.stuck)
			soundtarget = this.stucktarget;
		EmitSoundToAll(SOUND_STICKYDETONATE, soundtarget, SNDCHAN_AUTO, 100);

		int explosion = CreateEntityByName("env_explosion");
		SetEntPropEnt(explosion, Prop_Data, "m_hInflictor", inflictor);
		SetEntPropEnt(explosion, Prop_Send, "m_hOwnerEntity", this.owner);
		DispatchKeyValue(explosion, "spawnflags", "68");
		DispatchKeyValue(explosion, "iMagnitude", dmg);
		DispatchKeyValue(explosion, "iRadiusOverride", rad);
		TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(explosion);
		ActivateEntity(explosion);
		AcceptEntityInput(explosion, "Explode");
		this.Clear();
	}
	void Clear()
	{
		this.armed = false;
		this.stuck = false;
		this.stucktarget = INVALID_ENT_REFERENCE;
	}
}

Grenade Sticky[2049];
bool HasStickyGrenades[MAXPLAYERS+1];

float GrenadePos[2049][3];
float GrenadePosOld[2049][3];

ConVar g_friendlyfire;
// Plugin start

public void OnPluginStart()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;

		OnClientPostAdminCheck(i);
	}
	RegConsoleCmd("sm_stickies", CmdToggleStickies);
	g_friendlyfire = FindConVar("mp_friendlyfire");
}

Action CmdToggleStickies(int client, int args)
{
	HasStickyGrenades[client] = !HasStickyGrenades[client];
	ReplyToCommand(client, "[SM] Sticky grenades %s!", HasStickyGrenades[client] ? "enabled" : "disabled");
}

public void OnMapStart()
{
	PrecacheSound(SOUND_STICKYATTACH);
	PrecacheSound(SOUND_STICKYDETONATE);
	PrecacheSound(SOUND_STICKYDETONATEPRE);
}

public void OnEntityDestroyed(int ent)
{
	if (IsValidEntity(ent) && ent > MaxClients)
	{
		Sticky[ent].Clear();
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_projectile_pipe"))
	{
		SDKHook(entity, SDKHook_SpawnPost, PipeSpawn);
	}
}

public Action PipeSpawn(int pipe)
{
	int owner = GetEntPropEnt(pipe, Prop_Data, "m_hOwnerEntity");
	if (IsValidClient(owner))
	{
		if (HasStickyGrenades[owner])
		{
			SDKHook(pipe, SDKHook_Touch, PipeTouch);
			SetEntPropFloat(pipe, Prop_Send, "m_flModelScale", 0.1);
			switch (GetClientTeam(owner))
			{
				case 2: CreateParticle(pipe, "drg_cow_rockettrail_fire", true);
				case 3: CreateParticle(pipe, "drg_cow_rockettrail_fire_blue", true);
			}
			SDKHook(pipe, SDKHook_VPhysicsUpdate, OnPipeUpdate);
			GetEntPropVector(pipe, Prop_Send, "m_vecOrigin", GrenadePos[pipe]);
			SetEntProp(pipe, Prop_Data, "m_nNextThinkTick", -1);
			Sticky[pipe].owner = owner;
		}
	}
}

public Action OnPipeUpdate(int pipe)
{
	if (!IsValidEntity(pipe) || pipe <= 0) return Plugin_Continue;
	static float armCheckTime[2049];
	if (!Sticky[pipe].armed && GetEntProp(pipe, Prop_Send, "m_bTouched"))
	{
		if (armCheckTime[pipe] <= GetGameTime())
		{
			armCheckTime[pipe] = GetGameTime() + 0.1;
			GrenadePosOld[pipe] = GrenadePos[pipe];
			GetEntPropVector(pipe, Prop_Send, "m_vecOrigin", GrenadePos[pipe]);
			if (GetVectorDistance(GrenadePos[pipe], GrenadePosOld[pipe]) <= 25.0)
				Sticky[pipe].PrimeGrenade(0, StickyFuseTime, false);
		}
	}
	return Plugin_Continue;
}

public void OnGameFrame()
{
	int pipe = MaxClients + 1;
	while ((pipe = FindEntityByClassname(pipe, "tf_projectile_pipe")) != -1)
	{
		if (IsValidClient(Sticky[pipe].stucktarget) && !IsPlayerAlive(Sticky[pipe].stucktarget))
		{
			Sticky[pipe].stuck = false;
			Sticky[pipe].stucktarget = INVALID_ENT_REFERENCE;
			AcceptEntityInput(pipe, "ClearParent");
			SetEntityMoveType(pipe, MOVETYPE_VPHYSICS);
		}
		if (Sticky[pipe].armed)
		{
			static bool chargeSound[2049];
			if (Sticky[pipe].fuse - GetGameTime() < 1.0 && !chargeSound[pipe])
			{
				EmitSoundToAll(SOUND_STICKYDETONATEPRE, pipe, SNDCHAN_AUTO, 75);
				chargeSound[pipe] = true;
			}
			if (Sticky[pipe].fuse <= GetGameTime() && Sticky[pipe].detonate)
			{
				Sticky[pipe].detonate = false;
				float pos[3];
				int target = Sticky[pipe].stucktarget;
				if (IsValidClient(target))
					GetClientAbsOrigin(target, pos);
				else
					GetEntPropVector(pipe, Prop_Data, "m_vecOrigin", pos);
				Sticky[pipe].Detonate(pos, pipe);
				AcceptEntityInput(pipe, "KillHierarchy");
				chargeSound[pipe] = false;
			}
		}
	}
}

public Action PipeTouch(int entity, int victim)
{
	int owner = Sticky[entity].owner;
	if (IsValidClient(owner) && IsValidClient(victim))
	{
		int ownerteam = GetClientTeam(owner);
		if (CanStickToTarget(owner, victim, ownerteam))
		{
			if (!Sticky[entity].stuck)
			{
				SetVariantString("!activator");
				AcceptEntityInput(entity, "SetParent", victim, entity, 0);
				SetEntityMoveType(entity, MOVETYPE_NOCLIP);
				EmitSoundToAll(SOUND_STICKYATTACH, victim, SNDCHAN_AUTO, 80);
				Sticky[entity].PrimeGrenade(victim, StickyFuseTime, true);
			}
			return Plugin_Handled;
		}
	}
	return Plugin_Handled;
}

bool CanStickToTarget(int owner, int victim, int team)
{
	bool result;
	if (g_friendlyfire.BoolValue)
	{
		if (victim != owner) result = true;
	}
	else if (GetClientTeam(victim) != team)
		result = true;

	return result;
}
// Sdkhooks

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (IsValidClient(client))
	{
		bool crit;
		if (HasEntProp(inflictor, Prop_Send, "m_bCritical") && GetEntProp(inflictor, Prop_Send, "m_bCritical"))
		{
			crit = true;
			damagetype |= DMG_CRIT;
		}
		if (Sticky[inflictor].stuck)
		{
			if (client != Sticky[inflictor].stucktarget && !crit)
				damage = MiniCritDamage(attacker, client, damage, Sticky[inflictor].damage);
			else
				damage *= 1.67;
		}
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public float MiniCritDamage(int attacker, int victim, float damage, float basedamage)
{
	if (damage < basedamage)
		damage = basedamage; //No damage falloff
	damage *= 1.35;
	CreateParticle(victim, "minicrit_text", true, _, 5.0);
	char sCritSound[64];
	Format(sCritSound, sizeof sCritSound, "player/crit_hit_mini%i.wav", GetRandomInt(3, 5));
	PrecacheSound(sCritSound);
	PrecacheSound("player/crit_received2.mp3");
	EmitSoundToAll(sCritSound, victim, SNDCHAN_AUTO, 75);
	EmitSoundToClient(attacker, sCritSound);
	EmitSoundToClient(victim, "player/crit_received2.mp3");
	return damage;
}

stock void CreateParticle(int entity = 0, char[] sParticle, bool bAttach = false, float pos[3] = {0.0, 0.0, 0.0}, float duration = 0.0)
{
	int particle = CreateEntityByName("info_particle_system");
	if (IsValidEntity(particle))
	{
		if (entity > 0)
		{
			if (IsValidClient(entity))
			{
				GetClientEyePosition(entity, pos);
				pos[2] += 15.0;
			}
			else GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		}
		TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(particle, "effect_name", sParticle);
		if (bAttach)
		{
			SetVariantString("!activator");
			AcceptEntityInput(particle, "SetParent", entity, particle, 0);
		}
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");
		if (duration)
		{
			KillParticleDelay(particle, 10.0);
		}
	}
}

bool IsValidClient(int iClient)
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

void KillParticleDelay(int particle, float seconds)
{
    if(IsValidEdict(particle))
    {
        // send "kill" event to the event queue
        char addoutput[64];
        Format(addoutput, sizeof addoutput, "OnUser1 !self:kill::%f:1", seconds);
        SetVariantString(addoutput);
        AcceptEntityInput(particle, "AddOutput");
        AcceptEntityInput(particle, "FireUser1");
    }
}
