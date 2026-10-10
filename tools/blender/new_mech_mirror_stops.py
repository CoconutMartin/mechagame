"""Makes left-to-right mirror copies of the run stops: biped_run_stop_akira_L (the Akira slide that turns
left; the original turns right) and biped_run_stop_L (brakes on the left foot). The originals start on
the left foot landing of the run, the copies on the right foot landing, so the game can start a stop on
either foot. Pose markers are copied with footstep_L / footstep_R swapped.

Run inside Blender with models/new_mech/new_mech_exploded.blend open (Text Editor: Run Script), then run
export_new_mech_glb.py. Running it again replaces the old mirror copy.

Each bone's pose channel change is mirrored in armature space (X = -X) and given to the bone on the other
side (thigh_L <-> thigh_R; centre bones mirror onto themselves). This works for any bone roll, as long
as the rest pose is symmetric.
"""
import bpy
from mathutils import Matrix

RIG = "MechRig"
## Source action: mirror copy.
MIRRORS = {"biped_run_stop_akira": "biped_run_stop_akira_L", "biped_run_stop": "biped_run_stop_L"}
MIRROR = Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0))


def other_side(name):
    if name.endswith("_L"):
        return name[:-2] + "_R"
    if name.endswith("_R"):
        return name[:-2] + "_L"
    return name


def animated_bones(action):
    bones = set()
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if fc.data_path.startswith('pose.bones["'):
                        bones.add(fc.data_path.split('"')[1])
    return bones


def main():
    rig = bpy.data.objects[RIG]
    scene = bpy.context.scene
    ad = rig.animation_data
    saved = (ad.action, ad.use_nla, scene.frame_current)
    ad.use_nla = False
    for source, target in MIRRORS.items():
        mirror(rig, scene, bpy.data.actions[source], target)
    ad.action, ad.use_nla = saved[0], saved[1]
    scene.frame_set(saved[2])


def mirror(rig, scene, src, target):
    """Writes the mirror copy of action src as a new action named target."""
    ad = rig.animation_data
    old = bpy.data.actions.get(target)
    if old is not None:
        bpy.data.actions.remove(old)
    bones = animated_bones(src)
    first, last = int(src.frame_range[0]), int(src.frame_range[1])
    # Pose channels of every animated bone on every frame.
    ad.action = src
    frames = []
    for f in range(first, last + 1):
        scene.frame_set(f)
        frames.append({b: rig.pose.bones[b].matrix_basis.copy() for b in bones})
    rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
    dst = bpy.data.actions.new(target)
    dst.use_fake_user = True
    ad.action = dst
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    previous = {}
    for i, f in enumerate(range(first, last + 1)):
        for b in bones:
            to = other_side(b)
            # The channel change in armature space, mirrored, then back into the other bone's rest frame.
            change = rest[b] @ frames[i][b] @ rest[b].inverted()
            mirrored = MIRROR @ change @ MIRROR
            basis = rest[to].inverted() @ mirrored @ rest[to]
            pb = rig.pose.bones[to]
            loc, rot, _scale = basis.decompose()
            pb.location = loc
            pb.rotation_euler = rot.to_euler(pb.rotation_mode, previous.get(to, pb.rotation_euler))
            previous[to] = pb.rotation_euler.copy()
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_euler", frame=f)
    for m in src.pose_markers:
        name = m.name.replace("_L", "_TMP").replace("_R", "_L").replace("_TMP", "_R")
        dst.pose_markers.new(name).frame = m.frame
    ad.action = None
    print("mirrored", src.name, "->", target, len(bones), "bones,", last - first + 1, "frames")


if __name__ == "__main__":
    main()
