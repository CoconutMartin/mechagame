"""Builds the Recon Sheet mech in models/recon_sheet/recon_sheet.blend and exports the parts.

Run (from the project root):
    blender -b --python tools/blender/mech_kit.py -- recon_sheet data/frames/recon_sheet_frame.tres
    blender -b models/recon_sheet/recon_sheet.blend --python tools/blender/recon_sheet_build.py
(the first line makes a new kit file; only needed when the frame changes). The build removes the old
model pieces (not the socket and pivot empties) and builds them again, so hand edits in the part
collections are lost: after hand edits, export with export_parts.py only.

Traced from the user's three views, models/guides/recon_sheet_views.png (front, left side, back;
ground line at pixel row 863). Every piece is a box or side outline given in picture pixels:
  front view x (mech center at pixel 318, the mech's right side is on the left of the picture),
  picture rows y (ground at 863), side view x for depth (pixel 885 = the leg line, front is left).
One pixel = SCALE meters (the mech is 10 m tall to the helmet top). Hard chamfered edges (one bevel
segment) like the picture. Own joint layout: data/frames/recon_sheet_frame.tres (measured from the
same picture), read by frame_io.py. The helpers come from recon_accurate_build.py.
Colors: materials/recon_sheet (olive armor, darker olive armor_dark, dark gray frame and joint, red eye).
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import frame_io
import recon_accurate_build as ra
from recon_accurate_build import crect, cylinder

SCALE = 0.0132
FRONT_X, GROUND_Y, SIDE_Z = 318, 863, 885
FRAME = "data/frames/recon_sheet_frame.tres"
# Arms: the picture arms hang a little behind the leg line; the model keeps them on the joints.
ARM_Z = -0.15

ra.BEVEL_SEGMENTS = 1
ra.PREVIEW.update({"armor": (0.31, 0.34, 0.18), "armor_dark": (0.25, 0.28, 0.14), "frame": (0.11, 0.11, 0.12),
                   "joint": (0.2, 0.2, 0.21), "eye": (1.0, 0.05, 0.03)})
_sockets, _pivots = frame_io.layout(frame_io.read(FRAME))
ra.SOCKETS.update(_sockets)
for _list in _pivots.values():
    for _name, _socket, _pos, _tilt in _list:
        ra.SOCKETS[_name] = _pos


def X(px):
    return (FRONT_X - px) * SCALE


def Y(py):
    return (GROUND_Y - py) * SCALE


def Z(px):
    return (px - SIDE_Z) * SCALE


def hold(socket, obj):
    ra._holder[socket] = bpy.data.objects[obj]


def box(name, socket, fx, fy, sz, mat="armor", c=0.12, taper=1.0, rot=(0, 0, 0), bevel=0.05, k=1, x=None, z_shift=0.0):
    """Box from picture ranges: fx front view x pixels (mech right side), fy rows, sz side view x
    pixels. k = -1 mirrors it to the mech's left. x: center in meters instead of the fx center.
    taper scales the front face (-z)."""
    x0, x1 = sorted((X(fx[0]), X(fx[1])))
    y0, y1 = sorted((Y(fy[0]), Y(fy[1])))
    z0, z1 = Z(sz[0]), Z(sz[1])
    cx = (x0 + x1) * 0.5 if x is None else x
    pos = (k * cx, (y0 + y1) * 0.5, (z0 + z1) * 0.5 + z_shift)
    r = (rot[0], rot[1], rot[2] * k)
    return ra.plate(name, socket, crect(x1 - x0, y1 - y0, c), z1 - z0, pos, r, "z", mat, taper, 1.0, None, bevel=bevel)


def side(name, socket, points, fx, mat="armor", bevel=0.05, k=1, x=None, z_shift=0.0, scale=1.0):
    """Piece cut from a side view outline (side view pixels), as wide as the front view range fx.
    scale shrinks the far side (back half) of the outline toward its center."""
    x0, x1 = sorted((X(fx[0]), X(fx[1])))
    pts = [(Z(px), Y(py)) for px, py in points]
    cu = (min(u for u, v in pts) + max(u for u, v in pts)) * 0.5
    cv = (min(v for u, v in pts) + max(v for u, v in pts)) * 0.5
    outline = [(u - cu, v - cv) for u, v in pts]
    cx = (x0 + x1) * 0.5 if x is None else x
    return ra.plate(name, socket, outline, x1 - x0, (k * cx, cv, cu + z_shift), (0, 0, 0), "x", mat, scale, 1.0, None, bevel=bevel)


def head():
    S = "Torso"
    hold(S, "Torso_head")
    # Helmet: brim over the face, sloped top, from the side view.
    helmet = [(732, 153), (752, 130), (800, 113), (885, 100), (896, 140), (884, 190), (805, 180), (765, 160)]
    side("Helmet", S, helmet, (280, 356), bevel=0.12)
    box("Face", S, (286, 350), (150, 216), (748, 878), "frame", c=0.1, taper=0.9)
    box("Chin", S, (296, 340), (196, 214), (742, 790), "frame", c=0.04)
    cylinder("EyeRing", S, 0.21, 0.08, (0.0, Y(173), Z(748) - 0.02), "z", "joint", 24, bevel=0.0)
    cylinder("Eye", S, 0.16, 0.08, (0.0, Y(173), Z(748) - 0.06), "z", "eye", 24, bevel=0.0)
    box("Neck", S, (292, 344), (205, 250), (790, 880), "frame", c=0.08)


def core():
    S = "Torso"
    hold(S, "Torso_core")
    # Chest: deep block that bulges far forward (side view), olive.
    chest = [(712, 245), (735, 205), (800, 188), (950, 185), (965, 240), (960, 320), (880, 345), (765, 342), (718, 300)]
    side("Chest", S, chest, (216, 420), bevel=0.2)
    # Front plates beside the head (side torso areas) and the center plate.
    for k in (1, -1):
        box("ChestBlock", S, (205, 272), (170, 326), (712, 900), c=0.14, taper=0.9, bevel=0.15, k=k)
    box("ChestCenter", S, (276, 360), (225, 340), (700, 800), c=0.12, taper=0.88, bevel=0.15)
    box("Collar", S, (255, 381), (165, 232), (760, 900), "frame", c=0.1)
    box("Waist", S, (245, 391), (322, 368), (775, 905), "frame", c=0.1)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    hold("Torso", f"Torso_{part}")
    sx, sy = ra.SOCKETS[f"Shoulder{s}"][0] * k, ra.SOCKETS[f"Shoulder{s}"][1]
    # Dark shoulder joint between the chest and the pauldron (front view x 160 to 210).
    cylinder(f"ShoulderJoint{s}", "Torso", 0.7, 0.66, (k * X(185), sy, -0.4), "x", "frame", 24,
             rings=[(k * 0.1, 0.76, 0.12)], bevel=0.03)
    # Pauldron: big block, outer edge raised 16.5 degrees, square vent on the outer face.
    P = f"PauldronPivot{s}"
    hold(P, P)
    box(f"Pauldron{s}", P, (15, 175), (118, 245), (820, 995), c=0.3, rot=(0, 0, 16.5), bevel=0.2, k=k, x=2.75, z_shift=ARM_Z)
    a = math.radians(16.5)
    reach = 1.07  # pauldron half width + vent half depth
    cy = (Y(118) + Y(245)) * 0.5
    ra.plate(f"PauldronVent{s}", P, crect(0.95, 0.79, 0.05), 0.1,
             (k * (2.75 + reach * math.cos(a)), cy + reach * math.sin(a), Z(944) + ARM_Z), (0, 0, k * 16.5),
             "x", "frame", 1.0, 1.0, None, bevel=0.01)
    # Upper arm: short olive block under the pauldron.
    SH = f"Shoulder{s}"
    hold(SH, f"{SH}_{part}")
    cylinder(f"UpperJoint{s}", SH, 0.32, 0.6, (k * 2.75, Y(262), ARM_Z), "y", "frame", 20, bevel=0.02)
    box(f"UpperArm{s}", SH, (80, 155), (255, 312), (880, 950), c=0.12, bevel=0.1, k=k, x=2.75, z_shift=ARM_Z - 0.3)
    # Elbow, large forearm block, wrist, fist with fingers.
    EL = f"Elbow{s}"
    hold(EL, f"{EL}_{part}")
    cylinder(f"Elbow{s}", EL, 0.4, 0.9, (k * 2.85, ra.SOCKETS[EL][1], ARM_Z), "x", "frame", 24, rings=[(0.0, 0.46, 0.2)], bevel=0.02)
    box(f"Forearm{s}", EL, (25, 140), (335, 480), (850, 970), c=0.3, taper=0.92, bevel=0.18, k=k, x=3.1, z_shift=ARM_Z - 0.33)
    cylinder(f"Wrist{s}", EL, 0.3, 0.3, (k * 3.2, Y(488), ARM_Z), "y", "joint", 20, bevel=0.02)
    box(f"Fist{s}", EL, (30, 105), (492, 545), (848, 922), "frame", c=0.12, k=k, x=3.25, z_shift=ARM_Z)
    for i in range(4):
        box(f"Finger{s}", EL, (0, 13), (520, 560), (836, 866), "frame", c=0.05, bevel=0.02, k=k,
            x=3.25 + (i - 1.5) * 0.21, z_shift=ARM_Z)
    box(f"Thumb{s}", EL, (0, 14), (505, 540), (850, 900), "frame", c=0.05, bevel=0.02, k=k, x=3.25 - 0.6, z_shift=ARM_Z)


def legs():
    L = "Lower"
    hold(L, "Lower_legs")
    box("Pelvis", L, (235, 401), (360, 420), (780, 900), "frame", c=0.12)
    box("SkirtTop", L, (220, 416), (362, 388), (745, 890), "armor_dark", c=0.08)
    box("Groin", L, (282, 354), (365, 452), (740, 800), c=0.12, taper=0.88, bevel=0.12)
    for s, k in (("L", -1), ("R", 1)):
        cylinder(f"HipJoint{s}", L, 0.48, 0.4, (k * 0.72, Y(437), -0.3), "x", "frame", 24, bevel=0.03)
        H = f"Hip{s}"
        hold(H, f"{H}_legs")
        cylinder(f"ThighFrame{s}", H, 0.42, 1.7, (k * 1.6, 4.9, -0.1), "y", "frame", 20, bevel=0.02)
        box(f"Thigh{s}", H, (150, 265), (378, 545), (790, 880), c=0.3, taper=0.9, bevel=0.2, k=k, x=1.55, z_shift=-0.25)
        # Rear thigh plate (back view: olive behind the thigh frame).
        box(f"ThighBack{s}", H, (160, 262), (395, 530), (880, 960), c=0.25, bevel=0.15, k=k, x=1.55)
        K = f"Knee{s}"
        hold(K, f"{K}_legs")
        cylinder(f"KneeJoint{s}", K, 0.55, 1.1, (k * 1.66, ra.SOCKETS[K][1], -0.3), "x", "frame", 28, rings=[(0.0, 0.6, 0.3)], bevel=0.03)
        box(f"ShinFrame{s}", K, (0, 60), (600, 800), (855, 915), "frame", c=0.1, k=k, x=1.75)
        # Knee pad (front), inner shin plate, calf block (back), lower shin.
        box(f"KneePad{s}", K, (125, 225), (570, 690), (775, 860), c=0.3, taper=0.88, bevel=0.18, k=k, x=1.88)
        box(f"ShinInner{s}", K, (200, 255), (590, 700), (800, 900), c=0.12, bevel=0.12, k=k, x=1.2)
        box(f"Calf{s}", K, (0, 90), (575, 700), (855, 970), c=0.3, bevel=0.18, k=k, x=1.8)
        box(f"Shin{s}", K, (0, 105), (688, 778), (825, 950), c=0.25, taper=0.92, bevel=0.15, k=k, x=1.95)
        # Ankle, foot wedge, dark toe cap, heel block, inner ankle guard, sole.
        F = f"FootPivot{s}"
        hold(F, F)
        cylinder(f"Ankle{s}", F, 0.44, 1.0, (k * 1.85, ra.SOCKETS[F][1], 0.2), "x", "frame", 28, rings=[(0.0, 0.48, 0.25)], bevel=0.03)
        foot = [(745, 858), (748, 812), (800, 786), (872, 768), (950, 776), (962, 858)]
        side(f"Foot{s}", F, foot, (95, 250), bevel=0.12, k=k, x=2.0)
        toe = [(683, 858), (690, 838), (745, 806), (770, 822), (770, 858)]
        side(f"Toe{s}", F, toe, (82, 235), "frame", bevel=0.05, k=k, x=2.0)
        heel = [(945, 858), (945, 792), (992, 780), (1008, 858)]
        side(f"Heel{s}", F, heel, (0, 95), bevel=0.1, k=k, x=1.9)
        box(f"AnkleGuard{s}", F, (0, 42), (732, 850), (850, 930), c=0.12, bevel=0.1, k=k, x=1.25)
        box(f"Sole{s}", F, (85, 245), (850, 863), (686, 1006), "frame", c=0.04, bevel=0.02, k=k, x=2.0)


def booster():
    S = "Torso"
    hold(S, "Torso_booster")
    box("PackCenter", S, (285, 351), (160, 375), (960, 1010), "frame", c=0.1)
    for k in (1, -1):
        box("PackSide", S, (0, 80), (165, 378), (940, 990), c=0.14, bevel=0.12, k=k, x=0.85)
        # Antennas: thick base, thin top (front view x 252 and 382).
        cylinder("MastBase", S, 0.26, 1.34, (k * X(252), 9.27, Z(915)), "y", "frame", 16, bevel=0.03)
        cylinder("Mast", S, 0.145, 1.12, (k * X(252), 10.5, Z(915)), "y", "frame", 12, bevel=0.03)
        cylinder("Nozzle", S, 0.26, 0.4, (k * 0.64, ra.SOCKETS["Torso"][1] + 0.493, 1.75), "y", "joint", 20, rot=(25, 0, 0), bevel=0.02)


def reference_images():
    """The three views as reference images in the Blender front and side views (not exported)."""
    path = os.path.join(frame_io.ROOT, "models", "guides", "recon_sheet_views.png")
    if not os.path.exists(path) or bpy.data.objects.get("ref_front"):
        return
    image = bpy.data.images.load(path)
    width = image.size[0] * SCALE
    for name, rot, loc in (("ref_front", (1.5708, 0, 0), (0, 6.0, 0)), ("ref_side", (1.5708, 0, 1.5708), (-6.0, 0, 0))):
        ref = bpy.data.objects.new(name, None)
        ref.empty_display_type = "IMAGE"
        ref.data = image
        ref.empty_display_size = width
        ref.rotation_euler = rot
        ref.location = loc
        ref.use_empty_image_alpha = True
        ref.color = (1.0, 1.0, 1.0, 0.5)
        bpy.context.scene.collection.objects.link(ref)
        # Line up the picture: mech center, ground line.
        offset_x = FRONT_X if name == "ref_front" else SIDE_Z
        ref.empty_image_offset = (-offset_x / image.size[0], -(image.size[1] - GROUND_Y) / image.size[1])


def build():
    ra.clear_parts()
    ra.preview_colors()
    head()
    core()
    arm("L")
    arm("R")
    legs()
    booster()
    reference_images()
    bpy.ops.wm.save_mainfile()
    exec(bpy.data.texts["export_parts.py"].as_string())


build()
