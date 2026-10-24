extends SceneTree
## Solves the rest and aim places of a one-hand gun in the game (user request 2026-10-24: the gun lies along
## the forearm, and the arm that holds it looks like the empty arm, so the shoulder blocks match). It runs the
## right-hand gun SOLVE_GUN (a weapon file name, default heavy_rifle) and changes its rest transform and its
## aim origin (WeaponPose) a few times from what it measures, then prints the values for the .tres file.
## Rest: the barrel turns to the forearm axis (the mean of the elbow-to-wrist bone line and the forearm
## armor's long axis, roll about the barrel SOLVE_ROLL degrees, + = top out) and the gun moves until the wrist
## is where the empty right arm's wrist is (SOLVE_WRIST, torso space, default the empty arm's place), with the
## shift SOLVE_SHIFT (x,y,z) added. Aim (SOLVE_AIM=1): the gun origin moves until the forearm is parallel to
## the aim line, or (SOLVE_AIM_WRIST=x,y,z, torso space) until the wrist is at that place, so guns share one arm. Not part of the game; the printed numbers go into data/weapons and tools/mech_gen.
##   SOLVE_GUN=smg godot --headless --path . --script res://tools/godot/measure_arms_solve.gd

const MAP := "res://maps/urban_small/urban_small.tscn"
const Probe := preload("res://tools/godot/measure_arms_probe.gd")

var _snap: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _env(key: String, fallback: String) -> String:
	return OS.get_environment(key) if OS.has_environment(key) else fallback


func _vec(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	var probe := Probe.new()
	# The empty arm first: its wrist is the place the gun arm should reach.
	var player := await _build(switcher, "-")
	var weapons := player.get_node("WeaponController") as WeaponController
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	var hook := _hook(probe, player, skeleton, weapons)
	skeleton.skeleton_updated.connect(hook)
	await _frames(100)
	var free_wrist := _torso_point(weapons, _snap.R.wr)
	print("empty right arm: wrist (torso space) %s, block tilt %.1f yaw %.1f top %.2f" % [free_wrist, _snap.R.block_tilt, _snap.R.block_yaw, _snap.R.block_top])
	skeleton.skeleton_updated.disconnect(hook)
	var gun_name := _env("SOLVE_GUN", "heavy_rifle")
	player = await _build(switcher, gun_name)
	weapons = player.get_node("WeaponController") as WeaponController
	skeleton = player.find_child("Skeleton3D", true, false) as Skeleton3D
	probe = Probe.new()
	hook = _hook(probe, player, skeleton, weapons)
	skeleton.skeleton_updated.connect(hook)
	var pose := weapons.weapon_pose
	for p in player.find_children("*", "WeaponPose", true, false):
		(p as WeaponPose).recoil = null
	var wrist_goal := _vec(_env("SOLVE_WRIST", "%f,%f,%f" % [free_wrist.x, free_wrist.y, free_wrist.z])) + _vec(_env("SOLVE_SHIFT", "0,0,0"))
	var roll := deg_to_rad(float(_env("SOLVE_ROLL", "0")))
	await _frames(60)
	var iterations := int(_env("SOLVE_STEPS", "16"))
	for i in iterations:
		var data := _measured(weapons)
		var rest: Transform3D = pose.rest_transform
		var grip := (weapons.right_weapon.get_node("GripRight") as Node3D).position
		# Half way to the forearm axis each step: the forearm moves a little when the gun turns.
		var axis: Vector3 = (rest.basis * Vector3.FORWARD).slerp(data.target, 0.5)
		var up := Vector3.UP
		var basis := Basis.looking_at(axis, up).rotated(axis, -roll)
		var error: Vector3 = wrist_goal - data.wrist
		var origin := rest * grip - basis * grip + error * 0.8
		pose.rest_transform = Transform3D(basis, origin)
		print("rest %d: gun vs bone %.1f (side %+.1f front %+.1f), vs armor %.1f | wrist error %.3f | block tilt %.1f yaw %.1f top %.2f" % [
				i, data.angle, data.side, data.front, data.armor_angle, error.length(), _snap.R.block_tilt, _snap.R.block_yaw, _snap.R.block_top])
		await _frames(45)
	var final := _measured(weapons)
	print("rest final: gun vs bone %.1f (side %+.1f front %+.1f), vs armor %.1f, wrist %s | block tilt %.1f yaw %.1f top %.2f elbow %s" % [
			final.angle, final.side, final.front, final.armor_angle, final.wrist, _snap.R.block_tilt, _snap.R.block_yaw, _snap.R.block_top,
			_torso_point(weapons, _snap.R.el)])
	print("REST_TRANSFORM %s" % _text(pose.rest_transform))
	if _env("SOLVE_AIM", "1") == "1":
		await _solve_aim(weapons, pose)
	quit()


func _hook(probe: RefCounted, player: Mech, skeleton: Skeleton3D, weapons: WeaponController) -> Callable:
	return func() -> void:
		_snap = probe.snapshot(player, skeleton, weapons)


func _solve_aim(weapons: WeaponController, pose: WeaponPose) -> void:
	Input.action_press("use_right_arm")
	var gun := weapons.right_weapon as MechWeapon
	# No shot kick on the camera (the aim would climb with every shot).
	gun.data.recoil_up_deg = 0.0
	gun.data.recoil_side_deg = 0.0
	var steps := int(_env("SOLVE_AIM_STEPS", "12"))
	var gain := float(_env("SOLVE_GAIN", "0.7"))
	for i in steps:
		for k in 45:
			gun.ammo = gun.data.magazine
			await physics_frame
			await process_frame
		var data := _measured(weapons)
		# Aim line: the gun axis. The forearm (elbow to wrist) should lie parallel to it: the wrist moves
		# by the part of the forearm vector that is off the line.
		var aim: Vector3 = data.gun
		var forearm: Vector3 = data.wrist - data.elbow
		var off := forearm - aim * forearm.dot(aim)
		if _env("SOLVE_AIM_WRIST", "") != "":
			# A fixed wrist place (torso space) instead: every gun then has the same arm at aim.
			pose.aim_origin += (_vec(_env("SOLVE_AIM_WRIST", "")) - data.wrist) * gain
		else:
			pose.aim_origin -= off * gain
		print("aim %d: gun vs bone %.1f deg | gun elev %.1f, forearm elev %.1f | block tilt R %.1f L %.1f, yaw R %.1f | elbow %s wrist %s" % [
				i, data.angle, _elev(aim), _elev(forearm), _snap.R.block_tilt, _snap.L.block_tilt, _snap.R.block_yaw, data.elbow, data.wrist])
	Input.action_release("use_right_arm")
	print("AIM_ANCHOR %s" % pose.aim_origin)


func _elev(v: Vector3) -> float:
	return rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))


func _build(switcher: LoadoutSwitcher, gun: String) -> Mech:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = null if gun == "-" else load("res://data/weapons/%s.tres" % gun) as WeaponData
	loadout.weapon_left = null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(40)
	return switcher.mech


## Torso-space numbers of the right arm and gun from the last snapshot.
func _measured(weapons: WeaponController) -> Dictionary:
	var right: Dictionary = _snap.R
	var body: Transform3D = _snap.body
	var to_torso := weapons.torso.global_transform.affine_inverse() * body
	var out := {}
	out.wrist = to_torso * right.wr
	out.elbow = to_torso * right.el
	var bone := (to_torso.basis * (right.fore_dir as Vector3)).normalized() if right.has("fore_dir") else Vector3.ZERO
	var armor := (to_torso.basis * (right.armor_dir as Vector3)).normalized() if right.has("armor_dir") else Vector3.ZERO
	out.gun = (to_torso.basis * (right.gun_dir as Vector3)).normalized() if right.has("gun_dir") else Vector3.ZERO
	out.target = (bone + armor).normalized() if right.has("fore_dir") else Vector3.FORWARD
	out.angle = right.gun_angle if right.has("gun_angle") else 0.0
	out.side = right.gun_side if right.has("gun_side") else 0.0
	out.front = right.gun_front if right.has("gun_front") else 0.0
	out.armor_angle = right.armor_angle if right.has("armor_angle") else 0.0
	return out


func _torso_point(weapons: WeaponController, body_point: Vector3) -> Vector3:
	return weapons.torso.global_transform.affine_inverse() * (_snap.body as Transform3D) * body_point


func _text(t: Transform3D) -> String:
	var b := t.basis
	var v := [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, t.origin.x, t.origin.y, t.origin.z]
	var parts: PackedStringArray = []
	for x: float in v:
		parts.append(String.num(snappedf(x, 0.0000001), 7))
	return "Transform3D(" + ", ".join(parts) + ")"
