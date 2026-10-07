class_name UrbanProp
extends StaticBody3D
## A street prop of the urban map (car, bus, lamppost...). Its PropDef sets size, HP and the
## reaction when a mech walks into it (see PropDef.Reaction). Layer 3 (props): weapons hit it,
## mech bodies pass through it; the Contact area finds the mechs.
## Scene layout: this body, a CollisionShape3D, a Pivot node at the base that holds every mesh
## (the reactions turn, squash or move it) and a Contact Area3D.
## Weapons: at 0 HP the prop breaks (BEND and FALL props bend or fall instead).

@export var def: PropDef

var hp: float = 0.0
## Set once the reaction played (PUSH props can be pushed again).
var done: bool = false

var _pivot: Node3D
var _push_wait: float = 0.0


func _ready() -> void:
	if def == null:
		return
	hp = def.hp
	_pivot = get_node_or_null(^"Pivot") as Node3D
	var contact := get_node_or_null(^"Contact") as Area3D
	if contact != null:
		contact.body_entered.connect(_on_body_entered)
		contact.monitoring = def.reaction != PropDef.Reaction.NONE


func _physics_process(delta: float) -> void:
	_push_wait = maxf(_push_wait - delta, 0.0)


func get_pivot() -> Node3D:
	return _pivot


func on_hit(damage: float) -> void:
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


func _on_body_entered(body: Node3D) -> void:
	var mech := body as Mech
	if mech == null or done or (def.reaction == PropDef.Reaction.PUSH and _push_wait > 0.0):
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
			done = true
			PropCrush.play(self)
		PropDef.Reaction.PUSH:
			_push_wait = 0.6
			PropPush.play(self, direction, speed)
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
