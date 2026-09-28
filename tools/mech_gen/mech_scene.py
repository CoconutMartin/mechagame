"""Writes a player mech scene: the shared skeleton and logic nodes plus a model's meshes.

A model module calls write_scene() with a build(m) function. build() adds meshes to the
skeleton nodes with m.part() and m.node(). Run from the project root, for example:
    python3 tools/mech_gen/warden.py
"""
import os, sys
from shapes import Builder, xf, xf_aim, xf_rows, apply_rows

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
 ("camera/camera_shake","shake"),("animation/skirt_follow","skirt"),("weapons/weapon_fire","fire"),
 ("weapons/weapon_recoil","recoil"),("effects/booster_flames","flames"),("animation/shield_pose","shieldpose"),
 ("mech/mech_shield","shield"),("effects/brake_thrusters","brakes"),("animation/shield_mount","shieldmount"),
 ("animation/dodge_slide_pose","dodgeslide"),
 ("camera/free_aim","freeaim")]


def TT(x, y, z):
    """Mech space (feet at 0) to torso space."""
    return (x, y - WAIST, z)


class Model:
    def __init__(self):
        self.b = Builder()
        self.nodes = []
        self.skirts = []
        self.foot = "Foot"   # Mesh name prefix used by SkidDust (FootL, FootR).
        self.flames = []     # Booster flame node names on the torso.
        self.brake_flames = []  # Brake thruster flame paths (relative to the mech root).
        self.torso_scale = 1.0  # Set by write_scene. Scales build() parts on the torso and arms.

    def _scaled(self, parent, kind, params, pos):
        k = self.torso_scale
        if k == 1.0 or not parent.startswith(TO) or "/Shield" in parent:
            return params, pos
        n = {"box": 3, "cyl": 3, "prism": 3, "sphere": 1}[kind] if kind else 0
        params = tuple(v * k for v in params[:n]) + tuple(params[n:])
        return params, tuple(v * k for v in pos)

    def flame(self, name, pos, rot=(0, 0, 0), length=3.0, radius=0.45, parent=TO, brake=False):
        """Flame node. Points down its -Y axis. Uses materials "flame" and "flame_core".
        Booster flames (default) sit on the torso. brake=True: a brake thruster flame (BrakeThrusters)."""
        self.node(name, parent, pos=pos, rot=rot)
        outer = self.b.mesh("cyl", radius, 0.04, length)
        core = self.b.mesh("cyl", radius * 0.55, 0.02, length * 0.6)
        for part, mid, mat, y in (("Outer", outer, "flame", -length / 2), ("Core", core, "flame_core", -length * 0.3)):
            self.nodes.append(f'[node name="{part}" type="MeshInstance3D" parent="{parent}/{name}"]\ntransform = {xf((0, y, 0))}\ncast_shadow = 0\nmesh = SubResource("{mid}")\nsurface_material_override/0 = ExtResource("{mat}")\n')
        if brake:
            self.brake_flames.append(f"{parent}/{name}")
        else:
            self.flames.append(name)

    def node(self, name, parent, typ="Node3D", pos=(0, 0, 0), rot=(0, 0, 0)):
        _, pos = self._scaled(parent, None, (), pos)
        self.nodes.append(f'[node name="{name}" type="{typ}" parent="{parent}"]\ntransform = {xf(pos, rot)}\n')

    def part(self, name, parent, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0)):
        params, pos = self._scaled(parent, kind, params, pos)
        self.b.nodes = []
        self.b.part(name, parent, mat, kind, params, pos, rot)
        self.nodes.extend(self.b.nodes)

    def skirt(self, name, pivot, hips, placement):
        """placement 0 = front plate, 1 = rear plate."""
        self.skirts.append((name, pivot, hips, placement))


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


def write_scene(out_path, rifle_scene, materials, build, shoulder_x=2.9, shoulder_y=8.3, hip_x=1.3, thigh=2.6,
                rest_xf=None, one_hand=None, muzzle_flash=False, torso_scale=1.0):
    """rest_xf: weapon rest transform text in torso space (default: two-hand low ready).
    one_hand: dict for a one-hand weapon with a shield on the left arm. Keys (mech space):
    rest / raised (left hand markers), pole_rest / pole_raised (left elbow), right_pole_rest /
    right_pole_aim (right elbow), aim_anchor (stock place for hip fire), shield_area (m², sets the
    top speed with the shield up), shield_scale. The model makes the nodes Shield and ShieldMountRest
    (children of ElbowL) and ShieldCover (child of the torso).
    torso_scale: size of the upper body (torso, head, arms). Weapon and shield keep their size. RMB fires from the hip
    with no zoom. LMB lifts the shield (ShieldPose)."""
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
    k = torso_scale
    for s, sign in (("L", -1), ("R", 1)):
        m.node(f"Shoulder{s}", TO, pos=tuple(v * k for v in TT(sign * shoulder_x, shoulder_y, 0)))
        m.node(f"Elbow{s}", f"{TO}/Shoulder{s}", pos=(0, -UPPER_ARM * k, 0))
        m.node(f"Hip{s}", L, pos=(sign * hip_x, 0, 0))
        m.node(f"Knee{s}", f"{L}/Hip{s}", pos=(0, -thigh, 0))
    rest = rest_xf or xf(TT(*RIFLE_POS), RIFLE_ROT)
    m.nodes.append(f'[node name="Rifle" parent="{TO}" instance=ExtResource("rifle")]\ntransform = {rest}\n')
    m.nodes.append(f'[node name="RiflePoseRest" type="Marker3D" parent="{TO}"]\ntransform = {rest}\n')
    if one_hand:
        m.node("LeftHand", TO, "Marker3D", TT(*torso_point(one_hand["rest"], k)))
        m.node("LeftHandRest", TO, "Marker3D", TT(*torso_point(one_hand["rest"], k)))
        m.node("LeftHandRaised", TO, "Marker3D", TT(*torso_point(one_hand["raised"], k)))
    m.node("AimAnchor", TO, "Marker3D", TT(*torso_point(one_hand["aim_anchor"] if one_hand else AIM_ANCHOR, k)))
    m.torso_scale = k
    build(m)

    here = os.path.dirname(os.path.abspath(__file__))
    logic = open(os.path.join(here, "logic_nodes.tscn.txt")).read()
    logic = logic.replace("KneeL/FootL", f"KneeL/{m.foot}L").replace("KneeR/FootR", f"KneeR/{m.foot}R")
    logic = logic.replace('arm_ik_left = NodePath("../ArmIKLeft")\narm_ik_right = NodePath("../ArmIKRight")',
                          'arm_ik_left = NodePath("../ArmIKLeft")\narm_ik_right = NodePath("../ArmIKRight")\nrecoil = NodePath("../WeaponRecoil")')
    logic = logic.replace('"arm_ik_left", "arm_ik_right")]', '"arm_ik_left", "arm_ik_right", "recoil")]')
    logic = logic.replace('[node name="MechAim" type="Node" parent="." node_paths=PackedStringArray("mech", "camera", "aim_origin", "body_visual")]\nscript = ExtResource("aim")\n',
                          '[node name="MechAim" type="Node" parent="." node_paths=PackedStringArray("mech", "camera", "aim_origin", "body_visual", "camera_rig")]\nscript = ExtResource("aim")\ncamera_rig = NodePath("../CameraRig")\n')
    logic = logic.replace("upper_length = 2.7\nlower_length = 3.0", f"upper_length = {round(2.7 * k, 4)}\nlower_length = {round(3.0 * k, 4)}")
    extra = []
    if one_hand:
        m.nodes[0] = m.nodes[0].replace('"kneel", "dodge")]', '"kneel", "dodge", "shield")]').replace(
            'dodge = NodePath("MechDodge")\n', 'dodge = NodePath("MechDodge")\nshield = NodePath("MechShield")\n', 1)
        v = lambda t: f"Vector3({t[0]}, {t[1]}, {t[2]})"
        for line in ('left_grip_target = NodePath("../../Visual/Roll/Upper/Torso/Rifle/GripLeft")\n',
                     'left_grip_rest = NodePath("../../Visual/Roll/Upper/Torso/Rifle/GripLeftRest")\n',
                     'left_grip_aim = NodePath("../../Visual/Roll/Upper/Torso/Rifle/GripLeftAim")\n'):
            assert line in logic
            logic = logic.replace(line, "")
        logic = logic.replace('"input", "left_grip_target", "left_grip_rest", "left_grip_aim", ', '"input", ')
        logic = logic.replace('Torso/Rifle/GripLeft")', 'Torso/LeftHand")')
        logic = logic.replace('arm_ik_right = NodePath("../ArmIKRight")\n',
                              f'arm_ik_right = NodePath("../ArmIKRight")\nright_pole_rest = {v(one_hand["right_pole_rest"])}\nright_pole_aim = {v(one_hand["right_pole_aim"])}\n')
        logic = logic.replace('script = ExtResource("ads")\n', 'script = ExtResource("ads")\nenabled = false\n')
        logic = logic.replace('script = ExtResource("torsopose")\n', 'script = ExtResource("torsopose")\naim_twist_deg = 0.0\naim_tilt_deg = 0.0\n')
        logic = logic.replace('[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("kneel")]\nscript = ExtResource("freeaim")\n',
                              '[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("kneel", "shield")]\nscript = ExtResource("freeaim")\nshield = NodePath("../../MechShield")\n')
        extra.append(f'''[node name="MechShield" type="Node" parent="." node_paths=PackedStringArray("input")]
script = ExtResource("shield")
input = NodePath("../MechInput")
area_m2 = {round(one_hand["shield_area"], 3)}
''')
        extra.append(f'''[node name="ShieldPose" type="Node" parent="Animation" node_paths=PackedStringArray("shield", "arm_ik", "hand_target", "rest", "raised")]
script = ExtResource("shieldpose")
shield = NodePath("../../MechShield")
arm_ik = NodePath("../ArmIKLeft")
hand_target = NodePath("../../{TO}/LeftHand")
rest = NodePath("../../{TO}/LeftHandRest")
raised = NodePath("../../{TO}/LeftHandRaised")
pole_rest = {v(one_hand["pole_rest"])}
pole_raised = {v(one_hand["pole_raised"])}
''')
        extra.append(f'''[node name="ShieldMount" type="Node" parent="Animation" node_paths=PackedStringArray("shield", "shield_node", "rest_mount", "cover")]
script = ExtResource("shieldmount")
shield = NodePath("../../MechShield")
shield_node = NodePath("../../{TO}/ShoulderL/ElbowL/Shield")
rest_mount = NodePath("../../{TO}/ShoulderL/ElbowL/ShieldMountRest")
cover = NodePath("../../{TO}/ShieldCover")
shield_scale = {one_hand["shield_scale"]}
''')
    flash = '"muzzle_flash", ' if muzzle_flash else ""
    extra.append(f'''[node name="WeaponFire" type="Node" parent="Animation" node_paths=PackedStringArray("input", "weapon_pose", "mech_aim", "muzzle", {flash}"camera_shake", "shooter")]
script = ExtResource("fire")
input = NodePath("../../MechInput")
weapon_pose = NodePath("../WeaponPose")
mech_aim = NodePath("../../MechAim")
muzzle = NodePath("../../{TO}/Rifle/Muzzle")
bullet_scene = ExtResource("bullet")
''' + (f'muzzle_flash = NodePath("../../{TO}/Rifle/Muzzle/MuzzleFlash")\n' if muzzle_flash else "") + '''camera_shake = NodePath("../../CameraRig/Pitch/SpringArm/Camera")
shooter = NodePath("../..")
''')
    extra.append('''[node name="WeaponRecoil" type="Node" parent="Animation" node_paths=PackedStringArray("weapon_fire")]
script = ExtResource("recoil")
weapon_fire = NodePath("../WeaponFire")
''')
    if m.brake_flames:
        bf = ", ".join(f'NodePath("../../{f}")' for f in m.brake_flames)
        extra.append(f'''[node name="BrakeThrusters" type="Node" parent="Animation" node_paths=PackedStringArray("mech", "flames")]
script = ExtResource("brakes")
mech = NodePath("../..")
flames = [{bf}]
''')
    if m.flames:
        logic = logic.replace('[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("kneel"',
                              '[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("boosters", "kneel"')
        logic = logic.replace('script = ExtResource("freeaim")\n', 'script = ExtResource("freeaim")\nboosters = NodePath("../../Animation/BoosterFlames")\n')
        fl = ", ".join(f'NodePath("../../{TO}/{f}")' for f in m.flames)
        extra.append(f'''[node name="BoosterFlames" type="Node" parent="Animation" node_paths=PackedStringArray("mech", "dodge", "flames", "light")]
script = ExtResource("flames")
mech = NodePath("../..")
dodge = NodePath("../../MechDodge")
flames = [{fl}]
light = NodePath("../../{TO}/BoosterLight")
''')
    o = ['[gd_scene format=3]\n']
    for p, i in SCRIPTS:
        o.append(f'[ext_resource type="Script" path="res://scripts/{p}.gd" id="{i}"]')
    o.append(f'[ext_resource type="PackedScene" path="{rifle_scene}" id="rifle"]')
    o.append('[ext_resource type="PackedScene" path="res://scenes/weapons/bullet.tscn" id="bullet"]')
    for mid, path in materials.items():
        o.append(f'[ext_resource type="Material" path="{path}" id="{mid}"]')
    o.append('')
    o.append('[sub_resource type="CapsuleShape3D" id="body_shape"]\nradius = 2.6\nheight = 10.0\n')
    o.append('[sub_resource type="SphereShape3D" id="arm_shape"]\nradius = 0.6\n')
    o.append(m.b.sub_text())
    o += m.nodes
    o.append(logic)
    o += extra
    for name, pivot, hips, placement in m.skirts:
        hp = ", ".join(f'NodePath("../../{L}/{h}")' for h in hips)
        o.append(f'[node name="{name}" type="Node" parent="Animation" node_paths=PackedStringArray("skirt", "hips")]\nscript = ExtResource("skirt")\nskirt = NodePath("../../{L}/{pivot}")\nhips = [{hp}]\nplacement = {placement}\n')
    open(out_path, "w").write("\n".join(o))
    print("wrote", out_path)
