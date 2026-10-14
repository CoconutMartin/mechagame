class_name MechNameCatalog
extends Resource
## All mech names (user list 2026-10-14, docs/mech_names.md): status classes and model names.
## data/names/mech_names.tres, built by tools/data_gen/mech_names.py.

@export var names: Array[MechName] = []
## Honorific prefixes for named aces and bosses (Gat = noble man, Dayang = noble woman).
@export var honorifics: PackedStringArray = ["Gat", "Dayang"]


## The name with this code, or null.
func find_code(code: String) -> MechName:
	for entry in names:
		if entry.code == code:
			return entry
	return null


## The status class names (light to heavy ranks).
func status_classes() -> Array[MechName]:
	return names.filter(func(entry: MechName) -> bool: return entry.group == MechName.Group.STATUS_CLASS)


## The model names of one weight class.
func models_of(weight: WeightClass.Class) -> Array[MechName]:
	return names.filter(func(entry: MechName) -> bool:
			return entry.group != MechName.Group.STATUS_CLASS and entry.weight_class == weight)


## Full name: "Sagigilid-class Lawin LWN-088". No model: "SGG-101 Sagigilid".
static func full_name(status: MechName, model: MechName = null) -> String:
	if model == null:
		return "%s %s" % [status.code, status.name]
	return "%s-class %s %s" % [status.name, model.name, model.code]
