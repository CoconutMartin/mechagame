class_name ForearmGunWeapon
extends GunWeapon
## A gun held like a baton under the right forearm (Auto Cannon, new mech); in the left hand (user rule
## 2026-10-15) the same under the left forearm: it asks its controller for the arm that holds it
## (WeaponController.holding_arm_ik()). The root is the fist target
## for the arm IK (GripRight); the model ("Mount", with the muzzle) moves under the forearm: the butt
## behind the elbow, the grip handle in the palm, the muzzle past the hand. Held like a tonfa, straight
## under the fist (the user's arm drawing, 2026-10-12): the handle goes up through the fist, the body
## lies along the forearm.

## The heavy rifle's grip place in its model (GripRight): the fist goes there in the rifle poses.
@export var rifle_grip: Vector3 = Vector3(0.0, -0.33, -0.99)
## Turn of the cannon about the forearm (degrees, + = to the outer side), at rest and in the aim pose;
## it blends between them with the aim amount. 0 = straight under the fist (user's arm drawing).
@export var rest_roll_deg: float = 0.0
@export var aim_roll_deg: float = 0.0

@onready var _mount: Node3D = $Mount


func _ready() -> void:
	_muzzle = $Mount/Muzzle
	_flash = $Mount/Muzzle/MuzzleFlash


## The model (it sits on the forearm).
func get_model() -> Node3D:
	return _mount


func _update(delta: float) -> void:
	_attach_to_forearm()
	super(delta)


## Keeps the model under the right forearm (moved there once; placed every frame, because the arm
## rig sets the forearm length after the first frame).
func _attach_to_forearm() -> void:
	var ik := controller.holding_arm_ik()
	if ik.mid_joint == null:
		return
	if _mount.get_parent() != ik.mid_joint:
		_mount.reparent(ik.mid_joint, false)
	var grip := _mount.get_node("Model/Grip") as Node3D
	# Model axes on the forearm: muzzle (-Z) along the forearm (-Y); the model's +Y (from the fist to
	# the body) points to the forearm's lower side in the side view (the user's arm drawing: the cannon
	# straight under the fist, also in the front view): square to the forearm and to the torso's
	# sideways axis, toward the torso's down.
	var to_joint := ik.mid_joint.global_basis.orthonormalized().inverse()
	var up := Vector3.DOWN.cross(to_joint * controller.torso.global_basis.x)
	if up.dot(to_joint * -controller.torso.global_basis.y) < 0.0:
		up = -up
	if up.length_squared() < 0.01:
		# Forearm straight up or down: the hand's index-to-pinky line instead.
		var rig := controller.mech.find_child("ArmRig", true, false)
		if rig == null or not rig.has_method(&"hand_across"):
			return
		var across: Vector3 = rig.call(&"hand_across", not controller.left_arm_view)
		if across.is_zero_approx():
			return  # The rig is not set up yet (first frame).
		up = across - Vector3.DOWN * across.dot(Vector3.DOWN)
	up = up.normalized()
	var aim := controller.weapon_pose.aim_amount if controller.weapon_pose != null else 0.0
	var roll := deg_to_rad(lerpf(rest_roll_deg, aim_roll_deg, smoothstep(0.0, 1.0, aim)))
	up = Basis(Vector3.UP, -roll if controller.left_arm_view else roll) * up
	var back := Vector3.UP
	var basis := Basis(up.cross(back), up, back)
	_mount.transform = Transform3D(basis, Vector3(0.0, -ik.lower_length, 0.0) - basis * grip.position)


## The arm holds it like the heavy rifle: the weapon data poses are the rifle's, and the fist goes
## where the rifle's grip would be.
func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	return super(rest, aim, t) * Transform3D(Basis.IDENTITY, rifle_grip)
