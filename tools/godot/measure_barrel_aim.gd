extends SceneTree
## Barrel against crosshair probe (user request 2026-11-04: "shooting while kneeling with autocannon: make the
## forearm/shoulder adjust so that the firearm aligns with the crosshair"). For each weapon, stance (stand / kneel) and
## camera pitch the player holds the aim key (and the trigger when FIRE=1), and each frame (after the skeleton update)
## the probe measures the angle between the barrel (the muzzle's -Z, or the weapon's -Z without a Muzzle node) and the
## line from the muzzle to the aim point (MechAim.aim_point, the point the shots fly to). It prints the mean and largest
## angle over the last SAMPLE frames, split into the vertical (pitch) and the horizontal (yaw) part, and the distance.
## Exit code 1 when a case (stand or kneel) is above MAX_DEG. A close aim point (10 m and less) can stay above it where the arm
## cannot turn the forearm far enough; use PITCHES with farther points for the pass check.
## The trigger is held to raise a one-hand gun; the gun cannot fire (a long reload) unless FIRE=1, so no recoil moves the aim.
## TRANSITION=1: the kneel starts when the sampling starts (aim and trigger held), so the sample covers the way down.
## Environment: ALIGN=0 (the forearm gun alignment and the one-hand gun convergence off: the before numbers), HAND=left (the weapon in the left hand), YAW (degrees the camera turns to the left before the sample, default 0), WEAPONS (comma list of data/weapons names, default auto_cannon,heavy_rifle,smg,beam_rifle),
##   PITCHES (comma list of camera pitches in degrees, default 0,-12,8), FIRE=1 (real shots, with recoil), MAX_DEG (default 1.5),
##   SAMPLE (frames, default 40).
##   godot --headless --path . --fixed-fps 60 --script res://tools/godot/measure_barrel_aim.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures := 0


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
			node.visible = false
	var names := (OS.get_environment("WEAPONS") if OS.get_environment("WEAPONS") != "" else "auto_cannon,heavy_rifle,smg,beam_rifle").split(",", false)
	var pitches := (OS.get_environment("PITCHES") if OS.get_environment("PITCHES") != "" else "0,-12,8").split(",", false)
	var max_deg := float(OS.get_environment("MAX_DEG")) if OS.get_environment("MAX_DEG") != "" else 1.5
	for weapon_name in names:
		for pitch_text in pitches:
			var pitch := float(pitch_text)
			var stand := await _case(switcher, weapon_name, pitch, false)
			var kneel := await _case(switcher, weapon_name, pitch, true)
			var ok: bool = kneel.max <= max_deg and stand.max <= max_deg
			print(("ok   " if ok else "FAIL ") + "%s pitch %+.0f: stand mean %.2f max %.2f (v %.2f h %.2f) | kneel mean %.2f max %.2f (v %.2f h %.2f) | dist %.0f m / %.0f m" % [
					weapon_name, pitch, stand.mean, stand.max, stand.v, stand.h, kneel.mean, kneel.max, kneel.v, kneel.h, stand.dist, kneel.dist])
			if not ok:
				_failures += 1
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## Returns {mean, max, v, h, dist}: the barrel-to-aim-line angle in degrees (v and h are the mean absolute pitch and yaw parts).
func _case(switcher: LoadoutSwitcher, weapon_name: String, pitch: float, kneel: bool) -> Dictionary:
	var loadout := switcher.current_loadout.duplicate() as Loadout
	var left := OS.get_environment("HAND") == "left"
	loadout.weapon_right = null if left else load("res://data/weapons/%s.tres" % weapon_name) as WeaponData
	loadout.weapon_left = load("res://data/weapons/%s.tres" % weapon_name) as WeaponData if left else null
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var player := switcher.mech
	var rig := player.get_node("CameraRig") as MechCameraRig
	var controller := player.get_node("WeaponController") as WeaponController
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if OS.get_environment("ALIGN") == "0":
		(player.find_child("ArmRig", true, false) as SkeletalArmRig).align_forearm_gun = false
		controller.weapon_pose.converge = false
	var transition := OS.get_environment("TRANSITION") == "1"
	if kneel and not transition:
		Input.action_press("crouch")
		await _frames(2)
		Input.action_release("crouch")
		await _frames(100)
	Input.action_press("aim")
	Input.action_press("use_left_arm" if left else "use_right_arm")
	rig._target_pitch = deg_to_rad(pitch)
	rig._pitch_spring.value = deg_to_rad(pitch)
	var yaw_turn := float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 0.0
	rig._target_yaw += deg_to_rad(yaw_turn)
	for i in 120:
		if not OS.get_environment("FIRE") == "1":
			(controller.left_weapon if left else controller.right_weapon).reload_left = 1000.0
		rig._target_pitch = maxf(deg_to_rad(pitch), rig.get_min_pitch())
		await _frames(1)
	var fire := OS.get_environment("FIRE") == "1"
	if kneel and transition:
		Input.action_press("crouch")
		await physics_frame
		Input.action_release("crouch")
	var sample := int(OS.get_environment("SAMPLE")) if OS.get_environment("SAMPLE") != "" else 40
	var shots := [0]
	(controller.left_weapon if left else controller.right_weapon).fired.connect(func() -> void: shots[0] += 1)
	var angles: Array[float] = []
	var verticals: Array[float] = []
	var horizontals: Array[float] = []
	var dist := 0.0
	for i in sample:
		rig._target_pitch = maxf(deg_to_rad(pitch), rig.get_min_pitch())
		var weapon := controller.left_weapon if left else controller.right_weapon
		if not fire:
			weapon.reload_left = 1000.0
		await physics_frame
		await skeleton.skeleton_updated
		# The gun's own muzzle node (a forearm gun's model hangs on the forearm, not under the weapon node).
		var muzzle := SkeletalHeadSteady._muzzle_of(weapon)
		var barrel := -(muzzle.global_basis.z if muzzle != null else weapon.global_basis.z).normalized()
		var origin := muzzle.global_position if muzzle != null else weapon.global_position
		var line: Vector3 = (player.get_node("MechAim") as MechAim).aim_point - origin
		dist = line.length()
		line = line.normalized()
		angles.append(rad_to_deg(barrel.angle_to(line)))
		# Vertical part: the difference of the elevations; horizontal part: the difference of the headings.
		verticals.append(absf(rad_to_deg(asin(clampf(barrel.y, -1.0, 1.0)) - asin(clampf(line.y, -1.0, 1.0)))))
		horizontals.append(absf(rad_to_deg(wrapf(atan2(barrel.x, barrel.z) - atan2(line.x, line.z), -PI, PI))))
	Input.action_release("use_left_arm" if left else "use_right_arm")
	Input.action_release("aim")
	if OS.get_environment("TRACE") == "1":
		var w := controller.left_weapon if left else controller.right_weapon
		var wp := controller.left_pose if left else controller.weapon_pose
		print("  convergence turn yaw %.1f pitch %.1f deg, last measured error %.1f deg" % [rad_to_deg(wp.converge_trim.x), rad_to_deg(wp.converge_trim.y), wp.converge_error_deg])
		var arm_rig := player.find_child("ArmRig", true, false) as SkeletalArmRig
		if arm_rig != null:
			print("  arm rig alignment: before %.2f after %.2f deg (right), hinge pitch/turn/bend %s" % [arm_rig.align_error_before_deg[1], arm_rig.align_error_after_deg[1], arm_rig._sides[1].hinge * 57.2958])
		print("  shots %d, can_use %s trigger %s ammo %d reload %.1f cooldown %.2f aim %.2f active %s" % [shots[0], w.can_use(), w.trigger_held, w.ammo, w.reload_left, w._cooldown, controller.weapon_pose.aim_amount, controller.active])
		print("  trace (%s, %s): %s" % [weapon_name, "kneel" if kneel else "stand", ", ".join(angles.map(func(a: float) -> String: return "%.1f" % a))])
	var mean := 0.0
	var largest := 0.0
	for a in angles:
		mean += a
		largest = maxf(largest, a)
	var v := 0.0
	var h := 0.0
	for a in verticals:
		v += a
	for a in horizontals:
		h += a
	var n := float(maxi(angles.size(), 1))
	if OS.get_environment("TRACE") == "1":
		print("  kneel amount at the end %.2f, pelvis y %.2f" % [player.kneel.amount, skeleton.global_transform.origin.y + skeleton.get_bone_global_pose(skeleton.find_bone(&"pelvis")).origin.y])
	if kneel:
		Input.action_press("crouch")
		await _frames(2)
		Input.action_release("crouch")
		await _frames(30)
	return {"mean": mean / n, "max": largest, "v": v / n, "h": h / n, "dist": dist}
