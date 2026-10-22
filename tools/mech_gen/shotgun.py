"""Shotgun (user request 2026-10-15): the weapon scene and its data file. Run from the project root:
    python3 tools/mech_gen/shotgun.py
Placeholder model from boxes and cylinders (pump shotgun: long barrel, tube magazine under it, pump
grip, pistol grip, short stock), 4.65 m long, -Z forward, bore on the Y = 0 line. One hand (right arm),
held like the heavy rifle and the SMG (arm drawing poses). Fires 8 pellets per shot (GunWeapon).
The PS1 skin comes from PS1SkinLook (it skins every weapon mesh under the mech).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Builder, xf
from weapons import res, v3, gun_on_forearm_rest, gun_aim_anchor, grip_socket
import arm_poses

LENGTH = 4.65
## The forearm turns this much out to the side (rest and aim; the gun still points ahead), so the low
## stock passes beside the forearm (same as the SMG).
OUT_DEG = 30.0
# Pistol grip: top inside the receiver, leaning back like the heavy rifle's (rake 20 deg, top forward).
GRIP_TOP = (0.0, -0.2, -1.7)
GRIP_AXIS = (0.0, -0.9397, 0.342)
GRIP_LENGTH = 0.96
## The fist holds the grip this far down from the top (high, the fist top meets the receiver).
GRIP_HOLD = 0.45
GRIP_RAKE = 20.0
## Half thickness of the grip (the fingers close on it).
GRIP_RADIUS = 0.11
GRIP_HOLD_POINT = tuple(t + a * GRIP_HOLD for t, a in zip(GRIP_TOP, GRIP_AXIS))
# GripRight marker: the palm socket place, so the fist hollow is on the hold point.
GRIP = arm_poses.palm_socket(GRIP_HOLD_POINT)
MUZZLE = (0.0, 0.0, -LENGTH)

MATERIALS = {
    # id: (color, metallic, roughness)
    "metal": ((0.17, 0.18, 0.19), 0.6, 0.5),
    "dark": ((0.07, 0.07, 0.08), 0.5, 0.55),
    "poly": ((0.11, 0.095, 0.085), 0.1, 0.8),
}


def material_text(color, metallic, roughness):
    return ('[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n'
            f'albedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n'
            f'metallic = {metallic}\nroughness = {roughness}\n')


def build(b):
    P = "."
    # Short stock and pad (butt at Z = 0).
    b.part("Stock", P, "poly", "box", (0.24, 0.55, 1.0), (0, -0.12, -0.6))
    b.part("StockPad", P, "dark", "box", (0.3, 0.7, 0.12), (0, -0.14, -0.06))
    # Receiver, ejection port on the right, rear sight.
    b.part("Receiver", P, "metal", "box", (0.4, 0.5, 1.5), (0, -0.02, -1.85))
    b.part("EjectionPort", P, "dark", "box", (0.04, 0.16, 0.45), (0.2, 0.06, -1.9))
    b.part("RearSight", P, "dark", "box", (0.14, 0.1, 0.06), (0, 0.28, -1.3))
    # Pistol grip and trigger guard.
    centre = tuple(t + a * GRIP_LENGTH / 2 for t, a in zip(GRIP_TOP, GRIP_AXIS))
    b.part("Grip", P, "poly", "box", (0.2, GRIP_LENGTH, 0.24), centre, (-GRIP_RAKE, 0, 0))
    b.part("TriggerGuardBottom", P, "dark", "box", (0.06, 0.05, 0.62), (0, -0.46, -2.0))
    b.part("TriggerGuardFront", P, "dark", "box", (0.06, 0.28, 0.06), (0, -0.33, -2.3))
    # Barrel on the bore line, top rib, front bead and choke ring.
    b.part("Barrel", P, "metal", "cyl", (0.1, 0.1, 2.05), (0, 0, -3.625), (90, 0, 0))
    b.part("TopRib", P, "dark", "box", (0.06, 0.04, 2.0), (0, 0.12, -3.6))
    b.part("FrontBead", P, "dark", "box", (0.04, 0.1, 0.04), (0, 0.17, -4.5))
    b.part("Choke", P, "dark", "cyl", (0.12, 0.12, 0.16), (0, 0, -4.57), (90, 0, 0))
    # Tube magazine under the barrel, end cap, clamp, and the pump grip around the tube.
    b.part("Tube", P, "metal", "cyl", (0.07, 0.07, 1.5), (0, -0.22, -3.35), (90, 0, 0))
    b.part("TubeCap", P, "dark", "cyl", (0.09, 0.09, 0.1), (0, -0.22, -4.12), (90, 0, 0))
    b.part("Clamp", P, "dark", "box", (0.18, 0.45, 0.14), (0, -0.11, -4.0))
    b.part("Pump", P, "poly", "box", (0.28, 0.26, 0.85), (0, -0.22, -3.1))
    for i, z in enumerate((-2.8, -3.1, -3.4)):
        b.part(f"PumpGroove{i}", P, "dark", "box", (0.3, 0.28, 0.05), (0, -0.22, z))


def scene_text():
    b = Builder()
    build(b)
    ext = ['[gd_scene format=3]\n',
           '[ext_resource type="Script" path="res://scripts/weapons/gun_weapon.gd" id="script"]',
           '[ext_resource type="Material" path="res://materials/effects/muzzle_flash.tres" id="flash"]',
           '[ext_resource type="Script" path="res://scripts/effects/muzzle_flash.gd" id="flash_script"]']
    for mid in MATERIALS:
        ext.append(f'[ext_resource type="Material" path="res://materials/shotgun/{mid}.tres" id="{mid}"]')
    o = ext + ['',
        '[sub_resource type="CylinderMesh" id="flash_cone"]\ntop_radius = 0.0\nbottom_radius = 0.3\nheight = 1.1\nradial_segments = 8\nrings = 1\n',
        '[sub_resource type="SphereMesh" id="flash_core"]\nradius = 0.26\nheight = 0.52\nradial_segments = 8\nrings = 4\n',
        b.sub_text(),
        '[node name="Shotgun" type="Node3D"]\nscript = ExtResource("script")\n']
    o += b.nodes
    o.append(f'[node name="GripRight" type="Marker3D" parent="."]\ntransform = {xf(GRIP)}\n')
    o.append(f'[node name="Muzzle" type="Marker3D" parent="."]\ntransform = {xf(MUZZLE)}\n')
    o.append(grip_socket("GripSocketRight", GRIP_HOLD_POINT, GRIP_RAKE, GRIP_RADIUS))
    o.append(f'''[node name="MuzzleFlash" type="Node3D" parent="Muzzle" node_paths=PackedStringArray("light")]
script = ExtResource("flash_script")
light = NodePath("Light")

[node name="Cone" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
transform = {xf((0, 0, -0.55), (-90, 0, 0))}
cast_shadow = 0
mesh = SubResource("flash_cone")
surface_material_override/0 = ExtResource("flash")

[node name="Core" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
cast_shadow = 0
mesh = SubResource("flash_core")
surface_material_override/0 = ExtResource("flash")

[node name="Light" type="OmniLight3D" parent="Muzzle/MuzzleFlash"]
light_color = Color(1, 0.72, 0.38, 1)
omni_range = 11.0
''')
    return "\n".join(o)


if __name__ == "__main__":
    os.makedirs("materials/shotgun", exist_ok=True)
    for mid, (color, metallic, roughness) in MATERIALS.items():
        open(f"materials/shotgun/{mid}.tres", "w").write(material_text(color, metallic, roughness))
    path = "scenes/weapons/shotgun.tscn"
    open(path, "w").write(scene_text())
    print("wrote", path)
    # Slow, heavy shot: 8 pellets of 9 damage (the game's -25% damage pass), wide cone, small magazine.
    res("data/weapons/shotgun.tres", {
        "display_name": '"Shotgun"', "weight_t": 2.5, "hp": 250.0, "kind": 0, "slot": 0,
        "fire_rate": round(1 / 1.1, 4), "damage": 9.0, "pellets": 8, "projectile_speed": 350.0, "spread_deg": 6.0,
        "recoil_up_deg": 3.0, "recoil_side_deg": 1.2, "model_kick_back": 0.6, "model_kick_up_deg": 8.0,
        "shake_trauma": 0.3, "shake_kick": 0.15, "magazine": 6, "reload_time": 3.0,
        "rest_transform": gun_on_forearm_rest(GRIP, OUT_DEG), "aim_anchor": v3(gun_aim_anchor(GRIP, OUT_DEG)),
        "right_pole_rest": v3((0.4, -1.0, 0.5)), "right_pole_aim": v3((0.4, -1.0, 0.5))},
        "res://scenes/weapons/shotgun.tscn")
