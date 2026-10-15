class_name UrbanProp
extends RigidBody3D
## A street prop of the urban map (car, bus, lamppost, person...). Its PropDef sets size, HP, mass and
## the reaction when a mech walks into it (see PropDef.Reaction). Layer 3 (props): weapons hit it,
## mech bodies pass through it; the Contact area finds the mechs.
## Physics (user answer 2026-10-12, "physics push"): the prop is a rigid body held still (frozen) until
## a mech moves it. Cars are kicked away (crushed when a mech comes down on them), the bus is pushed
## along and slows the mech; a moving prop knocks other props loose, collides with the world and the
## other props, then is held still again when it comes to rest.
## Scene layout: this body, a CollisionShape3D, a Pivot node at the base that holds every mesh
## (the reactions turn, squash or move it) and a Contact Area3D.
## Weapons: at 0 HP the prop breaks (BEND and FALL props bend or fall instead).

@export var def: PropDef
## Kick speed per m/s of mech speed for a light prop (heavier props less: x 10 / (10 + mass t)), and
## the smallest kick speed (m/s).
@export var kick_per_speed: float = 1.3
@export var min_kick_speed: float = 3.0
## Upward kick speed (m/s), random between these.
@export var kick_lift: Vector2 = Vector2(1.5, 4.0)
## A mech coming down faster than this (m/s) crushes a CRUSH prop instead of kicking it.
@export var crush_fall_speed: float = 2.0
## PUSH props: how much of the mech's speed the prop takes while the mech pushes it (times mech mass /
## (mech mass + prop mass)).
@export var push_share: float = 0.9
## A moving prop faster than this (m/s) knocks a still prop it hits loose.
@export var knock_speed: float = 3.0
## Seconds slower than rest_speed (m/s) before a moving prop is held still again.
@export var rest_time: float = 1.5
@export var rest_speed: float = 0.3

var hp: float = 0.0
## Set once a one-time reaction played (crush, bend, break, fall).
var done: bool = false

var _pivot: Node3D
var _contact: Area3D
var _push_wait: float = 0.0
var _still_time: float = 0.0
## Mech body RIDs this prop does not collide with for a moment (the mech that kicked it).
var _exceptions: Array[RID] = []


func _ready() -> void:
	if def == null:
		return
	hp = def.hp
	mass = maxf(def.mass_t, 0.02)
	# Kinematic, not static: with Jolt a body frozen as static did not collide with the mech hitboxes
	# after it started moving.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_pivot = get_node_or_null(^"Pivot") as Node3D
	_contact = get_node_or_null(^"Contact") as Area3D
	if _contact != null:
		_contact.body_entered.connect(_on_body_entered)
		_contact.monitoring = def.reaction != PropDef.Reaction.NONE
	body_entered.connect(_on_prop_contact)


func _physics_process(delta: float) -> void:
	_push_wait = maxf(_push_wait - delta, 0.0)
	if def != null and def.reaction == PropDef.Reaction.PUSH and _contact != null and not done:
		for body in _contact.get_overlapping_bodies():
			if body is Mech:
				_push_along(body as Mech, delta)
	if freeze:
		return
	# Back to still when it lies at rest (cheap, and the bus does not drift).
	if linear_velocity.length() < rest_speed and angular_velocity.length() < rest_speed:
		_still_time += delta
		if _still_time > rest_time:
			_hold_still()
	else:
		_still_time = 0.0


func get_pivot() -> Node3D:
	return _pivot


## True while the prop moves as a physics body.
func is_moving() -> bool:
	return not freeze


func on_hit(damage: float, _from: Vector3 = Vector3.INF) -> void:
	if done or def == null:
		return
	hp -= damage
	if hp > 0.0:
		return
	var away := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	match def.reaction:
		PropDef.Reaction.BEND:
			_play(away, 8.0, null)
		PropDef.Reaction.FALL:
			_play(away, 8.0, null)
		_:
			done = true
			PropBreak.play(self, away, 4.0)


## Lets the prop move and gives it this velocity change (m/s). kicker: the mech that moved it (its
## body does not collide with the prop for a moment).
func kick(velocity_change: Vector3, kicker: Mech = null) -> void:
	_set_moving()
	if kicker != null:
		_except(kicker)
	apply_central_impulse(velocity_change * mass)
	apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * mass * 0.6)


func _set_moving() -> void:
	_still_time = 0.0
	if freeze:
		freeze = false
		# A kinematic body keeps the speed of its last move (a teleport would launch it).
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		contact_monitor = true
		max_contacts_reported = 4
		# A flying prop hurts the mechs it hits a little (minor damage).
		DebrisHurt.attach(self)
	sleeping = false


func _hold_still() -> void:
	freeze = true
	contact_monitor = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_still_time = 0.0


func _except(mech: Mech) -> void:
	for rid in mech.get_hit_exclude():
		if not _exceptions.has(rid):
			PhysicsServer3D.body_add_collision_exception(get_rid(), rid)
			_exceptions.append(rid)
	get_tree().create_timer(1.0, false).timeout.connect(_clear_exceptions)


func _clear_exceptions() -> void:
	if not is_inside_tree():
		return
	for rid in _exceptions:
		PhysicsServer3D.body_remove_collision_exception(get_rid(), rid)
	_exceptions.clear()


## A moving prop that hits a still one knocks it loose with part of its speed.
func _on_prop_contact(body: Node) -> void:
	var other := body as UrbanProp
	if other == null or not other.freeze or other.done or linear_velocity.length() < knock_speed:
		return
	if other.def != null and other.def.reaction in [PropDef.Reaction.BEND, PropDef.Reaction.FALL]:
		other._play.call_deferred(linear_velocity.normalized(), linear_velocity.length(), null)
		return
	var share := mass / (mass + other.mass)
	other.kick.call_deferred(linear_velocity * share * 0.8)


func _on_body_entered(body: Node3D) -> void:
	var mech := body as Mech
	if mech == null or done or _push_wait > 0.0:
		return
	# A prop already flying is not kicked again by the mech it flies into: it hits its hitboxes
	# (DebrisHurt). PUSH props keep moving with the mech (_push_along).
	if not freeze and linear_velocity.length() > knock_speed:
		return
	var flat := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	var away := global_position - mech.global_position
	away.y = 0.0
	var direction := flat.normalized() if flat.length() > 0.5 else away.normalized()
	# Deferred: nodes cannot be added or moved during the physics contact step.
	_play.call_deferred(direction, flat.length(), mech)


func _play(direction: Vector3, speed: float, mech: Mech) -> void:
	if done:
		return
	match def.reaction:
		PropDef.Reaction.CRUSH:
			if mech != null and mech.velocity.y < -crush_fall_speed:
				done = true
				PropCrush.play(self)
			else:
				_push_wait = 0.4
				_kick_from(direction, speed, mech)
		PropDef.Reaction.PUSH:
			_push_wait = 0.4
			_kick_from(direction, speed, mech)
		PropDef.Reaction.BEND:
			done = true
			PropBend.play(self, direction, speed)
		PropDef.Reaction.BREAK:
			done = true
			PropBreak.play(self, direction, speed)
		PropDef.Reaction.FALL:
			done = true
			PropFall.play(self, direction)
	if mech != null and def.shake > 0.0:
		var shake := mech.find_child("Camera", true, false) as CameraShake
		if shake != null:
			shake.add_shake(def.shake, def.shake * 0.5)


## Kicked away from the mech: faster for a fast mech, slower for a heavy prop.
func _kick_from(direction: Vector3, speed: float, mech: Mech) -> void:
	var along := maxf(speed * kick_per_speed * 10.0 / (10.0 + def.mass_t), min_kick_speed)
	kick(direction * along + Vector3.UP * randf_range(kick_lift.x, kick_lift.y) * 10.0 / (10.0 + def.mass_t), mech)


## A mech walking into a PUSH prop pushes it along: the prop takes the mech's speed (less for a heavy
## prop: mech mass / (mech mass + prop mass) x push_share), and the mech cannot walk faster than the prop
## into it, so it does not pass through.
func _push_along(mech: Mech, _delta: float) -> void:
	var flat := Vector3(mech.velocity.x, 0.0, mech.velocity.z)
	var toward := global_position - mech.global_position
	toward.y = 0.0
	if flat.length() < 0.3 or toward.length_squared() < 0.0001:
		return
	var dir := toward.normalized()
	var into := flat.dot(dir)
	if into <= 0.0:
		return  # Walking away from it.
	_set_moving()
	var share := push_share * mech.mass_tons / (mech.mass_tons + def.mass_t)
	var now := linear_velocity.dot(dir)
	var want := into * share
	if now < want:
		apply_central_impulse(dir * (want - now) * mass)
	# The mech walks no faster into the prop than the prop moves.
	var limit := maxf(now, 0.0)
	if into > limit:
		mech.velocity -= dir * (into - limit)
