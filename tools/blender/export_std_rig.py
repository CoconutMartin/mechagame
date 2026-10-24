"""Exports a standard mech rig for Godot: the skeleton and every animation, with no part meshes.
All mechs of one size share this rig, so their parts are interchangeable (see DESIGN.md, Standard rig).

Writes, in models/std_rig/<size>/:
  std_<size>_rig.glb        skeleton + every action as its own animation (Godot plays these)
  std_<size>_bones.json     bone names, parents, head and tail at rest (export_std_parts.py checks
                            every model against it)
  std_<size>_markers.json   pose markers (footsteps, slides): glTF cannot store them

Run inside Blender with the rig source open (medium: models/new_mech/new_mech_exploded.blend):
Text Editor > Run Script, or
  blender -b models/new_mech/new_mech_exploded.blend --python tools/blender/export_std_rig.py -- medium
Every frame is sampled, so the leg IK and other constraints are baked into plain bone keys; each
animation starts at 0 s. The .blend is not changed.
"""
import json
import os
import sys

import bpy

RIG = "MechRig"
## Size name when none is given after "--".
DEFAULT_SIZE = "medium"
## Bones only used by Blender (IK targets and poles). They are left out of the bone check.
CONTROL_BONES = ("foot_ctrl", "knee_pole", "elbow_pole", "hand_ik")


def project_root():
    # The rig source sits in models/<name>/; the project root is two folders up.
    return os.path.dirname(os.path.dirname(os.path.dirname(bpy.data.filepath)))


def size_arg():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return args[0] if args else DEFAULT_SIZE


def is_control(name):
    return name.startswith(CONTROL_BONES)


def bone_table(rig):
    """Rest place of each bone in rig space (Blender, z up), in meters."""
    table = {}
    for b in rig.data.bones:
        if is_control(b.name):
            continue
        table[b.name] = {"parent": b.parent.name if b.parent else "",
                         "head": [round(v, 4) for v in b.head_local],
                         "tail": [round(v, 4) for v in b.tail_local]}
    return table


def make_anchor(rig):
    """A one-triangle mesh skinned to the root bone. Godot makes a Skeleton3D only for skinned bones,
    so the rig needs a skinned mesh in the file. Godot hides it (SkeletalAssembler)."""
    mesh = bpy.data.meshes.new("RigAnchor")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0.01, 0)], [], [(0, 1, 2)])
    obj = bpy.data.objects.new("RigAnchor", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = rig
    group = obj.vertex_groups.new(name="root")
    group.add([0, 1, 2], 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


def main():
    rig = bpy.data.objects[RIG]
    size = size_arg()
    folder = os.path.join(project_root(), "models", "std_rig", size)
    os.makedirs(folder, exist_ok=True)
    base = os.path.join(folder, "std_%s" % size)
    ad = rig.animation_data
    saved = (ad.action, ad.use_nla, bpy.context.scene.frame_current)
    ad.use_nla = False
    ad.action = None
    for p in rig.pose.bones:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    anchor = make_anchor(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    anchor.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=base + "_rig.glb", export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_step=1, export_def_bones=False,
                              export_skins=True, export_apply=False, export_anim_slide_to_zero=True,
                              export_reset_pose_bones=True, export_anim_single_armature=True, export_yup=True,
                              export_morph=False, export_cameras=False, export_lights=False)
    bpy.data.objects.remove(anchor)
    bpy.data.meshes.remove(bpy.data.meshes["RigAnchor"])
    with open(base + "_bones.json", "w") as f:
        json.dump({"size": size, "rig": RIG, "note": "Rest place of each standard bone (Blender rig space, "
                   "m). export_std_parts.py checks models against it.", "bones": bone_table(rig)}, f, indent=1)
    fps = bpy.context.scene.render.fps
    markers = {}
    for act in bpy.data.actions:
        if act.pose_markers:
            start = act.frame_range[0]
            markers[act.name] = [{"name": m.name, "frame": int(m.frame - start), "time": round((m.frame - start) / fps, 4)}
                                 for m in sorted(act.pose_markers, key=lambda m: m.frame)]
    with open(base + "_markers.json", "w") as f:
        json.dump({"fps": fps, "note": "Footstep and slide events per animation (frame / seconds from its start). "
                   "glTF cannot store pose markers.", "animations": markers}, f, indent=2)
    ad.action, ad.use_nla = saved[0], saved[1]
    bpy.context.scene.frame_set(saved[2])
    print("exported", base + "_rig.glb", round(os.path.getsize(base + "_rig.glb") / 1e6, 2), "MB,",
          len(bpy.data.actions), "actions,", len(bone_table(rig)), "bones")


if __name__ == "__main__":
    main()
