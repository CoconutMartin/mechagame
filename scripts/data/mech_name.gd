class_name MechName
extends Resource
## One mech name from the naming list (user list 2026-10-14, docs/mech_names.md): pre-colonial
## Filipino names. Full name format: "STATUS-class MODEL CODE", for example "Sagigilid-class Lawin
## LWN-101". Built by tools/data_gen/mech_names.py.

enum Group { STATUS_CLASS, DEITY, EPIC_HERO, FOLKLORE, ANIMAL, WEAPON, VESSEL, NATURE, ROLE }

## The name, for example "Lawin".
@export var name: String = ""
@export var group: Group = Group.STATUS_CLASS
## Weight class of the frame.
@export var weight_class: WeightClass.Class = WeightClass.Class.LIGHT
## Unique code: 3 letters and a number, for example "LWN-088".
@export var code: String = ""
## Culture or language of origin (empty when the list gives none).
@export var origin: String = ""
@export var meaning: String = ""
## Role the name suits, for example "Sniper archetype".
@export var fit: String = ""
## Animals: the home the code number comes from. Weapons and vessels: the size it comes from.
@export var number_source: String = ""
