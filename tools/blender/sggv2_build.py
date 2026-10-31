"""SGGv2: SGG-101 with more body, heft and character (user request 2026-10-31).

Opens the user's SGG file (models/new_mech/new_mech_exploded.blend, not changed), and:
  1. Heft: thickens the torso, pelvis, arms and legs about their bones (the length along the bone stays, so the
     joints, the grips and every animation stay the same).
  2. Character: adds faceted armor in SGG's own palette (olive armor, darker olive accent panels, dark grey frame,
     orange lamps): shoulder flares, forearm guards, a chest plate and collar, side plates, a groin plate, thigh
     plates, knee guards, shin guards, tassets on the skirt bones (they swing off the thighs, AccessoryBoneFollow),
     a head crest, antennas and a chin guard, and lamps. Each piece is rigid on one bone (no tearing) and goes in
     its part collection (the child part owns it).
  3. Saves models/sggv2/sggv2.blend and exports the part files models/mechs/sgg/sgg_<part>.glb (the rig file
     does not change).
The colors of the new pieces are small textures, so every skin (Basic, PS1, Realistic, Paint) treats them like
the SGG texture: the Paint skin turns olive into the main color and the accent panels into the accent color.

Run headless (pip bpy 5.2.2):  python tools/blender/sggv2_build.py
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
OUT_BLEND = os.path.join(ROOT, "models/sggv2/sggv2.blend")
OUT_PARTS = os.path.join(ROOT, "models/mechs/sgg")
RIG = "MechRig"

## Thickening per mesh: (bone, factor across the bone).
HEFT = {
    "Torso": ("torso", 1.08), "Pelvis": ("pelvis", 1.08),
    "Arm_L_01": ("upper_arm_L", 1.1), "Arm_R_01": ("upper_arm_R", 1.1),
    "Arm_L_02": ("forearm_L", 1.12), "Arm_R_02": ("forearm_R", 1.12),
    "Leg_L_01": ("thigh_L", 1.12), "Leg_R_02": ("thigh_R", 1.12),
    "Leg_L_02": ("shin_L", 1.12), "Leg_R_03": ("shin_R", 1.12),
}
## Mesh names per side.
THIGH = {"L": "Leg_L_01", "R": "Leg_R_02"}
SHIN = {"L": "Leg_L_02", "R": "Leg_R_03"}

## SGG palette (sRGB, like its texture): the skins read these like the SGG texture.
PALETTE = {
    "sgg2_armor": (0.63, 0.63, 0.26),   # olive armor (Paint: main color)
    "sgg2_panel": (0.36, 0.36, 0.13),   # darker olive panel (Paint: accent color)
    "sgg2_frame": (0.2, 0.2, 0.21),     # dark grey frame
    "sgg2_lamp": (1.0, 0.55, 0.08),     # orange lamp
}
BEVEL = 0.05

rig = None


# ---------------------------------------------------------------- helpers

def material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    image = bpy.data.images.new(name, 4, 4)
    rgb = PALETTE[name]
    image.colorspace_settings.name = "sRGB"
    image.pixels = [c for _ in range(16) for c in (*rgb, 1.0)]
    image.pack()
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.2
    if name == "sgg2_lamp":
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return mat


def part_of(bone):
    if bone.startswith(("head",)):
        return "Head"
    if bone.startswith(("torso",)):
        return "Core"
    if bone.endswith("_L") and bone.startswith(("upper_arm", "forearm", "hand", "sleeve")):
        return "Arm_L"
    if bone.endswith("_R") and bone.startswith(("upper_arm", "forearm", "hand", "sleeve")):
        return "Arm_R"
    return "Legs"


def hull(name, points, bone, mat="sgg2_armor", bevel=BEVEL):
    """Faceted piece: convex hull of world points (rest pose), chamfered, rigid on bone."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(Vector(p))
    bmesh.ops.convex_hull(bm, input=bm.verts[:])
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=bevel, segments=1, affect="EDGES",
                        clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # A box UV per face, so the 4x4 color texture is sampled everywhere.
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (0.5, 0.5)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections[part_of(bone)].objects.link(obj)
    obj.data.materials.append(material(mat))
    obj.parent = rig
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


def bone_matrix(bone):
    """World matrix of a bone at rest: x side, y along the bone, z its third axis."""
    return rig.matrix_world @ rig.data.bones[bone].matrix_local


def extent(mesh_name, bone):
    """Box of a mesh in the bone's frame: (min, max)."""
    obj = bpy.data.objects[mesh_name]
    inv = bone_matrix(bone).inverted()
    pts = [inv @ (obj.matrix_world @ v.co) for v in obj.data.vertices]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def local_box(bone, x0, x1, y0, y1, z0, z1, shrink_end=0.0):
    """8 world points of a box given in the bone's frame; shrink_end narrows the y1 end (x and z) by that part."""
    m = bone_matrix(bone)
    pts = []
    for y in (y0, y1):
        s = shrink_end if y == y1 else 0.0
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        for x in (x0, x1):
            for z in (z0, z1):
                pts.append(m @ Vector((cx + (x - cx) * (1 - s), y, cz + (z - cz) * (1 - s))))
    return pts


def axis_sign(bone, world_dir, axis):
    """+1 or -1: the sign of the bone's local axis (0 x, 2 z) that points along world_dir."""
    col = bone_matrix(bone).col[axis].xyz
    return 1.0 if col.dot(Vector(world_dir)) >= 0 else -1.0


def thicken(mesh_name, bone, factor):
    obj = bpy.data.objects[mesh_name]
    m = bone_matrix(bone)
    inv = m.inverted()
    to_obj = obj.matrix_world.inverted()
    for v in obj.data.vertices:
        p = inv @ (obj.matrix_world @ v.co)
        p = Vector((p.x * factor, p.y, p.z * factor))
        v.co = to_obj @ (m @ p)


# ---------------------------------------------------------------- armor

def side_plate(name, mesh, bone, side, along=(0.15, 0.75), depth=0.12, inset=0.12, mat="sgg2_armor",
               stripe=True, axis=0):
    """Plate on the outer face of a limb mesh (axis 0 = the side, 2 = the front), with an accent stripe."""
    lo, hi = extent(mesh, bone)
    out = Vector((1, 0, 0)) if side == "L" else Vector((-1, 0, 0))
    if axis == 2:
        out = Vector((0, -1, 0))
    sgn = axis_sign(bone, out, axis)
    face = hi[axis] if sgn > 0 else lo[axis]
    y0 = lo.y + (hi.y - lo.y) * along[0]
    y1 = lo.y + (hi.y - lo.y) * along[1]
    other = 2 if axis == 0 else 0
    a0, a1 = lo[other] + inset, hi[other] - inset
    f0, f1 = face - sgn * 0.03, face + sgn * depth

    def box(o0, o1, f_0, f_1, ya, yb, shrink):
        if axis == 0:
            return local_box(bone, min(f_0, f_1), max(f_0, f_1), ya, yb, o0, o1, shrink)
        return local_box(bone, o0, o1, ya, yb, min(f_0, f_1), max(f_0, f_1), shrink)

    hull(name, box(a0, a1, f0, f1, y0, y1, 0.2), bone, mat)
    if stripe:
        mid = (a0 + a1) / 2
        w = (a1 - a0) * 0.12
        hull(name + "_Stripe", box(mid - w, mid + w, f1 - sgn * 0.01, f1 + sgn * 0.035, y0 + 0.1, y1 - 0.15, 0.2),
             bone, "sgg2_panel", 0.01)


def build_arms():
    for s in ("L", "R"):
        # Shoulder flare on the outside of the shoulder block, and a top ridge outside the shoulder pods.
        side_plate("SGG2_Shoulder_Flare_" + s, "Arm_%s_01" % s, "upper_arm_" + s, s, (0.0, 0.55), 0.14, 0.18)
        side_plate("SGG2_Forearm_Guard_" + s, "Arm_%s_02" % s, "forearm_" + s, s, (0.12, 0.72), 0.12, 0.14)
        # Elbow lamp: a small orange light on the back of the forearm guard.
        lo, hi = extent("Arm_%s_02" % s, "forearm_" + s)
        sgn = axis_sign("forearm_" + s, (1, 0, 0) if s == "L" else (-1, 0, 0), 0)
        face = (hi.x if sgn > 0 else lo.x) + sgn * 0.13
        hull("SGG2_Forearm_Lamp_" + s, local_box("forearm_" + s, min(face, face + sgn * 0.04),
                                                 max(face, face + sgn * 0.04), lo.y + 0.25, lo.y + 0.45,
                                                 -0.08, 0.08), "forearm_" + s, "sgg2_lamp", 0.01)


def build_core():
    lo, hi = extent("Torso", "torso")
    sgn = axis_sign("torso", (0, -1, 0), 2)  # the front
    front = hi.z if sgn > 0 else lo.z
    ylen = hi.y - lo.y
    # Chest plate: a raised center plate with an accent V.
    z0, z1 = sorted((front - sgn * 0.04, front + sgn * 0.16))
    hull("SGG2_Chest_Plate", local_box("torso", -0.62, 0.62, lo.y + ylen * 0.42, lo.y + ylen * 0.86, z0, z1, 0.25),
         "torso")
    for k in (-1, 1):
        a = local_box("torso", -0.05, 0.05, lo.y + ylen * 0.48, lo.y + ylen * 0.82, z1 - sgn * 0.02, z1 + sgn * 0.04)
        pts = [p + bone_matrix("torso").col[0].xyz * (k * 0.3 * (i // 4 == 0 and 1 or 0.2)) for i, p in enumerate(a)]
        hull("SGG2_Chest_V_%d" % (1 if k > 0 else 2), pts, "torso", "sgg2_panel", 0.01)
    # Collar ridge over the top front of the chest.
    hull("SGG2_Collar", local_box("torso", -0.85, 0.85, hi.y - 0.28, hi.y + 0.12, *sorted((front - sgn * 0.6,
                                                                                          front + sgn * 0.06)), 0.3),
         "torso", "sgg2_frame")
    # Side plates: wider flanks under the arms.
    for k, side in ((1, "L"), (-1, "R")):
        x = (hi.x if axis_sign("torso", (k, 0, 0), 0) > 0 else lo.x)
        sx = axis_sign("torso", (k, 0, 0), 0)
        hull("SGG2_Flank_" + side, local_box("torso", *sorted((x - sx * 0.05, x + sx * 0.14)),
                                             lo.y + ylen * 0.12, lo.y + ylen * 0.55, lo.z + 0.5, hi.z - 0.5, 0.2),
             "torso")
    # Chest lamps: two orange lights under the collar.
    for k in (-1, 1):
        hull("SGG2_Chest_Lamp_%d" % (1 if k > 0 else 2),
             local_box("torso", k * 0.42 - 0.09, k * 0.42 + 0.09, hi.y - 0.42, hi.y - 0.32, *sorted((z1 - sgn * 0.02,
                                                                                                  z1 + sgn * 0.03))),
             "torso", "sgg2_lamp", 0.01)


def build_head():
    head = bpy.data.objects["Head.001"]
    corners = [head.matrix_world @ Vector(c) for c in head.bound_box]
    lo = Vector([min(c[i] for c in corners) for i in range(3)])
    hi = Vector([max(c[i] for c in corners) for i in range(3)])
    cx = (lo.x + hi.x) / 2
    # Crest: a swept blade along the top, an accent edge.
    hull("SGG2_Crest", [(cx - 0.07, lo.y + 0.35, hi.z - 0.02), (cx + 0.07, lo.y + 0.35, hi.z - 0.02),
                        (cx - 0.07, hi.y - 0.2, hi.z - 0.02), (cx + 0.07, hi.y - 0.2, hi.z - 0.02),
                        (cx - 0.05, hi.y + 0.1, hi.z + 0.55), (cx + 0.05, hi.y + 0.1, hi.z + 0.55),
                        (cx - 0.05, lo.y + 0.6, hi.z + 0.12), (cx + 0.05, lo.y + 0.6, hi.z + 0.12)], "head")
    hull("SGG2_Crest_Edge", [(cx - 0.03, lo.y + 0.55, hi.z + 0.1), (cx + 0.03, lo.y + 0.55, hi.z + 0.1),
                             (cx - 0.03, hi.y + 0.08, hi.z + 0.54), (cx + 0.03, hi.y + 0.08, hi.z + 0.54),
                             (cx - 0.03, lo.y + 0.55, hi.z + 0.16), (cx + 0.03, lo.y + 0.55, hi.z + 0.16),
                             (cx - 0.03, hi.y + 0.1, hi.z + 0.6), (cx + 0.03, hi.y + 0.1, hi.z + 0.6)],
         "head", "sgg2_panel", 0.01)
    # Antennas at the back corners, swept back.
    for k in (-1, 1):
        x = cx + k * (hi.x - lo.x) * 0.36
        hull("SGG2_Antenna_%d" % (1 if k > 0 else 2),
             [(x - 0.04, hi.y - 0.35, hi.z - 0.05), (x + 0.04, hi.y - 0.35, hi.z - 0.05),
              (x - 0.04, hi.y - 0.25, hi.z - 0.05), (x + 0.04, hi.y - 0.25, hi.z - 0.05),
              (x + k * 0.12, hi.y + 0.45, hi.z + 0.75), (x + k * 0.12 + 0.02, hi.y + 0.47, hi.z + 0.75)],
             "head", "sgg2_frame", 0.0)
    # Chin guard under the face.
    hull("SGG2_Chin", [(cx - 0.35, lo.y + 0.02, lo.z + 0.05), (cx + 0.35, lo.y + 0.02, lo.z + 0.05),
                       (cx - 0.42, lo.y + 0.45, lo.z + 0.05), (cx + 0.42, lo.y + 0.45, lo.z + 0.05),
                       (cx - 0.3, lo.y + 0.1, lo.z + 0.28), (cx + 0.3, lo.y + 0.1, lo.z + 0.28),
                       (cx - 0.38, lo.y + 0.5, lo.z + 0.3), (cx + 0.38, lo.y + 0.5, lo.z + 0.3)], "head", "sgg2_frame")


def build_legs():
    # Groin plate.
    lo, hi = extent("Pelvis", "pelvis")
    sgn = axis_sign("pelvis", (0, -1, 0), 2)
    front = hi.z if sgn > 0 else lo.z
    cx = (lo.x + hi.x) / 2
    hull("SGG2_Groin_Plate", local_box("pelvis", cx - 0.38, cx + 0.38, lo.y + 0.05, lo.y + (hi.y - lo.y) * 0.62,
                                       *sorted((front - sgn * 0.05, front + sgn * 0.14)), 0.35), "pelvis")
    hull("SGG2_Groin_Stripe", local_box("pelvis", cx - 0.06, cx + 0.06, lo.y + 0.2, lo.y + (hi.y - lo.y) * 0.55,
                                        *sorted((front + sgn * 0.12, front + sgn * 0.17))), "pelvis", "sgg2_panel", 0.01)
    for s in ("L", "R"):
        thigh, shin = "thigh_" + s, "shin_" + s
        side_plate("SGG2_Thigh_Plate_" + s, THIGH[s], thigh, s, (0.18, 0.7), 0.12, 0.2, axis=2)
        side_plate("SGG2_Thigh_Side_" + s, THIGH[s], thigh, s, (0.12, 0.6), 0.1, 0.25, stripe=False)
        side_plate("SGG2_Shin_Guard_" + s, SHIN[s], shin, s, (0.3, 0.85), 0.12, 0.18, axis=2)
        # Knee guard: a pointed plate in front of the knee.
        lo2, hi2 = extent(SHIN[s], shin)
        sg = axis_sign(shin, (0, -1, 0), 2)
        f = hi2.z if sg > 0 else lo2.z
        cxs = (lo2.x + hi2.x) / 2
        pts = local_box(shin, cxs - 0.36, cxs + 0.36, lo2.y - 0.25, lo2.y + 0.35, *sorted((f - sg * 0.1, f + sg * 0.18)),
                        0.3)
        tip = bone_matrix(shin) @ Vector((cxs, lo2.y - 0.05, f + sg * 0.34))
        hull("SGG2_Knee_Guard_" + s, pts + [tip], shin)
        # Tassets: plates over the hips on the skirt bones (they swing off the thighs).
        tl, th = extent(THIGH[s], thigh)
        hip = rig.data.bones[thigh].head_local
        k = 1 if s == "L" else -1
        x_in, x_out = hip.x - k * 0.55, hip.x + k * 0.75
        front_y = min(-1.62, (rig.matrix_world @ (bone_matrix(thigh) @ Vector((0, 0, th.z if axis_sign(thigh, (0, -1, 0), 2) > 0 else tl.z)))).y - 0.12)
        hull("SGG2_Tasset_Front_" + s, [(x_in, front_y + 0.05, 6.45), (x_out, front_y + 0.05, 6.45),
                                       (x_in, front_y + 0.2, 6.45), (x_out, front_y + 0.2, 6.45),
                                       (x_in + k * 0.1, front_y - 0.15, 5.0), (x_out, front_y - 0.15, 5.1),
                                       (x_in + k * 0.1, front_y, 5.0), (x_out, front_y, 5.1)],
             "skirt_front_" + s)
        hull("SGG2_Tasset_Stripe_" + s, [(x_out - k * 0.18, front_y + 0.0, 6.35), (x_out - k * 0.08, front_y + 0.0, 6.35),
                                        (x_out - k * 0.18, front_y - 0.05, 6.35), (x_out - k * 0.08, front_y - 0.05, 6.35),
                                        (x_out - k * 0.18, front_y - 0.19, 5.25), (x_out - k * 0.08, front_y - 0.19, 5.25),
                                        (x_out - k * 0.18, front_y - 0.24, 5.25), (x_out - k * 0.08, front_y - 0.24, 5.25)],
             "skirt_front_" + s, "sgg2_panel", 0.01)
        xs = (th.x if axis_sign(thigh, (k, 0, 0), 0) > 0 else -tl.x)
        x_side = hip.x + k * (abs(xs) + 0.18)
        hull("SGG2_Tasset_Side_" + s, [(x_side, -0.9, 6.5), (x_side + k * 0.16, -0.9, 6.5),
                                      (x_side, 0.7, 6.5), (x_side + k * 0.16, 0.7, 6.5),
                                      (x_side + k * 0.12, -0.7, 4.95), (x_side + k * 0.26, -0.7, 4.95),
                                      (x_side + k * 0.12, 0.45, 5.05), (x_side + k * 0.26, 0.45, 5.05)],
             "skirt_side_" + s)


# ---------------------------------------------------------------- main

def main():
    global rig
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    rig = bpy.data.objects[RIG]
    mech_rig_standard.ensure_accessory_bones(rig)
    ad = rig.animation_data
    saved = (ad.action, ad.use_nla) if ad else None
    if ad:
        ad.action = None
        ad.use_nla = False
    for p in rig.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for mesh_name, (bone, factor) in HEFT.items():
        thicken(mesh_name, bone, factor)
    build_head()
    build_core()
    build_arms()
    build_legs()
    if saved:
        ad.action, ad.use_nla = saved
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, compress=True)
    added = [o.name for o in bpy.data.objects if o.name.startswith("SGG2_")]
    print("SGGV2 saved", OUT_BLEND, len(added), "new pieces")
    import export_mech_parts
    sys.argv = [sys.argv[0], "--", OUT_BLEND, "sgg", OUT_PARTS, "parts"]
    export_mech_parts.main()


if __name__ == "__main__":
    main()
