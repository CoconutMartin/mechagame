extends SceneTree
## Hit reaction test in the game (user choice 2026-10-16: the arcade stagger spec "B"). The player mech
## takes weapon stagger points on its center torso hitbox (MechStability.hit_body, the path the bullets,
## beams, blasts and melee use) and the test logs what plays: the flinch size (SkeletalHitAnimation,
## by stagger points, 0.15 s cooldown), the stagger (the stun clip of SkeletalStaggerAnimation), the
## protection after it, and the knock-down. User rules 2026-11-02: a normal hit never interrupts (the
## flinch clip never stops the legs: Mech.root_motion_active stays off), the visual HitReaction kick is
## small and the big stagger kick comes only when the bar is full. Exits with code 1 on any failure. Headless:
##   godot --headless --path . --script res://tools/godot/test_hit_reactions.gd

const MAP := "res://maps/urban_small/urban_small.tscn"

var _failures: int = 0
var _player: Mech
var _hits: SkeletalHitAnimation
var _stagger: SkeletalStaggerAnimation
var _hitbox: PartHitbox
var _reaction: HitReaction
## True when a hit_and_watch run saw the legs stopped (Mech.root_motion_active) or the mech fallen.
var _legs_stopped: bool = false
var _peak_lean: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _check(ok: bool, text: String) -> void:
	print(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_failures += 1


func _run() -> void:
	change_scene_to_file(MAP)
	await _frames(30)
	var map := current_scene
	for node in map.get_tree().get_nodes_in_group(&"lockable"):
		if node is Mech and not node.is_in_group(&"player"):
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
	await _frames(40)
	_player = (map.get_node("LoadoutSwitcher") as LoadoutSwitcher).mech
	_hits = _player.find_child("HitAnimation", true, false) as SkeletalHitAnimation
	_stagger = _player.find_child("StaggerAnimation", true, false) as SkeletalStaggerAnimation
	# The rigged Sanggigilid scene has no HitReaction node (only mech_template.tscn does), so the test adds one.
	_reaction = _player.find_child("HitReaction", true, false) as HitReaction
	if _reaction == null:
		_reaction = HitReaction.new()
		_reaction.mech = _player
		_player.add_child(_reaction)
	_check(_hits != null and _stagger != null and _reaction != null, "the player has hit, stagger and reaction nodes")
	_check(not _hits.interrupt_on_hit and is_equal_approx(_hits.hit_flinch, 0.5), "flinch: no interrupt, half strength by default")
	_check(is_equal_approx(_reaction.lean_deg_per_hit, 1.75) and is_equal_approx(_reaction.max_shake, 0.175), "HitReaction values are half of the old ones")
	for key: String in _player.health.max_hp:
		_player.health.max_hp[key] = 1.0e9
		_player.health.hp[key] = 1.0e9
	_hitbox = (_player.health.hitboxes["Torso C"] as Array)[0] as PartHitbox
	var stability := _player.health.stability
	_check(stability != null, "the player has a stagger meter")
	if stability == null:
		quit(1)
		return
	var from := _player.global_position - _player.global_basis.z * 100.0
	# Flinch size by stagger points.
	for entry: Array in [["Fist-size weak hit", 4.0, "small"], ["Heavy Rifle", 18.0, "medium"], ["Auto Cannon", 28.0, "large"]]:
		await _calm()
		var started := await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, entry[1], 0, 0.0, from))
		_check(started == [entry[2]], "%s (%.0f points): %s flinch (got %s)" % [entry[0], entry[1], entry[2], started])
		_check(not _legs_stopped, "%s: the flinch does not stop the legs" % entry[0])
	# One shotgun blast: 8 pellets in one frame, one flinch, 20 points on the meter.
	await _calm()
	var shot := MechStability.new_shot_id()
	var blast := await _hit_and_watch(func() -> void:
		for pellet in 8:
			MechStability.hit_body(_hitbox, 4.0, shot, 20.0, from))
	_check(blast == ["medium"], "shotgun blast (8 pellets): one medium flinch (got %s)" % [blast])
	_check(not _legs_stopped, "shotgun blast: the flinch does not stop the legs")
	_check(absf(stability.value - 20.0) < 0.5, "shotgun blast: meter 20 (got %.1f)" % stability.value)
	# SMG stream at 3 shots per second (user request 2026-10-18): one small flinch per 8 bullets.
	await _calm()
	var single := await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, 3.0, 0, 0.0, from))
	_check(single.is_empty(), "one SMG bullet (3 points): no flinch (got %s)" % [single])
	await _calm()
	var stream: Array = []
	for bullet in 16:
		stream.append_array(await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, 3.0, 0, 0.0, from), 20))
	var only_small := stream.all(func(name: String) -> bool: return name == "small")
	_check(only_small and stream.size() == 2,
			"SMG at 3 per second (16 bullets): 2 small flinches, one per 8 bullets (got %s)" % [stream])
	# Many damage points in a few frames (no stagger points) give only the small spring kick: the big
	# stagger kick of the old damage sum is gone.
	await _calm()
	_peak_lean = 0.0
	for i in 4:
		_player.health.damage("Torso C", 150.0, from)
	await _watch_lean(60)
	var damage_peak := _peak_lean
	_check(damage_peak < _reaction.stagger_lean_deg, "600 damage in one frame, bar empty: small kick only (peak lean %.1f deg)" % damage_peak)
	_check(not _stagger.is_staggered() and not _stagger.is_down, "600 damage, bar empty: no stun")
	# Stagger at 100: the stun clip plays, not a flinch; then the protection.
	await _calm()
	_peak_lean = 0.0
	for i in 3:
		MechStability.hit_body(_hitbox, 28.0, 0, 0.0, from)
		await _frames(30)
	var stun := await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, 28.0, 0, 0.0, from))
	_check(stun.has("stagger") and not stun.has("large"), "4 Auto Cannon hits (112): stagger, no flinch (got %s)" % [stun])
	_check(_peak_lean > damage_peak, "full bar: the stagger kick leans the body more than the damage sum (peak %.1f > %.1f deg)" % [_peak_lean, damage_peak])
	_check(stability.is_protected(), "protection after the stagger")
	var during := stability.value
	MechStability.hit_body(_hitbox, 32.0, 0, 0.0, from)
	_check(absf(stability.value - during) < 0.01, "a sniper hit in the protection adds nothing (meter %.1f)" % stability.value)
	# Knock-down: the War Hammer (45 points at once).
	await _calm(240)
	var knock := await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, 45.0, 0, 0.0, from), 30)
	_check(knock.has("down"), "War Hammer (45): knock-down (got %s)" % [knock])
	# Environment damage keeps its weak flinch (no stagger points).
	await _calm(480)
	var meter_before := stability.value
	var env := await _hit_and_watch(func() -> void: _player.health.damage("Torso C", 1.0, from, &"environment"))
	_check(not _legs_stopped, "building contact: the legs go on")
	_check(env.size() == 1 and absf(stability.value - meter_before) < 0.01, "building contact: weak flinch, no stagger points (got %s)" % [env])
	# The old rule stays available: interrupt_on_hit on stops the legs while the clip plays.
	await _calm(240)
	_hits.interrupt_on_hit = true
	var old_rule := await _hit_and_watch(func() -> void: MechStability.hit_body(_hitbox, 18.0, 0, 0.0, from))
	_check(old_rule == ["medium"] and _legs_stopped, "interrupt_on_hit on: the flinch stops the legs (got %s)" % [old_rule])
	_hits.interrupt_on_hit = false
	print("RESULT: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


## Waits until no reaction plays and the meter is empty.
func _calm(frames: int = 150) -> void:
	await _frames(frames)
	var guard := 0
	while (_hits.is_playing or _stagger.is_staggered() or _stagger.is_down or _player.health.stability.value > 0.0) and guard < 900:
		await _frames(1)
		guard += 1


## Runs the hit, then watches `frames` frames; returns what started: "small" / "medium" / "large"
## flinches, "stagger", "down".
func _hit_and_watch(hit: Callable, frames: int = 12) -> Array:
	var started: Array = []
	var was_playing := _hits.is_playing
	var last_clip: HitClip = _hits.clip
	var was_staggered := _stagger.is_staggered()
	var was_down := _stagger.is_down
	_legs_stopped = false
	hit.call()
	for f in frames:
		await _frames(1)
		_peak_lean = maxf(_peak_lean, absf(_reaction.lean_deg))
		if _player.root_motion_active and not _stagger.is_down:
			_legs_stopped = true
		if _hits.is_playing and (not was_playing or _hits.clip != last_clip or float(_hits.get("_time")) < 0.02):
			if not (was_playing and float(_hits.get("_time")) >= 0.02):
				started.append(_hits.clip.resource_path.get_file().get_basename())
		if _stagger.is_down and not was_down:
			started.append("down")
		elif _stagger.is_staggered() and not was_staggered and not _stagger.is_down:
			started.append("stagger")
		was_playing = _hits.is_playing
		last_clip = _hits.clip
		was_staggered = _stagger.is_staggered()
		was_down = _stagger.is_down
	return started


## Watches the body lean for `frames` frames and keeps the biggest swing in _peak_lean.
func _watch_lean(frames: int) -> void:
	for f in frames:
		await _frames(1)
		_peak_lean = maxf(_peak_lean, absf(_reaction.lean_deg))
