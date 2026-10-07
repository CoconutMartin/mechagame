@tool
class_name BuildingDef
extends Resource
## One building type for BuildingGenerator (urban map). Sizes in meters. New buildings need only a
## new .tres file in data/environment/buildings.

enum RoofType { FLAT, PARAPET, GRAVEL }

@export var display_name: String = ""

@export_group("Size")
@export var footprint_x: float = 16.0
@export var footprint_z: float = 12.0
@export_range(1, 30) var floor_count: int = 3
## Height of each floor above the ground floor (the window grid follows it).
@export var floor_height: float = 3.2
## Height of the ground floor (shops: 4 m).
@export var ground_floor_height: float = 4.0

@export_group("Materials")
## Wall panels.
@export var wall_material: MaterialDef
## Floor slabs, columns, window frames and parapets.
@export var frame_material: MaterialDef
## Window glass.
@export var glass_material: MaterialDef
## Roof top (GRAVEL roofs).
@export var roof_material: MaterialDef
## Doors.
@export var door_material: MaterialDef

@export_group("Facade")
## Part of each wall panel width that is window (0 = no windows).
@export_range(0.0, 0.9) var window_ratio: float = 0.5
## Part of each floor height that is window.
@export_range(0.0, 0.9) var window_height_ratio: float = 0.5
## Ground floor: shop windows on the front face (-z side of the building) and a door.
@export var shop_front: bool = true
@export var roof_type: RoofType = RoofType.PARAPET
## Wall panel thickness.
@export var wall_thickness: float = 0.4

@export_group("Structure")
## Wall panel width (the real width divides each face evenly).
@export var chunk_width: float = 4.0
## Interior column spacing.
@export var column_spacing: float = 8.0
## Tower: only the facade breaks; the core never collapses.
@export var facade_only: bool = false
## Out-of-bounds edge building: never takes damage.
@export var indestructible: bool = false
## Strength multiplier (also grows with the footprint area, see BuildingGenerator.integrity_of).
@export var integrity_multiplier: float = 1.0


func get_height() -> float:
	return ground_floor_height + floor_height * (floor_count - 1)


## Bottom height of a floor (0 = ground floor).
func floor_bottom(index: int) -> float:
	return 0.0 if index == 0 else ground_floor_height + floor_height * (index - 1)


func floor_top(index: int) -> float:
	return floor_bottom(index) + (ground_floor_height if index == 0 else floor_height)
