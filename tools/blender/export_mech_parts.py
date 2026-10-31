"""Exports a mech as swappable parts for Godot (user request 2026-10-31, see DESIGN "Swappable mech parts").

Writes into <out folder> (default: the .blend's folder + "/parts"):
  <prefix>_rig.glb    the standard rig MechRig with every action (no part meshes; one tiny anchor mesh,
                      so Godot makes a Skeleton3D). The game plays the animations from this file.
  <prefix>_head.glb, _core.glb, _arm_l.glb, _arm_r.glb, _legs.glb
                      the rig at rest and the meshes of one part collection (no animations).

Part collections (the child part owns the joint piece between two parts, user choice 2026-10-31):
  Head   head and neck joint          Core   torso and waist joint
  Arm_L  arm, shoulder ball, elbow, hand    Arm_R  the same, right
  Legs   pelvis, hip balls, thighs, knees, shins, feet

Rules for a part (check_mech_parts.py tests them): every mesh is a child of MechRig with an Armature
modifier and full weight (1.0) on its bones; fingers may use several bones, other meshes one bone (rigid,
no tearing). The bones keep the standard names and rest places (SGG-101, the joint standard).

Run headless (Blender 5.2, or pip bpy 5.2.2):
  python tools/blender/export_mech_parts.py -- models/new_mech/new_mech_exploded.blend sgg models/mechs/sgg
Without arguments after "--" it uses the open file, prefix "sgg" and <blend folder>/parts.
"""
import os
import sys

import bpy

RIG = "MechRig"
## Part collection -> file suffix.
PARTS = {"Head": "head", "Core": "core", "Arm_L": "arm_l", "Arm_R": "arm_r", "Legs": "legs"}
ANCHOR = "RigAnchor"

GLTF_COMMON = dict(export_format="GLB", use_selection=True, export_def_bones=False, export_skins=True,
                   export_apply=False, export_yup=True, export_morph=False, export_cameras=False,
                   export_lights=False)


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return argv


def _select(objects):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objects:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def _rest_pose(rig):
    ad = rig.animation_data
    saved = (ad.action, ad.use_nla) if ad else None
    if ad:
        ad.use_nla = False
        ad.action = None
    for p in rig.pose.bones:
        p.location = (0, 0, 0)
        p.rotation_quaternion = (1, 0, 0, 0)
        p.rotation_euler = (0, 0, 0)
        p.scale = (1, 1, 1)
    return saved


def _anchor(rig):
    """One small triangle on the root bone: a glTF skin needs a skinned mesh, and Godot makes the
    Skeleton3D from the skin."""
    mesh = bpy.data.meshes.new(ANCHOR)
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0.01, 0)], [], [(0, 1, 2)])
    obj = bpy.data.objects.new(ANCHOR, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = rig
    group = obj.vertex_groups.new(name="root")
    group.add([0, 1, 2], 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


def main():
    argv = _args()
    if argv:
        bpy.ops.wm.open_mainfile(filepath=os.path.abspath(argv[0]))
    prefix = argv[1] if len(argv) > 1 else "sgg"
    folder = os.path.abspath(argv[2]) if len(argv) > 2 else os.path.join(os.path.dirname(bpy.data.filepath), "parts")
    os.makedirs(folder, exist_ok=True)
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    rig = bpy.data.objects[RIG]
    saved = _rest_pose(rig)

    for collection, suffix in PARTS.items():
        meshes = [o for o in bpy.data.collections[collection].objects if o.type == "MESH" and o.parent == rig]
        path = os.path.join(folder, "%s_%s.glb" % (prefix, suffix))
        _select([rig] + meshes)
        bpy.ops.export_scene.gltf(filepath=path, export_animations=False, **GLTF_COMMON)
        print("part", path, len(meshes), "meshes", round(os.path.getsize(path) / 1e6, 1), "MB")

    # The rig: every action, sampled per frame (IK and constraints baked), as in export_new_mech_glb.py.
    anchor = _anchor(rig)
    path = os.path.join(folder, "%s_rig.glb" % prefix)
    _select([rig, anchor])
    bpy.ops.export_scene.gltf(filepath=path, export_animations=True, export_animation_mode="ACTIONS",
                              export_force_sampling=True, export_frame_step=1, export_anim_slide_to_zero=True,
                              export_reset_pose_bones=True, export_anim_single_armature=True, **GLTF_COMMON)
    print("rig", path, round(os.path.getsize(path) / 1e6, 1), "MB")
    bpy.data.objects.remove(anchor)
    if saved:
        rig.animation_data.action, rig.animation_data.use_nla = saved


if __name__ == "__main__":
    main()
