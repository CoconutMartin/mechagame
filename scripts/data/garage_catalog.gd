class_name GarageCatalog
extends Resource
## Everything the garage offers for each slot (Phase 5). Made by tools/data_gen/garage_data.py.

@export var heads: Array[HeadPart] = []
@export var cores: Array[CorePart] = []
@export var arms_left: Array[ArmPart] = []
@export var arms_right: Array[ArmPart] = []
@export var legs: Array[LegPart] = []
@export var boosters: Array[BoosterPart] = []
@export var generators: Array[GeneratorPart] = []
@export var fcs: Array[FcsPart] = []
## Right arm weapons (guns and melee).
@export var weapons_right: Array[WeaponData] = []
## Left arm (shields). The garage adds "none".
@export var weapons_left: Array[WeaponData] = []
@export var backs_left: Array[WeaponData] = []
@export var backs_right: Array[WeaponData] = []
## All plates (light and heavy for each slot).
@export var plates: Array[PlateData] = []
@export var mods: Array[ModData] = []
