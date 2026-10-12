"""Builds the SMG (user design 2026-10-11) and exports it.

Run (from the project root):
    blender -b --python tools/blender/smg_build.py
Writes models/smg/smg.blend and models/smg/smg.glb. The script starts from an empty file, so hand
edits in the .blend are lost when it runs again.

Traced from the user's picture, models/guides/smg_ref.png (side view, top left). Muzzle front at
pixel x 67, stock butt at 870, bore axis at pixel row 138. Widths from the top view. Size: the user
gave none; LENGTH makes the pistol grip about as big as the heavy rifle's (fits the mech fist).
Chamfered boxes, olive drab and black like the picture, yellow marks.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the butt (back face), on the bore axis.
Empties: Muzzle (bore front), Grip (fist center on the pistol grip).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "smg")

MUZZLE_PX, BUTT_PX, AXIS_PX = 67, 870, 138
## Length from muzzle to butt (m).
LENGTH = 3.6
SCALE = LENGTH / (BUTT_PX - MUZZLE_PX)
## Pistol grip: extra length past the picture's (pixels; 156 = 0.7 m), and where the fist holds it
## (pixels above its bottom end; 67 = 0.3 m).
GRIP_EXTRA_PX = 156
GRIP_HOLD_PX = 67

MATERIALS = {
    "smg_olive": ((0.15, 0.165, 0.11), 0.65, 0.1),
    "smg_black": ((0.022, 0.023, 0.025), 0.55, 0.35),
    "smg_bore": ((0.005, 0.005, 0.006), 0.7, 0.2),
    "smg_yellow": ((0.85, 0.45, 0.03), 0.5, 0.0),
}
O, K, B, YL = "smg_olive", "smg_black", "smg_bore", "smg_yellow"


def Y(u):
    return (BUTT_PX - u) * SCALE


def Z(v):
    return (AXIS_PX - v) * SCALE


def P(px):
    return px * SCALE


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    mat.diffuse_color = (*color, 1.0)
    return mat


def finish(obj, mat, bevel):
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
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


def block(name, mat, u0, u1, v0, v1, w, chamfer_px=0.0, bevel=0.012):
    """Box from picture pixels: side view u (along) and v (height), width w (pixels, centered)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((P(w), abs(Y(u0) - Y(u1)), P(v1 - v0))), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0.0, (Y(u0) + Y(u1)) / 2, (Z(v0) + Z(v1)) / 2)), verts=bm.verts)
    if chamfer_px > 0.0:
        # Chamfer the four edges along the gun (the picture's cut corners).
        along = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().y) > 0.99]
        bmesh.ops.bevel(bm, geom=along, offset=P(chamfer_px), segments=1, affect="EDGES")
    return finish(new_object(name, bm), mat, bevel)


def bar(name, mat, a, b, thick_px, w, bevel=0.01):
    """Straight bar in the side view from a = (u, v) to b = (u, v), thick_px across, w wide."""
    pa = Vector((0.0, Y(a[0]), Z(a[1])))
    pb = Vector((0.0, Y(b[0]), Z(b[1])))
    d = (pb - pa).normalized()
    n = Vector((0.0, -d.z, d.y)) * P(thick_px) / 2
    bm = bmesh.new()
    pts = [pa + n, pb + n, pb - n, pa - n]
    half = P(w) / 2
    vs = [bm.verts.new((sx * half, p.y, p.z)) for sx in (-1, 1) for p in pts]
    for f in ([0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def tube(name, mat, u0, u1, radius_px, sides=16):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px), radius2=P(radius_px),
                          depth=abs(Y(u0) - Y(u1)))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, (Y(u0) + Y(u1)) / 2, 0.0), verts=bm.verts)
    return finish(new_object(name, bm), mat, 0.0)


def empty(name, location):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.2
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    parts = []
    # Muzzle: square suppressor with chamfers, the dark bore, a step block behind it.
    parts.append(block("Suppressor", K, 67, 127, 112, 165, 48, chamfer_px=8))
    parts.append(tube("Bore", B, 63, 70, 12))
    parts.append(block("FrontStep", K, 120, 137, 97, 180, 60, chamfer_px=6))
    # Olive handguard with the lower step, and the vent slots (two rows of three, both sides).
    parts.append(block("Handguard", O, 135, 380, 84, 195, 70, chamfer_px=6))
    parts.append(block("HandguardTop", O, 378, 447, 84, 140, 70, chamfer_px=6))
    parts.append(block("HandguardStep", O, 240, 382, 190, 212, 66, chamfer_px=4))
    for row, (v0, v1) in enumerate(((112, 125), (144, 159))):
        for col, (u0, u1) in enumerate(((169, 207), (218, 256), (268, 310))):
            parts.append(block(f"Vent{row}{col}", B, u0, u1, v0, v1, 72, bevel=0.0))
    # Black upper and lower receiver, the olive rear cap.
    parts.append(block("UpperReceiver", K, 440, 650, 85, 140, 64, chamfer_px=4))
    parts.append(block("LowerReceiver", K, 375, 630, 138, 205, 60, chamfer_px=4))
    parts.append(block("RearCap", O, 612, 650, 95, 180, 72, chamfer_px=6))
    # Top rail with teeth and the two folding sights.
    parts.append(block("Rail", K, 172, 605, 66, 84, 40))
    for i, u in enumerate(range(176, 600, 11)):
        parts.append(block(f"RailTooth{i:02d}", K, u, u + 6, 61, 67, 44, bevel=0.0))
    for name, u0, u1 in (("FrontSight", 182, 232), ("RearSight", 553, 605)):
        parts.append(block(name + "Base", K, u0, u1, 50, 84, 46, chamfer_px=5))
        parts.append(block(name + "Post", K, u0 + 10, u1 - 10, 32, 52, 30, chamfer_px=4))
    # Charging handle, sticking out on both sides.
    parts.append(block("ChargingHandle", K, 495, 567, 170, 184, 74))
    # Trigger guard and trigger.
    parts.append(bar("TriggerGuardFront", K, (378, 205), (392, 254), 8, 14))
    parts.append(bar("TriggerGuard", K, (388, 252), (512, 252), 8, 14))
    parts.append(bar("Trigger", K, (458, 205), (447, 236), 7, 10))
    # Magazine (angled forward) with its base plate, pistol grip (angled back) with its base.
    parts.append(bar("Magazine", K, (398, 200), (353, 412), 74, 40))
    parts.append(bar("MagazinePlate", K, (354, 404), (350, 424), 86, 46))
    # Pistol grip longer than the picture by GRIP_EXTRA_PX (user choice 2026-10-12): the fist holds it
    # near the bottom, so the SMG rides clear above the thick forearm armor.
    gx, gy = 607 - 555, 352 - 200
    glen = math.hypot(gx, gy)
    end = (607 + gx / glen * GRIP_EXTRA_PX, 352 + gy / glen * GRIP_EXTRA_PX)
    parts.append(bar("PistolGrip", K, (555, 200), end, 72, 44))
    parts.append(bar("PistolGripBase", K, (end[0] - 1, end[1] - 8), (end[0] + 4, end[1] + 10), 84, 48))
    # Stock: tube, rear adapter, lower brace and the hollow triangle pad.
    parts.append(block("StockAdapter", K, 650, 676, 100, 160, 46, chamfer_px=4))
    parts.append(block("StockTube", K, 676, 780, 112, 142, 26, chamfer_px=3))
    parts.append(bar("StockBraceTop", K, (676, 158), (780, 158), 14, 22))
    parts.append(bar("StockBrace", K, (695, 162), (812, 288), 16, 22))
    parts.append(block("StockTop", K, 770, 870, 107, 160, 46, chamfer_px=8))
    parts.append(block("StockPad", K, 818, 869, 109, 297, 43, chamfer_px=6))
    parts.append(block("StockFoot", K, 800, 868, 270, 296, 44, chamfer_px=4))
    # Yellow marks: receiver side and stock pad.
    parts.append(block("MarkReceiver", YL, 540, 585, 113, 122, 66, bevel=0.0))
    parts.append(block("MarkStock", YL, 845, 853, 210, 256, 48, bevel=0.0))
    muzzle = empty("Muzzle", (0.0, Y(MUZZLE_PX), 0.0))
    # Fist center on the pistol grip: GRIP_HOLD_PX above its bottom end.
    hold = (end[0] - gx / glen * GRIP_HOLD_PX, end[1] - gy / glen * GRIP_HOLD_PX)
    grip = empty("Grip", (0.0, Y(hold[0]), Z(hold[1])))
    return parts + [muzzle, grip]


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True)
    tris = 0
    for obj in objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("smg: %s, %d objects, %d triangles, scale %.4f m per pixel" % (os.path.basename(path), len(objects), tris, SCALE))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "smg.blend"))
    export(os.path.join(OUT_DIR, "smg.glb"), objects)


main()
