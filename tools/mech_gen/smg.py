"""SMG (user design 2026-10-11): the weapon scene and its data file. Run from the project root:
    python3 tools/mech_gen/smg.py
The model comes from tools/blender/smg_build.py (models/smg/smg.glb, 3.6 m). One hand (right arm),
held like the heavy rifle (the arm drawing poses). Fast, light shots.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import xf
from weapons import res, v3, gun_on_forearm_rest, gun_aim_anchor, grip_socket
import arm_poses

# Godot axes (Blender (x, y, z) is Godot (x, z, -y)): the Grip and Muzzle empties of smg_build.py.
PX = 3.6 / (870 - 67)
# The fist place on the pistol grip: keep these the same as smg_build.py (pistol grip extra length,
# and the fist place above its bottom end, in picture pixels).
GRIP_EXTRA_PX = 56
GRIP_HOLD_PX = 116
## The forearm turns this much out to the side (rest and aim; the SMG still points ahead), so the low
## stock pad passes beside the forearm with the fist right under the receiver.
OUT_DEG = 30.0
_GX, _GY = 607 - 555, 352 - 200
_GL = math.hypot(_GX, _GY)
_HOLD = (607 + _GX / _GL * (GRIP_EXTRA_PX - GRIP_HOLD_PX), 352 + _GY / _GL * (GRIP_EXTRA_PX - GRIP_HOLD_PX))
GRIP = (0.0, (138 - _HOLD[1]) * PX, -(870 - _HOLD[0]) * PX)
# GripRight marker: the palm socket place, so the fist hollow is on the hold point.
## Grip socket: the hold point on the pistol grip axis, its rake and half thickness (MechHandControl).
GRIP_HOLD_POINT = GRIP
GRIP_RAKE = math.degrees(math.atan2(_GX, _GY))
GRIP_RADIUS = 0.12
GRIP = arm_poses.palm_socket(GRIP)
MUZZLE = (0.0, 0.0, -3.6)
# Poses from the user's arm drawing (weapons.py): on top of the forearm, elbow 45 deg at neutral and
# 90 deg when aiming.

SCENE = '''[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/weapons/gun_weapon.gd" id="script"]
[ext_resource type="PackedScene" path="res://models/smg/smg.glb" id="model"]
[ext_resource type="Material" path="res://materials/effects/muzzle_flash.tres" id="flash"]
[ext_resource type="Script" path="res://scripts/effects/muzzle_flash.gd" id="flash_script"]

[sub_resource type="CylinderMesh" id="flash_cone"]
top_radius = 0.0
bottom_radius = 0.22
height = 0.8
radial_segments = 8
rings = 1

[sub_resource type="SphereMesh" id="flash_core"]
radius = 0.18
height = 0.36
radial_segments = 8
rings = 4

[node name="Smg" type="Node3D"]
script = ExtResource("script")

[node name="Model" parent="." instance=ExtResource("model")]

[node name="GripRight" type="Marker3D" parent="."]
transform = {grip}

[node name="Muzzle" type="Marker3D" parent="."]
transform = {muzzle}

{socket}
[node name="MuzzleFlash" type="Node3D" parent="Muzzle" node_paths=PackedStringArray("light")]
script = ExtResource("flash_script")
light = NodePath("Light")

[node name="Cone" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 0, -0.4)
cast_shadow = 0
mesh = SubResource("flash_cone")
surface_material_override/0 = ExtResource("flash")

[node name="Core" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
cast_shadow = 0
mesh = SubResource("flash_core")
surface_material_override/0 = ExtResource("flash")

[node name="Light" type="OmniLight3D" parent="Muzzle/MuzzleFlash"]
light_color = Color(1, 0.75, 0.4, 1)
omni_range = 9.0
'''

if __name__ == "__main__":
    path = "scenes/weapons/smg.tscn"
    open(path, "w").write(SCENE.format(grip=xf(GRIP), muzzle=xf(MUZZLE),
                                       socket=grip_socket("GripSocketRight", GRIP_HOLD_POINT, GRIP_RAKE, GRIP_RADIUS)))
    print("wrote", path)
    # Fast, light shots: 10 per second, small kick.
    res("data/weapons/smg.tres", {
        "display_name": '"SMG"', "weight_t": 1.5, "hp": 250.0, "kind": 0, "slot": 0,
        "fire_rate": 10.0, "damage": 35.0, "projectile_speed": 380.0, "spread_deg": 1.2,
        "recoil_up_deg": 0.6, "recoil_side_deg": 0.5, "model_kick_back": 0.25, "model_kick_up_deg": 2.0,
        "shake_trauma": 0.02, "shake_kick": 0.03, "magazine": 45, "reload_time": 2.5,
        "rest_transform": gun_on_forearm_rest(GRIP, OUT_DEG), "aim_anchor": v3(gun_aim_anchor(GRIP, OUT_DEG)),
        "right_pole_rest": v3((0.4, -1.0, 0.5)), "right_pole_aim": v3((0.4, -1.0, 0.5))},
        "res://scenes/weapons/smg.tscn")
