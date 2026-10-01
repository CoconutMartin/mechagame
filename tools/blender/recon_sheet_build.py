"""Builds the Recon Sheet mech in models/recon_sheet/recon_sheet.blend and exports the parts.

Run (from the project root):
    blender -b models/recon_sheet/recon_sheet.blend --python tools/blender/recon_sheet_build.py
It removes the old model pieces (not the socket and pivot empties) and builds them again, so hand
edits in the part collections are lost: after hand edits, export with export_parts.py only.

Made from the user's part sheet (head, torso, backpack, arm, hand, leg, foot and joint views):
soft chunky blocks with round edges, flat colors.
  Head: big olive helmet that hangs over a dark gray face, one round red eye on the right side of
        the face, one thin antenna at the back left.
  Torso: olive chest block with front plates, dark gray waist, dark shoulder joint stubs.
  Backpack: two olive side boxes beside a dark center block, two tall dark antennas.
  Arm: olive shoulder block with a dark round cap on the outer face, dark joints, olive upper arm
        and a larger olive forearm block, dark fist with fingers and thumb.
  Leg: dark hip joint, olive thigh block, dark round knee with an olive knee block, olive shin
        that is wider at the bottom, dark ankle, olive foot with a dark toe cap and dark sole.
Colors: materials/recon_sheet (olive armor, darker olive armor_dark, dark gray frame and joint,
red eye). The helpers come from recon_accurate_build.py.
Sizes and places are in mech space (meters): x right, y up (feet at 0), -z forward.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import recon_accurate_build as ra
from recon_accurate_build import crect, cylinder

ra.BEVEL_SEGMENTS = 3
ra.PREVIEW.update({"armor": (0.42, 0.45, 0.26), "armor_dark": (0.35, 0.38, 0.21), "frame": (0.17, 0.17, 0.18),
                   "joint": (0.24, 0.24, 0.25), "eye": (1.0, 0.05, 0.03)})


def hold(socket, obj):
    ra._holder[socket] = bpy.data.objects[obj]


def block(name, socket, w, h, d, pos, mat="armor", c=0.14, taper=1.0, rot=(0, 0, 0), bevel=0.09):
    """Soft box w (x) by h (y) by d (z), corners cut by c, front face (-z) scaled by taper."""
    return ra.plate(name, socket, crect(w, h, c), d, pos, rot, "z", mat, taper, 1.0, None, bevel=bevel)


def side(name, socket, outline, w, pos, mat="armor", bevel=0.09, rot=(0, 0, 0)):
    """Piece cut from a side outline (u = z back/forward, v = y up), w wide in x."""
    return ra.plate(name, socket, outline, w, pos, rot, "x", mat, 1.0, 1.0, None, bevel=bevel)


def head():
    S = "Torso"
    hold(S, "Torso_head")
    # Helmet: rounded top, long brim over the face (side outline, front is -z).
    helmet = [(-0.95, -0.05), (-0.95, 0.25), (-0.7, 0.55), (0.35, 0.62), (0.7, 0.35), (0.7, -0.35), (0.35, -0.42), (-0.2, -0.2)]
    side("Helmet", S, [(u * 1.12, v * 1.12) for u, v in helmet], 1.5, (0, 9.0, -0.3), bevel=0.15)
    # Dark gray face under the brim and the jaw.
    block("Face", S, 1.15, 0.7, 1.2, (0, 8.48, -0.45), "frame", c=0.12, taper=0.92, bevel=0.07)
    block("Jaw", S, 0.8, 0.22, 0.5, (0, 8.18, -0.72), "frame", c=0.06, bevel=0.04)
    # One round red eye on the right side of the face (game +x).
    cylinder("EyeRim", S, 0.19, 0.12, (0.26, 8.52, -1.03), "z", "joint", 24, bevel=0.02)
    cylinder("Eye", S, 0.14, 0.1, (0.26, 8.52, -1.08), "z", "eye", 24, bevel=0.0)
    # Side cheek plates.
    for k in (-1, 1):
        block("Cheek", S, 0.5, 0.45, 0.14, (k * 0.68, 8.5, -0.3), "armor", c=0.08, rot=(0, 90, 0), bevel=0.04)
    # Thin antenna at the back left.
    cylinder("AntennaBase", S, 0.1, 0.25, (-0.5, 9.45, 0.25), "y", "frame", 12, bevel=0.02)
    cylinder("Antenna", S, 0.045, 0.85, (-0.5, 9.95, 0.25), "y", "frame", 10, bevel=0.0)
    block("Neck", S, 0.6, 0.45, 0.7, (0, 8.0, -0.2), "frame", c=0.08, bevel=0.04)


def core():
    S = "Torso"
    hold(S, "Torso_core")
    # Chest block (rounded back, front sloped), front plates.
    chest = [(-1.05, -0.75), (-1.05, 0.55), (-0.75, 0.95), (0.7, 0.95), (1.05, 0.6), (1.05, -0.55), (0.75, -0.95), (-0.75, -0.95)]
    side("Chest", S, chest, 2.4, (0, 7.35, 0.05), bevel=0.15)
    for k in (-1, 1):
        block("ChestPlate", S, 1.0, 0.85, 0.22, (k * 0.55, 7.75, -1.05), "armor", c=(0.08, 0.2, 0.2, 0.08) if k > 0 else (0.2, 0.08, 0.08, 0.2),
              taper=0.92, rot=(-10, 0, 0), bevel=0.06)
    block("ChestLower", S, 1.5, 0.6, 0.25, (0, 6.85, -0.95), "armor_dark", c=0.18, taper=0.9, rot=(8, 0, 0), bevel=0.06)
    block("Vent", S, 0.7, 0.18, 0.1, (0, 7.15, -1.12), "frame", c=0.05, bevel=0.02)
    # Side blocks under the shoulders (side torso hit areas).
    for k in (-1, 1):
        block("ChestSide", S, 0.5, 1.4, 1.5, (k * 1.3, 7.3, 0.05), "armor_dark", c=0.15, bevel=0.08)
    # Dark waist and the shoulder joint stubs.
    block("Waist", S, 1.4, 0.75, 1.2, (0, 6.05, 0.05), "frame", c=0.15, bevel=0.07)
    cylinder("WaistRing", S, 0.62, 0.3, (0, 5.7, 0.05), "y", "joint", 28, bevel=0.03)
    block("Collar", S, 1.2, 0.3, 1.0, (0, 8.35, 0.2), "frame", c=0.08, bevel=0.04)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    hold("Torso", f"Torso_{part}")
    # Big dark shoulder joint (sheet: SHOULDER).
    cylinder(f"ShoulderJoint{s}", "Torso", 0.5, 0.75, (k * 1.9, 7.865, 0), "x", "frame", 32,
             rings=[(k * 0.15, 0.56, 0.14)], bevel=0.04)
    # Olive shoulder block with a dark round cap on the outer face.
    P = f"PauldronPivot{s}"
    hold(P, P)
    block(f"Pauldron{s}", P, 1.15, 1.35, 1.45, (k * 2.8, 8.0, 0.0), "armor", c=0.22, bevel=0.14)
    cylinder(f"ShoulderCap{s}", P, 0.45, 0.22, (k * 3.45, 7.95, 0.05), "x", "frame", 32, rings=[(k * 0.06, 0.32, 0.12)], bevel=0.04)
    # Upper arm: dark joint, olive block.
    SH = f"Shoulder{s}"
    hold(SH, f"{SH}_{part}")
    cylinder(f"UpperJoint{s}", SH, 0.3, 0.7, (k * 2.465, 7.0, 0), "y", "frame", 24, bevel=0.03)
    block(f"UpperArm{s}", SH, 0.85, 1.05, 0.9, (k * 2.5, 6.3, 0.0), "armor", c=0.16, bevel=0.1)
    # Elbow (sheet: ELBOW), big forearm block, wrist, fist.
    EL = f"Elbow{s}"
    hold(EL, f"{EL}_{part}")
    cylinder(f"Elbow{s}", EL, 0.33, 0.75, (k * 2.465, 5.57, 0), "x", "frame", 28, rings=[(0.0, 0.38, 0.2)], bevel=0.03)
    block(f"Forearm{s}", EL, 1.0, 1.6, 1.05, (k * 2.5, 4.45, 0.0), "armor", c=0.18, bevel=0.12)
    block(f"ForearmPlate{s}", EL, 0.7, 1.1, 0.15, (k * 2.5, 4.5, -0.58), "armor_dark", c=0.1, bevel=0.04)
    cylinder(f"Wrist{s}", EL, 0.22, 0.3, (k * 2.465, 3.55, 0), "y", "joint", 20, bevel=0.02)
    # Fist: palm block, four fingers curled at the front, thumb on the inner side.
    block(f"Fist{s}", EL, 0.72, 0.62, 0.72, (k * 2.465, 3.15, 0.0), "frame", c=0.1, bevel=0.06)
    for i in range(4):
        block(f"Finger{s}", EL, 0.16, 0.42, 0.24, (k * 2.465 + (i - 1.5) * 0.175, 3.0, -0.44), "frame", c=0.04, bevel=0.03)
    block(f"Thumb{s}", EL, 0.17, 0.36, 0.36, (k * 2.465 - k * 0.42, 3.12, -0.18), "frame", c=0.04, bevel=0.03)


def legs():
    L = "Lower"
    hold(L, "Lower_legs")
    block("Pelvis", L, 1.6, 0.75, 1.2, (0, 5.25, 0.0), "frame", c=0.18, bevel=0.07)
    block("Groin", L, 0.7, 0.6, 0.25, (0, 5.0, -0.65), "armor", c=0.12, taper=0.85, rot=(-8, 0, 0), bevel=0.06)
    for s, k in (("L", -1), ("R", 1)):
        # Hip joint (sheet: HIP), thigh block.
        block(f"HipJoint{s}", L, 0.55, 0.75, 0.85, (k * 1.05, 5.2, 0), "frame", c=0.12, bevel=0.06)
        cylinder(f"HipCap{s}", L, 0.32, 0.12, (k * 1.33, 5.2, 0), "x", "joint", 24, bevel=0.02)
        H = f"Hip{s}"
        hold(H, f"{H}_legs")
        block(f"Thigh{s}", H, 1.05, 1.7, 1.15, (k * 1.5, 4.0, 0.0), "armor", c=0.2, bevel=0.13)
        block(f"ThighPlate{s}", H, 0.75, 1.1, 0.15, (k * 1.5, 4.05, -0.62), "armor_dark", c=0.1, bevel=0.04)
        cylinder(f"ThighJoint{s}", H, 0.28, 0.5, (k * 1.5, 3.0, 0.05), "y", "frame", 20, bevel=0.03)
        # Knee (sheet: KNEE): dark round joint, olive knee block in front.
        K = f"Knee{s}"
        hold(K, f"{K}_legs")
        cylinder(f"KneeJoint{s}", K, 0.4, 0.95, (k * 1.5, 2.6, 0.05), "x", "frame", 32, rings=[(0.0, 0.45, 0.25)], bevel=0.03)
        block(f"KneePad{s}", K, 0.85, 0.8, 0.45, (k * 1.5, 2.65, -0.45), "armor", c=0.16, taper=0.85, rot=(-8, 0, 0), bevel=0.09)
        # Shin, wider at the bottom, with a front plate and calf block.
        ra.plate(f"Shin{s}", K, [(-0.5, 0.85), (0.5, 0.85), (0.62, 0.55), (0.62, -0.75), (0.45, -0.95), (-0.45, -0.95), (-0.62, -0.75), (-0.62, 0.55)],
                 1.2, (k * 1.5, 1.4, 0.0), (0, 0, 0), "z", "armor", 0.95, 1.0, None, bevel=0.13)
        block(f"ShinPlate{s}", K, 0.7, 1.2, 0.15, (k * 1.5, 1.45, -0.64), "armor_dark", c=0.1, taper=0.95, bevel=0.04)
        block(f"Calf{s}", K, 0.8, 1.2, 0.35, (k * 1.5, 1.5, 0.68), "armor_dark", c=0.12, bevel=0.06)
        # Ankle (sheet: ANKLE), foot wedge, dark toe cap, sole.
        F = f"FootPivot{s}"
        hold(F, F)
        cylinder(f"Ankle{s}", F, 0.32, 0.9, (k * 1.5, 0.55, 0.05), "x", "frame", 28, rings=[(0.0, 0.36, 0.2)], bevel=0.03)
        foot = [(-1.3, 0.1), (-1.3, 0.35), (-0.6, 0.55), (0.0, 0.75), (0.75, 0.75), (0.95, 0.5), (0.95, 0.1)]
        side(f"Foot{s}", F, foot, 1.15, (k * 1.5, 0.0, -0.2), bevel=0.1)
        side(f"Toe{s}", F, [(-0.55, 0.0), (-0.55, 0.32), (-0.1, 0.42), (0.25, 0.42), (0.25, 0.0)], 1.05,
             (k * 1.5, 0.08, -1.7), "frame", bevel=0.07)
        block(f"Sole{s}", F, 1.15, 2.95, 0.12, (k * 1.5, 0.06, -0.72), "frame", c=0.35, rot=(90, 0, 0), bevel=0.03)


def booster():
    S = "Torso"
    hold(S, "Torso_booster")
    block("PackCenter", S, 0.55, 1.35, 0.9, (0, 7.35, 1.45), "frame", c=0.1, bevel=0.06)
    for k in (-1, 1):
        block("PackSide", S, 0.6, 1.2, 0.8, (k * 0.58, 7.3, 1.4), "armor", c=0.14, bevel=0.1)
        # Tall antenna on a thick base.
        cylinder("MastBase", S, 0.13, 0.55, (k * 0.58, 8.15, 1.4), "y", "frame", 16, bevel=0.02)
        cylinder("Mast", S, 0.07, 1.6, (k * 0.58, 9.2, 1.4), "y", "frame", 12, bevel=0.0)
        cylinder("Nozzle", S, 0.25, 0.4, (k * 0.62, 6.45, 1.75), "y", "joint", 24, rot=(25, 0, 0), bevel=0.02)


def build():
    ra.clear_parts()
    ra.preview_colors()
    head()
    core()
    arm("L")
    arm("R")
    legs()
    booster()
    bpy.ops.wm.save_mainfile()
    exec(bpy.data.texts["export_parts.py"].as_string())


build()
