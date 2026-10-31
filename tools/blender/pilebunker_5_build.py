"""Builds Pile Bunker 5, a shield type Pile Bunker (mock-up, user request 2026-10-31: "mockup a shield type pile
bunker"; no picture). A long forearm shield with a pointed front, the pile bunker body behind it, and the stake
coming out of the shield's pointed front.

Run (from the project root):
    blender -b --python tools/blender/pilebunker_5_build.py
Writes models/pilebunker_5/pilebunker_5.blend and pilebunker_5.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = the shield's face (the outer side of the arm). Origin: the
back of the body, on the stake axis. The shield runs from behind the elbow (-0.5 m) to its pointed front, where the
stake comes out (the Nose, 3.0 m). Named pieces the weapon script uses (same names as pile_bunker.glb): Stake
(empty, parent of the stake; it moves along +Y), Drum (lamps on the shield face), NoseRing (ring glow at the
stake port). Empties: Nose, Mount.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NAME = "pilebunker_5"
OUT_DIR = os.path.join(ROOT, "models", NAME)

## Stake port at the shield's pointed front (the Nose).
NOSE_Y = 3.0
## Stake: length in front of the port, base radius, and how far its rod goes back into the body.
SPIKE_LENGTH = 1.5
SPIKE_RADIUS = 0.17
ROD_BACK = 1.8
## The shield plate: its back and front (x) and its outline in the side view (y, z), pointed at the front.
SHIELD_X0, SHIELD_X1 = 0.34, 0.46
SHIELD_OUTLINE = [(-0.5, 0.8), (0.0, 1.0), (2.1, 1.0), (3.05, 0.28), (3.05, -0.28), (2.1, -1.0), (0.0, -1.0),
                  (-0.5, -0.8)]
## Bent rims along the top and the bottom edge (turned back toward the arm).
RIM_DEG = 30.0

MATERIALS = {
    # name: (sRGB color, roughness, metallic, emission)
    "pb5_armor": ((0.36, 0.38, 0.40), 0.55, 0.5, None),
    "pb5_plate": ((0.70, 0.66, 0.56), 0.6, 0.3, None),
    "pb5_red": ((0.60, 0.16, 0.14), 0.6, 0.3, None),
    "pb5_black": ((0.12, 0.12, 0.13), 0.6, 0.4, None),
    "pb5_steel": ((0.62, 0.61, 0.60), 0.3, 0.9, None),
    "pb5_glow": ((0.6, 0.35, 0.05), 0.5, 0.0, (1.0, 0.55, 0.1)),
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


def build_shield():
    """The shield: the main plate, the bent top and bottom rims, a raised face plate, red stripes, lamps, the
    stake port with its ring, and bolts."""
    A, P, R, K, L = "pb5_armor", "pb5_plate", "pb5_red", "pb5_black", "pb5_glow"
    parts = []
    parts.append(wedge("ShieldPlate", A, SHIELD_X0, SHIELD_X1, SHIELD_OUTLINE, bevel=0.03))
    # Rims: thin plates along the straight top and bottom edges, turned back toward the arm.
    for side, sz in (("Top", 1.0), ("Bottom", -1.0)):
        rim = block(f"Rim{side}", A, -0.3, 0.0, 0.0, 2.1, -0.06, 0.06, chamfer=0.0, bevel=0.015)
        bm_shift = Matrix.Translation((SHIELD_X1, 0.0, sz * 1.0))
        rim.matrix_world = bm_shift @ Matrix.Rotation(math.radians(-sz * RIM_DEG), 4, "Y")
        parts.append(rim)
    # Raised face plate with the same pointed front, smaller.
    face = [(0.1, 0.78), (2.0, 0.78), (2.7, 0.25), (2.7, -0.25), (2.0, -0.78), (0.1, -0.78)]
    parts.append(wedge("FacePlate", P, SHIELD_X1, SHIELD_X1 + 0.06, face, bevel=0.02))
    parts.append(block("FaceSeam", K, SHIELD_X1 + 0.055, SHIELD_X1 + 0.065, 1.2, 1.23, -0.76, 0.76, bevel=0.0))
    for i, z in enumerate((0.55, -0.55)):
        parts.append(block(f"Stripe{i}", R, SHIELD_X1 + 0.055, SHIELD_X1 + 0.07, 0.3, 1.1, z - 0.06, z + 0.06,
                           bevel=0.0))
    # Center boss and two lamps (Drum) on the face.
    parts.append(hex_pad("Boss", K, SHIELD_X1 + 0.06, SHIELD_X1 + 0.16, 1.65, 0.0, 0.26))
    parts.append(block("Drum", L, SHIELD_X1 + 0.06, SHIELD_X1 + 0.075, 2.25, 2.45, -0.04, 0.04, bevel=0.0))
    for i, (y, z) in enumerate(((0.3, 0.88), (0.3, -0.88), (1.9, 0.88), (1.9, -0.88), (2.6, 0.3), (2.6, -0.3))):
        parts.append(cylinder_x(f"Bolt{i}", K, y, z, 0.035, 0.02, sides=8, bevel=0.0))
        parts[-1].location.x = SHIELD_X1 + 0.02
    # Stake port at the pointed front: a black collar through the shield tip with the glow ring.
    parts.append(prism("PortCollar", K, 2.6, NOSE_Y, 0.26, 0.22, sides=8, bevel=0.015))
    bm = bmesh.new()
    ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=16, radius1=SPIKE_RADIUS + 0.03,
                                 radius2=SPIKE_RADIUS + 0.03, depth=0.03)
    bmesh.ops.rotate(bm, verts=ring["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, NOSE_Y + 0.005, 0.0), verts=ring["verts"])
    parts.append(finish(new_object("NoseRing", bm), L, 0.0))
    return parts


def build_body():
    """The pile bunker body behind the shield: a core along the stake, a cylinder housing, and two braces."""
    A, K = "pb5_armor", "pb5_black"
    parts = []
    parts.append(block("Core", K, -0.26, SHIELD_X0, 0.0, 2.65, -0.3, 0.3, chamfer=0.08))
    parts.append(prism("Housing", A, 0.2, 2.2, 0.36, 0.36, sides=8, bevel=0.02))
    for i, y in enumerate((0.5, 1.8)):
        parts.append(block(f"Brace{i}", K, 0.0, SHIELD_X0, y, y + 0.2, -0.7, 0.7, chamfer=0.04))
    parts.append(block("BackCap", K, -0.3, 0.3, -0.15, 0.05, -0.32, 0.32, chamfer=0.08))
    return parts


def build_spike():
    """The stake under one Stake empty at the port (rest); the empty moves along +Y to fire."""
    S, K = "pb5_steel", "pb5_black"
    stake = empty("Stake", (0.0, NOSE_Y, 0.0))
    parts = [prism("SpikeRod", K, -ROD_BACK, 0.05, SPIKE_RADIUS * 0.7, SPIKE_RADIUS * 0.7, sides=12, bevel=0.0),
             prism("SpikeBlade", S, 0.0, SPIKE_LENGTH, SPIKE_RADIUS, 0.0, sides=6, bevel=0.0)]
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
    objects = build_shield() + build_body() + build_spike()
    objects.append(empty("Nose", (0.0, NOSE_Y, 0.0)))
    objects.append(empty("Mount", (0.0, 0.75, 0.0)))
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, NAME + ".blend"))
    export(os.path.join(OUT_DIR, NAME + ".glb"), objects)


main()
