"""Builds Pile Bunker 5, a shield type Pile Bunker (mock-up, user request 2026-10-31: "mockup a shield type pile
bunker"; no picture). A long forearm shield with a pointed front, the pile bunker body behind it, and the stake
coming out of the shield's pointed front.

Run (from the project root):
    blender -b --python tools/blender/pilebunker_5_build.py
Writes models/pilebunker_5/pilebunker_5.blend and pilebunker_5.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Axes: Blender +Y = forward (Godot -Z), +Z = up, +X = the shield's face (the outer side of the arm). Origin: the
back of the body, on the stake axis. The shield runs from behind the elbow (-0.5 m) to its pointed front, where the
stake comes out (the Nose, 3.0 m). The shield is thick (0.26 to 0.44 m) with a ridge along its middle. Named pieces the weapon script uses (same names as pile_bunker.glb): Stake
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
## The shield (user 2026-10-31: "beautify it and put some meat on the shield section"): a thick plate with a
## ridge along its middle (the face slopes from RIDGE_X at z = 0 to EDGE_X at the top and bottom edges), from its
## back face SHIELD_X0. Outline in the side view (y, z), pointed at the front; HALF is the upper half (z >= 0).
SHIELD_X0 = 0.3
EDGE_X, RIDGE_X = 0.56, 0.74
SHIELD_HALF = [(-0.5, 0.0), (-0.5, 0.82), (-0.1, 1.05), (2.15, 1.05), (3.05, 0.3), (3.05, 0.0)]
## The raised face plate on the ridge (thickness FACE_T) and its upper-half outline.
FACE_T = 0.07
FACE_HALF = [(-0.15, 0.0), (-0.15, 0.7), (0.1, 0.86), (2.0, 0.86), (2.72, 0.24), (2.72, 0.0)]
## Rim along the top and bottom edges: thickness and how far it turns back toward the arm (degrees).
RIM_T = 0.13
RIM_DEG = 32.0

MATERIALS = {
    # name: (sRGB color, roughness, metallic, emission)
    "pb5_armor": ((0.36, 0.38, 0.40), 0.55, 0.5, None),
    "pb5_plate": ((0.70, 0.66, 0.56), 0.6, 0.3, None),
    "pb5_red": ((0.60, 0.16, 0.14), 0.6, 0.3, None),
    "pb5_black": ((0.12, 0.12, 0.13), 0.6, 0.4, None),
    "pb5_dark": ((0.22, 0.23, 0.25), 0.55, 0.5, None),
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


def face_x(z):
    """Front face of the shield plate at height z (the ridge slope)."""
    return RIDGE_X + (EDGE_X - RIDGE_X) * min(abs(z) / 1.05, 1.0)


def sloped_plate(name, mat, x_back, half, lift, bevel=0.015, flip=False, y_shift=0.0):
    """A plate from x_back to the shield face plus lift, over the upper-half outline half (or the lower half with
    flip). Its front follows the ridge slope, so it lies on the shield face."""
    sz = -1.0 if flip else 1.0
    pts = [(y + y_shift, sz * z) for y, z in half]
    if flip:
        pts = list(reversed(pts))
    bm = bmesh.new()
    back = [bm.verts.new((x_back, y, z)) for y, z in pts]
    front = [bm.verts.new((face_x(z) + lift, y, z)) for y, z in pts]
    n = len(pts)
    bm.faces.new(list(reversed(back)))
    bm.faces.new(front)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([back[i], back[j], front[j], front[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def build_shield():
    """The shield: the ridged main plate, thick rims bent back along the top and bottom, the face plate with its
    seams, red bands, three ribs, a guard round the pointed front, the boss, lamps, bolts, and the stake port."""
    A, P, R, K, D, L = "pb5_armor", "pb5_plate", "pb5_red", "pb5_black", "pb5_dark", "pb5_glow"
    parts = []
    parts.append(sloped_plate("ShieldUpper", A, SHIELD_X0, SHIELD_HALF, 0.0, bevel=0.04))
    parts.append(sloped_plate("ShieldLower", A, SHIELD_X0, SHIELD_HALF, 0.0, bevel=0.04, flip=True))
    # Thick rims along the straight top and bottom edges, turned back toward the arm, with end caps.
    for side, sz in (("Top", 1.0), ("Bottom", -1.0)):
        rim = block(f"Rim{side}", A, -0.42, 0.0, -0.1, 2.15, -RIM_T / 2, RIM_T / 2, chamfer=0.03, bevel=0.02)
        rim.matrix_world = Matrix.Translation((EDGE_X, 0.0, sz * 1.0)) @ Matrix.Rotation(math.radians(-sz * RIM_DEG), 4, "Y")
        parts.append(rim)
        trim = block(f"RimTrim{side}", K, -0.02, 0.02, 0.0, 2.05, -RIM_T / 2 - 0.01, RIM_T / 2 + 0.01, bevel=0.0)
        trim.matrix_world = Matrix.Translation((EDGE_X, 0.0, sz * 1.0)) @ Matrix.Rotation(math.radians(-sz * RIM_DEG), 4, "Y")
        parts.append(trim)
        parts.append(block(f"RimCap{side}", D, EDGE_X - 0.36, EDGE_X + 0.03, -0.42, -0.1, sz * 0.86 - 0.12,
                           sz * 0.86 + 0.12, chamfer=0.04))
    # Raised face plate in two halves (the ridge line between them shows as a crease), with a seam across.
    parts.append(sloped_plate("FaceUpper", P, EDGE_X - 0.05, FACE_HALF, FACE_T, bevel=0.02))
    parts.append(sloped_plate("FaceLower", P, EDGE_X - 0.05, FACE_HALF, FACE_T, bevel=0.02, flip=True))
    for i, y in enumerate((0.95, 1.75)):
        parts.append(sloped_plate(f"FaceSeam{i}", K, EDGE_X - 0.04, [(y, 0.0), (y, 0.84), (y + 0.035, 0.84),
                                                                       (y + 0.035, 0.0)], FACE_T + 0.004, bevel=0.0))
        parts.append(sloped_plate(f"FaceSeamLow{i}", K, EDGE_X - 0.04, [(y, 0.0), (y, 0.84), (y + 0.035, 0.84),
                                                                          (y + 0.035, 0.0)], FACE_T + 0.004, bevel=0.0,
                                  flip=True))
    # Red bands near the top and bottom edges of the face plate.
    band = [(0.15, 0.62), (0.15, 0.74), (1.6, 0.74), (1.6, 0.62)]
    parts.append(sloped_plate("BandUpper", R, EDGE_X, band, FACE_T + 0.012, bevel=0.0))
    parts.append(sloped_plate("BandLower", R, EDGE_X, band, FACE_T + 0.012, bevel=0.0, flip=True))
    # Ribs: dark raised bars across the back part of the face (over the arm).
    for i, y in enumerate((0.25, 0.5)):
        rib = [(y, 0.0), (y, 0.5), (y + 0.1, 0.5), (y + 0.1, 0.0)]
        parts.append(sloped_plate(f"Rib{i}", D, EDGE_X, rib, FACE_T + 0.05, bevel=0.01))
        parts.append(sloped_plate(f"RibLow{i}", D, EDGE_X, rib, FACE_T + 0.05, bevel=0.01, flip=True))
    # Guard plates along the two slanted front edges, round the stake port.
    guard = [(2.15, 0.9), (2.3, 1.05), (3.05, 0.3), (3.05, 0.12), (2.85, 0.3)]
    parts.append(sloped_plate("GuardUpper", D, SHIELD_X0 - 0.04, guard, 0.06, bevel=0.015))
    parts.append(sloped_plate("GuardLower", D, SHIELD_X0 - 0.04, guard, 0.06, bevel=0.015, flip=True))
    # Boss on the ridge and the lamps (Drum).
    parts.append(hex_pad("Boss", K, RIDGE_X + FACE_T - 0.02, RIDGE_X + FACE_T + 0.12, 1.35, 0.0, 0.24))
    parts.append(hex_pad("BossCap", D, RIDGE_X + FACE_T + 0.12, RIDGE_X + FACE_T + 0.15, 1.35, 0.0, 0.13, bevel=0.0))
    parts.append(block("Drum", L, RIDGE_X + FACE_T - 0.01, RIDGE_X + FACE_T + 0.012, 2.15, 2.45, -0.035, 0.035,
                       bevel=0.0))
    for i, (y, z) in enumerate(((0.0, 0.62), (0.0, -0.62), (1.95, 0.62), (1.95, -0.62), (2.5, 0.3), (2.5, -0.3),
                                (1.0, 0.35), (1.0, -0.35))):
        parts.append(cylinder_x(f"Bolt{i}", K, y, z, 0.035, 0.02, sides=8, bevel=0.0))
        parts[-1].location.x = face_x(z) + FACE_T + 0.01
    # Stake port at the pointed front: a black collar through the shield tip with the glow ring.
    parts.append(prism("PortCollar", K, 2.6, NOSE_Y, 0.28, 0.23, sides=8, bevel=0.015))
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
    parts.append(block("Core", K, -0.26, SHIELD_X0 + 0.02, 0.0, 2.65, -0.3, 0.3, chamfer=0.08))
    parts.append(prism("Housing", A, 0.2, 2.2, 0.36, 0.36, sides=8, bevel=0.02))
    for i, y in enumerate((0.5, 1.8)):
        parts.append(block(f"Brace{i}", K, 0.0, SHIELD_X0 + 0.02, y, y + 0.2, -0.7, 0.7, chamfer=0.04))
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
