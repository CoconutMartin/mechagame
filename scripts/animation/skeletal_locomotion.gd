class_name SkeletalLocomotion
extends Node
## Plays a rigged mech model (skeletal_mech.tscn) from the Mech movement. Standing still: Idle.
## Moving: the walk, jog and run cycles blended by ground speed (Jog is made for the walking speed,
## 9.1 m/s, so a walking mech plays it alone). Every cycle starts with the left foot
## landing, so they share one stride phase; the phase moves by speed / stride length, which keeps the
## feet with the ground at any speed. Head_Scan plays on the head bone on top of everything.
## Each foot landing sends the footstep signal (camera shake).

## A foot lands (strength 0.4 to 1, from the speed).
signal footstep(strength: float)

@export var mech: Mech
@export var tree: AnimationTree
## Optional. Hip turn: while it steps backward the cycles play in reverse.
@export var hip_turn: SkeletalHipTurn
## Locomotion cycles from slow to fast, and the ground speed each one was made for in Blender (m/s;
## this sets its stride length).
@export var cycles: Array[StringName] = [&"Walk", &"Slow_Run", &"Jog", &"biped_run_full"]
@export var cycle_speeds: PackedFloat32Array = PackedFloat32Array([2.71, 4.6, 9.1, 14.16])
## Ground speed (m/s) at which each cycle plays alone (empty = cycle_speeds). Away from its made-for
## speed a cycle plays slower or faster, with the same stride, so the feet still stay planted.
@export var play_speeds: PackedFloat32Array = PackedFloat32Array()
## Near a cycle's own speed only that cycle plays (part of each blend band at each end, 0 to 0.5): two
## blended cycles cannot both keep a planted foot still, one cycle alone always can.
@export_range(0.0, 0.5) var snap: float = 0.12
## Ground speed (m/s) at which the walk has fully replaced Idle.
@export var idle_blend_speed: float = 1.5
## How fast the shown speed follows the mech speed (per second).
@export var speed_follow: float = 8.0
## Head bone track of the model (filter for the head scan layer).
@export var head_track: NodePath
@export var head_scan: StringName = &"Head_Scan"
## Head scan strength (0 = off, 1 = full).
@export_range(0.0, 1.0) var head_scan_amount: float = 1.0

var _speed: float = 0.0
var _phase: float = 0.0
var _band: int = -1
var _lengths: Dictionary = {}
var _root: AnimationNodeBlendTree
var _strides: PackedFloat32Array = PackedFloat32Array()
var _play: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var player := tree.get_node(tree.anim_player) as AnimationPlayer
	for i in cycles.size():
		_lengths[cycles[i]] = player.get_animation(cycles[i]).length
		_strides.append(player.get_animation(cycles[i]).length * cycle_speeds[i])
	_play = play_speeds if play_speeds.size() == cycles.size() else cycle_speeds
	_root = AnimationNodeBlendTree.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = &"Idle"
	_root.add_node(&"idle", idle)
	for side in ["a", "b"]:
		_root.add_node(StringName(side), AnimationNodeAnimation.new())
		_root.add_node(StringName("seek_" + side), AnimationNodeTimeSeek.new())
		_root.connect_node(StringName("seek_" + side), 0, StringName(side))
	_root.add_node(&"mix", AnimationNodeBlend2.new())
	_root.connect_node(&"mix", 0, &"seek_a")
	_root.connect_node(&"mix", 1, &"seek_b")
	_root.add_node(&"move", AnimationNodeBlend2.new())
	_root.connect_node(&"move", 0, &"idle")
	_root.connect_node(&"move", 1, &"mix")
	var scan := AnimationNodeAnimation.new()
	scan.animation = head_scan
	_root.add_node(&"scan", scan)
	var head := AnimationNodeBlend2.new()
	head.filter_enabled = true
	head.set_filter_path(head_track, true)
	_root.add_node(&"head", head)
	_root.connect_node(&"head", 0, &"move")
	_root.connect_node(&"head", 1, &"scan")
	_root.connect_node(&"output", 0, &"head")
	tree.tree_root = _root
	tree.active = true


func _process(delta: float) -> void:
	# In the air the stride stops (no jump animation yet); on the ground it follows the speed.
	var target := mech.get_horizontal_speed() if mech.is_on_floor() else 0.0
	_speed = lerpf(_speed, target, 1.0 - exp(-speed_follow * delta))
	var band := 0
	var t := 0.0
	var last := _play.size() - 1
	if _speed >= _play[last]:
		band = last - 1
		t = 1.0
	else:
		while band < last - 1 and _speed > _play[band + 1]:
			band += 1
		t = clampf((_speed - _play[band]) / (_play[band + 1] - _play[band]), 0.0, 1.0)
		t = smoothstep(0.0, 1.0, clampf((t - snap) / (1.0 - 2.0 * snap), 0.0, 1.0))
	if band != _band:
		_band = band
		(_root.get_node(&"a") as AnimationNodeAnimation).animation = cycles[band]
		(_root.get_node(&"b") as AnimationNodeAnimation).animation = cycles[band + 1]
	var len_a: float = _lengths[cycles[band]]
	var len_b: float = _lengths[cycles[band + 1]]
	var stride := lerpf(_strides[band], _strides[band + 1], t)
	var before := _phase
	var direction := -1.0 if hip_turn != null and hip_turn.is_backward else 1.0
	_phase = fposmod(_phase + direction * _speed * delta / stride, 1.0)
	var landed_forward := _phase < before or (before < 0.5 and _phase >= 0.5)
	var landed_backward := _phase > before or (before >= 0.5 and _phase < 0.5)
	var crossed := landed_forward if direction > 0.0 else landed_backward
	if _speed > idle_blend_speed * 0.5 and mech.is_on_floor() and crossed:
		footstep.emit(clampf(_speed / mech.walk_speed, 0.4, 1.0))
	tree.set(&"parameters/seek_a/seek_request", _phase * len_a)
	tree.set(&"parameters/seek_b/seek_request", _phase * len_b)
	tree.set(&"parameters/mix/blend_amount", t)
	tree.set(&"parameters/move/blend_amount", clampf(_speed / idle_blend_speed, 0.0, 1.0))
	tree.set(&"parameters/head/blend_amount", head_scan_amount)


## Stride phase now (0 = left foot lands, 0.5 = right foot lands).
func get_phase() -> float:
	return _phase
