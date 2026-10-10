extends SceneTree
## Builds scenes/mech/skeletal_mech.tscn and data/loadouts/new_mech.tres: the new mech (rigged model
## models/new_mech/new_mech_exploded.glb) as a playable mech that plays its own animations.
## Run from the project root:
##   godot --headless --path . --script res://tools/godot/build_skeletal_mech.gd
##
## It starts from the player mech scene and keeps its movement, input, aim and camera nodes; the
## part-built body (frame joints, parts, procedural animation, weapons, damage, falls) is removed and the
## rigged model goes in its place, played by SkeletalLocomotion; SkeletalMoves plays the run start and
## the run stops (clips from tools/mech_gen/new_mech_moves.py). Weapons come in a later phase.

const SOURCE := "res://scenes/mech/player_mech.tscn"
const MODEL := "res://models/new_mech/new_mech_exploded.glb"
const OUT_SCENE := "res://scenes/mech/skeletal_mech.tscn"
const OUT_LOADOUT := "res://data/loadouts/new_mech.tres"
## Part HP and the bones of each part.
const HIT_PARTS := "res://data/mechs/new_mech_hit_parts.tres"
## Run start and stop clips.
const MOVES := "res://data/mechs/new_mech_moves/"
## Player mech nodes that belong to the part-built body.
const REMOVE := ["MechAssembler", "Visual", "Animation", "FootLeveler", "WeaponController", "PartBreaker", "PowerDownPose", "MechFall", "BodyGroundClamp", "FallPose", "MechDeath", "MechShield"]
## Bone used for the camera size (MechCameraRig looks for a ShoulderL node).
const SHOULDER_BONE := "upper_arm_L"
## Where the aim ray starts on the body (chest, in front of the torso), m.
const AIM_ORIGIN := Vector3(0.0, 8.0, -1.0)
## Walking speed of this mech (m/s): the player mech's 9.1 less 15%. Boost is 1.5 times this.
const WALK_SPEED := 7.735
## Strafe and backward walk speed, as a part of the forward speed.
const STRAFE_SPEED := 0.9
const BACK_SPEED := 0.8
## Speed (m/s) at which each locomotion cycle plays alone: Walk, Slow_Run, Jog at walking speed, the
## full run at boost speed.
const PLAY_SPEEDS := [2.71, 4.6, WALK_SPEED, WALK_SPEED * 1.5]


func _initialize() -> void:
	var root := (load(SOURCE) as PackedScene).instantiate() as Mech
	root.scene_file_path = ""
	root.name = "SkeletalMech"
	root.walk_speed = WALK_SPEED
	root.strafe_speed_multiplier = STRAFE_SPEED
	root.back_speed_multiplier = BACK_SPEED
	root.boost_exit_style = Mech.BoostExit.ANIMATION
	var removed: Array[Node] = []
	var tops: Array[Node] = []
	for node_name: String in REMOVE:
		var node := root.get_node_or_null(node_name)
		if node != null:
			tops.append(node)
			removed.append_array([node] + node.find_children("*", "", true, false))
			root.remove_child(node)
	# Exports that pointed at removed nodes are cleared.
	for node in [root] + root.find_children("*", "", true, false):
		for prop in node.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and prop.type == TYPE_OBJECT:
				var value = node.get(prop.name)
				if value is Node and value in removed:
					node.set(prop.name, null)
	for node in tops:
		node.free()

	var visual := Node3D.new()
	visual.name = "Visual"
	root.add_child(visual)
	root.move_child(visual, 1)
	visual.owner = root
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.rotation.y = PI  # the model faces +Z (glTF front); the mech faces -Z
	visual.add_child(model)
	model.owner = root
	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.owner = root
	tree.anim_player = NodePath("../AnimationPlayer")

	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var shoulder := Marker3D.new()
	shoulder.name = "ShoulderL"
	visual.add_child(shoulder)
	shoulder.owner = root
	var bone := skeleton.find_bone(SHOULDER_BONE)
	shoulder.position = visual.to_local(skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin) \
		if skeleton.is_inside_tree() else model.transform * (skeleton.transform * skeleton.get_bone_global_rest(bone).origin)
	var aim := Marker3D.new()
	aim.name = "AimOrigin"
	visual.add_child(aim)
	aim.owner = root
	aim.position = AIM_ORIGIN

	var locomotion := SkeletalLocomotion.new()
	locomotion.name = "Locomotion"
	root.add_child(locomotion)
	locomotion.owner = root
	locomotion.mech = root
	locomotion.tree = tree
	locomotion.head_track = NodePath("MechRig/Skeleton3D:head")
	locomotion.play_speeds = PackedFloat32Array(PLAY_SPEEDS)

	var hips := SkeletalHipTurn.new()
	hips.name = "HipTurn"
	visual.add_child(hips)
	hips.owner = root
	hips.mech = root
	hips.model = model
	locomotion.hip_turn = hips

	var moves := SkeletalMoves.new()
	moves.name = "SkeletalMoves"
	root.add_child(moves)
	moves.owner = root
	moves.mech = root
	moves.input = root.get_node("MechInput")
	moves.locomotion = locomotion
	moves.hip_turn = hips
	moves.run_start = load(MOVES + "run_start.tres")
	var stops: Array[SkeletalMoveClip] = [load(MOVES + "run_stop_right.tres"), load(MOVES + "run_stop_left.tres")]
	moves.run_stops = stops
	moves.akira_left = load(MOVES + "akira_left.tres")
	moves.akira_right = load(MOVES + "akira_right.tres")

	var shake := root.get_node("CameraRig/Pitch/SpringArm/Camera") as CameraShake
	shake.animation_steps = locomotion

	var health := root.get_node("MechHealth") as MechHealth
	var hitboxes := SkeletalHitboxes.new()
	hitboxes.name = "SkeletalHitboxes"
	root.add_child(hitboxes)
	hitboxes.owner = root
	hitboxes.health = health
	hitboxes.model = model
	hitboxes.parts = load(HIT_PARTS)
	var death := SkeletalDeath.new()
	death.name = "SkeletalDeath"
	root.add_child(death)
	death.owner = root
	death.mech = root
	death.health = health
	death.tree = tree
	death.camera_shake = shake
	death.visual = visual
	var breaker := SkeletalPartBreaker.new()
	breaker.name = "SkeletalPartBreaker"
	root.add_child(breaker)
	breaker.owner = root
	breaker.mech = root
	breaker.health = health
	breaker.hitboxes = hitboxes
	breaker.camera_shake = shake

	var mech_aim := root.get_node("MechAim") as MechAim
	mech_aim.aim_origin = aim
	mech_aim.body_visual = visual

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_SCENE)
	print("BUILD scene ", OUT_SCENE, " ", error_string(err), " shoulder ", shoulder.position)
	var loadout := Loadout.new()
	loadout.display_name = "New Mech"
	loadout.mech_scene = load(OUT_SCENE)
	print("BUILD loadout ", OUT_LOADOUT, " ", error_string(ResourceSaver.save(loadout, OUT_LOADOUT)))
	root.free()
	quit()
