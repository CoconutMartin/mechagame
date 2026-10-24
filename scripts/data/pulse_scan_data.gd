class_name PulseScanData
extends EquipmentData
## Pulse scan (user idea 2026-10-14, MechWarrior 5 "enhanced imaging"): a ring spreads out from the mech
## and turns the world into a green wire frame, which then fades from the mech out to the ring's edge.
## A mech the ring finds is highlighted through walls and gets a warning. Start values (user, grade 1
## to grade 3): range 300 to 700 m, wire frame 3 to 5 s, highlight 3 to 5 s, cool down 30 to 20 s,
## uses 3 to 5.

## Ring reach in meters.
@export var range_m: float = 500.0
## Ring speed in m/s (the ring reaches range_m after range_m / ring_speed seconds). 70 since 2026-10-24
## (user: "slow down the scan creep by 80%"; was 350).
@export var ring_speed: float = 70.0
## Seconds a place stays in wire frame after the ring passes it (halved 2026-10-24, user request).
@export var wireframe_time: float = 4.0
## Seconds a found mech stays highlighted.
@export var highlight_time: float = 4.0
## Seconds between uses.
@export var cooldown: float = 25.0
## Uses per battle (a respawn gives a new mech with all uses).
@export var uses: int = 4


func create_device(slot: int) -> Node:
	var scanner := PulseScanner.new()
	scanner.data = self
	scanner.slot = slot
	return scanner
