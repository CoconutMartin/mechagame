"""Exports the new mech for Godot: models/new_mech/new_mech_exploded.glb (rig, parts, every action as its
own animation) and models/new_mech/new_mech_markers.json (pose markers: glTF cannot store them).

Run inside Blender with models/new_mech/new_mech_exploded.blend open (Text Editor: Run Script).
Every frame is sampled, so the leg IK and other constraints are baked into plain bone keys; each
animation starts at 0 s. After a new animation is added, add it to the looping list in
new_mech_exploded.glb.import if it loops, and let Godot import again.
"""
import json
import os

import bpy

RIG = "MechRig"


def main():
    rig = bpy.data.objects[RIG]
    ad = rig.animation_data
    folder = os.path.dirname(bpy.data.filepath)
    glb = os.path.join(folder, "new_mech_exploded.glb")
    saved = (ad.action, ad.use_nla, bpy.context.scene.frame_current)
    ad.use_nla = False
    ad.action = None
    for p in rig.pose.bones:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    for o in rig.children:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
                              export_def_bones=False, export_skins=True, export_apply=False,
                              export_anim_slide_to_zero=True, export_reset_pose_bones=True,
                              export_anim_single_armature=True, export_yup=True, export_morph=False,
                              export_cameras=False, export_lights=False)
    fps = bpy.context.scene.render.fps
    markers = {}
    for act in bpy.data.actions:
        if act.pose_markers:
            start = act.frame_range[0]
            markers[act.name] = [{"name": m.name, "frame": int(m.frame - start), "time": round((m.frame - start) / fps, 4)}
                                 for m in sorted(act.pose_markers, key=lambda m: m.frame)]
    with open(os.path.join(folder, "new_mech_markers.json"), "w") as f:
        json.dump({"fps": fps, "note": "Footstep and slide events per animation (frame / seconds from its start). "
                   "glTF cannot store pose markers.", "animations": markers}, f, indent=2)
    ad.action, ad.use_nla = saved[0], saved[1]
    bpy.context.scene.frame_set(saved[2])
    print("exported", glb, round(os.path.getsize(glb) / 1e6, 1), "MB;", len(markers), "animations with markers")


if __name__ == "__main__":
    main()
