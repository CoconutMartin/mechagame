extends SceneTree
## Writes each arm part's jointed hand place into its ArmPart .tres, read from the mech scene of its own rig, so the arm's hand fits on any mech.
## Run after a change to an arm's rig or wrist. Headless:
##   godot --headless --path . --script res://tools/godot/write_arm_hand_data.gd

const MECHS := {
	"res://scenes/mech/sanggigilid.tscn": ["res://data/parts/sanggigilid/sanggigilid_arm_l.tres", "res://data/parts/sanggigilid/sanggigilid_arm_r.tres"],
	"res://scenes/mech/haliya.tscn": ["res://data/parts/haliya/haliya_arm_l.tres", "res://data/parts/haliya/haliya_arm_r.tres"],
}


func _initialize() -> void:
	for scene_path: String in MECHS:
		var mech := (load(scene_path) as PackedScene).instantiate()
		var control := mech.get_node("MechHandControl") as MechHandControl
		var left := load(MECHS[scene_path][0]) as ArmPart
		left.hand_transform = control.hand_left.transform
		left.wrist_pin = control.wrist_pin_left
		left.hand_shift = control.hand_shift_left
		var right := load(MECHS[scene_path][1]) as ArmPart
		right.hand_transform = control.hand_right.transform
		right.wrist_pin = control.wrist_pin_right
		right.hand_shift = control.hand_shift_right
		print(scene_path, " pins ", left.wrist_pin, " ", right.wrist_pin, " save ", error_string(ResourceSaver.save(left)), " ", error_string(ResourceSaver.save(right)))
		mech.free()
	quit()
