extends SceneTree
## Effective range test (user choice 2026-10-16). For each gun in WEAPONS, fires single bullets at a
## damage receiver from several distances and logs the damage that arrives (full up to the effective
## range, then down to falloff_min at range_m, nothing past range_m). Headless:
##   godot --headless --path . --script res://tools/godot/test_range.gd

const WEAPONS := ["smg", "shotgun", "heavy_rifle", "auto_cannon"]
const BULLET := preload("res://scenes/weapons/bullet.tscn")


class Receiver extends StaticBody3D:
	var total: float = 0.0

	func on_hit(damage: float, _from: Vector3 = Vector3.INF, _kind: StringName = &"") -> void:
		total += damage


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var receiver := Receiver.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 40, 2)
	shape.shape = box
	receiver.add_child(shape)
	receiver.collision_layer = 8  # hitboxes
	world.add_child(receiver)
	for name in WEAPONS:
		var data := load("res://data/weapons/%s.tres" % name) as WeaponData
		var line := "%s (effective %d m, max %d m, damage %.1f):" % [name, data.effective_range_m, data.range_m, data.damage]
		for distance in [20.0, data.effective_range_m * 0.9, (data.effective_range_m + data.range_m) * 0.5, data.range_m * 0.98, data.range_m * 1.1]:
			receiver.total = 0.0
			receiver.global_position = Vector3(0, 0, -distance)
			await physics_frame
			var bullet := BULLET.instantiate() as Bullet
			bullet.gravity = 0.0
			bullet.velocity = Vector3.FORWARD * data.projectile_speed
			bullet.damage = data.damage
			bullet.weapon_data = data
			world.add_child(bullet)
			bullet.global_position = Vector3.ZERO
			for i in int(distance / data.projectile_speed * 60.0) + 30:
				await physics_frame
			line += "  %d m: %.1f (%.0f%%)" % [distance, receiver.total, receiver.total / data.damage * 100.0]
		print(line)
	quit()
