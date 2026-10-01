class_name FrameLayout
extends RefCounted
## Custom skeletons: each part model can bring its own joint places, so mechs of any size and mixed
## parts fit together. MechAssembler calls apply() before it attaches the parts.
## A part model brings joint places when its socket groups are not at the model origin (Blender
## .glb parts: the kit socket empties). Generated .tscn parts keep their groups at the origin and
## bring nothing: the frame keeps the places from the mech scene.
## Who decides what (the other parts follow):
##   legs  -> Lower (waist) place, HipL/R and KneeL/R
##   core  -> Torso height above the waist
##   arms  -> ShoulderL/R (from the torso) and ElbowL/R (upper arm length)
## The animation scripts measure the bone lengths from the frame when they start (FrameMeasure).


## Socket name -> place in mech space, from the top-level groups of a part scene. Empty when the
## part brings no joint places.
static func read(scene: PackedScene) -> Dictionary:
	var places := {}
	var model := scene.instantiate()
	for group in model.get_children():
		var node := group as Node3D
		if node == null or node.transform.origin.is_zero_approx():
			continue
		var socket := String(node.name).get_slice("_", 0).get_slice(".", 0)
		# The children of a group land on the socket without the group's turn, so the socket place
		# in mech space is the group origin seen from the group's turn (Blender kit: 180 degrees).
		places[socket] = node.transform.basis.inverse() * node.transform.origin
	model.free()
	return places


## Moves the frame sockets to the joint places of the loadout parts.
static func apply(frame: Node3D, loadout: Loadout) -> void:
	var lower := frame.find_child("Lower", true, false) as Node3D
	var torso := frame.find_child("Torso", true, false) as Node3D
	if lower == null or torso == null:
		return
	# Waist height of the mech scene: the core places its torso above this.
	var scene_waist := lower.position.y
	var legs := _places(loadout.legs)
	if legs.has("Lower"):
		lower.position = legs["Lower"]
	for side in ["L", "R"]:
		_set_local(frame, "Hip" + side, legs, "Lower")
		_set_local(frame, "Knee" + side, legs, "Hip" + side, true)
	var core := _places(loadout.core)
	if core.has("Torso"):
		var place: Vector3 = core["Torso"]
		torso.position = Vector3(place.x, lower.position.y + place.y - scene_waist, place.z)
	for pair in [["L", loadout.arm_left], ["R", loadout.arm_right]]:
		var arm := _places(pair[1])
		_set_local(frame, "Shoulder" + pair[0], arm, "Torso")
		_set_local(frame, "Elbow" + pair[0], arm, "Shoulder" + pair[0], true)


static func _places(part: PartData) -> Dictionary:
	if part == null or part.scene == null:
		return {}
	return read(part.scene)


## Sets a socket to its place from the part, measured from its parent socket in the same part.
## straight: the socket goes straight below its parent at the same distance (knees and elbows: the
## leg and arm IK bend the bones along -Y).
static func _set_local(frame: Node3D, socket_name: String, places: Dictionary, parent_name: String,
		straight: bool = false) -> void:
	if not places.has(socket_name) or not places.has(parent_name):
		return
	var socket := frame.find_child(socket_name, true, false) as Node3D
	if socket == null:
		return
	FrameMeasure.remember(socket)
	var offset := (places[socket_name] as Vector3) - (places[parent_name] as Vector3)
	socket.position = Vector3(0.0, -offset.length(), 0.0) if straight else offset
