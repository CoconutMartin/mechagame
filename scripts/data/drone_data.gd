class_name DroneData
extends Resource
## Attack drones of a drone back pack (user design 2026-10-31): hold T to lock a target, release to launch. A
## drone flies to the target (2 s at 100 m) at most 12.5 m over the ground, over low buildings and around tall ones,
## takes a firing place on its flank of it (a launched
## pair holds opposite flanks: a pincer) within 20 m that sees it, then stops and fires its bursts (it does not
## move after the first shot). After max_flight_s it is gone (it does not come back). It can be shot down.

@export_group("Lock")
## Lock range from the mech (m).
@export var lock_range_m: float = 160.0
## Half angle of the lock box around the mech aim (degrees).
@export var lock_box_deg: float = 8.0
## Seconds to lock a target.
@export var lock_time: float = 0.5
## Seconds after the last drone of a launch is gone or back on its dock before the next launch (user rule
## 2026-10-31: 10 s; no launch while drones of the mech are in the air).
@export var cooldown_s: float = 10.0
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
## Highest flight over the ground under the drone (m; user rule 2026-10-31: 12.5 m). Taller buildings: around.
@export var max_height: float = 12.5
## Highest the drone tilts up to aim (degrees; user rule 2026-10-31: 45). A target above the ceiling (a mech on a
## roof) can be attacked from under it when it is within the gun range, in sight and at most this steep.
@export var max_tilt_up_deg: float = 45.0
## Gap the drone body keeps from walls, roofs and corners (m; user rule: it cannot touch them).
@export var skin: float = 0.15
## Extra room a planned way keeps from them (m).
@export var corner_margin: float = 0.4
## Seconds between path plans.
@export var path_check_time: float = 0.25
## Grid path around tall buildings: cell size (m), room around the start and the goal (m), most cells per plan,
## and how many points ahead a shortcut may skip.
@export var path_cell: float = 3.0
@export var path_margin: float = 40.0
@export var path_max_cells: int = 8000
@export var path_shorten_reach: int = 12
## Seconds a cell's "free or not" stays known (buildings can break).
@export var cell_cache_time: float = 1.0

## Recall mod: the drone counts as back this close to its dock (m), and is lost when the way back takes longer than
## return_max_s seconds.
@export var dock_distance: float = 1.0
@export var return_max_s: float = 10.0

@export_group("Attack")
## The drone fires from a place this close to its goal (m).
@export var arrive_distance: float = 1.5
## Seconds between checks that the firing place still sees the target (the target can go behind cover).
@export var recheck_time: float = 0.25
## Seconds without a way to a firing place before the drone drops it, and how far (m) from a dropped place a new
## one must be.
@export var unreachable_time: float = 0.5
@export var avoid_radius: float = 6.0
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
