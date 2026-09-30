"""Blender kit for custom mechs (Blender 4.x). Makes a .blend file to model a new mech in.

Run (from the project root):
    blender -b --python tools/blender/mech_kit.py -- <mech_name>
It writes models/<mech_name>/<mech_name>.blend with:
  - One collection per part: part_head, part_core, part_arm_l, part_arm_r, part_legs, part_booster.
  - In each, the socket empties the part attaches to (named <Socket>_<part>, for example
    "Torso_core", "ShoulderL_arm_l"). Put the part meshes under (parented to) these empties.
  - Pivot empties: PauldronPivotL/R (arms), FootPivotL/R (ankles, legs), BoosterFlameL/R (booster).
    Parts under a pivot turn with it in the game. Keep these names.
  - The OG mech as a grey guide (collection "guide_og", not exported, not selectable).
  - Materials named armor, armor_dark, frame, joint, eye, emblem, lens: the game uses its own
    materials for these names. Other material names keep their Blender look.
  - A text block "export_parts.py" (Text Editor > Run Script) that writes one .glb per part.
Rules: 1 unit = 1 m, the mech stands on Z = 0, the front faces -Y (Blender front view), about 10 m
tall. Joints: see SOCKETS. Armor that should break off: materials armor...; inner frame that stays
when a leg is blown apart: frame or joint.
"""
import bpy, os, sys, math
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# Rest places of the frame joints in the game (x right, y up, -z forward), meters.
SOCKETS = {
    "Torso": (0.0, 5.4, 0.0), "ShoulderL": (-2.465, 7.865, 0.0), "ElbowL": (-2.465, 5.57, 0.0),
    "ShoulderR": (2.465, 7.865, 0.0), "ElbowR": (2.465, 5.57, 0.0), "Lower": (0.0, 5.2, 0.0),
    "HipL": (-1.5, 5.2, 0.0), "KneeL": (-1.5, 2.6, 0.0), "HipR": (1.5, 5.2, 0.0), "KneeR": (1.5, 2.6, 0.0),
}
PARTS = {
    "head": ["Torso"], "core": ["Torso"], "arm_l": ["Torso", "ShoulderL", "ElbowL"],
    "arm_r": ["Torso", "ShoulderR", "ElbowR"], "legs": ["Lower", "HipL", "KneeL", "HipR", "KneeR"],
    "booster": ["Torso"],
}
# Pivots: part -> (name, socket, game position, rotation about the game X axis in degrees).
PIVOTS = {
    "arm_l": [("PauldronPivotL", "Torso", (-2.465, 7.865, 0.0), 0.0)],
    "arm_r": [("PauldronPivotR", "Torso", (2.465, 7.865, 0.0), 0.0)],
    "legs": [("FootPivotL", "KneeL", (-1.5, 0.55, 0.0), 0.0), ("FootPivotR", "KneeR", (1.5, 0.55, 0.0), 0.0)],
    "booster": [("BoosterFlameL", "Torso", (-0.6375, 5.893, 1.887), 25.0),
                ("BoosterFlameR", "Torso", (0.6375, 5.893, 1.887), 25.0)],
}
MATERIALS = {"armor": (0.7, 0.69, 0.66), "armor_dark": (0.5, 0.49, 0.47), "frame": (0.14, 0.14, 0.15),
             "joint": (0.3, 0.3, 0.31), "eye": (0.9, 0.12, 0.04), "emblem": (0.8, 0.3, 0.25), "lens": (0.5, 0.4, 0.25)}


def to_blender(p):
    """Game point to Blender: the mech faces -Y, Z up."""
    return Vector((-p[0], p[2], p[1]))


def to_socket_local(p):
    """Game offset in socket space to the local space of a socket empty (turned 180 degrees)."""
    return Vector((p[0], -p[2], p[1]))


def collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col


def empty(name, col, location, rotation=(0.0, 0.0, 0.0), parent=None, size=0.6, kind="PLAIN_AXES"):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = kind
    obj.empty_display_size = size
    col.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    obj.location = location
    obj.rotation_euler = rotation
    return obj


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    for mat_name, color in MATERIALS.items():
        mat = bpy.data.materials.new(mat_name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.45
        bsdf.inputs["Roughness"].default_value = 0.6
        mat.use_fake_user = True
    for part, sockets in PARTS.items():
        col = collection(f"part_{part}")
        made = {}
        for socket in sockets:
            made[socket] = empty(f"{socket}_{part}", col, to_blender(SOCKETS[socket]), (0.0, 0.0, math.pi),
                                 size=0.8, kind="ARROWS")
        for pivot, socket, pos, tilt in PIVOTS.get(part, []):
            offset = [pos[i] - SOCKETS[socket][i] for i in range(3)]
            empty(pivot, col, to_socket_local(offset), (math.radians(tilt), 0.0, 0.0), parent=made[socket],
                  size=0.5, kind="SINGLE_ARROW" if pivot.startswith("Booster") else "SPHERE")
    guide = os.path.join(ROOT, "models", "guides", "og_guide.glb")
    if os.path.exists(guide):
        import_guide(guide)
    text = bpy.data.texts.new("export_parts.py")
    text.from_string(open(os.path.join(ROOT, "tools", "blender", "export_parts.py")).read())
    out_dir = os.path.join(ROOT, "models", name)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{name}.blend")
    bpy.ops.wm.save_as_mainfile(filepath=path)
    print("wrote", path)


def import_guide(path):
    col = collection("guide_og")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in new:
        # "og_" names keep the joint and part names (FootL, KneeL...) free for the new mech.
        obj.name = "og_" + obj.name
        for c in obj.users_collection:
            c.objects.unlink(obj)
        col.objects.link(obj)
        obj.hide_select = True
        if obj.type == "MESH":
            obj.display_type = "WIRE"
    # glTF faces +Y after import (the game front is -Z): turn the guide to face -Y.
    for obj in new:
        if obj.parent is None:
            obj.rotation_mode = "XYZ"
            obj.rotation_euler.z += math.pi
    grey = bpy.data.materials.new("og_guide_grey")
    for obj in new:
        if obj.type == "MESH":
            obj.data.materials.clear()
            obj.data.materials.append(grey)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)
    for mat in list(bpy.data.materials):
        if mat.users == 0 and not mat.use_fake_user:
            bpy.data.materials.remove(mat)
    col.hide_render = True


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(argv[0] if argv else "new_mech")
