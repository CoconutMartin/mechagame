class_name WeaponPartSync
extends Node
## Keeps the HP part of a hand weapon in step with the weapon (user rules 2026-10-17): a weapon on the ground
## takes no damage and keeps the HP it had, and the next hand that takes it gets that HP.
##   Released (Tab drop, knock-down, death): the part "Weapon R" / "Weapon L" and its hitboxes leave the mech
##   (MechHealth.detach_weapon_part), and the HP left is kept on the weapon (MechWeapon.part_hp).
##   Equipped (picked up): the part comes back with that HP (or the full HP of a weapon that never took
##   damage) and new hitboxes on the model nodes.
## A child of MechHealth (MechHealth makes it). A two-hand weapon is the right part ("Weapon R").

@export var health: MechHealth
@export var weapons: WeaponController


func _ready() -> void:
	weapons.hand_weapon_released.connect(_on_released)
	weapons.hand_weapon_equipped.connect(_on_equipped)


static func key_of(is_right: bool) -> String:
	return "Weapon R" if is_right else "Weapon L"


func _on_released(is_right: bool, weapon: MechWeapon) -> void:
	var left_over := health.detach_weapon_part(key_of(is_right))
	if left_over >= 0.0 and is_instance_valid(weapon):
		weapon.part_hp = left_over


func _on_equipped(is_right: bool, weapon: MechWeapon) -> void:
	if weapon.data == null or weapon.data.hp <= 0.0:
		return
	var nodes: Array[Node3D] = weapons.right_weapon_nodes() if is_right else weapons.left_weapon_nodes()
	var value := weapon.part_hp if weapon.part_hp >= 0.0 else weapon.data.hp
	health.attach_weapon_part(key_of(is_right), weapon.data.hp, value, nodes)
	weapon.part_hp = -1.0
