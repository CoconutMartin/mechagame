class_name HpIndicatorSpot
extends Resource
## Where one HP gauge (HpIndicator) sits on a rigged mech, for MechHpIndicators. Each spot has its own
## values, so one side can change with no change to the other.

## MechHealth key of the part it shows, for example "Arm R".
@export var key: String = ""
## Bone of the armor mesh that carries it (the part's largest mesh on this bone).
@export var bone: StringName = &""
## Window length and height (m, without the bezel). Length runs along the gauge.
@export var length: float = 0.68
@export var height: float = 0.12
## Number of cells (shoulders: 3).
@export var cells: int = 3
## True: the gauge runs up and fills from the bottom (legs). Length is then its height.
@export var vertical: bool = false
## True: one bar whose length shows the HP (torso, legs).
@export var continuous: bool = false
## Bar thickness across the gauge (0 to 1), and its corner radius (m; half the thickness = a pill).
@export_range(0.1, 1.0) var bar_share: float = 1.0
@export var cell_round: float = 0.006
## Frame width (rim, bezel and inner lip) as a share of the gauge's own frame values.
@export var frame_scale: float = 1.0
## Space between the display and the window edge (m).
@export var cell_margin: float = 0.022
## How far it sits into the armor, as a share of its window width (0 = on the surface).
@export_range(0.0, 0.5) var recess: float = 0.0
## Shift from the back center of the armor mesh (m, model space: X to the model's left, Y up).
@export var offset: Vector2 = Vector2.ZERO
## True: the gauge fills toward the model's left (+X), false: toward its right. Set it outward
## (left on the left shoulder) so the two sides are mirror images.
@export var fill_to_left: bool = false
## True: the gauge gets smaller (down to min_fit of its size) until the armor under its frame is
## flat, so it keeps clear of bevels and edges.
@export var fit_to_panel: bool = true
@export_range(0.3, 1.0) var min_fit: float = 0.6
