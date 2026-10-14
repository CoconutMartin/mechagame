class_name HpIndicatorSpot
extends Resource
## Where one HP indicator (HpIndicator) sits on a rigged mech, for MechHpIndicators. Each spot has its
## own values, so one side can change with no change to the other.

## MechHealth key of the part it shows, for example "Arm R".
@export var key: String = ""
## Bone of the armor mesh that carries it (the part's largest mesh on this bone).
@export var bone: StringName = &""
## Display size (m, side of the square, without the housing frame).
@export var size: float = 0.3
## Shift from the back center of the armor mesh (m, model space: X to the model's left, Y up).
@export var offset: Vector2 = Vector2.ZERO
## Turn on the armor face (degrees, about the face normal).
@export var roll_degrees: float = 0.0
## True: the indicator gets smaller (down to min_fit of its size) until the armor under its frame
## is flat, so it keeps clear of bevels and edges.
@export var fit_to_panel: bool = true
@export_range(0.3, 1.0) var min_fit: float = 0.6
