"""Builds the Beam Rifle (two-hand weapon, 6 m long) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_build.py
Writes models/beam_rifle/beam_rifle.blend and models/beam_rifle/beam_rifle.glb. The script starts
from an empty file, so hand edits in the .blend are lost when it runs again.

Traced from the user's picture, models/guides/beam_rifle_ref.png. Side view: muzzle at pixel x 492,
butt at 1728 (6 m, so one pixel = SCALE m), bore axis at pixel row 241. The front and 3/4 views give
the widths (user approved: top view from the 3/4 view, 3/4 view scope with twin lenses, lower rail
is the mirror of the upper rail, simple stock back, no dark blocks under the barrel).

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = left side of the gun (Godot +X after export).
Origin: butt plate back face, on the bore axis (like the other weapon scenes).
Empties (Marker3D in Godot): GripRight (pistol grip), GripLeft, GripLeftRest and GripLeftAim (under
the barrel, neutral hold), Muzzle.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "beam_rifle")

MUZZLE_PX, BUTT_PX, BORE_PX = 492, 1728, 241
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
BEVEL = 0.018

# name: (base color, roughness, metallic, emission strength)
MATERIALS = {
    "beam_rifle_white": ((0.82, 0.83, 0.84), 0.45, 0.0, 0.0),
    "beam_rifle_dark": ((0.035, 0.038, 0.042), 0.5, 0.3, 0.0),
    "beam_rifle_orange": ((1.0, 0.32, 0.03), 0.35, 0.0, 1.5),
    "beam_rifle_cyan": ((0.15, 0.7, 1.0), 0.3, 0.0, 2.5),
    "beam_rifle_glass": ((0.008, 0.008, 0.01), 0.08, 0.0, 0.0),
}


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


def octagon(u0, u1, v0, v1, cut):
    return [(u0 + cut, v0), (u1 - cut, v0), (u1, v0 + cut), (u1, v1 - cut),
            (u1 - cut, v1), (u0 + cut, v1), (u0, v1 - cut), (u0, v0 + cut)]


def tube(name, mat, u0, u1, radius_px, v=BORE_PX, x=0.0, bevel=0.01, sides=24):
    """Cylinder along the gun (u0..u1 pixels), radius in pixels."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px),
                          radius2=P(radius_px), depth=abs(Y(u0) - Y(u1)))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=(x, (Y(u0) + Y(u1)) / 2, Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def pin(name, u, v, half_width):
    """Small dark round pin through the part, seen as a dot on both sides."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=P(3.5), radius2=P(3.5),
                          depth=half_width * 2 + 0.01)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(0, Y(u), Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), "beam_rifle_dark", 0.0)


def slanted(name, mat, center_u, center_v, length_px, depth_px, width, angle_deg, x=0.0,
            bevel=BEVEL):
    """Box along a slanted axis (the pistol grip). angle_deg: tilt of the long axis from vertical,
    bottom end toward the butt."""
    a = math.radians(angle_deg)
    down = (math.sin(a), math.cos(a))      # picture (u, v) direction of the long axis
    back = (math.cos(a), -math.sin(a))     # picture direction across the grip, toward the butt
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


def build():
    W, D, O, C, G = ("beam_rifle_white", "beam_rifle_dark", "beam_rifle_orange", "beam_rifle_cyan",
                     "beam_rifle_glass")
    rail_w, plate_w = 0.54, 0.145
    plate_x = rail_w / 2 - plate_w / 2
    core_w = rail_w - 2 * plate_w + 0.02

    # Upper rail: white side plates and top cap, dark core open toward the barrel.
    for side, sx in (("L", plate_x), ("R", -plate_x)):
        box(f"RailTop{side}", W, 492, 1345, 173, 214, plate_w, sx)
    box("RailTopCap", W, 492, 1345, 173, 182, core_w, 0.0)
    box("RailTopCore", D, 498, 1345, 180, 221, core_w, 0.0)
    # Lower rail: the mirror of the upper rail across the bore axis.
    for side, sx in (("L", plate_x), ("R", -plate_x)):
        box(f"RailBottom{side}", W, 492, 1240, 268, 309, plate_w, sx)
    box("RailBottomCap", W, 492, 1240, 300, 309, core_w, 0.0)
    box("RailBottomCore", D, 498, 1240, 261, 302, core_w, 0.0)
    pin("PinTop", 1190, 191, rail_w / 2)
    pin("PinBottom", 520, 294, rail_w / 2)

    # Barrel, front to back: muzzle cap, tube, cyan ring, collar, orange cell, collar.
    tube("MuzzleCap", D, 535, 577, 19)
    tube("MuzzleBore", G, 532, 540, 10, bevel=0.0)
    tube("Barrel", D, 577, 1215, 15)
    tube("Coil0", C, 1009, 1024, 17)
    tube("Collar0", D, 1024, 1064, 18)
    tube("Coil1", O, 1064, 1146, 16)
    tube("Collar1", D, 1146, 1215, 18)

    # Receiver: dark core block, octagon hub on both sides, raised breech covers.
    box("Receiver", D, 1200, 1400, 180, 312, 0.46)
    prism("Hub", D, octagon(1215, 1385, 202, 285, 22), 0.62)
    prism("BreechCover", D, octagon(1180, 1355, 224, 263, 10), 0.70, bevel=0.035)

    # Scope (3/4 view): white body on a dark mount, twin lenses in front, twin caps behind.
    box("ScopeMount", D, 1195, 1350, 170, 184, 0.28)
    box("Scope", W, 1209, 1342, 115, 172, 0.36)
    for side, sx in (("L", 0.095), ("R", -0.095)):
        tube(f"ScopeLens{side}", D, 1173, 1211, 20, 149, sx)
        tube(f"ScopeGlass{side}", G, 1170, 1176, 12, 149, sx, bevel=0.0)
        tube(f"ScopeCap{side}", D, 1340, 1370, 20, 149, sx)

    # Stock: white top member, dark spine, white lower brace, butt plate and pad.
    prism("StockTop", W, [(1395, 183), (1585, 183), (1634, 137), (1660, 137), (1660, 172),
                          (1634, 172), (1592, 223), (1395, 223)], 0.30)
    prism("StockSpine", D, [(1395, 222), (1592, 222), (1634, 176), (1634, 300), (1610, 265),
                            (1395, 265)], 0.24)
    prism("StockBrace", W, [(1560, 262), (1600, 262), (1650, 320), (1650, 345), (1630, 345)], 0.30)
    prism("ButtPlate", W, [(1632, 137), (1672, 137), (1672, 345), (1632, 345)], 0.36)
    prism("ButtPad", D, [(1672, 135), (1716, 135), (1728, 147), (1728, 341), (1716, 353),
                         (1672, 353)], 0.38)

    # Pistol grip: tilted 24°, white body, dark side panels, dark base, trigger slot on both sides.
    tilt = 24.0
    slanted("Grip", W, 1338, 370, 172, 92, 0.24, tilt)
    for side, sx in (("L", 0.125), ("R", -0.125)):
        slanted(f"GripPanel{side}", D, 1360, 380, 100, 44, 0.02, tilt, sx, bevel=0.006)
        slanted(f"TriggerSlot{side}", D, 1315, 311, 32, 22, 0.02, tilt + 6, sx, bevel=0.006)
    slanted("GripBase", D, 1374, 448, 28, 108, 0.30, tilt)

    # Hand and muzzle markers.
    empty("GripRight", 1340, 368)
    for name in ("GripLeft", "GripLeftRest", "GripLeftAim"):
        empty(name, 1000, 318)
    empty("Muzzle", 492, BORE_PX)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "beam_rifle.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("beam_rifle: %d objects, %d triangles" % (len(bpy.data.objects), tris))


main()
