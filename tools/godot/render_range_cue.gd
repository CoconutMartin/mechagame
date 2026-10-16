extends SceneTree
## Crosshair range cue render (user choice 2026-10-16). Gives the player CUE_WEAPON in the right hand
## (default shotgun, effective 50 m) and saves the player camera view at the start point
## (range_cue.png): a target past the effective range shows faded brackets and "FAR".
## Render: CUE_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_range_cue.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("CUE_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://range_cue")
	DirAccess.make_dir_recursive_absolute(out)
	var weapon := OS.get_environment("CUE_WEAPON") if OS.get_environment("CUE_WEAPON") != "" else "shotgun"
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	var loadout := switcher.current_loadout.duplicate() as Loadout
	loadout.weapon_right = load("res://data/weapons/%s.tres" % weapon) as WeaponData
	switcher.rebuild(loadout, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	await _frames(60)
	var reticle: AimReticle = null
	for node in map.find_children("*", "AimReticle", true, false):
		reticle = node as AimReticle
	print("effective range %.0f m, distance %.0f m, out of range %s" % [reticle.get_effective_range(), reticle.get("_distance"), reticle.get("_out_of_range")])
	map.get_viewport().get_texture().get_image().save_png(out + "/range_cue.png")
	quit()
