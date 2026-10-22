class_name PulseScanner
extends Node
## Runs a pulse scan (PulseScanData) from a back pack slot: the player presses the slot key (aux_1 = X).
## Each use sends the ring (PulseScanEffect) and finds the targets in range (group "lockable", the
## mech itself left out) when the ring reaches them: they get a highlight (PulseScanHighlight) and a
## warning (ScanAlert). Uses and cool down per mech.

signal scanned(found: int)

var data: PulseScanData
## Back pack slot, 1-based (input action aux_<slot>).
var slot: int = 1
var uses_left: int = 0
var cooldown_left: float = 0.0

var _mech: Mech
var _action: StringName
## Targets the ring has not reached yet: [target, seconds until the ring reaches it].
var _pending: Array = []
var _found: int = 0


func _ready() -> void:
	_mech = get_parent().get_parent() as Mech
	name = "PulseScanner%d" % slot
	_action = StringName("aux_%d" % slot)
	if data != null:
		uses_left = data.uses


func _unhandled_input(event: InputEvent) -> void:
	if _mech == null or not _mech.is_in_group(&"player") or not InputMap.has_action(_action):
		return
	if event.is_action_pressed(_action):
		scan()


## True when a scan can start now.
func is_ready() -> bool:
	return data != null and uses_left > 0 and cooldown_left <= 0.0


## Starts a scan from the mech. Returns false when it cannot (no uses left, cooling down).
func scan() -> bool:
	if not is_ready() or _mech == null:
		return false
	uses_left -= 1
	cooldown_left = data.cooldown
	var origin := _mech.global_position
	var world := get_tree().current_scene
	PulseScanEffect.create(world, origin, data)
	_pending.clear()
	_found = 0
	for node in get_tree().get_nodes_in_group(&"lockable"):
		var target := node as Node3D
		if target == null or target == _mech or not target.is_inside_tree():
			continue
		var distance := origin.distance_to(target.global_position)
		if distance <= data.range_m:
			_pending.append([target, distance / maxf(data.ring_speed, 1.0)])
	if _pending.is_empty():
		scanned.emit.call_deferred(0)
	return true


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if _pending.is_empty():
		return
	for i in range(_pending.size() - 1, -1, -1):
		var entry: Array = _pending[i]
		entry[1] -= delta
		if entry[1] > 0.0:
			continue
		_pending.remove_at(i)
		var target: Variant = entry[0]
		if is_instance_valid(target) and (target as Node3D).is_inside_tree():
			PulseScanHighlight.attach(target as Node3D, data.highlight_time)
			ScanAlert.notify(target as Node3D, _mech)
			_found += 1
	if _pending.is_empty():
		scanned.emit(_found)
