class_name DebrisHurt
extends Node
## Minor damage to a mech from flying debris (user answer 2026-10-12): rubble, broken prop pieces and
## kicked props that hit a mech part hitbox (layer 4) at speed hurt that part a little. Add it as a
## child of the debris body with DebrisHurt.attach(); it turns on the body's contact reports and its
## collision with the hitbox layer.

const HITBOX_LAYER := 8

## Damage per ton per m/s of the debris speed, and the limits of one hit.
@export var damage_per_ton_speed: float = 2.0
@export var min_damage: float = 2.0
@export var max_damage: float = 40.0
## Slower debris does nothing (m/s).
@export var min_speed: float = 5.0
## Seconds before the same piece can hurt again.
@export var cooldown: float = 0.5
## Top speed of the piece (m/s). The mech hitboxes move by animation, so physics can push a piece out of
## one very fast (400 m/s was seen); this keeps it believable.
@export var max_speed: float = 40.0

var _body: RigidBody3D
## Speed and mass from the last physics frame (the contact signal comes after the bounce).
var _speed: float = 0.0
var _wait: float = 0.0


## Lets body hurt mechs it hits. Returns the new node (or the one it already has).
static func attach(body: RigidBody3D) -> DebrisHurt:
	var existing := body.get_node_or_null(^"DebrisHurt") as DebrisHurt
	if existing != null:
		return existing
	var hurt := DebrisHurt.new()
	hurt.name = "DebrisHurt"
	body.add_child(hurt)
	return hurt


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		return
	_body.collision_mask |= HITBOX_LAYER
	_body.contact_monitor = true
	_body.max_contacts_reported = maxi(_body.max_contacts_reported, 4)
	_body.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_wait = maxf(_wait - delta, 0.0)
	if _body != null:
		if _body.linear_velocity.length() > max_speed:
			_body.linear_velocity = _body.linear_velocity.limit_length(max_speed)
		_speed = _body.linear_velocity.length()


func _on_body_entered(other: Node) -> void:
	var hitbox := other as PartHitbox
	if hitbox == null or _wait > 0.0 or _speed < min_speed:
		return
	_wait = cooldown
	hitbox.on_hit(clampf(_body.mass * _speed * damage_per_ton_speed, min_damage, max_damage))
