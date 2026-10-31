class_name DroneData
extends Resource
## Attack drones of a drone back pack (user design 2026-10-31): hold T to lock a target, release to launch. A
## drone flies to the target (2 s at 100 m), takes a flank of it (a launched pair holds opposite flanks: a
## pincer), fires a burst, moves to a new semi-random place on its flank, and so on (3 bursts). After
## max_flight_s it is gone (it does not come back). It can be shot down.

@export_group("Lock")
## Lock range from the mech (m).
@export var lock_range_m: float = 160.0
## Half angle of the lock box around the mech aim (degrees).
@export var lock_box_deg: float = 8.0
## Seconds to lock a target.
@export var lock_time: float = 0.5
## Drones per launch (taken left and right in turn). 2 = one pair.
@export_range(1, 12) var drones_per_launch: int = 2

@export_group("Flight")
## Seconds of the pop out of the dock before the drone flies to the target.
@export var launch_time: float = 0.3
## Speed of the pop out of the dock, sideways (m/s).
@export var launch_speed: float = 14.0
## Seconds from the launch to the first attack place, the pop out included (user: 2 s at 100 m). Farther places
## take longer at max_speed. The attack starts then.
@export var approach_time: float = 2.0
## Top speed (m/s).
@export var max_speed: float = 75.0
## How fast the drone turns its speed to the wanted one (1/s; higher = sharper).
@export var steer: float = 6.0
## Longest flight (s; user: 2 s approach + 3 s attack). Then the drone is gone.
@export var max_flight_s: float = 5.0
## Spin of the disc about its axis while flying (degrees per second).
@export var spin_deg_per_s: float = 540.0

@export_group("Attack")
## Bursts per flight.
@export var bursts: int = 3
## Seconds of fire per burst.
@export var burst_time: float = 0.5
## Seconds from one burst start to the next: the drone moves to a new place after each burst.
@export var cycle_time: float = 1.0
## Distance from the target (m), random in this range.
@export var attack_distance_min: float = 28.0
@export var attack_distance_max: float = 42.0
## Angle of the place from the line target -> launching mech, toward the drone's flank (degrees, random in this
## range). 90 = straight to the side of the target.
@export var flank_angle_min: float = 55.0
@export var flank_angle_max: float = 125.0
## Height of the place over the target's lock point (m), random in this range.
@export var height_min: float = 4.0
@export var height_max: float = 14.0
## A new place is at least this far from the last one (m).
@export var min_move_m: float = 10.0
## The gun: damage, bullet speed, spread, range and falloff, stagger (Kind GUN, no model).
@export var gun: WeaponData

@export_group("Body")
## Hit points (balance later, user).
@export var hp: float = 60.0
## Radius of the drone's hit sphere (m).
@export var hit_radius: float = 0.35
## Size of the explosion flash when the drone is shot down or its flight ends (m).
@export var explosion_size: float = 2.5
