"""Granpa Gundam: RX-78-2 style placeholder model (Phase 1 revision 41)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mech_scene import write_scene, TT, TO, L

MATS = {m: f"res://materials/rx78/{m}.tres" for m in ["white", "blue", "red", "yellow", "frame", "dark", "eye"]}
MATS["flame"] = "res://materials/effects/booster_flame.tres"
MATS["flame_core"] = "res://materials/effects/booster_core.tres"


def build(m):
    # ---- Torso (mech faces -Z, right is +X) ----
    m.part("Abdomen", TO, "red", "box", (2.3, 1.3, 2.0), TT(0, 6.2, -0.05))
    m.part("AbdomenFrame", TO, "frame", "box", (2.0, 0.6, 1.8), TT(0, 5.6, 0))
    m.part("Chest", TO, "blue", "box", (3.9, 2.2, 2.7), TT(0, 7.85, 0))
    m.part("ChestFront", TO, "blue", "box", (3.3, 1.5, 0.4), TT(0, 7.75, -1.4), (8, 0, 0))
    m.part("ChestLower", TO, "blue", "box", (3.0, 0.5, 2.3), TT(0, 6.75, -0.05))
    for s, x in (("L", -0.85), ("R", 0.85)):
        m.part(f"Vent{s}", TO, "yellow", "box", (1.0, 0.8, 0.14), TT(x, 7.65, -1.62), (8, 0, 0))
        for i, dy in enumerate((0.18, -0.02, -0.22)):
            m.part(f"Vent{s}Slat{i}", TO, "dark", "box", (0.85, 0.07, 0.06), TT(x, 7.65 + dy, -1.71), (8, 0, 0))
    m.part("CockpitHatch", TO, "blue", "box", (0.7, 0.9, 0.12), TT(0, 7.55, -1.64), (8, 0, 0))
    m.part("Collar", TO, "yellow", "box", (1.9, 0.45, 0.7), TT(0, 8.95, -0.85), (-15, 0, 0))
    m.part("CollarBack", TO, "blue", "box", (2.6, 0.4, 1.6), TT(0, 9.0, 0.35))
    m.part("Neck", TO, "frame", "cyl", (0.35, 0.4, 0.6), TT(0, 9.2, -0.1))
    # Backpack and beam sabers
    m.part("Backpack", TO, "white", "box", (2.6, 2.3, 1.0), TT(0, 7.9, 1.8))
    m.part("BackpackTop", TO, "white", "box", (2.2, 0.4, 0.8), TT(0, 9.1, 1.7))
    for s, x in (("L", -0.75), ("R", 0.75)):
        m.part(f"Saber{s}", TO, "white", "cyl", (0.17, 0.17, 1.3), TT(x, 9.5, 1.95), (-18, 0, 0))
        m.part(f"SaberCap{s}", TO, "red", "cyl", (0.2, 0.2, 0.15), TT(x, 10.12, 2.15), (-18, 0, 0))
        m.part(f"Thruster{s}", TO, "frame", "cyl", (0.3, 0.45, 0.7), TT(x * 0.9, 6.5, 2.0))
    # Head
    m.part("Helmet", TO, "white", "box", (1.1, 0.9, 1.25), TT(0, 9.75, -0.1))
    m.part("HelmetTop", TO, "white", "box", (0.7, 0.2, 1.0), TT(0, 10.25, -0.05))
    m.part("Face", TO, "white", "box", (0.72, 0.55, 0.2), TT(0, 9.62, -0.78))
    m.part("EyeBand", TO, "dark", "box", (0.66, 0.2, 0.06), TT(0, 9.78, -0.87))
    for s, x in (("L", -0.17), ("R", 0.17)):
        m.part(f"Eye{s}", TO, "eye", "box", (0.22, 0.09, 0.04), TT(x, 9.78, -0.9), (0, 0, 8 if x > 0 else -8))
        m.part(f"Ear{s}", TO, "frame", "cyl", (0.28, 0.28, 0.2), TT(x * 3.6, 9.72, -0.05), (0, 0, 90))
    m.part("MouthVent", TO, "frame", "box", (0.3, 0.2, 0.05), TT(0, 9.5, -0.89))
    m.part("Chin", TO, "red", "box", (0.3, 0.18, 0.24), TT(0, 9.28, -0.78))
    m.part("Crest", TO, "red", "box", (0.28, 0.24, 0.22), TT(0, 10.08, -0.75))
    for s, sign in (("L", -1), ("R", 1)):
        m.part(f"VFin{s}", TO, "yellow", "box", (0.12, 0.95, 0.08), TT(sign * 0.33, 10.33, -0.75), (0, 0, -sign * 55))
        m.part(f"Vulcan{s}", TO, "yellow", "cyl", (0.07, 0.07, 0.25), TT(sign * 0.4, 10.05, -0.62), (90, 0, 0))
    m.part("Camera", TO, "frame", "box", (0.3, 0.2, 0.3), TT(0, 10.2, 0.4))
    # Shoulders (stay on the torso)
    for s, sign in (("L", -1), ("R", 1)):
        x = sign * 2.85
        m.part(f"ShoulderPad{s}", TO, "white", "box", (1.5, 1.4, 1.85), TT(x, 8.5, 0))
        m.part(f"ShoulderTop{s}", TO, "white", "box", (1.2, 0.3, 1.5), TT(x, 9.3, 0))
        m.part(f"ShoulderRim{s}", TO, "white", "box", (1.7, 0.3, 2.0), TT(x, 7.85, 0))
        m.part(f"ShoulderBlock{s}", TO, "frame", "box", (0.9, 0.9, 1.2), TT(sign * 2.0, 8.4, 0))
    # Arms
    for s, sign in (("L", -1), ("R", 1)):
        SH = f"{TO}/Shoulder{s}"
        m.part(f"UpperArmFrame{s}", SH, "frame", "cyl", (0.42, 0.42, 1.6), (0, -0.9, 0))
        m.part(f"UpperArm{s}", SH, "white", "box", (0.95, 1.2, 1.0), (0, -1.9, 0))
        EL = f"{SH}/Elbow{s}"
        m.part(f"ElbowJoint{s}", EL, "frame", "sphere", (0.46,))
        m.part(f"Forearm{s}", EL, "white", "box", (1.05, 2.1, 1.12), (0, -1.3, 0))
        m.part(f"Cuff{s}", EL, "white", "box", (1.2, 0.35, 1.26), (0, -2.45, 0))
        m.part(f"Hand{s}", EL, "frame", "box", (0.65, 0.72, 0.78), (0, -3.0, 0))
        m.part(f"Fingers{s}", EL, "dark", "box", (0.6, 0.35, 0.5), (0, -3.35, 0.05))
    # Shield on the left forearm. Local -Z is the outer side of the forearm.
    SL = f"{TO}/ShoulderL/ElbowL"
    m.node("Shield", SL, pos=(0, -1.7, -0.95))
    SHL = f"{SL}/Shield"
    m.part("ShieldRim", SHL, "white", "box", (2.1, 4.9, 0.2), (0, 0, 0.05))
    m.part("ShieldFace", SHL, "red", "box", (1.75, 4.2, 0.2), (0, -0.25, -0.05))
    m.part("ShieldTop", SHL, "white", "box", (1.75, 0.5, 0.26), (0, 2.1, -0.02))
    m.part("ShieldWindow", SHL, "frame", "box", (0.3, 0.18, 0.1), (0.45, 2.1, -0.18))
    m.part("ShieldCrossV", SHL, "yellow", "box", (0.16, 2.4, 0.08), (0, 0.2, -0.18))
    m.part("ShieldCrossH", SHL, "yellow", "prism", (0.9, 0.3, 0.08, 0.5), (0, 0.65, -0.18))
    m.part("ShieldTip", SHL, "yellow", "prism", (0.3, 0.45, 0.08, 0.5), (0, -1.15, -0.18), (0, 0, 180))
    m.part("ShieldMount", SHL, "frame", "box", (0.6, 1.4, 0.5), (0, 0, 0.35))

    # ---- Lower body ----
    m.part("Pelvis", L, "frame", "box", (2.6, 1.0, 2.0), (0, 0.2, 0))
    m.part("Waist", L, "white", "box", (3.1, 0.55, 2.3), (0, 0.55, 0))
    m.part("Crotch", L, "red", "box", (0.8, 1.1, 0.5), (0, -0.15, -1.0))
    m.part("CrotchV", L, "yellow", "prism", (0.55, 0.35, 0.08, 0.5), (0, 0.05, -1.27), (0, 0, 180))
    m.part("CrotchBack", L, "white", "box", (0.8, 0.9, 0.5), (0, -0.1, 0.95))
    for s, sign in (("L", -1), ("R", 1)):
        # Front skirt: pivot at the top edge, the plate hangs down.
        m.node(f"SkirtFront{s}", L, pos=(sign * 1.02, 0.45, -1.1))
        SK = f"{L}/SkirtFront{s}"
        m.part(f"SkirtFrontPlate{s}", SK, "white", "box", (1.2, 1.5, 0.25), (0, -0.7, -0.05), (-10, 0, 0))
        m.part(f"SkirtFrontMark{s}", SK, "yellow", "box", (0.55, 0.5, 0.08), (0, -0.62, -0.23), (-10, 0, 0))
        m.part(f"SkirtSide{s}", L, "white", "box", (0.25, 1.4, 1.6), (sign * 2.05, -0.15, 0), (0, 0, sign * 8))
    m.node("SkirtRear", L, pos=(0, 0.45, 1.1))
    m.part("SkirtRearPlate", f"{L}/SkirtRear", "white", "box", (2.4, 1.3, 0.25), (0, -0.6, 0.05), (10, 0, 0))
    for s, sign in (("L", -1), ("R", 1)):
        HP = f"{L}/Hip{s}"
        m.part(f"HipJoint{s}", HP, "frame", "sphere", (0.55,))
        m.part(f"ThighFrame{s}", HP, "frame", "cyl", (0.5, 0.5, 1.2), (0, -0.6, 0))
        m.part(f"Thigh{s}", HP, "white", "box", (1.25, 1.7, 1.45), (0, -1.55, 0))
        KN = f"{HP}/Knee{s}"
        m.part(f"KneeJoint{s}", KN, "frame", "sphere", (0.5,))
        m.part(f"KneePad{s}", KN, "white", "box", (1.05, 0.85, 0.45), (0, -0.25, -0.75), (-12, 0, 0))
        m.part(f"Shin{s}", KN, "white", "box", (1.3, 1.6, 1.55), (0, -0.95, 0))
        m.part(f"ShinFlare{s}", KN, "white", "box", (1.55, 0.75, 1.85), (0, -1.75, 0.05))
        m.part(f"ShinVent{s}", KN, "frame", "cyl", (0.28, 0.28, 0.12), (sign * 0.82, -1.75, 0.2), (0, 0, 90))
        m.part(f"Ankle{s}", KN, "frame", "sphere", (0.45,), (0, -2.1, 0))
        m.part(f"Foot{s}", KN, "white", "box", (1.35, 0.5, 2.2), (0, -2.12, -0.55))
        m.part(f"FootSole{s}", KN, "red", "box", (1.8, 0.36, 3.2), (0, -2.42, -0.45))
        m.part(f"FootToe{s}", KN, "red", "box", (1.6, 0.35, 0.6), (0, -2.15, -1.8), (-20, 0, 0))

    for s, x in (("L", -0.675), ("R", 0.675)):
        m.flame(f"BoosterFlame{s}", TT(x, 6.15, 2.0), (0, 0, 0), length=2.6, radius=0.4)
    m.nodes.append(f'[node name="BoosterLight" type="OmniLight3D" parent="{TO}"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.4, 3.0)\nvisible = false\nlight_color = Color(1, 0.55, 0.2, 1)\nomni_range = 12.0\n')
    for s in ("L", "R"):
        m.skirt(f"SkirtFollow{s}", f"SkirtFront{s}", [f"Hip{s}"], 0)
    m.skirt("SkirtFollowRear", "SkirtRear", ["HipL", "HipR"], 1)
    m.foot = "FootSole"


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "scenes/mech/granpa_gundam.tscn"
    write_scene(out, "res://scenes/weapons/beam_rifle.tscn", MATS, build)
