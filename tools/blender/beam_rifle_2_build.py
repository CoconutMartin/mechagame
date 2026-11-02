"""Builds Beam Rifle 2 (two-hand rapid-fire beam rifle, 6 m long) and exports it.

Run (from the project root):
    blender -b --python tools/blender/beam_rifle_2_build.py
Writes models/beam_rifle_2/beam_rifle_2.blend and beam_rifle_2.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

From the user's picture models/guides/beam_rifle_2_ref.png (side, front, back, 3/4 and top views):
segmented white rails above and below a dark barrel, a bore in the front of each rail, a large round
hub on the receiver, two orange cells, a small scope with one lens, a Y stock, a pistol grip.

The pistol grip and the lower rail sit at the same places as on the first Beam Rifle
(tools/blender/beam_rifle_build.py, same picture pixel frame), so the hand markers, grip sockets and
holds of the Beam Rifle fit this model too.

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = left side of the gun (Godot +X after export).
Origin: butt pad back face, on the bore axis.
Empties (Marker3D in Godot): GripRight, GripLeft, Muzzle (barrel tip), MuzzleTop and MuzzleBottom
(the rail bores, where the shots leave).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "beam_rifle_2")

# The first Beam Rifle's picture frame: muzzle at pixel 492, butt at 1728 (6 m), bore row 241.
MUZZLE_PX, BUTT_PX, BORE_PX = 492, 1728, 241
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
BEVEL = 0.018

# name: (base color, roughness, metallic, emission strength). Colors from the picture.
MATERIALS = {
    "beam_rifle_2_white": ((0.78, 0.77, 0.75), 0.5, 0.0, 0.0),
    "beam_rifle_2_dark": ((0.03, 0.032, 0.036), 0.5, 0.3, 0.0),
    "beam_rifle_2_grey": ((0.11, 0.115, 0.125), 0.45, 0.4, 0.0),
    "beam_rifle_2_orange": ((1.0, 0.36, 0.04), 0.35, 0.0, 1.5),
    "beam_rifle_2_glass": ((0.25, 0.42, 0.45), 0.08, 0.0, 0.0),
}
W, D, GR, O, G = ("beam_rifle_2_white", "beam_rifle_2_dark", "beam_rifle_2_grey", "beam_rifle_2_orange",
                  "beam_rifle_2_glass")


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


# Rail segments along the gun (picture pixels, front to back) and the dots on each (the picture: two
# dots on most segments, one on some). The last segment runs into the receiver.
SEGMENTS = [(492, 600), (608, 760), (768, 920), (928, 1080), (1088, 1236)]
DOTS_TOP = [2, 2, 1, 1, 0]
DOTS_BOTTOM = [2, 2, 2, 2, 0]
RAIL_W = 0.50
# Raised side panel on each segment: this much wider than the segment (both sides together).
PANEL_RISE = 0.06
# Upper and lower rail rows (top, bottom). The lower rail bottom (313) is where the left hand holds
# (the first Beam Rifle's rail bottom is 309, its grip socket 0.37 m under the bore). Nothing hangs
# below the lower rail between u 640 and 1200 (the left hand's rest, aim and low aim places).
TOP_ROWS = (166, 219)
BOTTOM_ROWS = (263, 313)


def rail(prefix, rows, dots, top):
    v0, v1 = rows
    mid = (v0 + v1) / 2
    # Dark spine behind the segments, seen in the gaps between them.
    box(f"{prefix}Spine", D, 500, 1240, v0 + 6, v1 - 6, RAIL_W - 0.08, bevel=0.01)
    for i, ((u0, u1), count) in enumerate(zip(SEGMENTS, dots)):
        if i == 0:
            # Nose segment: the front corners cut deeper, so the rail tip narrows like a shroud.
            prism(f"{prefix}Seg{i}", W, [(u0 + 12, v0), (u1 - 5, v0), (u1, v0 + 5), (u1, v1 - 5),
                                         (u1 - 5, v1), (u0 + 12, v1), (u0, v1 - 12), (u0, v0 + 12)],
                  RAIL_W, bevel=0.022)
        else:
            chamfer_box(f"{prefix}Seg{i}", W, u0, u1, v0, v1, RAIL_W, 5, bevel=0.022)
        # Raised side panel with chamfered corners, a grey seam line under it on the outer edge.
        pu0, pu1 = u0 + (20 if i == 0 else 12), u1 - 12
        chamfer_box(f"{prefix}Panel{i}", W, pu0, pu1, v0 + 9, v1 - 9, RAIL_W + PANEL_RISE, 6, bevel=0.012)
        seam_v = v1 - 6 if top else v0 + 6
        box(f"{prefix}Seam{i}", GR, pu0 + 6, pu1 - 6, seam_v - 1.5, seam_v + 1.5, RAIL_W + 0.012, bevel=0.0)
        span = pu1 - pu0
        if count == 1:
            places = [pu0 + span * 0.5]
        elif count == 2:
            places = [pu0 + span * 0.3, pu0 + span * 0.7]
        else:
            places = []
        for k, u in enumerate(places):
            pin(f"{prefix}Dot{i}_{k}", u, mid, (RAIL_W + PANEL_RISE) / 2)
        # Vent slots on the outer face (top of the upper rail, bottom of the lower rail) of the middle
        # segments. Only on the upper rail's top: the left hand holds the lower rail's bottom.
        if top and 1 <= i <= 3:
            for k in range(3):
                su = u0 + span * 0.35 + k * 14
                box(f"{prefix}Vent{i}_{k}", D, su, su + 6, v0 - 1.5, v0 + 3, 0.26, bevel=0.0)
    # Bore in the front face of the rail: a grey ring and a dark hole, where the shots leave.
    tube(f"{prefix}BoreRing", GR, 486, 494, 17, mid, bevel=0.005, sides=16)
    tube(f"{prefix}Bore", D, 484, 487, 10, mid, bevel=0.0, sides=16)


def build():
    rail("RailTop", TOP_ROWS, DOTS_TOP, True)
    rail("RailBottom", BOTTOM_ROWS, DOTS_BOTTOM, False)

    # Front bracket between the rails, behind the barrel tip.
    box("FrontBracket", D, 548, 578, 214, 268, 0.30, bevel=0.012)

    # Barrel: dark tube with collars, a grey muzzle cap, heat-sink fins, an orange cell in a dark cage.
    tube("MuzzleCap", GR, 500, 540, 18)
    tube("MuzzleBore", D, 497, 502, 10, bevel=0.0)
    tube("Barrel", D, 540, 1220, 13)
    for i, (u0, u1) in enumerate(((600, 622), (760, 784), (920, 944))):
        tube(f"Collar{i}", GR, u0, u1, 17)
    for i in range(6):
        u = 966 + i * 14
        tube(f"Fin{i}", GR, u, u + 6, 21, bevel=0.004)
    # Coil core between the fins: a dark sleeve that the game lights with the heat (user 2026-11-02: the ribbed coil
    # turns red at max heat; BeamRepeaterWeapon.heat_glow_paths: CoilCore and Fin0..5).
    tube("CoilCore", D, 964, 1046, 16, bevel=0.0)
    tube("CellCollar0", D, 1050, 1078, 19)
    box("Cell", O, 1078, 1132, 226, 256, 0.24, bevel=0.008)
    for i, u in enumerate((1092, 1116)):
        box(f"CellStrap{i}", D, u, u + 6, 223, 259, 0.27, bevel=0.0)
    tube("CellCollar1", D, 1132, 1152, 19)

    # Receiver: dark core, white upper body that steps up to the stock with a raised side plate,
    # white lower body under the lower rail with vent slats, a big round hub with bolts and a lamp.
    box("Receiver", D, 1150, 1400, 176, 314, 0.50)
    prism("UpperBody", W, [(1236, 166), (1330, 166), (1352, 152), (1400, 152), (1400, 219), (1236, 219)], 0.56)
    prism("UpperPlate", W, [(1248, 175), (1325, 175), (1347, 162), (1392, 162), (1392, 196), (1248, 196)],
          0.62, bevel=0.012)
    box("UpperSeam", GR, 1252, 1388, 199, 202, 0.572, bevel=0.0)
    prism("LowerBody", W, [(1236, 263), (1300, 263), (1312, 275), (1312, 300), (1292, 320), (1236, 320)], 0.56)
    for i in range(3):
        u = 1248 + i * 14
        box(f"LowerVent{i}", D, u, u + 6, 285, 308, 0.575, bevel=0.0)
    disc("Hub", D, 1290, 243, 58, 0.64)
    disc("HubRing", GR, 1290, 243, 44, 0.68)
    disc("HubCap", D, 1290, 243, 26, 0.72)
    disc("HubLamp", O, 1290, 243, 8, 0.74, bevel=0.0, sides=16)
    for k in range(6):
        a = math.radians(30 + 60 * k)
        disc(f"HubBolt{k}", GR, 1290 + 51 * math.cos(a), 243 + 51 * math.sin(a), 4.5, 0.70, bevel=0.0, sides=10)
    # Second orange cell behind the hub, on both sides of the stock spine, in a dark frame.
    box("CellRearFrame", D, 1354, 1416, 226, 260, 0.28, bevel=0.008)
    box("CellRear", O, 1360, 1410, 230, 256, 0.32, bevel=0.008)

    # Scope: dark mount on a grey rail, white body with side knobs, a dark lens hood with glass,
    # a dark back cap, a small sight with glass on top.
    box("ScopeRail", GR, 1240, 1345, 160, 168, 0.18, bevel=0.004)
    box("ScopeMount", D, 1250, 1330, 148, 166, 0.24)
    prism("Scope", W, [(1240, 112), (1325, 112), (1338, 122), (1338, 146), (1325, 154), (1240, 154)], 0.32)
    for side, sx in (("L", 0.18), ("R", -0.18)):
        tube(f"ScopeKnob{side}", GR, 1282, 1300, 9, 133, sx, bevel=0.003, sides=12)
    tube("ScopeHood", D, 1196, 1242, 22, 132)
    tube("ScopeGlass", G, 1194, 1200, 15, 132, bevel=0.0)
    tube("ScopeCap", D, 1336, 1356, 17, 132)
    box("ScopeSight", D, 1262, 1302, 96, 113, 0.14, bevel=0.008)
    box("ScopeSightGlass", G, 1259, 1263, 99, 109, 0.10, bevel=0.0)

    # Stock: white top member with a raised cheek plate, dark spine with an orange stripe, white lower
    # brace, white butt plate with a dot, dark pad with grey grooves.
    prism("StockTop", W, [(1400, 152), (1560, 152), (1610, 126), (1660, 126), (1660, 175),
                          (1622, 175), (1580, 222), (1400, 222)], 0.36)
    prism("CheekPlate", W, [(1415, 164), (1548, 164), (1585, 145), (1640, 145), (1640, 160),
                            (1600, 160), (1565, 206), (1415, 206)], 0.42, bevel=0.012)
    prism("StockSpine", D, [(1400, 220), (1580, 220), (1634, 176), (1634, 300), (1610, 268),
                            (1400, 268)], 0.26)
    prism("StockStripe", O, [(1430, 238), (1560, 238), (1590, 214), (1598, 220), (1566, 246), (1430, 246)],
          0.272, bevel=0.0)
    prism("StockBrace", W, [(1548, 262), (1592, 262), (1650, 322), (1650, 350), (1626, 350)], 0.36)
    prism("ButtPlate", W, [(1630, 126), (1674, 126), (1674, 350), (1630, 350)], 0.44)
    pin("ButtDot", 1652, 240, 0.23)
    prism("ButtPad", D, [(1674, 122), (1716, 122), (1728, 136), (1728, 346), (1716, 360),
                         (1674, 360)], 0.48)
    for i in range(5):
        v = 170 + i * 36
        box(f"PadGroove{i}", GR, 1682, 1720, v, v + 4, 0.492, bevel=0.0)

    # Pistol grip (the first Beam Rifle's place and size): white body, dark back panels, a grey
    # swell plate, dark base, trigger slot on both sides.
    tilt = 24.0
    slanted("Grip", W, 1338, 370, 172, 92, 0.24, tilt)
    for side, sx in (("L", 0.125), ("R", -0.125)):
        slanted(f"GripPanel{side}", D, 1366, 384, 110, 40, 0.02, tilt, sx, bevel=0.006)
        slanted(f"TriggerSlot{side}", D, 1312, 316, 34, 22, 0.02, tilt + 6, sx, bevel=0.006)
    slanted("GripSwell", GR, 1312, 425, 80, 10, 0.25, tilt, bevel=0.004)
    slanted("GripBase", D, 1374, 448, 28, 108, 0.30, tilt)

    # Markers.
    empty("GripRight", 1340, 368)
    empty("GripLeft", 1000, 318)
    empty("Muzzle", 484, BORE_PX)
    empty("MuzzleTop", 484, sum(TOP_ROWS) / 2)
    empty("MuzzleBottom", 484, sum(BOTTOM_ROWS) / 2)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle_2.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "beam_rifle_2.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("beam_rifle_2: %d objects, %d triangles" % (len(bpy.data.objects), tris))


main()
