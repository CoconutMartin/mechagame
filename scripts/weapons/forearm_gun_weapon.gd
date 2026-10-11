class_name ForearmGunWeapon
extends GunWeapon
## A gun held like a baton under the right forearm (Auto Cannon, new mech). The root is the fist target
## for the arm IK (GripRight); the model ("Mount", with the muzzle) moves under the forearm: the butt
## at the elbow, the grip handle in the palm, the muzzle past the hand. Aiming points the whole arm
## along the aim line from the shoulder. The forearm joint node points down -Y; its elbow bend side
## (-Z) is the forearm underside when the elbow points down.

## Arm stretch in the aim pose (part of the arm length; 1 = straight).
@export_range(0.5, 1.0) var aim_reach: float = 0.93

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
	# Model axes on the forearm: muzzle (-Z) along the forearm (-Y), top (+Y) away from it (-Z).
	var basis := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	_mount.transform = Transform3D(basis, Vector3(0.0, -ik.lower_length, 0.0) - basis * grip.position)


## Aim: the fist on the aim line from the shoulder, aim_reach of the arm length out.
func get_pose(rest: Transform3D, aim: Transform3D, t: float) -> Transform3D:
	var ik := controller.arm_ik_right
	var shoulder := ik.root_joint.position
	var direction := -aim.basis.z
	var aimed := Transform3D(aim.basis, shoulder + direction * (ik.upper_length + ik.lower_length) * aim_reach)
	return rest.interpolate_with(aimed, t)
