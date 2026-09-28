class_name GroupNodes
extends RefCounted
## Finds nodes in a group under one root node (for example the part models of one mech).


static func find(root: Node, group: StringName) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in root.get_tree().get_nodes_in_group(group):
		if node is Node3D and root.is_ancestor_of(node):
			found.append(node)
	return found
