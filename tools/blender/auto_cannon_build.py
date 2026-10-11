"""Builds the Auto Cannon (user design; traced at 6 m, then width and height 50%, length 75%: 4.5 m)
and exports its two versions.

Run (from the project root):
    blender -b --python tools/blender/auto_cannon_build.py
Writes models/auto_cannon/auto_cannon.blend and two .glb files:
    auto_cannon.glb           baton version (held under the right forearm): the model with the grip
                              handle that the picture does not show (user request)
    auto_cannon_shoulder.glb  shoulder unit: the model with a mount block under the rear body
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Traced from the user's picture, models/guides/auto_cannon_ref.png. Side view: muzzle at pixel x 823,
butt at 1510 (6 m, so one pixel = SCALE m), bore axis at pixel row 254. Top view: center row 553
(widths). Chamfered boxes like the picture (one wide bevel segment).

Axes: Blender +Y = forward (Godot -Z), +Z = up (top box and hinge on top). Origin: the butt (back
face), on the bore axis. Empties: Muzzle (both), Grip (baton: the fist center on the handle),
Mount (shoulder: bottom of the mount block, the turn point).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "auto_cannon")

MUZZLE_PX, BUTT_PX, AXIS_PX, MID_W = 823, 1510, 254, 553
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
## Size change after tracing (user request 2026-10-11): width and height 50%, length 75% (4.5 m).
SIZE = (0.5, 0.75, 0.5)
## Baton version: grip handle from the butt (the new mech's elbow to palm socket, 2.71 m), the
## distance from the bore axis to the fist center (the cannon clears the forearm armor), the handle
## radius and how far the handle goes on through the fist.
GRIP_FROM_BUTT = 2.71
GRIP_DROP = 1.1
HANDLE_RADIUS = 0.11
HANDLE_PAST_FIST = 0.25
## Shoulder version: mount block under the rear body.
MOUNT_FROM_BUTT = 0.94
MOUNT_DROP = 0.15

MATERIALS = {
    "auto_cannon_dark": ((0.105, 0.108, 0.112), 0.55, 0.35),
    "auto_cannon_khaki": ((0.36, 0.34, 0.2), 0.6, 0.0),
    "auto_cannon_bore": ((0.01, 0.01, 0.012), 0.7, 0.2),
}


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


def finish(obj, mat, bevel, segments=1):
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


def block(name, mat, u0, u1, v0, v1, w0, w1, chamfer_px=0.0, bevel=0.02):
    """Box from picture pixels: side view u (along) and v (height), top view w (width)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    size = Vector((P(w1 - w0), abs(Y(u0) - Y(u1)), P(v1 - v0)))
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    center = Vector((P((w0 + w1) / 2 - MID_W), (Y(u0) + Y(u1)) / 2, (Z(v0) + Z(v1)) / 2))
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    if chamfer_px > 0.0:
        # Chamfer the four edges along the gun (the picture's cut corners).
        along = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().y) > 0.99]
        bmesh.ops.bevel(bm, geom=along, offset=P(chamfer_px), segments=1, affect="EDGES")
    return finish(new_object(name, bm), mat, bevel)


def tube(name, mat, u0, u1, radius_px, v=AXIS_PX, w=MID_W, sides=32, bevel=0.015):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px), radius2=P(radius_px),
                          depth=abs(Y(u0) - Y(u1)))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=(P(w - MID_W), (Y(u0) + Y(u1)) / 2, Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def pin(name, mat, u, v, w0, w1, radius_px, sides=20):
    """Cylinder across the gun (X), from top view w0 to w1."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=P(radius_px), radius2=P(radius_px),
                          depth=P(w1 - w0))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(P((w0 + w1) / 2 - MID_W), Y(u), Z(v)), verts=bm.verts)
    return finish(new_object(name, bm), mat, 0.01)


def link(name, mat, a, b, w, thick_px, width_px):
    """Flat bar in the side view from a = (u, v) to b = (u, v), thick_px across, at top view w."""
    pa = Vector((0.0, Y(a[0]), Z(a[1])))
    pb = Vector((0.0, Y(b[0]), Z(b[1])))
    d = (pb - pa).normalized()
    n = Vector((0.0, -d.z, d.y)) * P(thick_px) / 2
    bm = bmesh.new()
    pts = [pa + n, pb + n, pb - n, pa - n]
    half = P(width_px) / 2
    vs = [bm.verts.new((P(w - MID_W) + sx * half, p.y, p.z)) for sx in (-1, 1) for p in pts]
    for f in ([0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, 0.012)


def empty(name, location):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    D, T, B = "auto_cannon_dark", "auto_cannon_khaki", "auto_cannon_bore"
    common = []
    # Muzzle: round tube with a ring and the dark bore.
    common.append(tube("MuzzleTube", D, 823, 876, 56))
    common.append(tube("MuzzleRing", D, 868, 888, 60))
    common.append(tube("Bore", B, 820, 830, 36, bevel=0.0))
    # Body, front to back.
    common.append(block("Barrel", D, 876, 1078, 190, 318, 491, 616, chamfer_px=18))
    common.append(block("FrontCollar", T, 1078, 1187, 177, 332, 474, 633, chamfer_px=20))
    common.append(block("Core", D, 1187, 1267, 205, 300, 500, 612, chamfer_px=8))
    common.append(block("UnderRail", D, 1187, 1265, 300, 325, 525, 581, bevel=0.015))
    common.append(block("RearBody", T, 1267, 1462, 175, 332, 474, 632, chamfer_px=20))
    common.append(block("BackCap", D, 1462, 1510, 176, 311, 495, 615, chamfer_px=16))
    # Top: box at the back, hinge links from the front collar to a pin, cross bar to the box.
    common.append(block("TopBox", D, 1352, 1466, 112, 175, 505, 603, chamfer_px=10))
    common.append(block("CrossBar", D, 1290, 1356, 140, 166, 527, 586, bevel=0.015))
    common.append(pin("HingePin", D, 1287, 150, 476, 630, 10))
    for side, w in (("L", 489), ("R", 617)):
        common.append(link(f"Link{side}", D, (1203, 186), (1287, 150), w, 24, 16))
        common.append(pin(f"PinCap{side}", D, 1287, 150, w - 9, w + 9, 17))
        common.append(block(f"LinkFoot{side}", D, 1192, 1216, 170, 179, w - 10, w + 10, bevel=0.01))
    resize = Matrix.Diagonal((*SIZE, 1.0))
    for obj in common:
        obj.data.transform(resize)
        for mod in obj.modifiers:
            mod.width *= SIZE[0]
    muzzle = empty("Muzzle", (0.0, Y(MUZZLE_PX) * SIZE[1], 0.0))

    # Baton version: grip handle under the body (held like a tonfa: the handle goes through the fist
    # from the pinky side, the body lies along the forearm).
    rail_bottom = Z(325) * SIZE[2]
    grip_y = GRIP_FROM_BUTT
    handle_top = -GRIP_DROP - HANDLE_PAST_FIST
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=HANDLE_RADIUS, radius2=HANDLE_RADIUS,
                          depth=rail_bottom - handle_top + 0.1)
    bmesh.ops.translate(bm, vec=(0.0, grip_y, (rail_bottom + handle_top - 0.1) / 2), verts=bm.verts)
    handle = finish(new_object("GripHandle", bm), D, 0.02)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.3, 0.3, 0.1), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, grip_y, rail_bottom - 0.03), verts=bm.verts)
    grip_base = finish(new_object("GripBase", bm), T, 0.02)
    grip = empty("Grip", (0.0, grip_y, -GRIP_DROP))

    # Shoulder version: mount block under the rear body.
    body_bottom = Z(332) * SIZE[2]
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.38, 0.8, MOUNT_DROP + 0.05), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, MOUNT_FROM_BUTT, body_bottom - (MOUNT_DROP - 0.05) / 2), verts=bm.verts)
    mount_block = finish(new_object("MountBlock", bm), D, 0.04)
    mount = empty("Mount", (0.0, MOUNT_FROM_BUTT, body_bottom - MOUNT_DROP))
    return common + [muzzle], [handle, grip_base, grip], [mount_block, mount]


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
    print("auto_cannon: %s, %d objects, %d triangles" % (os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    common, baton, shoulder = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "auto_cannon.blend"))
    export(os.path.join(OUT_DIR, "auto_cannon.glb"), common + baton)
    export(os.path.join(OUT_DIR, "auto_cannon_shoulder.glb"), common + shoulder)


main()
