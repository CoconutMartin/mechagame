"""Writes a player mech scene: the shared skeleton (frame) and logic nodes plus a model's meshes.

A model module calls write_scene() with a build(m) function. build() adds meshes to the
skeleton nodes with m.part() and m.node(). Run from the project root, for example:
    python3 tools/mech_gen/warden.py

Part scenes (Phase 2): set m.current_part = "<id>" in build() and the next meshes go to that part
scene instead of the mech scene. A part scene has one child group per socket (frame node name,
for example Torso or KneeL). MechAssembler moves the group children onto the frame at run time.
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
 ("animation/dodge_slide_pose","dodgeslide"),("animation/pauldron_follow","pauldron"),
 ("camera/free_aim","freeaim"),("mech/mech_assembler","assembler"),("weapons/weapon_controller","weaponctl"),
 ("combat/mech_health","health"),("combat/part_breaker","breaker")]


# Frame nodes that part groups attach to, with their paths in the mech scene.
SOCKETS = {"Torso": TO, "Lower": L}
for _s in ("L", "R"):
    SOCKETS[f"Shoulder{_s}"] = f"{TO}/Shoulder{_s}"
    SOCKETS[f"Elbow{_s}"] = f"{TO}/Shoulder{_s}/Elbow{_s}"
    SOCKETS[f"Hip{_s}"] = f"{L}/Hip{_s}"
    SOCKETS[f"Knee{_s}"] = f"{L}/Hip{_s}/Knee{_s}"


def socket_path(parent):
    """Mech scene parent path to a part scene path (socket group name plus the rest)."""
    best = None
    for name, path in SOCKETS.items():
        if parent == path or parent.startswith(path + "/"):
            if best is None or len(path) > len(SOCKETS[best]):
                best = name
    assert best is not None, f"no socket for {parent}"
    return best + parent[len(SOCKETS[best]):]


class PartScene:
    """Nodes of one part scene (its own meshes and node list)."""
    def __init__(self):
        self.b = Builder()
        self.nodes = []
        self.groups = []


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
        self.current_part = None  # Part id: the next nodes go to that part scene.
        self.parts = {}           # Part id -> PartScene.

    def _target(self, parent):
        """(builder, node list, parent path) for a new node: the mech scene or the current part."""
        if self.current_part is None:
            return self.b, self.nodes, parent
        part = self.parts.setdefault(self.current_part, PartScene())
        path = socket_path(parent)
        group = path.split("/")[0]
        if group not in part.groups:
            part.groups.append(group)
            part.nodes.append(f'[node name="{group}" type="Node3D" parent="."]\n')
        return part.b, part.nodes, path

    @staticmethod
    def _with_groups(text, groups):
        if not groups:
            return text
        g = ", ".join(f'"{x}"' for x in groups)
        head, rest = text.split("]\n", 1)
        return f"{head} groups=[{g}]]\n{rest}"

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
        self.node(name, parent, pos=pos, rot=rot, groups=["brake_flame" if brake else "booster_flame"])
        b, nodes, path = self._target(parent)
        outer = b.mesh("cyl", radius, 0.04, length)
        core = b.mesh("cyl", radius * 0.55, 0.02, length * 0.6)
        for part, mid, mat, y in (("Outer", outer, "flame", -length / 2), ("Core", core, "flame_core", -length * 0.3)):
            nodes.append(f'[node name="{part}" type="MeshInstance3D" parent="{path}/{name}"]\ntransform = {xf((0, y, 0))}\ncast_shadow = 0\nmesh = SubResource("{mid}")\nsurface_material_override/0 = ExtResource("{mat}")\n')
        if self.current_part is not None:
            return  # Part flames are found by group at run time.
        if brake:
            self.brake_flames.append(f"{parent}/{name}")
        else:
            self.flames.append(name)

    def node(self, name, parent, typ="Node3D", pos=(0, 0, 0), rot=(0, 0, 0), groups=None, extra="", transform=None):
        """transform: a Transform3D text that replaces pos and rot (no torso scaling)."""
        _, pos = self._scaled(parent, None, (), pos)
        _, nodes, path = self._target(parent)
        text = f'[node name="{name}" type="{typ}" parent="{path}"]\ntransform = {transform or xf(pos, rot)}\n{extra}'
        nodes.append(self._with_groups(text, groups))

    def part(self, name, parent, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0), groups=None):
        params, pos = self._scaled(parent, kind, params, pos)
        b, nodes, path = self._target(parent)
        b.nodes = []
        b.part(name, path, mat, kind, params, pos, rot)
        nodes.extend(self._with_groups(t, groups) for t in b.nodes)

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
                rest_xf=None, one_hand=None, muzzle_flash=False, torso_scale=1.0, parts=None, loadout=None):
    """rest_xf: weapon rest transform text in torso space (default: two-hand low ready).
    one_hand: dict for a one-hand weapon with a shield on the left arm. Keys (mech space):
    rest / raised (left hand markers), pole_rest / pole_raised (left elbow), right_pole_rest /
    right_pole_aim (right elbow), aim_anchor (stock place for hip fire), shield_area (m², sets the
    top speed with the shield up), shield_scale. The model makes the nodes Shield and ShieldMountRest
    (children of ElbowL) and ShieldCover (child of the torso).
    RMB fires from the hip with no zoom. LMB lifts the shield (ShieldPose).
    torso_scale: size of the upper body (torso, head, arms). Weapon and shield keep their size.
    parts: {part id: (scene path, root name)} for the part scenes build() makes. loadout: res:// path
    of the Loadout that MechAssembler uses. With parts, the mech scene holds only the frame."""
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
    if not parts:
        # Phase 3: with part scenes, WeaponController adds the weapons from the loadout instead.
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
    if parts:
        # The feet come from the leg part: SkidDust finds them by the "foot" group.
        feet = [line for line in logic.split("\n") if line.startswith("feet = [")]
        assert len(feet) == 1
        logic = logic.replace(feet[0] + "\n", "")
        logic = logic.replace('[node name="SkidDust" type="Node" parent="Animation" node_paths=PackedStringArray("mech", "feet")]',
                              '[node name="SkidDust" type="Node" parent="Animation" node_paths=PackedStringArray("mech")]')
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
    # With part scenes, BrakeThrusters and BoosterFlames find their flames by group at run time.
    if m.brake_flames or parts:
        bf = ", ".join(f'NodePath("../../{f}")' for f in m.brake_flames)
        extra.append(f'''[node name="BrakeThrusters" type="Node" parent="Animation" node_paths=PackedStringArray("mech"{', "flames"' if bf else ''})]
script = ExtResource("brakes")
mech = NodePath("../..")
''' + (f"flames = [{bf}]\n" if bf else ""))
    if m.flames or parts:
        logic = logic.replace('[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("kneel"',
                              '[node name="FreeAim" type="Node" parent="CameraRig" node_paths=PackedStringArray("boosters", "kneel"')
        logic = logic.replace('script = ExtResource("freeaim")\n', 'script = ExtResource("freeaim")\nboosters = NodePath("../../Animation/BoosterFlames")\n')
        fl = ", ".join(f'NodePath("../../{TO}/{f}")' for f in m.flames)
        wired = f'flames = [{fl}]\nlight = NodePath("../../{TO}/BoosterLight")\n' if fl else ""
        extra.append(f'''[node name="BoosterFlames" type="Node" parent="Animation" node_paths=PackedStringArray("mech", "dodge"{', "flames", "light"' if fl else ''})]
script = ExtResource("flames")
mech = NodePath("../..")
dodge = NodePath("../../MechDodge")
''' + wired)
    o = ['[gd_scene format=3]\n']
    for p, i in SCRIPTS:
        o.append(f'[ext_resource type="Script" path="res://scripts/{p}.gd" id="{i}"]')
    o.append(f'[ext_resource type="PackedScene" path="{rifle_scene}" id="rifle"]')
    o.append('[ext_resource type="PackedScene" path="res://scenes/weapons/bullet.tscn" id="bullet"]')
    if loadout:
        o.append(f'[ext_resource type="Resource" path="{loadout}" id="loadout"]')
        # MechAssembler goes first (after the collision), so the parts exist before the other nodes start.
        m.nodes.insert(1, '''[node name="MechAssembler" type="Node" parent="." node_paths=PackedStringArray("mech", "frame", "weapon_controller")]
script = ExtResource("assembler")
loadout = ExtResource("loadout")
mech = NodePath("..")
frame = NodePath("../Visual")
weapon_controller = NodePath("../WeaponController")
''')
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
    text = "\n".join(o)
    if parts:
        text = _weapons_by_controller(text, one_hand)
    open(out_path, "w").write(text)
    for part_id, (path, root) in (parts or {}).items():
        write_part_scene(path, root, m.parts[part_id], materials)
        print("wrote", path)
    print("wrote", out_path)


def write_part_scene(path, root, part, materials):
    """One part model: child groups named after sockets, meshes under them."""
    o = ['[gd_scene format=3]\n']
    for mid, mat in materials.items():
        o.append(f'[ext_resource type="Material" path="{mat}" id="{mid}"]')
    o.append('')
    o.append(part.b.sub_text())
    o.append(f'[node name="{root}" type="Node3D"]\n')
    o += part.nodes
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(o))


def _strip(text, node, props):
    """Removes properties (and their node_paths entries) from one node block."""
    start = text.index(f'[node name="{node}"')
    end = text.find("\n[node ", start + 1)
    end = len(text) if end < 0 else end
    block = text[start:end]
    for prop in props:
        lines = [l for l in block.split("\n") if not l.startswith(prop + " = ")]
        block = "\n".join(lines).replace(f'"{prop}", ', "").replace(f', "{prop}"', "")
    return text[:start] + block + text[end:]


def _drop_node(text, node):
    start = text.index(f'[node name="{node}"')
    end = text.find("\n[node ", start + 1)
    return text[:start] + (text[end + 1:] if end >= 0 else "")


def _weapons_by_controller(text, one_hand):
    """Phase 3: the weapon nodes come from the loadout, so WeaponController wires them at start."""
    text = _strip(text, "WeaponPose", ["weapon", "rest_pose"])
    text = _strip(text, "ArmIKRight", ["target"])
    text = _strip(text, "WeaponRecoil", ["weapon_fire"])
    text = _drop_node(text, "WeaponFire")
    if one_hand:
        text = _strip(text, "ShieldMount", ["shield_node", "rest_mount", "cover"])
    text += f'''
[node name="WeaponController" type="Node" parent="." node_paths=PackedStringArray("mech", "input", "mech_aim", "weapon_pose", "weapon_recoil", "arm_ik_left", "arm_ik_right", "camera_ads", "torso_pose", "camera_shake", "mech_shield", "shield_pose", "shield_mount", "torso", "left_hand")]
script = ExtResource("weaponctl")
mech = NodePath("..")
input = NodePath("../MechInput")
mech_aim = NodePath("../MechAim")
weapon_pose = NodePath("../Animation/WeaponPose")
weapon_recoil = NodePath("../Animation/WeaponRecoil")
arm_ik_left = NodePath("../Animation/ArmIKLeft")
arm_ik_right = NodePath("../Animation/ArmIKRight")
camera_ads = NodePath("../CameraRig/CameraAds")
torso_pose = NodePath("../Animation/TorsoPose")
camera_shake = NodePath("../CameraRig/Pitch/SpringArm/Camera")
mech_shield = NodePath("../MechShield")
shield_pose = NodePath("../Animation/ShieldPose")
shield_mount = NodePath("../Animation/ShieldMount")
torso = NodePath("../{TO}")
left_hand = NodePath("../{TO}/LeftHand")

[node name="MechHealth" type="Node" parent="." node_paths=PackedStringArray("mech", "assembler", "weapons")]
script = ExtResource("health")
mech = NodePath("..")
assembler = NodePath("../MechAssembler")
weapons = NodePath("../WeaponController")

[node name="PartBreaker" type="Node" parent="." node_paths=PackedStringArray("mech", "health", "assembler", "weapons", "mech_aim", "jump_charge", "camera_shake", "frame")]
script = ExtResource("breaker")
mech = NodePath("..")
health = NodePath("../MechHealth")
assembler = NodePath("../MechAssembler")
weapons = NodePath("../WeaponController")
mech_aim = NodePath("../MechAim")
jump_charge = NodePath("../MechJumpCharge")
camera_shake = NodePath("../CameraRig/Pitch/SpringArm/Camera")
frame = NodePath("../Visual")
'''
    return text
