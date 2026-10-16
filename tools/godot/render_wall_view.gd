extends SceneTree
## Camera wall test (user report 2026-10-16: a wall behind the player blocked the view). Puts the
## player with its back WALL_GAP meters (default 3) from the nearest building wall, facing away, and
## saves the player camera's view with CameraWallSeeThrough off (wall_off.png) and on (wall_on.png).
## Render (pictures in WALL_OUT, default user://wall_renders/):
##   WALL_OUT=/tmp/x xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --fixed-fps 60 --script res://tools/godot/render_wall_view.gd

const MAP := "res://maps/urban_small/urban_small.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _run() -> void:
	var out := OS.get_environment("WALL_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("user://wall_renders")
	DirAccess.make_dir_recursive_absolute(out)
	var gap := float(OS.get_environment("WALL_GAP")) if OS.get_environment("WALL_GAP") != "" else 3.0
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	var switcher := map.get_node("LoadoutSwitcher") as LoadoutSwitcher
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	# The nearest building's wall side that faces the start point.
	var start := Vector3(0, 0.5, 0)
	var best: AABB
	var best_distance := INF
	for building: BuildingGenerator in map.find_children("*", "BuildingGenerator", true, false):
		var box := AABB()
		var first := true
		for chunk: UrbanChunk in building.find_children("*", "UrbanChunk", true, false):
			var place := AABB(chunk.global_position - Vector3.ONE, Vector3.ONE * 2.0)
			box = place if first else box.merge(place)
			first = false
		if first:
			continue
		var distance := Vector2(box.get_center().x, box.get_center().z).length()
		if distance < best_distance:
			best_distance = distance
			best = box
	var center := best.get_center()
	# The side nearest to the start point: +X, -X, +Z or -Z.
	var sides := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var out_dir: Vector3 = sides[0]
	var near := INF
	for side: Vector3 in sides:
		var face := center + side * (best.size * 0.5).dot(side.abs())
		var d := Vector2(face.x - start.x, face.z - start.z).length()
		if d < near:
			near = d
			out_dir = side
	var face_point := center + out_dir * (best.size * 0.5).dot(out_dir.abs())
	var spot := Vector3(face_point.x, 0.5, face_point.z) + out_dir * (gap + 2.0)
	var yaw := atan2(-out_dir.x, -out_dir.z) + PI
	switcher.rebuild(switcher.current_loadout.duplicate() as Loadout, Transform3D(Basis(Vector3.UP, yaw), spot))
	await _frames(60)
	var player := switcher.mech
	var see := player.find_child("WallSeeThrough", true, false) as CameraWallSeeThrough
	print("player at %s, wall side %s, see-through node %s" % [player.global_position, out_dir, see != null])
	see.process_mode = Node.PROCESS_MODE_DISABLED
	see._show_all()
	await _frames(5)
	map.get_viewport().get_texture().get_image().save_png(out + "/wall_off.png")
	see.process_mode = Node.PROCESS_MODE_INHERIT
	await _frames(5)
	print("hidden chunks: %d" % see._hidden.size())
	map.get_viewport().get_texture().get_image().save_png(out + "/wall_on.png")
	quit()
