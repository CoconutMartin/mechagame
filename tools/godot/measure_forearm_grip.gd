extends SceneTree
## Forearm gun grip probe (user request 2026-10-25: the Auto Cannon handle hung 0.18 m off the fist). Holds the Auto
## Cannon (or WEAPON) in the right hand, standing, and prints the fist miss (the fist hollow to the grip center)
## in the forearm joint's space: add it to ForearmGunWeapon.handle_offset (handle_offset_left) to put the handle in the fist.
## OFFSET="x,y,z" tries a handle_offset first; SIDE=L holds it in the left hand (handle_offset_left). Run:
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_forearm_grip.gd

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _run() -> void:
	change_scene_to_file("res://maps/urban_small/urban_small.tscn")
	await _frames(30)
	var switcher := current_scene.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var side := OS.get_environment("SIDE") if OS.has_environment("SIDE") else "R"
	var data := load("res://data/weapons/%s.tres" % (OS.get_environment("WEAPON") if OS.has_environment("WEAPON") else "auto_cannon")) as WeaponData
	loadout.weapon_right = data if side == "R" else null
	loadout.weapon_left = data if side == "L" else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(10)
	var weapons := switcher.mech.find_child("WeaponController", true, false) as WeaponController
	var gun := (weapons.right_weapon if side == "R" else weapons.left_weapon) as ForearmGunWeapon
	if OS.has_environment("OFFSET"):
		var parts := OS.get_environment("OFFSET").split(",")
		var tried := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		if side == "R":
			gun.handle_offset = tried
		else:
			gun.handle_offset_left = tried
	await _frames(90)
	var control := switcher.mech.find_child("MechHandControl", true, false) as MechHandControl
	var state: Dictionary = control._sides[side]
	var socket := state.socket as Node3D if is_instance_valid(state.socket) else null
	if socket == null:
		# No socket (the left hand): the model's Grip marker, with the handle radius.
		socket = gun.get_model().get_node("Model/Grip") as Node3D
		if not socket.has_meta(&"grip_radius"):
			socket.set_meta(&"grip_radius", control.handle_radius)
	var hand := state.hand as MechHand
	var hollow := MechHandControl.RIGHT_HOLLOW if side == "R" else MechHandControl.LEFT_HOLLOW
	hollow.z = MechHandControl.PALM_FACE_Z - control._radius(socket, control.grip_radius)
	hollow.x += float(socket.get_meta(&"hold_drop", 0.0)) * (-1.0 if side == "R" else 1.0)
	var fist := hand.global_transform * hollow
	var grip := socket.global_position
	var joint := gun.get_model().get_parent() as Node3D
	var local := joint.global_basis.orthonormalized().inverse() * (fist - grip)
	var now := gun.handle_offset if side == "R" else gun.handle_offset_left
	print("%s handle offset %s: miss %.3f m, in the forearm joint space %s -> try %s" % [side, now, local.length(), local, now + local])
	quit()
