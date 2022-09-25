#pragma semicolon 1

//// TODO:
/// 
/// Update all float arrays used for vectors and angles to FVector and FRotator structs, respectively
/// Update client and object structs to be consistent with my other major plugins
///
////

#include <sdktools>
#include <sdkhooks>
#include <ilib>

ConVar Gravity;
bool GameInProgress;

#define EF_BONEMERGE	(1 << 0)
#define EF_NOSHADOW		16
#define EF_NOINTERP		8

public Plugin MyInfo =
{
	name = "[TF2] Admin Cheats",
	author = "IvoryPal",
	description = "Aimbot and other visuals",
	version = "1.0"
}

//Wallbang SDKCalls
Handle GetWeaponDamageCall;
Handle GetWeaponSpreadCall;
Handle GetCustomDamageTypeCall;

FObject Outline[2049];
FObject Target[2049];
int Offset;

enum AimPriority
{
	Aim_Default,
	Aim_Head,
	Aim_Body,
}

Handle GetBonePosition;

enum struct Aimbot
{
	//esp
	bool esp;
	bool team;
	bool building_esp;
	bool proj_esp;

	//aimbot
	bool aimbot;
	bool silent;
	bool trigger;
	bool target_buildings;
	bool projectile;
	bool ignore_walls;

	int seed; //player seed for prediction
	bool attack_crit;

	AimPriority aim_type;

	int target; //aimbot target
	int priority[MAXPLAYERS+1];

	float fov;

	void SetFov()
	{
		this.fov += 10.0;
		if (this.fov > 180.0)
			this.fov = 0.0;
	}
	void SetPriority(FClient client)
	{
		int player = client.Get();
		if (IsValidClient(player))
		{
			this.priority[player]++;
			if (this.priority[player] > 5)
				this.priority[player] = -1;

		}
	}
	int GetPriority(FClientclient)
	{
		if (client.valid())
		{
			int player = client.Get();
			return this.priority[player];
		}

		return 0;
	}
	bool IsIgnored(FClientclient)
	{
		if (client.valid())
		{
			int player = client.Get();
			return this.priority[player] == -1;
		}

		return false;
	}
	void Disable()
	{
		this.esp = false;
		this.team = false;
		this.aimbot = false;
		this.silent = false;
		this.trigger = false;

		this.fov = 10.0;
	}
}
Aimbot Settings[MAXPLAYERS+1];

///
/// Core Functions
///

public void OnPluginStart()
{
	RegAdminCmd("sm_cheat_config", CmdCheats, ADMFLAG_BAN);

	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	HookEvent("post_inventory_application", OnPlayerSpawn, EventHookMode_Post);

	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);

	//SDKCalls
	GameData config = new GameData("admincheats");
	if (!config)
		SetFailState("Failed to find tf2-punchthrough gamedata! Cannot proceed!");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFWeaponBaseGun::GetProjectileDamage");
	PrepSDKCall_SetReturnInfo(SDKType_Float, SDKPass_Plain);
	GetWeaponDamageCall = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	//PrepSDKCall_SetSignature(SDKLibrary_Server, "\x55\x8B\xEC\x83\xEC\x30\x56\x8B\xF1\x80\xBE\x41\x03\x00\x00\x00", 16);
	PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseAnimating::GetBonePosition");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef, _, VENCODE_FLAG_COPYBACK);
	if ((GetBonePosition = EndPrepSDKCall()) == INVALID_HANDLE)
		SetFailState("Failed to create SDKCall for CBaseAnimating::GetBonePosition signature!");

	Offset = FindSendPropInfo("CBaseAnimating", "m_flFadeScale") + 28;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
			OnClientPostAdminCheck(i);
	}
}

Action OnPlayerSpawn(Event event, const char[] name, bool dbroad)
{
	FClient client;
	client = ConstructClient(event.GetInt("userid"));

	SetupGlow(client, client.GetTeam());

	return Plugin_Continue;
}

Action OnPlayerDeath(Event event, const char[] name, bool dbroad)
{
	FClientclient;
	client = ConstructClient(event.GetInt("userid"));

	int player = client.Get();

	RemoveGlow(Outline[player].Get());
	Outline[player].Kill();

	return Plugin_Continue;
}

public void OnMapStart()
{
	GameInProgress = true;
}

public void OnMapEnd()
{
	GameInProgress = false;
}

public void OnClientPostAdminCheck(int client)
{
	Settings[client].Disable();
}

public void OnClientDisconnect(int client)
{
	Outline[client].Kill();
}

///
/// Player Functions
///

//Order of hitboxes to check for depending on weapon used
enum //hitgroups
{
	HITGROUP_GENERIC,
	HITGROUP_HEAD,
	HITGROUP_CHEST,
	HITGROUP_STOMACH,
	HITGROUP_LEFTARM,
	HITGROUP_RIGHTARM,
	HITGROUP_LEFTLEG,
	HITGROUP_RIGHTLEG,

	NUM_HITGROUPS
};

int HeadShotPriority[] = //Hitbox priority when using a headshot weapon
{
	HITGROUP_HEAD,
	HITGROUP_CHEST,
	HITGROUP_STOMACH,
	HITGROUP_GENERIC,
	HITGROUP_LEFTARM,
	HITGROUP_RIGHTARM,
	HITGROUP_LEFTLEG,
	HITGROUP_RIGHTLEG,
};

int NormalPriority[] = //priority for everything else
{
	HITGROUP_STOMACH,
	HITGROUP_CHEST,
	HITGROUP_GENERIC,
	HITGROUP_HEAD,
	HITGROUP_LEFTARM,
	HITGROUP_RIGHTARM,
	HITGROUP_LEFTLEG,
	HITGROUP_RIGHTLEG,
};

void SetupGlow(int entity, TFTeam team)
{
	RemoveGlow(Outline[entity].Get());
	Outline[entity].Kill();
	int glow = AttachESP(entity, team);
	Target[glow].Set(entity);
	Outline[entity].Set(glow);

	SDKHook(Outline[entity].Get(), SDKHook_SetTransmit, OnGlowReplicated);
}

Action CmdCheats(int client, int args)
{
	OpenMenu(client, Settings[client]);

	return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
	if (Settings[client].aimbot)
		TryAimbot(client, Settings[client], weapon);

	return Plugin_Continue;
}

///
/// Aimbot functions
///

bool TryAimbot(int client, Aimbot settings, int weapon)
{
	bool result = false;
	float pos[3];
	GetClientEyePosition(client, pos);
	FClientplayer;
	GetClosestTarget(client, pos, settings, player);
	settings.target = player.Get();
	PrintToChatAll("Target: %i", settings.target);
	if (settings.target != -1)
	{
		float bonePos[3], aimDir[3], aimAngle[3];
		AimPriority priority = GetAimPriority(client, settings, weapon);
		if (GetBonePositionFromHitbox(client, settings.target, bonePos, priority))
		{
			// wip
		}
	}

	return result;
}

any[sizeof FClient] GetClosestTarget(int client, float origin[3], Aimbot settings)
{
	float targPos[3], closest, fov, distance;
	FClient target, best;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsInFov(i, client, settings.fov, targPos, origin))
				continue;

			if (GetClientTeam(i) == GetClientTeam(client))
				continue;
			else
				target.Set(i);

			if (settings.IsIgnored(target))
				continue;

			int priority = settings.GetPriority(target);
			int cur = settings.GetPriority(best);

			if (priority > cur)
			{
				PrintToChatAll("Found Target %N", i);
				best = target;
				continue;
			}
		}
	}
	return best
}

bool IsInFov(int target, int client, float fov, float targetPos[3], float pos[3])
{
	float forwardVec[3], aimVec[3], angles[3];
	GetClientEyeAngles(client, angles);
	GetAngleVectors(angles, forwardVec, NULL_VECTOR, NULL_VECTOR);

	MakeVectorFromPoints(pos, targetPos, aimVec);

	float rad = ArcCosine(GetVectorDotProduct(forwardVec, aimVec) / GetVectorLength(forwardVec, true));
	float deg = RadToDeg(rad);
	return deg < fov;
}

AimPriority GetAimPriority(int client, Aimbot settings, int weapon)
{
	if (settings.aim_type == Aim_Default)
	{
		char classname[64];
		GetEntityClassname(weapon, classname, sizeof classname);
		if (StrContains(classname, "tf_weapon_sniperrifle") != -1) //need to also check for ambassador and huntsman
			return Aim_Head;
		else
			return Aim_Body;
	}
	return settings.aim_type;
}

//Pull position of bone based on hitbox selection
bool GetBonePositionFromHitbox(int client, int target, float buffer[3], AimPriority aimType)
{
	if (!IsValidClient(target))
		return false;

	Address address = view_as<Address>(GetEntData(target, Offset));
	int data = LoadFromAddress(address, NumberType_Int32);
	address = view_as<Address>(data);
	if (address == Address_Null)
		return false;

	int hitboxes = GetEntProp(target, Prop_Send, "m_nHitboxSet");
	if (hitboxes != 0)
		return false;

	Address addrHitboxes = address + view_as<Address>(LoadFromAddress(address + view_as<Address>(0xB0), NumberType_Int32));
	if (addrHitboxes == Address_Null)
		return false;

	int hitboxCount = LoadFromAddress(addrHitboxes + view_as<Address>(0x4), NumberType_Int32);

	addrHitboxes += view_as<Address>(0xC);

	//Loop all hitgroups
	for (int i = 0; i < NUM_HITGROUPS; i++)
	{
		//Match hitgroup to order we want to check
		int hitgroup;
		if (aimType == Aim_Head)
			hitgroup = HeadShotPriority[i];
		else
			hitgroup = NormalPriority[i];

		if (aimType == Aim_Head && hitgroup != HITGROUP_HEAD)
			continue;

		for (int HitBox = 0; HitBox < hitboxCount; HitBox++) //loop through hitboxes and check bone positions
		{
			Address box = view_as<Address>(addrHitboxes + view_as<Address>(HitBox * 68));
			if (box == Address_Null)
				continue;

			int bone = LoadFromAddress(box, NumberType_Int32);
			int group = LoadFromAddress(box + view_as<Address>(0x4), NumberType_Int32);

			if (group != hitgroup)
				continue;

			float bonePosition[3], boneAngles[3];
			SDKCall(GetBonePosition, target, bone, bonePosition, boneAngles);

			if (aimType == Aim_Head && group == HITGROUP_HEAD)
			{
				float mins[3]; mins = VectorFromAddress(box + view_as<Address>(0x8));
				float maxs[3]; maxs = VectorFromAddress(box + view_as<Address>(0x14));

				//Hitbox Size
				float size[3];
				size[0] = FloatAbs(maxs[0]) + FloatAbs(mins[0]);
				size[1] = FloatAbs(maxs[1]) + FloatAbs(mins[1]);
				size[2] = FloatAbs(maxs[2]) + FloatAbs(mins[2]);

				//Hitbox Origin
				float center[3];
				AddVectors(mins, maxs, center);
				ScaleVector(center, 0.5);

				//Angle vectors
				float vforward[3], vleft[3], up[3];
				GetAngleVectors(boneAngles, vforward, vleft, up);

				//Center bone pos to hitbox
				bonePosition[0] += vleft[2] * center[2];
				bonePosition[1] += vleft[0] * center[0];
				bonePosition[2] -= vleft[2] * center[1];
			}

			float eyePos[3];
			GetClientEyePosition(client, eyePos);
			if (CheckVisibility(client, target, eyePos, bonePosition, hitgroup))
			{
				buffer = bonePosition;
				return true;
			}
		}
	}

	return false;
}

bool CheckVisibility(int client, int target, float pos[3], float end[3], int group)
{
	return true;
}


///
/// Game Events and Functions
///

public void OnEntityCreated(int entity, const char[] classname)
{
	if (GameInProgress)
	{
		if (StrContains(classname, "tf_projectile") != -1 || StrContains(classname, "obj_") != -1)
			RequestFrame(OnEntSpawnPost, entity);
	}
}

void OnEntSpawnPost(int entity)
{
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	SetupGlow(entity, team);
}

public void OnEntityDestroyed(int entity)
{
	if (entity > 0 && entity < 2049) // exclude pointers
	{
		RemoveGlow(Outline[entity].Get());
		Outline[entity].Kill();
	}
}


///
/// Menu Functions
///

enum
{
	SETTINGS_AIMBOT,
	SETTINGS_ESP,
	SETTINGS_MISC,
	SETTINGS_PLAYERS,
}

void OpenMenu(int client, Aimbot settings)
{
	Menu cheats = new Menu(MainMenuCallback);
	cheats.SetTitle("Cheat Menu\n ");

	char item[32];

	//Aimbot
	cheats.AddItem("", "Aimbot Settings");

	//ESP
	cheats.AddItem("", "ESP Settings");

	//Misc
	cheats.AddItem("", "Misc. Settings");

	//Players
	cheats.AddItem("", "Player List");

	cheats.ExitButton = true;
	cheats.Display(client, 120);
}

void OpenSettingsMenu(int client, Aimbot settings, int type)
{
	Menu cheats = new Menu(MenuSettingsCallback);
	char item[32];
	switch(type)
	{
		case SETTINGS_AIMBOT: AimbotMenu(cheats, client, settings);
		case SETTINGS_ESP: ESPMenu(cheats, client, settings);
		case SETTINGS_MISC: MiscMenu(cheats, client, settings);
		case SETTINGS_PLAYERS: PlayerMenu(cheats, client, settings);
	}
	cheats.ExitBackButton = true;
	cheats.Display(client, 120);
}

void AimbotMenu(Menu cheats, int client, Aimbot settings)
{
	cheats.SetTitle("Aimbot Settings\n ");
	char item[32];

	//Enabled | Disable
	FormatEx(item, sizeof item, "Aimbot: %s", settings.aimbot ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_enable", item);

	//FOV
	FormatEx(item, sizeof item, "Field of View: %i", RoundFloat(settings.fov));
	cheats.AddItem("aimbot_fov", item);

	//Buildings
	FormatEx(item, sizeof item, "Target Buildings: %s", settings.target_buildings ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_building", item);

	//Silent
	FormatEx(item, sizeof item, "Silent Aim: %s", settings.silent ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_silent", item);

	//Trigger
	FormatEx(item, sizeof item, "Trigger Bot: %s", settings.trigger ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_trigger", item);

	//Ignore walls
	FormatEx(item, sizeof item, "Ignore Walls: %s", settings.ignore_walls ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_walls", item);

	//Projectile
	FormatEx(item, sizeof item, "Projectile Aimbot: %s", settings.projectile ? "Enabled" : "Disabled");
	cheats.AddItem("aimbot_proj", item);
}

void ESPMenu(Menu cheats, int client, Aimbot settings)
{
	cheats.SetTitle("ESP Settings: \n");
	char item[32];

	//ESP
	FormatEx(item, sizeof item, "ESP: %s", settings.esp ? "Enabled" : "Disabled");
	cheats.AddItem("esp_enable", item);

	//Team
	FormatEx(item, sizeof item, "Outline Teammates: %s", settings.team ? "Enabled" : "Disabled");
	cheats.AddItem("esp_team", item);

	//Buildings
	FormatEx(item, sizeof item, "Outline Buildings: %s", settings.building_esp ? "Enabled" : "Disabled");
	cheats.AddItem("esp_buildings", item);

	//Projectiles
	FormatEx(item, sizeof item, "Outline Projectiles: %s", settings.proj_esp ? "Enabled" : "Disabled");
	cheats.AddItem("esp_proj", item);
}

void MiscMenu(Menu cheats, int client, Aimbot settings)
{
	cheats.SetTitle("Misc Settings\n\nCurrently Unavailable");
}

void PlayerMenu(Menu cheats, int client, Aimbot settings)
{
	cheats.SetTitle("Player List\n ");
	char item[32];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && i != client)
		{
			char id[8], value[16];
			IntToString(i, id, sizeof id);

			if (settings.priority[i] == -1)
				FormatEx(value, sizeof value, "Ignored");
			else
				IntToString(settings.priority[i], value, sizeof value);

			//Add player to list
			FormatEx(item, sizeof item, "%N: %s", i, value);
			cheats.AddItem(id, item);
		}
	}
}

///
/// Menu Callback Functions
///

int MainMenuCallback(Menu menu, MenuAction action, int client, int param)
{
	switch (action)
	{
		case MenuAction_Select: OpenSettingsMenu(client, Settings[client], param);
	}
	return 0;
}

int MenuSettingsCallback(Menu menu, MenuAction action, int client, int param)
{
	switch (action)
	{
		case MenuAction_Cancel:
		{
			if (param == MenuCancel_ExitBack)
				OpenMenu(client, Settings[client]);
		}
		case MenuAction_Select:
		{
			int type;
			char item[32];
			menu.GetItem(param, item, sizeof item);

			if (IsCharNumeric(item[0])) //Client ID selected
			{
				int id = StringToInt(item);
				FClientplayer;
				player.Set(id);

				Settings[client].SetPriority(player);
				type = SETTINGS_PLAYERS;
			}
			else
			{
				//determine which menu we are in
				if (StrContains(item, "aimbot_") != -1)
				{
					type = SETTINGS_AIMBOT;
					CheckAimbotSettings(client, Settings[client], item);
				}
				else if (StrContains(item, "esp_") != -1)
				{
					type = SETTINGS_ESP;
					CheckESPSettings(client, Settings[client], item);
				}
				else if (StrContains(item, "misc_") != -1)
				{
					type = SETTINGS_MISC;
					//CheckMiscSettings(client, Settings[client], item);
				}
			}
			OpenSettingsMenu(client, Settings[client], type);
		}
	}
	return 0;
}

///
/// ESP Functions
///

public Action OnGlowReplicated(int overlay, int client)
{
	int owner = Target[overlay].Get();
	if (owner && IsValidEntity(owner)) //IsValidEntity returns true on entity 0 (server) so make sure owner is not 0
	{
		if (ReplicateESP(client, Settings[client], owner))
			return Plugin_Continue;
		else if (owner != client)
			return Plugin_Handled;

	}
	return Plugin_Handled;
}

bool ReplicateESP(int client, Aimbot settings, int target)
{
	if (IsValidClient(client))
	{
		if (!settings.esp)
			return false;

		int team = GetClientTeam(client);
		int targTeam;
		if (IsValidClient(target)) //Player ESP
		{
			FClient player;
			player.Set(target);

			if (settings.IsIgnored(player)) //do not outline ignored players
				return false;

			targTeam = GetClientTeam(target);
		}
		else if (IsValidEntity(target) && target > MaxClients && HasEntProp(target, Prop_Send, "m_iTeamNum")) //Projectiles and buildings
		{
			char classname[64];
			GetEntityClassname(target, classname, sizeof classname);
			if (StrContains(classname, "tf_projectile") != -1)
			{
				if (!settings.proj_esp)
					return false;
			}
			else if (StrContains(classname, "obj_") != -1)
			{
				if (!settings.building_esp)
					return false;
			}
			targTeam = GetEntProp(target, Prop_Send, "m_iTeamNum");
		}
		//ESP on own team
		if (team == targTeam)
			return settings.team;
		else
			return true;
	}
	return false;
}

///
/// Helper Functions
///

// Needs to be removed in favor of FClient::Valid()
bool IsValidClient(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		return IsClientInGame(client);
	}
	return false;
}

void CheckAimbotSettings(int client, Aimbot settings, const char[] item)
{
	//whew
	if (StrEqual(item, "aimbot_enable"))
		settings.aimbot = !settings.aimbot;
	else if (StrEqual(item, "aimbot_fov"))
		settings.SetFov();
	else if (StrEqual(item, "aimbot_building"))
		settings.target_buildings = !settings.target_buildings;
	else if (StrEqual(item, "aimbot_trigger"))
		settings.trigger = !settings.trigger;
	else if (StrEqual(item, "aimbot_walls"))
		settings.ignore_walls = !settings.ignore_walls;
	else if (StrEqual(item, "aimbot_proj"))
		settings.projectile = !settings.projectile;
}

void CheckESPSettings(int client, Aimbot settings, const char[] item)
{
	if (StrEqual(item, "esp_enable"))
		settings.esp = !settings.esp;
	else if (StrEqual(item, "esp_team"))
		settings.team = !settings.team;
	else if (StrEqual(item, "esp_buildings"))
		settings.building_esp = !settings.building_esp;
	else if (StrEqual(item, "esp_proj"))
		settings.proj_esp = !settings.proj_esp;
}

float[] VectorFromAddress(Address address)
{
	float vector[3];

	vector[0] = float(LoadFromAddress(address + view_as<Address>(0x0), NumberType_Int32));
	vector[1] = float(LoadFromAddress(address + view_as<Address>(0x4), NumberType_Int32));
	vector[2] = float(LoadFromAddress(address + view_as<Address>(0x8), NumberType_Int32));
	return vector;
}

int AttachESP(int entity, TFTeam team)
{
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);

	if (strlen(model) != 0)
	{
		FObject prop;
		prop.create("tf_taunt_prop");

		if (prop.valid())
		{
			prop.spawn();
			if (team != TFTeam_Unassigned)
			{
				prop.SetProp(Prop_Data, "m_iInitialTeamNum", view_as<int>(team));
				prop.SetProp(Prop_Send, "m_iTeamNum", view_as<int>(team));
			}

			prop.SetModel(model);

			prop.SetPropEnt(Prop_Data, "m_hEffectEntity", entity);
			//SetEntProp(prop, Prop_Send, "m_bGlowEnabled", 1);

			CreateOutline(prop, view_as<int>(team));

			int flags = prop.GetProp(Prop_Send, "m_fEffects");

			prop.SetProp(Prop_Send, "m_fEffects", flags | EF_BONEMERGE | EF_NOSHADOW | EF_NOINTERP);

			SetVariantString("!activator");
			prop.input("SetParent", entity);

			LinearColor color;
			color.Set(255, 255, 255, 0);
			SetEntityRenderMode(prop.Get(), RENDER_TRANSCOLOR);
			prop.SetColor(color);
		}
		return prop.Get();
	}
	return -1;
}

int CreateOutline(int entity, int team)
{
	char oldEntName[64];
	GetEntPropString(entity, Prop_Data, "m_iName", oldEntName, sizeof oldEntName);

	char strName[126], strClass[64];
	GetEntityClassname(entity, strClass, sizeof strClass);
	Format(strName, sizeof strName, "%s%i", strClass, entity);
	DispatchKeyValue(entity, "targetname", strName);

	int glow = CreateEntityByName("tf_glow");
	DispatchKeyValue(glow, "target", strName);
	DispatchKeyValue(glow, "Mode", "0");
	DispatchSpawn(glow);

	AcceptEntityInput(glow, "Enable");

	int color[4];
	switch (team)
	{
		case 2: color = {255, 0, 0, 255};
		case 3: color = {0, 185, 255, 255};
		default: color = {200, 200, 200, 255};
	}

	SetVariantColor(color);
	AcceptEntityInput(glow, "SetGlowColor");

	//Change name back to old name because we don't need it anymore.
	SetEntPropString(entity, Prop_Data, "m_iName", oldEntName);

	return ent;
}

stock void RemoveGlow(int entity)
{
	if (IsValidEntity(iEnt) && iEnt > 0)
	{
		int index = -1;
		while ((index = FindEntityByClassname(index, "tf_glow")) != -1)
		{
			if (GetEntPropEnt(index, Prop_Send, "m_hTarget") == iEnt)
			{
				RemoveEntity(index);
			}
		}
	}
}
