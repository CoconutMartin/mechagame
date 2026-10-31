"""Builds Pile Bunker 4 (user design 2026-10-31: one spike inside three claws, red armor petals behind the
claws, tan inner sleeve, black core and a black rear bracket).

Run (from the project root):
    blender -b --python tools/blender/pilebunker_4_build.py
Writes models/pilebunker_4/pilebunker_4.blend and pilebunker_4.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Shapes from the user's picture, models/guides/pilebunker_4_ref.png (3/4, front, side and top views; sizes are
estimated from the side view, about 0.0095 m per pixel). All sizes below are in meters.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the back face of the core, on the spike axis. Named
pieces the weapon script uses (same names as pile_bunker.glb): Stake (empty, parent of the spike; it moves along
+Y), Drum (lamp glow on top), NoseRing (collar ring glow), Claw0 to Claw2 (empties at the claw hinges, parents of
the claws; the weapon script turns each one out from the spike axis to open it). Empties: Nose (front of the
collar), Mount.
Each claw and its red petal are built in a local frame with the claw on the +Z side, then turned about the
spike axis by CLAW_ANGLES (0 = up, 90 = the +X side, 180 = down).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "pilebunker_4")
NAME = "pilebunker_4"

## Front face of the collar (the Nose), where the spike comes out.
NOSE_Y = 2.6
## Spike: length in front of the collar, base radius, and how far its rod goes back into the core.
SPIKE_LENGTH = 2.4
SPIKE_RADIUS = 0.24
ROD_BACK = 1.6
## Claw places about the spike axis (degrees): upper right, upper left, down (the picture's 3/4 view).
CLAW_ANGLES = (60.0, -60.0, 180.0)
## Claw hinge place in the local frame (y along, z out from the axis).
HINGE_Y, HINGE_Z = 2.3, 0.47
## The closed claw outline in the side view (y, z out from the axis): from the hinge to the tip, which closes
## round the spike.
CLAW_OUTLINE = [(2.18, 0.62), (3.0, 0.58), (3.8, 0.38), (4.1, 0.27), (4.1, 0.18), (3.5, 0.22), (2.7, 0.32),
                (2.18, 0.33)]
CLAW_HALF_WIDTH = 0.12

MATERIALS = {
    # name: (sRGB color from the picture, roughness, metallic, emission)
    "pb4_tan": ((0.80, 0.72, 0.58), 0.6, 0.3, None),
    "pb4_red": ((0.60, 0.16, 0.14), 0.6, 0.3, None),
    "pb4_dark": ((0.24, 0.24, 0.26), 0.55, 0.45, None),
    "pb4_black": ((0.12, 0.12, 0.13), 0.6, 0.4, None),
    "pb4_steel": ((0.62, 0.61, 0.60), 0.3, 0.9, None),
    "pb4_glow": ((0.6, 0.35, 0.05), 0.5, 0.0, (1.0, 0.55, 0.1)),
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, emission = MATERIALS[name]
    color = tuple(srgb_to_linear(c) for c in color)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.0
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


def block(name, mat, x0, x1, y0, y1, z0, z1, chamfer=0.0, bevel=0.015):
    """Box from x0..x1 (side), y0..y1 (along), z0..z1 (up). Chamfer cuts the four edges along Y."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(x1 - x0, y1 - y0, z1 - z0), verts=bm.verts)
    bmesh.ops.translate(bm, vec=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=bm.verts)
    if chamfer > 0.0:
        along = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().y) > 0.99]
        bmesh.ops.bevel(bm, geom=along, offset=chamfer, segments=1, affect="EDGES")
    return finish(new_object(name, bm), mat, bevel)


def prism(name, mat, y0, y1, r0, r1, z=0.0, sides=8, bevel=0.01):
    """Prism or frustum along +Y from y0 (radius r0) to y1 (radius r1); 8 sides with a flat face on top."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r0, radius2=r1, depth=y1 - y0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / sides, 3, "Z"))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, (y0 + y1) / 2, z), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def wedge(name, mat, x0, x1, pts, bevel=0.012):
    """Flat plate across X from x0 to x1, outline pts = [(y, z), ...] in the side view."""
    bm = bmesh.new()
    left = [bm.verts.new((x0, y, z)) for y, z in pts]
    right = [bm.verts.new((x1, y, z)) for y, z in pts]
    n = len(pts)
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([left[i], left[j], right[j], right[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = location
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def hex_pad(name, mat, x0, x1, y, z, radius, bevel=0.01):
    """Six-sided pad across X from x0 to x1, centered at (y, z) in the side view."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=radius, depth=x1 - x0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=((x0 + x1) / 2, y, z), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def cylinder_x(name, mat, y, z, radius, half_width, sides=16, bevel=0.01):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=2 * half_width)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=(0.0, y, z), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def turned(obj, angle):
    """Turns an object built in the local frame (claw side +Z) about the spike axis (Y)."""
    obj.rotation_euler = (0.0, math.radians(angle), 0.0)
    return obj


def build_core():
    """Black core, the tan inner sleeve, the collar and the lamp."""
    T, K, D, L = "pb4_tan", "pb4_black", "pb4_dark", "pb4_glow"
    parts = []
    parts.append(block("Core", K, -0.26, 0.26, 0.0, 2.45, -0.26, 0.26, chamfer=0.08))
    parts.append(block("Sleeve", T, -0.34, 0.34, 0.25, 2.1, -0.34, 0.34, chamfer=0.14, bevel=0.025))
    parts.append(block("SleeveSeam", K, -0.345, 0.345, 1.1, 1.13, -0.3, 0.3, bevel=0.0))
    parts.append(block("TopSlot", K, -0.04, 0.04, 0.5, 1.6, 0.33, 0.35, bevel=0.0))
    parts.append(prism("Collar", D, 2.3, NOSE_Y, 0.3, 0.26, sides=8, bevel=0.015))
    parts.append(block("Drum", L, -0.06, 0.06, 1.75, 1.85, 0.33, 0.36, bevel=0.0))
    bm = bmesh.new()
    ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=SPIKE_RADIUS + 0.03,
                                 radius2=SPIKE_RADIUS + 0.03, depth=0.03)
    bmesh.ops.rotate(bm, verts=ring["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, NOSE_Y + 0.005, 0.0), verts=ring["verts"])
    parts.append(finish(new_object("NoseRing", bm), L, 0.0))
    return parts


def build_petal(i, angle):
    """Red armor petal behind a claw, with a tan edge plate and the black hinge block (body, not moving)."""
    R, T, K, D = "pb4_red", "pb4_tan", "pb4_black", "pb4_dark"
    parts = []
    parts.append(wedge(f"Petal{i}", R, -0.3, 0.3,
                       [(0.15, 0.36), (0.15, 0.62), (0.45, 0.78), (1.55, 0.78), (2.1, 0.62), (2.1, 0.36)], bevel=0.03))
    parts.append(block(f"PetalEdge{i}", T, -0.32, 0.32, 1.55, 2.12, 0.36, 0.55, chamfer=0.05, bevel=0.015))
    parts.append(block(f"PetalSeam{i}", K, -0.305, 0.305, 0.9, 0.93, 0.4, 0.77, bevel=0.0))
    parts.append(block(f"PetalMark{i}", K, -0.06, 0.06, 0.5, 0.8, 0.775, 0.785, bevel=0.0))
    parts.append(block(f"HingeBlock{i}", K, -0.2, 0.2, 2.05, 2.45, 0.3, 0.6, chamfer=0.06))
    parts.append(cylinder_x(f"HingeCap{i}", D, HINGE_Y, HINGE_Z, 0.09, 0.22, sides=12))
    return [turned(p, angle) for p in parts]


def build_claw(i, angle):
    """One claw under its ClawN empty at the hinge; the geometry is relative to the hinge."""
    T, K = "pb4_tan", "pb4_black"
    pivot = empty(f"Claw{i}", (0.0, HINGE_Y, 0.0))
    pivot.location = Matrix.Rotation(math.radians(angle), 3, "Y") @ Vector((0.0, HINGE_Y, HINGE_Z))
    pivot.rotation_euler = (0.0, math.radians(angle), 0.0)
    outline = [(y - HINGE_Y, z - HINGE_Z) for y, z in CLAW_OUTLINE]
    parts = [wedge(f"ClawArm{i}", T, -CLAW_HALF_WIDTH, CLAW_HALF_WIDTH, outline, bevel=0.02)]
    parts.append(block(f"ClawKnuckle{i}", K, -0.14, 0.14, -0.15, 0.25, -0.12, 0.17, chamfer=0.05))
    parts.append(block(f"ClawMark{i}", K, -0.125, 0.125, 0.9, 0.93, 0.0, 0.12, bevel=0.0))
    for p in parts:
        p.parent = pivot
    return [pivot] + parts


def build_bracket():
    """Black rear bracket: a block behind the core, side lugs with pin caps, and a loop on top."""
    K, D = "pb4_black", "pb4_dark"
    parts = []
    parts.append(block("BracketBack", K, -0.32, 0.32, -0.4, 0.15, -0.45, 0.45, chamfer=0.1))
    parts.append(block("BracketLoopBack", K, -0.14, 0.14, -0.55, -0.3, 0.35, 0.95, chamfer=0.04))
    parts.append(block("BracketLoopTop", K, -0.14, 0.14, -0.55, 0.45, 0.8, 0.95, chamfer=0.04))
    parts.append(block("BracketLoopFront", K, -0.14, 0.14, 0.3, 0.45, 0.6, 0.95, chamfer=0.03))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * 0.3, sx * 0.48))
        parts.append(block(f"BracketLug{side}", K, x0, x1, -0.3, 0.1, -0.35, -0.05, chamfer=0.04))
        x0, x1 = sorted((sx * 0.48, sx * 0.51))
        parts.append(cylinder_x(f"BracketPin{side}", D, -0.1, -0.2, 0.07, 0.015, sides=10, bevel=0.0))
        parts[-1].location.x = sx * 0.495
    return parts


def build_spike():
    """The spike under one Stake empty at the collar front (rest); the empty moves along +Y to fire."""
    S, D = "pb4_steel", "pb4_dark"
    stake = empty("Stake", (0.0, NOSE_Y, 0.0))
    parts = []
    parts.append(prism("SpikeRod", D, -ROD_BACK, 0.05, SPIKE_RADIUS * 0.7, SPIKE_RADIUS * 0.7, sides=12, bevel=0.0))
    parts.append(prism("SpikeBlade", S, 0.0, SPIKE_LENGTH, SPIKE_RADIUS, 0.0, sides=6, bevel=0.0))
    for obj in parts:
        obj.parent = stake
    return [stake] + parts


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
    print("%s: %s, %d objects, %d triangles" % (NAME, os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build_core() + build_bracket() + build_spike()
    for i, angle in enumerate(CLAW_ANGLES):
        objects += build_petal(i, angle) + build_claw(i, angle)
    objects.append(empty("Nose", (0.0, NOSE_Y, 0.0)))
    objects.append(empty("Mount", (0.0, 0.75, 0.0)))
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, NAME + ".blend"))
    export(os.path.join(OUT_DIR, NAME + ".glb"), objects)


main()
