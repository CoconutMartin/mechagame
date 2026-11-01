"""Builds Beam Rifle 4 (two-hand sniper beam rifle, 7 m long, one barrel) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_4_build.py
Writes models/beam_rifle_4/beam_rifle_4.blend and beam_rifle_4.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

From the user's picture models/guides/beam_rifle_4_ref.png (two side views, front, back, top, bottom). Traced
from the level side view (the second picture, x 48 muzzle to 1080 butt). User request 2026-11-01: "make the
barrel part longer, total length 7 meters. One barrel only" (the picture has two barrels).

Picture pixels (x, y) go to the first Beam Rifle's frame (u, v) by PU and PV: the receiver and stock (x 560
and back) at KR frame pixels per picture pixel, with the pistol grip on the first Beam Rifle's grip (frame 1338,
370) and the butt at the frame origin (u 1728); the barrel section (x 48 to 560) stretched to KF so the rifle is
7 m long. The lower armor and the hand pad sit lower than the Beam Rifle's rail: the scene's left hand markers
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
KR = 390 / (1080 - GRIP_X)     # Frame pixels per picture pixel, receiver and stock (butt at frame 1728).
U_SPLIT = 1338 + (SPLIT_X - GRIP_X) * KR
MUZZLE_U = 1728 - 7.0 / SCALE  # 7 m from the butt to the muzzle.
KF = (U_SPLIT - MUZZLE_U) / (SPLIT_X - 48)


def PU(x):
    if x >= SPLIT_X:
        return 1338 + (x - GRIP_X) * KR
    return U_SPLIT - (SPLIT_X - x) * KF


def PV(y):
    return 370 + (y - GRIP_Y) * KR


def pic(outline):
    return [(PU(x), PV(y)) for x, y in outline]


def pbox(name, mat, x0, x1, y0, y1, width, x=0.0, bevel=BEVEL):
    return box(name, mat, PU(x0), PU(x1), PV(y0), PV(y1), width, x, bevel)


def pprism(name, mat, outline, width, x=0.0, bevel=BEVEL):
    return prism(name, mat, pic(outline), width, x, bevel)


def ptube(name, mat, x0, x1, radius, y, bevel=0.01, sides=24):
    return tube(name, mat, PU(x0), PU(x1), radius * KR, PV(y), 0.0, bevel, sides)


def ppin(name, x, y, half_width):
    return pin(name, PU(x), PV(y), half_width)


def pdisc(name, mat, x, y, radius, width, bevel=0.0, sides=12):
    return disc(name, mat, PU(x), PV(y), radius * KR, width, bevel, sides)


ARMOR_W = 0.56
BORE_Y = 552   # The one barrel (between the picture's two barrels).


def build():
    # Barrel: one long dark tube with two grey collars, a grey muzzle ring (flashes orange at a shot) and a
    # dark bore; it runs back into the receiver.
    ptube("Barrel", D, 56, 700, 13, BORE_Y)
    ptube("MuzzleRing", GR, 48, 60, 17, BORE_Y, bevel=0.005, sides=32)
    ptube("MuzzleBore", D, 45, 49, 9, BORE_Y, bevel=0.0)
    for i, (x0, x1) in enumerate(((205, 228), (515, 540))):
        ptube(f"Collar{i}", GR, x0, x1, 17, BORE_Y, bevel=0.005)
    ptube("BarrelBlock", D, 640, 690, 21, BORE_Y)

    # Upper armor (barrel section): a long white plate, deeper toward the receiver, a dark vent in its front
    # face and a dark slot on top near the front, a grey seam along the side, dots.
    pprism("UpperArmor", W, [(48, 476), (405, 470), (428, 458), (560, 456), (560, 524), (70, 534), (48, 530)],
           ARMOR_W)
    pbox("FrontVent", D, 46, 52, 492, 514, 0.30, bevel=0.0)
    pbox("TopSlot", D, 75, 130, 469, 476, 0.22, bevel=0.0)
    pbox("UpperSeam", GR, 60, 556, 515, 517.5, ARMOR_W + 0.012, bevel=0.0)
    pprism("UpperPanel", W, [(80, 484), (400, 478), (420, 468), (540, 466), (540, 508), (80, 512)], ARMOR_W + 0.05,
           bevel=0.012)
    ppin("UpperDot0", 520, 490, (ARMOR_W + 0.05) / 2)
    ppin("UpperDot1", 100, 498, (ARMOR_W + 0.05) / 2)

    # Lower armor (barrel section): a long white plate with a slanted nose, a seam, and a dark hand pad under it
    # with two bolts, where the left hand holds when aiming.
    pprism("LowerArmor", W, [(110, 562), (560, 558), (560, 585), (125, 585), (100, 575)], ARMOR_W)
    pbox("LowerSeam", GR, 130, 556, 566, 568.5, ARMOR_W + 0.012, bevel=0.0)
    pprism("LowerPanel", W, [(140, 566), (540, 563), (540, 580), (150, 580)], ARMOR_W + 0.05, bevel=0.01)
    pbox("HandPad", D, 410, 480, 582, 590, 0.42, bevel=0.01)
    for k, x in enumerate((420, 470)):
        pdisc(f"PadBolt{k}", GR, x, 586, 3.5, 0.43)
    pbox("BarrelSpine", D, 300, 560, 524, 560, 0.30, bevel=0.008)

    # Receiver: dark body, a white band with a slanted back over it, a raised white plate under the sight, a
    # white lower plate that rises to a hex panel with a dot.
    pbox("Receiver", D, 560, 1000, 470, 590, 0.46)
    pprism("UpperBand", W, [(560, 456), (640, 456), (660, 470), (860, 470), (880, 488), (880, 504), (600, 504),
                            (560, 524)], 0.54)
    pbox("BandSeam", GR, 600, 870, 506, 508.5, 0.552, bevel=0.0)
    pbox("SightBase", W, 640, 800, 452, 471, 0.40)
    pprism("LowerPlate", W, [(560, 558), (700, 558), (755, 530), (862, 530), (876, 540), (876, 552), (862, 560),
                             (780, 560), (742, 585), (560, 585)], 0.54)
    pprism("HexPanel", W, [(780, 534), (858, 534), (868, 541), (868, 551), (858, 557), (780, 557)], 0.58, bevel=0.008)
    ppin("HexDot", 850, 545, 0.29)
    pbox("ReceiverSlot", GR, 700, 840, 512, 522, 0.47, bevel=0.0)
    for k in range(4):
        x = 920 + k * 14
        pbox(f"StockVent{k}", GR, x, x + 6, 520, 570, 0.412, bevel=0.0)

    # Top sight: white box with a dark top and an amber lens (glows), a dark rear cap.
    pprism("Sight", W, [(668, 452), (772, 452), (782, 440), (782, 470), (668, 470)], 0.30)
    pbox("SightTop", D, 688, 726, 424, 442, 0.20, bevel=0.008)
    pbox("SightLens", A, 683, 689, 427, 439, 0.15, bevel=0.0)
    pbox("SightCap", D, 772, 790, 444, 466, 0.24, bevel=0.006)

    # Rear scope: a dark tube with grey rings on a dark mount, the glass at its front.
    ptube("Scope", D, 850, 912, 15, 466)
    for i, x in enumerate((860, 882)):
        ptube(f"ScopeRing{i}", GR, x, x + 8, 17, 466, bevel=0.004)
    ptube("ScopeGlass", G, 846, 851, 10, 466, bevel=0.0)
    pbox("ScopeMount", D, 862, 902, 478, 492, 0.20)

    # Stock: dark block, white Y top member with a dark hole, white lower brace, dark butt pad with grey ribs.
    pbox("StockBlock", D, 900, 1042, 478, 592, 0.40)
    pprism("StockTop", W, [(900, 478), (990, 478), (1022, 444), (1062, 444), (1062, 470), (1032, 470),
                           (1000, 504), (900, 504)], 0.36)
    pprism("StockPanel", W, [(912, 484), (985, 484), (1012, 452), (1052, 452), (1052, 464), (1026, 464),
                             (996, 498), (912, 498)], 0.40, bevel=0.008)
    pbox("StockHole", D, 1030, 1052, 450, 462, 0.37, bevel=0.0)
    pprism("StockBrace", W, [(955, 590), (995, 590), (1042, 612), (1042, 628), (1018, 628)], 0.36)
    pprism("ButtPad", D, [(1042, 446), (1074, 446), (1080, 454), (1080, 622), (1074, 630), (1042, 630)], 0.50)
    for k in range(6):
        y = 470 + k * 24
        pbox(f"PadRib{k}", GR, 1050, 1074, y, y + 4, 0.512, bevel=0.0)

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
    empty("GripLeft", PU(300), PV(592))
    empty("Muzzle", PU(45), PV(BORE_Y))


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
    for prefix in ("LowerArmor", "HandPad", "LowerPlate"):
        obj = bpy.data.objects[prefix]
        print("%s bottom z %.4f" % (prefix, min((obj.matrix_world @ Vector(c)).z for c in obj.bound_box)))
    ys = [(o.matrix_world @ Vector(c)).y for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    print("length %.3f m (y %.3f to %.3f)" % (max(ys) - min(ys), min(ys), max(ys)))


main()
