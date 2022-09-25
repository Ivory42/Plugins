////
///
/// Plugin still needs to be cleaned up quite a bit
///
/// This acts as a proof of concept for somewhat custom NPCs without the use of base_boss
/// Instead, these are entirely physics prop based and nothing else
///
/// This is almost exclusively for VSPR and as such the include will likely never be made public, but everything here can be replicated in normal sourcemod syntax
/// A lot here is done with SM 1.10 since FF2 needs a complete rewrite for 1.11. As such, some of my syntax may look weird since 1.10 isn't great with enum structs
/// However, I hate sourcepawn's normal syntax so I'm fine with dealing with the shortcomings
///
/// Theoretically, the model used for physics can be replaced with a box model to allow ground based NPCs to move on the ground and not roll around
/// Animation graphs can also be done to give proper animations... might try more with that for another plugin I have in mind with this
///
////


#include <vspr_stocks>
#include <SetCollisionGroup>

bool IsManhack[2049];

enum struct FManhack
{
	FObject hull;
	FObject model;

	FTimer DeployTime;
	FTimer SoundDelay;

	FClient owner;

	// Attack timers
	FTimer AttackDelay;
	FTimer AttackRate;

	// Logic timers
	FTimer WaitTimer;
	FTimer CheckTargetTimer;
	FTimer RoamingTimer;

	FVector targetLastPos;
	FVector roamPos;

	FClient target;

	bool waiting;
	bool roaming;
	bool roamingwait;

	float attacktime;

	int attacksleft;

	float speed;

	float damage;
	float health;
	float maxhealth;

	void Kill()
	{
		if (this.hull.Valid())
		{
			int id = this.hull.Get();
			IsManhack[id] = false;
			this.hull.Kill();
		}
	}

	int GetOwner()
	{
		return this.owner.Get();
	}

	void SetOwner(int client)
	{
		this.owner.Set(client);
	}

	bool HasTarget()
	{
		return this.target.Alive();
	}

	void GetPosition(FVector position)
	{
		this.hull.GetPosition(position);
	}
	void GetAngles(FRotator rotation)
	{
		this.hull.GetAngles(rotation);
	}
}

FManhack Manhack[2049];

public void OnPluginStart()
{
	RegAdminCmd("sm_manhack", CmdManhack, ADMFLAG_ROOT);
}

Action CmdManhack(int clientId, int args)
{
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

	SpawnManhack(spawnpos, client);

	return Plugin_Continue;
}

bool FilterSelf(int entity, int mask, int exclude)
{
	return (entity != exclude);
}

void SpawnManhack(FVector pos, FClient owner)
{
	FObject hull;
	hull.Create("prop_physics_override");

	hull.SetKeyValue("model", "models/manhack.mdl");

	hull.SetKeyValue("solid", "0"); // Doesn't seem to do anything at all..

	hull.Spawn();
	hull.Activate();

	hull.Teleport(pos, ConstructRotator(), ConstructVector());

	SetEntityCollisionGroup(hull.Get(), COLLISION_GROUP_NONE);

	int id = hull.Get();
	SDKHook(id, SDKHook_OnTakeDamage, OnTakeDamageManhack);
	
	// We need a physics model, but physics models don't seem to like having animations applied
	// So we'll just set this to be invisible and parent a dynamic prop for animations
	SetEntityRenderFx(id, RENDERFX_FADE_FAST);

	FObject model;
	model.Create("prop_dynamic_override");

	model.SetKeyValue("model", "models/manhack.mdl");

	model.Spawn();
	model.Activate();

	SetEntityCollisionGroup(model.Get(), COLLISION_GROUP_NONE);

	model.Teleport(pos, ConstructRotator(), ConstructVector());

	model.Attach(hull.Get());

	SetAnimation(model, "Deploy");

	Manhack[id].DeployTime.Set(2.0);
	Manhack[id].hull = hull;
	Manhack[id].model = model;
	Manhack[id].maxhealth = 100.0;
	Manhack[id].health = 100.0;
	Manhack[id].attacksleft = 3;
	//Manhack[id].attacktime = 3.0;

	Manhack[id].AttackDelay.Set(1.2);
	Manhack[id].AttackRate.Set(0.3);

	Manhack[id].SetOwner(owner.Get());

	Manhack[id].damage = 20.0;

	IsManhack[id] = true;
}

void SetAnimation(FObject model, const char[] sequence)
{
	SetVariantString(sequence);
	model.Input("SetAnimation");
}

public void OnEntityDestroyed(int entity)
{
	if (entity < 2049 && entity > 0)
		IsManhack[entity] = false;
}

public void OnGameFrame()
{
	int entity;
	while ((entity = FindEntityByClassname(entity, "prop_physics")) != -1)
	{
		if (IsManhack[entity])
			OnManhackTick(Manhack[entity]);
	}
}

void OnManhackTick(FManhack manhack)
{
	if (manhack.hull.Valid())
	{
		float maxspeed = 175.0;
		float acceleration = 3.0;
		if (manhack.DeployTime.Expired())
		{
			SetAnimation(manhack.model, "fly");

			// Set bodygroups so the blades are deployed
			manhack.model.SetProp(Prop_Data, "m_nBody", 1); // blades
			manhack.model.SetProp(Prop_Data, "m_nBody", 2); // blur
			//manhack.model.SetProp(Prop_Data, "m_nBody", 2, 1);
		}

		FRotator angle;
		manhack.GetAngles(angle);

		FVector velocity, pos, upwards;
		upwards = ConstructVector(0.0, 0.0, 12.0); // Try to counteract gravity

		FVector aimvector;

		manhack.GetPosition(pos);
		
		// All of this really needs to be cleaned up

		if (manhack.HasTarget())
		{
			FVector targetpos;

			if (!VisibleTarget(manhack, angle, pos))
			{
				float targetdistance = pos.DistanceTo(Vector_MakeFloat(manhack.targetLastPos));
				//manhack.CheckTargetTimer.Loop();
				if (targetdistance > 100.0)
				{
					manhack.waiting = false; // No longer waiting
					//PrintDistanceToLastPosition(manhack);
					targetpos = manhack.targetLastPos;
					manhack.WaitTimer.Set(3.0); // Wait five seconds before searching for new target
				}
				else if (targetdistance <= 105.0 && !manhack.waiting)
				{
					manhack.waiting = true;
					targetpos = pos;
				}
				else if (manhack.WaitTimer.Expired())
				{
					manhack.WaitTimer.Clear();
					manhack.target.userid = -1;
					manhack.waiting = false;
					manhack.roaming = false;
					//PrintToChatAll("Manhack lost target");
					return;
				}
			}
			else
			{
				if (manhack.CheckTargetTimer.Expired() && TargetInFOV(manhack.target, angle, pos))
				{
					//manhack.CheckTargetTimer.Loop();
					manhack.target.GetPosition(targetpos);
					targetpos.z += 65.0;
				}
				else if (TargetInFOV(manhack.target, angle, pos))
				{
					manhack.target.GetPosition(targetpos);
					targetpos.z += 65.0;
				}
				else
					targetpos = manhack.targetLastPos;
			}

			// Do not move unless we are far enough away from our destination and we are not waiting
			float destination = pos.DistanceTo(Vector_MakeFloat(targetpos)); // SM 1.10 doesn't allow structs to accept arguments of the same type... so they need to be converted to a float array instead
			if (destination > 70.0 && !manhack.waiting)
			{
				Vector_MakeFromPoints(pos, targetpos, aimvector);

				aimvector.Normalize();

				velocity = aimvector;
				Vector_GetAngles(aimvector, angle);

				manhack.speed += acceleration;
			}
			else if (!manhack.waiting && destination < 60.0)
			{
				Vector_MakeFromPoints(pos, targetpos, aimvector);

				aimvector.Normalize();

				velocity = aimvector;
				Vector_GetAngles(aimvector, angle);

				manhack.speed -= acceleration;
			}

			// Do our attack stuff
			if (manhack.AttackDelay.Expired())
			{
				if (destination <= 100.0)
				{
					if (manhack.AttackRate.Expired() && manhack.attacksleft)
					{
						FVector forwardpos;
						angle.GetForwardVector(forwardpos);
						forwardpos.Scale(120.0);
						forwardpos.Add(Vector_MakeFloat(pos));

						RayTrace attack = new RayTrace(pos, forwardpos, MASK_PLAYERSOLID, FilterSelf, manhack.hull.Get());
						if (attack.DidHit())
						{
							FClient client;
							client = ConstructClient(attack.GetHitEntity(), true);

							if (client.Valid())
							{
								//SDKHooks_TakeDamage(client.Get(), manhack.GetOwner(), manhack.GetOwner(), manhack.damage);
								DamagePlayer(client, ConstructClient(manhack.GetOwner(), true), manhack.damage);
								PlayImpactSound(manhack.hull);
							}
							else if (attack.GetHitEntity())
							{
								PlayHitWorld(manhack.hull);
							}
						}
						//attack.DebugTrace(1.0);
						delete attack;

						manhack.attacksleft--;
						if (!manhack.attacksleft)
						{
							manhack.AttackDelay.Loop();
							manhack.attacksleft = 3;
						}
						manhack.AttackRate.Loop();
					}
				}
			}
		}
		else
		{
			manhack.target = GetClosestTarget(manhack, manhack.hull);

			// No target found, let's start roaming around
			if (!manhack.HasTarget())
			{
				if (!manhack.roaming)
				{
					manhack.roaming = true;
					FRotator roamAngle;
					FVector roam;

					roamAngle.pitch = GetRandomFloat(-60.0, 60.0);
					roamAngle.yaw = GetRandomFloat(-180.0, 180.0);

					roamAngle.GetForwardVector(roam);
					roam.Scale(GetRandomFloat(200.0, 1000.0));

					roam.Add(Vector_MakeFloat(pos));

					FVector end;
					end = roam;

					RayTrace trace = new RayTrace(pos, end, MASK_SHOT, FilterSelf, manhack.hull.Get());
					if (trace.DidHit())
					{
						// Move position off surface a bit
						FVector hitpos;
						trace.GetEndPosition(hitpos);
						trace.GetNormalVector(roam);
						roam.Scale(50.0);
						roam.Add(Vector_MakeFloat(hitpos));
					}
					//trace.DebugTrace(5.0);
					delete trace;

					manhack.roamPos = roam;
				}
				else
				{
					//PrintCenterTextAll("Manhack Roaming");
					float distance = pos.DistanceTo(Vector_MakeFloat(manhack.roamPos));

					//PrintDistanceToLastPosition(manhack);

					if (distance <= 50.0 && !manhack.roamingwait)
					{
						manhack.roamingwait = true;
						manhack.RoamingTimer.Set(2.0);
						angle.pitch = 0.0;
					}
					else if (manhack.RoamingTimer.Expired())
					{
						manhack.RoamingTimer.Clear();
						manhack.roamingwait = false;
						manhack.roaming = false;
					}

					if (!manhack.roamingwait)
					{
						Vector_MakeFromPoints(pos, manhack.roamPos, aimvector);
						aimvector.Normalize();

						Vector_GetAngles(aimvector, angle);

						velocity = aimvector;

						manhack.speed += acceleration;
					}
				}
			}
			else
				manhack.waiting = false;
		}

		if (manhack.waiting || manhack.roamingwait)
		{
			manhack.speed -= acceleration * 2.0;
			if (manhack.speed < 0.0)
				manhack.speed = 0.0;
		}

		//PrintCenterTextAll("Manhack Target = %i", manhack.target.Get());

		if (manhack.speed > maxspeed)
			manhack.speed = maxspeed;

		if (manhack.speed < maxspeed * -1.0)
			manhack.speed = maxspeed * -1.0;

		velocity.Scale(manhack.speed);
		velocity.Add(Vector_MakeFloat(upwards));
		manhack.hull.SetVelocityRotation(angle, velocity);
	}
}

/*
void PrintDistanceToLastPosition(FManhack manhack)
{
	static float nextTime;
	FVector pos;
	manhack.GetPosition(pos);

	float distance = pos.DistanceTo(Vector_MakeFloat(manhack.targetLastPos));

	if (nextTime <= GetGameTime())
	{
		//PrintToChatAll("Distance to position = %.1f", distance);
		nextTime = GetGameTime() + 2.0;
	}

	RayTrace trace = new RayTrace(pos, manhack.targetLastPos, MASK_SHOT, FilterSelf, manhack.hull.Get());
	trace.DebugTrace(0.1);

	delete trace;
}
*/

bool TargetInFOV(FClient target, FRotator angles, FVector pos)
{
	FVector targetpos;
	target.GetPosition(targetpos);

	//manhack.GetPosition(pos);//

	FRotator direction;
	direction = CalcAngle(pos, targetpos);
	float angle = GetAngle(angles, direction);

	if (angle <= 70.0)
		return true;

	return false;
}

bool VisibleTarget(FManhack manhack, FRotator angles, FVector origin)
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
	{
		if (manhack.CheckTargetTimer.Expired())
			manhack.targetLastPos = targetPos;
	}
	else
		manhack.CheckTargetTimer.Set(0.8);

	return result;
}

void PlayHitWorld(FObject source)
{
	int number = GetRandomInt(1, 5);

	char sample[64];
	FormatEx(sample, sizeof sample, "npc/manhack/grind%i.wav", number);

	PrecacheSound(sample);
	EmitSoundToAll(sample, source.Get());
}

void PlayImpactSound(FObject source)
{
	int number = GetRandomInt(1, 3);

	char sample[64];
	FormatEx(sample, sizeof sample, "npc/manhack/grind_flesh%i.wav", number);

	PrecacheSound(sample);
	EmitSoundToAll(sample, source.Get());
}

any[sizeof FClient] GetClosestTarget(FManhack manhack, FObject entity) //Closest player to an object
{
	float targetDistance = 0.0;
	FClient closestTarget;

	for (int i = 1; i <= MaxClients; i++)
	{
		FClient target;
		target.Set(i);

		if (!target.Alive())
			continue;

		if (manhack.owner.Valid())
		{
			if (target.GetTeam() == manhack.owner.GetTeam())
				continue;
		}
		else
		{
			PrintCenterTextAll("No owner");
		}

		if (target.GetTeam() < 2)
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
			if (player.GetTeam() == owner.GetTeam())
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
		Manhack[manId].Kill();

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

	if (entity.Cast("prop_physics"))
	{
		if (IsManhack[entityId])
			return false;
	}

	return true;
}

// Well FF2 decided that bosses just can't be damaged with SDKHooks_TakeDamage... so we have to do this instead! Wow! I hate FF2!
void DamagePlayer(FClient victim, FClient attacker, float damage)
{
	if (attacker.Valid())
	{
		if (attacker.GetTeam() == victim.GetTeam()) // For other purposes.. don't damage teammates yada yada
			return;
	}

	char damagestring[16];
	IntToString(RoundFloat(damage), damagestring, sizeof damagestring);

	FObject pointhurt;
	pointhurt.Create("point_hurt");

	DispatchKeyValue(victim.Get(), "targetname", "halevic");
	pointhurt.SetKeyValue("DamageTarget", "halevic");
	pointhurt.SetKeyValue("Damage", damagestring);

	pointhurt.Spawn();
	if (attacker.Valid())
		pointhurt.Input("Hurt", attacker.Get());

	pointhurt.SetKeyValue("classname", "point_hurt");
	DispatchKeyValue(victim.Get(), "targetname", "noonespecial");

	pointhurt.Kill();
}
