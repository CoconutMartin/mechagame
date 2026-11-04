"""Moves the Haliya model of haliya_ref_build.py onto the joint standard MechRig (user choice 2026-11-05).

Run in Blender:
  p = r"D:/EMCMII/GitHub/mechagame/tools/blender/haliya_rig_fit.py"; exec(open(p).read(), {"__file__": p, "__name__": "__main__"})
It builds the model, appends MechRig and its actions from the SGG file, adds the accessory bones, moves every piece
so its joint sits on its bone, binds each piece rigidly to one bone and saves models/haliya/haliya.blend.
The fingers are built along the finger bones, so the rest pose has an open hand (the Hand_Grip action closes it).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import mech_rig_standard  # noqa: E402

BUILD_SCRIPT = os.path.join(HERE, "haliya_ref_build.py")
RIG_SOURCE = os.path.join(ROOT, "models/new_mech/new_mech_exploded.blend")
OUT_BLEND = os.path.join(ROOT, "models/haliya/haliya.blend")
RIG = "MechRig"

## Chest height added above the shoulder line, so the shoulders reach the rig shoulders.
CHEST_RAISE = 0.35
## Width factor of the chest, so the chest side reaches the shoulder roller.
CHEST_WIDE = 1.12
## Size of the head about the bottom of the neck, so the mech stays about 10 m tall.
HEAD_SCALE = 0.95
## Height the head bottom moves to, with the chest raise.
NECK_BOTTOM = (8.18, 8.53)
## Width factors of the pelvis pieces, so they reach the rig hips. Other pelvis pieces use PELVIS_WIDE.
HIP_WIDE = 1.55
PELVIS_WIDE = 1.35
CENTER_WIDE = 1.15
## Forward offset removed from the thigh armor (m): the rig knee is further forward than the picture's.
THIGH_BACK = 0.30
## Moves of the hanging armor (m), so the top of each plate reaches its accessory bone.
SLEEVE_MOVE = Vector((0.30, -0.35, 0.35))
SKIRT_SIDE_MOVE = Vector((0.50, -0.35, -0.10))
SKIRT_BACK_MOVE = Vector((0.0, -0.20, -0.30))
## Sizes of the hand pieces (m).
FINGER_WIDTH = 0.17
THUMB_WIDTH = 0.18

MATERIAL_JOINT = "hly_joint"
MATERIAL_TAN = "hly_tan"
MATERIAL_ARMOR = "hly_armor"


def run_build():
    source = open(BUILD_SCRIPT).read()
    scope = {"__file__": BUILD_SCRIPT, "__name__": "haliya_ref_build"}
    exec(source, scope)
    return scope


def append_rig():
    old = bpy.data.objects.get(RIG)
    if old is not None:
        bpy.data.objects.remove(old)
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


def rest_pose(rig):
    if rig.animation_data:
        rig.animation_data.action = None
        rig.animation_data.use_nla = False
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def bone_head(rig, name):
    return (rig.matrix_world @ rig.data.bones[name].head_local).copy()


def bone_tail(rig, name):
    return (rig.matrix_world @ rig.data.bones[name].tail_local).copy()


def segment_map(a, b, a2, b2):
    """Moves a to a2, turns the segment onto a2-b2 and scales along it only: the width stays."""
    d0 = (b - a).normalized()
    d1 = (b2 - a2).normalized()
    ratio = (b2 - a2).length / (b - a).length

    def apply(p):
        rel = p - a
        along = rel.dot(d0)
        rel = rel + d0 * (along * (ratio - 1.0))
        return a2 + d0.rotation_difference(d1) @ rel
    return apply


def move_map(offset):
    return lambda p: p + offset


def torso_map(p):
    z = p.z
    if z >= 7.75:
        z += CHEST_RAISE
    elif z > 6.75:
        z = 6.75 + (z - 6.75) * (1.0 + CHEST_RAISE)
    return Vector((p.x * CHEST_WIDE, p.y, z))


def pelvis_z(z):
    if z >= 6.75:
        return z
    if z >= 6.31:
        return 6.75 + (z - 6.75) * (0.80 / 0.44)
    return z - 0.36


def pelvis_map(wide):
    return lambda p: Vector((p.x * wide, p.y, pelvis_z(p.z)))


def head_map(p):
    base = Vector((0.0, 0.0, NECK_BOTTOM[0]))
    return Vector((0.0, 0.02, NECK_BOTTOM[1])) + (p - base) * HEAD_SCALE


def foot_map(a, a2):
    factor = a2.z / a.z
    return lambda p: Vector((p.x - a.x + a2.x, p.y - a.y + a2.y, p.z * factor))


def fit_rule(name, joint, side, rig, joints):
    """Returns (bone, collection, map) for a piece of the model, or None for a piece that is rebuilt."""
    tag = "L" if side > 0 else "R"
    mirror = Vector((side, 1, 1))

    def j(key):
        return joints[key] * mirror

    if name.startswith("Arm_palm") or name.startswith("Arm_hand_guard") or name.startswith("Arm_finger") \
            or name.startswith("Arm_thumb"):
        return None
    if joint == "head":
        return "head", "Head", head_map
    if joint == "torso":
        return "torso", "Core", torso_map
    if name == "Core_waist":
        return "torso", "Core", torso_map
    if name.startswith("Core_hip"):
        return "pelvis", "Legs", pelvis_map(HIP_WIDE)
    if name.startswith("Core_belt") or name == "Core_pelvis_block":
        return "pelvis", "Legs", pelvis_map(PELVIS_WIDE)
    if joint == "pelvis" and name.startswith("Core_"):
        return "pelvis", "Legs", pelvis_map(CENTER_WIDE)
    if name.startswith("Skirt_side") or name.startswith("Skirt_blade"):
        return "skirt_side_" + tag, "Legs", move_map(SKIRT_SIDE_MOVE * mirror)
    if name.startswith("Skirt_back"):
        return "skirt_back_" + tag, "Legs", move_map(SKIRT_BACK_MOVE * mirror)
    shoulder = bone_head(rig, "upper_arm_" + tag)
    elbow = bone_head(rig, "forearm_" + tag)
    wrist = bone_head(rig, "hand_" + tag)
    hip = bone_head(rig, "thigh_" + tag)
    knee = bone_head(rig, "shin_" + tag)
    ankle = bone_head(rig, "foot_" + tag)
    if name.startswith("Arm_sleeve"):
        return "sleeve_" + tag, "Arm_" + tag, move_map(SLEEVE_MOVE * mirror)
    if name.startswith("Arm_shoulder"):
        roller_center = Vector((1.13 * side, 0.10, joints["shoulder"].z))
        target = shoulder - Vector((0.06 * side, 0, 0))
        return "upper_arm_" + tag, "Arm_" + tag, move_map(target - roller_center)
    if name.startswith("Arm_upper"):
        return "upper_arm_" + tag, "Arm_" + tag, segment_map(j("shoulder"), j("elbow"), shoulder, elbow)
    if name.startswith("Arm_elbow"):
        return "forearm_" + tag, "Arm_" + tag, move_map(elbow - j("elbow"))
    if joint.startswith("forearm"):
        return "forearm_" + tag, "Arm_" + tag, segment_map(j("elbow"), j("wrist"), elbow, wrist)
    if name.startswith("Legs_hip"):
        return "thigh_" + tag, "Legs", move_map(hip - j("hip"))
    if joint.startswith("thigh"):
        fit = segment_map(j("hip"), j("knee"), hip, knee)
        back = Vector((0, THIGH_BACK, 0))
        if name.startswith("Legs_thigh_frame"):
            return "thigh_" + tag, "Legs", fit
        return "thigh_" + tag, "Legs", lambda p: fit(p) + back
    if name.startswith("Legs_knee_" + tag) or name.startswith("Legs_knee_block"):
        return "shin_" + tag, "Legs", move_map(knee - j("knee"))
    if joint.startswith("shin"):
        return "shin_" + tag, "Legs", segment_map(j("knee"), j("ankle"), knee, ankle)
    if joint.startswith("foot"):
        return "foot_" + tag, "Legs", foot_map(j("ankle"), ankle)
    raise ValueError("no rule for %s on %s" % (name, joint))


def bind(obj, rig, bone, collection):
    world = obj.matrix_world.copy()
    inverse = rig.matrix_world.inverted()
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
    return world, inverse


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
    """Eight points of a box along a bone, tapered a little to the tip."""
    b = rig.data.bones[bone]
    m = rig.matrix_world @ b.matrix_local
    x = m.col[0].xyz.normalized()
    z = m.col[2].xyz.normalized()
    head = bone_head(rig, bone)
    tail = bone_tail(rig, bone)
    points = []
    for c, w in ((head, width), (tail, width * 0.85)):
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                points.append(c + x * (w * sx) + z * (w * sz))
    return points


def build_hand(rig, side, tag):
    collection = "Arm_" + tag
    hand = "hand_" + tag
    wrist = bone_head(rig, hand)
    knuckles = bone_tail(rig, hand)
    roots = [bone_head(rig, "%s_01_%s" % (f, tag)) for f in ("index", "middle", "ring", "pinky")]
    back = Vector((side, 0, 0))
    palm = []
    for r in roots:
        for s in (-0.18, 0.18):
            palm.append(r + back * s + Vector((0, 0, 0.04)))
    middle = (roots[0] + roots[-1]) * 0.5
    front = (roots[0] - roots[-1]).normalized()
    for s in (-0.18, 0.18):
        for t in (-0.22, 0.22):
            palm.append(wrist + (knuckles - wrist) * 0.10 + back * s + front * t)
    thumb = bone_head(rig, "thumb_01_" + tag)
    for s in (-0.08, 0.08):
        palm.append(thumb + back * s)
    add_hull("Arm_palm_" + tag, palm, rig, hand, collection, MATERIAL_JOINT, 0.02)
    # Tan guard on the back of the hand.
    guard = []
    top = wrist + (knuckles - wrist) * 0.02
    for s, reach in ((0.17, 0.0), (0.27, 0.04)):
        for t in (-0.26, 0.26):
            guard.append(top + back * s + front * t)
        for t in (-0.34, 0.34):
            guard.append(middle + back * (s + reach) + front * t + Vector((0, 0, 0.10)))
    add_hull("Arm_hand_guard_" + tag, guard, rig, hand, collection, MATERIAL_TAN, 0.02)
    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        width = THUMB_WIDTH if finger == "thumb" else FINGER_WIDTH
        for i in (1, 2, 3):
            bone = "%s_%02d_%s" % (finger, i, tag)
            add_hull("Arm_%s_%d_%s" % (finger, i, tag), bone_box(rig, bone, width), rig, bone, collection,
                     MATERIAL_JOINT)


def box_points(x0, x1, y0, y1, z0, z1):
    return [Vector((x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def build_fill(rig):
    """Dark pieces that close the gaps the move to the rig opens: the waist and the chest flanks on the torso, a
    sheath on each upper arm from the shoulder to the tan plate."""
    add_hull("Core_waist_column", box_points(-0.40, 0.40, -0.34, 0.36, 5.95, 6.95), rig, "torso", "Core",
             MATERIAL_JOINT, 0.05)
    for tag, side in (("L", 1), ("R", -1)):
        flank = [Vector((p.x * side, p.y, p.z)) for p in (
            Vector((0.50, -0.46, 7.70)), Vector((1.10, -0.40, 7.70)), Vector((0.50, 0.40, 7.70)),
            Vector((1.10, 0.36, 7.70)), Vector((0.50, -0.42, 7.05)), Vector((1.22, -0.34, 7.12)),
            Vector((0.50, 0.36, 7.05)), Vector((1.22, 0.30, 7.12)))]
        add_hull("Core_flank_" + tag, flank, rig, "torso", "Core", MATERIAL_ARMOR, 0.03)
        shoulder = bone_head(rig, "upper_arm_" + tag)
        elbow = bone_head(rig, "forearm_" + tag)
        along = elbow - shoulder
        forward = Vector((0, 1, 0))
        out = along.normalized().cross(forward).normalized()
        sheath = []
        for t, half in ((0.06, 0.23), (0.62, 0.20)):
            c = shoulder + along * t
            for su in (-1, 1):
                for sv in (-1, 1):
                    sheath.append(c + out * (su * half) + forward * (sv * half))
        add_hull("Arm_upper_sheath_" + tag, sheath, rig, "upper_arm_" + tag, "Arm_" + tag, MATERIAL_ARMOR, 0.03)


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    scope = run_build()
    joints = {"shoulder": scope["SHOULDER"].copy(), "elbow": scope["ELBOW"].copy(), "wrist": scope["WRIST"].copy(),
              "hip": scope["HIP"].copy(), "knee": scope["KNEE"].copy(), "ankle": scope["ANKLE"].copy()}
    rig = append_rig()
    mech_rig_standard.ensure_accessory_bones(rig)
    rest_pose(rig)
    bpy.context.view_layer.update()

    root = bpy.data.collections["Haliya_HLY101"]
    pieces = [o for c in root.children for o in c.objects if o.type == "MESH"]
    empties = [o for c in root.children for o in c.objects if o.type == "EMPTY"]
    inverse = rig.matrix_world.inverted()
    for obj in pieces:
        joint = obj.parent.name
        side = -1 if obj.name.endswith("_R") or "_R_" in obj.name else 1
        # Waist ribs and guards carry the side inside the name, before a digit.
        for marker in ("_R0", "_R1"):
            if marker in obj.name:
                side = -1
        rule = fit_rule(obj.name, joint, side, rig, joints)
        if rule is None:
            bpy.data.objects.remove(obj)
            continue
        bone, collection, fit = rule
        world = obj.matrix_world.copy()
        for v in obj.data.vertices:
            v.co = inverse @ fit(world @ v.co)
        bind(obj, rig, bone, collection)
    for e in empties:
        bpy.data.objects.remove(e)
    for tag, side in (("L", 1), ("R", -1)):
        build_hand(rig, side, tag)
    build_fill(rig)
    # Flat normals point the right way only with clean winding after the moves.
    for obj in (o for c in root.children for o in c.objects if o.type == "MESH"):
        obj.data.update()
    rig.animation_data_create()
    rig.animation_data.use_nla = False
    bpy.context.view_layer.update()
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
    print("saved", OUT_BLEND)


if __name__ == "__main__":
    main()
