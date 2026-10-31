"""Builds Haliya (HLY-101) on the joint standard (user picture 2026-10-31, models/guides/haliya_ref.png).

Slim faceted mech: gunmetal armor with tan panels, a round tan face disc with one black eye, two tall horns,
sleeves (wing-like plates) over the shoulders, a skirt of six long panels at the hips, high-heel feet.
Every part sits on the SGG-101 rig (same joints, so every animation plays) and is rigid: each mesh has one
bone at full weight (the fingers use their own bones). A ball joint covers every joint, so no gap opens and
nothing tears when a joint bends. The child part owns the joint ball (DESIGN "Swappable mech parts").

Run headless (pip bpy 5.2.2):
  python tools/blender/haliya_build.py
It opens the SGG file for its rig and actions, removes the SGG meshes, adds the accessory bones, builds Haliya
into the part collections, saves models/haliya/haliya.blend and exports models/mechs/hly/hly_<part>.glb.
"""
import math
import os
import sys

import bpy  # first: bpy loads bmesh and mathutils
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import mech_rig_standard  # noqa: E402

SOURCE = os.path.join(ROOT, "models/new_mech/new_mech_exploded.blend")
OUT_BLEND = os.path.join(ROOT, "models/haliya/haliya.blend")
OUT_PARTS = os.path.join(ROOT, "models/mechs/hly")
RIG = "MechRig"
PARTS = ["Head", "Core", "Arm_L", "Arm_R", "Legs"]

## Colors from the picture (linear).
COLORS = {
    "hly_armor": (0.07, 0.073, 0.08),     # gunmetal
    "hly_tan": (0.5, 0.44, 0.3),          # sand
    "hly_joint": (0.018, 0.018, 0.02),    # black joints and frame
    "hly_eye": (0.004, 0.004, 0.005),     # the eye
}
## Chamfer width (m) of the faceted armor.
BEVEL = 0.06

rig = None


# ---------------------------------------------------------------- helpers

def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*COLORS[name], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.55 if name != "hly_joint" else 0.4
        bsdf.inputs["Metallic"].default_value = 0.35 if name != "hly_tan" else 0.1
        mat.diffuse_color = (*COLORS[name], 1.0)
    return mat


def _finish(name, bm, part, bone, mat, bones=None):
    """Mesh object from bm, in a part collection, rigid on bone (or on several bones: bones = {vertex: bone})."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections[part].objects.link(obj)
    obj.data.materials.append(material(mat))
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.parent = rig
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


def hull(name, points, part, bone, mat="hly_armor", bevel=BEVEL):
    """Convex hull of points (world, rest pose), chamfered edges: the faceted armor look."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(Vector(p))
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=1, affect="EDGES",
                        clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return _finish(name, bm, part, bone, mat)


def ball(name, center, radius, part, bone, mat="hly_joint"):
    """Ball joint: a low-poly sphere (faceted like the armor)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=radius,
                              matrix=Matrix.Translation(Vector(center)))
    return _finish(name, bm, part, bone, mat)


def disc(name, center, axis, radius, depth, part, bone, mat, sides=12, bevel=0.03):
    """Flat cylinder (face disc, eye) along axis."""
    bm = bmesh.new()
    rot = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=depth,
                          matrix=Matrix.Translation(Vector(center)) @ rot)
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES", clamp_overlap=True)
    return _finish(name, bm, part, bone, mat)


def bone_frame(name):
    """World head, tail and the bone's x (side) and z (front) axes at rest."""
    b = rig.data.bones[name]
    m = rig.matrix_world @ b.matrix_local
    head = rig.matrix_world @ b.head_local
    tail = rig.matrix_world @ b.tail_local
    return head, tail, m.col[0].xyz.normalized(), m.col[2].xyz.normalized()


def seg(bone, t0, t1, w0, d0, w1, d1, off=(0.0, 0.0), out=None):
    """8 points of a tapered box along a bone, from t0 to t1 (parts of its length): width w along the bone's
    x axis, depth d along its z axis (front), centered at off (x, z). out: a side to push the box to (world)."""
    head, tail, x, z = bone_frame(bone)
    pts = []
    for t, w, d in ((t0, w0, d0), (t1, w1, d1)):
        c = head.lerp(tail, t) + x * off[0] + z * off[1]
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                pts.append(c + x * (w * sx) + z * (d * sz))
    return pts


def mirror(points):
    return [Vector((-p[0], p[1], p[2])) for p in points]


def side_points(points, side):
    return [Vector(p) for p in points] if side == "L" else mirror(points)


# ---------------------------------------------------------------- parts

def build_head():
    h0, h1, _x, _z = bone_frame("head")
    ball("HLY_Neck_Ball", (0.0, 0.0, 9.0), 0.22, "Head", "head")
    hull("HLY_Neck", [(-0.15, -0.12, 9.0), (0.15, -0.12, 9.0), (-0.15, 0.18, 9.0), (0.15, 0.18, 9.0),
                      (-0.13, -0.1, 9.32), (0.13, -0.1, 9.32), (-0.13, 0.16, 9.32), (0.13, 0.16, 9.32)],
         "Head", "head", "hly_joint", 0.03)
    # Helmet: a narrow rounded block behind the face disc.
    hull("HLY_Helmet", [(-0.36, -0.22, 9.18), (0.36, -0.22, 9.18), (-0.3, 0.42, 9.2), (0.3, 0.42, 9.2),
                        (-0.4, -0.25, 9.62), (0.4, -0.25, 9.62), (-0.32, 0.48, 9.6), (0.32, 0.48, 9.6),
                        (-0.28, -0.18, 10.0), (0.28, -0.18, 10.0), (-0.2, 0.36, 9.95), (0.2, 0.36, 9.95)],
         "Head", "head", "hly_armor", 0.08)
    # Face: the round tan disc with one black eye (picture front).
    disc("HLY_Face", (0.0, -0.33, 9.6), (0, -1, 0), 0.5, 0.12, "Head", "head", "hly_tan", 14, 0.025)
    disc("HLY_Face_Rim", (0.0, -0.26, 9.6), (0, -1, 0), 0.53, 0.06, "Head", "head", "hly_armor", 14, 0.0)
    disc("HLY_Eye", (0.0, -0.41, 9.6), (0, -1, 0), 0.16, 0.06, "Head", "head", "hly_eye", 12, 0.015)
    # Horns: tall blades up and out behind the face.
    for side in ("L", "R"):
        pts = [(0.22, 0.02, 9.35), (0.42, 0.02, 9.2), (0.22, 0.42, 9.35), (0.42, 0.42, 9.2),
               (0.3, 0.12, 9.75), (0.3, 0.32, 9.75), (1.12, 0.28, 10.75), (1.08, 0.2, 10.7)]
        hull("HLY_Horn_" + side, side_points(pts, side), "Head", "head", "hly_armor", 0.03)


def build_core():
    ball("HLY_Waist_Ball", (0.0, -0.05, 6.78), 0.32, "Core", "torso")
    # Waist: three dark rings, the narrow waist of the picture.
    for i, z in enumerate((6.98, 7.22, 7.46)):
        w = 0.5 + 0.04 * i
        hull("HLY_Waist_%d" % (i + 1), [(-w, -0.42, z), (w, -0.42, z), (-w, 0.38, z), (w, 0.38, z),
                                        (-w, -0.42, z + 0.18), (w, -0.42, z + 0.18), (-w, 0.38, z + 0.18),
                                        (w, 0.38, z + 0.18)], "Core", "torso", "hly_joint", 0.04)
    # Chest: dark, widest under the shoulders.
    hull("HLY_Chest", [(-0.62, -0.5, 7.62), (0.62, -0.5, 7.62), (-0.62, 0.48, 7.62), (0.62, 0.48, 7.62),
                       (-1.05, -0.66, 8.32), (1.05, -0.66, 8.32), (-1.05, 0.55, 8.32), (1.05, 0.55, 8.32),
                       (-0.82, -0.48, 9.02), (0.82, -0.48, 9.02), (-0.82, 0.5, 9.02), (0.82, 0.5, 9.02)],
         "Core", "torso", "hly_armor", 0.1)
    # Tan front plates: a V over the chest and a tan abdomen block.
    for side in ("L", "R"):
        pts = [(0.06, -0.62, 7.75), (0.36, -0.6, 7.75), (0.06, -0.78, 8.3), (0.62, -0.72, 8.42),
               (0.06, -0.62, 8.95), (0.55, -0.56, 8.98), (0.06, -0.5, 8.3), (0.45, -0.5, 8.4)]
        hull("HLY_Chest_Plate_" + side, side_points(pts, side), "Core", "torso", "hly_tan", 0.04)
    hull("HLY_Abdomen", [(-0.3, -0.58, 7.36), (0.3, -0.58, 7.36), (-0.34, -0.66, 7.7), (0.34, -0.66, 7.7),
                         (-0.3, -0.3, 7.36), (0.3, -0.3, 7.36), (-0.34, -0.3, 7.7), (0.34, -0.3, 7.7)],
         "Core", "torso", "hly_tan", 0.04)
    hull("HLY_Collar", [(-0.42, -0.36, 8.9), (0.42, -0.36, 8.9), (-0.42, 0.4, 8.9), (0.42, 0.4, 8.9),
                        (-0.34, -0.3, 9.12), (0.34, -0.3, 9.12), (-0.34, 0.34, 9.12), (0.34, 0.34, 9.12)],
         "Core", "torso", "hly_joint", 0.04)
    # Shoulder housings: the chest side that holds the shoulder ball.
    for side in ("L", "R"):
        pts = [(0.9, -0.42, 7.95), (1.12, -0.38, 8.0), (0.9, 0.42, 7.95), (1.12, 0.38, 8.0),
               (0.86, -0.42, 8.78), (1.08, -0.36, 8.7), (0.86, 0.42, 8.78), (1.08, 0.36, 8.7)]
        hull("HLY_Shoulder_Housing_" + side, side_points(pts, side), "Core", "torso", "hly_armor", 0.05)
    # Back: the tan spine strip and the hardpoint block the backpack bolts to (back face at y 1.37).
    hull("HLY_Back_Block", [(-0.6, 0.4, 7.3), (0.6, 0.4, 7.3), (-0.52, 1.3, 7.42), (0.52, 1.3, 7.42),
                            (-0.7, 0.45, 8.62), (0.7, 0.45, 8.62), (-0.58, 1.3, 8.5), (0.58, 1.3, 8.5)],
         "Core", "torso", "hly_armor", 0.08)
    hull("HLY_Spine", [(-0.17, 1.28, 7.0), (0.17, 1.28, 7.0), (-0.17, 1.38, 7.05), (0.17, 1.38, 7.05),
                       (-0.17, 1.28, 8.8), (0.17, 1.28, 8.8), (-0.17, 1.38, 8.75), (0.17, 1.38, 8.75)],
         "Core", "torso", "hly_tan", 0.03)


def build_arm(side):
    part = "Arm_" + side
    s = side
    sh, el, _x, _z = bone_frame("upper_arm_" + s)
    _fe, wr, _x2, _z2 = bone_frame("forearm_" + s)
    ball("HLY_Shoulder_Ball_" + s, sh, 0.3, part, "upper_arm_" + s)
    # Upper arm: dark core with a tan outer plate.
    hull("HLY_Upper_Arm_" + s, seg("upper_arm_" + s, 0.18, 0.86, 0.56, 0.6, 0.48, 0.52), part, "upper_arm_" + s)
    out = 0.22 if s == "L" else -0.22
    hull("HLY_Upper_Arm_Plate_" + s, seg("upper_arm_" + s, 0.25, 0.8, 0.16, 0.62, 0.14, 0.54, (out * 1.3, 0.0)),
         part, "upper_arm_" + s, "hly_tan", 0.04)
    ball("HLY_Elbow_Ball_" + s, el, 0.24, part, "forearm_" + s)
    # Forearm: tan armor, wider at the elbow end, a dark cuff at the wrist.
    hull("HLY_Forearm_" + s, seg("forearm_" + s, 0.1, 0.8, 0.7, 0.72, 0.56, 0.6), part, "forearm_" + s, "hly_tan")
    hull("HLY_Forearm_Inner_" + s, seg("forearm_" + s, 0.15, 0.85, 0.46, 0.78, 0.4, 0.66, (-out * 0.8, 0.0)),
         part, "forearm_" + s, "hly_armor", 0.04)
    hull("HLY_Cuff_" + s, seg("forearm_" + s, 0.8, 0.94, 0.4, 0.44, 0.34, 0.38), part, "forearm_" + s,
         "hly_joint", 0.03)
    ball("HLY_Wrist_Ball_" + s, wr, 0.16, part, "forearm_" + s)
    build_hand(side)
    build_sleeve(side)


def build_hand(side):
    """Black hand: palm and three segments per finger on their own bones (MechHandControl uses the jointed
    hand scenes in play and hides these; they show in Blender and in pictures)."""
    part = "Arm_" + side
    roots = [bone_frame("%s_01_%s" % (f, side))[0] for f in ("index", "middle", "ring", "pinky")
             if "%s_01_%s" % (f, side) in rig.data.bones]
    _h, _t, hx, hz = bone_frame("hand_" + side)
    palm = seg("hand_" + side, 0.0, 0.3, 0.4, 0.24, 0.42, 0.24)
    for r in roots:
        palm += [r + hz * 0.1, r - hz * 0.1]
    hull("HLY_Palm_" + side, palm, part, "hand_" + side, "hly_joint", 0.03)
    for finger in ("index", "middle", "ring", "pinky", "thumb"):
        for i in (1, 2, 3):
            bone = "%s_%02d_%s" % (finger, i, side)
            if bone not in rig.data.bones:
                continue
            w = 0.12 if finger != "thumb" else 0.14
            hull("HLY_%s_%d_%s" % (finger.capitalize(), i, side), seg(bone, 0.0, 1.0, w, w, w * 0.85, w * 0.85),
                 part, bone, "hly_joint", 0.02)


def build_sleeve(side):
    """Sleeve: a cap over the shoulder and a long wing plate outside the arm (picture), on the sleeve bone."""
    part = "Arm_" + side
    bone = "sleeve_" + side
    cap = [(1.12, -0.55, 8.62), (1.12, 0.55, 8.62), (1.12, -0.5, 9.0), (1.12, 0.5, 9.0),
           (2.42, -0.6, 8.42), (2.42, 0.6, 8.42), (2.32, -0.55, 8.92), (2.32, 0.55, 8.92)]
    hull("HLY_Sleeve_Cap_" + side, side_points(cap, side), part, bone, "hly_armor", 0.07)
    wing = [(2.12, -0.55, 8.62), (2.12, 0.55, 8.62), (2.62, -0.6, 8.95), (2.62, 0.6, 8.95),
            (3.55, -0.42, 6.8), (3.55, 0.42, 6.8), (3.12, -0.36, 6.5), (3.12, 0.36, 6.5),
            (3.45, -0.1, 4.95), (3.45, 0.12, 4.95)]
    hull("HLY_Sleeve_Wing_" + side, side_points(wing, side), part, bone, "hly_armor", 0.06)
    strip = [(2.38, -0.58, 8.7), (2.38, 0.58, 8.7), (2.55, -0.6, 8.82), (2.55, 0.6, 8.82),
             (3.32, -0.43, 6.9), (3.32, 0.43, 6.9), (3.42, -0.42, 6.95), (3.42, 0.42, 6.95)]
    hull("HLY_Sleeve_Strip_" + side, side_points(strip, side), part, bone, "hly_tan", 0.02)


def build_legs():
    part = "Legs"
    # Pelvis: the dark groin wedge and the bars to the hip balls.
    hull("HLY_Pelvis", [(-0.52, -0.55, 6.6), (0.52, -0.55, 6.6), (-0.52, 0.5, 6.6), (0.52, 0.5, 6.6),
                        (-0.5, -0.6, 5.85), (0.5, -0.6, 5.85), (-0.45, 0.45, 5.75), (0.45, 0.45, 5.75),
                        (-0.2, -0.62, 5.15), (0.2, -0.62, 5.15), (-0.18, 0.1, 5.2), (0.18, 0.1, 5.2)],
         part, "pelvis", "hly_armor", 0.08)
    hull("HLY_Groin_Plate", [(-0.3, -0.64, 6.3), (0.3, -0.64, 6.3), (-0.16, -0.68, 5.35), (0.16, -0.68, 5.35),
                             (-0.3, -0.56, 6.3), (0.3, -0.56, 6.3), (-0.16, -0.6, 5.35), (0.16, -0.6, 5.35)],
         part, "pelvis", "hly_tan", 0.03)
    hull("HLY_Hip_Bar", [(-1.0, -0.2, 5.78), (1.0, -0.2, 5.78), (-1.0, 0.2, 5.78), (1.0, 0.2, 5.78),
                         (-1.0, -0.2, 6.06), (1.0, -0.2, 6.06), (-1.0, 0.2, 6.06), (1.0, 0.2, 6.06)],
         part, "pelvis", "hly_joint", 0.04)
    # Skirt belt: the hip ring the six skirt panels hang from.
    hull("HLY_Skirt_Belt", [(-1.92, -0.5, 6.36), (1.92, -0.5, 6.36), (-1.92, 0.5, 6.36), (1.92, 0.5, 6.36),
                            (-1.1, -0.74, 6.36), (1.1, -0.74, 6.36), (-1.1, 0.74, 6.36), (1.1, 0.74, 6.36),
                            (-1.9, -0.5, 6.74), (1.9, -0.5, 6.74), (-1.9, 0.5, 6.74), (1.9, 0.5, 6.74),
                            (-1.08, -0.74, 6.74), (1.08, -0.74, 6.74), (-1.08, 0.74, 6.74), (1.08, 0.74, 6.74)],
         part, "pelvis", "hly_joint", 0.05)
    for s in ("L", "R"):
        build_leg(s)
        build_skirt(s)


def build_leg(s):
    part = "Legs"
    hip, knee, _x, _z = bone_frame("thigh_" + s)
    _k, ankle, _x2, _z2 = bone_frame("shin_" + s)
    ball("HLY_Hip_Ball_" + s, hip, 0.33, part, "thigh_" + s)
    hull("HLY_Thigh_" + s, seg("thigh_" + s, 0.12, 0.86, 0.86, 0.9, 0.66, 0.72), part, "thigh_" + s)
    hull("HLY_Thigh_Plate_" + s, seg("thigh_" + s, 0.2, 0.74, 0.66, 0.14, 0.54, 0.12, (0.0, 0.48)),
         part, "thigh_" + s, "hly_tan", 0.03)
    ball("HLY_Knee_Ball_" + s, knee, 0.31, part, "shin_" + s)
    # Knee guard (front) and the shin: a tan calf block on a slim dark shin.
    hull("HLY_Knee_Guard_" + s, seg("shin_" + s, -0.12, 0.16, 0.6, 0.22, 0.52, 0.2, (0.0, 0.4)),
         part, "shin_" + s, "hly_armor", 0.05)
    hull("HLY_Shin_" + s, seg("shin_" + s, 0.12, 0.88, 0.6, 0.64, 0.42, 0.48), part, "shin_" + s)
    hull("HLY_Calf_" + s, seg("shin_" + s, 0.14, 0.6, 0.64, 0.42, 0.5, 0.34, (0.0, -0.26)), part, "shin_" + s,
         "hly_tan", 0.04)
    hull("HLY_Shin_Plate_" + s, seg("shin_" + s, 0.55, 0.85, 0.42, 0.12, 0.36, 0.1, (0.0, 0.3)),
         part, "shin_" + s, "hly_tan", 0.02)
    ball("HLY_Ankle_Ball_" + s, ankle, 0.2, part, "foot_" + s)
    # High-heel foot: a wedge from the ankle to the pointed toe, a heel post at the back.
    a = ankle
    wedge = [(a.x - 0.26, a.y - 0.05, a.z + 0.12), (a.x + 0.26, a.y - 0.05, a.z + 0.12),
             (a.x - 0.26, a.y + 0.3, a.z + 0.05), (a.x + 0.26, a.y + 0.3, a.z + 0.05),
             (a.x - 0.34, a.y - 0.85, 0.0), (a.x + 0.34, a.y - 0.85, 0.0),
             (a.x - 0.34, a.y - 0.85, 0.3), (a.x + 0.34, a.y - 0.85, 0.3),
             (a.x - 0.08, a.y - 1.75, 0.0), (a.x + 0.08, a.y - 1.75, 0.0), (a.x, a.y - 1.75, 0.12)]
    hull("HLY_Foot_" + s, wedge, part, "foot_" + s, "hly_armor", 0.04)
    top = [(a.x - 0.22, a.y - 0.2, a.z + 0.02), (a.x + 0.22, a.y - 0.2, a.z + 0.02),
           (a.x - 0.26, a.y - 0.8, 0.36), (a.x + 0.26, a.y - 0.8, 0.36),
           (a.x - 0.22, a.y - 0.2, a.z - 0.12), (a.x + 0.22, a.y - 0.2, a.z - 0.12),
           (a.x - 0.26, a.y - 0.8, 0.24), (a.x + 0.26, a.y - 0.8, 0.24)]
    hull("HLY_Foot_Plate_" + s, top, part, "foot_" + s, "hly_tan", 0.03)
    heel = [(a.x - 0.13, a.y + 0.22, a.z - 0.1), (a.x + 0.13, a.y + 0.22, a.z - 0.1),
            (a.x - 0.13, a.y + 0.5, a.z - 0.1), (a.x + 0.13, a.y + 0.5, a.z - 0.1),
            (a.x - 0.09, a.y + 0.48, 0.0), (a.x + 0.09, a.y + 0.48, 0.0),
            (a.x - 0.09, a.y + 0.66, 0.0), (a.x + 0.09, a.y + 0.66, 0.0)]
    hull("HLY_Heel_" + s, heel, part, "foot_" + s, "hly_joint", 0.03)


def build_skirt(s):
    """Six long panels at the hips (picture), each on its accessory bone so it can swing off the thigh."""
    part = "Legs"
    front = [(0.18, -0.6, 6.62), (1.08, -0.62, 6.58), (0.18, -0.72, 6.62), (1.08, -0.74, 6.58),
             (0.78, -0.88, 3.3), (1.4, -0.9, 3.55), (0.78, -0.98, 3.3), (1.4, -1.0, 3.55),
             (1.08, -1.0, 2.95)]
    hull("HLY_Skirt_Front_" + s, side_points(front, s), part, "skirt_front_" + s, "hly_armor", 0.04)
    inner = [(0.24, -0.73, 6.4), (0.5, -0.74, 6.4), (0.24, -0.76, 6.4), (0.5, -0.77, 6.4),
             (0.84, -0.99, 3.6), (0.98, -1.0, 3.6), (0.84, -1.02, 3.6), (0.98, -1.03, 3.6)]
    hull("HLY_Skirt_Front_Strip_" + s, side_points(inner, s), part, "skirt_front_" + s, "hly_tan", 0.01)
    side = [(1.6, -0.48, 6.68), (1.6, 0.48, 6.68), (1.82, -0.5, 6.6), (1.82, 0.5, 6.6),
            (2.32, -0.28, 4.4), (2.32, 0.32, 4.4), (2.12, -0.24, 4.3), (2.12, 0.28, 4.3),
            (2.38, 0.02, 2.6), (2.38, 0.1, 2.6)]
    hull("HLY_Skirt_Side_" + s, side_points(side, s), part, "skirt_side_" + s, "hly_armor", 0.04)
    back = [(0.18, 0.58, 6.62), (1.08, 0.58, 6.58), (0.18, 0.7, 6.62), (1.08, 0.72, 6.58),
            (0.78, 1.0, 3.45), (1.4, 1.02, 3.7), (0.78, 1.1, 3.45), (1.4, 1.12, 3.7),
            (1.08, 1.12, 3.1)]
    hull("HLY_Skirt_Back_" + s, side_points(back, s), part, "skirt_back_" + s, "hly_armor", 0.04)


# ---------------------------------------------------------------- main

def main():
    global rig
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    rig = bpy.data.objects[RIG]
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o)
    for c in PARTS:
        if c not in bpy.data.collections:
            bpy.context.scene.collection.children.link(bpy.data.collections.new(c))
    mech_rig_standard.ensure_accessory_bones(rig)
    ad = rig.animation_data
    if ad:
        ad.action = None
        ad.use_nla = False
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    build_head()
    build_core()
    build_arm("L")
    build_arm("R")
    build_legs()
    if ad:
        ad.use_nla = True
    # Drop the SGG meshes, images and the weapon left without users (the file keeps the rig and its actions).
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
    counts = {c: len(bpy.data.collections[c].objects) for c in PARTS}
    faces = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print("HALIYA saved", OUT_BLEND, counts, faces, "faces")
    import export_mech_parts
    sys.argv = [sys.argv[0], "--", OUT_BLEND, "hly", OUT_PARTS, "parts"]
    export_mech_parts.main()


if __name__ == "__main__":
    main()
