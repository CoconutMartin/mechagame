class_name DummyMech
extends Node3D
## A target dummy that is a real mech (the current player mech model and parts), standing still
## at this node's place and facing this node's front (-Z). It has the full part damage (hitboxes,
## parts that break, falls, death), missiles can lock it, and a label shows the HP of its parts.
## When it is destroyed it is built again after respawn_time.

@export var mech_scene: PackedScene
@export var loadout: Loadout
## Seconds from the death to the new dummy.
@export var respawn_time: float = 6.0
## Height of the label bottom above the ground, in meters.
@export var label_height: float = 12.5

var mech: Mech

var _label: Label3D
var _respawn_left: float = 0.0


func _ready() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.025
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.font_size = 48
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)
	_spawn.call_deferred()


func _spawn() -> void:
	mech = mech_scene.instantiate() as Mech
	if loadout != null:
		(mech.get_node("MechAssembler") as MechAssembler).loadout = loadout
	# No pilot: no keyboard or mouse, no camera of its own.
	var camera := mech.get_node("CameraRig/Pitch/SpringArm/Camera") as Camera3D
	camera.current = false
	mech.name = "DummyMechBody"
	# Placed before it enters the scene, so it starts with its torso and legs facing forward.
	mech.transform = transform
	get_parent().add_child(mech)
	var input := mech.get_node("MechInput") as MechInput
	input.process_mode = Node.PROCESS_MODE_DISABLED
	input.aim_yaw = global_rotation.y
	mech.get_node("CameraRig").process_mode = Node.PROCESS_MODE_DISABLED
	mech.add_to_group(&"lockable")
	mech.health.destroyed.connect(_on_destroyed)


func _on_destroyed(_cause: String) -> void:
	mech.remove_from_group(&"lockable")
	_respawn_left = respawn_time


func _process(delta: float) -> void:
	_update_label()
	if _respawn_left <= 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		if is_instance_valid(mech):
			mech.queue_free()
		_spawn()


func _update_label() -> void:
	if not is_instance_valid(mech) or mech.health == null:
		_label.text = ""
		return
	_label.global_position = mech.global_position + Vector3.UP * label_height
	var health := mech.health
	if health.is_destroyed:
		_label.text = "DESTROYED"
		_label.modulate = Color(1.0, 0.3, 0.25)
		return
	_label.text = "Head %s   Booster %s\nTorso L %s  C %s  R %s\nArm L %s  R %s   Shield %s\nGroin %s   Leg L %s  R %s" % [
		_hp(health, "Head"), _hp(health, "Booster"), _hp(health, "Torso L"), _hp(health, "Torso C"),
		_hp(health, "Torso R"), _hp(health, "Arm L"), _hp(health, "Arm R"), _hp(health, "Shield"),
		_hp(health, "Groin"), _hp(health, "Leg L"), _hp(health, "Leg R")]
	_label.modulate = Color.WHITE


## HP of a part as text ("--" when destroyed, "" when the mech has no such part).
static func _hp(health: MechHealth, key: String) -> String:
	if not health.max_hp.has(key):
		return ""
	var now: float = health.hp[key]
	return str(roundi(now)) if now > 0.0 else "--"
