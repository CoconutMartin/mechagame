"""Builds Beam Rifle 4 (two-hand sniper beam rifle, 10 m long, one barrel) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_4_build.py
Writes models/beam_rifle_4/beam_rifle_4.blend and beam_rifle_4.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

From the user's picture models/guides/beam_rifle_4_ref.png (two side views, front, back, top, bottom). Traced
from the level side view (the second picture, x 48 muzzle to 1080 butt). User request 2026-11-01: "make the
barrel part longer, total length 7 meters. One barrel only" (the picture has two barrels); then "Extend to 10
meters. Beautify, add some character, body, and heft".

Picture pixels (x, y) go to the first Beam Rifle's frame (u, v) by PU and PV: the receiver and stock (x 560
and back) at KR frame pixels per picture pixel, with the pistol grip on the first Beam Rifle's grip (frame 1338,
370) and the butt at the frame origin (u 1728); the barrel section (x 48 to 560) stretched to KF so the rifle is
10 m long, and heights at KV (35% more). The lower armor and the hand pad sit a little lower than the Beam Rifle's rail: the scene's left hand markers
go down (LEFT_DROP_REST, LEFT_DROP_AIM in the scene notes, DESIGN "Beam Rifle 4").

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = left side of the gun.
Origin: the butt pad back face (frame u 1728), on the first Beam Rifle's bore row.
Empties: GripRight, GripLeft, Muzzle (the barrel front, where the beam leaves).
Glow meshes: SightLens (amber, always lit, emissive material), MuzzleRing (the weapon flashes it orange at a shot).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "beam_rifle_4")

# The first Beam Rifle's picture frame: muzzle at pixel 492, butt at 1728 (6 m), bore row 241.
MUZZLE_PX, BUTT_PX, BORE_PX = 492, 1728, 241
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
BEVEL = 0.018

# name: (base color, roughness, metallic, emission strength). Colors from the picture.
MATERIALS = {
    "beam_rifle_4_white": ((0.78, 0.77, 0.75), 0.5, 0.0, 0.0),
    "beam_rifle_4_dark": ((0.03, 0.032, 0.036), 0.5, 0.3, 0.0),
    "beam_rifle_4_grey": ((0.11, 0.115, 0.125), 0.45, 0.4, 0.0),
    "beam_rifle_4_orange": ((1.0, 0.36, 0.04), 0.35, 0.0, 0.0),
    "beam_rifle_4_glass": ((0.25, 0.42, 0.45), 0.08, 0.0, 0.0),
    # Sight lens: amber, always glowing (user choice 2026-11-01).
    "beam_rifle_4_amber": ((1.0, 0.55, 0.05), 0.2, 0.0, 2.0),
}
A = "beam_rifle_4_amber"
W, D, GR, O, G = ("beam_rifle_4_white", "beam_rifle_4_dark", "beam_rifle_4_grey", "beam_rifle_4_orange",
                  "beam_rifle_4_glass")


def Y(px):
    return (BUTT_PX - px) * SCALE


def Z(py):
    return (BORE_PX - py) * SCALE


def P(px):
    """Picture pixels to meters (lengths)."""
    return px * SCALE


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, glow = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = glow
    mat.diffuse_color = (*color, 1.0)
    return mat


def finish(obj, mat, bevel=BEVEL, segments=1):
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        if hasattr(obj.data, "use_auto_smooth"):
            obj.data.use_auto_smooth = True
    return obj


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def prism(name, mat, outline, width, x=0.0, bevel=BEVEL):
    """Side outline [(u, v) picture pixels], extruded across X (width m), centered on x."""
    bm = bmesh.new()
    verts = [bm.verts.new((x - width / 2, Y(u), Z(v))) for u, v in outline]
    face = bm.faces.new(verts)
    bmesh.ops.recalc_face_normals(bm, faces=[face])
    out = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in out["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(width, 0, 0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def box(name, mat, u0, u1, v0, v1, width, x=0.0, bevel=BEVEL):
    """Box from picture pixels (u0..u1 along the gun, v0..v1 top to bottom), width m across."""
    return prism(name, mat, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], width, x, bevel)


def chamfer_box(name, mat, u0, u1, v0, v1, width, cut, x=0.0, bevel=BEVEL):
    """Box with its four side corners cut by cut pixels (the rail segments)."""
    return prism(name, mat, [(u0 + cut, v0), (u1 - cut, v0), (u1, v0 + cut), (u1, v1 - cut),
                             (u1 - cut, v1), (u0 + cut, v1), (u0, v1 - cut), (u0, v0 + cut)], width, x, bevel)


def tube(name, mat, u0, u1, radius_px, v=BORE_PX, x=0.0, bevel=0.01, sides=24):
    """Cylinder along the gun (u0..u1 pixels), radius in pixels."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px),
                          radius2=P(radius_px), depth=abs(Y(u0) - Y(u1)))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=(x, (Y(u0) + Y(u1)) / 2, Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def disc(name, mat, u, v, radius_px, width, bevel=0.012, sides=32):
    """Cylinder across the gun (axis X), centered at picture pixel (u, v)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px), radius2=P(radius_px),
                          depth=width)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(0, Y(u), Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def pin(name, u, v, half_width):
    """Small dark round pin through the part, seen as a dot on both sides."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=P(4.0), radius2=P(4.0),
                          depth=half_width * 2 + 0.01)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(0, Y(u), Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), D, 0.0)


def slanted(name, mat, center_u, center_v, length_px, depth_px, width, angle_deg, x=0.0, bevel=BEVEL):
    """Box along a slanted axis (the pistol grip). angle_deg: tilt of the long axis from vertical,
    bottom end toward the butt."""
    a = math.radians(angle_deg)
    down = (math.sin(a), math.cos(a))
    back = (math.cos(a), -math.sin(a))
    hl, hd = length_px / 2, depth_px / 2
    pts = []
    for sl, sd in ((-1, -1), (-1, 1), (1, 1), (1, -1)):
        pts.append((center_u + down[0] * hl * sl + back[0] * hd * sd,
                    center_v + down[1] * hl * sl + back[1] * hd * sd))
    return prism(name, mat, pts, width, x, bevel)


def empty(name, u, v, x=0.0):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = (x, Y(u), Z(v))
    bpy.context.collection.objects.link(obj)
    return obj



GRIP_X, GRIP_Y = 770, 625      # Picture grip center (level side view).
SPLIT_X = 560                  # Front of the receiver: the barrel section is in front of it.
KR = 390 / (1080 - GRIP_X)     # Frame pixels per picture pixel along the gun, receiver and stock (butt at 1728).
# Heft (user 2026-11-01: "Extend to 10 meters. Beautify, add some character, body, and heft"): heights and
# radii at KV, 35% more than KR. The grip stays on the first Beam Rifle's grip, so the body grows upward.
KV = KR * 1.35
U_SPLIT = 1338 + (SPLIT_X - GRIP_X) * KR
LENGTH_M = 10.0
MUZZLE_U = 1728 - LENGTH_M / SCALE
KF = (U_SPLIT - MUZZLE_U) / (SPLIT_X - 43)  # The bore face (picture x 43) is the muzzle.


def PU(x):
    if x >= SPLIT_X:
        return 1338 + (x - GRIP_X) * KR
    return U_SPLIT - (SPLIT_X - x) * KF


def XU(u):
    """Frame pixel u back to a picture x (the inverse of PU)."""
    if u >= U_SPLIT:
        return GRIP_X + (u - 1338) / KR
    return SPLIT_X - (U_SPLIT - u) / KF


def XZ(z_godot):
    """Picture x of a place given as Godot z (meters, negative = forward of the butt)."""
    return XU(1728 + z_godot / SCALE)


def PV(y):
    return 370 + (y - GRIP_Y) * KV


def pic(outline):
    return [(PU(x), PV(y)) for x, y in outline]


def pbox(name, mat, x0, x1, y0, y1, width, x=0.0, bevel=BEVEL):
    return box(name, mat, PU(x0), PU(x1), PV(y0), PV(y1), width, x, bevel)


def pprism(name, mat, outline, width, x=0.0, bevel=BEVEL):
    return prism(name, mat, pic(outline), width, x, bevel)


def pchamfer(name, mat, x0, x1, y0, y1, width, cut, bevel=BEVEL):
    """Box with its side corners cut by cut picture pixels (vertical cut at KV, along the gun at the local scale)."""
    u0, u1, v0, v1 = PU(x0), PU(x1), PV(y0), PV(y1)
    c = cut * KV
    return prism(name, mat, [(u0 + c, v0), (u1 - c, v0), (u1, v0 + c), (u1, v1 - c), (u1 - c, v1), (u0 + c, v1),
                             (u0, v1 - c), (u0, v0 + c)], width, 0.0, bevel)


def ptube(name, mat, x0, x1, radius, y, bevel=0.01, sides=24):
    return tube(name, mat, PU(x0), PU(x1), radius * KV, PV(y), 0.0, bevel, sides)


def ppin(name, x, y, half_width):
    return pin(name, PU(x), PV(y), half_width)


def pdisc(name, mat, x, y, radius, width, bevel=0.0, sides=12):
    return disc(name, mat, PU(x), PV(y), radius * KV, width, bevel, sides)


ARMOR_W = 0.72
RISE = 0.05
BORE_Y = 552   # The one barrel (between the picture's two barrels).
# Upper armor segments of the barrel section (picture x, front to back), dark gaps between them.
UPPER_SEGS = [(48, 210), (216, 395), (401, 560)]
# The lower armor runs to the muzzle brake, as long as the barrel (user 2026-11-01), in the upper armor's segments.
LOWER_SEGS = [(50, 210), (216, 395), (401, 560)]
# Left hand places (Godot z): rest, aim (the hand pad; 0.6 m ahead of the Beam Rifle's, user 2026-11-01: "Move the
# left hand a bit more forward when holding the rifle while aiming"), low aim.
LEFT_REST_Z, LEFT_AIM_Z, LEFT_LOW_Z = -5.0835, -4.7835, -2.734


def upper_top(x):
    """Top edge of the upper armor at picture x: level at the front, rising to the receiver."""
    return 476 - 6 * (x - 48) / 357 if x < 405 else (470 if x < 428 else 458)


def build():
    # Barrel: one long thick dark barrel, a heavy muzzle brake (dark block with ports, a grey muzzle ring that
    # flashes orange, a dark bore), grey support collars with dark clamps up to the upper armor.
    ptube("Barrel", D, 70, 700, 15, BORE_Y)
    pchamfer("MuzzleBrake", D, 50, 74, 532, 572, 0.36, 5, bevel=0.012)
    for k in range(3):
        pbox(f"BrakePort{k}", GR, 54 + k * 6.5, 57 + k * 6.5, 540, 564, 0.372, bevel=0.0)
    ptube("MuzzleRing", GR, 45, 51, 19, BORE_Y, bevel=0.005, sides=32)
    ptube("MuzzleBore", D, 43, 46, 10, BORE_Y, bevel=0.0)
    for i, x in enumerate((140, 300, 470)):
        ptube(f"Collar{i}", GR, x, x + 10, 20, BORE_Y, bevel=0.005)
        pbox(f"Clamp{i}", D, x + 1, x + 9, 528, 540, 0.20, bevel=0.006)
    ptube("BarrelBlock", D, 640, 690, 23, BORE_Y)

    # Upper armor (barrel section): three white segments with dark gaps, each with a raised side panel, a grey
    # seam, dots and top vents; a dark vent in the front face; a grey rail along the top.
    pbox("UpperSpine", D, 52, 560, 480, 528, ARMOR_W - 0.08, bevel=0.01)
    for i, (x0, x1) in enumerate(UPPER_SEGS):
        top0, top1 = upper_top(x0), upper_top(x1 - 0.01)
        outline = [(x0, top0), (x1, top1), (x1, 528), (x0, 532)]
        if i == 0:
            outline = [(x0 + 6, top0), (x1, top1), (x1, 528), (x0 + 14, 534), (x0, 528), (x0, top0 + 6)]
        if i == 2:
            outline = [(x0, top0), (405, upper_top(404)), (428, 458), (x1, 456), (x1, 524), (x0, 528)]
        pprism(f"UpperArmor{i}", W, outline, ARMOR_W)
        p0, p1 = x0 + (14 if i == 0 else 8), x1 - 8
        pchamfer(f"UpperPanel{i}", W, p0, p1, max(top0, top1) + 8, 512, ARMOR_W + RISE, 4, bevel=0.012)
        pbox(f"UpperSeam{i}", GR, p0 + 4, p1 - 4, 516, 518, ARMOR_W + 0.012, bevel=0.0)
        for k, x in enumerate((p0 + 10, p1 - 10)):
            ppin(f"UpperDot{i}_{k}", x, 500, (ARMOR_W + RISE) / 2)
        # A grey rail along the top of the segment.
        rail_top = min(top0, top1) if i < 2 else 456
        rx0, rx1 = (x0 + 12, x1 - 12) if i < 2 else (434, x1 - 12)
        pbox(f"TopRail{i}", GR, rx0, rx1, rail_top - 3, rail_top + 1, 0.12, bevel=0.003)
        for k in range(3):
            vx = (x0 + x1) / 2 - 10 + k * 8
            pbox(f"UpperVent{i}_{k}", D, vx, vx + 4, upper_top(vx) - 1.5, upper_top(vx) + 2, 0.30, bevel=0.0)
    pbox("FrontVent", D, 46, 50, 492, 514, 0.34, bevel=0.0)

    # Lower armor (barrel section): two white segments with raised panels and seams; a dark hand pad with bolts
    # under it where the left hand holds when aiming.
    for i, (x0, x1) in enumerate(LOWER_SEGS):
        outline = [(x0, 560), (x1, 558), (x1, 585), (x0, 585)]
        if i == 0:
            outline = [(x0 + 4, 562), (x1, 560), (x1, 585), (x0 + 12, 585), (x0, 576), (x0, 566)]
        pprism(f"LowerArmor{i}", W, outline, ARMOR_W)
        p0, p1 = x0 + (16 if i == 0 else 8), x1 - 8
        pchamfer(f"LowerPanel{i}", W, p0, p1, 566, 580, ARMOR_W + RISE, 3, bevel=0.01)
        ppin(f"LowerDot{i}", p1 - 8, 573, (ARMOR_W + RISE) / 2)
    pbox("LowerSpine", D, 54, 560, 560, 580, ARMOR_W - 0.08, bevel=0.008)
    pad_x = XZ(LEFT_AIM_Z)
    pbox("HandPad", D, pad_x - 14, pad_x + 14, 582, 590, 0.46, bevel=0.01)
    for k, x in enumerate((pad_x - 9, pad_x + 9)):
        pdisc(f"PadBolt{k}", GR, x, 586, 3.0, 0.47)

    # Receiver: dark body, a white band with a raised panel, a raised plate under the sight, a white lower plate
    # with a hex panel, a dark power cell on the side with an amber lamp strip, vents and bolts.
    pbox("Receiver", D, 560, 1000, 470, 592, 0.52)
    pprism("UpperBand", W, [(560, 456), (640, 456), (660, 470), (860, 470), (880, 488), (880, 504), (600, 504),
                            (560, 524)], 0.60)
    pprism("BandPanel", W, [(575, 466), (640, 466), (656, 478), (850, 478), (864, 490), (864, 498), (600, 498),
                            (575, 512)], 0.65, bevel=0.01)
    pbox("BandSeam", GR, 600, 870, 506, 508, 0.612, bevel=0.0)
    pbox("SightBase", W, 640, 800, 450, 471, 0.44)
    pprism("LowerPlate", W, [(560, 558), (700, 558), (755, 530), (862, 530), (876, 540), (876, 552), (862, 560),
                             (780, 560), (742, 585), (560, 585)], 0.60)
    pprism("HexPanel", W, [(780, 534), (858, 534), (868, 541), (868, 551), (858, 557), (780, 557)], 0.65, bevel=0.008)
    ppin("HexDot", 850, 545, 0.325)
    pchamfer("PowerCell", D, 600, 690, 512, 548, 0.70, 3, bevel=0.01)
    pbox("CellLamp", A, 610, 680, 527, 532, 0.712, bevel=0.0)
    for k, x in enumerate((606, 684)):
        pdisc(f"CellBolt{k}", GR, x, 518, 2.5, 0.71)
    for k in range(4):
        x = 705 + k * 9
        pbox(f"ReceiverVent{k}", GR, x, x + 4, 512, 524, 0.532, bevel=0.0)

    # Top sight: white box with a dark top and an amber lens (glows), a dark rear cap.
    pprism("Sight", W, [(668, 438), (774, 438), (784, 448), (784, 470), (668, 470)], 0.34)
    pbox("SightTop", D, 688, 726, 422, 440, 0.22, bevel=0.008)
    pbox("SightLens", A, 683, 689, 425, 437, 0.17, bevel=0.0)
    pbox("SightCap", D, 772, 790, 442, 466, 0.26, bevel=0.006)

    # Rear scope: a dark tube with grey rings on a dark mount, the glass at its front, side knobs.
    ptube("Scope", D, 846, 914, 15, 464)
    for i, x in enumerate((858, 882, 900)):
        ptube(f"ScopeRing{i}", GR, x, x + 7, 17, 464, bevel=0.004)
    ptube("ScopeGlass", G, 842, 847, 10, 464, bevel=0.0)
    pbox("ScopeMount", D, 860, 904, 476, 492, 0.24)

    # Stock: dark block with grey vents, white Y top member with a raised panel and a dark hole, a white cheek
    # plate, white lower brace, a thick dark butt pad with grey ribs.
    pbox("StockBlock", D, 900, 1042, 478, 594, 0.46)
    for k in range(4):
        x = 920 + k * 14
        pbox(f"StockVent{k}", GR, x, x + 6, 522, 572, 0.472, bevel=0.0)
    pprism("StockTop", W, [(900, 478), (990, 478), (1022, 442), (1064, 442), (1064, 470), (1032, 470),
                           (1000, 506), (900, 506)], 0.42)
    pprism("StockPanel", W, [(912, 484), (985, 484), (1012, 452), (1054, 452), (1054, 464), (1026, 464),
                             (996, 500), (912, 500)], 0.47, bevel=0.008)
    pbox("StockHole", D, 1032, 1054, 448, 462, 0.43, bevel=0.0)
    pprism("StockBrace", W, [(950, 592), (995, 592), (1042, 614), (1042, 632), (1014, 632)], 0.42)
    pprism("ButtPad", D, [(1042, 442), (1074, 442), (1082, 452), (1082, 626), (1074, 636), (1042, 636)], 0.58)
    for k in range(7):
        y = 462 + k * 24
        pbox(f"PadRib{k}", GR, 1050, 1076, y, y + 4, 0.592, bevel=0.0)

    # Pistol grip (the first Beam Rifle's place and size): white body, dark side panels, dark base,
    # trigger slot on both sides.
    tilt = 24.0
    slanted("Grip", W, 1338, 370, 172, 92, 0.24, tilt)
    for side, sx in (("L", 0.125), ("R", -0.125)):
        slanted(f"GripPanel{side}", D, 1366, 384, 110, 40, 0.02, tilt, sx, bevel=0.006)
        slanted(f"TriggerSlot{side}", D, 1312, 316, 34, 22, 0.02, tilt + 6, sx, bevel=0.006)
    slanted("GripBase", D, 1374, 448, 28, 108, 0.30, tilt)

    # Markers.
    empty("GripRight", 1340, 368)
    empty("GripLeft", PU(XZ(LEFT_REST_Z)), PV(592))
    empty("Muzzle", PU(43), PV(BORE_Y))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle_4.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "beam_rifle_4.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("beam_rifle_4: %d objects, %d triangles, KR %.3f KF %.3f" % (len(bpy.data.objects), tris, KR, KF))
    for name in ("Muzzle", "GripRight", "GripLeft"):
        o = bpy.data.objects[name]
        print("marker %s godot (%.4f, %.4f, %.4f)" % (name, o.location.x, o.location.z, -o.location.y))
    from mathutils import Vector
    for prefix in ("LowerArmor0", "LowerArmor1", "HandPad", "LowerPlate"):
        obj = bpy.data.objects[prefix]
        print("%s bottom z %.4f" % (prefix, min((obj.matrix_world @ Vector(c)).z for c in obj.bound_box)))
    ys = [(o.matrix_world @ Vector(c)).y for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    print("length %.3f m (y %.3f to %.3f)" % (max(ys) - min(ys), min(ys), max(ys)))


main()
