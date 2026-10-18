class_name AIMelee
extends Node
## Melee part of the AI pilot (user request 2026-10-16). AIPilot calls drive() each physics frame when
## the right arm weapon is a Fist, a War Hammer or a Pile Bunker. It fills the same MechInput values a
## player fills, so the melee animation reads the move key and the button like it does for a player.
##   Move: it closes in on the target (boosts when far). When the attack is not ready (cooldown, pile
##         bunker reload) it keeps a medium range and circles.
##   Attack: inside attack_range, with the torso on the target, after a short random pause it presses
##           the weapon button for one frame. The move key of that frame picks the attack (the situation
##           and some randomness decide: where the target moves, kneeling or down, close or far).
##   Fist combo: a plain punch that hit gets its next press inside the combo window.
##   Pile bunker: it holds the button for a random time at 15 to 25 m, then releases (charge and punch).

## Fist and hammer: direction keys by name, in the aim frame (forward is the aim).
const KEYS := {
	&"forward": Vector3(0.0, 0.0, -1.0),
	&"back": Vector3(0.0, 0.0, 1.0),
	&"left": Vector3(-1.0, 0.0, 0.0),
	&"right": Vector3(1.0, 0.0, 0.0),
}

@export_group("Range")
## It presses the attack button inside this distance (m, center to center). The melee glide covers the rest.
@export var attack_range: float = 16.0
## While the attack is not ready it keeps about this distance (m) and circles the target.
@export var wait_range: float = 22.0
## Half width of the band around wait_range where it only circles (m).
@export var wait_band: float = 5.0
## Farther than this it boosts toward the target (m).
@export var boost_range: float = 45.0

@export_group("Attack")
## It presses the button when the torso points within this angle of the target (degrees).
@export var attack_angle_deg: float = 8.0
## Pause between being ready to attack and the press, random in this range (seconds).
@export var attack_delay_min: float = 0.2
@export var attack_delay_max: float = 0.7
## Seconds after a hit until it presses the next swing of a fist combo, random in this range (the
## melee window is 0.6 s: SkeletalMeleeAnimation.combo_window).
@export var combo_delay_min: float = 0.05
@export var combo_delay_max: float = 0.3

## The button and the move key stay down for this many physics frames (a player holds them longer).
@export var press_frames: int = 3

@export_group("Direction")
## The target counts as moving to a side when its sideways speed is above this (m/s).
@export var side_speed: float = 1.5
## Or when it stands to a side of the aim by more than this part of the distance (0.1 = about 6 degrees).
@export var side_offset: float = 0.1
## The target counts as slow below this speed (m/s): the hammer strikes it heavy.
@export var slow_speed: float = 2.5
## Closer than this (m) the fist likes the uppercut.
@export var close_range: float = 9.0
## Fist weights: plain punch (starts the combo), uppercut, overhead swipe, hook toward the target's side.
@export var weight_straight: float = 4.0
@export var weight_uppercut: float = 1.0
@export var weight_swipe: float = 1.0
@export var weight_hook_side: float = 3.0
## Hammer weights: heavy strike on a stunned, down or slow target, the swing toward the target's side,
## the light strike.
@export var weight_heavy_hit: float = 6.0
@export var weight_hammer_side: float = 4.0
@export var weight_light: float = 2.0

@export_group("Pile bunker")
## It holds the power up button for a random time in this range (seconds; 1.5 s is full power).
@export var power_min: float = 0.6
@export var power_max: float = 1.5
## It powers up between these distances (m).
@export var bunker_min_range: float = 15.0
@export var bunker_max_range: float = 25.0

## Attack counts by name, for tests: "fist/straight", "fist/forward", "hammer/left", "bunker" and so on.
var attack_counts := {}
## Fist combo swings pressed after the first one.
var combo_presses: int = 0

var mech: Mech
var input: MechInput

var _weapons: WeaponController
var _anim: SkeletalMeleeAnimation
var _stagger: SkeletalStaggerAnimation
var _strafe_side: float = 1.0
var _strafe_left: float = 0.0
## Seconds left of the pause before the attack press (below 0: not started).
var _attack_wait: float = -1.0
var _combo_delay: float = -1.0
## Pile bunker: seconds held and the goal (below 0: not powering).
var _power_held: float = -1.0
var _power_goal: float = 0.0
var _last_press_frame: int = -10
## A press lasts press_frames physics frames: the weapon reads the button a frame late, and the animation
## reads the move key when it gets the request.
var _hold_left: int = 0
var _held_key: StringName = &""
var _held_left_button: bool = false


func setup(pilot_mech: Mech, pilot_input: MechInput, weapons: WeaponController) -> void:
	mech = pilot_mech
	input = pilot_input
	_weapons = weapons
	_anim = mech.find_child("MeleeAnimation", true, false) as SkeletalMeleeAnimation
	_strafe_side = 1.0 if randf() < 0.5 else -1.0


## True when the weapon is one this class flies.
static func handles(weapons: WeaponController) -> bool:
	if weapons == null or weapons.right_data == null or weapons.right_weapon == null:
		return false
	var kind := weapons.right_data.kind
	return kind == WeaponData.Kind.FIST or kind == WeaponData.Kind.HAMMER or kind == WeaponData.Kind.PILE_BUNKER


## True while a melee attack plays or a bunker attack runs (the AI does not dodge or walk then).
func is_committed() -> bool:
	var bunker := _weapons.right_weapon as PileBunkerWeapon
	if bunker != null:
		return bunker.state != PileBunkerWeapon.State.IDLE or _power_held >= 0.0
	return _anim != null and _anim.is_playing


## True when the next attack can start now.
func is_ready() -> bool:
	var bunker := _weapons.right_weapon as PileBunkerWeapon
	if bunker != null:
		return bunker.state == PileBunkerWeapon.State.IDLE and bunker.can_use() \
				and mech.energy.current >= bunker.data.lunge_energy and mech.is_on_floor() and not mech.is_fallen
	return _anim != null and _anim.is_ready()


## Fills the input for this frame. flat = flat vector to the target, distance = its length.
func drive(target: Mech, flat: Vector3, distance: float, delta: float) -> void:
	if _anim == null or _weapons.right_weapon == null:
		return
	var bunker := _weapons.right_weapon as PileBunkerWeapon
	if bunker != null:
		_drive_bunker(bunker, target, flat, distance, delta)
		return
	if _hold_left > 0:
		_hold_left -= 1
		_apply_press()
		return
	_combo(delta)
	var ready := is_ready()
	if not is_committed():
		_move(flat, distance, delta, ready, 0.0, attack_range - 2.0)
	if not ready:
		_attack_wait = -1.0
		return
	var error := absf(wrapf(input.aim_yaw - mech.get_aim_yaw(), -PI, PI))
	if distance > attack_range or error > deg_to_rad(attack_angle_deg):
		_attack_wait = -1.0
		return
	if _attack_wait < 0.0:
		_attack_wait = randf_range(attack_delay_min, attack_delay_max)
	_attack_wait -= delta
	if _attack_wait > 0.0:
		return
	_attack_wait = -1.0
	if _weapons.right_data.kind == WeaponData.Kind.HAMMER:
		_hammer_attack(target, distance)
	else:
		_fist_attack(target, distance)


## Moves toward the goal band: wait_range while the attack is not ready, else lo to hi.
func _move(flat: Vector3, distance: float, delta: float, ready: bool, lo: float, hi: float) -> void:
	var forward := flat.normalized()
	var side := forward.cross(Vector3.UP).normalized()
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(2.0, 4.5)
		_strafe_side = -_strafe_side
	if not ready:
		lo = wait_range - wait_band
		hi = wait_range + wait_band
	var wish := side * _strafe_side * (0.7 if not ready else 0.35)
	var closing := false
	if distance > hi:
		wish = forward + side * _strafe_side * 0.3
		closing = true
	elif distance < lo:
		wish = -forward * 0.8 + side * _strafe_side * 0.6
	input.move_direction = wish.normalized()
	input.turn_input = -_strafe_side
	input.boost_held = distance > boost_range
	input.forward_held = closing


## The next swing of a fist combo: a press inside the window after a hit.
func _combo(delta: float) -> void:
	var since_hit := _anim.get_combo_wait()
	if since_hit < 0.0:
		_combo_delay = -1.0
		return
	if _combo_delay < 0.0:
		_combo_delay = randf_range(combo_delay_min, combo_delay_max)
	if since_hit < _combo_delay:
		return
	_combo_delay = -1.0
	combo_presses += 1
	_press(&"", _pick_fist_button())
	_count("fist/combo")


func _fist_attack(target: Mech, distance: float) -> void:
	var side := _target_side(target)
	var has_left := _weapons.left_weapon is MeleeWeapon
	var down := _target_down(target)
	var weights := {
		&"straight": weight_straight,
		&"forward": weight_uppercut + (4.0 if down else 0.0) + (2.0 if distance < close_range else 0.0),
		&"back": weight_swipe,
		&"right": weight_hook_side if side > 0 else (0.3 if side < 0 else 0.6),
	}
	if has_left:
		weights[&"left"] = weight_hook_side if side < 0 else (0.3 if side > 0 else 0.6)
	var key: StringName = _pick(weights)
	var use_left := false
	match key:
		&"left":
			use_left = true
		&"right":
			use_left = false
		_:
			use_left = _pick_fist_button()
	_press(&"" if key == &"straight" else key, use_left)
	_count("fist/" + String(key))


func _hammer_attack(target: Mech, _distance: float) -> void:
	var side := _target_side(target)
	var heavy := _target_down(target) or _target_speed(target) < slow_speed
	var weights := {
		&"back": weight_heavy_hit if heavy else 0.8,
		&"": weight_light if not heavy else 1.0,
		&"left": weight_hammer_side if side < 0 else (0.3 if side > 0 else 1.0),
		&"right": weight_hammer_side if side > 0 else (0.3 if side < 0 else 1.0),
	}
	if heavy:
		weights[&"left"] = 0.5
		weights[&"right"] = 0.5
	var key: StringName = _pick(weights)
	_press(key, false)
	_count("hammer/" + (String(key) if key != &"" else "light"))


## Pile bunker: hold the button at 15 to 25 m for a random time, then release.
func _drive_bunker(bunker: PileBunkerWeapon, target: Mech, flat: Vector3, distance: float, delta: float) -> void:
	if _power_held >= 0.0:
		# Powering: hold the button until the goal. The weapon takes the release as the attack.
		_power_held += delta
		if bunker.state == PileBunkerWeapon.State.POWER or _power_held < 0.1:
			if _power_held < _power_goal:
				input.fire_held = true
				return
		_power_held = -1.0
		return
	if bunker.state != PileBunkerWeapon.State.IDLE:
		return
	var ready := is_ready()
	_move(flat, distance, delta, ready, bunker_min_range + 1.0, bunker_max_range - 1.0)
	var error := absf(wrapf(input.aim_yaw - mech.get_aim_yaw(), -PI, PI))
	if not ready or distance < bunker_min_range or distance > bunker_max_range or error > deg_to_rad(attack_angle_deg):
		_attack_wait = -1.0
		return
	if _attack_wait < 0.0:
		_attack_wait = randf_range(attack_delay_min, attack_delay_max)
	_attack_wait -= delta
	if _attack_wait > 0.0:
		return
	_attack_wait = -1.0
	_power_held = 0.0
	_power_goal = randf_range(power_min, power_max)
	input.fire_held = true
	_count("bunker")


## One frame press of a button with a move key (empty = no key).
func _press(key: StringName, use_left: bool) -> void:
	var frame := Engine.get_physics_frames()
	# A press needs released frames before it.
	if frame - _last_press_frame < press_frames + 2:
		return
	_last_press_frame = frame
	_held_key = key
	_held_left_button = use_left
	_hold_left = press_frames - 1
	_apply_press()


## The button and the move key of the press (the key is in the aim frame, like the player's keys).
func _apply_press() -> void:
	var local: Vector3 = KEYS.get(_held_key, Vector3.ZERO)
	input.move_direction = Basis(Vector3.UP, mech.get_aim_yaw()) * local
	input.forward_held = false
	input.boost_held = false
	if _held_left_button:
		input.left_fire_held = true
	else:
		input.fire_held = true


## A random fist button (true = left) among the fists the mech has.
func _pick_fist_button() -> bool:
	return _weapons.left_weapon is MeleeWeapon and randf() < 0.5


func _count(name: String) -> void:
	attack_counts[name] = attack_counts.get(name, 0) + 1


## Picks a key by weight.
func _pick(weights: Dictionary) -> Variant:
	var total := 0.0
	for key in weights:
		total += weights[key]
	var roll := randf() * total
	for key in weights:
		roll -= weights[key]
		if roll <= 0.0:
			return key
	return weights.keys()[0]


## Where the target goes or stands, in the aim frame: -1 left, 1 right, 0 none.
func _target_side(target: Mech) -> int:
	var to_local := Basis(Vector3.UP, mech.get_aim_yaw()).inverse()
	var velocity := to_local * target.velocity
	if absf(velocity.x) > side_speed:
		return 1 if velocity.x > 0.0 else -1
	var offset := to_local * (target.global_position - mech.global_position)
	var distance := maxf(Vector2(offset.x, offset.z).length(), 1.0)
	if absf(offset.x) / distance > side_offset:
		return 1 if offset.x > 0.0 else -1
	return 0


func _target_speed(target: Mech) -> float:
	return Vector2(target.velocity.x, target.velocity.z).length()


## Stunned, knocked down or kneeling.
func _target_down(target: Mech) -> bool:
	if target.is_fallen:
		return true
	if target.kneel != null and target.kneel.is_kneeling:
		return true
	if not is_instance_valid(_stagger) or not _stagger.is_inside_tree() or not target.is_ancestor_of(_stagger):
		_stagger = target.find_child("StaggerAnimation", true, false) as SkeletalStaggerAnimation
	return _stagger != null and (_stagger.is_staggered() or _stagger.is_down)
