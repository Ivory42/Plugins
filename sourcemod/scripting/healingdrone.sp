////
///
/// Modification of my manhack plugin
/// This plugin spawns drones which follow and heal the player as opposed to finding and attacking enemy players
///
/// Drones will find the nearest player and follow them while healing them, as they get further away, their speed will increase to try and close the gap
/// If more than one drone is on the same player, any extra drones will bail as soon as another player is visible to them
///
/// Experimented with a bit of pathfinding so drones don't get stuck on walls or other obstacles; it's not perfect but it works pretty well so far
///
////


#include <npc_logic>

FHealDrone Manhack[2049];

GlobalForward NPCKilled;

public void OnPluginStart()
{
	RegAdminCmd("sm_healdrone", CmdManhack, ADMFLAG_ROOT);
	RegAdminCmd("sm_neutralhealdrone", CmdManhackNeutral, ADMFLAG_ROOT);

	HookEvent("player_death", OnPlayerDeath);

	NPCKilled = CreateGlobalForward("NPC_OnNpcKilled", ET_Ignore, Param_Array, Param_String, Param_Array);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("NPC_SpawnHealDrone", Native_SpawnHealdrone);
	return APLRes_Success;
}

public any Native_SpawnHealdrone(Handle Plugin, int args)
{
	FClient client;
	GetNativeArray(1, client, sizeof FClient);

	FNpcInfo npc;
	GetNativeArray(3, npc, sizeof FNpcInfo);

	FObject drone;

	if (client.Valid())
	{
		FVector spawnpos;
		client.GetEyePosition(spawnpos);

		spawnpos.z += 10.0;

		drone = SpawnDrone(spawnpos, client, npc);
	}
	SetNativeArray(2, drone, sizeof FObject);
}

Action OnPlayerDeath(Event event, const char[] name, bool dBroad)
{
	int client = event.GetInt("userid");

	if (client > 0)
		HasDrone[client] = false;
}

Action CmdManhack(int clientId, int args)
{
	char argument[64];
	GetCmdArgString(argument, sizeof argument);

	FVector spawnpos, tracepos;
	FRotator angle;

	FClient client;
	client.Set(clientId);

	client.GetEyePosition(tracepos);
	client.GetEyeAngles(angle);
	angle.GetForwardVector(spawnpos);

	spawnpos.Scale(4000.0);

	spawnpos.Add(Vector_MakeFloat(tracepos));

	RayTrace trace = new RayTrace(tracepos, spawnpos, MASK_PLAYERSOLID, FilterSelf, clientId);
	trace.GetEndPosition(spawnpos);

	delete trace;

	spawnpos.z += 150.0;

	FNpcInfo npc;

	npc.health = 250.0;
	npc.healRate = 0.08; // Healing rate

	npc.healing = 1.0; // Amount to heal per heal tick

	SpawnDrone(spawnpos, client, npc);


	return Plugin_Continue;
}


// Spawns a healing drone which will heal either team
Action CmdManhackNeutral(int clientId, int args)
{
	char argument[64];
	GetCmdArgString(argument, sizeof argument);

	FVector spawnpos, tracepos;
	FRotator angle;

	FClient client;
	client.Set(clientId);

	client.GetEyePosition(tracepos);
	client.GetEyeAngles(angle);
	angle.GetForwardVector(spawnpos);

	spawnpos.Scale(4000.0);

	spawnpos.Add(Vector_MakeFloat(tracepos));

	RayTrace trace = new RayTrace(tracepos, spawnpos, MASK_PLAYERSOLID, FilterSelf, clientId);
	trace.GetEndPosition(spawnpos);

	delete trace;

	spawnpos.z += 150.0;

	FNpcInfo npc;

	npc.health = 250.0;
	npc.healRate = 0.08; // Healing rate

	npc.healing = 1.0; // Amount to heal per heal tick

	SpawnDrone(spawnpos, ConstructClient(0), npc);


	return Plugin_Continue;
}


bool FilterSelf(int entity, int mask, int exclude)
{
	return (entity != exclude);
}

any[sizeof FObject] SpawnDrone(FVector pos, FClient owner, FNpcInfo npc)
{
	FObject hull;
	hull.Create("prop_physics_multiplayer"); // Works way better than prop_physics. Collision is disabled with players so no worries about getting players stuck

	hull.SetKeyValue("model", "models/manhack.mdl"); // models/shield_scanner doesn't have a physics asset I guess? so just using the manhack instead...

	//hull.SetKeyValue("solid", "4");

	hull.Spawn();
	hull.Activate();

	hull.Teleport(pos, ConstructRotator(), ConstructVector());

	int id = hull.Get();
	SDKHook(id, SDKHook_OnTakeDamage, OnTakeDamageManhack);

	// We need a physics model, but physics models don't seem to like having animations applied
	// So we'll just set this to be invisible and parent a dynamic prop for animations
	SetEntityRenderFx(id, RENDERFX_FADE_FAST);

	FObject model;
	model.Create("prop_dynamic_override");

	model.SetKeyValue("model", "models/shield_scanner.mdl");

	model.Spawn();
	model.Activate();

	model.Teleport(pos, ConstructRotator(), ConstructVector());

	model.Attach(hull.Get());

	SetAnimation(model, "CloseUp"); // Deploy animation

	Manhack[id].DeployTime.Set(2.0);
	Manhack[id].hull = hull;
	Manhack[id].model = model;
	Manhack[id].maxhealth = npc.health;
	Manhack[id].health = npc.health;

	Manhack[id].HealDelay.Set(npc.healRate);

	Manhack[id].SetOwner(owner.Get());
	Manhack[id].team = owner.GetTeam();

	Manhack[id].healing = npc.healing;

	IsManhack[id] = true;

	return hull;
}

void SetAnimation(FObject model, const char[] sequence)
{
	SetVariantString(sequence);
	model.Input("SetAnimation");
}

public void OnEntityDestroyed(int entity)
{
	if (entity < 2049 && entity > 0)
	{
		if (IsManhack[entity])
			Manhack[entity].KillParticles();

		IsManhack[entity] = false;
	}
}

public void OnGameFrame()
{
	int entity;
	while ((entity = FindEntityByClassname(entity, "prop_physics_multiplayer")) != -1)
	{
		if (IsManhack[entity])
			OnManhackTick(Manhack[entity]);
	}
}

void OnManhackTick(FHealDrone manhack)
{
	if (manhack.hull.Valid())
	{
		float maxspeed = 600.0;
		float basespeed = 500.0;
		float acceleration = 12.0;
		if (manhack.DeployTime.Expired())
			SetAnimation(manhack.model, "HoverClosed");

		FRotator angle;
		manhack.GetAngles(angle);

		FVector velocity, pos, upwards;
		upwards = ConstructVector(0.0, 0.0, 12.0); // Try to counteract gravity

		FVector aimvector;

		manhack.GetPosition(pos);

		// heal target found
		if (manhack.HasTarget())
		{
			FVector targetpos;

			if (manhack.loose)
				CheckForOtherPlayers(manhack);

			basespeed = manhack.target.GetMaxSpeed();

			if (!manhack.targetvisible)
				basespeed = 500.0;

			if (!VisibleTarget(manhack, angle, pos))
			{
				float targetdistance = pos.DistanceTo(Vector_MakeFloat(manhack.targetLastPos)); // SM 1.10 doesn't allow structs to accept arguments of the same type... so they need to be converted to a float array instead

				manhack.KillParticles();
				//manhack.CheckTargetTimer.Loop();
				if (targetdistance > 5.0)
				{
					//PrintDistanceToLastPosition(manhack);
					targetpos = manhack.targetLastPos;
					manhack.targetvisible = false;
				}
				else if (targetdistance <= 5.0) // Lose our target immediately if we still can't see them
				{
					manhack.ClearTarget();
					targetpos = pos;
					return;
				}
			}
			else
			{
				if (TargetInFOV(manhack.target, angle, pos))
				{
					// Try to match our target's speed
					// Scale acceleration and max speed by our distance

					manhack.targetvisible = true;

					float targetdistance = pos.DistanceTo(Vector_MakeFloat(manhack.targetLastPos)); 
					if (targetdistance > 150.0)
						acceleration = targetdistance / 150.0 * acceleration; // Scale our acceleration when further than 150hu

					maxspeed = targetdistance / 200.0 * basespeed;

					if (maxspeed <= basespeed) maxspeed = basespeed;

					//manhack.CheckTargetTimer.Loop();
					manhack.target.GetPosition(targetpos);
					targetpos.z += 85.0;
				}
				else
					targetpos = manhack.targetLastPos;
			}

			// Do not move unless we are far enough away from our destination and we are not waiting
			float destination = pos.DistanceTo(Vector_MakeFloat(targetpos));
			if (destination > 140.0)
			{
				Vector_MakeFromPoints(pos, targetpos, aimvector);

				manhack.speed += acceleration;
			}
			else if (!manhack.targetvisible)
			{
				Vector_MakeFromPoints(pos, targetpos, aimvector);
				manhack.speed += 5.0;
			}
			else if (destination <= 1.0) // Move backwards
			{
				Vector_MakeFromPoints(pos, targetpos, aimvector);

				manhack.speed = basespeed * -1.0;
			}
			else
			{
				// Have the drone inherit speed from the heal target as long as the target isn't traveling too fast
				FVector playervel;
				manhack.target.GetPropVector(Prop_Data, "m_vecVelocity", playervel);

				float playerspeed = playervel.Length();

				if (playerspeed <= 700.0)
				{
					Vector_Add(upwards, playervel, upwards); // Just add to the upwards velocity

					// Find a random position around the player to move to
					FVector moveto;
					float orbitspeed = 60.0;

					moveto = GetPositionAroundPlayer(manhack, pos, orbitspeed, upwards);

					if (manhack.orbiting)
					{
						FVector trajectory;
						Vector_MakeFromPoints(pos, moveto, trajectory);
						trajectory.Normalize();

						trajectory.Scale(orbitspeed);

						Vector_Add(upwards, trajectory, upwards);
					}
					if (pos.DistanceTo(Vector_MakeFloat(moveto)) <= 5.0)
					{
						manhack.orbiting = false;
					}
				}

				manhack.speed = basespeed;
			}

			aimvector.Normalize();
			velocity = aimvector;

			FVector lookdirection, lookpos;
			lookpos = targetpos;
			targetpos.z -= 30.0;
			Vector_MakeFromPoints(pos, lookpos, lookdirection);

			velocity.Normalize();

			Vector_GetAngles(lookdirection, angle);

			velocity.Scale(manhack.speed);

			// Do our healing stuff
			if (destination <= 200.0)
			{
				FVector healpos;
				manhack.target.GetPosition(healpos);
				healpos.z += 60.0;

				if (!manhack.Particles() && manhack.targetvisible) // attach our heal beam
				{
					manhack.DisplayTimer.Set(1.0);
					manhack.event = manhack.target.GetHealth() < manhack.target.GetMaxHealth();

					CreateHealBeamEntity(manhack.target, manhack.hull, manhack.healbeam, manhack.healattach);
				}
				//else
					//manhack.healbeam.SetVelocityRotation(angle, ConstructVector()); // Doesn't seem to do anything

				RayTrace attack = new RayTrace(pos, healpos, MASK_PLAYERSOLID, FilterPlayers, manhack.target.Get());
				if (attack.DidHit())
				{
					FClient client;
					client = ConstructClient(attack.GetHitEntity(), true);

					if (client.Valid() && manhack.HealDelay.Expired())
					{
						manhack.HealDelay.Loop();
						HealPlayer(client, ConstructClient(manhack.GetOwner(), true), manhack);
					}
				}
				//attack.DebugTrace(0.1);
				delete attack;
			}
			else
				manhack.KillParticles();
		}
		else
		{
			manhack.target = GetClosestTarget(manhack, manhack.hull);
			manhack.KillParticles();
		}

		//PrintCenterTextAll("Drone speed = %.1f\nMax Speed = %.1f", manhack.speed, maxspeed);
		if (manhack.speed > maxspeed)
			manhack.speed = maxspeed;

		if (manhack.speed < maxspeed * -1.0)
			manhack.speed = maxspeed * -1.0;

		velocity.Add(Vector_MakeFloat(upwards));
		manhack.hull.SetVelocityRotation(angle, velocity);
	}
}

///
/// Instead of just having the drone sit completely still near the player, let's have it randomly move around them instead
/// This makes them a bit harder to hit and just looks better
///

any[sizeof FVector] GetPositionAroundPlayer(FHealDrone manhack, FVector pos, float& movespeed, FVector velocity)
{
	if (!manhack.orbiting)
	{
		manhack.orbiting = true;

		manhack.orbitOffset = ConstructVector(GetRandomFloatInRange(60.0, 80.0, true), GetRandomFloatInRange(60.0, 80.0, true), GetRandomFloat(20.0, 40.0));
	}

	FVector playerpos;
	manhack.target.GetEyePosition(playerpos);

	Vector_Add(playerpos, manhack.orbitOffset, playerpos);

	float hullsize = 14.0;

	// Hull trace for better pathfinding
	HullTrace trace = new HullTrace(pos, playerpos, ConstructVector(hullsize * -1.0, hullsize * -1.0, hullsize * -1.0), ConstructVector(hullsize, hullsize, hullsize), MASK_SHOT, FilterDroneCollision, manhack.hull.Get());
	if (trace.DidHit())
	{
		// Offset our position slightly if we hit a surface
		FVector hitpos, normal;
		trace.GetEndPosition(hitpos);
		trace.GetNormalVector(normal);

		normal.Scale(60.0);
		Vector_Add(hitpos, normal, playerpos);
	}
	delete trace;

	FVector intersect, velAdd;
	bool colliding = CollidingObject(manhack, pos, velAdd, intersect, movespeed);
	if (colliding)
	{
		Vector_Add(velocity, velAdd, velocity); // Add velocity in direction away from the obstacle
		
		//Vector_Add(playerpos, intersect, playerpos); // Shift our destination position in the direction we want to move to avoid the obstacle
		//manhack.orbitOffset = playerpos;
	}

	/*
	FTempentProperties info;
	info.model = PrecacheModel("materials/sprites/laser.vmt");
	info.halo = info.model;
	info.lifetime = 0.1;
	info.width = 5.0;
	info.color = {255, 0, 180, 255};

	TempEnt laser = TempEnt();

	laser.CreateBeam(pos, playerpos, info);

	Tempent_DrawBox(playerpos, hullsize);
	*/

	return playerpos;
}

///
/// Wowie this was a pain to figure out properly. Seems adding velocity to the object works a lot better than trying to just shift its destination point
/// This can definitely be better but it seems to work pretty well
/// The drone moves under doorways and around corners pretty decently
/// However.... inside corners are not handled well at all and the drone seems to just freak out at times. Oh well!
///

bool CollidingObject(FHealDrone manhack, FVector pos, FVector velocity, FVector offset, float& movespeed)
{
	bool result = false;
	float hullsize = 7.0; // The model is about 12 hu so give a bit more space
	HullTrace trace = new HullTrace(pos, pos, ConstructVector(hullsize * -1.0, hullsize * -1.0, hullsize * -1.0), ConstructVector(hullsize, hullsize, hullsize), MASK_SHOT, FilterDroneCollision, manhack.hull.Get());
	if (trace.DidHit())
	{
		result = true;
		FVector end;
		trace.GetEndPosition(end);
		FVector direction;

		float distance = Vector_GetDistance(end, pos);
		if (distance < 20.0)
			movespeed *= ((1.0 - (distance / 20.0)) * 2.0); // We want to move faster the closer we are to the wall

		Vector_MakeFromPoints(end, pos, direction);
		direction.Normalize();
		direction.Scale(manhack.owner.GetMaxSpeed()); // velocity

		velocity = direction;

		offset = end;

		//direction.Normalize();
		//direction.Scale(70.0); // shift by 70 hu

		//Vector_Add(offset, direction, offset);
	}
	delete trace;

	//Tempent_DrawBox(pos, hullsize);

	return result;
}

bool FilterDroneCollision(int entityId, int mask, int droneId)
{
	FClient player;
	player.Set(entityId);

	if (player.Valid()) // Do not block from players ever
		return false;

	FObject entity;
	entity.Set(entityId);

	if (entity.Cast("prop_physics_multiplayer")) // ignore other drones as well
		return false;

	return true;
}

float GetRandomFloatInRange(float min, float max, bool sign)
{
	float result = GetRandomFloat(min, max);
	if (sign && GetRandomInt(1, 2) == 2)
		result *= -1.0;

	return result;
}

void CheckForOtherPlayers(FHealDrone manhack)
{
	FClient client;
	client = GetClosestTarget(manhack, manhack.hull);

	if (client.Valid())
		manhack.target = client;
}

/*
void PrintDistanceToLastPosition(FHealDrone manhack)
{
	static float nextTime;
	FVector pos;
	manhack.GetPosition(pos);

	float distance = pos.DistanceTo(Vector_MakeFloat(manhack.targetLastPos));

	if (nextTime <= GetGameTime())
	{
		PrintToChatAll("Distance to position = %.1f", distance);
		nextTime = GetGameTime() + 2.0;
	}

	RayTrace trace = new RayTrace(pos, manhack.targetLastPos, MASK_SHOT, FilterSelf, manhack.hull.Get());
	trace.DebugTrace(0.1);

	delete trace;
}
*/

// Not really needed but leaving in case I decide to use it again
bool TargetInFOV(FClient target, FRotator angles, FVector pos)
{
	FVector targetpos;
	target.GetPosition(targetpos);

	//manhack.GetPosition(pos);//

	FRotator direction;
	direction = CalcAngle(pos, targetpos);
	float angle = GetAngle(angles, direction);

	if (angle <= 180.0)
		return true;

	return false;
}

bool VisibleTarget(FHealDrone manhack, FRotator angles, FVector origin)
{
	if (!TargetInFOV(manhack.target, angles, origin))
		return false;

	bool result = false;

	FVector targetPos;
	manhack.target.GetEyePosition(targetPos);

	RayTrace trace = new RayTrace(origin, targetPos, MASK_PLAYERSOLID, FilterPlayers, manhack.target.Get());
	if (trace.DidHit())
	{
		FClient test;
		test = ConstructClient(trace.GetHitEntity(), true);

		if (test.Valid())
			result = (test.Get() == manhack.target.Get());
		else
			result = false;
	}
	//trace.DebugTrace(0.1);
	delete trace;

	if (result)
		manhack.targetLastPos = targetPos;

	return result;
}

any[sizeof FClient] GetClosestTarget(FHealDrone manhack, FObject entity) //Closest player to an object
{
	float targetDistance = 0.0;
	FClient closestTarget;

	for (int i = 1; i <= MaxClients; i++)
	{
		FClient target;
		target.Set(i);

		if (!target.Alive())
			continue;

		if (manhack.GetTeam() >= 2) // Only find teammates
		{
			if (target.GetTeam() != manhack.GetTeam())
				continue;
		}

		if (target.Get() == manhack.target.Get())
			continue;

		if (target.GetTeam() < 2)
			continue;

		if (manhack.loose && HasDrone[i])
			continue;

		FVector position, targetPosition;
		FRotator angles;

		entity.GetAngles(angles);

		entity.GetPosition(position);
		target.GetPosition(targetPosition);

		if (!TargetInFOV(target, angles, position))
			continue;

		// Calculate distance between object and player, then sort by closest
		float distance = position.DistanceTo(Vector_MakeFloat(targetPosition));
		if (CheckEntTrace(entity, target))
		{
			if (targetDistance)
			{
				if (distance >= targetDistance)
					continue;
			}
			closestTarget = target;
			targetDistance = distance;
		}
	}

	if (closestTarget.Valid())
	{
		int id = closestTarget.Get();
		manhack.loose = HasDrone[id]; // Break off and go to the next player when one becomes available

		HasDrone[id] = true; // Set to true for any other drones that attach
	}

	return closestTarget;
}

public bool CheckEntTrace(FObject entity, FClient victim)
{
	FVector position, targetPosition;

	bool result;

	entity.GetPosition(position);
	victim.GetPosition(targetPosition);

	RayTrace trace = new RayTrace(position, targetPosition, MASK_PLAYERSOLID, FilterSelf, entity.Get());
	if (trace.DidHit())
	{
		FClient test;
		test.Set(trace.GetHitEntity());
		if (test.Valid())
		{
			if (test.Get() == victim.Get()) // visible target
				result = true;
			else
				result = false;
		}
	}
	else
		result = false;

	//trace.DebugTrace(0.1);

	delete trace;
	return result;
}

Action OnTakeDamageManhack(int manId, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	FClient player;
	player.Set(attacker);

	FClient owner;
	owner.Set(Manhack[manId].GetOwner());

	if (player.Valid())
	{
		if (owner.Valid())
		{
			// Do not allow friendly players to deal damage
			if (player.GetTeam() == Manhack[manId].GetTeam())
				return Plugin_Stop;
		}
		int damageamount = RoundFloat(damage);
		int health = RoundFloat(Manhack[manId].health);
		Event PropHurt = CreateEvent("npc_hurt", true);

		//setup components for event
		PropHurt.SetInt("entindex", manId);
		PropHurt.SetInt("attacker_player", player.userid);
		PropHurt.SetInt("damageamount", damageamount);
		PropHurt.SetInt("health", health - damageamount);
		//PropHurt.SetBool("crit", crit);

		PropHurt.Fire(false);
	}

	Manhack[manId].health -= damage;

	if (!Manhack[manId].HasTarget())
		Manhack[manId].target.Set(attacker);

	if (Manhack[manId].health <= 0.0)
	{
		Manhack[manId].Kill();

		Call_StartForward(NPCKilled);
		Call_PushArray(Manhack[manId].hull, sizeof FObject);
		Call_PushString("npc_healdrone"); //npc classname
		Call_PushArray(Manhack[manId].owner, sizeof FClient);
		Call_Finish();
	}

	return Plugin_Continue;
}

bool FilterPlayers(int entityId, int mask, int client)
{
	FClient player;
	player.Set(entityId);

	if (player.Valid()) // Do not allow other players to block the trace
		return entityId == client;

	FObject entity;
	entity.Set(entityId);

	if (entity.Cast("prop_physics_multiplayer"))
	{
		if (IsManhack[entityId])
			return false;
	}

	return true;
}

// heals our player
void HealPlayer(FClient patient, FClient healer, FHealDrone drone)
{
	patient.AddHealth(RoundFloat(drone.healing), 1.20); // 20% overheal

	if (patient.GetHealth() < patient.GetMaxHealth())
		drone.healingtotal += RoundFloat(drone.healing);

	if (drone.DisplayTimer.Expired())
	{
		if (drone.event)
		{
			drone.DisplayTimer.Loop();
			if (healer.Valid())
			{
				Event healing = CreateEvent("player_healed", true);

				//setup components for event
				healing.SetInt("patient", patient.userid);
				healing.SetInt("healer", healer.userid);
				healing.SetInt("amount", drone.healingtotal);

				drone.healingtotal = 0;

				healing.Fire(false);
			}
		}
		drone.event = patient.GetHealth < patient.GetMaxHealth();
	}
}
