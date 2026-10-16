extends SceneTree
## Flinch threshold test (user choice 2026-10-16: small 40, medium 100, large 200; hits under 40 add
## up to a small flinch, the sum falls to zero in 3 s). Hits the player's center torso and logs which
## hit clip starts. Headless:
##   godot --headless --path . --script res://tools/godot/test_flinch.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(40)
	var player := switcher.mech
	var hits := player.find_child("HitAnimation", true, false) as SkeletalHitAnimation
	player.health.max_hp["Torso C"] = 1.0e9
	player.health.hp["Torso C"] = 1.0e9
	# [name, damage per hit, hits, frames between hits]
	var cases := [["one 26 hit (SMG bullet)", 26.0, 1, 1], ["one 39 hit", 39.0, 1, 1],
			["one 40 hit", 40.0, 1, 1], ["one 90 hit (heavy rifle)", 90.0, 1, 1],
			["one 165 hit (auto cannon)", 165.0, 1, 1], ["one 225 hit", 225.0, 1, 1],
			["SMG stream: 26 every 6 frames x 10", 26.0, 10, 6], ["26 every 2 s x 3 (decays)", 26.0, 3, 120]]
	for case: Array in cases:
		await _frames(240)  # longer than the 3 s decay of the small hits
		var started: PackedStringArray = []
		var was_playing := hits.is_playing
		for i in int(case[2]):
			player.health.damage("Torso C", float(case[1]), player.global_position + Vector3.FORWARD * 50.0, &"bullet")
			for f in int(case[3]):
				await _frames(1)
				if hits.is_playing and (not was_playing or f == 0 and i > 0 and hits.get("_time") < 0.05):
					started.append("%s@hit%d" % [hits.clip.resource_path.get_file().get_basename(), i + 1])
				was_playing = hits.is_playing
		for f in 30:
			await _frames(1)
			if hits.is_playing and not was_playing:
				started.append("%s@after" % hits.clip.resource_path.get_file().get_basename())
			was_playing = hits.is_playing
		print("%s: %s" % [case[0], ", ".join(started) if not started.is_empty() else "no flinch"])
	quit()
