class_name ForearmGunWeapon
extends GunWeapon
## A gun held like a baton under the right forearm (Auto Cannon, new mech). The root is the fist target
## for the arm IK (GripRight); the model ("Mount", with the muzzle) moves under the forearm: the butt
## at the elbow, the grip handle in the palm, the muzzle past the hand. The arm takes the heavy rifle's
## rest and hip-fire places. Held like a tonfa: the handle goes through the fist from the
## pinky side (the hand's index-to-pinky line, from the arm rig), the body lies along the forearm.

## The heavy rifle's grip place in its model (GripRight): the fist goes there in the rifle poses.
@export var rifle_grip: Vector3 = Vector3(0.0, -0.33, -0.99)
## Turn of the cannon about the forearm (degrees, + = to the outer side), so it clears the thigh: at
## rest (arm hanging) and in the aim pose (hip fire). It blends between them with the aim amount.
@export var rest_roll_deg: float = 60.0
@export var aim_roll_deg: float = 60.0

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
	var ik := controller.arm_ik_right
	if ik.mid_joint == null:
		return
	if _mount.get_parent() != ik.mid_joint:
		_mount.reparent(ik.mid_joint, false)
	var grip := _mount.get_node("Model/Grip") as Node3D
	# Model axes on the forearm: muzzle (-Z) along the forearm (-Y); the handle (model -Y, from the
	# body to the fist) points from the pinky to the index finger.
	var across := Vector3(0.0, 0.0, -1.0)
	var rig := controller.mech.find_child("ArmRig", true, false)
	if rig != null and rig.has_method(&"hand_across"):
		across = rig.call(&"hand_across", true)
		if across.is_zero_approx():
			return  # The rig is not set up yet (first frame).
	var up := (across - Vector3.DOWN * across.dot(Vector3.DOWN)).normalized()
	var aim := controller.weapon_pose.aim_amount if controller.weapon_pose != null else 0.0
	up = Basis(Vector3.UP, deg_to_rad(lerpf(rest_roll_deg, aim_roll_deg, smoothstep(0.0, 1.0, aim)))) * up
	var back := Vector3.UP
	var basis := Basis(up.cross(back), up, back)
	_mount.transform = Transform3D(basis, Vector3(0.0, -ik.lower_length, 0.0) - basis * grip.position)


## The arm holds it like the heavy rifle: the weapon data poses are the rifle's, and the fist goes
## where the rifle's grip would be.
func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	return super(rest, aim, t) * Transform3D(Basis.IDENTITY, rifle_grip)
