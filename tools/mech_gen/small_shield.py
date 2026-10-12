"""Small Shield (user request 2026-10-12, the small shield of the user's arm drawing): the shield scene
and its data file. Run from the project root:
    python3 tools/mech_gen/small_shield.py
The model comes from tools/blender/small_shield_build.py (models/small_shield/small_shield.glb).
Socket groups like the Hex Shield (scenes/weapons/warden_shield.tscn): ElbowL (the shield on the outer
side of the left forearm, long side along it) and Torso (ShieldCover, kept for ShieldMount; the shield
does not move there on Sanggigilid). The arm: elbow 45 deg (arm_poses.py), all the time.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arm_poses
from weapons import res, v3

LENGTH, WIDTH = 3.4, 2.2
## Shield center in the left elbow joint space: out to the side (-X), along the forearm (-Y), from the
## elbow; the basis puts the long side along the forearm and the front face outward.
MOUNT = "Transform3D(0, 0, 1, 0, -1, 0, 1, 0, 0, -0.85, -1.0, 0)"

SCENE = f'''[gd_scene format=3]

[ext_resource type="PackedScene" path="res://models/small_shield/small_shield.glb" id="model"]

[node name="SmallShield" type="Node3D"]

[node name="ElbowL" type="Node3D" parent="."]

[node name="ShieldMountRest" type="Marker3D" parent="ElbowL"]
transform = {MOUNT}

[node name="Shield" type="Node3D" parent="ElbowL"]
transform = {MOUNT}

[node name="Model" parent="ElbowL/Shield" instance=ExtResource("model")]

[node name="Torso" type="Node3D" parent="."]

[node name="ShieldCover" type="Marker3D" parent="Torso"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.17, 1.53, -2.0)
'''

if __name__ == "__main__":
    path = "scenes/weapons/small_shield.tscn"
    open(path, "w").write(SCENE)
    print("wrote", path)
    res("data/weapons/small_shield.tres", {
        "display_name": '"Small Shield"', "weight_t": 1.5, "hp": 700.0, "kind": 4,
        "shield_area_m2": round(LENGTH * WIDTH, 3), "shield_scale": 1.0,
        "shield_hand": v3(arm_poses.hand(arm_poses.ELBOW_L, arm_poses.NEUTRAL_DEG, side=-1.0))},
        "res://scenes/weapons/small_shield.tscn")
