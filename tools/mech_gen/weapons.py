"""Weapons: beam sniper, pile bunker, missile pods, the Beam Rifle scene, and the weapon data files with
their poses (torso space of the weapon frame). The heavy rifle model comes from heavy_rifle.py; the
shield scene (scenes/weapons/warden_shield.tscn) is kept as it is (its generator went with the
Warden, 2026-10-11). Run from the project root: python3 tools/mech_gen/weapons.py"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Builder, xf, xf_aim, xf_rows, apply_rows, r
import arm_poses

# Frame values the weapon poses were made for (from the removed Warden generator, 2026-10-11): torso
# pivot height, torso scale, hold places. The new mech's arm rig uses the same torso space.
WAIST = 5.4
K = 0.85
SHIELD_SCALE = 1.2
SHIELD_WIDTH = 2.1 * 0.8
ONE_HAND = {
    "right_pole_rest": (0.4, -1.0, 0.5),
    "right_pole_aim": (0.4, -1.0, 0.5),
    "aim_anchor": (2.8, 6.5, -1.0),
    "shield_area": (SHIELD_WIDTH * 3.8 + 2 * 0.5 * SHIELD_WIDTH * 0.7) * SHIELD_SCALE ** 2,
}


def TT(x, y, z):
    """Mech space (feet at 0) to torso space."""
    return (x, y - WAIST, z)


def torso_point(p, k):
    """Mech-space point moved toward the torso pivot by the torso scale k."""
    return (p[0] * k, WAIST + (p[1] - WAIST) * k, p[2] * k)


def one_hand_rest(hand, muzzle_dir, up_hint, grip=(0, -0.33, -0.99), torso_scale=1.0):
    """Rest transform text that puts the weapon grip at hand, muzzle along muzzle_dir (mech space)."""
    hand = torso_point(hand, torso_scale)
    rows = xf_aim(muzzle_dir, up_hint, hand)
    g = apply_rows(rows, grip)
    origin = TT(*(h - o for h, o in zip(hand, g)))
    return xf_rows(rows, origin)


# Right hand poses from the user's arm drawing (tools/mech_gen/arm_poses.py, torso space): elbow 45 deg
# at neutral, the gun on top of the forearm and along it; elbow 90 deg when aiming. Mech space for
# one_hand_rest (torso y + WAIST).
RIGHT_HAND_NEUTRAL_TORSO = arm_poses.hand(arm_poses.ELBOW_R, arm_poses.NEUTRAL_DEG)
RIGHT_HAND_NEUTRAL = (RIGHT_HAND_NEUTRAL_TORSO[0], RIGHT_HAND_NEUTRAL_TORSO[1] + WAIST, RIGHT_HAND_NEUTRAL_TORSO[2])
RIGHT_HAND_AIM = arm_poses.hand(arm_poses.ELBOW_R, arm_poses.AIM_DEG)


def grip_socket(name, origin, rake_deg, radius, hand_reach=True, hold_drop=0.0):
    """Grip socket node text (user request 2026-10-13; MechHandControl): a Marker3D at the grip center
    (where the fist hollow goes), +Y along the grip toward the gun body (a pistol grip leans back:
    rake_deg, top forward), +Z toward the butt (the palm side), +X to the gun's right; metadata
    grip_radius = the grip's half thickness (meters, the fingers close on it); hand_reach = false keeps
    the arm's pose and only turns the hand at the wrist; hold_drop (meters, 0 = none) sits the hand that
    much lower on the grip, so the thumb mount and the thumb clear the gun body (user request 2026-10-22)."""
    drop = f'metadata/hold_drop = {hold_drop}\n' if hold_drop else ''
    return (f'[node name="{name}" type="Marker3D" parent="."]\ntransform = {xf(origin, (-rake_deg, 0, 0))}\n'
            f'metadata/grip_radius = {radius}\nmetadata/hand_reach = {"true" if hand_reach else "false"}\n{drop}')


def gun_on_forearm_rest(grip, out_deg=0.0):
    """One-hand gun at neutral: grip in the fist, muzzle along the forearm (side view), gun top away from
    it. out_deg turns the forearm out to the side (the gun keeps pointing ahead), so a low stock passes
    beside the forearm, not into it."""
    hand = arm_poses.hand(arm_poses.ELBOW_R, arm_poses.NEUTRAL_DEG, out_deg)
    return one_hand_rest(hand=(hand[0], hand[1] + WAIST, hand[2]),
                         muzzle_dir=arm_poses.forearm_dir(arm_poses.NEUTRAL_DEG),
                         up_hint=arm_poses.top_side(arm_poses.NEUTRAL_DEG), grip=grip)


def gun_aim_anchor(grip, out_deg=0.0):
    """Aim anchor (the gun origin) that puts the grip in the fist of the level forearm (aiming ahead),
    the forearm turned out_deg out to the side like at rest."""
    return arm_poses.minus(arm_poses.hand(arm_poses.ELBOW_R, arm_poses.AIM_DEG, out_deg), grip)


# Heavy rifle pistol grip (heavy_rifle.py builds it from these; model units, SCALE 0.6): it hangs from
# RIFLE_GRIP_TOP along RIFLE_GRIP_AXIS (tilted 20 deg). The fist holds it RIFLE_GRIP_HOLD down from the
# top: high, so the fist top meets the rifle body (user picture 2026-10-12).
RIFLE_SCALE = 0.6
RIFLE_GRIP_TOP = (0.0, -0.2675, -1.778)
RIFLE_GRIP_AXIS = (0.0, -0.9397, 0.342)
RIFLE_GRIP_HOLD = 0.75
RIFLE_GRIP_LENGTH = 1.6
## The forearm turns this much out to the side (rest and aim), so the stock passes beside it.
RIFLE_OUT_DEG = 25.0
RIFLE_GRIP_HOLD_POINT = tuple(RIFLE_SCALE * (t + a * RIFLE_GRIP_HOLD) for t, a in zip(RIFLE_GRIP_TOP, RIFLE_GRIP_AXIS))
## Pistol grip rake (degrees from vertical, top forward) and half thickness (the 0.32 x 0.38 box x 0.6).
RIFLE_GRIP_RAKE = 20.0
RIFLE_GRIP_RADIUS = 0.105
RIFLE_GRIP = arm_poses.palm_socket(RIFLE_GRIP_HOLD_POINT)
RIFLE_REST = gun_on_forearm_rest(RIFLE_GRIP, RIFLE_OUT_DEG)
# One-hand hold on the SGG-101 (user report 2026-10-16: the arm drawing's hand place is out of reach of
# its arm, so the arm stretched out to the side and the hand looked off the forearm): the rest grip goes
# to ONE_HAND_GRIP (torso space) and the aim anchor to ONE_HAND_AIM_X; the SMG and Shotgun .tres files
# got the same places by hand.
ONE_HAND_GRIP = (2.55, -0.2, -1.9)
ONE_HAND_AIM_X = 2.55
RIFLE_REST_GRIP = (3.5253, -0.449447, -1.659444)  # where RIFLE_REST put the grip socket (measured)


def shifted_rest(rest, old_grip, new_grip):
    """Rest transform text moved so the grip goes from old_grip to new_grip (torso space)."""
    v = [float(x) for x in rest[rest.index("(") + 1:rest.rindex(")")].split(",")]
    for i in range(3):
        v[9 + i] += new_grip[i] - old_grip[i]
    return "Transform3D(" + ", ".join(f"{x:.5g}" for x in v) + ")"


RIFLE_REST = shifted_rest(RIFLE_REST, RIFLE_REST_GRIP, ONE_HAND_GRIP)
MATS = {
    "rifle": "res://materials/warden/rifle.tres", "dark": "res://materials/warden/rifle_dark.tres",
    "armor": "res://materials/warden/armor.tres", "joint": "res://materials/warden/joint.tres",
    "beam": "res://materials/effects/beam.tres", "beam_core": "res://materials/effects/beam_core.tres",
    "frame": "res://materials/warden/frame.tres",
}


def write_model(path, root, script, build, root_transform=None, extra_ext=(), root_meta=None):
    b = Builder()
    nodes = []
    def part(name, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0), parent="."):
        b.nodes = []
        b.part(name, parent, mat, kind, params, pos, rot)
        nodes.extend(b.nodes)
    def marker(name, pos, rot=(0, 0, 0), parent=".", meta=None):
        text = f'[node name="{name}" type="Marker3D" parent="{parent}"]\ntransform = {xf(pos, rot)}\n'
        for key, value in (meta or {}).items():
            text += f'metadata/{key} = {value}\n'
        nodes.append(text)
    build(part, marker)
    o = ['[gd_scene format=3]\n', f'[ext_resource type="Script" path="res://scripts/weapons/{script}.gd" id="script"]']
    for mid, p in MATS.items():
        o.append(f'[ext_resource type="Material" path="{p}" id="{mid}"]')
    o += list(extra_ext)
    o.append('')
    o.append(b.sub_text())
    head = f'[node name="{root}" type="Node3D"]\n'
    if root_transform:
        head += f'transform = {root_transform}\n'
    head += 'script = ExtResource("script")\n'
    for key, value in (root_meta or {}).items():
        head += f'metadata/{key} = {value}\n'
    o.append(head)
    o += nodes
    open(path, "w").write("\n".join(o))
    print("wrote", path)


# Right elbow hints of the Beam Sniper (user request 2026-10-24; read by SkeletalArmRig._right_elbow_hint):
# torso-space directions from the shoulder to the elbow, blended by the aim amount.
SNIPER_ELBOW = {"elbow_rest": "Vector3(0.67, -0.74, 0.0)", "elbow_aim": "Vector3(0.55, -0.84, -0.05)"}


def sniper(part, marker):
    """Beam sniper, 7.4 m. -Z forward. Held with two hands."""
    part("Stock", "rifle", "box", (0.4, 0.7, 1.3), (0, -0.05, -0.6))
    part("StockPad", "dark", "box", (0.44, 0.85, 0.2), (0, -0.05, 0.05))
    part("Body", "rifle", "box", (0.55, 0.85, 2.6), (0, 0.05, -2.3))
    part("CellL", "beam", "box", (0.05, 0.25, 1.6), (-0.29, 0.1, -2.3))
    part("CellR", "beam", "box", (0.05, 0.25, 1.6), (0.29, 0.1, -2.3))
    part("Grip", "dark", "box", (0.3, 0.7, 0.35), (0, -0.62, -1.4), (-20, 0, 0))
    part("ForeGrip", "dark", "box", (0.26, 0.65, 0.3), (0, -0.6, -2.9), (-10, 0, 0))
    part("Scope", "rifle", "box", (0.32, 0.42, 1.8), (0, 0.72, -2.3))
    part("ScopeLens", "beam", "cyl", (0.14, 0.14, 0.05), (0, 0.72, -3.22), (90, 0, 0))
    part("Barrel", "rifle", "box", (0.34, 0.4, 3.2), (0, 0.05, -5.2))
    for i, z in enumerate((-4.2, -5.0, -5.8)):
        part(f"Coil{i}", "dark", "cyl", (0.3, 0.3, 0.25), (0, 0.05, z), (90, 0, 0))
    # Emitter: a flat lens set into the barrel face (it lights up with the charge, BeamRifleWeapon).
    part("Emitter", "dark", "cyl", (0.14, 0.14, 0.04), (0, 0.05, -6.81), (90, 0, 0))
    # Hand markers (arm IK targets, the palm socket bone): placed so the fist hollow sits on the grip
    # sockets (measured in the game, 2026-10-13); the right one slides from rest to aim like the left.
    marker("GripRight", SNIPER_HANDS["right_rest"])
    marker("GripRightRest", SNIPER_HANDS["right_rest"])
    marker("GripRightAim", SNIPER_HANDS["right_aim"])
    # Grip sockets: on the grip and foregrip axes, nearest the hand markers.
    marker("GripSocketRight", (0, -0.514, -1.439), (-20, 0, 0), meta={"grip_radius": 0.15, "hand_reach": "true"})
    marker("GripSocketLeft", (0, -0.454, -2.926), (-10, 0, 0), meta={"grip_radius": 0.14, "hand_reach": "true"})
    # Aim (user request 2026-10-18): the left hand cups the underside of the barrel between the first two
    # coils, about 65% of the way from the butt to the muzzle (was under the body at z -2.2).
    marker("GripSocketLeftAim", SNIPER_LEFT_AIM, (-90, 0, 0), meta={"grip_radius": 0.2, "hand_reach": "true"})
    marker("GripLeft", SNIPER_HANDS["left_rest"])
    marker("GripLeftRest", SNIPER_HANDS["left_rest"])
    # Aim: out on the barrel (SNIPER_LEFT_AIM), as far forward as the left arm reaches at level aim.
    marker("GripLeftAim", SNIPER_HANDS["left_aim"])
    # Low aim (user choice 2026-10-18, "Slide hand back"): aiming down, the left hand slides back to its
    # old place under the body (WeaponPose low_aim_start_deg / low_aim_full_deg).
    marker("GripSocketLeftAimLow", SNIPER_LEFT_AIM_LOW, (-90, 0, 0), meta={"grip_radius": 0.2, "hand_reach": "true"})
    marker("GripLeftAimLow", SNIPER_HANDS["left_aim_low"])
    marker("Muzzle", (0, 0.05, -7.15))


def pile_bunker(part, marker):
    """Pile bunker. The root is the fist target (the hand holds nothing). The model is under "Mount",
    which PileBunkerWeapon moves onto the right forearm (like the shield on the left forearm).
    Mount space: -Z along the forearm toward the fist, +X to the outer side. The stake (the "needle")
    points along -Z. The Stake node slides out when it fires."""
    marker("GripRight", (0, 0, 0))
    marker("Mount", (0, 0, 0))
    m = "Mount"
    part("Housing", "armor", "box", (0.8, 1.1, 3.6), (0, 0, -0.6), parent=m)
    part("HousingRail", "dark", "box", (0.85, 0.3, 3.2), (0, 0.65, -0.5), parent=m)
    part("Clamp0", "frame", "box", (1.9, 1.5, 0.3), (-0.55, 0, 0.6), parent=m)
    part("Clamp1", "frame", "box", (1.9, 1.5, 0.3), (-0.55, 0, -1.2), parent=m)
    part("Drum", "joint", "cyl", (0.45, 0.45, 0.7), (0.25, 0.6, 0.5), (0, 0, 90), parent=m)
    part("NoseRing", "dark", "cyl", (0.42, 0.42, 0.3), (0, 0, -2.45), (90, 0, 0), parent=m)
    marker("Stake", (0, 0, -1.0), parent=m)
    part("StakeRod", "frame", "cyl", (0.2, 0.2, 3.2), (0, 0, -0.2), (90, 0, 0), parent=f"{m}/Stake")
    part("StakeTip", "rifle", "cyl", (0.2, 0.02, 0.7), (0, 0, -2.15), (90, 0, 0), parent=f"{m}/Stake")
    marker("Nose", (0, 0, -2.6), parent=m)


def pod(part, marker):
    """Missile pod: a box with 2 x 2 tubes on the front. -Z forward."""
    part("Box", "armor", "box", (1.5, 1.3, 2.2), (0, 0, 0))
    part("Face", "dark", "box", (1.3, 1.1, 0.15), (0, 0, -1.12))
    part("Mount", "joint", "box", (0.6, 0.5, 1.2), (0, -0.8, 0.2))
    for i, (x, y) in enumerate(((-0.33, 0.28), (0.33, 0.28), (-0.33, -0.28), (0.33, -0.28))):
        part(f"Tube{i}", "frame", "cyl", (0.24, 0.24, 0.12), (x, y, -1.2), (90, 0, 0))
        marker(f"Launch{i}", (x, y, -1.3))


# Beam Rifle (user design, models/beam_rifle): picture pixels of tools/blender/beam_rifle_build.py.
BR_K = 6.0 / (1728 - 492)
BR_GRIP_RIGHT = (0.0, (241 - 368) * BR_K, -(1728 - 1340) * BR_K)
BR_GRIP_LEFT = (0.0, (241 - 318) * BR_K, -(1728 - 1000) * BR_K)
BR_MUZZLE = (0.0, 0.0, -6.0)
## Beam Rifle rest (user request 2026-10-13): the left hand holds the lower rail this far ahead of the
## pistol grip, out near the barrel (the rail runs from z -2.37 to -6.0).
BR_LEFT_REST_SPACING = 3.2
BR_LEFT_REST = (0.0, BR_GRIP_LEFT[1], BR_GRIP_RIGHT[2] - BR_LEFT_REST_SPACING)
## Beam Rifle aim (user request 2026-10-18: the left hand sat too close to the right hand): the left hand
## holds the lower rail this far ahead of the pistol grip, about 70% of the way from the butt to the
## muzzle. Farther forward the left upper arm reaches its swing limit (SkeletalArmRig) at level aim.
BR_LEFT_AIM_SPACING = 2.3
BR_LEFT_AIM = (0.0, BR_GRIP_LEFT[1], BR_GRIP_RIGHT[2] - BR_LEFT_AIM_SPACING)
SNIPER_GRIP_RIGHT = (0.0, -0.5, -1.4)
## Beam Sniper aim (user request 2026-10-18): the left aim socket on the barrel (center height, between the
## coils at z -4.2 and -5.0), about 65% of the way from the butt to the muzzle.
SNIPER_LEFT_AIM = (0.0, 0.05, -4.6)
## Low aim (user choice 2026-10-18, "Slide hand back"): aiming down, the left hand slides back along the
## rifle to these places (the old aim holds near the right hand), so the left upper arm stays inside its
## swing limit and the arm rig does not drag the rifle to the hand (WeaponPose low_aim_*_deg).
BR_LEFT_AIM_LOW = (0.0, BR_GRIP_LEFT[1], BR_GRIP_LEFT[2] + 0.8)
SNIPER_LEFT_AIM_LOW = (0.0, -0.3, -2.2)


def plus(a, b):
    return tuple(round(x + y, 4) for x, y in zip(a, b))


# Two-hand rifle hand markers (grip sockets, 2026-10-13): the arm IK target is the palm socket bone,
# about 0.3 m from the fist hollow, so each marker sits off its grip socket by the gap measured in the
# game (hand turned to the grip, fist hollow on the socket), at rest and at aim.
SNIPER_HANDS = {
    "right_rest": plus(SNIPER_GRIP_RIGHT, (-0.1, 0.739, -0.163)),  # Close rest (2026-10-13).
    "right_aim": plus(SNIPER_GRIP_RIGHT, (-0.051, 0.427, -0.291)),
    "left_rest": plus((0.0, -0.45, -2.9), (0.079, 0.061, 0.208)),
    "left_aim": plus(SNIPER_LEFT_AIM, (0.197, -0.157, 0.085)),
    "left_aim_low": plus((0.0, -0.45, -2.2), (0.115, 0.391, 0.143)),
}
BR_HANDS = {
    "right_rest": plus(BR_GRIP_RIGHT, (0.051, 0.406, -0.249)),
    "right_aim": plus(BR_GRIP_RIGHT, (-0.043, 0.594, -0.237)),
    "left_rest": plus(BR_LEFT_REST, (0.146, -0.06, 0.305)),
    "left_aim": plus(BR_LEFT_AIM, (0.185, -0.103, 0.192)),
    "left_aim_low": plus(BR_LEFT_AIM_LOW, (0.145, 0.22, 0.07)),
}


def beam_rifle_scene(path):
    """Beam Rifle scene: the Blender model (.glb) under a BeamRifleWeapon root, plus the hand and
    muzzle markers. The cyan ring lights up while charging, the muzzle bore is the emitter, the 3 lamps on the
    stock (Indicator1..3) show the charge level."""
    o = ['[gd_scene format=3]\n',
         '[ext_resource type="Script" path="res://scripts/weapons/beam_rifle_weapon.gd" id="script"]',
         '[ext_resource type="PackedScene" path="res://models/beam_rifle/beam_rifle.glb" id="model"]\n',
         '[node name="BeamRifle" type="Node3D"]',
         'script = ExtResource("script")',
         'coil_paths = Array[NodePath]([NodePath("Model/Coil0")])',
         'emitter_path = NodePath("Model/MuzzleBore")',
         'lamp_paths = Array[NodePath]([NodePath("Model/Indicator1"), NodePath("Model/Indicator2"), NodePath("Model/Indicator3")])\n',
         '[node name="Model" parent="." instance=ExtResource("model")]\n']
    # Hand markers: the fist hollows on the grip sockets (see SNIPER_HANDS).
    for name, pos in (("GripRight", BR_HANDS["right_rest"]), ("GripRightRest", BR_HANDS["right_rest"]),
                      ("GripRightAim", BR_HANDS["right_aim"]), ("GripLeft", BR_HANDS["left_rest"]),
                      ("GripLeftRest", BR_HANDS["left_rest"]), ("GripLeftAim", BR_HANDS["left_aim"]),
                      ("GripLeftAimLow", BR_HANDS["left_aim_low"]), ("Muzzle", BR_MUZZLE)):
        o.append(f'[node name="{name}" type="Marker3D" parent="."]\ntransform = {xf(pos)}\n')
    # Grip sockets: the pistol grip (tilted 24 deg, 0.24 x 0.45 m) and the lower rail (along the gun).
    # Radius 0.26 (was 0.16): the grip mesh is 0.24 x 0.45 m, the fingers sank 0.08 m into it (2026-10-22).
    o.append(grip_socket("GripSocketRight", BR_GRIP_RIGHT, 24.0, 0.26, hand_reach=True))
    o.append(grip_socket("GripSocketLeft", BR_LEFT_REST, 90.0, 0.15, hand_reach=True))
    o.append(grip_socket("GripSocketLeftAim", BR_LEFT_AIM, 90.0, 0.15, hand_reach=True))
    o.append(grip_socket("GripSocketLeftAimLow", BR_LEFT_AIM_LOW, 90.0, 0.15, hand_reach=True))
    open(path, "w").write("\n".join(o))
    print("wrote", path)


def res(path, props, scene=None):
    lines = ['[gd_resource type="Resource" script_class="WeaponData" format=3]\n',
             '[ext_resource type="Script" path="res://scripts/data/weapon_data.gd" id="script"]']
    if scene:
        lines.append(f'[ext_resource type="PackedScene" path="{scene}" id="scene"]')
    lines.append('\n[resource]\nscript = ExtResource("script")')
    lines += [f"{k} = {v}" for k, v in props.items()]
    if scene:
        lines.append('scene = ExtResource("scene")')
    open(path, "w").write("\n".join(lines) + "\n")
    print("wrote", path)


def v3(p):
    return f"Vector3({p[0]:.4f}, {p[1]:.4f}, {p[2]:.4f})"


if __name__ == "__main__":
    os.makedirs("scenes/weapons", exist_ok=True)
    write_model("scenes/weapons/beam_sniper.tscn", "BeamSniper", "beam_rifle_weapon", sniper, root_meta=SNIPER_ELBOW)
    write_model("scenes/weapons/pile_bunker.tscn", "PileBunker", "pile_bunker_weapon", pile_bunker)
    # Pods sit above the shoulders, behind the head (torso space), tilted 10 degrees up.
    for side, sign in (("l", -1), ("r", 1)):
        place = xf(TT(*torso_point((sign * 1.6, 10.1, 1.2), K)), (10, 0, 0))
        write_model(f"scenes/weapons/missile_pod_{side}.tscn", f"MissilePod{side.upper()}", "missile_pod_weapon", pod, place)

    common = {"slot": 0}
    # Heavy rifle: one hand (arm drawing poses above).
    RIFLE_HIP = gun_aim_anchor(RIFLE_GRIP, RIFLE_OUT_DEG)
    RIFLE_HIP = (ONE_HAND_AIM_X, RIFLE_HIP[1], RIFLE_HIP[2])
    res("data/weapons/heavy_rifle.tres", {"display_name": '"Heavy Rifle"', "weight_t": 2.0, "hp": 300.0,
        "kind": 0, "fire_rate": 0.33333, "damage": 90.0, "stagger_points": 18.0, "projectile_speed": 400.0, "spread_deg": 0.4,
        "range_m": 310.0, "effective_range_m": 155.0,
        "recoil_up_deg": 2.0, "recoil_side_deg": 0.8, "model_kick_back": 0.7, "model_kick_up_deg": 10.0,
        "shake_trauma": 0.25, "shake_kick": 0.12, "magazine": 12, "reload_time": 3.5,
        # Forearm line (2026-10-24): found by the in-game solver tools/godot/measure_arms_solve.gd: the gun axis lies
        # along the forearm at rest and aim (the aim wrist is the same place for all three guns); at rest the arm is the empty arm's hang pose moved 0.4 m out and 0.2 m up
        # (so the shoulder blocks match the empty side) and the gun is rolled 16 deg (keeps off the thigh and the
        # forearm armor). The same for the SMG and the Shotgun.
        "rest_transform": "Transform3D(0.944414, -0.0353381, -0.326854, 0.2266064, 0.7902704, 0.5693173, 0.2381845, -0.6117384, 0.7543503, 2.1944599, 0.5915485, -1.7262977)",
        "aim_anchor": "Vector3(1.5708, 1.7383, -1.6552)",
        "right_pole_rest": v3(ONE_HAND["right_pole_rest"]), "right_pole_aim": v3(ONE_HAND["right_pole_aim"])},
        "res://scenes/weapons/heavy_rifle.tscn")
    # Two-hand rest (beam sniper and Beam Rifle; user drawing 2026-10-12): across the front of the body,
    # muzzle left and a little down, right hand on the grip at two_hand_hand (torso space), left hand
    # supporting the forestock. Both shoulder blocks flat and facing forward (no turn), the forearms
    # forward: each hand is one forearm (2.71 m) from its elbow under the flat block. Places found by
    # search (no weapon or forearm point inside the body part boxes, the stock off the right forearm,
    # the barrel off the left forearm), then checked in the game (no clipping on either rifle).
    # Grip sockets (2026-10-13): the hands lower and further forward, the muzzle straight across the
    # body and 15 deg down (was 20 deg down and forward), so the right forearm runs across the pistol
    # grip and the fist closes around it (before: the forearm ran up along the grip, a 50 deg wrist
    # bend). Found by search: wrist bends at most 30 deg, no clipping.
    # Close rest (user request 2026-10-13: the low rest put the left hand into the left thigh while
    # walking and boosting): the pistol grip socket at (1.0, 1.2, -1.85) torso space, in front of the
    # chest; the muzzle to the left, 10 deg down and 15 deg forward. Found by search in the game (148
    # poses: weapon and hand points inside body meshes while standing, walking, strafing, boosting and
    # stopping); the poses next to it are clear too.
    two_hand_hand = (1.0, 1.2, -1.85)
    sniper_dir = (-math.cos(math.radians(15)) * math.cos(math.radians(10)), -math.sin(math.radians(10)),
                  -math.sin(math.radians(15)) * math.cos(math.radians(10)))
    rest_rows = xf_aim(sniper_dir, (0.0, 1.0, 0.0), two_hand_hand)
    stock_rest = tuple(h - g for h, g in zip(two_hand_hand, apply_rows(rest_rows, (0.0, -0.514, -1.439))))
    # Beam sniper: two hands. Aim = stock at the chest, zoom.
    # Stock in front of the chest (torso space; the torso front is at z -1.6).
    # Sniping stance (user reference 2026-10-12): the rifle level across the turned chest (hips 45 deg,
    # SkeletalAimStance, plus aim_twist_deg 25). Grip sockets (2026-10-13): the butt 0.8 m lower (at the
    # front of the chest, was the front of the right shoulder) and 0.5 m further out, so the right fist
    # lines up with the pistol grip and the stock keeps off the right forearm (found by search).
    # Aim hold (user request 2026-10-24): 0.4 m out and 0.3 m up from the old (1.9, 1.2, -1.5), so the right
    # elbow sits out under a level shoulder block and the stock keeps off the forearm armor (measure_arms_search.gd).
    sniper_anchor = (2.3, 1.5, -1.5)
    res("data/weapons/beam_sniper.tres", {"display_name": '"Beam Sniper"', "weight_t": 4.0, "hp": 300.0,
        "kind": 1, "two_handed": "true", "fire_rate": 0.16667, "damage": 225.0, "stagger_points": 32.0, "spread_deg": 0.05, "range_m": 337.5,
        "effective_range_m": 168.75,
        "recoil_up_deg": 3.5, "recoil_side_deg": 0.5, "model_kick_back": 0.5, "model_kick_up_deg": 6.0,
        "shake_trauma": 0.1, "shake_kick": 0.15, "heat_per_use": 34.0, "heat_cooling": 10.0, "overheat_cooling": 25.0,
        "rest_transform": xf_rows(rest_rows, stock_rest), "aim_anchor": v3(sniper_anchor),
        "right_pole_rest": v3((1.0, -0.6, 0.4)), "right_pole_aim": v3((1.0, -0.6, 0.3)),
        "left_pole_rest": v3((-1.0, -0.5, 0.3)), "left_pole_aim": v3((-0.4, -1.0, 0.0)),
        "aim_twist_deg": 25.0, "aim_tilt_deg": 4.0, "zoom_fov": 43.4},
        "res://scenes/weapons/beam_sniper.tscn")
    # Beam Rifle: two hands, right hand on the pistol grip, left hand under the lower rail. Aim = the
    # sniper hold.
    beam_rifle_scene("scenes/weapons/beam_rifle.tscn")
    # Rest (user requests 2026-10-13): across the body at groin height, the muzzle 10 deg down to the
    # left (was 45 deg), the pistol grip right of the groin, the left hand out on the rail near the
    # barrel (BR_LEFT_REST_SPACING). Found by search in the game: no clipping at rest and while moving
    # (WeaponBounce).
    br_hand = (1.0, 0.6, -2.3)
    br_rows = xf_aim((-0.9848, -0.1736, 0.0), (0.0, 1.0, 0.0), br_hand)
    br_rest = tuple(h - g for h, g in zip(br_hand, apply_rows(br_rows, BR_GRIP_RIGHT)))
    # The same butt place as the sniper (grip sockets, 2026-10-13).
    br_anchor = (1.9, 1.2, -1.5)
    res("data/weapons/beam_rifle.tres", {"display_name": '"Beam Rifle"', "weight_t": 3.5, "hp": 300.0,
        "kind": 1, "two_handed": "true", "fire_rate": 0.25, "damage": 225.0, "stagger_points": 102.0, "stagger_cap_per_shot": 102.0, "spread_deg": 0.05, "range_m": 225.0,
        "effective_range_m": 112.5,
        "recoil_up_deg": 3.5, "recoil_side_deg": 0.5, "model_kick_back": 0.5, "model_kick_up_deg": 6.0,
        "shake_trauma": 0.1, "shake_kick": 0.15, "heat_per_use": 34.0, "heat_cooling": 10.0, "overheat_cooling": 25.0,
        "rest_transform": xf_rows(br_rows, br_rest), "aim_anchor": v3(br_anchor),
        "right_pole_rest": v3((1.0, -0.6, 0.4)), "right_pole_aim": v3((1.0, -0.6, 0.3)),
        "left_pole_rest": v3((-1.0, -0.5, 0.3)), "left_pole_aim": v3((-0.4, -1.0, 0.0)),
        "aim_twist_deg": 25.0, "aim_tilt_deg": 4.0, "zoom_fov": 43.4},
        "res://scenes/weapons/beam_rifle.tscn")
    # Pile bunker: on the forearm like the auto cannon (user, 2026-10-12): the fist (weapon root) at the
    # drawing's hand places, elbow 45 deg at neutral, 90 deg when aiming.
    # The forearm turns out like the auto cannon's (CANNON_OUT_DEG), so the clamps clear the thigh.
    bunker_hand = arm_poses.hand(arm_poses.ELBOW_R, arm_poses.NEUTRAL_DEG, arm_poses.CANNON_OUT_DEG)
    bunker_rest = one_hand_rest(hand=(bunker_hand[0], bunker_hand[1] + WAIST, bunker_hand[2]),
                                muzzle_dir=arm_poses.forearm_dir(arm_poses.NEUTRAL_DEG, arm_poses.CANNON_OUT_DEG),
                                up_hint=arm_poses.top_side(arm_poses.NEUTRAL_DEG), grip=(0, 0, 0))
    bunker_aim = RIGHT_HAND_AIM
    res("data/weapons/pile_bunker.tres", {"display_name": '"Pile Bunker"', "weight_t": 2.5, "hp": 300.0,
        "kind": 5, "fire_rate": 0.16667,  # 1 punch per 6 s (user 2026-10-15)
        "damage": 675.0, "stagger_points": 30.0, "magazine": 3, "reload_time": 5.0,
        "lunge_distance": 16.0, "lunge_speed": 32.0, "lunge_energy": 20.0,
        "shake_trauma": 0.45, "shake_kick": 0.6, "recoil_up_deg": 2.0, "recoil_side_deg": 1.0,
        "rest_transform": bunker_rest, "aim_anchor": v3(bunker_aim),
        "right_pole_rest": v3((0.6, -1.0, 0.3)), "right_pole_aim": v3((0.6, -1.0, 0.4))},
        "res://scenes/weapons/pile_bunker.tscn")
    for side in ("l", "r"):
        res(f"data/weapons/missile_pod_{side}.tres", {"display_name": f'"Missile Pod {side.upper()}"', "weight_t": 3.0, "hp": 250.0,
            "kind": 3, "slot": 1, "fire_rate": 1.0, "damage": 112.5, "stagger_points": 10.0, "stagger_cap_per_shot": 30.0, "projectile_speed": 90.0, "range_m": 250.0,
            "magazine": 4, "reload_time": 6.0, "lock_box_deg": 7.0, "lock_time": 0.5, "missile_turn_deg": 110.0,
            "recoil_up_deg": 0.3, "recoil_side_deg": 0.3, "shake_trauma": 0.08, "shake_kick": 0.1},
            f"res://scenes/weapons/missile_pod_{side}.tscn")
    res("data/weapons/warden_shield.tres", {"display_name": '"Hex Shield"', "weight_t": 3.0, "hp": 1200.0,
        "kind": 4, "shield_area_m2": round(ONE_HAND["shield_area"], 3), "shield_scale": SHIELD_SCALE,
        # Large shield (user's arm drawing 2026-10-12): elbow 90 deg, forearm level.
        "shield_hand": v3(arm_poses.hand(arm_poses.ELBOW_L, arm_poses.AIM_DEG)), "blocks_dodge": "true"},
        "res://scenes/weapons/warden_shield.tscn")
