class_name DroneData
extends Resource
## Attack drones of a drone back pack (user design 2026-10-31): hold T to lock a target, release to launch. A
## drone flies to the target (2 s at 100 m) around buildings, takes a firing place on its flank of it (a launched
## pair holds opposite flanks: a pincer) within 20 m that sees it, then stops and fires its bursts (it does not
## move after the first shot). After max_flight_s it is gone (it does not come back). It can be shot down.

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

## Layers that block the drone's flight and sight (1 = world, 5 = buildings).
@export_flags_3d_physics var sight_mask: int = 17
## Seconds between path checks (the way over buildings).
@export var path_check_time: float = 0.1
## Height steps and top height of the climb over a building in the way (m).
@export var climb_step: float = 4.0
@export var climb_max: float = 120.0

@export_group("Attack")
## The drone fires from a place this close to its goal (m).
@export var arrive_distance: float = 1.5
## Seconds between checks that the firing place still sees the target (the target can go behind cover).
@export var recheck_time: float = 0.25
## Random places tried per flank when a firing place is picked.
@export var place_tries: int = 16
## Free air around a firing place (m).
@export var place_clearance: float = 1.5
## Bursts per flight.
@export var bursts: int = 3
## Seconds of fire per burst.
@export var burst_time: float = 0.5
## Seconds from one burst start to the next. From the first shot the drone does not move (user rule).
@export var cycle_time: float = 1.0
## Distance from the target's lock point (m), random in this range (inside the gun's 20 m range, user rule).
@export var attack_distance_min: float = 9.0
@export var attack_distance_max: float = 15.0
## Angle of the place from the line target -> launching mech, toward the drone's flank (degrees, random in this
## range). 90 = straight to the side of the target.
@export var flank_angle_min: float = 55.0
@export var flank_angle_max: float = 125.0
## Height of the place over the target's lock point (m), random in this range.
@export var height_min: float = -1.0
@export var height_max: float = 7.0
## The gun: damage, bullet speed, spread, range (20 m, user rule), stagger (Kind GUN, no model).
@export var gun: WeaponData

@export_group("Body")
## Hit points (balance later, user).
@export var hp: float = 60.0
## Radius of the drone's hit sphere (m).
@export var hit_radius: float = 0.45
## Size of the explosion flash when the drone is shot down or its flight ends (m).
@export var explosion_size: float = 2.5
