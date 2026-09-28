"""Warden weapons (Phase 3): beam sniper, beam blade, missile pods, and the weapon data files with
their poses for the Warden frame. The heavy rifle model comes from heavy_rifle.py and the shield
model from warden.py. Run from the project root."""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Builder, xf, xf_aim, xf_rows, apply_rows
from mech_scene import TT, torso_point, one_hand_rest
import warden

K = warden.UPPER_BODY_SCALE
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
    def marker(name, pos, rot=(0, 0, 0)):
        nodes.append(f'[node name="{name}" type="Marker3D" parent="."]\ntransform = {xf(pos, rot)}\n')
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
    part("Emitter", "beam_core", "cyl", (0.16, 0.2, 0.3), (0, 0.05, -6.95), (90, 0, 0))
    marker("GripRight", (0, -0.5, -1.4))
    marker("GripLeft", (0, -0.45, -2.9))
    marker("GripLeftRest", (0, -0.45, -2.9))
    marker("GripLeftAim", (0, -0.45, -2.7))
    marker("Muzzle", (0, 0.05, -7.15))


def blade(part, marker):
    """Beam blade. The hand holds the hilt. The glowing blade points along -Z."""
    part("Hilt", "dark", "cyl", (0.2, 0.2, 1.1), (0, 0, -0.3), (90, 0, 0))
    part("Pommel", "rifle", "cyl", (0.26, 0.26, 0.2), (0, 0, 0.3), (90, 0, 0))
    part("Guard", "rifle", "box", (0.9, 0.3, 0.25), (0, 0, -0.9))
    part("Emitter", "joint", "cyl", (0.24, 0.3, 0.3), (0, 0, -1.1), (90, 0, 0))
    part("Blade", "beam", "box", (0.18, 0.55, 5.0), (0, 0, -3.7))
    part("BladeCore", "beam_core", "box", (0.08, 0.25, 4.9), (0, 0, -3.7))
    marker("GripRight", (0, 0, -0.3))
    marker("BladeTip", (0, 0, -6.2))


def pod(part, marker):
    """Missile pod: a box with 2 x 2 tubes on the front. -Z forward."""
    part("Box", "armor", "box", (1.5, 1.3, 2.2), (0, 0, 0))
    part("Face", "dark", "box", (1.3, 1.1, 0.15), (0, 0, -1.12))
    part("Mount", "joint", "box", (0.6, 0.5, 1.2), (0, -0.8, 0.2))
    for i, (x, y) in enumerate(((-0.33, 0.28), (0.33, 0.28), (-0.33, -0.28), (0.33, -0.28))):
        part(f"Tube{i}", "frame", "cyl", (0.24, 0.24, 0.12), (x, y, -1.2), (90, 0, 0))
        marker(f"Launch{i}", (x, y, -1.3))


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
    write_model("scenes/weapons/beam_blade.tscn", "BeamBlade", "blade_weapon", blade)
    # Pods sit above the shoulders, behind the head (torso space), tilted 10 degrees up.
    for side, sign in (("l", -1), ("r", 1)):
        place = xf(TT(*torso_point((sign * 1.6, 10.1, 1.2), K)), (10, 0, 0))
        write_model(f"scenes/weapons/missile_pod_{side}.tscn", f"MissilePod{side.upper()}", "missile_pod_weapon", pod, place)

    common = {"slot": 0}
    # Heavy rifle: one hand, rest = ready to fire at the hip, hip fire.
    anchor = TT(*torso_point(warden.ONE_HAND["aim_anchor"], K))
    res("data/weapons/heavy_rifle.tres", {"display_name": '"Heavy Rifle"', "weight_t": 2.0, "hp": 300.0,
        "kind": 0, "fire_rate": 0.5, "damage": 120.0, "projectile_speed": 400.0, "spread_deg": 0.4,
        "recoil_up_deg": 2.0, "recoil_side_deg": 1.0, "model_kick_back": 0.7, "model_kick_up_deg": 10.0,
        "shake_trauma": 0.052, "shake_kick": 0.078, "magazine": 12, "reload_time": 3.5,
        "rest_transform": warden.RIFLE_REST, "aim_anchor": v3(anchor),
        "right_pole_rest": v3(warden.ONE_HAND["right_pole_rest"]), "right_pole_aim": v3(warden.ONE_HAND["right_pole_aim"])},
        "res://scenes/weapons/heavy_rifle.tscn")
    # Beam sniper: two hands. Rest = low ready across the body. Aim = stock at the chest, zoom.
    stock_rest = TT(*torso_point((1.6, 6.6, -1.4), K))
    rest_rows = xf_aim((-0.5, -0.35, -1.0), (0.0, 1.0, 0.0), stock_rest)
    sniper_anchor = TT(*torso_point((1.0, 8.0, -1.3), K))
    res("data/weapons/beam_sniper.tres", {"display_name": '"Beam Sniper"', "weight_t": 4.0, "hp": 300.0,
        "kind": 1, "two_handed": "true", "fire_rate": 1.25, "damage": 300.0, "spread_deg": 0.05, "range_m": 1500.0,
        "recoil_up_deg": 3.5, "recoil_side_deg": 0.5, "model_kick_back": 0.5, "model_kick_up_deg": 6.0,
        "shake_trauma": 0.1, "shake_kick": 0.15, "heat_per_use": 34.0, "heat_cooling": 10.0, "overheat_cooling": 25.0,
        "rest_transform": xf_rows(rest_rows, stock_rest), "aim_anchor": v3(sniper_anchor),
        "right_pole_rest": v3((1.0, -0.6, 0.4)), "right_pole_aim": v3((1.0, -0.6, 0.3)),
        "left_pole_rest": v3((-1.0, -0.5, 0.3)), "left_pole_aim": v3((-0.4, -1.0, 0.0)),
        "aim_twist_deg": 20.0, "aim_tilt_deg": 4.0, "zoom_fov": 52.6},
        "res://scenes/weapons/beam_sniper.tscn")
    # Beam blade: one hand, held upright in front of the right shoulder (reference image 12),
    # blade up and a little forward, edge facing forward.
    blade_rest = one_hand_rest(hand=(2.6, 7.0, -2.1), muzzle_dir=(0.05, 1.0, -0.12), up_hint=(0.0, 0.0, 1.0),
                               grip=(0, 0, -0.3), torso_scale=K)
    res("data/weapons/beam_blade.tres", {"display_name": '"Beam Blade"', "weight_t": 1.5, "hp": 200.0,
        "kind": 2, "fire_rate": 1.5, "damage": 400.0, "heat_per_use": 30.0, "heat_cooling": 22.0, "overheat_cooling": 30.0,
        "lunge_distance": 16.0, "lunge_speed": 32.0, "lunge_energy": 20.0, "slash_reach": 11.0,
        "shake_trauma": 0.1, "shake_kick": 0.1, "recoil_up_deg": 0.0, "recoil_side_deg": 0.0,
        "rest_transform": blade_rest, "aim_anchor": v3(anchor),
        "right_pole_rest": v3((0.25, -1.0, -0.2)), "right_pole_aim": v3((0.6, -1.0, 0.4))},
        "res://scenes/weapons/beam_blade.tscn")
    for side in ("l", "r"):
        res(f"data/weapons/missile_pod_{side}.tres", {"display_name": f'"Missile Pod {side.upper()}"', "weight_t": 3.0, "hp": 250.0,
            "kind": 3, "slot": 1, "fire_rate": 1.0, "damage": 150.0, "projectile_speed": 90.0, "range_m": 600.0,
            "magazine": 4, "reload_time": 6.0, "lock_box_deg": 7.0, "lock_time": 0.5, "missile_turn_deg": 110.0,
            "recoil_up_deg": 0.3, "recoil_side_deg": 0.3, "shake_trauma": 0.08, "shake_kick": 0.1},
            f"res://scenes/weapons/missile_pod_{side}.tscn")
    res("data/weapons/warden_shield.tres", {"display_name": '"Warden Hex Shield"', "weight_t": 3.0, "hp": 1200.0,
        "kind": 4, "shield_area_m2": round(warden.ONE_HAND["shield_area"], 3), "shield_scale": warden.SHIELD_SCALE},
        "res://scenes/weapons/warden_shield.tscn")
