class_name MechSpawner
extends Node3D
## Places a mech (the current player mech model and parts) at this node's place, facing this
## node's front (-Z). It has the full part damage (hitboxes, parts that break, falls, death),
## missiles can lock it, and a label above it shows the HP of its parts. When it is destroyed it is
## built again after respawn_time, and it is built again when the player respawns (reset).
## Pilot NONE: a target dummy that stands still. Pilot AI: an enemy flown by AIPilot.

enum Pilot { NONE, AI }

@export var mech_scene: PackedScene
@export var loadout: Loadout
@export var pilot: Pilot = Pilot.NONE
## Optional. When the player respawns, this mech is built again too.
@export var player_respawner: PlayerRespawner
## Seconds from the death to the new mech.
@export var respawn_time: float = 6.0
## Height of the label bottom above the ground, in meters.
@export var label_height: float = 12.5
## Show the part HP label above the mech (off since 2026-10-22, user request: no enemy HP text on screen).
@export var show_label: bool = false

var mech: Mech
## False: no mech (the garage test buttons switch it). A reset or respawn does nothing then.
@export var active: bool = true

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
	_label.visible = show_label
	add_child(_label)
	add_to_group(&"mech_spawner")
	if player_respawner != null:
		player_respawner.respawned.connect(_reset)
	_spawn_if_active.call_deferred()


## Builds the mech again at the start place with full HP.
func _reset() -> void:
	_respawn_left = 0.0
	_remove_mech()
	if active:
		_spawn()


## Spawns (true) or removes (false) the mech.
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	_reset()


## The right arm weapon the mech is built with (the loadout's, or the mech scene's own).
func get_right_weapon() -> WeaponData:
	var base := loadout if loadout != null else _scene_loadout(mech_scene)
	return base.weapon_right if base != null else null


## Gives the mech another right arm weapon (garage test targets) and builds it again. A Fist also
## goes to the left hand (combos and A hooks need both fists). A two-hand weapon clears the left hand,
## and so does any other pick when the left hand holds a fist.
func set_right_weapon(weapon: WeaponData) -> void:
	var base := loadout if loadout != null else _scene_loadout(mech_scene)
	if base == null:
		return
	loadout = base.duplicate() as Loadout
	loadout.weapon_right = weapon
	if weapon != null and weapon.kind == WeaponData.Kind.FIST:
		loadout.weapon_left = weapon
	elif weapon != null and weapon.two_handed:
		loadout.weapon_left = null
	elif loadout.weapon_left != null and loadout.weapon_left.kind == WeaponData.Kind.FIST:
		loadout.weapon_left = null
	if active:
		_reset()


## The back pack the mech is built with (the loadout's, or the mech scene's own).
func get_back_pack() -> BackPackPart:
	var base := loadout if loadout != null else _scene_loadout(mech_scene)
	return base.back_pack if base != null else null


## Gives the mech another back pack (garage test targets: an AI with the Drone Pack launches drones) and builds it
## again.
func set_back_pack(pack: BackPackPart) -> void:
	var base := loadout if loadout != null else _scene_loadout(mech_scene)
	if base == null:
		return
	loadout = base.duplicate() as Loadout
	loadout.back_pack = pack
	if active:
		_reset()


## The loadout saved in a mech scene (its WeaponMount or MechAssembler), or null.
static func _scene_loadout(scene: PackedScene) -> Loadout:
	if scene == null:
		return null
	var state := scene.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			if state.get_node_property_name(node, property) == &"loadout":
				return state.get_node_property_value(node, property) as Loadout
	return null


## Name for the garage buttons.
func get_label() -> String:
	return "Enemy (AI)" if pilot == Pilot.AI else "Dummy"


func _remove_mech() -> void:
	if is_instance_valid(mech):
		# Free the name now, so the new mech gets it.
		mech.name = "OldMech"
		mech.leave_mech_layer()
		mech.queue_free()
	mech = null


func _spawn_if_active() -> void:
	if active:
		_spawn()


func _spawn() -> void:
	mech = mech_scene.instantiate() as Mech
	if loadout != null:
		LoadoutSwitcher.loadout_node(mech).set(&"loadout", loadout)
	# No keyboard, mouse or camera of its own.
	var camera := mech.get_node("CameraRig/Pitch/SpringArm/Camera") as Camera3D
	camera.current = false
	mech.name = "EnemyMechBody" if pilot == Pilot.AI else "DummyMechBody"
	# Placed before it enters the scene, so it starts with its torso and legs facing forward.
	mech.transform = transform
	get_parent().add_child(mech)
	var input := mech.get_node("MechInput") as MechInput
	input.process_mode = Node.PROCESS_MODE_DISABLED
	input.aim_yaw = global_rotation.y
	mech.get_node("CameraRig").process_mode = Node.PROCESS_MODE_DISABLED
	mech.add_to_group(&"lockable")
	mech.health.destroyed.connect(_on_destroyed)
	if pilot == Pilot.AI:
		var ai := AIPilot.new()
		ai.name = "AIPilot"
		ai.mech = mech
		ai.input = input
		ai.mech_aim = mech.get_node("MechAim") as MechAim
		mech.add_child(ai)


func _on_destroyed(_cause: String) -> void:
	mech.remove_from_group(&"lockable")
	_respawn_left = respawn_time
	_wait_for_fall.call_deferred()


## After SkeletalDeath picked its death clip: the wreck stays until the fall ends.
func _wait_for_fall() -> void:
	var death := mech.get_node_or_null("SkeletalDeath") as SkeletalDeath if is_instance_valid(mech) else null
	if death != null:
		_respawn_left = maxf(_respawn_left, death.get_fall_time())


func _process(delta: float) -> void:
	_update_label()
	if _respawn_left <= 0.0:
		return
	_respawn_left -= delta
	if _respawn_left <= 0.0:
		_remove_mech()
		if active:
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
	_label.modulate = Color(1.0, 0.55, 0.45) if pilot == Pilot.AI else Color.WHITE
	_label.text = "Head %s   Booster %s\nTorso L %s  C %s  R %s\nArm L %s  R %s   Shield %s\nGroin %s   Leg L %s  R %s" % [
		_hp(health, "Head"), _hp(health, "Booster"), _hp(health, "Torso L"), _hp(health, "Torso C"),
		_hp(health, "Torso R"), _hp(health, "Arm L"), _hp(health, "Arm R"), _hp(health, "Shield"),
		_hp(health, "Groin"), _hp(health, "Leg L"), _hp(health, "Leg R")]


## HP of a part as text ("--" when destroyed, "" when the mech has no such part).
static func _hp(health: MechHealth, key: String) -> String:
	if not health.max_hp.has(key):
		return ""
	var now: float = health.hp[key]
	return str(roundi(now)) if now > 0.0 else "--"
