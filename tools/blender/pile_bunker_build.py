"""Builds the Pile Bunker (user design 2026-10-26: twin stakes, magazine box on top, forearm bracket).

Run (from the project root):
    blender -b --python tools/blender/pile_bunker_build.py
Writes models/pile_bunker/pile_bunker.blend and pile_bunker.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Shapes from the user's picture, models/guides/pile_bunker_ref.png (one 3/4 view, so the sizes are
estimated, not traced). All sizes below are in meters before SIZE.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the back face of the body, halfway between the
two stake axes. The bracket is on the -X side (it holds the forearm). Named pieces the weapon script
uses: Stake (empty, parent of both stakes; it moves along +Y), Drum (side port glow), NoseRing (sleeve
ring glow). Empties: Nose (front of the sleeves), Mount (the forearm axis in the bracket).
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "pile_bunker")

## Size after the design (all parts): 0.8 gives about 4.2 m from the back to the stake tips.
SIZE = 0.8
## Length of the body and the bracket (not the stakes) after SIZE (user request 2026-10-26): the body
## goes from the elbow to the front of the fist (2.7 m), so only the stakes stick out past the hand.
BODY_LENGTH = 0.854
## Height of the two stake axes above and under the body center.
STAKE_Z = 0.25
## Front face of the sleeves (the Nose).
NOSE_Y = 3.95
## Stake rod length (it stays inside the front housing and the middle tube; a longer rod shows through
## the skirt cut-out; it is not shortened by BODY_LENGTH) and how far the rod shows in front of the sleeves.
ROD_LENGTH = 1.9
ROD_SHOWN = 0.25
## Forearm axis in the bracket (x, z).
MOUNT_X, MOUNT_Z = -0.8, -0.35
## The forearm bracket of the picture. Off since 2026-10-26 (user choice): the game hangs the Pile Bunker
## upside down under the forearm, where the bracket would go into the forearm armor.
WITH_BRACKET = False

MATERIALS = {
    # name: (color, roughness, metallic, emission)
    "pile_bunker_grey": ((0.20, 0.21, 0.23), 0.55, 0.6, None),
    "pile_bunker_dark": ((0.10, 0.105, 0.115), 0.6, 0.5, None),
    "pile_bunker_steel": ((0.30, 0.31, 0.33), 0.35, 0.9, None),
    "pile_bunker_bore": ((0.01, 0.01, 0.012), 0.7, 0.2, None),
    "pile_bunker_glow": ((0.35, 0.12, 0.02), 0.5, 0.0, (1.0, 0.35, 0.05)),
}


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, emission = MATERIALS[name]
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


def cylinder(name, mat, center, radius, depth, axis="Y", sides=24, radius2=None, bevel=0.01):
    """Cylinder (or cone with radius2) along an axis; for Y the radius2 end is at +Y."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    if axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    elif axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
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


def build_body():
    G, D, S, B, L = "pile_bunker_grey", "pile_bunker_dark", "pile_bunker_steel", "pile_bunker_bore", "pile_bunker_glow"
    parts = []
    # Magazine box on top at the back: a long chamfered box, a rail with a button on top, small
    # plates and a round port on the side.
    parts.append(block("MagazineBox", G, -0.33, 0.33, 0.0, 1.45, 0.1, 0.95, chamfer=0.1))
    parts.append(block("MagazineFrontCap", G, -0.3, 0.3, 1.45, 1.58, 0.15, 0.9, chamfer=0.08))
    parts.append(block("MagazineRail", D, -0.12, 0.12, 0.15, 1.3, 0.95, 1.0, bevel=0.01))
    parts.append(block("MagazineRailBar", G, -0.07, 0.07, 0.25, 1.1, 1.0, 1.04, bevel=0.008))
    parts.append(cylinder("MagazineButton", G, (0.0, 0.9, 1.04), 0.07, 0.07, axis="Z", sides=16))
    parts.append(block("MagazineSeam", D, -0.335, 0.335, 0.55, 0.58, 0.12, 0.93, bevel=0.0))
    for i, y in enumerate((0.25, 0.85)):
        parts.append(block(f"MagazinePlate{i}", D, -0.345, -0.33, y, y + 0.12, 0.6, 0.72, bevel=0.0))
    parts.append(block("MagazineLatch", D, -0.345, -0.33, 1.1, 1.2, 0.3, 0.55, bevel=0.0))
    parts.append(cylinder("DrumBoss", G, (-0.37, 0.45, 0.42), 0.12, 0.1, axis="X", sides=20))
    parts.append(cylinder("Drum", L, (-0.42, 0.45, 0.42), 0.06, 0.02, axis="X", sides=20, bevel=0.0))
    # Step block between the magazine and the middle body.
    parts.append(block("ShoulderBlock", G, -0.27, 0.27, 1.45, 1.85, -0.05, 0.62, chamfer=0.08))
    # Lower back body under the magazine (the bracket comes out of its -X side).
    parts.append(block("LowerBack", G, -0.28, 0.28, 0.1, 1.45, -0.55, 0.1, chamfer=0.06))
    # Middle body: the upper tube and a lower skirt that rises toward the back.
    parts.append(block("MidTube", G, -0.22, 0.22, 1.85, 2.6, 0.02, 0.46, chamfer=0.07))
    parts.append(wedge("MidSkirt", G, -0.24, 0.24,
                       [(1.45, -0.55), (2.6, -0.55), (2.6, -0.02), (2.15, -0.02), (1.75, -0.3), (1.45, -0.3)]))
    parts.append(block("MidCollar", G, -0.31, 0.31, 2.6, 2.88, -0.5, 0.5, chamfer=0.08))
    # Front housing over both stakes, with the split line and the side lug.
    parts.append(block("FrontUpper", G, -0.33, 0.33, 2.88, 3.62, 0.015, 0.52, chamfer=0.1))
    parts.append(block("FrontLower", G, -0.33, 0.33, 2.88, 3.62, -0.52, -0.015, chamfer=0.1))
    parts.append(block("FrontSplit", D, -0.31, 0.31, 2.9, 3.6, -0.015, 0.015, bevel=0.0))
    parts.append(block("SideLug", D, -0.37, -0.33, 3.0, 3.22, -0.14, 0.14, bevel=0.008))
    parts.append(cylinder("SideLugHole", B, (-0.375, 3.11, 0.0), 0.05, 0.02, axis="X", sides=12, bevel=0.0))
    for i, z in enumerate((-0.18, 0.18)):
        parts.append(block(f"SideLugTab{i}", D, -0.36, -0.33, 3.06 if i else 3.16, 3.1 if i else 3.2,
                           z - 0.05, z + 0.05, bevel=0.0))
    for side, z in (("Upper", STAKE_Z), ("Lower", -STAKE_Z)):
        parts.append(cylinder(f"FrontPin{side}", D, (-0.34, 3.5, z), 0.025, 0.06, axis="X", sides=10, bevel=0.0))
        # Round sleeve for each stake, with the glow ring at the front.
        parts.append(cylinder(f"Sleeve{side}", G, (0.0, 3.62 + (NOSE_Y - 0.02 - 3.62) / 2, z), 0.17,
                              NOSE_Y - 0.02 - 3.62, sides=24))
        parts.append(cylinder(f"SleeveBore{side}", B, (0.0, NOSE_Y - 0.01, z), 0.1, 0.02, sides=16, bevel=0.0))
    # One glow mesh for both sleeve rings (the weapon script lights one NoseRing).
    bm = bmesh.new()
    for z in (STAKE_Z, -STAKE_Z):
        ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=0.175, radius2=0.175, depth=0.04)
        bmesh.ops.rotate(bm, verts=ring["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
        bmesh.ops.translate(bm, vec=(0.0, NOSE_Y - 0.03, z), verts=ring["verts"])
    parts.append(finish(new_object("NoseRing", bm), L, 0.0))
    return parts


def build_bracket():
    """Forearm bracket on the -X side under the magazine: an L plate with a slot, two arms and posts."""
    G, D = "pile_bunker_grey", "pile_bunker_dark"
    parts = []
    y0, y1 = 0.3, 1.25
    x_out = MOUNT_X - 0.4
    parts.append(block("BracketTopArm", G, x_out, -0.28, y0, y1, 0.0, 0.14, chamfer=0.04))
    parts.append(block("BracketBottomArm", G, x_out, -0.28, y0, y1, -0.84, -0.68, chamfer=0.04))
    parts.append(block("BracketPlate", G, -0.4, -0.28, y0 + 0.05, y1 - 0.05, -0.68, 0.0, bevel=0.01))
    parts.append(block("BracketSlot", D, -0.42, -0.39, y0 + 0.2, y1 - 0.2, -0.44, -0.36, bevel=0.0))
    # Outer posts with a gap between them (the picture's open frame).
    for i, (ya, yb) in enumerate(((y0, y0 + 0.22), (y1 - 0.22, y1))):
        parts.append(block(f"BracketPost{i}", G, x_out, x_out + 0.16, ya, yb, -0.68, 0.0, chamfer=0.03))
    parts.append(cylinder("BracketPegFront", D, (x_out + 0.08, y0 + 0.11, 0.24), 0.06, 0.2, axis="Z", sides=16))
    parts.append(cylinder("BracketPegBack", D, (x_out + 0.08, y1 - 0.11, 0.2), 0.05, 0.12, axis="Z", sides=16))
    parts.append(cylinder("BracketFoot", D, (x_out + 0.08, y0 + 0.11, -0.92), 0.07, 0.16, axis="Z", sides=16))
    return parts


def build_stakes(nose_y):
    """Both stakes under one Stake empty at the rod front (rest); the empty moves along +Y to fire."""
    S, D, G = "pile_bunker_steel", "pile_bunker_dark", "pile_bunker_grey"
    root_y = nose_y + ROD_SHOWN
    stake = empty("Stake", (0.0, root_y, 0.0))
    parts = []
    for side, z in (("Upper", STAKE_Z), ("Lower", -STAKE_Z)):
        rod = cylinder(f"StakeRod{side}", D, (0.0, -ROD_LENGTH / 2, z), 0.075, ROD_LENGTH, sides=16)
        collar = block(f"StakeCollar{side}", G, -0.14, 0.14, 0.0, 0.32, z - 0.14, z + 0.14, chamfer=0.04)
        plate = wedge(f"StakePlate{side}", S, -0.1, 0.1,
                      [(0.02, z + 0.14), (0.32, z + 0.14), (0.55, z + 0.07), (0.25, z + 0.2), (0.02, z + 0.2)])
        bolt = cylinder(f"StakeBolt{side}", D, (-0.15, 0.16, z), 0.03, 0.04, axis="X", sides=10, bevel=0.0)
        tip = cylinder(f"StakeTip{side}", S, (0.0, 0.32 + 0.4, z), 0.13, 0.8, sides=6, radius2=0.0, bevel=0.0)
        for obj in (rod, collar, plate, bolt, tip):
            obj.parent = stake
            parts.append(obj)
    return [stake] + parts


def apply_size(objects):
    """Scale every root object and its place by SIZE (children follow their parent). The body, the
    bracket and the empties are also BODY_LENGTH long along Y; the stakes (under the Stake empty) only move."""
    length = SIZE * BODY_LENGTH
    for obj in objects:
        if obj.parent is None:
            obj.location = Vector((obj.location.x * SIZE, obj.location.y * length, obj.location.z * SIZE))
            obj.scale = (SIZE, SIZE if obj.name == "Stake" or obj.type == "EMPTY" else length, SIZE)
    bpy.context.view_layer.update()
    for obj in objects:
        if obj.type == "MESH":
            for mod in obj.modifiers:
                mod.width *= SIZE


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
    print("pile_bunker: %s, %d objects, %d triangles" % (os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build_body() + (build_bracket() if WITH_BRACKET else []) + build_stakes(NOSE_Y)
    objects.append(empty("Nose", (0.0, NOSE_Y, 0.0)))
    objects.append(empty("Mount", (MOUNT_X, 0.75, MOUNT_Z)))
    apply_size(objects)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "pile_bunker.blend"))
    export(os.path.join(OUT_DIR, "pile_bunker.glb"), objects)


main()
