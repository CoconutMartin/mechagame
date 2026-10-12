"""Builds the Small Shield (user request 2026-10-12: the small shield of the user's arm drawing) and
exports it.

Run (from the project root):
    blender -b --python tools/blender/small_shield_build.py
Writes models/small_shield/small_shield.blend and small_shield.glb. The script starts from an empty
file, so hand edits in the .blend are lost when it runs again.

A rectangular arm shield that covers the forearm and the elbow: 3.4 m long, 2.2 m wide, a chamfered
olive plate with a dark raised rim, two cross ribs, a round center boss, yellow hazard marks, and a
mount bracket on the back. Colors like the SMG (olive and black, yellow marks).

Axes: Blender +Z = the long side (Godot +Y), +X = the width, +Y = the front face (Godot -Z), so the
scene places it like the Hex Shield (long side along the forearm, front face outward). Origin: the plate
center.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "small_shield")

## Plate size (m): long side, width, thickness.
LENGTH = 3.4
WIDTH = 2.2
THICK = 0.18

MATERIALS = {
    "shield_olive": ((0.15, 0.165, 0.11), 0.65, 0.1),
    "shield_black": ((0.022, 0.023, 0.025), 0.55, 0.35),
    "shield_yellow": ((0.85, 0.45, 0.03), 0.5, 0.0),
}
O, K, YL = "shield_olive", "shield_black", "shield_yellow"


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


def box(name, mat, size, center, chamfer=0.0, bevel=0.015):
    """Box of size (x, y, z) at center; chamfer cuts the four edges along the thickness (Y)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if chamfer > 0.0:
        edges = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().y) > 0.99]
        bmesh.ops.bevel(bm, geom=edges, offset=chamfer, segments=1, affect="EDGES")
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, mat, bevel)


def disc(name, mat, radius, depth, center, sides=12):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius * 0.8, depth=depth)
    # Cone along Z: turn it to face front (+Y).
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, mat, 0.01)


def build():
    parts = []
    front = THICK / 2
    parts.append(box("Plate", O, (WIDTH, THICK, LENGTH), (0, 0, 0), chamfer=0.3))
    # Raised rim along the four sides (front face).
    rim = 0.16
    for name, size, center in (
            ("RimTop", (WIDTH - 0.5, 0.08, rim), (0, front + 0.03, LENGTH / 2 - rim / 2 - 0.05)),
            ("RimBottom", (WIDTH - 0.5, 0.08, rim), (0, front + 0.03, -LENGTH / 2 + rim / 2 + 0.05)),
            ("RimLeft", (rim, 0.08, LENGTH - 0.5), (-WIDTH / 2 + rim / 2 + 0.05, front + 0.03, 0)),
            ("RimRight", (rim, 0.08, LENGTH - 0.5), (WIDTH / 2 - rim / 2 - 0.05, front + 0.03, 0))):
        parts.append(box(name, K, size, center, bevel=0.01))
    # Two cross ribs and the center boss.
    for i, z in enumerate((LENGTH * 0.25, -LENGTH * 0.25)):
        parts.append(box(f"Rib{i}", K, (WIDTH - 0.6, 0.06, 0.12), (0, front + 0.02, z), bevel=0.008))
    parts.append(disc("Boss", K, 0.32, 0.14, (0, front + 0.06, 0)))
    # Yellow hazard marks near the two ends.
    for i, z in enumerate((LENGTH * 0.38, -LENGTH * 0.38)):
        for j, x in enumerate((-0.45, 0.45)):
            parts.append(box(f"Mark{i}{j}", YL, (0.36, 0.04, 0.09), (x, front + 0.01, z), bevel=0.0))
    # Mount bracket on the back (it clamps on the forearm armor).
    parts.append(box("Bracket", K, (0.9, 0.22, 1.6), (0, -front - 0.1, 0), chamfer=0.08))
    return parts


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True)
    tris = 0
    for obj in objects:
        ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        m = ev.to_mesh()
        m.calc_loop_triangles()
        tris += len(m.loop_triangles)
        ev.to_mesh_clear()
    print("small_shield: %s, %d objects, %d triangles" % (os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "small_shield.blend"))
    export(os.path.join(OUT_DIR, "small_shield.glb"), objects)


main()
