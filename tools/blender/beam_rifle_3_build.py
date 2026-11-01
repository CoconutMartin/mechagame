"""Builds Beam Rifle 3 (two-hand charged beam cannon, about 6.3 m long) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_3_build.py
Writes models/beam_rifle_3/beam_rifle_3.blend and beam_rifle_3.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

From the user's picture models/guides/beam_rifle_3_ref.png (side, front, back, 3/4, top and bottom
views): white armor plates above and below an open barrel with 7 rings (2 orange, 5 black), a heavy
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
}
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


ARMOR_W = 0.60


def build():
    # Barrel: heavy dark muzzle cap with a dark bore, a dark tube, an open core with 7 rings.
    ptube("MuzzleCap", D, 105, 150, 38, sides=32)
    ptube("MuzzleBore", D, 101, 106, 17, bevel=0.0)
    ptube("MuzzleTube", D, 150, 242, 30)
    ptube("BarrelCore", GR, 242, 645, 27)
    for i, x in enumerate((255, 305)):
        ptube(f"OrangeRing{i}", O, x, x + 27, 58, sides=32)
    for i, x in enumerate((365, 420, 475, 530, 585)):
        ptube(f"BlackRing{i}", D, x, x + 20, 54, sides=32)

    # Prongs above and below the barrel at the front: grey rods with round tips (glow red on a shot).
    for name, y in (("Top", 122), ("Bottom", 288)):
        ptube(f"Prong{name}", GR, 172, 240, 9, y, sides=16)
        ptube(f"ProngTip{name}", GR, 160, 174, 15, y, bevel=0.006, sides=16)

    # Upper armor: long front plate over the open barrel, a second plate behind it, a top plate.
    pprism("UpperArmor", W, [(235, 88), (652, 88), (670, 104), (670, 134), (242, 134), (235, 126)], ARMOR_W)
    pbox("UpperRail", D, 242, 650, 132, 146, ARMOR_W - 0.08, bevel=0.008)
    pprism("UpperArmor2", W, [(615, 150), (640, 128), (985, 128), (1000, 140), (1000, 166), (985, 170),
                               (640, 170)], ARMOR_W - 0.02)
    pprism("TopPlate", W, [(750, 104), (768, 94), (935, 94), (950, 106), (950, 126), (750, 126)], 0.50)
    ppin("UpperDot0", 258, 100, ARMOR_W / 2)
    ppin("UpperDot1", 648, 117, ARMOR_W / 2)
    ppin("UpperDot2", 975, 150, (ARMOR_W - 0.02) / 2)

    # Lower armor: front plate, a dark gap, a rear plate with a slanted front, and the slanted plate
    # above them. Its bottom (y 305) is where the left hand holds; nothing hangs below it.
    pprism("LowerArmor", W, [(235, 262), (700, 262), (700, 305), (242, 305), (235, 297)], ARMOR_W)
    pbox("LowerRail", D, 242, 650, 248, 264, ARMOR_W - 0.08, bevel=0.008)
    pbox("LowerGap", D, 690, 770, 262, 302, ARMOR_W - 0.06, bevel=0.008)
    pprism("LowerArmor2", W, [(762, 262), (975, 262), (990, 275), (990, 295), (975, 305), (738, 305)], ARMOR_W)
    pprism("SidePlate", W, [(620, 256), (660, 216), (985, 216), (1000, 228), (1000, 246), (985, 256)],
           ARMOR_W - 0.02)
    ppin("LowerDot0", 272, 293, ARMOR_W / 2)
    ppin("LowerDot1", 690, 230, (ARMOR_W - 0.02) / 2)

    # Receiver: dark body, a grey slide, the stock block behind, a white hex plate with two dots.
    pbox("Receiver", D, 630, 1150, 100, 302, 0.50)
    pbox("Slide", GR, 800, 1030, 178, 208, 0.54, bevel=0.008)
    pbox("SlideSlot", D, 840, 1000, 186, 200, 0.56, bevel=0.0)
    pbox("StockBlock", D, 1140, 1245, 135, 245, 0.42)
    pbox("StockStep", D, 1150, 1215, 125, 140, 0.36, bevel=0.008)
    hex_ = [(995, 232), (1015, 215), (1080, 215), (1098, 232), (1098, 263), (1080, 280), (1015, 280), (995, 263)]
    pprism("HexPlate", W, hex_, 0.62)
    ppin("HexDot0", 1016, 232, 0.315)
    ppin("HexDot1", 1078, 263, 0.315)

    # Scope: white body on a dark mount, a dark lens tube with glass in front, a back knob, a dark
    # sight with glass on top.
    pbox("ScopeMount", D, 1005, 1100, 104, 128, 0.26)
    pprism("Scope", W, [(992, 48), (1108, 48), (1118, 58), (1118, 102), (1108, 112), (1000, 112), (992, 104)], 0.38)
    ptube("ScopeLens", D, 940, 995, 22, 72)
    ptube("ScopeLensRing", W, 952, 980, 25, 72, bevel=0.006)
    ptube("ScopeGlass", G, 936, 942, 14, 72, bevel=0.0)
    ptube("ScopeKnob", D, 1116, 1128, 17, 76)
    pbox("Sight", D, 1004, 1062, 12, 48, 0.22, bevel=0.01)
    pbox("SightGlass", G, 1000, 1006, 20, 36, 0.16, bevel=0.0)

    # Stock: white butt with slanted front edges, a dark pad with a grey inner panel.
    pprism("Butt", W, [(1240, 132), (1286, 80), (1335, 80), (1335, 352), (1308, 352), (1240, 252)], 0.56)
    pprism("ButtPad", D, [(1322, 76), (1415, 76), (1428, 90), (1428, 342), (1415, 356), (1322, 356)], 0.60)
    pbox("ButtPadPanel", GR, 1345, 1405, 108, 328, 0.612, bevel=0.006)

    # Pistol grip (the first Beam Rifle's place and size, dark): grey side panels, dark base,
    # trigger slot on both sides.
    tilt = 24.0
    slanted("Grip", D, 1338, 370, 172, 92, 0.24, tilt)
    for side, sx in (("L", 0.125), ("R", -0.125)):
        slanted(f"GripPanel{side}", GR, 1366, 384, 110, 40, 0.02, tilt, sx, bevel=0.006)
        slanted(f"TriggerSlot{side}", GR, 1312, 316, 34, 22, 0.02, tilt + 6, sx, bevel=0.006)
    slanted("GripBase", D, 1374, 448, 28, 108, 0.30, tilt)

    # Glow mesh names for the weapon scene: rings back to front.
    rings = [f"BlackRing{i}" for i in range(4, -1, -1)] + ["OrangeRing1", "OrangeRing0"]
    for i, name in enumerate(rings):
        bpy.data.objects[name].name = f"Ring{i}"

    # Markers.
    empty("GripRight", 1340, 368)
    empty("GripLeft", PU(400), PV(318))
    empty("Muzzle", PU(101), BORE_PX)


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
