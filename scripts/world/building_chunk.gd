class_name BuildingChunk
extends StaticBody3D
## One block of a DestructibleBuilding (world layer 1). Weapons call on_hit(); the building keeps
## the HP rules. The block darkens as it takes damage.

var building: DestructibleBuilding
## Grid place in the building.
var cell: Vector3i
var max_hp: float = 1000.0
var hp: float = 1000.0
var mesh: MeshInstance3D


func on_hit(damage: float) -> void:
	if building != null:
		building.damage_chunk(self, damage)


## Darker as HP goes down (down to dark_scale x the tint at 0 HP).
func show_damage(tint: Color, dark_scale: float) -> void:
	var t := clampf(hp / max_hp, 0.0, 1.0)
	var color := tint * lerpf(dark_scale, 1.0, t)
	color.a = 1.0
	mesh.material_override = GridMaterials.get_material(color)
