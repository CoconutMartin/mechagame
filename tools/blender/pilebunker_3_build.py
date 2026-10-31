"""Builds Pile Bunker 3 (user design 2026-10-31: one long spike, tan upper housing, black collar with hex side
pads, a red and tan magazine box under the back, a jointed black mount arm behind).

Run (from the project root):
    blender -b --python tools/blender/pilebunker_3_build.py
Writes models/pilebunker_3/pilebunker_3.blend and pilebunker_3.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Shapes from the user's picture, models/guides/pilebunker_3_ref.png (3/4, front, side and top views; sizes are
estimated from the side view, about 0.027 m per pixel). All sizes below are in meters.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the back face of the housing, on the spike axis. The
back to the nose is 2.7 m, as the other Pile Bunkers (elbow to the front of the fist), so the same mount works.
Named pieces the weapon script uses (same names as pile_bunker.glb): Stake (empty, parent of the spike; it moves
along +Y), Drum (lamp glow on the magazine box), NoseRing (collar ring glow). Empties: Nose (front of the
collar), Mount.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "pilebunker_3")
NAME = "pilebunker_3"

## Front face of the collar (the Nose): back to nose length.
NOSE_Y = 2.7
## Spike length in front of the collar (base sleeve and the pointed blade) and its base radius.
SPIKE_LENGTH = 2.2
SPIKE_RADIUS = 0.23
## How far the spike rod goes back into the housing (it shows when the spike fires).
ROD_BACK = 1.6
## The jointed mount arm behind the housing (the picture's black arm).
WITH_MOUNT_ARM = True

MATERIALS = {
    # name: (sRGB color from the picture, roughness, metallic, emission)
    "pb3_tan": ((0.80, 0.72, 0.57), 0.6, 0.3, None),
    "pb3_dark": ((0.24, 0.24, 0.26), 0.55, 0.45, None),
    "pb3_black": ((0.12, 0.12, 0.13), 0.6, 0.4, None),
    "pb3_red": ((0.55, 0.13, 0.12), 0.6, 0.3, None),
    "pb3_steel": ((0.58, 0.56, 0.53), 0.3, 0.9, None),
    "pb3_glow": ((0.6, 0.35, 0.05), 0.5, 0.0, (1.0, 0.55, 0.1)),
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


def build_housing():
    """Tan upper housing with its top details, the black core along the spike, the collar and its hex pads."""
    T, D, K, L = "pb3_tan", "pb3_dark", "pb3_black", "pb3_glow"
    parts = []
    parts.append(block("Core", K, -0.22, 0.22, 0.0, 2.3, -0.3, 0.12, chamfer=0.07))
    parts.append(block("Housing", T, -0.27, 0.27, 0.0, 2.05, 0.08, 0.62, chamfer=0.1, bevel=0.025))
    # Slanted front of the housing toward the collar (side view).
    parts.append(wedge("HousingNose", T, -0.25, 0.25, [(2.05, 0.1), (2.05, 0.62), (2.3, 0.45), (2.3, 0.1)], bevel=0.02))
    parts.append(block("HousingSeam", K, -0.272, 0.272, 1.2, 1.23, 0.1, 0.6, bevel=0.0))
    parts.append(block("TopRail", D, -0.08, 0.08, 0.3, 1.1, 0.62, 0.67, bevel=0.008))
    parts.append(block("TopSlot", K, -0.05, 0.05, 0.45, 0.95, 0.665, 0.675, bevel=0.0))
    # Black sight block on the top front.
    parts.append(block("TopBlock", K, -0.12, 0.12, 1.55, 1.95, 0.6, 0.78, chamfer=0.04))
    # Side marks (thin dark strips).
    for side, x in (("L", -0.27), ("R", 0.27)):
        x0, x1 = (x - 0.005, x + 0.01) if x > 0 else (x - 0.01, x + 0.005)
        for i, (y0, y1, z0, z1) in enumerate(((0.25, 1.0, 0.5, 0.52), (0.25, 0.27, 0.3, 0.5), (1.4, 1.9, 0.5, 0.52),
                                              (1.6, 1.8, 0.25, 0.28))):
            parts.append(block(f"HousingMark{side}{i}", K, x0, x1, y0, y1, z0, z1, bevel=0.0))
    # Collar: black block with chamfers, a darker front plate and the hex pads on the sides.
    parts.append(block("Collar", K, -0.3, 0.3, 2.2, NOSE_Y - 0.06, -0.36, 0.36, chamfer=0.12, bevel=0.02))
    parts.append(block("CollarFront", D, -0.24, 0.24, NOSE_Y - 0.06, NOSE_Y, -0.28, 0.28, chamfer=0.1, bevel=0.01))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * 0.28, sx * 0.38))
        parts.append(hex_pad(f"HexPad{side}", D, x0, x1, 1.95, -0.08, 0.26))
        x0, x1 = sorted((sx * 0.38, sx * 0.41))
        parts.append(hex_pad(f"HexCap{side}", K, x0, x1, 1.95, -0.08, 0.14, bevel=0.0))
    bm = bmesh.new()
    ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=SPIKE_RADIUS + 0.04,
                                 radius2=SPIKE_RADIUS + 0.04, depth=0.03)
    bmesh.ops.rotate(bm, verts=ring["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, NOSE_Y + 0.005, 0.0), verts=ring["verts"])
    parts.append(finish(new_object("NoseRing", bm), L, 0.0))
    return parts


def build_magazine():
    """The box under the back: a red core, tan side slabs over its upper front, and a small lamp."""
    T, R, K, L = "pb3_tan", "pb3_red", "pb3_black", "pb3_glow"
    parts = []
    parts.append(block("MagazineNeck", K, -0.18, 0.18, 0.3, 1.3, -0.45, -0.25, bevel=0.01))
    parts.append(block("Magazine", R, -0.3, 0.3, 0.15, 1.45, -1.35, -0.42, chamfer=0.1, bevel=0.025))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * 0.29, sx * 0.34))
        parts.append(wedge(f"MagazineSlab{side}", T, x0, x1,
                           [(0.45, -0.4), (1.5, -0.4), (1.5, -1.15), (1.35, -1.3), (0.75, -1.3), (0.45, -1.0)],
                           bevel=0.02))
        x0, x1 = sorted((sx * 0.335, sx * 0.345))
        parts.append(block(f"MagazineSlabMark{side}", K, x0, x1, 0.9, 1.3, -0.62, -0.6, bevel=0.0))
        parts.append(block(f"MagazineSlabMark2{side}", K, x0, x1, 1.28, 1.3, -1.0, -0.62, bevel=0.0))
    parts.append(block("MagazineFront", T, -0.29, 0.29, 1.45, 1.52, -1.15, -0.45, bevel=0.01))
    parts.append(block("Drum", L, -0.08, 0.08, 1.52, 1.54, -0.6, -0.55, bevel=0.0))
    return parts


def build_mount_arm():
    """Jointed black arm behind the housing: a top link, a big joint, a down link, a low joint, a link forward."""
    D, K = "pb3_dark", "pb3_black"
    parts = []
    parts.append(block("ArmTopLink", K, -0.16, 0.16, -0.35, 0.2, 0.25, 0.6, chamfer=0.05))
    parts.append(cylinder_x("ArmJointTop", D, -0.4, 0.42, 0.22, 0.19))
    parts.append(cylinder_x("ArmJointTopCap", K, -0.4, 0.42, 0.12, 0.21, bevel=0.0))
    parts.append(block("ArmDownLink", K, -0.15, 0.15, -0.6, -0.22, -0.55, 0.42, chamfer=0.06))
    parts.append(cylinder_x("ArmJointLow", D, -0.42, -0.55, 0.19, 0.17))
    parts.append(block("ArmLowLink", K, -0.14, 0.14, -0.45, 0.25, -0.72, -0.42, chamfer=0.05))
    return parts


def build_spike():
    """The spike under one Stake empty at the collar front (rest); the empty moves along +Y to fire.
    A rod back into the housing, a sleeve, and a long six-sided blade to a sharp point."""
    S, D = "pb3_steel", "pb3_dark"
    stake = empty("Stake", (0.0, NOSE_Y, 0.0))
    parts = []
    parts.append(prism("SpikeRod", D, -ROD_BACK, 0.05, SPIKE_RADIUS * 0.7, SPIKE_RADIUS * 0.7, sides=12, bevel=0.0))
    parts.append(prism("SpikeSleeve", D, 0.0, 0.22, SPIKE_RADIUS + 0.02, SPIKE_RADIUS, sides=6, bevel=0.008))
    parts.append(prism("SpikeBlade", S, 0.22, SPIKE_LENGTH, SPIKE_RADIUS, 0.0, sides=6, bevel=0.0))
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
    objects = build_housing() + build_magazine() + (build_mount_arm() if WITH_MOUNT_ARM else []) + build_spike()
    objects.append(empty("Nose", (0.0, NOSE_Y, 0.0)))
    objects.append(empty("Mount", (0.0, 0.75, 0.0)))
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, NAME + ".blend"))
    export(os.path.join(OUT_DIR, NAME + ".glb"), objects)


main()
