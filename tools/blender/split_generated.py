"""Cuts one generated mech mesh (for example an image-to-3D model from Hyper3D Rodin) into the game
parts of a mech kit .blend (made by mech_kit.py), then exports the parts.

Use (in Blender, with a kit file open, for example models/<name>/<name>.blend):
  1. Import the generated model. Select all its mesh objects.
  2. Turn it so it faces the Blender front view (-Y) and stands on the ground (Z = 0).
     Check it against the grey OG guide: shoulders, elbows, hips, knees and ankles should be near
     the guide joints. FIT_HEIGHT scales it for you (set None if you scaled it yourself).
  3. Run this script: Text Editor > Open > this file > Run Script, or (Blender MCP)
     exec(open(r"<project>/tools/blender/split_generated.py").read())
     To change a setting without editing the file: exec(open(path).read(), {"FIT_HEIGHT": None})
  4. Check the parts (each part collection), fix by hand if needed, save, run export_parts.py.

How it cuts: each face goes to the nearest "bone" (a line from joint to joint with a thickness,
listed in BONES), and the bone names the socket it hangs on. The core is cut again into center and
side pieces (the game makes the side torso hit areas from pieces beyond 0.9 m from the center).
The original objects are hidden, not deleted.
Materials: the generated material stays (the game keeps materials with unknown names). For part
damage looks, give armor faces a material named armor... and frame faces frame (see mech_kit.py).
"""
import bpy, bmesh
from mathutils import Matrix, Vector
from mathutils.geometry import intersect_point_line

## Model height after fitting, meters (feet to the top of the head or antennas). None: keep size.
FIT_HEIGHT = globals().get("FIT_HEIGHT", 10.6)
## Largest face count of the whole model (a decimate step runs above this). None: keep all faces.
MAX_FACES = globals().get("MAX_FACES", 80000)
## Core pieces this far from the center (meters) are side torso pieces.
SIDE_TORSO_X = 0.9

# Bones in game space (x right, y up, -z forward), from the OG skeleton (mech_kit.py SOCKETS).
# name: (start, end, radius, holder object). L is the mech's left (game x < 0).
BONES = {
    "head":      ((0, 8.2, -0.45), (0, 9.1, -0.45), 0.55, "Torso_head"),
    "core":      ((0, 5.9, 0.0), (0, 8.2, 0.0), 1.15, "Torso_core"),
    "booster":   ((0, 6.4, 1.8), (0, 8.0, 1.6), 0.7, "Torso_booster"),
    "antennaL":  ((-0.55, 8.3, 1.3), (-0.55, 11.5, 1.3), 0.25, "Torso_booster"),
    "antennaR":  ((0.55, 8.3, 1.3), (0.55, 11.5, 1.3), 0.25, "Torso_booster"),
    "pauldronL": ((-2.2, 7.9, 0.0), (-3.4, 7.9, 0.0), 0.95, "PauldronPivotL"),
    "pauldronR": ((2.2, 7.9, 0.0), (3.4, 7.9, 0.0), 0.95, "PauldronPivotR"),
    "upperArmL": ((-2.465, 7.2, 0.0), (-2.465, 5.8, 0.0), 0.45, "ShoulderL_arm_l"),
    "upperArmR": ((2.465, 7.2, 0.0), (2.465, 5.8, 0.0), 0.45, "ShoulderR_arm_r"),
    "forearmL":  ((-2.465, 5.57, 0.0), (-2.465, 2.8, 0.0), 0.55, "ElbowL_arm_l"),
    "forearmR":  ((2.465, 5.57, 0.0), (2.465, 2.8, 0.0), 0.55, "ElbowR_arm_r"),
    "pelvis":    ((-0.9, 5.2, 0.0), (0.9, 5.2, 0.0), 0.55, "Lower_legs"),
    "thighL":    ((-1.5, 5.0, 0.0), (-1.5, 2.8, 0.0), 0.6, "HipL_legs"),
    "thighR":    ((1.5, 5.0, 0.0), (1.5, 2.8, 0.0), 0.6, "HipR_legs"),
    "shinL":     ((-1.5, 2.6, 0.0), (-1.5, 0.8, 0.0), 0.6, "KneeL_legs"),
    "shinR":     ((1.5, 2.6, 0.0), (1.5, 0.8, 0.0), 0.6, "KneeR_legs"),
    "footL":     ((-1.5, 0.3, -1.6), (-1.5, 0.3, 0.8), 0.45, "FootPivotL"),
    "footR":     ((1.5, 0.3, -1.6), (1.5, 0.3, 0.8), 0.45, "FootPivotR"),
}


def to_blender(p):
    """Game point -> Blender world point (the mech faces -Y, its left is +X)."""
    return Vector((-p[0], p[2], p[1]))


def join_selected():
    meshes = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("Select the generated mesh objects first.")
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for o in meshes:
        c = o.copy()
        c.data = o.data.copy()
        c.parent = None
        c.matrix_world = o.matrix_world.copy()
        bpy.context.scene.collection.objects.link(c)
        copies.append(c)
        o.hide_set(True)
        o.hide_render = True
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    if len(copies) > 1:
        bpy.ops.object.join()
    model = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return model


def fit(model):
    corners = [Vector(v.co) for v in model.data.vertices]
    low = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    high = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    scale = 1.0 if FIT_HEIGHT is None else FIT_HEIGHT / max(high.z - low.z, 0.001)
    # Center in X and Y, feet on Z = 0.
    move = Vector((-(low.x + high.x) * 0.5, -(low.y + high.y) * 0.5, -low.z))
    model.data.transform(Matrix.Scale(scale, 4) @ Matrix.Translation(move))
    print(f"fit: scale {scale:.3f}, height {(high.z - low.z) * scale:.2f} m")


def decimate(model):
    faces = len(model.data.polygons)
    if MAX_FACES is None or faces <= MAX_FACES:
        return
    mod = model.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = MAX_FACES / faces
    bpy.context.view_layer.objects.active = model
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print(f"decimate: {faces} -> {len(model.data.polygons)} faces")


def bone_of(point, bones):
    best, best_d = None, 1e9
    for name, (a, b, radius) in bones.items():
        closest, t = intersect_point_line(point, a, b)
        if t < 0.0:
            closest = a
        elif t > 1.0:
            closest = b
        d = (point - closest).length - radius
        if d < best_d:
            best, best_d = name, d
    return best


def piece(model, name, face_ids, holder_name):
    """New object from these faces, origin at its center, parented to the holder empty."""
    holder = bpy.data.objects.get(holder_name)
    if holder is None:
        raise RuntimeError(f"No empty named {holder_name}: open a kit file made by mech_kit.py.")
    bm = bmesh.new()
    bm.from_mesh(model.data)
    keep = set(face_ids)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    center = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)
    bmesh.ops.translate(bm, vec=-center, verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for mat in model.data.materials:
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    for col in holder.users_collection:
        col.objects.link(obj)
    obj.parent = holder
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = holder.matrix_world.inverted() @ Matrix.Translation(center)
    return obj


def split():
    model = join_selected()
    fit(model)
    decimate(model)
    bones = {n: (to_blender(a), to_blender(b), r) for n, (a, b, r, _h) in BONES.items()}
    groups = {}
    for poly in model.data.polygons:
        name = bone_of(Vector(poly.center), bones)
        if name == "core":
            game_x = -poly.center.x
            if game_x < -SIDE_TORSO_X:
                name = "coreSideL"
            elif game_x > SIDE_TORSO_X:
                name = "coreSideR"
        groups.setdefault(name, []).append(poly.index)
    for name, faces in groups.items():
        holder = BONES["core"][3] if name.startswith("core") else BONES[name][3]
        piece(model, "gen_" + name, faces, holder)
        print(f"{name}: {len(faces)} faces -> {holder}")
    bpy.data.objects.remove(model, do_unlink=True)


split()
