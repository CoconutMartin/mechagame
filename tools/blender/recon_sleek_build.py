"""Builds the Recon Sleek mech in models/recon_sleek/recon_sleek.blend and exports the parts.

Run (from the project root):
    blender -b models/recon_sleek/recon_sleek.blend --python tools/blender/recon_sleek_build.py
It removes the old model pieces (not the socket and pivot empties) and builds them again, so hand
edits in the part collections are lost: after hand edits, export with export_parts.py only.

A sleek version of Recon Accurate (same reference, same skeleton, same colors): slimmer limbs,
swept and tapered plates, soft wide bevels, no bolts, thin panel lines.
  Head: long low wedge with a pointed nose, one red visor band, two swept fins.
  Chest: V-shaped chest that narrows to a thin waist, a pointed keel plate, thin vent lines.
  Shoulders: swept teardrop pauldrons with a rear fin and a slit vent.
  Arms: thin frame, long forearm guards that taper to the wrist, small fists.
  Legs: tapered thighs, pointed diamond knee pads, long tapered shins with a calf fairing,
        long pointed feet.
  Back: slim backpack, two thin tapered antennas, nozzles.
The helpers (plate, cylinder, outlines) come from recon_accurate_build.py.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import recon_accurate_build as ra
from recon_accurate_build import crect, ngon, trapezoid, cylinder

ra.BEVEL_SEGMENTS = 4
SOFT = 0.07   # Bevel width of the large plates (meters).


def plate(*args, **kw):
    """ra.plate with soft bevels, thin panel lines and no bolts."""
    kw.setdefault("bevel", SOFT)
    if len(args) < 12:
        kw.setdefault("inset", 0.06)
    kw.pop("bolts", None)
    return ra.plate(*args, **kw)


def hold(socket, obj):
    ra._holder[socket] = bpy.data.objects[obj]


def head():
    S = "Torso"
    hold(S, "Torso_head")
    # Long low wedge: side outline (z back/forward, y up), pointed nose at the front (-z).
    helmet = [(-1.25, -0.2), (-1.2, 0.02), (-0.5, 0.42), (0.55, 0.5), (0.85, 0.2), (0.8, -0.3), (-0.3, -0.42)]
    plate("Helmet", S, helmet, 1.05, (0, 8.55, -0.5), (0, 0, 0), "x", "armor", 0.8, 0.8, None, bevel=0.1)
    plate("Cheek", S, [(-1.0, -0.12), (-0.4, 0.12), (0.5, 0.1), (0.5, -0.25), (-0.5, -0.3)], 1.2,
          (0, 8.4, -0.55), (0, 0, 0), "x", "armor_dark", 0.85, 0.85, None, bevel=0.05)
    # One visor band across the face, eyes glow inside it.
    plate("Visor", S, crect(0.8, 0.12, 0.05), 0.2, (0, 8.52, -1.43), (-12, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.03)
    plate("VisorGlow", S, crect(0.62, 0.05, 0.02), 0.06, (0, 8.52, -1.53), (-12, 0, 0), "z", "eye", 1.0, 1.0, None, bevel=0.0)
    for k in (-1, 1):
        fin = [(-0.35, 0.0), (0.2, 0.08), (0.75, 0.5), (0.6, 0.0), (0.3, -0.12)]
        plate("Fin", S, [(u, v) for u, v in fin], 0.07, (k * 0.36, 8.95, 0.1), (0, 0, -k * 8), "x", "armor", 1.0, 1.0, None, bevel=0.02)
    cylinder("Lens", S, 0.07, 0.14, (0.0, 8.28, -1.5), "z", "lens", 16)
    plate("Neck", S, crect(0.6, 0.45, 0.12), 0.8, (0, 7.95, -0.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.04)


def core():
    S = "Torso"
    hold(S, "Torso_core")
    # V-shaped chest: wide at the shoulders, narrow at the waist, tapered to the front.
    chest = trapezoid(2.5, 1.5, 2.1, 0.45)
    plate("Chest", S, chest, 1.9, (0, 7.3, 0.0), (0, 0, 0), "z", "armor_dark", 0.82, 1.0, None, bevel=0.14)
    # Sloped upper plates beside the head.
    for k in (-1, 1):
        c = (0.35, 0.08, 0.3, 0.08) if k < 0 else (0.08, 0.35, 0.08, 0.3)
        plate("ChestUpper", S, crect(0.95, 0.8, c), 0.22, (k * 0.66, 8.05, -0.88), (-34, k * -8, 0), "z", "armor", 0.9, 1.0, "front")
    # Pointed keel plate down the chest.
    keel = [(-0.6, 0.55), (0.6, 0.55), (0.52, -0.1), (0.0, -0.75), (-0.52, -0.1)]
    plate("Keel", S, keel, 0.3, (0, 7.05, -0.98), (-8, 0, 0), "z", "armor", 0.9, 1.0, "front")
    for i in range(2):
        plate("ChestVent", S, crect(0.55, 0.035, 0.015), 0.05, (0, 7.35 - i * 0.12, -1.16), (-8, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
    plate("ChestMark", S, crect(0.05, 0.5, 0.01), 0.04, (-0.42, 6.95, -1.12), (-8, 0, 0), "z", "emblem", 1.0, 1.0, None, bevel=0.0)
    # Side plates under the shoulders (side torso hit areas), swept back.
    for k in (-1, 1):
        side = [(-0.8, 0.7), (0.55, 0.75), (0.85, 0.2), (0.6, -0.7), (-0.6, -0.55)]
        plate("ChestSide", S, side, 0.5, (k * 1.3, 7.3, 0.1), (0, 0, 0), "x", "armor", 0.92, 0.92, None)
    # Thin waist.
    plate("Abdomen", S, trapezoid(1.0, 0.75, 0.6, 0.12), 0.95, (0, 6.05, 0.05), (0, 0, 0), "z", "frame", 0.95, 1.0, None, bevel=0.05)
    cylinder("Waist", S, 0.5, 0.35, (0, 5.75, 0.05), "y", "joint", 32, rings=[(0.12, 0.54, 0.05)])
    plate("Collar", S, crect(1.3, 0.3, 0.12), 1.0, (0, 8.45, 0.35), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.05)
    plate("Back", S, trapezoid(1.8, 1.2, 1.6, 0.35), 0.45, (0, 7.45, 1.0), (0, 0, 0), "z", "frame", 1.0, 0.9, None)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    hold("Torso", f"Torso_{part}")
    cylinder(f"ShoulderJoint{s}", "Torso", 0.42, 0.85, (k * 1.95, 7.865, 0), "x", "frame", 32,
             rings=[(k * 0.2, 0.47, 0.08)])
    # Pauldron: swept teardrop in the side view (low round front, long rising back).
    P = f"PauldronPivot{s}"
    hold(P, P)
    side = [(-1.05, -0.35), (-1.0, 0.25), (-0.6, 0.7), (0.4, 0.95), (1.35, 1.05), (1.25, 0.35), (0.8, -0.55), (-0.5, -0.75)]
    plate(f"Pauldron{s}", P, side, 1.05, (k * 2.82, 7.9, 0.0), (0, 0, -k * 12), "x", "armor",
          1.0 if k < 0 else 0.72, 0.72 if k < 0 else 1.0, "back" if k > 0 else "front", 0.08, bevel=0.16)
    fin = [(0.0, 0.0), (0.9, 0.1), (1.35, 0.55), (0.7, 0.35), (-0.1, 0.18)]
    plate(f"PauldronFin{s}", P, fin, 0.08, (k * 2.95, 8.75, 0.25), (0, 0, k * 10), "x", "armor_dark", 1.0, 1.0, None, bevel=0.02)
    for i in range(3):
        plate(f"PauldronVent{s}", P, crect(0.7, 0.04, 0.015), 0.06, (k * 3.45, 7.75 - i * 0.12, 0.35), (0, 90, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
    plate(f"PauldronInner{s}", P, crect(1.4, 1.1, 0.35), 0.1, (k * 2.3, 7.95, 0.0), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None, bevel=0.03)
    # Thin upper arm with a slim outer plate.
    SH = f"Shoulder{s}"
    hold(SH, f"{SH}_{part}")
    cylinder(f"UpperArmFrame{s}", SH, 0.24, 1.8, (k * 2.465, 6.75, 0), "y", "frame", 24, rings=[(0.55, 0.29, 0.1)])
    plate(f"UpperArm{s}", SH, trapezoid(0.75, 0.55, 1.2, 0.2), 0.22, (k * 2.8, 6.65, 0), (0, 90, 0), "z", "armor", 0.9, 1.0, None)
    # Elbow and a long forearm guard that tapers to the wrist.
    EL = f"Elbow{s}"
    hold(EL, f"{EL}_{part}")
    cylinder(f"Elbow{s}", EL, 0.3, 0.65, (k * 2.465, 5.57, 0), "x", "frame", 28, rings=[(0.0, 0.35, 0.12)])
    guard = [(-0.42, 0.25), (-0.25, 0.55), (0.25, 0.55), (0.42, 0.25), (0.42, -0.3), (0.2, -0.5), (-0.2, -0.5), (-0.42, -0.3)]
    plate(f"Forearm{s}", EL, guard, 1.75, (k * 2.5, 4.5, 0.02), (0, 0, 0), "y", "armor", 0.72, 1.0, None, bevel=0.1)
    plate(f"ForearmStripe{s}", EL, crect(0.12, 1.2, 0.04), 0.06, (k * 2.5, 4.6, -0.5), (-5, 0, 0), "z", "armor_dark", 1.0, 1.0, None, bevel=0.0)
    cylinder(f"Wrist{s}", EL, 0.2, 0.3, (k * 2.465, 3.55, 0), "y", "joint", 20)
    plate(f"Fist{s}", EL, crect(0.5, 0.52, 0.12), 0.58, (k * 2.465, 3.12, -0.05), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.05)


def legs():
    L = "Lower"
    hold(L, "Lower_legs")
    plate("Pelvis", L, crect(1.45, 0.75, 0.25), 1.15, (0, 5.25, 0.0), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.05)
    skirt = [(-0.42, 0.4), (0.42, 0.4), (0.3, -0.1), (0.0, -0.5), (-0.3, -0.1)]
    plate("Skirt", L, skirt, 0.2, (0, 4.95, -0.72), (-12, 0, 0), "z", "armor", 0.9, 1.0, "front")
    plate("SkirtBack", L, trapezoid(0.9, 0.55, 0.7, 0.15), 0.2, (0, 5.0, 0.68), (12, 0, 0), "z", "armor_dark", 0.9, 1.0, None)
    for s, k in (("L", -1), ("R", 1)):
        cylinder(f"HipJoint{s}", L, 0.42, 0.65, (k * 1.05, 5.2, 0), "x", "frame", 32, rings=[(0.0, 0.46, 0.1)])
        H = f"Hip{s}"
        hold(H, f"{H}_legs")
        cylinder(f"ThighFrame{s}", H, 0.27, 2.3, (k * 1.5, 3.95, 0.15), "y", "frame", 24, rings=[(0.7, 0.32, 0.12)])
        plate(f"Thigh{s}", H, trapezoid(1.2, 0.8, 2.0, 0.3), 0.5, (k * 1.5, 4.05, -0.42), (-4, 0, 0), "z", "armor", 0.85, 1.0, "front", bevel=0.1)
        plate(f"ThighSide{s}", H, trapezoid(1.1, 0.7, 1.5, 0.3), 0.14, (k * 2.02, 4.1, -0.05), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None, bevel=0.03)
        K = f"Knee{s}"
        hold(K, f"{K}_legs")
        cylinder(f"KneeJoint{s}", K, 0.35, 0.85, (k * 1.5, 2.6, 0), "x", "frame", 28, rings=[(0.0, 0.4, 0.1)])
        # Pointed diamond knee pad.
        plate(f"KneePad{s}", K, ngon(0.55, 4, 90, 0.9, 1.35), 0.32, (k * 1.5, 2.7, -0.6), (-10, 0, 0), "z", "armor", 0.8, 1.0, "front")
        # Long shin that tapers to the ankle, with a swept calf fairing behind.
        plate(f"Shin{s}", K, trapezoid(1.05, 0.7, 1.95, 0.22), 0.85, (k * 1.5, 1.45, -0.18), (0, 0, 0), "z", "armor", 0.85, 1.0, "front", bevel=0.12)
        calf = [(-0.35, 0.9), (0.2, 0.85), (0.75, 0.3), (0.55, -0.7), (-0.2, -0.85)]
        plate(f"Calf{s}", K, calf, 0.6, (k * 1.5, 1.55, 0.35), (0, 0, 0), "x", "armor_dark", 0.9, 0.9, None)
        F = f"FootPivot{s}"
        hold(F, F)
        cylinder(f"Ankle{s}", F, 0.3, 0.85, (k * 1.5, 0.55, 0), "x", "frame", 28, rings=[(0.0, 0.34, 0.14)])
        # Long pointed foot: side outline (z back/forward, y up) with a sharp toe.
        wedge = [(-2.0, 0.0), (-1.95, 0.14), (-1.1, 0.42), (-0.2, 0.68), (0.6, 0.68), (0.95, 0.35), (0.95, 0.0)]
        plate(f"Foot{s}", F, wedge, 1.05, (k * 1.5, 0.0, -0.3), (0, 0, 0), "x", "armor", 0.9, 0.9, None, bevel=0.05)
        plate(f"Toe{s}", F, trapezoid(0.85, 0.5, 0.5, 0.1), 0.1, (k * 1.5, 0.08, -2.0), (90, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.02)
        plate(f"FootSole{s}", F, crect(1.0, 2.9, 0.3), 0.1, (k * 1.5, 0.05, -0.45), (90, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.02)


def booster():
    S = "Torso"
    hold(S, "Torso_booster")
    plate("Backpack", S, trapezoid(1.4, 1.0, 1.6, 0.3), 0.7, (0, 7.45, 1.58), (0, 0, 0), "z", "armor_dark", 1.0, 0.85, None)
    for i in range(3):
        plate("Grille", S, crect(0.8, 0.05, 0.02), 0.06, (0, 7.85 - i * 0.16, 1.95), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
    for k in (-1, 1):
        cylinder("Nozzle", S, 0.27, 0.5, (k * 0.64, 6.25, 1.85), "y", "joint", 24, rot=(25, 0, 0))
        plate("MastBase", S, trapezoid(0.4, 0.3, 0.45, 0.08), 0.35, (k * 0.5, 8.35, 1.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.04)
        # Thin antenna that tapers to a point.
        plate("Mast", S, ngon(0.11, 8), 2.4, (k * 0.5, 9.75, 1.3), (0, 0, 0), "y", "frame", 1.0, 0.3, None, bevel=0.0)
        cylinder("MastRing", S, 0.14, 0.06, (k * 0.5, 9.2, 1.3), "y", "joint", 16)


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
