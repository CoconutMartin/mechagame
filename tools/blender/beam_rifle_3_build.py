"""Builds Beam Rifle 3 (two-hand charged beam cannon, about 6.3 m long) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_3_build.py
Writes models/beam_rifle_3/beam_rifle_3.blend and beam_rifle_3.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

From the user's picture models/guides/beam_rifle_3_ref.png (side, front, back, 3/4, top and bottom
views): white armor plates above and below an open barrel with 7 rings (user 2026-11-01: all the same,
grey at rest, glowing orange when ready), a heavy
muzzle cap, two prongs at the front (above and below the barrel; they glow red when it fires), a dark
receiver with a hex plate, a scope with a sight on top, a big stock with a dark pad, a dark grip.

Picture pixels (x, y) go to the first Beam Rifle's frame (u, v) by PU and PV: the same scale
(0.934 frame pixels per picture pixel), the pistol grip on the first Beam Rifle's grip (frame
1338, 370), the bore on the frame bore row 241. So the right hand markers and the grip socket of the
Beam Rifle fit. The lower armor is deeper than the Beam Rifle's rail: the left hand markers go down
by LEFT_DROP (the scene).

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = left side of the gun.
Origin: the first Beam Rifle's butt place (frame u 1728), on the bore axis.
Empties: GripRight, GripLeft, Muzzle (the barrel front, where the bolt leaves).
Glow meshes for the weapon scene: Ring0..Ring6 (back to front), ProngTipTop, ProngTipBottom.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "beam_rifle_3")

# The first Beam Rifle's picture frame: muzzle at pixel 492, butt at 1728 (6 m), bore row 241.
MUZZLE_PX, BUTT_PX, BORE_PX = 492, 1728, 241
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
BEVEL = 0.018

# name: (base color, roughness, metallic, emission strength). Colors from the picture.
MATERIALS = {
    "beam_rifle_3_white": ((0.78, 0.77, 0.75), 0.5, 0.0, 0.0),
    "beam_rifle_3_dark": ((0.03, 0.032, 0.036), 0.5, 0.3, 0.0),
    "beam_rifle_3_grey": ((0.11, 0.115, 0.125), 0.45, 0.4, 0.0),
    "beam_rifle_3_orange": ((1.0, 0.36, 0.04), 0.35, 0.0, 0.0),
    "beam_rifle_3_glass": ((0.25, 0.42, 0.45), 0.08, 0.0, 0.0),
    # Barrel rings: grey at rest (the weapon script makes them glow orange when ready).
    "beam_rifle_3_ring": ((0.32, 0.31, 0.3), 0.4, 0.3, 0.0),
}
R = "beam_rifle_3_ring"
W, D, GR, O, G = ("beam_rifle_3_white", "beam_rifle_3_dark", "beam_rifle_3_grey", "beam_rifle_3_orange",
                  "beam_rifle_3_glass")


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


K = 0.934  # Frame pixels per picture pixel.


def PU(x):
    return 1338 + (x - 1085) * K


def PV(y):
    return BORE_PX + (y - 205) * K


def pic(outline):
    return [(PU(x), PV(y)) for x, y in outline]


def pbox(name, mat, x0, x1, y0, y1, width, x=0.0, bevel=BEVEL):
    return box(name, mat, PU(x0), PU(x1), PV(y0), PV(y1), width, x, bevel)


def pprism(name, mat, outline, width, x=0.0, bevel=BEVEL):
    return prism(name, mat, pic(outline), width, x, bevel)


def ptube(name, mat, x0, x1, radius, y=205, bevel=0.01, sides=24):
    return tube(name, mat, PU(x0), PU(x1), radius * K, PV(y), 0.0, bevel, sides)


def ppin(name, x, y, half_width):
    return pin(name, PU(x), PV(y), half_width)


def pchamfer(name, mat, x0, x1, y0, y1, width, cut, bevel=BEVEL):
    return chamfer_box(name, mat, PU(x0), PU(x1), PV(y0), PV(y1), width, cut * K, 0.0, bevel)


def pdisc(name, mat, x, y, radius, width, bevel=0.0, sides=12):
    return disc(name, mat, PU(x), PV(y), radius * K, width, bevel, sides)


ARMOR_W = 0.60
# Raised side panels: this much wider than the plate under them (both sides together).
RISE = 0.05


def build():
    # Barrel: heavy muzzle cap (dark, a grey band, a flared lip, vent slots), a dark tube, an open core
    # with a ribbed grey sleeve and 7 rings, all the same size and color (grey at rest, glow orange).
    ptube("MuzzleLip", D, 98, 112, 41, sides=32)
    ptube("MuzzleCap", D, 112, 150, 37, sides=32)
    ptube("MuzzleBand", GR, 126, 136, 39, sides=32, bevel=0.004)
    ptube("MuzzleBore", D, 95, 99, 19, bevel=0.0)
    ptube("MuzzleBoreRing", O, 96, 99, 25, bevel=0.0, sides=32)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        ptube(f"MuzzleVent{k}", D, 116, 124, 6, 205, bevel=0.0, sides=8)
        obj = bpy.data.objects[f"MuzzleVent{k}"]
        obj.location.x += math.cos(a) * P(37 * K)
        obj.location.z += math.sin(a) * P(37 * K)
    ptube("MuzzleTube", D, 150, 242, 30)
    ptube("MuzzleCollar", GR, 150, 164, 33, bevel=0.004)
    ptube("BarrelCore", GR, 242, 645, 26)
    for k in range(12):
        x = 252 + k * 32
        ptube(f"CoreRib{k}", D, x, x + 6, 30, bevel=0.0, sides=20)
    ring_xs = (258, 312, 366, 420, 474, 528, 582)
    for i, x in enumerate(ring_xs):
        ptube(f"RingBody{i}", R, x, x + 24, 56, sides=32, bevel=0.012)

    # Prongs: grey rods with collars and round tips (glow red on a shot), held by dark brackets.
    for name, y in (("Top", 122), ("Bottom", 288)):
        ptube(f"Prong{name}", GR, 172, 240, 9, y, sides=16)
        ptube(f"ProngCollar{name}", D, 196, 210, 13, y, bevel=0.004, sides=16)
        ptube(f"ProngTip{name}", GR, 158, 174, 15, y, bevel=0.006, sides=20)
        pbox(f"ProngBracket{name}", D, 222, 248, y - 16, y + 16, 0.22, bevel=0.008)

    # Upper armor: long front plate with a chamfered nose, a raised side panel with a seam and dots, a
    # dark rail under it; a second plate and a top plate behind, with raised panels and vents.
    pprism("UpperArmor", W, [(244, 88), (652, 88), (670, 104), (670, 134), (242, 134), (232, 124), (232, 100)], ARMOR_W)
    pchamfer("UpperPanel", W, 262, 640, 97, 126, ARMOR_W + RISE, 6, bevel=0.012)
    pbox("UpperSeam", GR, 270, 632, 128, 130.5, ARMOR_W + 0.012, bevel=0.0)
    pbox("UpperRail", D, 242, 650, 132, 146, ARMOR_W - 0.08, bevel=0.008)
    for k in range(4):
        x = 330 + k * 16
        pbox(f"UpperVent{k}", D, x, x + 8, 86, 91, 0.30, bevel=0.0)
    pprism("UpperArmor2", W, [(615, 150), (640, 128), (985, 128), (1000, 140), (1000, 166), (985, 170),
                               (640, 170)], ARMOR_W - 0.02)
    pprism("UpperPanel2", W, [(660, 158), (676, 136), (975, 136), (985, 144), (985, 162)],
           ARMOR_W - 0.02 + RISE, bevel=0.01)
    pprism("TopPlate", W, [(750, 104), (768, 94), (935, 94), (950, 106), (950, 126), (750, 126)], 0.50)
    for k in range(3):
        x = 790 + k * 16
        pbox(f"TopVent{k}", D, x, x + 8, 92, 97, 0.26, bevel=0.0)
    ppin("UpperDot0", 285, 111, (ARMOR_W + RISE) / 2)
    ppin("UpperDot1", 615, 111, (ARMOR_W + RISE) / 2)
    ppin("UpperDot2", 960, 150, (ARMOR_W - 0.02 + RISE) / 2)

    # Lower armor: front plate with a chamfered nose and a raised panel, a dark gap with a grey bolt, a
    # rear plate with a slanted front, and the slanted side plate above them with a dark inset and an
    # orange lamp. Its bottom (y 305) is where the left hand holds; nothing hangs below it.
    pprism("LowerArmor", W, [(242, 262), (700, 262), (700, 305), (244, 305), (232, 295), (232, 272)], ARMOR_W)
    pchamfer("LowerPanel", W, 262, 680, 272, 296, ARMOR_W + RISE, 6, bevel=0.012)
    pbox("LowerSeam", GR, 270, 672, 268, 270.5, ARMOR_W + 0.012, bevel=0.0)
    pbox("LowerRail", D, 242, 650, 248, 264, ARMOR_W - 0.08, bevel=0.008)
    pbox("LowerGap", D, 690, 770, 262, 302, ARMOR_W - 0.06, bevel=0.008)
    pdisc("GapBolt", GR, 728, 283, 7, ARMOR_W - 0.04)
    pprism("LowerArmor2", W, [(762, 262), (975, 262), (990, 275), (990, 295), (975, 305), (738, 305)], ARMOR_W)
    pprism("LowerPanel2", W, [(774, 270), (968, 270), (978, 278), (978, 292), (970, 298), (758, 298)],
           ARMOR_W + RISE, bevel=0.01)
    pprism("SidePlate", W, [(620, 256), (660, 216), (985, 216), (1000, 228), (1000, 246), (985, 256)],
           ARMOR_W - 0.02)
    pprism("SideInset", D, [(672, 246), (692, 226), (850, 226), (850, 246)], ARMOR_W - 0.02 + 0.012, bevel=0.0)
    pbox("SideLamp", O, 860, 900, 232, 240, ARMOR_W - 0.02 + 0.014, bevel=0.0)
    ppin("LowerDot0", 290, 284, (ARMOR_W + RISE) / 2)
    ppin("LowerDot1", 655, 284, (ARMOR_W + RISE) / 2)
    ppin("LowerDot2", 960, 236, (ARMOR_W - 0.02) / 2)

    # Receiver: dark body with grey vent slats, a grey slide with a slot, the stock block behind, a
    # white hex plate with a raised inner hex and four bolts.
    pbox("Receiver", D, 630, 1150, 100, 302, 0.50)
    pbox("Slide", GR, 800, 1030, 178, 208, 0.54, bevel=0.008)
    pbox("SlideSlot", D, 840, 1000, 186, 200, 0.56, bevel=0.0)
    for k in range(4):
        x = 1100 + k * 12
        pbox(f"ReceiverVent{k}", GR, x, x + 5, 180, 230, 0.512, bevel=0.0)
    pbox("StockBlock", D, 1140, 1245, 135, 245, 0.42)
    pbox("StockStep", D, 1150, 1215, 125, 140, 0.36, bevel=0.008)
    for k in range(3):
        y = 160 + k * 26
        pbox(f"StockRib{k}", GR, 1160, 1232, y, y + 6, 0.432, bevel=0.0)
    hex_ = [(995, 232), (1015, 215), (1080, 215), (1098, 232), (1098, 263), (1080, 280), (1015, 280), (995, 263)]
    pprism("HexPlate", W, hex_, 0.62)
    inner = [(1012, 236), (1024, 225), (1071, 225), (1082, 236), (1082, 259), (1071, 270), (1024, 270), (1012, 259)]
    pprism("HexInner", W, inner, 0.66, bevel=0.01)
    pprism("HexCore", D, [(1035, 240), (1062, 240), (1062, 255), (1035, 255)], 0.672, bevel=0.0)
    for k, (x, y) in enumerate(((1006, 230), (1088, 230), (1006, 265), (1088, 265))):
        pdisc(f"HexBolt{k}", GR, x, y, 4.5, 0.64)

    # Scope: white body with a raised side panel on a dark mount and grey rail, a dark lens hood with a
    # white ring and glass, side knobs, a back knob, a dark sight with glass on top.
    pbox("ScopeRail", GR, 995, 1110, 120, 130, 0.18, bevel=0.004)
    pbox("ScopeMount", D, 1005, 1100, 104, 124, 0.26)
    pprism("Scope", W, [(992, 48), (1108, 48), (1118, 58), (1118, 102), (1108, 112), (1000, 112), (992, 104)], 0.38)
    pchamfer("ScopePanel", W, 1010, 1100, 60, 98, 0.42, 6, bevel=0.008)
    ptube("ScopeHood", D, 930, 995, 23, 72)
    ptube("ScopeLensRing", W, 950, 978, 26, 72, bevel=0.006)
    ptube("ScopeGlass", G, 926, 932, 15, 72, bevel=0.0)
    ptube("ScopeKnob", D, 1116, 1128, 17, 76)
    for side, sx in (("L", 1), ("R", -1)):
        obj = ptube(f"ScopeSideKnob{side}", GR, 1045, 1065, 9, 80, bevel=0.003, sides=12)
        obj.location.x += sx * 0.22
    pbox("Sight", D, 1004, 1062, 12, 48, 0.22, bevel=0.01)
    pbox("SightGlass", G, 1000, 1006, 20, 36, 0.16, bevel=0.0)

    # Stock: white butt with slanted front edges and a raised panel, a dark pad with a grey inner panel
    # and grooves.
    pprism("Butt", W, [(1240, 132), (1286, 80), (1335, 80), (1335, 352), (1308, 352), (1240, 252)], 0.56)
    pprism("ButtPanel", W, [(1258, 140), (1292, 100), (1322, 100), (1322, 330), (1312, 330), (1258, 245)],
           0.56 + RISE, bevel=0.01)
    ppin("ButtDot", 1305, 290, (0.56 + RISE) / 2)
    pprism("ButtPad", D, [(1322, 76), (1415, 76), (1428, 90), (1428, 342), (1415, 356), (1322, 356)], 0.60)
    pbox("ButtPadPanel", GR, 1345, 1405, 108, 328, 0.612, bevel=0.006)
    for k in range(6):
        y = 130 + k * 34
        pbox(f"PadGroove{k}", D, 1352, 1398, y, y + 5, 0.62, bevel=0.0)

    # Pistol grip (the first Beam Rifle's place and size, dark): grey side panels, dark base,
    # trigger slot on both sides.
    tilt = 24.0
    slanted("Grip", D, 1338, 370, 172, 92, 0.24, tilt)
    for side, sx in (("L", 0.125), ("R", -0.125)):
        slanted(f"GripPanel{side}", GR, 1366, 384, 110, 40, 0.02, tilt, sx, bevel=0.006)
        slanted(f"TriggerSlot{side}", GR, 1312, 316, 34, 22, 0.02, tilt + 6, sx, bevel=0.006)
    slanted("GripBase", D, 1374, 448, 28, 108, 0.30, tilt)

    # Glow mesh names for the weapon scene: rings back to front.
    for i in range(len(ring_xs)):
        bpy.data.objects[f"RingBody{len(ring_xs) - 1 - i}"].name = f"Ring{i}"

    # Markers.
    empty("GripRight", 1340, 368)
    empty("GripLeft", PU(400), PV(318))
    empty("Muzzle", PU(95), BORE_PX)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle_3.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "beam_rifle_3.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("beam_rifle_3: %d objects, %d triangles" % (len(bpy.data.objects), tris))
    for name in ("Muzzle", "GripRight", "GripLeft"):
        o = bpy.data.objects[name]
        print("marker %s godot (%.4f, %.4f, %.4f)" % (name, o.location.x, o.location.z, -o.location.y))
    lo = min((obj.matrix_world @ __import__("mathutils").Vector(c)).z for obj in bpy.data.objects
             if obj.type == "MESH" and obj.name.startswith("LowerArmor") for c in obj.bound_box)
    print("lower armor bottom z %.4f" % lo)


main()
