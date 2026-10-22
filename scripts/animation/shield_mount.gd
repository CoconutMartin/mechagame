class_name ShieldMount
extends Node
## Places the shield. Shield down: on the outside of the left forearm, the long side along the
## forearm (held at the side). Shield up: across the front of the torso on a diagonal, so it covers
## the torso. Blends between the two with MechShield.amount. Runs after the arm IK.

@export var shield: MechShield
## The shield model. Its parent is the left elbow.
@export var shield_node: Node3D
## Shield place when down. A child of the left elbow, so it follows the forearm.
@export var rest_mount: Node3D
## Shield place when up. A child of the torso.
@export var cover: Node3D
## Size of the shield model.
@export var shield_scale: float = 1.2
## False: the shield stays on the forearm (rest_mount) when raised.
## True: it moves to the cover place (the guard; WeaponController turns it on for every shield, user request
## 2026-10-22: LMB raises the shield in front of the body).
@export var move_to_cover: bool = true
## The pose that knows the guard place. With it, the cover marker takes the guard place every frame.
var pose: ShieldPose


func _ready() -> void:
	# After the arm IK (10).
	process_physics_priority = 11


func _physics_process(_delta: float) -> void:
	var place := rest_mount.global_transform
	if pose != null and pose.has_guard and move_to_cover:
		# The guard path of ShieldPose (the shield moves out first, turns later). The first 10% of the raise
		# blend from the live forearm place to it, so the arm's sway does not make a jump.
		cover.transform = pose.guard
		var torso := cover.get_parent_node_3d()
		var path := torso.global_transform * pose.place_at(shield.amount)
		place = place.interpolate_with(path, smoothstep(0.0, 0.1, shield.amount))
	elif move_to_cover:
		place = place.interpolate_with(cover.global_transform, smoothstep(0.0, 1.0, shield.amount))
	shield_node.global_transform = Transform3D(place.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * shield_scale), place.origin)
