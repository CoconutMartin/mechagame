extends SkeletonModifier3D
## Brace stance of the rigged mech for the shoulder cannons (user request 2026-10-22): the knees bend, the
## hips go down and back and the body leans a little forward, with the feet where they stand (the leg solve of
## CrouchPose). It follows ShoulderBrace.amount: 0 = standing, 1 = braced.
## WeaponController makes this node and puts it in the Skeleton3D just before the arm rig (ArmRig), so the arms
## and the shoulder cannons follow the lowered body. A skeleton modifier must be a child of the Skeleton3D.

## The brace to follow (WeaponController sets it).
var brace: Node
var mech: Mech

@export_group("Stance")
## Hip bend forward at full brace (degrees; the whole upper body).
@export var lean_deg: float = 3.0
## Extra bend forward at the waist (degrees).
@export var torso_lean_deg: float = 0.0
## The hips move back this far at full brace (m).
@export var hips_back: float = 0.3
## Inner knee angle at full brace (degrees; 180 = straight leg).
@export var knee_deg: float = 115.0
## The knees point this far to the side (0 = forward).
@export var knee_out: float = 0.0

var _jump_pose: SkeletalJumpPose
var _tries: int = 0


func _ready() -> void:
	_place.call_deferred()


## Moves the node just before the arm rig (it reparents itself under the skeleton first when it is not there).
func _place() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var arm_rig := skeleton.get_node_or_null("ArmRig")
	if arm_rig == null:
		# The arm rig moves into the skeleton in its own deferred call: try again next frame.
		_tries += 1
		if _tries < 10:
			get_tree().process_frame.connect(_place, CONNECT_ONE_SHOT)
		return
	skeleton.move_child(self, arm_rig.get_index())


func _process_modification_with_delta(_delta: float) -> void:
	if brace == null or mech == null:
		return
	var amount := smoothstep(0.0, 1.0, brace.amount as float)
	# The jump charge and the landing bend the same legs: the brace gives way to them.
	if _jump_pose == null or not is_instance_valid(_jump_pose):
		_jump_pose = mech.find_child("JumpPose", true, false) as SkeletalJumpPose
	if _jump_pose != null:
		amount *= 1.0 - clampf(maxf(_jump_pose.crouch, absf(_jump_pose.landing)), 0.0, 1.0)
	if amount <= 0.001:
		return
	CrouchPose.apply(get_skeleton(), amount, lean_deg, torso_lean_deg, hips_back, knee_deg, knee_out)
