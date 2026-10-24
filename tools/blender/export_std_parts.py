"""Exports the parts of a standard-rig mech for Godot: one glTF file per part collection.
Parts from any model of the same size fit together, because they all use the same rig
(see DESIGN.md, Standard rig).

Rules for the model .blend (models/<model>/<model>.blend or any .blend in models/<model>/):
  - The armature is named MechRig and matches models/std_rig/<size>/std_<size>_bones.json
    (same bone names and parents, joints within 1 cm). Make new models from the standard rig.
  - Each part is a collection named Head, Core, Arm_L, Arm_R, Legs or Booster. Its meshes are children
    of MechRig with an Armature modifier, weighted to standard bones only (rigid: one bone per piece).

Writes models/<model>/parts/<model>_<slot>.gltf (+ .bin), and the textures once in
models/<model>/parts/textures/ (shared by the parts). No animations: the game plays the rig's.

Run inside Blender with the model open: Text Editor > Run Script, or
  blender -b models/<model>/<file>.blend --python tools/blender/export_std_parts.py -- [model] [size]
model: default the folder name; size: default the rig's custom property std_size, else medium.
"""
import json
import os
import sys

import bpy

RIG = "MechRig"
DEFAULT_SIZE = "medium"
## Part collection name -> part file suffix (the Loadout slot).
SLOTS = {"Head": "head", "Core": "core", "Arm_L": "arm_l", "Arm_R": "arm_r", "Legs": "legs", "Booster": "booster"}
## Largest joint distance (m) from the standard rig before the export stops.
TOLERANCE = 0.01


def args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def check_rig(rig, standard):
    """Returns a list of problems: missing or moved bones, wrong parents."""
    problems = []
    for name, want in standard["bones"].items():
        bone = rig.data.bones.get(name)
        if bone is None:
            problems.append("missing bone %s" % name)
            continue
        parent = bone.parent.name if bone.parent else ""
        if parent != want["parent"]:
            problems.append("bone %s: parent %s, standard %s" % (name, parent, want["parent"]))
        for key, place in (("head", bone.head_local), ("tail", bone.tail_local)):
            off = max(abs(a - b) for a, b in zip(place, want[key]))
            if off > TOLERANCE:
                problems.append("bone %s: %s %.3f m from the standard" % (name, key, off))
    return problems


def check_mesh(obj, rig, bone_names):
    problems = []
    if obj.parent != rig:
        problems.append("%s: parent is not %s" % (obj.name, RIG))
    if not any(m.type == "ARMATURE" and m.object == rig for m in obj.modifiers):
        problems.append("%s: no Armature modifier on %s" % (obj.name, RIG))
    used = {g.group for v in obj.data.vertices for g in v.groups if g.weight > 0.0}
    for group in obj.vertex_groups:
        if group.index in used and group.name not in bone_names:
            problems.append("%s: vertex group %s is not a standard bone" % (obj.name, group.name))
    unweighted = sum(1 for v in obj.data.vertices if not any(g.weight > 0.0 for g in v.groups))
    if unweighted:
        problems.append("%s: %d vertices have no bone weight (they would stay behind)" % (obj.name, unweighted))
    return problems


def main():
    rig = bpy.data.objects[RIG]
    given = args()
    folder = os.path.dirname(bpy.data.filepath)
    model = given[0] if given else os.path.basename(folder)
    size = given[1] if len(given) > 1 else rig.get("std_size", DEFAULT_SIZE)
    root = os.path.dirname(os.path.dirname(folder))
    with open(os.path.join(root, "models", "std_rig", size, "std_%s_bones.json" % size)) as f:
        standard = json.load(f)
    problems = check_rig(rig, standard)
    parts = {}
    for coll_name, slot in SLOTS.items():
        coll = bpy.data.collections.get(coll_name)
        if coll is None:
            continue
        meshes = [o for o in coll.all_objects if o.type == "MESH"]
        for obj in meshes:
            problems += check_mesh(obj, rig, standard["bones"])
        if meshes:
            parts[slot] = meshes
    if problems:
        raise RuntimeError("export_std_parts: fix these first:\n  " + "\n  ".join(problems))

    out = os.path.join(folder, "parts")
    os.makedirs(out, exist_ok=True)
    ad = rig.animation_data
    saved = (ad.action, ad.use_nla) if ad else None
    if ad:
        ad.use_nla = False
        ad.action = None
    for p in rig.pose.bones:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
        p.rotation_quaternion = (1, 0, 0, 0)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for slot, meshes in parts.items():
        for o in bpy.context.selected_objects:
            o.select_set(False)
        rig.select_set(True)
        for obj in meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = rig
        path = os.path.join(out, "%s_%s.gltf" % (model, slot))
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                                  use_selection=True, export_animations=False, export_def_bones=False,
                                  export_skins=True, export_apply=False, export_yup=True, export_morph=False,
                                  export_cameras=False, export_lights=False)
        print("exported", path, len(meshes), "meshes")
    if saved:
        ad.action, ad.use_nla = saved
    print("export_std_parts: %d parts of %s for the %s rig" % (len(parts), model, size))


if __name__ == "__main__":
    main()
