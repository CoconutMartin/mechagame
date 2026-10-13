"""Builds Sanggigilid's new hands (user drawings 2026-10-13: right hand palm, back, closed underside,
closed back, open back) and exports them.

Run (from the project root):
    blender -b --python tools/blender/mech_hand_build.py
Writes models/mech_hand/mech_hand.blend, mech_hand_r.glb and mech_hand_l.glb. The script starts from an
empty file, so hand edits in the .blend are lost when it runs again.

Look from the drawings: a big boxy back-of-hand block with a ridge along the knuckle edge, four fingers
and a thumb of round segments with banded roller joints, the thumb on two rollers at the side of the palm.
Dark joint metal like the old hands.

Joints are empties (no skin): each finger has three (Index1..3, Middle1..3, Ring1..3, Pinky1..3) and so
has the thumb (Thumb1..3). A joint bends about its own X axis; in the game MechHand turns them (negative
angle = toward the palm). Meshes are children of their joint, so each segment stays rigid.

Coordinates (the game's hand frame H, measured from the old hand): origin at the wrist (the hand bone),
+Y toward the fingers, +Z to the back of the hand, +X = Y x Z. Right hand: index at -X, thumb at -X.
The left hand is the mirror (X flipped). Blender point = (x, -z, y) of the game point.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "mech_hand")

## Knuckle line (finger joint 1) distance from the wrist, per hand (the old hands' finger roots).
KNUCKLE_Y = {"r": 0.78, "l": 0.66}
## Back-of-hand block: width, from the palm face (Z) to the back (Z).
PALM_WIDTH = 0.86
PALM_Z = (0.08, 0.5)
## Fingers: X place (right hand), segment lengths (proximal, middle, distal), radius.
FINGERS = [("Index", -0.30, (0.30, 0.20, 0.16)), ("Middle", -0.10, (0.33, 0.22, 0.17)),
           ("Ring", 0.10, (0.31, 0.21, 0.16)), ("Pinky", 0.30, (0.26, 0.18, 0.14))]
FINGER_RADIUS = 0.075
FINGER_Z = 0.17
## Thumb: base joint place (right hand), direction (out, forward, to the palm), segment lengths.
THUMB_BASE = (-0.45, 0.30, 0.16)
THUMB_DIR = (-0.55, 0.75, -0.35)
THUMB_SEGMENTS = (0.22, 0.18, 0.15)
THUMB_RADIUS = 0.08
## Where the thumb tip goes when it closes (right hand): across the front of the bent fingers.
THUMB_CLOSE_TARGET = (0.05, 0.62, -0.28)

MATERIALS = {
    "hand_metal": ((0.11, 0.115, 0.125), 0.55, 0.6),
    "hand_joint": ((0.05, 0.05, 0.055), 0.6, 0.5),
}
METAL, JOINT = "hand_metal", "hand_joint"

C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # game H -> Blender


def B(p):
    return Vector((p[0], -p[2], p[1]))


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


def mesh_object(name, bm, mat, parent, bevel=0.0):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        obj.data.use_auto_smooth = True
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def box(name, mat, lo, hi, parent, sx, bevel=0.02):
    """Box between game-space corners lo and hi (right hand X; sx mirrors)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    a, b = Vector((lo[0] * sx, lo[1], lo[2])), Vector((hi[0] * sx, hi[1], hi[2]))
    size = Vector((abs(b.x - a.x), abs(b.y - a.y), abs(b.z - a.z)))
    center = (a + b) / 2
    bmesh.ops.scale(bm, vec=Vector((size.x, size.z, size.y)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=B(center), verts=bm.verts)
    return mesh_object(name, bm, mat, parent, bevel)


def cylinder(name, mat, a, b, radius, parent, sides=12, cap_round=False):
    """Cylinder from game point a to b (already mirrored)."""
    pa, pb = B(a), B(b)
    bm = bmesh.new()
    length = (pb - pa).length
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=length)
    # Cone along Blender Z: turn it to the a->b direction, then move to the middle.
    rot = Vector((0, 0, 1)).rotation_difference((pb - pa).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(pa + pb) / 2, verts=bm.verts)
    if cap_round:
        sphere = bmesh.ops.create_uvsphere(bm, u_segments=sides, v_segments=6, radius=radius)
        bmesh.ops.translate(bm, vec=pb, verts=sphere["verts"])
    return mesh_object(name, bm, mat, parent)


def empty(name, location, basis, parent):
    """Joint: an empty at game point location with game-space basis (columns X, Y, Z)."""
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 0.1
    bpy.context.collection.objects.link(obj)
    rot = (C @ basis @ C.transposed()).to_4x4()
    obj.matrix_world = Matrix.Translation(B(location)) @ rot
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def chain(prefix, base, direction, hinge, lengths, radius, root, sx, objects):
    """A finger or thumb: three joints along direction, each bending about hinge (game space)."""
    d = Vector(direction).normalized()
    x = Vector(hinge).normalized()
    z = x.cross(d).normalized()
    x = d.cross(z).normalized()
    basis = Matrix((x, d, z)).transposed()
    parent = root
    point = Vector(base)
    for i, length in enumerate(lengths):
        joint = empty(f"{prefix}{i + 1}", point, basis, parent)
        objects.append(joint)
        # Banded roller joint across the hinge, then the segment with a ring near its end.
        objects.append(cylinder(f"{prefix}{i + 1}Roller", JOINT, point - x * radius * 1.05, point + x * radius * 1.05,
                                radius * 1.12, joint, sides=12))
        start = point + d * radius * 0.9
        end = point + d * length
        last = i == len(lengths) - 1
        objects.append(cylinder(f"{prefix}{i + 1}Segment", METAL, start, end - (d * radius * 0.6 if last else d * 0.0),
                                radius, joint, cap_round=last))
        if not last:
            objects.append(cylinder(f"{prefix}{i + 1}Band", JOINT, end - d * 0.06, end - d * 0.02, radius * 1.08, joint))
        parent = joint
        point = end
    return objects


def build(side):
    sx = 1.0 if side == "r" else -1.0
    ky = KNUCKLE_Y[side]
    objects = []
    hand = empty("Hand", (0, 0, 0), Matrix.Identity(3), None)
    objects.append(hand)
    w = PALM_WIDTH / 2
    # Wrist joint and the back-of-hand block, a ridge along the knuckle edge, the palm plate.
    objects.append(cylinder("Wrist", JOINT, (-0.2 * sx, 0.0, 0.26), (0.2 * sx, 0.0, 0.26), 0.17, hand, sides=14))
    objects.append(box("BackBlock", METAL, (-w, 0.08, PALM_Z[0] + 0.06), (w, ky - 0.08, PALM_Z[1]), hand, sx, 0.035))
    objects.append(box("KnuckleRidge", METAL, (-w - 0.01, ky - 0.12, PALM_Z[0]), (w + 0.01, ky - 0.03, PALM_Z[1] - 0.12), hand, sx, 0.02))
    objects.append(box("PalmPlate", JOINT, (-w + 0.04, 0.12, PALM_Z[0]), (w - 0.04, ky - 0.1, PALM_Z[0] + 0.07), hand, sx, 0.015))
    # Thumb rollers at the side of the palm (two, as in the palm drawing).
    tb = (THUMB_BASE[0] * sx, THUMB_BASE[1], THUMB_BASE[2])
    for i, dy in enumerate((-0.11, 0.0)):
        objects.append(cylinder(f"ThumbMount{i}", JOINT, (tb[0], tb[1] + dy - 0.05, tb[2]), (tb[0], tb[1] + dy + 0.05, tb[2]),
                                0.09, hand, sides=12))
    for name, x, lengths in FINGERS:
        chain(name, (x * sx, ky, FINGER_Z), (0, 1, 0), (1, 0, 0), lengths, FINGER_RADIUS, hand, sx, objects)
    tdir = (THUMB_DIR[0] * sx, THUMB_DIR[1], THUMB_DIR[2])
    # The thumb bends toward THUMB_CLOSE_TARGET: the hinge is across its direction and the target, so
    # a closing thumb folds across the front of the fingers (a negative turn about X moves the
    # direction toward -Z of the joint, which chain() points at the target).
    base = Vector((tb[0], tb[1] + 0.1, tb[2]))
    d = Vector(tdir).normalized()
    t = Vector((THUMB_CLOSE_TARGET[0] * sx, THUMB_CLOSE_TARGET[1], THUMB_CLOSE_TARGET[2])) - base
    t = (t - d * t.dot(d)).normalized()
    hinge = t.cross(d)
    chain("Thumb", base, tdir, hinge, THUMB_SEGMENTS, THUMB_RADIUS, hand, sx, objects)
    return objects


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
    print("mech hand: %s, %d objects, %d triangles" % (os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    right = build("r")
    export(os.path.join(OUT_DIR, "mech_hand_r.glb"), right)
    # The left hand alone (same joint names; MechHand finds them by name), then both in the .blend.
    for obj in right:
        obj.name = obj.name + "_R"
    left = build("l")
    export(os.path.join(OUT_DIR, "mech_hand_l.glb"), left)
    for obj in right:
        obj.location.x += 2.0 if obj.parent is None else 0.0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "mech_hand.blend"))


main()
