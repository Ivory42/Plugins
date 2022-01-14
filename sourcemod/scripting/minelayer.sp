/*
NOT FULLY TESTED MOST LIKELY DOES NOT WORK

Just a standalone stickybomb toggle that turns stickies into land mines
Walking over a mine from the opposing team will cause it to detonate
Mines cannot be manually detonated by the owner
*/

#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>

bool LandMine[2049];
bool PlayerHasMines[MAXPLAYERS+1];

enum struct LandMine
{
	int pipe;
	int trigger;
	bool armed;
	
	int CreateMine(char[] modelname, int oldPipe, float triggerPos[3])
	{
		this.pipe = oldPipe;
		if (strlen(modelname) > 0)
		{
			PrecacheModel(modelname);
			SetEntityModel(this.pipe, modelname);
		}
		LandMine[this.pipe] = true;
		SetEntProp(this.pipe, Prop_Data, "m_nNextThinkTick", -1);
		this.trigger = CreateEntityByName("trigger_hurt"); //create our trigger box. TODO - Set bounds for trigger
		TeleportEntity(this.trigger, triggerPos, NULL_VECTOR, NULL_VECTOR);
		SetVariantString("!activator");
		AcceptEntityInput(this.trigger, "SetParent", this.pipe, this.trigger, 0);
		SDKHook(this.trigger, SDKHook_Touch, OnTriggerOverlap);
		DispatchSpawn(this.trigger);
		ActivateEntity(this.trigger);
		
		return this.pipe;
	}
	void DetonateMine()
	{
		if (IsValidEntity(this.pipe) && this.pipe > MaxClients)
		{
			SDKCall(this.pipe, DetonatePipe);
		}
	}
}

LandMine Mine[2049];
Handle DetonatePipe;

public void OnPluginStart()
{
	RegConsoleCmd("sm_mines", SetLandMines);
	GameData data = new GameData("GrenadeData");
	if (!data)
		SetFailState("Failed to find GrenadeData.txt. Unable to continue!");
		
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(data, SDKConf_Virtual, "GrenadeDetonate");
	DetonatePipe = EndPrepSDKCall();
	delete data;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			OnClientPutInServer(i);
		}
	}
}

Action SetLandMines(int client, int args)
{
	PlayerHasMines[client] = !PlayerHasMines[client];
	ReplyToCommand(client, "[SM] Landmines %s!", PlayerHasMines[client] ? "enabled" : "disabled");
}

public void OnClientPutInServer(int client)
{
	PlayerHasMines[client] = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (IsValidEntity(entity) && entity > MaxClients)
	{
		if (StrEqual(classname, "tf_projectile_pipe_remote")
			SDKHook(entity, SDKHook_SpawnPost, OnPipeSpawned);
	}
}

public void OnEntityDestroyed(int entity)
{
	if (IsValidEntity(entity) && entity > MaxClients)
		LandMine[entity] = false;
}

Action OnPipeSpawned(int pipe)
{
	int owner = GetEntPropEnt(pipe, Prop_Send, "m_hOwnerEntity");
	if (IsValidClient(owner) && PlayerHasMines[owner])
	{
		LandMine[pipe] = true;
		float pos[3];
		GetEntPropVector(pipe, Prop_Data, "m_vecOrigin", pos);
		Mine[pipe].create("", pipe, pos);
		int trigger = Mine[pipe].trigger;
		Mine[trigger] = Mine[pipe];
		SDKHook(pipe, SDKHook_VPhysicsUpdate, OnPipeUpdate);
	}
}

Action OnPipeUpdate(int pipe)
{
	if (HasEntProp(pipe, Prop_Send, "m_bTouched"))
	{
		if (GetEntProp(pipe, Prop_Send, "m_bTouched") && LandMine[pipe] && Mine[pipe].CanArm())
		{
			Mine[pipe].isArming = true;
			Mine[pipe].armDelay = GetGameTime() + 2.0;
		}
		else if (Mine[pipe].isArming && Mine[pipe].armDelay <= GetGameTime() && LandMine[pipe])
		{
			Mine[pipe].isArming = false;
			Mine[pipe].armed = true;
			//Need to find a fitting sound to play here
		}
	}
}

Action OnTriggerOverlap(int trigger, int other)
{
	if (IsValidClient(other))
	{
		int pipe = TriggerPipe[trigger];
		if (IsValidEntity(pipe) && LandMine[pipe])
			PrepareDetonate(Mine[pipe]);
	}
}
