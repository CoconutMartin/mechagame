class_name BackPackPart
extends PartData
## A back pack (pulse scan phase, user answer 2026-10-14): it carries auxiliary equipment
## (EquipmentData) in its slots. Slot 1 is used with key X (action aux_1), slot 2 with aux_2.

## Number of auxiliary equipment slots.
@export_range(1, 4) var aux_slots: int = 2
