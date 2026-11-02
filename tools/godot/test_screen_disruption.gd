extends SceneTree
## Screen disruption test (user request 2026-11-02): Shotgun 2 pellets fired at the player's mech start the
## ScreenDisruption effect, which fades to nothing; pellets that hit the ground near the player do not.
## SHOT=<png path>: also saves a picture at the hit (needs a renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/godot/test_screen_disruption.gd).
## Headless: godot --headless --path . --script res://tools/godot/test_screen_disruption.gd

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("PASS " if ok else "FAIL ") + text)
	if not ok:
		_fails += 1


func _fire(at: Vector3, from: Vector3) -> void:
	var data := load("res://data/weapons/shotgun_2.tres") as WeaponData
	for i in 9:
		var pellet := (load("res://scenes/weapons/pulse_pellet.tscn") as PackedScene).instantiate() as Bullet
		var direction := (at + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) - from).normalized()
		pellet.velocity = direction * data.projectile_speed
		pellet.damage = data.damage
		pellet.weapon_data = data
		current_scene.add_child(pellet)
		pellet.global_position = from


func _effect() -> ScreenDisruption:
	return current_scene.get_node_or_null("ScreenDisruption") as ScreenDisruption


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(60)
	var player := get_first_node_in_group(&"player") as Mech
	var chest := player.global_position + Vector3.UP * 6.0
	var from := chest - player.global_basis.z * 30.0
	# Near miss: into the ground 20 m away.
	_fire(from + Vector3.DOWN * 20.0 - player.global_basis.z * 5.0, from)
	await _frames(20)
	_check(_effect() == null or _effect().amount == 0.0, "pellets that miss the player give no disruption")
	_fire(chest, from)
	var peak := 0.0
	for i in 20:
		await _frames(1)
		if _effect() != null:
			peak = maxf(peak, _effect().amount)
		if peak > 0.0 and OS.has_environment("SHOT") and i % 1 == 0 and peak == _effect().amount:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("SHOT"))
	_check(peak > 0.3, "pellets on the player start the disruption (peak %.2f)" % peak)
	await _frames(70)
	_check(_effect() != null and _effect().amount == 0.0, "the disruption fades out within about 1 s (%.2f)" % (
			_effect().amount if _effect() != null else -1.0))
	print("SCREEN DISRUPTION: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)
