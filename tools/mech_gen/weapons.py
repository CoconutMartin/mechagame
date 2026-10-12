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


def gun_on_forearm_rest(grip):
    """One-hand gun at neutral: grip in the fist, muzzle along the forearm, gun top away from it."""
    return one_hand_rest(hand=RIGHT_HAND_NEUTRAL, muzzle_dir=arm_poses.forearm_dir(arm_poses.NEUTRAL_DEG),
                         up_hint=arm_poses.top_side(arm_poses.NEUTRAL_DEG), grip=grip)


def gun_aim_anchor(grip):
    """Aim anchor (the gun origin) that puts the grip in the fist of the level forearm (aiming ahead)."""
    return arm_poses.minus(RIGHT_HAND_AIM, grip)


# Heavy rifle fist place (GripRight of heavy_rifle.py: low on its long pistol grip, user choice
# 2026-10-12, so the rifle rides clear above the forearm armor).
RIFLE_GRIP = (0.0, -0.89347, -0.80004)
RIFLE_REST = gun_on_forearm_rest(RIFLE_GRIP)
MATS = {
    "rifle": "res://materials/warden/rifle.tres", "dark": "res://materials/warden/rifle_dark.tres",
    "armor": "res://materials/warden/armor.tres", "joint": "res://materials/warden/joint.tres",
    "beam": "res://materials/effects/beam.tres", "beam_core": "res://materials/effects/beam_core.tres",
    "frame": "res://materials/warden/frame.tres",
}


def write_model(path, root, script, build, root_transform=None, extra_ext=()):
    b = Builder()
    nodes = []
    def part(name, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0), parent="."):
        b.nodes = []
        b.part(name, parent, mat, kind, params, pos, rot)
        nodes.extend(b.nodes)
    def marker(name, pos, rot=(0, 0, 0), parent="."):
        nodes.append(f'[node name="{name}" type="Marker3D" parent="{parent}"]\ntransform = {xf(pos, rot)}\n')
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
    o.append(head)
    o += nodes
    open(path, "w").write("\n".join(o))
    print("wrote", path)


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
    marker("GripRight", (0, -0.5, -1.4))
    marker("GripLeft", (0, -0.45, -2.9))
    marker("GripLeftRest", (0, -0.45, -2.9))
    # Aim: nearer the right hand than at rest, so the left arm reaches with the stock off the chest.
    marker("GripLeftAim", (0, -0.45, -2.2))
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
SNIPER_GRIP_RIGHT = (0.0, -0.5, -1.4)


def beam_rifle_scene(path):
    """Beam Rifle scene: the Blender model (.glb) under a BeamRifleWeapon root, plus the hand and
    muzzle markers. The cyan ring lights up while charging, the muzzle bore is the emitter."""
    o = ['[gd_scene format=3]\n',
         '[ext_resource type="Script" path="res://scripts/weapons/beam_rifle_weapon.gd" id="script"]',
         '[ext_resource type="PackedScene" path="res://models/beam_rifle/beam_rifle.glb" id="model"]\n',
         '[node name="BeamRifle" type="Node3D"]',
         'script = ExtResource("script")',
         'coil_paths = Array[NodePath]([NodePath("Model/Coil0")])',
         'emitter_path = NodePath("Model/MuzzleBore")\n',
         '[node name="Model" parent="." instance=ExtResource("model")]\n']
    # Aim: the left hand 0.8 m nearer the right hand, so the stock stays off the chest (see br_anchor).
    br_left_aim = (BR_GRIP_LEFT[0], BR_GRIP_LEFT[1], BR_GRIP_LEFT[2] + 0.8)
    for name, pos in (("GripRight", BR_GRIP_RIGHT), ("GripLeft", BR_GRIP_LEFT), ("GripLeftRest", BR_GRIP_LEFT),
                      ("GripLeftAim", br_left_aim), ("Muzzle", BR_MUZZLE)):
        o.append(f'[node name="{name}" type="Marker3D" parent="."]\ntransform = {xf(pos)}\n')
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
    write_model("scenes/weapons/beam_sniper.tscn", "BeamSniper", "beam_rifle_weapon", sniper)
    write_model("scenes/weapons/pile_bunker.tscn", "PileBunker", "pile_bunker_weapon", pile_bunker)
    # Pods sit above the shoulders, behind the head (torso space), tilted 10 degrees up.
    for side, sign in (("l", -1), ("r", 1)):
        place = xf(TT(*torso_point((sign * 1.6, 10.1, 1.2), K)), (10, 0, 0))
        write_model(f"scenes/weapons/missile_pod_{side}.tscn", f"MissilePod{side.upper()}", "missile_pod_weapon", pod, place)

    common = {"slot": 0}
    # Heavy rifle: one hand (arm drawing poses above).
    RIFLE_HIP = gun_aim_anchor(RIFLE_GRIP)
    res("data/weapons/heavy_rifle.tres", {"display_name": '"Heavy Rifle"', "weight_t": 2.0, "hp": 300.0,
        "kind": 0, "fire_rate": 0.5, "damage": 120.0, "projectile_speed": 400.0, "spread_deg": 0.4,
        "recoil_up_deg": 2.0, "recoil_side_deg": 1.0, "model_kick_back": 0.7, "model_kick_up_deg": 10.0,
        "shake_trauma": 0.052, "shake_kick": 0.078, "magazine": 12, "reload_time": 3.5,
        "rest_transform": RIFLE_REST, "aim_anchor": v3(RIFLE_HIP),
        "right_pole_rest": v3(ONE_HAND["right_pole_rest"]), "right_pole_aim": v3(ONE_HAND["right_pole_aim"])},
        "res://scenes/weapons/heavy_rifle.tscn")
    # Two-hand rest (beam sniper and Beam Rifle; user drawing 2026-10-12): across the front of the body,
    # muzzle left and a little down, right hand on the grip at two_hand_hand (torso space), left hand
    # supporting the forestock. Both shoulder blocks flat and facing forward (no turn), the forearms
    # forward: each hand is one forearm (2.71 m) from its elbow under the flat block. Places found by
    # search (no weapon or forearm point inside the body part boxes, the stock off the right forearm,
    # the barrel off the left forearm), then checked in the game (no clipping on either rifle).
    two_hand_hand = (0.363, 1.01, -2.011)
    rest_rows = xf_aim((-0.894, -0.342, -0.29), (0.0, 1.0, 0.0), two_hand_hand)
    stock_rest = tuple(h - g for h, g in zip(two_hand_hand, apply_rows(rest_rows, SNIPER_GRIP_RIGHT)))
    # Beam sniper: two hands. Aim = stock at the chest, zoom.
    # Stock in front of the chest (torso space; the torso front is at z -1.6).
    # Sniping stance (user reference 2026-10-12): the butt against the front of the right shoulder, the
    # rifle level across the turned chest (hips 45 deg, SkeletalAimStance, plus aim_twist_deg 25).
    sniper_anchor = (1.4, 2.0, -1.7)
    res("data/weapons/beam_sniper.tres", {"display_name": '"Beam Sniper"', "weight_t": 4.0, "hp": 300.0,
        "kind": 1, "two_handed": "true", "fire_rate": 0.4, "damage": 300.0, "spread_deg": 0.05, "range_m": 1500.0,
        "recoil_up_deg": 3.5, "recoil_side_deg": 0.5, "model_kick_back": 0.5, "model_kick_up_deg": 6.0,
        "shake_trauma": 0.1, "shake_kick": 0.15, "heat_per_use": 34.0, "heat_cooling": 10.0, "overheat_cooling": 25.0,
        "rest_transform": xf_rows(rest_rows, stock_rest), "aim_anchor": v3(sniper_anchor),
        "right_pole_rest": v3((1.0, -0.6, 0.4)), "right_pole_aim": v3((1.0, -0.6, 0.3)),
        "left_pole_rest": v3((-1.0, -0.5, 0.3)), "left_pole_aim": v3((-0.4, -1.0, 0.0)),
        "aim_twist_deg": 25.0, "aim_tilt_deg": 4.0, "zoom_fov": 52.6},
        "res://scenes/weapons/beam_sniper.tscn")
    # Beam Rifle: two hands. Rest (neutral) = the two-hand rest above, right hand on the pistol grip,
    # left hand under the lower rail (Warden: left arm 92%, right 67%). Aim = the sniper hold with the
    # right hand at the same place (the grip is 0.48 m further from the butt than on the sniper).
    beam_rifle_scene("scenes/weapons/beam_rifle.tscn")
    br_hand = two_hand_hand
    br_rows = rest_rows
    br_rest = tuple(h - g for h, g in zip(br_hand, apply_rows(br_rows, BR_GRIP_RIGHT)))
    # The butt on the right shoulder (sniping stance), 0.4 m further out than the sniper's: the longer
    # stock then keeps off the right upper arm.
    br_anchor = (1.8, 2.0, -1.7)
    res("data/weapons/beam_rifle.tres", {"display_name": '"Beam Rifle"', "weight_t": 3.5, "hp": 300.0,
        "kind": 1, "two_handed": "true", "fire_rate": 0.4, "damage": 300.0, "spread_deg": 0.05, "range_m": 1500.0,
        "recoil_up_deg": 3.5, "recoil_side_deg": 0.5, "model_kick_back": 0.5, "model_kick_up_deg": 6.0,
        "shake_trauma": 0.1, "shake_kick": 0.15, "heat_per_use": 34.0, "heat_cooling": 10.0, "overheat_cooling": 25.0,
        "rest_transform": xf_rows(br_rows, br_rest), "aim_anchor": v3(br_anchor),
        "right_pole_rest": v3((1.0, -0.6, 0.4)), "right_pole_aim": v3((1.0, -0.6, 0.3)),
        "left_pole_rest": v3((-1.0, -0.5, 0.3)), "left_pole_aim": v3((-0.4, -1.0, 0.0)),
        "aim_twist_deg": 25.0, "aim_tilt_deg": 4.0, "zoom_fov": 52.6},
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
        "kind": 5, "fire_rate": 0.3333, "damage": 900.0, "magazine": 3, "reload_time": 5.0,
        "lunge_distance": 16.0, "lunge_speed": 32.0, "lunge_energy": 20.0,
        "shake_trauma": 0.45, "shake_kick": 0.6, "recoil_up_deg": 2.0, "recoil_side_deg": 1.0,
        "rest_transform": bunker_rest, "aim_anchor": v3(bunker_aim),
        "right_pole_rest": v3((0.6, -1.0, 0.3)), "right_pole_aim": v3((0.6, -1.0, 0.4))},
        "res://scenes/weapons/pile_bunker.tscn")
    for side in ("l", "r"):
        res(f"data/weapons/missile_pod_{side}.tres", {"display_name": f'"Missile Pod {side.upper()}"', "weight_t": 3.0, "hp": 250.0,
            "kind": 3, "slot": 1, "fire_rate": 1.0, "damage": 150.0, "projectile_speed": 90.0, "range_m": 600.0,
            "magazine": 4, "reload_time": 6.0, "lock_box_deg": 7.0, "lock_time": 0.5, "missile_turn_deg": 110.0,
            "recoil_up_deg": 0.3, "recoil_side_deg": 0.3, "shake_trauma": 0.08, "shake_kick": 0.1},
            f"res://scenes/weapons/missile_pod_{side}.tscn")
    res("data/weapons/warden_shield.tres", {"display_name": '"Hex Shield"', "weight_t": 3.0, "hp": 1200.0,
        "kind": 4, "shield_area_m2": round(ONE_HAND["shield_area"], 3), "shield_scale": SHIELD_SCALE,
        # Large shield (user's arm drawing 2026-10-12): elbow 90 deg, forearm level.
        "shield_hand": v3(arm_poses.hand(arm_poses.ELBOW_L, arm_poses.AIM_DEG))},
        "res://scenes/weapons/warden_shield.tscn")
