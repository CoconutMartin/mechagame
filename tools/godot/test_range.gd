extends SceneTree
## Damage falloff integration test (spec "weapon_damage_falloff_implementation_spec.md", 2026-10-16).
## Fires real bullets (scenes/weapons/bullet.tscn, as GunWeapon sets them up: damage, weapon_data) at a
## mech part hitbox (PartHitbox -> MechHealth.damage) from several distances, and checks the part HP
## lost against base damage x WeaponData.damage_factor(muzzle-to-impact distance): the falloff is
## applied once, before the part takes it. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_range.gd

const WEAPONS := ["shotgun", "smg", "heavy_rifle", "auto_cannon", "auto_cannon_shoulder"]
const BULLET := preload("res://scenes/weapons/bullet.tscn")
## The part box is this deep; the bullet hits its front face.
const BOX_DEPTH := 2.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var holder := Node3D.new()
	world.add_child(holder)
	var health := MechHealth.new()  # Not in the tree: only its part HP is used.
	health.add_part("Torso C", 1.0e9)
	var hitbox := PartHitbox.create(holder, "Torso C", AABB(Vector3(-20, -20, -BOX_DEPTH * 0.5), Vector3(40, 40, BOX_DEPTH)), health)
	health.add_hitbox("Torso C", hitbox)
	for name in WEAPONS:
		var data := load("res://data/weapons/%s.tres" % name) as WeaponData
		var s := data.effective_range_m
		var e := data.falloff_end_m
		var line := "%s (S %d m, E %d m, M %.2f, damage %.2f):" % [name, s, e, data.falloff_min, data.damage]
		for distance in [5.0, s, (s + e) * 0.5, e, e + 20.0, 400.0]:
			# The front face of the part is `distance` meters from the muzzle.
			holder.global_position = Vector3(0, 0, -(distance + BOX_DEPTH * 0.5))
			await physics_frame
			var before: float = health.hp["Torso C"]
			var bullet := BULLET.instantiate() as Bullet
			bullet.gravity = 0.0
			bullet.velocity = Vector3.FORWARD * data.projectile_speed
			bullet.damage = data.damage
			bullet.weapon_data = data
			world.add_child(bullet)
			bullet.global_position = Vector3.ZERO
			for i in int(distance / data.projectile_speed * 60.0) + 30:
				await physics_frame
			var lost: float = before - health.hp["Torso C"]
			var want := data.damage * data.damage_factor(distance)
			var ok := absf(lost - want) <= maxf(0.01 * want, 0.01)
			if not ok:
				_failures += 1
				print("FAIL: %s at %.1f m: part lost %.3f, want %.3f" % [name, distance, lost, want])
			line += "  %.1f m: %.2f (%.1f%%)" % [distance, lost, lost / data.damage * 100.0]
		print(line)
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
