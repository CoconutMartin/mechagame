"""Builds the light rig on Haliya HLY-101 (DESIGN "Three rigs", phase B).

Run in Blender:
  p = r"D:/EMCMII/GitHub/mechagame/tools/blender/haliya_rig_light.py"; exec(open(p).read(), {"__file__": p, "__name__": "__main__"})
It builds the model with haliya_ref_build.py, appends MechRig and its actions from the SGG file, and keeps every bone's rest
rotation. Only bone offsets and lengths change, to Haliya's joints, so the same actions play. Limb meshes turn about their joints to
the MechRig rest direction (A-pose) and bind rigidly to one bone each; their shape and size do not change. An Action constraint brings the arms down to the stance under every clip. The action Haliya_Stand
holds the stance of the pictures and is the action the file opens with. Saves models/haliya/haliya.blend.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import mech_rig_standard  # noqa: E402

BUILD_SCRIPT = os.path.join(HERE, "haliya_ref_build.py")
RIG_SOURCE = os.path.join(ROOT, "models/new_mech/new_mech_exploded.blend")
OUT_BLEND = os.path.join(ROOT, "models/haliya/haliya.blend")
RIG = "MechRig"
STAND_ACTION = "Haliya_Stand"
CARRY_ACTION = "Haliya_Arm_Carry"
SKIRT_ACTION = "Haliya_Skirt_Follow"
## The values of AccessoryBoneFollow in the game (scripts/animation/accessory_bone_follow.gd): part of the thigh's swing a skirt
## plate always follows, the extra part of the swing toward the plate, and the largest plate turn in degrees.
SKIRT_FOLLOW = 0.35
SKIRT_PUSH_FOLLOW = 1.0
SKIRT_MAX_TURN_DEG = 70.0
## The swing of the thigh (degrees) that the skirt action covers, and the step between its keys.
SKIRT_SWING_RANGE_DEG = 90
SKIRT_SWING_STEP_DEG = 10

## Size of the hand and finger bones against MechRig.
HAND_SCALE = 0.78
## Size of the foot bone against MechRig.
FOOT_SCALE = 0.8
## Width (m) of the finger and thumb pieces.
FINGER_WIDTH = 0.13
THUMB_WIDTH = 0.14
## Arm limits (radians) on this rig, wide enough for the stand pose.
STAND_ARM_LIMIT = math.radians(60.0)
## Height (m) the stand pose lowers the pelvis so the straight legs can reach the ground.
STAND_KNEE_SLACK = 0.03
## Height (m) of the pelvis bone above the hip joints, as on MechRig at this size.
PELVIS_ABOVE_HIP = 0.19

SIDES = (("L", 1), ("R", -1))


def run_build():
    scope = {"__file__": BUILD_SCRIPT, "__name__": "haliya_ref_build"}
    exec(open(BUILD_SCRIPT).read(), scope)
    return scope


def append_rig():
    old = bpy.data.objects.get(RIG)
    if old is not None:
        data = old.data
        bpy.data.objects.remove(old)
        bpy.data.armatures.remove(data)
    # A second run in one session must not add a second copy of every action.
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    with bpy.data.libraries.load(RIG_SOURCE, link=False) as (src, dst):
        dst.objects = [RIG]
        dst.actions = list(src.actions)
    rig = dst.objects[0]
    bpy.data.collections["Haliya_HLY101"].objects.link(rig)
    for action in dst.actions:
        action.use_fake_user = True
    for lib in list(bpy.data.libraries):
        bpy.data.libraries.remove(lib)
    bpy.context.view_layer.update()
    return rig


def clear_pose(rig):
    ad = rig.animation_data_create()
    ad.action = None
    ad.use_nla = False
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def bone_data(rig):
    """Rest of every bone before the edit: head, tail, length, direction."""
    data = {}
    for b in rig.data.bones:
        head = b.head_local.copy()
        tail = b.tail_local.copy()
        data[b.name] = {"head": head, "tail": tail, "length": (tail - head).length, "dir": (tail - head).normalized()}
    return data


def empty_at(name):
    return bpy.data.objects[name].matrix_world.translation.copy()


def rig_targets(old, source_joints):
    """New head of each joint bone, chain by chain with MechRig's directions and Haliya's lengths. Returns heads, lengths, turns."""
    heads = {}
    lengths = {}
    turns = {}
    hip_z = source_joints["thigh_L"].z
    # Feet stay on the ground: everything above them moves by drop.
    leg = source_joints["thigh_L"].copy()
    for bone, joint, end in (("thigh_L", "thigh_L", "shin_L"), ("shin_L", "shin_L", "foot_L")):
        leg += old[bone]["dir"] * (source_joints[end] - source_joints[joint]).length
    drop = leg.z - source_joints["foot_L"].z
    down = Vector((0, 0, -drop))
    for tag, _side in SIDES:
        for chain in ((("upper_arm_", "forearm_"), ("forearm_", "hand_")), (("thigh_", "shin_"), ("shin_", "foot_"))):
            head = source_joints[chain[0][0] + tag] + down
            for a, b in chain:
                bone_a = a + tag
                bone_b = b + tag
                span = source_joints[bone_b] - source_joints[bone_a]
                heads[bone_a] = head
                lengths[bone_a] = span.length
                turns[bone_a] = span.normalized().rotation_difference(old[bone_a]["dir"])
                head = head + old[bone_a]["dir"] * span.length
            heads[b + tag] = head
    for name in ("torso", "head"):
        heads[name] = source_joints[name] + down
    heads["pelvis"] = Vector((0, 0, hip_z + PELVIS_ABOVE_HIP)) + down
    lengths["pelvis"] = (heads["torso"] - heads["pelvis"]).length
    lengths["torso"] = (heads["head"] - heads["torso"]).length
    lengths["head"] = old["head"]["length"]
    return heads, lengths, turns, drop


def edit_rig(rig, old, heads, lengths, source_joints, sleeve_pivot, skirt_pivot, back_pivot, front_pivot):
    """Moves the bones and keeps every rest rotation: the direction and the roll of each bone stay."""
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = rig.data.edit_bones
    place = {}
    for name, head in heads.items():
        place[name] = (head, lengths.get(name, old[name]["length"] * FOOT_SCALE))
    for tag, side in SIDES:
        mirror = Vector((side, 1, 1))
        place["sleeve_" + tag] = (sleeve_pivot * mirror, old["sleeve_" + tag]["length"] * 0.8)
        place["skirt_side_" + tag] = (skirt_pivot * mirror, old["skirt_side_" + tag]["length"] * 0.8)
        place["skirt_back_" + tag] = (back_pivot * mirror, old["skirt_back_" + tag]["length"] * 0.8)
        place["skirt_front_" + tag] = (front_pivot * mirror, old["skirt_front_" + tag]["length"] * 0.8)
        hand = heads["hand_" + tag]
        place["hand_" + tag] = (hand, old["hand_" + tag]["length"] * HAND_SCALE)
        for finger in ("index", "middle", "ring", "pinky", "thumb"):
            for i in (1, 2, 3):
                name = "%s_%02d_%s" % (finger, i, tag)
                place[name] = (hand + (old[name]["head"] - old["hand_" + tag]["head"]) * HAND_SCALE,
                               old[name]["length"] * HAND_SCALE)
        name = "grip_" + tag
        place[name] = (hand + (old[name]["head"] - old["hand_" + tag]["head"]) * HAND_SCALE, old[name]["length"] * HAND_SCALE)
        # Controls move with their joints; their shape stays.
        place["foot_ctrl_" + tag] = (heads["foot_" + tag], old["foot_ctrl_" + tag]["length"] * FOOT_SCALE)
        place["hand_ik_" + tag] = (heads["hand_" + tag], old["hand_ik_" + tag]["length"])
        for pole, joint in (("knee_pole_", "shin_"), ("elbow_pole_", "forearm_")):
            place[pole + tag] = (old[pole + tag]["head"] + heads[joint + tag] - old[joint + tag]["head"],
                                 old[pole + tag]["length"])
    # Children first would stretch connected parents, so set every head and tail, then check.
    for name, (head, length) in place.items():
        eb = ebs[name]
        roll = eb.roll
        direction = old[name]["dir"]
        eb.use_connect = False
        eb.head = head
        eb.tail = head + direction * length
        eb.roll = roll
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()


def piece_rule(name, joint, side, heads, source_joints, turns, drop):
    """(bone, collection, map from the built model to the rest of the rig), or None for a piece the hand build replaces."""
    tag = "L" if side > 0 else "R"
    down = Vector((0, 0, -drop))

    def move(p):
        return p + down

    def limb(bone):
        pivot = source_joints[bone]
        target = heads[bone]
        turn = turns[bone]

        def apply(p):
            return target + turn @ (p - pivot)
        return apply

    if name.startswith(("Arm_palm", "Arm_hand_guard", "Arm_finger", "Arm_thumb")):
        return None
    if joint == "head":
        return "head", "Head", move
    if joint == "torso" or name == "Core_waist":
        return "torso", "Core", move
    if joint == "pelvis" and name.startswith("Core_"):
        return "pelvis", "Legs", move
    if name.startswith("Skirt_side"):
        return "skirt_side_" + tag, "Legs", move
    if name.startswith("Skirt_rear"):
        return "skirt_back_" + tag, "Legs", move
    if name.startswith(("Skirt_back", "Skirt_hip")):
        return "pelvis", "Legs", move
    if name.startswith("Arm_sleeve"):
        return "sleeve_" + tag, "Arm_" + tag, move
    if joint.startswith("upper_arm"):
        return joint, "Arm_" + tag, limb(joint)
    if joint.startswith("forearm"):
        return joint, "Arm_" + tag, limb(joint)
    if joint.startswith(("thigh", "shin")):
        return joint, "Legs", limb(joint)
    if joint.startswith("foot"):
        offset = heads[joint] - source_joints[joint]
        return joint, "Legs", lambda p: p + offset
    raise ValueError("no rule for %s on %s" % (name, joint))


def bind(obj, rig, bone, collection):
    obj.parent = rig
    obj.parent_type = "OBJECT"
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Identity(4)
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    if not any(m.type == "ARMATURE" for m in obj.modifiers):
        obj.modifiers.new("Armature", "ARMATURE").object = rig
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    bpy.data.collections[collection].objects.link(obj)


def add_hull(name, points, rig, bone, collection, material, bevel=0.012):
    bm = bmesh.new()
    seen = set()
    for p in points:
        key = tuple(round(c, 4) for c in p)
        if key not in seen:
            seen.add(key)
            bm.verts.new(key)
    result = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    junk = list({g for g in result["geom_interior"] + result["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), use_dissolve_boundaries=False,
                             verts=bm.verts[:], edges=bm.edges[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(bpy.data.materials[material])
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections[collection].objects.link(obj)
    bind(obj, rig, bone, collection)
    return obj


def bone_box(rig, bone, width):
    b = rig.data.bones[bone]
    m = b.matrix_local
    x = m.col[0].xyz.normalized()
    z = m.col[2].xyz.normalized()
    points = []
    for c, w in ((b.head_local, width), (b.tail_local, width * 0.85)):
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                points.append(c + x * (w * sx) + z * (w * sz))
    return points


def build_hand(rig, side, tag):
    """Palm and tan guard on the hand bone, one piece per finger bone: open at rest, Hand_Grip closes it."""
    collection = "Arm_" + tag
    hand = "hand_" + tag
    b = rig.data.bones[hand]
    wrist = b.head_local
    knuckles = b.tail_local
    roots = [rig.data.bones["%s_01_%s" % (f, tag)].head_local for f in ("index", "middle", "ring", "pinky")]
    back = Vector((side, 0, 0))
    front = (roots[0] - roots[-1]).normalized()
    middle = (roots[0] + roots[-1]) * 0.5
    palm = []
    for r in roots:
        for s in (-0.14, 0.14):
            palm.append(r + back * s + Vector((0, 0, 0.03)))
    for s in (-0.14, 0.14):
        for t in (-0.18, 0.18):
            palm.append(wrist + (knuckles - wrist) * 0.10 + back * s + front * t)
    thumb = rig.data.bones["thumb_01_" + tag].head_local
    for s in (-0.06, 0.06):
        palm.append(thumb + back * s)
    add_hull("Arm_palm_" + tag, palm, rig, hand, collection, "hly_joint", 0.02)
    guard = []
    top = wrist + (knuckles - wrist) * 0.02
    for s, reach in ((0.13, 0.0), (0.21, 0.03)):
        for t in (-0.20, 0.20):
            guard.append(top + back * s + front * t)
        for t in (-0.27, 0.27):
            guard.append(middle + back * (s + reach) + front * t + Vector((0, 0, 0.08)))
    add_hull("Arm_hand_guard_" + tag, guard, rig, hand, collection, "hly_tan", 0.02)
    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        width = THUMB_WIDTH if finger == "thumb" else FINGER_WIDTH
        for i in (1, 2, 3):
            bone = "%s_%02d_%s" % (finger, i, tag)
            add_hull("Arm_%s_%d_%s" % (finger, i, tag), bone_box(rig, bone, width), rig, bone, collection, "hly_joint")


def key_pose(pb, frame):
    pb.keyframe_insert("location", frame=frame)
    if pb.rotation_mode == "QUATERNION":
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    else:
        pb.keyframe_insert("rotation_euler", frame=frame)


def add_arm_carry(rig, turns):
    """The clips hold the arm at the MechRig rest angles, out from the body. An Action constraint on each arm bone adds the turn
    from that angle down to Haliya's stance under every clip, so all clips stay shared. The game needs the same value on the arm part."""
    ad = rig.animation_data
    action = bpy.data.actions.new(CARRY_ACTION)
    action.use_fake_user = True
    ad.action = action
    for tag, _side in SIDES:
        upper = rig.pose.bones["upper_arm_" + tag]
        rest = upper.bone.matrix_local.to_3x3()
        upper_turn = turns["upper_arm_" + tag].inverted().to_matrix()
        upper.matrix_basis = (rest.inverted() @ upper_turn @ rest).to_4x4()
        key_pose(upper, 1)
        # The forearm hangs from the upper arm, so its own turn is what is left after the upper arm's.
        fore = rig.pose.bones["forearm_" + tag]
        rest = fore.bone.matrix_local.to_3x3()
        fore_turn = upper_turn.inverted() @ turns["forearm_" + tag].inverted().to_matrix()
        fore.matrix_basis = (rest.inverted() @ fore_turn @ rest).to_4x4()
        key_pose(fore, 1)
    clear_pose(rig)
    slot = action.slots[0]
    for tag, _side in SIDES:
        for bone in ("upper_arm_", "forearm_"):
            pb = rig.pose.bones[bone + tag]
            c = pb.constraints.new("ACTION")
            c.name = "Arm carry"
            c.action = action
            c.action_slot = slot
            c.use_eval_time = True
            c.eval_time = 0.0
            c.frame_start = 1
            c.frame_end = 2
            c.mix_mode = "BEFORE_FULL"
            pb.constraints.move(len(pb.constraints) - 1, 0)
    bpy.context.view_layer.update()


def skirt_turn(rest_dir, axis, push, angle):
    """The plate turn of AccessoryBoneFollow for a thigh swung by angle about axis (all in the armature's rest frame)."""
    now = Matrix.Rotation(angle, 3, axis) @ rest_dir
    move = now - rest_dir
    toward = max(move.dot(push), 0.0)
    target = (rest_dir + move * SKIRT_FOLLOW + push * toward * SKIRT_PUSH_FOLLOW).normalized()
    turn = rest_dir.rotation_difference(target)
    limit = math.radians(SKIRT_MAX_TURN_DEG)
    if turn.angle > limit:
        turn = Quaternion(turn.axis, limit)
    return turn


def bone_swing(rig, name):
    """The front and back swing of a bone now: the X turn from its rest, in the bone's own frame, as an Action constraint reads it."""
    pb = rig.pose.bones[name]
    rest = pb.parent.bone.matrix_local.inverted() @ pb.bone.matrix_local
    pose = pb.parent.matrix.inverted() @ pb.matrix
    return (rest.inverted() @ pose).to_euler("XYZ").x


def add_skirt_follow(rig, stand_swings):
    """Shows in Blender what AccessoryBoneFollow does in the game: each skirt plate turns with its thigh. An Action constraint reads the
    front and back swing of the thigh and picks the plate pose from a keyed action, so no clip changes. The stance is the zero here,
    because the plates are modelled in the stance; the game counts from the rest pose (phase C)."""
    ad = rig.animation_data
    action = bpy.data.actions.new(SKIRT_ACTION)
    action.use_fake_user = True
    ad.action = action
    swings = list(range(-SKIRT_SWING_RANGE_DEG, SKIRT_SWING_RANGE_DEG + 1, SKIRT_SWING_STEP_DEG))
    plates = [bone + tag for tag, _side in SIDES for bone in ("skirt_front_", "skirt_side_", "skirt_back_")]
    for name in plates:
        pb = rig.pose.bones[name]
        limb = rig.data.bones["thigh_" + name[-1]]
        limb_rest = limb.matrix_local.to_3x3()
        rest_dir = limb_rest.col[1].normalized()
        axis = limb_rest.col[0].normalized()
        # Push direction as in the game: from the thigh's line to the plate's middle, across the thigh. A plate bone with no child counts as 3 m long.
        plate_rest = pb.bone.matrix_local.to_3x3()
        across = pb.bone.head_local + plate_rest.col[1].normalized() * 1.5 - limb.head_local
        across -= rest_dir * across.dot(rest_dir)
        push = across.normalized()
        stand = skirt_turn(rest_dir, axis, push, stand_swings[name[-1]]).inverted()
        for i, swing in enumerate(swings):
            turn = skirt_turn(rest_dir, axis, push, math.radians(swing)) @ stand
            pb.matrix_basis = (plate_rest.inverted() @ turn.to_matrix() @ plate_rest).to_4x4()
            key_pose(pb, i + 1)
    clear_pose(rig)
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:
                        key.interpolation = "LINEAR"
    slot = action.slots[0]
    for name in plates:
        pb = rig.pose.bones[name]
        c = pb.constraints.new("ACTION")
        c.name = "Skirt follow"
        c.target = rig
        c.subtarget = "thigh_" + name[-1]
        c.action = action
        c.action_slot = slot
        c.transform_channel = "ROTATION_X"
        c.target_space = "LOCAL"
        c.min = -SKIRT_SWING_RANGE_DEG
        c.max = SKIRT_SWING_RANGE_DEG
        c.frame_start = 1
        c.frame_end = len(swings)
        c.mix_mode = "BEFORE_FULL"
    bpy.context.view_layer.update()


def build_stand(rig, source_joints, turns, drop):
    """The stance of the pictures, keyed on every bone so that it clears any clip that played before it. The arms are FK on this rig
    (their IK influence is 0), the legs use their IK controls."""
    clear_pose(rig)
    # The MechRig limits stop the arm before Haliya's stance. The clips stay inside the old limits, so wider limits do not change them.
    for tag, _side in SIDES:
        for bone in ("upper_arm_", "forearm_"):
            for c in rig.pose.bones[bone + tag].constraints:
                if c.type == "LIMIT_ROTATION":
                    c.min_x = min(c.min_x, -STAND_ARM_LIMIT)
                    c.max_x = max(c.max_x, STAND_ARM_LIMIT)
                    c.min_y = min(c.min_y, -STAND_ARM_LIMIT)
                    c.max_y = max(c.max_y, STAND_ARM_LIMIT)
                    c.min_z = min(c.min_z, -STAND_ARM_LIMIT)
                    c.max_z = max(c.max_z, STAND_ARM_LIMIT)
    add_arm_carry(rig, turns)
    ad = rig.animation_data
    # The grip pose of the fingers, read from Hand_Grip.
    ad.action = bpy.data.actions["Hand_Grip"]
    bpy.context.scene.frame_set(2)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    fingers = {}
    for pb in rig.pose.bones:
        if pb.name.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"):
            fingers[pb.name] = pb.matrix_basis.copy()
    clear_pose(rig)
    old = bpy.data.actions.get(STAND_ACTION)
    if old is not None:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(STAND_ACTION)
    action.use_fake_user = True
    ad.action = action
    pelvis = rig.pose.bones["pelvis"]
    world = pelvis.bone.matrix_local.copy()
    world.translation = world.translation + Vector((0, 0, drop - STAND_KNEE_SLACK))
    pelvis.matrix = world
    bpy.context.view_layer.update()
    for tag, _side in SIDES:
        foot = rig.pose.bones["foot_ctrl_" + tag]
        m = foot.bone.matrix_local.copy()
        m.translation = source_joints["foot_" + tag]
        foot.matrix = m
        hand_ik = rig.pose.bones["hand_ik_" + tag]
        forearm = rig.pose.bones["forearm_" + tag]
        m = turns["forearm_" + tag].inverted().to_matrix().to_4x4() @ hand_ik.bone.matrix_local.to_3x3().to_4x4()
        m.translation = forearm.tail
        hand_ik.matrix = m
    bpy.context.view_layer.update()
    for name, basis in fingers.items():
        rig.pose.bones[name].matrix_basis = basis
    bpy.context.view_layer.update()
    for pb in rig.pose.bones:
        key_pose(pb, 1)
    bpy.context.view_layer.update()
    stand_swings = {tag: bone_swing(rig, "thigh_" + tag) for tag, _side in SIDES}
    add_skirt_follow(rig, stand_swings)
    ad.action = action
    ad.action_slot = action.slots[0]
    return action


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    arm_lift = run_build()["ARM_LIFT"]
    bpy.context.view_layer.update()
    joint_names = ["pelvis", "torso", "head"] + [j + t for t in ("L", "R") for j in (
        "upper_arm_", "forearm_", "hand_", "thigh_", "shin_", "foot_")]
    source_joints = {n: empty_at(n) for n in joint_names}
    scale = source_joints["head"].z / 8.42  # the build places the neck at 8.42 before its scale
    rig = append_rig()
    mech_rig_standard.ensure_accessory_bones(rig)
    clear_pose(rig)
    old = bone_data(rig)
    heads, lengths, turns, drop = rig_targets(old, source_joints)
    down = Vector((0, 0, -drop))
    sleeve_pivot = Vector((1.25, 0.25, 8.40 + arm_lift)) * scale + down
    skirt_pivot = Vector((1.05, 0.15, 6.30)) * scale + down
    back_pivot = Vector((0.95, 0.84, 6.19)) * scale + down
    front_pivot = Vector((0.75, -0.60, 5.75)) * scale + down
    edit_rig(rig, old, heads, lengths, source_joints, sleeve_pivot, skirt_pivot, back_pivot, front_pivot)

    root = bpy.data.collections["Haliya_HLY101"]
    pieces = [o for c in root.children for o in c.objects if o.type == "MESH"]
    empties = [o for c in root.children for o in c.objects if o.type == "EMPTY"]
    for obj in pieces:
        joint = obj.parent.name
        name = obj.name
        side = -1 if name.endswith("_R") or "_R_" in name or "_R0" in name or "_R1" in name else 1
        rule = piece_rule(name, joint, side, heads, source_joints, turns, drop)
        if rule is None:
            bpy.data.objects.remove(obj)
            continue
        bone, collection, fit = rule
        world = obj.matrix_world.copy()
        for v in obj.data.vertices:
            v.co = fit(world @ v.co)
        bind(obj, rig, bone, collection)
    for e in empties:
        bpy.data.objects.remove(e)
    for tag, side in SIDES:
        build_hand(rig, side, tag)
    build_stand(rig, source_joints, turns, drop)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
    print("drop", round(drop, 3), "saved", OUT_BLEND)
    return old


if __name__ == "__main__":
    main()
