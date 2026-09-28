class_name FcsPart
extends PartData
## FCS (fire control computer): lock-on. Used in Phase 3.

## Lock-on range in meters.
@export var lock_range: float = 500.0
## Most targets locked at the same time.
@export var max_locks: int = 4
## Aim assist strength (0 = none).
@export_range(0.0, 1.0) var aim_assist: float = 0.0
