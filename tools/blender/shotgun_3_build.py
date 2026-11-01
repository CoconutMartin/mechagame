"""Builds Shotgun 3 (one-hand electric pulse shotgun with an X of four spinning heads) and exports it.

Run (from the project root):
    blender -b --python tools/blender/shotgun_3_build.py
Writes models/shotgun_3/shotgun_3.blend and shotgun_3.glb. The script starts from an empty file.

From the user's picture models/guides/shotgun_3_ref.png (2026-11-01, "X-Hammerhead"; side, front, back, top, bottom,
3/4 views): four heads in an X round a black hub with a blue ring (dark blocks, red outer caps, three blue lamps on
the front and outer faces; they spin while the trigger is held), a dark body with light grey armor, a red panel, blue
light slits, a blue glowing cell under the barrel with a pipe, a carry frame with a blue light strip and a red top
stripe, a skeleton stock with a blue strip, a dark pistol grip with a red stripe. Same approach as Shotgun 2: no
lettering or decals.

Frame: the first Shotgun's (Godot -Z forward, the bore on y = 0, the same pistol grip place and size). Picture
pixels (level side view) go to Godot meters by GZ and GY (0.005 m per pixel, the grip lined up).
Nodes for the weapon scene: Heads (an empty on the bore axis; the four heads under it, so it spins them), HeadLamps
(lamp meshes are named HeadLamp*), EmitterRing, ArcRing, Muzzle, GripRight.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "shotgun_3")
M = 0.005  # Meters per picture pixel.
BEVEL = 0.014

MATERIALS = {
    "shotgun_3_light": ((0.6, 0.6, 0.58), 0.55, 0.05, 0.0),
    "shotgun_3_dark": ((0.075, 0.08, 0.09), 0.55, 0.35, 0.0),
    "shotgun_3_grey": ((0.2, 0.21, 0.23), 0.5, 0.45, 0.0),
    "shotgun_3_slate": ((0.15, 0.18, 0.25), 0.5, 0.3, 0.0),
    "shotgun_3_red": ((0.55, 0.07, 0.05), 0.5, 0.1, 0.0),
    "shotgun_3_blue": ((0.25, 0.6, 1.0), 0.3, 0.0, 2.0),
}
LT, D, GR, SL, RD, BL = ("shotgun_3_light", "shotgun_3_dark", "shotgun_3_grey", "shotgun_3_slate", "shotgun_3_red",
                         "shotgun_3_blue")


def GZ(x):
    """Picture x (level side view) to Godot z: the grip lines up with the first Shotgun's."""
    return -(985 - x) * M - 0.4


def GY(y):
    return -(y - 543) * M


def B(g):
    """Godot (x, y, z) to Blender (x, y, z)."""
    return Vector((g[0], -g[2], g[1]))


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


def finish(obj, mat, bevel=BEVEL, parent=None):
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        if hasattr(obj.data, "use_auto_smooth"):
            obj.data.use_auto_smooth = True
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_basis.inverted()
    return obj


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def prism(name, mat, outline, width, x=0.0, bevel=BEVEL, parent=None):
    """Side outline [(picture x, picture y)] extruded across X (width m), centered on x."""
    bm = bmesh.new()
    verts = [bm.verts.new(B((x - width / 2, GY(v), GZ(u)))) for u, v in outline]
    face = bm.faces.new(verts)
    out = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in out["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(width, 0, 0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel, parent)


def box(name, mat, x0, x1, y0, y1, width, x=0.0, bevel=BEVEL, parent=None):
    return prism(name, mat, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], width, x, bevel, parent)


def gbox(name, mat, center, size, basis=None, bevel=BEVEL, parent=None):
    """Box in Godot meters: center, size (x, y, z), optional Godot basis (3 column vectors x, y, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        p = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if basis is not None:
            p = basis[0] * p.x + basis[1] * p.y + basis[2] * p.z
        v.co = B(Vector(center) + p)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel, parent)


def gtube(name, mat, z0, z1, radius, center=(0.0, 0.0), sides=32, bevel=0.01, parent=None):
    """Cylinder along Godot z from z0 to z1."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=abs(z1 - z0))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=B((center[0], center[1], (z0 + z1) / 2)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel, parent)


def gtorus(name, mat, z, major, minor, parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=8,
                                     location=B((0.0, 0.0, z)), rotation=(math.radians(90), 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return finish(obj, mat, 0.0, parent)


def empty(name, g, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = B(g)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj



HEAD_Z0, HEAD_Z1 = GZ(40), GZ(128)    # Front and back of the heads.
HEAD_R0, HEAD_R1 = 0.14, 0.64         # Inner and outer radius of a head arm.
HEAD_W = 0.28                         # Tangential width of a head arm.


def head(i, angle_deg, pivot):
    a = math.radians(angle_deg)
    radial = Vector((math.cos(a), math.sin(a), 0.0))
    tangent = Vector((-math.sin(a), math.cos(a), 0.0))
    forward = Vector((0.0, 0.0, 1.0))
    basis = (tangent, radial, forward)
    zc = (HEAD_Z0 + HEAD_Z1) / 2
    depth = abs(HEAD_Z0 - HEAD_Z1)
    rc = (HEAD_R0 + HEAD_R1) / 2
    length = HEAD_R1 - HEAD_R0
    z = Vector((0.0, 0.0, zc))
    gbox(f"HeadArm{i}", D, radial * rc + z, (HEAD_W, length, depth), basis, 0.025, pivot)
    # Red outer cap, a slate side plate on each side, three blue lamps on the front face and two on the outer face.
    gbox(f"HeadCap{i}", RD, radial * (HEAD_R1 - 0.05) + z, (HEAD_W + 0.02, 0.12, depth + 0.02), basis, 0.02, pivot)
    for s_side in (-1.0, 1.0):
        gbox(f"HeadSide{i}_{int(s_side > 0)}", SL, radial * (rc - 0.04) + tangent * s_side * (HEAD_W / 2 + 0.008) + z,
             (0.016, length - 0.18, depth - 0.1), basis, 0.0, pivot)
    for k in range(3):
        r = HEAD_R0 + 0.12 + k * 0.11
        gbox(f"HeadLamp{i}_{k}", BL, radial * r + Vector((0.0, 0.0, HEAD_Z0 - 0.006)), (0.1, 0.075, 0.012), basis, 0.0,
             pivot)
    # More character (user 2026-11-01): a raised grey frame round the front lamps, a dark seam before the red cap, two
    # bolts on the front face, a dark fin on the back face, slots on the sides.
    gbox(f"HeadLampFrame{i}", GR, radial * (HEAD_R0 + 0.23) + Vector((0.0, 0.0, HEAD_Z0 - 0.003)), (0.16, 0.38, 0.008),
         basis, 0.0, pivot)
    gbox(f"HeadSeam{i}", D, radial * (HEAD_R1 - 0.115) + z, (HEAD_W + 0.03, 0.012, depth + 0.03), basis, 0.0, pivot)
    for k, r in enumerate((HEAD_R0 + 0.05, HEAD_R1 - 0.15)):
        for s_side in (-1.0, 1.0):
            gbox(f"HeadBolt{i}_{k}_{int(s_side > 0)}", GR, radial * r + tangent * s_side * 0.095
                 + Vector((0.0, 0.0, HEAD_Z0 - 0.008)), (0.035, 0.035, 0.01), basis, 0.0, pivot)
    gbox(f"HeadFin{i}", D, radial * (rc - 0.02) + Vector((0.0, 0.0, HEAD_Z1 + 0.04)), (0.06, length - 0.14, 0.08), basis,
         0.008, pivot)
    for s_side in (-1.0, 1.0):
        for k in range(3):
            gbox(f"HeadSlot{i}_{int(s_side > 0)}_{k}", D, radial * (HEAD_R0 + 0.12 + k * 0.08) + tangent * s_side * (HEAD_W / 2 + 0.018)
                 + z, (0.01, 0.04, depth * 0.55), basis, 0.0, pivot)
    for k in range(2):
        gbox(f"HeadLampOut{i}_{k}", BL, radial * (HEAD_R1 + 0.012) + Vector((0.0, 0.0, zc - 0.1 + k * 0.2)),
             (0.1, 0.012, 0.07), basis, 0.0, pivot)


def build():
    # Spinner: an empty on the bore axis with the four heads in an X under it.
    pivot = empty("Heads", (0.0, 0.0, (HEAD_Z0 + HEAD_Z1) / 2))
    for i, a in enumerate((45.0, 135.0, 225.0, 315.0)):
        head(i, a, pivot)
    gtube("HeadHub", D, HEAD_Z0 + 0.01, HEAD_Z1, 0.2, parent=pivot)
    # Emitter: black lens and a blue ring in front of the hub, a big blue ring behind the heads; the arc ring.
    gtube("EmitterLens", D, GZ(36), GZ(44), 0.12, bevel=0.0)
    gtube("EmitterRing", BL, GZ(38), GZ(42), 0.15, bevel=0.0)
    gtube("Hub", D, GZ(128), GZ(205), 0.29)
    gtube("BackRing", BL, GZ(196), GZ(204), 0.31, bevel=0.0)
    gtube("HubBand", GR, GZ(150), GZ(165), 0.3, bevel=0.004)
    gtorus("ArcRing", BL, GZ(84), 0.55, 0.025)

    # Barrel section: dark segmented barrel, light grey front armor above and below, the red panel, blue slits.
    gtube("Barrel", D, GZ(200), GZ(400), 0.21)
    for k, x in enumerate((215, 245, 275)):
        gtube(f"BarrelRing{k}", GR, GZ(x), GZ(x + 10), 0.225, bevel=0.003)
    box("Frame", D, 300, 720, 470, 600, 0.52)
    prism("UpperArmor", LT, [(250, 500), (300, 470), (440, 456), (470, 470), (560, 470), (560, 500), (440, 505),
                             (300, 510)], 0.58)
    prism("RedPanel", RD, [(300, 512), (430, 506), (442, 520), (432, 556), (300, 560), (288, 546)], 0.6)
    prism("LowerArmor", LT, [(160, 562), (390, 562), (400, 575), (390, 600), (175, 600), (160, 588)], 0.58)
    for k in range(2):
        x = 205 + k * 18
        prism(f"BlueSlit{k}", BL, [(x + 8, 578), (x + 14, 578), (x + 6, 596), (x, 596)], 0.592, bevel=0.0)
    box("SideRail", GR, 300, 560, 520, 528, 0.59, bevel=0.0)

    # Glowing cell under the barrel with grey caps, and a grey pipe back to the receiver.
    gtube("Cell", BL, GZ(390), GZ(490), 0.085, center=(0.0, GY(610)), bevel=0.0)
    for k, (x0, x1) in enumerate(((378, 392), (488, 502))):
        gtube(f"CellCap{k}", GR, GZ(x0), GZ(x1), 0.11, center=(0.0, GY(610)), bevel=0.005)
    pts = [(502, 610), (530, 618), (560, 614), (585, 600)]
    for k in range(len(pts) - 1):
        a = Vector((0.0, GY(pts[k][1]), GZ(pts[k][0])))
        b = Vector((0.0, GY(pts[k + 1][1]), GZ(pts[k + 1][0])))
        along = (b - a).normalized()
        up = Vector((1.0, 0.0, 0.0)).cross(along).normalized()
        gbox(f"Pipe{k}", GR, (a + b) / 2, (0.07, 0.07, (b - a).length + 0.03), (Vector((1.0, 0.0, 0.0)), up, along), 0.02)

    # Carry frame on top with a blue light strip and a red stripe; a sight block.
    prism("CarryFrame", D, [(380, 456), (420, 432), (690, 432), (700, 446), (690, 470), (660, 470), (650, 450),
                            (430, 450), (410, 470), (380, 470)], 0.18)
    box("CarryLight", BL, 450, 560, 436, 444, 0.19, bevel=0.0)
    box("CarryRed", RD, 590, 680, 430, 438, 0.19, bevel=0.0)
    box("Sight", GR, 470, 520, 462, 472, 0.16, bevel=0.004)

    # Rear: light grey upper armor, a slate panel, the lower receiver, trigger guard and trigger.
    prism("RearArmor", LT, [(560, 470), (700, 470), (720, 482), (860, 482), (870, 494), (860, 516), (720, 516), (700, 528),
                            (560, 528)], 0.56)
    box("SlatePanel", SL, 600, 690, 540, 562, 0.54, bevel=0.008)
    box("LowerReceiver", D, 400, 720, 562, 612, 0.44)
    box("TriggerGuard", D, 640, 720, 612, 642, 0.2, bevel=0.01)
    box("Trigger", RD, 668, 678, 612, 634, 0.06, bevel=0.0)

    # Skeleton stock: top bar, rear upright with a blue strip, a diagonal brace to the grip, a dark pad.
    prism("StockTop", SL, [(720, 482), (930, 482), (950, 470), (980, 470), (980, 520), (930, 520), (720, 518)], 0.36)
    prism("StockUpright", SL, [(930, 470), (990, 470), (990, 650), (960, 660), (930, 640)], 0.42)
    box("StockStrip", BL, 952, 966, 530, 620, 0.432, bevel=0.0)
    prism("StockBrace", D, [(758, 596), (800, 596), (945, 628), (945, 660), (920, 662)], 0.32)
    box("StockPad", D, 986, 1004, 468, 652, 0.46, bevel=0.012)

    # Pistol grip: the first Shotgun's place and size (dark), a red front stripe, a light grey back cap.
    top = Vector((0.0, -0.2, -1.7))
    axis = Vector((0.0, -0.9397, 0.342))
    back = Vector((0.0, 0.342, 0.9397))
    grip_basis = (Vector((1.0, 0.0, 0.0)), axis * -1.0, back)
    gbox("Grip", D, top + axis * 0.48, (0.2, 0.96, 0.24), grip_basis, 0.03)
    gbox("GripStripe", RD, top + axis * 0.5 - back * 0.115, (0.21, 0.6, 0.03), grip_basis, 0.0)
    gbox("GripBack", LT, top + axis * 0.82 + back * 0.08, (0.22, 0.28, 0.1), grip_basis, 0.012)
    gbox("GripBase", D, top + axis * 0.98, (0.24, 0.07, 0.3), grip_basis, 0.015)

    details()

    # Markers.
    empty("Muzzle", (0.0, 0.0, GZ(36)))
    empty("GripRight", (-0.2, -0.62287, -1.7261))


def side_bolt(name, mat, x, y, width, size=0.045):
    """A small square bolt head on both side faces (picture x, y; the faces at +-width / 2)."""
    for k, sx in enumerate((width / 2, -width / 2)):
        gbox(f"{name}_{k}", mat, (sx, GY(y), GZ(x)), (0.02, size, size), None, 0.0)


def details():
    """More character and body (user 2026-11-01: "Beautify it, add a bit more character and body")."""
    # Hub: four dark ribs between the heads behind them, bolts round the front lens, a light grey ring on the hub.
    for k, a_deg in enumerate((0.0, 90.0, 180.0, 270.0)):
        a = math.radians(a_deg)
        radial = Vector((math.cos(a), math.sin(a), 0.0))
        tangent = Vector((-math.sin(a), math.cos(a), 0.0))
        gbox(f"HubRib{k}", D, radial * 0.32 + Vector((0.0, 0.0, GZ(168))), (0.06, 0.1, 0.34),
             (tangent, radial, Vector((0.0, 0.0, 1.0))), 0.008)
    gtube("HubRing", LT, GZ(178), GZ(188), 0.3, bevel=0.004)
    # Barrel shroud: light grey half shells with dark slots over the barrel, front and back collars.
    prism("ShroudTop", LT, [(205, 500), (290, 500), (300, 508), (300, 520), (205, 520)], 0.4, bevel=0.01)
    for k in range(4):
        x = 215 + k * 18
        box(f"ShroudSlot{k}", D, x, x + 8, 498, 503, 0.24, bevel=0.0)
    for k, x in enumerate((198, 296)):
        gtube(f"ShroudCollar{k}", GR, GZ(x), GZ(x + 8), 0.235, bevel=0.003)
    # Upper armor: a raised panel with a seam and bolts; red panel: a dark inset and a light grey edge strip.
    prism("UpperPanel", LT, [(312, 486), (440, 474), (460, 484), (548, 484), (548, 498), (440, 500), (312, 504)], 0.62,
          bevel=0.008)
    box("UpperSeam", GR, 310, 548, 507, 509, 0.592, bevel=0.0)
    for k, x in enumerate((330, 530)):
        side_bolt(f"UpperBolt{k}", GR, x, 494, 0.62)
    prism("RedInset", D, [(318, 524), (410, 520), (418, 530), (410, 546), (318, 548)], 0.612, bevel=0.0)
    box("RedEdge", LT, 300, 430, 557, 561, 0.612, bevel=0.0)
    # Lower armor: a raised panel and bolts; lower receiver ribs; a magazine block below it.
    prism("LowerPanel", LT, [(250, 568), (380, 568), (388, 576), (380, 592), (250, 592)], 0.62, bevel=0.008)
    for k, x in enumerate((180, 370)):
        side_bolt(f"LowerBolt{k}", GR, x, 590, 0.58)
    for k in range(6):
        x = 520 + k * 16
        box(f"ReceiverRib{k}", GR, x, x + 6, 566, 606, 0.452, bevel=0.0)
    box("Magazine", GR, 540, 610, 612, 650, 0.3, bevel=0.012)
    box("MagazineBase", D, 536, 614, 650, 658, 0.32, bevel=0.006)
    # Cell cage: three dark bars across the glowing cell.
    for k, x in enumerate((410, 440, 470)):
        gtube(f"CellBar{k}", D, GZ(x), GZ(x + 5), 0.095, center=(0.0, GY(610)), bevel=0.0)
    # Carry frame: grip rings, a longer blue strip, a red tab at the front.
    for k in range(4):
        x = 470 + k * 26
        box(f"CarryRing{k}", GR, x, x + 10, 430, 452, 0.195, bevel=0.003)
    box("CarryTab", RD, 382, 400, 446, 470, 0.19, bevel=0.004)
    # Rear armor: dark vents and a blue lamp; the slate panel gets bolts.
    for k in range(4):
        x = 740 + k * 14
        box(f"RearVent{k}", D, x, x + 6, 490, 510, 0.572, bevel=0.0)
    box("RearLamp", BL, 820, 840, 494, 500, 0.574, bevel=0.0)
    for k, x in enumerate((608, 682)):
        side_bolt(f"PanelBolt{k}", GR, x, 551, 0.54)
    # Stock: a light grey plate on the upright, slots in the top bar, bolts, pad ribs.
    prism("UprightPlate", LT, [(936, 540), (984, 540), (984, 632), (962, 640), (936, 626)], 0.44, bevel=0.008)
    for k in range(4):
        x = 760 + k * 36
        box(f"StockSlot{k}", D, x, x + 20, 494, 506, 0.372, bevel=0.0)
    for k, y in enumerate((486, 640)):
        side_bolt(f"StockBolt{k}", GR, 960, y, 0.42)
    for k in range(6):
        y = 486 + k * 28
        box(f"PadRib{k}", GR, 998, 1008, y, y + 5, 0.38, bevel=0.0)
    # Grip: finger ridges on its front face.
    top = Vector((0.0, -0.2, -1.7))
    axis = Vector((0.0, -0.9397, 0.342))
    back = Vector((0.0, 0.342, 0.9397))
    for k in range(3):
        gbox(f"GripRidge{k}", D, top + axis * (0.38 + 0.13 * k) - back * 0.13, (0.215, 0.025, 0.02),
             (Vector((1.0, 0.0, 0.0)), axis * -1.0, back), 0.0)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "shotgun_3.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "shotgun_3.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    ys = [(o.matrix_world @ Vector(c)).y for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    print("shotgun_3: %d objects, %d triangles, length %.2f m (godot z %.2f to %.2f)" % (
        len(bpy.data.objects), tris, max(ys) - min(ys), -max(ys), -min(ys)))
    for name in ("Heads", "Muzzle"):
        o = bpy.data.objects[name]
        print("node %s godot (%.3f, %.3f, %.3f)" % (name, o.location.x, o.location.z, -o.location.y))


main()
