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
## False: the shield stays on the forearm (rest_mount) when raised; the arm pose already covers
## (Sanggigilid, user's arm drawing 2026-10-12).
@export var move_to_cover: bool = true


func _ready() -> void:
	# After the arm IK (10).
	process_physics_priority = 11


func _physics_process(_delta: float) -> void:
	var t := smoothstep(0.0, 1.0, shield.amount) if move_to_cover else 0.0
	var place := rest_mount.global_transform.interpolate_with(cover.global_transform, t)
	shield_node.global_transform = Transform3D(place.basis.orthonormalized() * Basis.from_scale(Vector3.ONE * shield_scale), place.origin)
