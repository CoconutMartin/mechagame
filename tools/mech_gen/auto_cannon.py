"""Auto Cannon (new mech only): the two weapon scenes and their data files. Run from the project root:
    python3 tools/mech_gen/auto_cannon.py
The models come from tools/blender/auto_cannon_build.py (models/auto_cannon/*.glb).
  auto_cannon:          baton version, right arm. ForearmGunWeapon moves Mount (the model) under the
                        right forearm; the root is the fist target (GripRight).
  auto_cannon_shoulder: shoulder unit (Back L or Back R). It sits on the shoulder armor and turns with it;
                        the root is the bottom of the mount block. Stop to fire (the mech stands still).
Values: slow heavy shots (user choice 2026-10-11).
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import xf

# Godot axes (Blender (x, y, z) is Godot (x, z, -y)): values from auto_cannon_build.py.
PX = 6.0 / (1510 - 823)
# Width and height 50%, length 75% (auto_cannon_build.py SIZE).
MUZZLE = (0.0, 0.0, -4.5)
MOUNT_BOTTOM = (0.0, (254 - 332) * PX * 0.5 - 0.15, -0.94)

FLASH = '''[node name="MuzzleFlash" type="Node3D" parent="{parent}" node_paths=PackedStringArray("light")]
script = ExtResource("flash_script")
light = NodePath("Light")

[node name="Cone" type="MeshInstance3D" parent="{parent}/MuzzleFlash"]
transform = Transform3D(1, 0, 0, 0, 0, 1, 0, -1, 0, 0, 0, -0.5)
cast_shadow = 0
mesh = SubResource("flash_cone")
surface_material_override/0 = ExtResource("flash")

[node name="Core" type="MeshInstance3D" parent="{parent}/MuzzleFlash"]
cast_shadow = 0
mesh = SubResource("flash_core")
surface_material_override/0 = ExtResource("flash")

[node name="Light" type="OmniLight3D" parent="{parent}/MuzzleFlash"]
light_color = Color(1, 0.7, 0.35, 1)
omni_range = 14.0
'''

HEAD = '''[gd_scene format=3]

[ext_resource type="Script" path="res://scripts/weapons/{script}.gd" id="script"]
[ext_resource type="PackedScene" path="res://models/auto_cannon/{model}.glb" id="model"]
[ext_resource type="Material" path="res://materials/effects/muzzle_flash.tres" id="flash"]
[ext_resource type="Script" path="res://scripts/effects/muzzle_flash.gd" id="flash_script"]

[sub_resource type="CylinderMesh" id="flash_cone"]
top_radius = 0.0
bottom_radius = 0.3
height = 1.0
radial_segments = 8
rings = 1

[sub_resource type="SphereMesh" id="flash_core"]
radius = 0.25
height = 0.5
radial_segments = 8
rings = 4
'''


def baton(path):
    o = [HEAD.format(script="forearm_gun_weapon", model="auto_cannon"),
         '[node name="AutoCannon" type="Node3D"]\nscript = ExtResource("script")\n',
         '[node name="GripRight" type="Marker3D" parent="."]\n',
         '[node name="Mount" type="Node3D" parent="."]\n',
         '[node name="Model" parent="Mount" instance=ExtResource("model")]\n',
         f'[node name="Muzzle" type="Marker3D" parent="Mount"]\ntransform = {xf(MUZZLE)}\n',
         FLASH.format(parent="Mount/Muzzle")]
    open(path, "w").write("\n".join(o))
    print("wrote", path)


def shoulder(path):
    offset = tuple(-c for c in MOUNT_BOTTOM)
    muzzle = tuple(a + b for a, b in zip(offset, MUZZLE))
    o = [HEAD.format(script="shoulder_gun_weapon", model="auto_cannon_shoulder"),
         '[node name="AutoCannonShoulder" type="Node3D"]\nscript = ExtResource("script")\n',
         f'[node name="Model" parent="." instance=ExtResource("model")]\ntransform = {xf(offset)}\n',
         f'[node name="Muzzle" type="Marker3D" parent="."]\ntransform = {xf(muzzle)}\n',
         FLASH.format(parent="Muzzle")]
    open(path, "w").write("\n".join(o))
    print("wrote", path)


def res(path, scene, props):
    lines = ['[gd_resource type="Resource" script_class="WeaponData" format=3]\n',
             '[ext_resource type="Script" path="res://scripts/data/weapon_data.gd" id="script"]',
             f'[ext_resource type="PackedScene" path="{scene}" id="scene"]',
             '\n[resource]\nscript = ExtResource("script")']
    lines += [f"{k} = {v}" for k, v in props.items()]
    lines.append('scene = ExtResource("scene")')
    open(path, "w").write("\n".join(lines) + "\n")
    print("wrote", path)


# Slow heavy shots.
FIRING = {"kind": 0, "fire_rate": 1.5, "damage": 220.0, "projectile_speed": 450.0, "spread_deg": 0.3,
          "recoil_up_deg": 4.0, "recoil_side_deg": 1.5, "shake_trauma": 0.12, "shake_kick": 0.18,
          "magazine": 8, "reload_time": 4.5}

if __name__ == "__main__":
    baton("scenes/weapons/auto_cannon.tscn")
    shoulder("scenes/weapons/auto_cannon_shoulder.tscn")
    # Baton: rest = the neutral right arm (user rule 2026-10-11): shoulder block flat, forearm hanging
    # 35 deg forward (fist at (2.45, -1.04, -1.6)), so the cannon points down along it and its muzzle
    # clears the shin. Aim = the heavy rifle's hip fire.
    # ForearmGunWeapon puts the fist where the rifle's grip (RIFLE_GRIP (0, -0.33, -0.99)) would be.
    res("data/weapons/auto_cannon.tres", "res://scenes/weapons/auto_cannon.tscn", {
        "display_name": '"Auto Cannon"', "weight_t": 3.5, "hp": 300.0, **FIRING, "slot": 0,
        "model_kick_back": 0.8, "model_kick_up_deg": 4.0,
        "rest_transform": "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2.45, -0.71, -0.61)",
        "aim_anchor": "Vector3(2.38, 0.935, -0.85)",
        "right_pole_rest": "Vector3(0.4, -1, 0.5)", "right_pole_aim": "Vector3(0.4, -1, 0.5)"})
    res("data/weapons/auto_cannon_shoulder.tres", "res://scenes/weapons/auto_cannon_shoulder.tscn", {
        "display_name": '"Shoulder Cannon"', "weight_t": 3.5, "hp": 300.0, **FIRING, "slot": 1})
