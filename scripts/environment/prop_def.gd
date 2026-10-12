class_name PropDef
extends Resource
## One street prop type (urban map): size, strength and what happens when a mech walks into it.
## The prop scene (scenes/props/urban) holds the look; UrbanProp reads this file.

enum Reaction {
	NONE,   ## Nothing.
	CRUSH,  ## Kicked away (UrbanProp physics); flattened when a mech comes down on it: the model shrinks
	        ## to crush_scale high, sparks, small camera shake (cars).
	PUSH,   ## Pushed along by the mech, which slows down (UrbanProp physics; buses).
	BEND,   ## Bends at the base, up to bend_max_deg (lampposts, traffic lights).
	BREAK,  ## Breaks into debris (bus stops, benches, fences, hydrants).
	FALL,   ## Falls over away from the mech (trees, people).
}

@export var display_name: String = ""
## Size in meters (x wide, y tall, z long). Used for the collision box.
@export var size: Vector3 = Vector3(1.0, 1.0, 1.0)
## Hit points against weapons. 0 HP = the reaction plays (or BREAK for NONE / PUSH).
@export var hp: float = 100.0
## Mass in tons (push distance, debris).
@export var mass_t: float = 1.0
@export var reaction: Reaction = Reaction.BREAK

@export_group("Reaction")
## CRUSH: height left after crushing (part of the full height).
@export var crush_scale: float = 0.4
## BEND: largest bend angle at the base, in degrees.
@export var bend_max_deg: float = 80.0
## BREAK: number of debris pieces.
@export var debris_pieces: int = 6
## BREAK: water spray (fire hydrant).
@export var water_spray: bool = false
## Camera shake (trauma) on the mech that touched it.
@export var shake: float = 0.12
