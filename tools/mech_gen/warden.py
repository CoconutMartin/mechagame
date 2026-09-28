"""Warden: heavy armored mech from reference image 9 (Phase 1 revision 42).
Weathered grey plates, head built into the center torso with a red eye, hex shield on the left
forearm, claw feet, two backpack thrusters with flames.
Revision 43: missile rack removed, shield 20% larger, rifle held in the right hand only
(one-hand high ready, like reference image 10).
Revision 44: blade antenna removed, legs 20% thicker, RMB hip fire (no zoom), LMB lifts the shield.
Mech faces -Z. Right is +X. Heights are in mech space (feet at 0)."""
import math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mech_scene import write_scene, one_hand_rest, TT, TO, L

MATS = {m: f"res://materials/warden/{m}.tres" for m in
        ["armor", "armor_dark", "frame", "joint", "mark", "emblem", "eye"]}
MATS["flame"] = "res://materials/effects/booster_flame.tres"
MATS["flame_core"] = "res://materials/effects/booster_core.tres"
SHIELD_SCALE = 1.2
# One-hand high ready: grip in the right hand in front of the right shoulder, muzzle up.
RIFLE_REST = one_hand_rest(hand=(2.7, 7.3, -2.15), muzzle_dir=(0.12, 1.0, -0.12), up_hint=(0.25, 0.0, 1.0))
ONE_HAND = {
    "rest": (-3.3, 3.8, -0.8),         # Left hand hangs at the side, shield on the outside.
    "raised": (-1.9, 8.6, -2.7),       # LMB: forearm up in front of the left chest, shield faces forward.
    "pole_rest": (-1.0, -0.2, 0.3),
    "pole_raised": (-0.3, -1.0, -0.1),
    "right_pole_rest": (0.25, -1.0, -0.2),  # Elbow down under the hand, like the photo.
    "right_pole_aim": (0.4, -1.0, 0.5),     # Hip fire: elbow down and back.
    "aim_anchor": (2.8, 6.5, -1.0),         # Hip fire: stock at the right hip.
}
LEG_THICKNESS = 1.2  # Leg width and depth multiplier (revision 44: 20% thicker).
HIP_X = 1.5
SIDES = (("L", -1), ("R", 1))


def X(axis_rot=(0, 0, 90)):
    """Rotation that lays a cylinder along the X axis."""
    return axis_rot


def build(m):
    # ---- Center torso: body core, cockpit head and sensor ports ----
    m.part("Waist", TO, "frame", "box", (2.0, 1.1, 1.8), TT(0, 5.9, 0))
    m.part("WaistRing", TO, "joint", "cyl", (1.05, 1.05, 0.35), TT(0, 6.3, 0))
    m.part("Core", TO, "armor_dark", "box", (3.0, 2.6, 2.3), TT(0, 7.9, 0.1))
    m.part("CenterColumn", TO, "armor", "box", (1.5, 2.5, 0.6), TT(0, 7.6, -1.2))
    m.part("PortPlate", TO, "armor_dark", "box", (1.0, 1.4, 0.2), TT(0, 7.3, -1.55))
    for i, y in enumerate((7.65, 6.95)):
        m.part(f"PortRing{i}", TO, "joint", "cyl", (0.32, 0.32, 0.14), TT(0, y, -1.65), (90, 0, 0))
        m.part(f"PortLens{i}", TO, "frame", "cyl", (0.2, 0.2, 0.16), TT(0, y, -1.68), (90, 0, 0))
    m.part("ChinGuard", TO, "armor", "box", (1.4, 0.5, 0.8), TT(0, 6.5, -1.05), (-15, 0, 0))
    # Head: armored cowl in the upper center torso.
    m.part("Head", TO, "armor", "box", (1.5, 1.3, 1.9), TT(0, 9.1, -0.55))
    m.part("HeadBrow", TO, "armor", "box", (1.6, 0.35, 0.7), TT(0, 9.55, -1.35), (12, 0, 0))
    m.part("HeadCheekL", TO, "armor_dark", "box", (0.35, 0.9, 0.9), TT(-0.65, 8.75, -1.3))
    m.part("HeadCheekR", TO, "armor_dark", "box", (0.35, 0.9, 0.9), TT(0.65, 8.75, -1.3))
    m.part("EyeHousing", TO, "frame", "box", (0.9, 0.7, 0.2), TT(0, 8.85, -1.6))
    m.part("Eye", TO, "eye", "prism", (0.75, 0.55, 0.12, 0.5), TT(0, 8.85, -1.68), (0, 0, 180))
    m.part("Fin", TO, "armor", "prism", (1.6, 1.5, 0.22, 0.25), TT(0, 10.4, -0.3), (0, 90, 0))
    m.part("FinBase", TO, "armor_dark", "box", (0.5, 0.4, 1.4), TT(0, 9.85, -0.4))
    # Right torso: armor block with an emblem.
    m.part("TorsoR", TO, "armor", "box", (1.4, 2.4, 2.3), TT(1.45, 8.1, -0.05))
    m.part("TorsoRFront", TO, "armor", "box", (1.2, 1.4, 0.25), TT(1.45, 8.4, -1.25))
    m.part("Emblem", TO, "emblem", "box", (0.6, 0.6, 0.05), TT(1.45, 8.45, -1.39), (0, 0, 45))
    m.part("TorsoRLower", TO, "armor_dark", "box", (1.2, 0.8, 0.3), TT(1.45, 7.2, -1.2))
    # Left torso: plain armor block.
    m.part("TorsoL", TO, "armor", "box", (1.4, 2.4, 2.3), TT(-1.45, 8.1, -0.05))
    m.part("TorsoLFront", TO, "armor", "box", (1.2, 1.4, 0.25), TT(-1.45, 8.4, -1.25))
    m.part("TorsoLLower", TO, "armor_dark", "box", (1.2, 0.8, 0.3), TT(-1.45, 7.2, -1.2))
    # Shoulder yoke and back.
    m.part("Yoke", TO, "armor", "box", (4.0, 0.7, 2.3), TT(0, 9.45, 0.35))
    m.part("Back", TO, "armor", "box", (3.0, 2.8, 1.3), TT(0, 8.0, 1.8))
    m.part("BackPlate", TO, "armor_dark", "box", (2.4, 2.2, 0.3), TT(0, 7.9, 2.5))
    # Backpack thrusters, tilted back 25 degrees, with flames out of the nozzles.
    for s, sign in SIDES:
        m.part(f"BackThruster{s}", TO, "joint", "cyl", (0.32, 0.48, 0.8), TT(sign * 0.75, 6.35, 2.05), (-25, 0, 0))
        m.part(f"BackThrusterInner{s}", TO, "frame", "cyl", (0.34, 0.34, 0.06), TT(sign * 0.75, 5.99, 2.22), (-25, 0, 0))
        m.flame(f"BoosterFlame{s}", TT(sign * 0.75, 5.98, 2.22), (-25, 0, 0))
    m.nodes.append(f'[node name="BoosterLight" type="OmniLight3D" parent="{TO}"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {5.0 - 5.4}, 3.0)\nvisible = false\nlight_color = Color(1, 0.55, 0.2, 1)\nomni_range = 12.0\n')
    # Shoulders: round joint and a big pauldron on each side.
    for s, sign in SIDES:
        x = sign * 2.9
        m.part(f"ShoulderJoint{s}", TO, "joint", "cyl", (0.75, 0.75, 0.8), TT(sign * 2.35, 8.3, 0), X())
        m.part(f"ShoulderGear{s}", TO, "frame", "cyl", (0.55, 0.55, 0.9), TT(sign * 2.35, 8.3, 0), X())
        m.part(f"Pauldron{s}", TO, "armor", "box", (1.8, 1.4, 2.3), TT(x, 9.0, 0))
        m.part(f"PauldronTop{s}", TO, "armor", "box", (1.4, 0.35, 1.9), TT(x, 9.85, 0))
        m.part(f"PauldronFront{s}", TO, "armor_dark", "box", (1.6, 1.0, 0.3), TT(x, 8.8, -1.2), (10, 0, 0))
        m.part(f"PauldronSide{s}", TO, "armor", "box", (0.3, 1.5, 2.1), TT(sign * 3.85, 8.6, 0), (0, 0, -sign * 8))

    # ---- Arms ----
    for s, sign in SIDES:
        SH = f"{TO}/Shoulder{s}"
        EL = f"{SH}/Elbow{s}"
        m.part(f"UpperArmFrame{s}", SH, "frame", "cyl", (0.45, 0.45, 2.0), (0, -1.1, 0))
        m.part(f"UpperArm{s}", SH, "armor", "box", (1.1, 1.4, 1.2), (0, -1.5, 0))
        m.part(f"ElbowJoint{s}", EL, "joint", "cyl", (0.5, 0.5, 1.0), (0, 0, 0), X())
        m.part(f"Forearm{s}", EL, "armor", "box", (1.2, 2.0, 1.3), (0, -1.25, 0))
        m.part(f"ForearmPlate{s}", EL, "armor_dark", "box", (1.0, 1.4, 0.25), (0, -1.2, 0.72))
        m.part(f"Wrist{s}", EL, "frame", "box", (0.8, 0.4, 0.9), (0, -2.45, 0))
        m.part(f"Hand{s}", EL, "joint", "box", (0.7, 0.7, 0.85), (0, -2.95, 0))
        for i, z in enumerate((-0.28, -0.05, 0.18)):
            m.part(f"Finger{s}{i}", EL, "frame", "box", (0.6, 0.45, 0.18), (0, -3.45, z))
    # Hex shield on the outer side of the left forearm (local -Z).
    SL = f"{TO}/ShoulderL/ElbowL"
    k = SHIELD_SCALE
    m.nodes.append(f'[node name="Shield" type="Node3D" parent="{SL}"]\ntransform = Transform3D({k}, 0, 0, 0, {k}, 0, 0, 0, {k}, 0, -1.5, -1.05)\n')
    SHD = f"{SL}/Shield"
    m.part("ShieldBody", SHD, "armor", "box", (2.1, 3.8, 0.25), (0, 0, 0))
    m.part("ShieldTop", SHD, "armor", "prism", (2.1, 0.7, 0.25, 0.5), (0, 2.25, 0))
    m.part("ShieldBottom", SHD, "armor", "prism", (2.1, 0.7, 0.25, 0.5), (0, -2.25, 0), (0, 0, 180))
    m.part("ShieldFrame", SHD, "frame", "box", (0.7, 2.4, 0.4), (0, 0.2, 0.3))
    for i, sign in enumerate((-1, 1)):
        m.part(f"Chevron{i}", SHD, "mark", "box", (0.16, 0.95, 0.06), (sign * 0.3, -1.25, -0.14), (0, 0, sign * 45))
    for i, (x, y) in enumerate(((-0.75, 1.7), (0.75, 1.7), (-0.75, -1.7), (0.75, -1.7), (0, 2.25))):
        m.part(f"Bolt{i}", SHD, "frame", "cyl", (0.08, 0.08, 0.06), (x, y, -0.14), (90, 0, 0))

    # ---- Lower body ----
    m.part("Pelvis", L, "frame", "box", (2.4, 1.0, 1.8), (0, 0.2, 0))
    m.part("Crotch", L, "armor", "box", (0.9, 1.3, 0.45), (0, -0.2, -0.95))
    m.part("CrotchMarkTop", L, "mark", "box", (0.4, 0.08, 0.05), (0, 0.1, -1.19))
    m.part("CrotchMarkStem", L, "mark", "box", (0.08, 0.4, 0.05), (0, -0.1, -1.19))
    m.part("CrotchTip", L, "armor_dark", "prism", (0.9, 0.35, 0.45, 0.5), (0, -1.03, -0.95), (0, 0, 180))
    m.part("PelvisBack", L, "armor", "box", (1.6, 1.0, 0.4), (0, -0.05, 0.95))
    for s, sign in SIDES:
        m.part(f"HipGear{s}", L, "joint", "cyl", (0.6, 0.6, 0.5), (sign * 0.75, 0, 0), X())
    k = LEG_THICKNESS
    leg = m.part

    def part(name, parent, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0)):
        """Leg part with width and depth times LEG_THICKNESS. Height stays the same."""
        along_x = rot == (0, 0, 90)
        if kind == "box":
            params = (params[0] * k, params[1], params[2] * k)
        elif kind == "cyl":
            params = (params[0] * k, params[1] * k, params[2] * (k if along_x else 1.0))
        elif kind == "sphere":
            params = (params[0] * k,)
        elif kind == "prism":
            params = (params[0] * k, params[1], params[2], params[3])
        leg(name, parent, mat, kind, params, (pos[0] * k, pos[1], pos[2] * k), rot)

    for s, sign in SIDES:
        HP = f"{L}/Hip{s}"
        KN = f"{HP}/Knee{s}"
        # Thigh: big square plate on top, armored thigh below.
        part(f"ThighPlate{s}", HP, "armor", "box", (1.7, 1.7, 1.7), (sign * 0.1, -0.55, 0))
        part(f"ThighPlateFace{s}", HP, "armor_dark", "box", (1.3, 1.3, 0.1), (sign * 0.1, -0.55, -0.88))
        part(f"ThighFrame{s}", HP, "frame", "cyl", (0.5, 0.5, 1.2), (0, -1.6, 0))
        part(f"Thigh{s}", HP, "armor", "box", (1.3, 1.1, 1.4), (0, -1.95, 0))
        # Knee: round joint and a front cap.
        part(f"KneeJoint{s}", KN, "joint", "cyl", (0.6, 0.6, 1.3), (0, 0, 0), X())
        part(f"KneeCap{s}", KN, "armor", "box", (1.1, 1.2, 0.5), (0, -0.2, -0.75), (-10, 0, 0))
        # Shin: thick armor with a front plate and a chamfered back.
        part(f"Shin{s}", KN, "armor", "box", (1.45, 1.8, 1.6), (0, -1.15, 0.05))
        part(f"ShinFront{s}", KN, "armor", "box", (1.15, 1.7, 0.3), (0, -1.1, -0.85), (-6, 0, 0))
        part(f"ShinSide{s}", KN, "armor_dark", "box", (0.2, 1.2, 1.2), (sign * 0.8, -1.2, 0.05))
        part(f"Ankle{s}", KN, "joint", "cyl", (0.4, 0.4, 1.2), (0, -2.05, 0), X())
        # Claw foot: base, three front toes, one heel toe. Bottom at y -2.6 (ground).
        part(f"Foot{s}", KN, "armor", "box", (1.4, 0.55, 1.5), (0, -2.3, -0.15))
        for i, (x, yaw, length) in enumerate(((-0.5, 18, 1.2), (0, 0, 1.4), (0.5, -18, 1.2))):
            z = -0.9 - length / 2 * 0.9
            part(f"Toe{s}{i}", KN, "armor", "box", (0.42, 0.4, length), (x * 1.2, -2.4, z), (0, yaw, 0))
            reach = length / 2 + 0.15
            tip = (x * 1.2 - math.sin(math.radians(yaw)) * reach, -2.45, z - math.cos(math.radians(yaw)) * reach)
            part(f"ToeTip{s}{i}", KN, "armor_dark", "prism", (0.42, 0.3, 0.4, 0.5), tip, (-90, yaw, 0))
        part(f"Heel{s}", KN, "armor", "box", (0.5, 0.4, 0.9), (0, -2.4, 0.95))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "scenes/mech/player_mech.tscn"
    write_scene(out, "res://scenes/weapons/heavy_rifle.tscn", MATS, build, hip_x=HIP_X,
                rest_xf=RIFLE_REST, one_hand=ONE_HAND, muzzle_flash=True)
