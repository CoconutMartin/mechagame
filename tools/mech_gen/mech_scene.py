"""Writes a player mech scene: the shared skeleton and logic nodes plus a model's meshes.

A model module calls write_scene() with a build(m) function. build() adds meshes to the
skeleton nodes with m.part() and m.node(). Run from the project root, for example:
    python3 tools/mech_gen/warden.py
"""
import os, sys
from shapes import Builder, xf

WAIST = 5.4            # Torso pivot height.
LOWER_Y = 5.2          # Pelvis height.
UPPER_ARM = 2.7        # Shoulder to elbow (TwoBoneIK upper_length).
RIFLE_POS = (2.3, 7.2, -1.8)
RIFLE_ROT = (-18, 55, 0)   # pitch, yaw, roll in degrees.
AIM_ANCHOR = (2.1, 8.2, -1.1)
U = "Visual/Roll/Upper"
TO = f"{U}/Torso"
L = f"{U}/Lower"
SCRIPTS = [("mech/mech","mech"),("mech/mech_input","input"),("mech/mech_energy","energy"),("mech/mech_footsteps","footsteps"),
 ("animation/mech_leg_swing","legswing"),("animation/mech_leg_twist","legtwist"),("animation/two_bone_ik","ik"),
 ("camera/mech_camera_rig","rig"),("camera/camera_ads","ads"),("mech/mech_landing_recovery","recovery"),("mech/mech_aim","aim"),
 ("mech/mech_jump_charge","jumpcharge"),("mech/mech_air_steer","airsteer"),("mech/mech_kneel","kneel"),
 ("animation/torso_pose","torsopose"),("effects/skid_dust","skiddust"),("animation/skid_body_turn","skidturn"),
 ("animation/inertia_sway","inertia"),("mech/mech_dodge","dodge"),("animation/weapon_pose","weaponpose"),
 ("camera/camera_shake","shake"),("animation/skirt_follow","skirt")]


def TT(x, y, z):
    """Mech space (feet at 0) to torso space."""
    return (x, y - WAIST, z)


class Model:
    def __init__(self):
        self.b = Builder()
        self.nodes = []
        self.skirts = []
        self.foot = "Foot"   # Mesh name prefix used by SkidDust (FootL, FootR).

    def node(self, name, parent, typ="Node3D", pos=(0, 0, 0), rot=(0, 0, 0)):
        self.nodes.append(f'[node name="{name}" type="{typ}" parent="{parent}"]\ntransform = {xf(pos, rot)}\n')

    def part(self, name, parent, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0)):
        self.b.nodes = []
        self.b.part(name, parent, mat, kind, params, pos, rot)
        self.nodes.extend(self.b.nodes)

    def skirt(self, name, pivot, hips, placement):
        """placement 0 = front plate, 1 = rear plate."""
        self.skirts.append((name, pivot, hips, placement))


def write_scene(out_path, rifle_scene, materials, build, shoulder_x=2.9, shoulder_y=8.3, hip_x=1.3, thigh=2.6):
    m = Model()
    m.nodes.append('''[node name="PlayerMech" type="CharacterBody3D" node_paths=PackedStringArray("input", "energy", "footsteps", "landing_recovery", "jump_charge", "air_steer", "kneel", "dodge")]
collision_layer = 2
collision_mask = 1
floor_snap_length = 1.0
script = ExtResource("mech")
input = NodePath("MechInput")
energy = NodePath("MechEnergy")
footsteps = NodePath("MechFootsteps")
landing_recovery = NodePath("MechLandingRecovery")
jump_charge = NodePath("MechJumpCharge")
air_steer = NodePath("MechAirSteer")
kneel = NodePath("MechKneel")
dodge = NodePath("MechDodge")

[node name="Collision" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 0)
shape = SubResource("body_shape")
''')
    m.node("Visual", ".")
    m.node("Roll", "Visual")
    m.node("Upper", "Visual/Roll")
    m.node("Torso", U, pos=(0, WAIST, 0))
    m.node("Lower", U, pos=(0, LOWER_Y, 0))
    for s, sign in (("L", -1), ("R", 1)):
        m.node(f"Shoulder{s}", TO, pos=TT(sign * shoulder_x, shoulder_y, 0))
        m.node(f"Elbow{s}", f"{TO}/Shoulder{s}", pos=(0, -UPPER_ARM, 0))
        m.node(f"Hip{s}", L, pos=(sign * hip_x, 0, 0))
        m.node(f"Knee{s}", f"{L}/Hip{s}", pos=(0, -thigh, 0))
    m.nodes.append(f'[node name="Rifle" parent="{TO}" instance=ExtResource("rifle")]\ntransform = {xf(TT(*RIFLE_POS), RIFLE_ROT)}\n')
    m.node("RiflePoseRest", TO, "Marker3D", TT(*RIFLE_POS), RIFLE_ROT)
    m.node("AimAnchor", TO, "Marker3D", TT(*AIM_ANCHOR))
    build(m)

    here = os.path.dirname(os.path.abspath(__file__))
    logic = open(os.path.join(here, "logic_nodes.tscn.txt")).read()
    logic = logic.replace("KneeL/FootL", f"KneeL/{m.foot}L").replace("KneeR/FootR", f"KneeR/{m.foot}R")
    o = ['[gd_scene format=3]\n']
    for p, i in SCRIPTS:
        o.append(f'[ext_resource type="Script" path="res://scripts/{p}.gd" id="{i}"]')
    o.append(f'[ext_resource type="PackedScene" path="{rifle_scene}" id="rifle"]')
    for mid, path in materials.items():
        o.append(f'[ext_resource type="Material" path="{path}" id="{mid}"]')
    o.append('')
    o.append('[sub_resource type="CapsuleShape3D" id="body_shape"]\nradius = 2.6\nheight = 10.0\n')
    o.append('[sub_resource type="SphereShape3D" id="arm_shape"]\nradius = 0.6\n')
    o.append(m.b.sub_text())
    o += m.nodes
    o.append(logic)
    for name, pivot, hips, placement in m.skirts:
        hp = ", ".join(f'NodePath("../../{L}/{h}")' for h in hips)
        o.append(f'[node name="{name}" type="Node" parent="Animation" node_paths=PackedStringArray("skirt", "hips")]\nscript = ExtResource("skirt")\nskirt = NodePath("../../{L}/{pivot}")\nhips = [{hp}]\nplacement = {placement}\n')
    open(out_path, "w").write("\n".join(o))
    print("wrote", out_path)
