class_name DroneSquad
extends RefCounted
## The drones of one launch (user 2026-11-04: "drones switching places and firing should be synchronized"). They
## start each burst together: a drone that has aimed waits for the others of its squad to be ready for that burst
## (waiting at most DroneData.sync_wait_max_s), then all fire at once. The bursts last the same time, so the hops
## after them (the position changes) start together too. A drone that is late (a long way round a building, no
## sight yet) is not waited for after the wait ran out: it joins at its next burst start. A pair is a squad of 2;
## the swarm mod makes a squad of every drone on the pack.

## Answers of AttackDrone.burst_state.
enum State { PASSED, READY, NOT_READY }

var members: Array[AttackDrone] = []
var _data: DroneData
## Seconds each member has waited for the others (instance id -> s).
var _waited: Dictionary = {}


func _init(drone_data: DroneData) -> void:
	_data = drone_data


func add(drone: AttackDrone) -> void:
	members.append(drone)
	drone.squad = self
	drone.finished.connect(_on_finished)


## True when drone (aimed, ready for burst number index, 0-based) may start the burst: the others of the squad are
## ready or past it, or it has waited sync_wait_max_s. Call it every frame while the drone is ready; delta is the
## frame time.
func may_start_burst(drone: AttackDrone, index: int, delta: float) -> bool:
	var id := drone.get_instance_id()
	var late: Array[AttackDrone] = []
	for member in members:
		if member != drone and member.burst_state(index) == State.NOT_READY:
			late.append(member)
	if late.is_empty():
		_waited.erase(id)
		return true
	var waited: float = float(_waited.get(id, 0.0)) + delta
	_waited[id] = waited
	if waited < _data.sync_wait_max_s:
		return false
	# The wait ran out: the late ones are not waited for until they are ready themselves.
	for member in late:
		member.sync_free = true
	_waited.erase(id)
	return true


## A drone is gone or docked: it is not waited for.
func _on_finished(drone: AttackDrone) -> void:
	members.erase(drone)
