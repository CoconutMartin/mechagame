"""Builds the Haliya HLY-101 model from the user pictures "D:/Pictures/Mechs/Haliya/Haliya 4k.png" (front three
quarter view), "Haliya Back.PNG" (the back) and "Haliya back 3-4.png" (the back forms),
and "Angular Graphite Mecha Side Profile.png" (the side: every depth along Y and the stance).

Run in Blender: exec(open(r"D:/EMCMII/GitHub/mechagame/tools/blender/haliya_ref_build.py").read())
Blender space: Z up, the mech faces -Y, its left side is +X. Meters, feet on Z = 0.
Every piece is its own mesh object, parented to an empty on its joint; the collections are the part slots
(Head, Core, Arm_L, Arm_R, Legs). The proportions come from the pictures, not from MechRig (user choice 2026-11-05).
All coordinates below are for the unscaled model; build() applies MODEL_SCALE at the end.
"""
import math

import bpy
import bmesh
from mathutils import Matrix, Vector

## sRGB colors sampled from the picture, and roughness.
COLORS = {
    "hly_armor": ((74, 74, 79), 0.62),
    "hly_tan": ((205, 190, 150), 0.68),
    "hly_joint": ((34, 34, 37), 0.5),
    "hly_eye": ((10, 10, 12), 0.38),
}
## Size of the whole mech against the coordinates below: Haliya is a light mech, a little smaller in frame.
MODEL_SCALE = 0.95
## Height (m) the whole arm sits above the coordinates below: the shoulder rollers reach almost to the top of the traps.
ARM_LIFT = 0.30
## Size of the whole head, about the bottom of the neck, so the neck stays seated in the chest.
HEAD_SCALE = 0.756
HEAD_SCALE_PIVOT = Vector((0.0, 0.0, 8.20))
## Height (m) the head sits above its seat: the neck grows by this much and shows between the chest and the jaw.
NECK_LENGTH = 0.238
## Width of the pauldrons seen from the front, against the coordinates in build_arm. They grow outward from their inner edge (x = 1.0).
PAULDRON_WIDTH = 1.20
## Height of the flat top of the pauldrons, against the coordinates in build_arm.
PAULDRON_TOP = 8.36
## Radius (m) of the shoulder ball, centered on the shoulder joint.
SHOULDER_BALL_RADIUS = 0.36
## Width (m) of the tan border around the dark plate on the side and rear skirts.
SKIRT_COVER_BORDER = 0.20
## Width (m) of the tan strap that joins the side and rear skirt plates.
SKIRT_STRAP_WIDTH = 0.30
## Chamfer width (m) of the armor edges.
BEVEL = 0.018

PARTS = ["Head", "Core", "Arm_L", "Arm_R", "Legs"]
ROOT_COLLECTION = "Haliya_HLY101"

## Joints of the left side, read from the picture.
SHOULDER = Vector((1.28, -0.05, 7.75))
ELBOW = Vector((1.62, 0.30, 6.30))
WRIST = Vector((2.22, 0.30, 4.90))
HIP = Vector((0.72, 0.0, 6.31))
KNEE = Vector((1.08, 0.14, 3.20))
ANKLE = Vector((1.35, 0.25, 0.84))
## Foot origin on the ground, under the instep; the heel post stands under the ankle.
FOOT_BASE = Vector((1.445, -0.29, 0.0))
FOOT_SPLAY = math.radians(10.0)
## Size of the forefoot (toe, midfoot front, instep front): it scales toward the back of the midfoot.
FOREFOOT_SCALE = 0.75
DISC_CENTER = Vector((0.0, -0.48, 9.08))
DISC_TILT = math.radians(19.0)


def srgb(v):
    v /= 255.0
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    rgb, rough = COLORS[name]
    col = (srgb(rgb[0]), srgb(rgb[1]), srgb(rgb[2]), 1.0)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    mat.diffuse_color = col
    return mat


class Build:
    """Holds the joint empties and adds pieces. side = 1 for left and for the center, -1 for right."""

    def __init__(self):
        self.joints = {}

    def joint(self, name, part, at, parent=None):
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = 0.08
        e.location = at
        bpy.data.collections[part].objects.link(e)
        if parent:
            e.parent = self.joints[parent]
            e.matrix_parent_inverse = self.joints[parent].matrix_world.inverted()
        e.matrix_world = Matrix.Translation(at)
        bpy.context.view_layer.update()
        self.joints[name] = e
        return e

    def finish(self, name, bm, part, joint, mat, side=1):
        if side < 0:
            bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts[:])
            bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.data.collections[part].objects.link(obj)
        mesh.materials.append(material(mat))
        for poly in mesh.polygons:
            poly.use_smooth = False
        parent = self.joints[joint]
        origin = parent.matrix_world.translation
        mesh.transform(Matrix.Translation(-origin))
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
        return obj

    def hull(self, name, part, joint, mat, points, side=1, bevel=BEVEL):
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
        return self.finish(name, bm, part, joint, mat, side)

    def rings(self, name, part, joint, mat, a, axis, profile, sides=20, side=1):
        """Turned shape along axis from a. profile = [(distance, radius), ...]; both ends are capped."""
        axis = Vector(axis).normalized()
        u = axis.orthogonal().normalized()
        v = axis.cross(u)
        bm = bmesh.new()
        loops = []
        for dist, radius in profile:
            loop = []
            for i in range(sides):
                t = 2.0 * math.pi * i / sides
                loop.append(bm.verts.new(a + axis * dist + (u * math.cos(t) + v * math.sin(t)) * radius))
            loops.append(loop)
        for l0, l1 in zip(loops, loops[1:]):
            for i in range(sides):
                j = (i + 1) % sides
                bm.faces.new((l0[i], l0[j], l1[j], l1[i]))
        bm.faces.new(loops[0])
        bm.faces.new(loops[-1])
        return self.finish(name, bm, part, joint, mat, side)


def limb_frame(a, b):
    """along (a to b), out (away from the body), back (+Y). Returns a function: t along, u out, v back -> point."""
    along = (b - a).normalized()
    back = (Vector((0, 1, 0)) - along * along.y).normalized()
    out = along.cross(back)
    length = (b - a).length

    def at(t, u, v):
        return a + along * (t * length) + out * u + back * v
    return at


def inset_outline(points, border):
    """Moves each edge of a convex 2D outline inward by border. Returns the new corners, each from its two edges."""
    corners = [Vector(p) for p in points]
    center = sum(corners, Vector((0.0, 0.0))) / len(corners)
    edges = []
    for i, a in enumerate(corners):
        along = (corners[(i + 1) % len(corners)] - a).normalized()
        inward = Vector((-along.y, along.x))
        if inward.dot(center - a) < 0:
            inward = -inward
        edges.append((a + inward * border, along))
    result = []
    for i, (p, d) in enumerate(edges):
        q, e = edges[i - 1]
        t = (q - p).cross(e) / d.cross(e)
        result.append(p + d * t)
    return result


def box_section(at, t, half_u, half_v, cu=0.0, cv=0.0, ch=0.0):
    """Eight points of a section at t, with chamfered corners when ch > 0."""
    pts = []
    for su in (-1, 1):
        for sv in (-1, 1):
            pts.append(at(t, cu + su * half_u, cv + sv * (half_v - ch)))
            pts.append(at(t, cu + su * (half_u - ch), cv + sv * half_v))
    return pts


# ---------------------------------------------------------------- head

def build_head(b):
    part = "Head"
    n = Vector((0.0, -math.cos(DISC_TILT), math.sin(DISC_TILT)))
    up = Vector((0.0, math.sin(DISC_TILT), math.cos(DISC_TILT)))
    right = Vector((1.0, 0.0, 0.0))

    def disc_point(angle, radius, front):
        return DISC_CENTER + (right * math.cos(angle) + up * math.sin(angle)) * radius + n * front

    # Face disc: a shallow cone of 24 flat sectors around the eye.
    sides = 24
    bm = bmesh.new()
    start = math.radians(7.5)
    ring_back = [bm.verts.new(disc_point(start + i * 2 * math.pi / sides, 0.69, -0.07)) for i in range(sides)]
    ring_rim = [bm.verts.new(disc_point(start + i * 2 * math.pi / sides, 0.74, -0.01)) for i in range(sides)]
    ring_inner = [bm.verts.new(disc_point(start + i * 2 * math.pi / sides, 0.31, 0.30)) for i in range(sides)]
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((ring_back[i], ring_back[j], ring_rim[j], ring_rim[i]))
        bm.faces.new((ring_rim[i], ring_rim[j], ring_inner[j], ring_inner[i]))
    bm.faces.new(ring_back)
    bm.faces.new(ring_inner)
    b.finish("Head_disc", bm, part, "head", "hly_tan")

    # Eye: a black half ball standing out of the cone.
    bm = bmesh.new()
    matrix = (Matrix.Translation(DISC_CENTER + n * 0.20) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4()
              @ Matrix.Scale(0.6, 4, (0, 0, 1)))
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=0.30, matrix=matrix)
    eye = b.finish("Head_eye", bm, part, "head", "hly_eye")
    for poly in eye.data.polygons:
        poly.use_smooth = True

    # Twelve dark slots on the disc rim.
    for i in range(12):
        angle = math.radians(15.0) + i * math.radians(30.0)
        out = right * math.cos(angle) + up * math.sin(angle)
        tangent = n.cross(out)
        inner = 0.62
        outer = 0.72
        face = lambda r: 0.31 * (0.74 - r) / 0.43 - 0.01
        half = 0.012
        pts = []
        for r in (inner, outer):
            c = DISC_CENTER + out * r + n * face(r)
            for s in (-1, 1):
                pts.append(c + tangent * (s * half) + n * 0.004)
                pts.append(c + tangent * (s * half) - n * 0.02)
        b.hull("Head_slot_%02d" % i, part, "head", "hly_joint", pts, bevel=0.0)

    # Cranium behind the disc.
    z0 = 9.20
    b.hull("Head_cranium", part, "head", "hly_armor", [
        (-0.40, -0.10, z0 + 0.50), (0.40, -0.10, z0 + 0.50), (-0.30, 0.15, z0 + 0.56), (0.30, 0.15, z0 + 0.56),
        (-0.58, -0.25, z0 + 0.10), (0.58, -0.25, z0 + 0.10), (-0.58, 0.20, z0 + 0.25), (0.58, 0.20, z0 + 0.25),
        (-0.42, 0.52, z0 + 0.05), (0.42, 0.52, z0 + 0.05), (-0.34, 0.50, z0 - 0.30), (0.34, 0.50, z0 - 0.30),
        (-0.52, -0.36, z0 - 0.42), (0.52, -0.36, z0 - 0.42), (-0.50, 0.22, z0 - 0.52), (0.50, 0.22, z0 - 0.52),
    ])
    # Mount from the back of the disc to the cranium.
    mount = [disc_point(i * math.pi / 4.0, 0.46, -0.05) for i in range(8)]
    mount += [Vector((sx, -0.20, sz)) for sx in (-0.42, 0.42) for sz in (z0 - 0.42, z0 + 0.36)]
    b.hull("Head_disc_mount", part, "head", "hly_joint", mount)
    # Center plate on the back of the cranium.
    b.hull("Head_back_plate", part, "head", "hly_armor", [
        (-0.24, 0.30, z0 + 0.46), (0.24, 0.30, z0 + 0.46), (-0.28, 0.58, z0 + 0.20), (0.28, 0.58, z0 + 0.20),
        (-0.28, 0.58, z0 - 0.18), (0.28, 0.58, z0 - 0.18), (-0.20, 0.30, z0 - 0.42), (0.20, 0.30, z0 - 0.42),
    ])
    # Jaw block and the neck under it.
    b.hull("Head_jaw", part, "head", "hly_joint", [
        (-0.44, -0.40, z0 - 0.38), (0.44, -0.40, z0 - 0.38), (-0.44, 0.30, z0 - 0.45), (0.44, 0.30, z0 - 0.45),
        (-0.36, -0.30, z0 - 0.72), (0.36, -0.30, z0 - 0.72), (-0.38, 0.30, z0 - 0.72), (0.38, 0.30, z0 - 0.72),
    ])
    b.hull("Head_neck", part, "head", "hly_joint", [
        (-0.32, -0.25, z0 - 0.70), (0.32, -0.25, z0 - 0.70), (-0.32, 0.28, z0 - 0.70), (0.32, 0.28, z0 - 0.70),
        (-0.30, -0.20, z0 - 1.02), (0.30, -0.20, z0 - 1.02), (-0.30, 0.25, z0 - 1.02), (0.30, 0.25, z0 - 1.02),
    ])
    b.hull("Head_neck_back", part, "head", "hly_joint", [
        (-0.40, 0.15, 9.04), (0.40, 0.15, 9.04), (-0.34, 0.48, 8.96), (0.34, 0.48, 8.96),
        (-0.42, 0.15, 8.42), (0.42, 0.15, 8.42), (-0.36, 0.48, 8.50), (0.36, 0.48, 8.50),
    ])
    for side, tag in ((1, "L"), (-1, "R")):
        # Pivot on the side of the head.
        b.rings("Head_pivot_" + tag, part, "head", "hly_joint", Vector((0.40, 0.25, z0 - 0.28)), (1, 0, 0),
                [(0.0, 0.16), (0.08, 0.16), (0.11, 0.13), (0.12, 0.09)], sides=14, side=side)
        # Horn: a thick root and a long point, up, out and back.
        tip = Vector((1.40, 1.53, 9.95))
        root_mid = Vector((0.92, 0.30, 9.48))
        b.hull("Head_horn_root_" + tag, part, "head", "hly_armor", [
            (0.50, -0.20, 8.86), (0.50, 0.40, 8.86), (0.52, -0.10, 9.62), (0.52, 0.30, 9.60),
            root_mid + Vector((-0.02, -0.26, -0.40)), root_mid + Vector((0.08, 0.20, -0.42)),
            root_mid + Vector((-0.05, -0.20, 0.20)), root_mid + Vector((0.02, 0.26, 0.20)),
        ], side=side)
        b.hull("Head_horn_tip_" + tag, part, "head", "hly_armor", [
            root_mid + Vector((-0.02, -0.26, -0.40)), root_mid + Vector((0.08, 0.20, -0.42)),
            root_mid + Vector((-0.05, -0.20, 0.20)), root_mid + Vector((0.02, 0.26, 0.20)),
            tip,
        ], side=side, bevel=0.012)


# ---------------------------------------------------------------- core

def build_core(b):
    part = "Core"
    tan = "hly_tan"
    dark = "hly_armor"
    joint = "hly_joint"
    # Center chest plate: three front facets.
    b.hull("Core_chest_plate", part, "torso", tan, [
        (-0.30, -0.92, 7.90), (0.30, -0.92, 7.90), (-0.37, -1.18, 7.55), (0.37, -1.18, 7.55),
        (-0.37, -1.18, 7.25), (0.37, -1.18, 7.25), (-0.29, -0.90, 6.94), (0.29, -0.90, 6.94),
        (-0.30, -0.50, 7.90), (0.30, -0.50, 7.90), (-0.29, -0.50, 6.94), (0.29, -0.50, 6.94),
    ])
    b.hull("Core_chest_lower", part, "torso", tan, [
        (-0.29, -0.78, 6.93), (0.29, -0.78, 6.93), (-0.21, -0.66, 6.56), (0.21, -0.66, 6.56),
        (-0.29, -0.40, 6.93), (0.29, -0.40, 6.93), (-0.21, -0.40, 6.56), (0.21, -0.40, 6.56),
    ])
    # Back: a tan strip up the neck and the large tan plate on the spine, with a center facet.
    b.hull("Core_spine_neck", part, "torso", tan, [
        (-0.21, 0.40, 8.78), (0.21, 0.40, 8.78), (-0.21, 0.62, 8.72), (0.21, 0.62, 8.72),
        (-0.21, 1.00, 8.14), (0.21, 1.00, 8.14), (-0.21, 0.40, 8.14), (0.21, 0.40, 8.14),
    ])
    b.hull("Core_spine_plate", part, "torso", tan, [
        (-0.30, 0.48, 8.16), (0.30, 0.48, 8.16), (-0.30, 1.00, 8.16), (0.30, 1.00, 8.16),
        (-0.20, 1.10, 8.14), (0.20, 1.10, 8.14),
        (-0.32, 1.10, 7.60), (0.32, 1.10, 7.60), (-0.20, 1.22, 7.56), (0.20, 1.22, 7.56),
        (-0.32, 1.10, 7.05), (0.32, 1.10, 7.05), (-0.18, 1.22, 7.05), (0.18, 1.22, 7.05),
        (-0.23, 0.95, 6.71), (0.23, 0.95, 6.71), (-0.14, 1.05, 6.71), (0.14, 1.05, 6.71),
        (-0.32, 0.48, 7.60), (0.32, 0.48, 7.60), (-0.23, 0.40, 6.71), (0.23, 0.40, 6.71),
    ])
    b.hull("Core_waist_back", part, "torso", dark, [
        (-0.22, 0.28, 6.74), (0.22, 0.28, 6.74), (-0.22, 0.82, 6.74), (0.22, 0.82, 6.74),
        (-0.22, 0.28, 6.22), (0.22, 0.28, 6.22), (-0.22, 0.78, 6.22), (0.22, 0.78, 6.22),
    ])
    b.hull("Core_neck_seat", part, "torso", joint, [
        (-0.40, -0.40, 8.20), (0.40, -0.40, 8.20), (-0.40, 0.42, 8.20), (0.40, 0.42, 8.20),
        (-0.34, -0.30, 8.45), (0.34, -0.30, 8.45), (-0.34, 0.34, 8.45), (0.34, 0.34, 8.45),
    ])
    for side, tag in ((1, "L"), (-1, "R")):
        b.hull("Core_shell_" + tag, part, "torso", dark, [
            (0.28, -0.35, 8.24), (0.28, 0.40, 8.24), (0.90, -0.25, 8.24), (0.90, 0.35, 8.24),
            (0.98, -0.88, 7.60), (0.98, 0.45, 7.72), (1.10, 0.05, 7.42), (0.72, -0.72, 7.18), (0.72, 0.42, 7.22),
            (0.25, -1.02, 7.60), (0.25, -0.86, 7.10), (0.25, 0.55, 7.10), (0.25, 0.58, 8.00),
        ], side=side)
        # Back: an octagon block on each side of the spine, a step above it, an arc from the neck to the shoulder.
        b.hull("Core_back_block_" + tag, part, "torso", dark, [
            (0.34, 0.92, 8.22), (0.90, 0.92, 8.22), (0.34, 1.04, 8.06), (0.92, 1.04, 8.06),
            (1.00, 1.04, 7.90), (1.00, 1.04, 7.30), (0.34, 1.08, 7.62), (0.34, 1.06, 7.05),
            (0.92, 1.00, 7.10), (0.82, 0.90, 6.86), (0.40, 0.92, 6.84),
            (0.34, 0.30, 8.22), (1.00, 0.30, 7.90), (0.96, 0.30, 7.20), (0.40, 0.30, 6.84),
        ], side=side)
        b.hull("Core_back_step_" + tag, part, "torso", dark, [
            (0.44, 0.40, 8.36), (0.80, 0.40, 8.36), (0.44, 0.86, 8.34), (0.80, 0.86, 8.34),
            (0.44, 0.40, 8.18), (0.80, 0.40, 8.18), (0.44, 0.94, 8.18), (0.80, 0.94, 8.18),
        ], side=side)
        b.hull("Core_neck_arc_" + tag, part, "torso", dark, [
            (0.42, 0.20, 8.68), (0.62, 0.20, 8.68), (0.42, 0.62, 8.66), (0.62, 0.62, 8.66),
            (0.85, 0.20, 8.30), (0.85, 0.80, 8.28), (0.85, 0.20, 8.12), (0.85, 0.80, 8.12),
            (0.42, 0.20, 8.30), (0.42, 0.80, 8.30),
        ], side=side)
        b.hull("Core_collar_front_" + tag, part, "torso", tan, [
            (0.28, -0.98, 7.90), (0.38, -1.12, 7.68), (0.78, -0.48, 8.30), (0.78, -0.30, 8.42),
            (0.42, -0.52, 8.50), (0.28, -0.70, 7.92), (0.30, -0.62, 7.72), (0.74, -0.16, 8.20),
        ], side=side)
        b.hull("Core_collar_top_" + tag, part, "torso", tan, [
            (0.42, -0.50, 8.50), (0.79, -0.30, 8.42), (0.79, 0.08, 8.36), (0.45, 0.18, 8.47),
            (0.79, -0.30, 8.18), (0.79, 0.08, 8.14), (0.42, -0.50, 8.28), (0.42, 0.18, 8.24),
        ], side=side)
        b.hull("Core_rib_" + tag, part, "torso", tan, [
            (1.18, -0.42, 7.16), (1.18, 0.10, 7.12), (1.14, -0.42, 6.94), (1.14, 0.10, 6.90), (0.62, -0.76, 6.98), (0.68, -0.62, 6.84),
            (0.74, 0.10, 6.84), (0.84, -0.62, 7.12), (0.58, -0.40, 6.90), (0.58, 0.05, 6.88),
        ], side=side)
        # Shoulder socket on the side of the chest.
        b.rings("Core_socket_" + tag, part, "torso", joint, Vector((0.82, SHOULDER.y, SHOULDER.z + ARM_LIFT)), (1, 0, 0),
                [(0.0, 0.30), (0.08, 0.40), (0.20, 0.42), (0.24, 0.34)], sides=20, side=side)
        # Waist ribs: two rows of two blocks.
        for row, (z1, z0, w) in enumerate(((7.10, 6.90, 0.80), (6.86, 6.66, 0.66))):
            b.hull("Core_rib_front_%s%d" % (tag, row), part, "torso", joint, [
                (0.02, -0.40, z1), (w, -0.32, z1 - 0.04), (0.02, -0.46, z0), (w - 0.06, -0.34, z0),
                (0.02, 0.0, z1), (w, 0.0, z1 - 0.04), (0.02, 0.0, z0), (w - 0.06, 0.0, z0),
            ], side=side, bevel=0.012)
            b.hull("Core_rib_back_%s%d" % (tag, row), part, "torso", joint, [
                (0.02, 0.48, z1), (w, 0.40, z1 - 0.04), (0.02, 0.50, z0), (w - 0.06, 0.40, z0),
                (0.02, 0.02, z1), (w, 0.02, z1 - 0.04), (0.02, 0.02, z0), (w - 0.06, 0.02, z0),
            ], side=side, bevel=0.012)

    b.rings("Core_waist", part, "pelvis", joint, Vector((0, 0.02, 6.62)), (0, 0, 1),
            [(0.0, 0.42), (0.40, 0.40)], sides=12)
    # Pelvis.
    b.hull("Core_pelvis_plate", part, "pelvis", tan, [
        (-0.21, -0.66, 6.53), (0.21, -0.66, 6.53), (-0.17, -0.78, 6.22), (0.17, -0.78, 6.22),
        (-0.21, -0.30, 6.53), (0.21, -0.30, 6.53), (-0.17, -0.30, 6.22), (0.17, -0.30, 6.22),
    ])
    b.hull("Core_pelvis_block", part, "pelvis", dark, [
        (-0.32, -0.40, 6.62), (0.32, -0.40, 6.62), (-0.32, 0.42, 6.62), (0.32, 0.42, 6.62),
        (-0.34, -0.40, 6.0), (0.34, -0.40, 6.0), (-0.34, 0.42, 6.0), (0.34, 0.42, 6.0),
    ])
    # Crotch block: a faceted shield.
    b.hull("Core_crotch", part, "pelvis", dark, [
        (-0.24, -0.84, 6.24), (0.24, -0.84, 6.24), (-0.32, -0.96, 5.86), (0.32, -0.96, 5.86),
        (-0.32, -0.90, 5.32), (0.32, -0.90, 5.32), (-0.14, -0.58, 4.90), (0.14, -0.58, 4.90),
        (-0.10, -1.05, 5.86), (0.10, -1.05, 5.86), (-0.10, -1.00, 5.32), (0.10, -1.00, 5.32),
        (-0.30, 0.0, 6.20), (0.30, 0.0, 6.20), (-0.30, 0.0, 5.40), (0.30, 0.0, 5.40),
        (-0.14, 0.0, 4.90), (0.14, 0.0, 4.90),
    ])
    b.hull("Core_pelvis_back", part, "pelvis", tan, [
        (-0.22, 0.40, 6.25), (0.22, 0.40, 6.25), (-0.22, 0.84, 6.22), (0.22, 0.84, 6.22),
        (-0.31, 0.92, 5.85), (0.31, 0.92, 5.85), (-0.31, 0.96, 5.12), (0.31, 0.96, 5.12),
        (-0.20, 0.98, 4.82), (0.20, 0.98, 4.82), (-0.31, 0.40, 5.85), (0.31, 0.40, 5.85),
        (-0.31, 0.62, 5.12), (0.31, 0.62, 5.12), (-0.20, 0.66, 4.82), (0.20, 0.66, 4.82),
        (-0.16, 0.96, 5.80), (0.16, 0.96, 5.80), (-0.16, 1.02, 5.16), (0.16, 1.02, 5.16),
    ])
    for side, tag in ((1, "L"), (-1, "R")):
        b.hull("Core_hip_back_" + tag, part, "pelvis", dark, [
            (0.30, 0.35, 5.95), (0.30, 0.80, 5.95), (0.30, 0.35, 5.60), (0.30, 0.82, 5.60),
            (0.74, 0.35, 6.25), (0.74, 0.70, 6.25), (0.74, 0.35, 5.90), (0.74, 0.72, 5.90),
        ], side=side)
        b.hull("Core_hip_shell_" + tag, part, "pelvis", dark, [
            (0.30, -0.36, 6.56), (0.30, 0.36, 6.56), (0.60, -0.30, 6.50), (0.60, 0.30, 6.50),
            (0.30, -0.42, 6.15), (0.30, 0.42, 6.15), (0.60, -0.30, 6.05), (0.60, 0.30, 6.05),
        ], side=side)
        b.hull("Core_hip_low_" + tag, part, "pelvis", dark, [
            (0.30, -0.34, 6.12), (0.85, -0.28, 6.12), (0.30, 0.34, 6.12), (0.85, 0.28, 6.12),
            (0.30, -0.28, 5.72), (0.80, -0.24, 5.72), (0.30, 0.28, 5.72), (0.80, 0.24, 5.72),
        ], side=side)
        # Belt: the band from the crotch up to the hip.
        b.hull("Core_belt_" + tag, part, "pelvis", dark, [
            (0.18, -0.68, 6.40), (0.20, -0.72, 6.06), (0.92, -0.56, 6.56), (0.94, -0.56, 6.18),
            (0.18, -0.40, 6.40), (0.20, -0.40, 6.06), (0.92, -0.25, 6.56), (0.94, -0.25, 6.18),
        ], side=side)


# ---------------------------------------------------------------- arms

def build_arm(b, side, tag):
    part = "Arm_" + tag
    tan = "hly_tan"
    dark = "hly_armor"
    joint = "hly_joint"
    upper = "upper_arm_" + tag
    fore = "forearm_" + tag
    hand = "hand_" + tag

    # Shoulder roller on the chest side.
    # Shoulder: a ball centered on the joint, so the arm turns in any direction with no gap.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=SHOULDER_BALL_RADIUS,
                              matrix=Matrix.Translation(SHOULDER))
    ball = b.finish("Arm_shoulder_" + tag, bm, part, upper, joint, side)
    for poly in ball.data.polygons:
        poly.use_smooth = True

    at = limb_frame(SHOULDER, ELBOW)
    # The upper arm starts inside the ball, on the line from the shoulder to the elbow.
    b.hull("Arm_upper_core_" + tag, part, upper, joint,
           box_section(at, 0.08, 0.20, 0.20, ch=0.05) + box_section(at, 0.92, 0.20, 0.22, ch=0.05), side=side)
    b.hull("Arm_upper_tan_" + tag, part, upper, tan,
           box_section(at, 0.32, 0.20, 0.14, cv=-0.11, ch=0.05)
           + box_section(at, 0.62, 0.25, 0.17, cv=-0.11, ch=0.06)
           + box_section(at, 0.90, 0.23, 0.15, cv=-0.11, ch=0.06), side=side)
    b.hull("Arm_upper_back_" + tag, part, upper, tan,
           box_section(at, 0.32, 0.20, 0.14, cv=0.11, ch=0.05)
           + box_section(at, 0.62, 0.25, 0.17, cv=0.11, ch=0.06)
           + box_section(at, 0.90, 0.23, 0.15, cv=0.11, ch=0.06), side=side)

    # Elbow: a black roller between two blocks.
    b.rings("Arm_elbow_" + tag, part, fore, joint, ELBOW - Vector((0.22, 0, 0)), (1, 0, 0),
            [(0.0, 0.18), (0.03, 0.24), (0.41, 0.24), (0.44, 0.18)], sides=18, side=side)

    at = limb_frame(ELBOW, WRIST)
    b.hull("Arm_fore_core_" + tag, part, fore, joint,
           box_section(at, 0.08, 0.24, 0.26) + box_section(at, 1.0, 0.18, 0.18), side=side)
    # Forearm: tan shell with a seam two thirds down.
    b.hull("Arm_fore_tan_top_" + tag, part, fore, tan,
           box_section(at, 0.17, 0.27, 0.25, cv=-0.04, ch=0.08)
           + box_section(at, 0.32, 0.32, 0.29, cv=-0.04, ch=0.09)
           + box_section(at, 0.64, 0.31, 0.28, cv=-0.04, ch=0.09), side=side)
    b.hull("Arm_fore_tan_low_" + tag, part, fore, tan,
           box_section(at, 0.655, 0.31, 0.28, cv=-0.04, ch=0.09)
           + box_section(at, 0.95, 0.23, 0.22, cv=-0.04, ch=0.09), side=side)
    b.hull("Arm_fore_back_" + tag, part, fore, tan,
           box_section(at, 0.20, 0.24, 0.10, cv=0.20, ch=0.04)
           + box_section(at, 0.62, 0.25, 0.10, cv=0.20, ch=0.04), side=side)
    b.hull("Arm_wrist_" + tag, part, fore, joint,
           box_section(at, 0.92, 0.17, 0.17, ch=0.05) + box_section(at, 1.06, 0.14, 0.14, ch=0.04), side=side)

    # Sleeve: a pauldron. The cap covers the shoulder ball on the top, front, back and outer side; the arm leaves
    # from under it.
    # The top is one flat face at PAULDRON_TOP.
    a0 = Vector((1.00, 0.30, PAULDRON_TOP))
    a1 = Vector((1.66, 0.38, PAULDRON_TOP))
    a2 = Vector((1.84, 0.82, PAULDRON_TOP))
    a3 = Vector((1.04, 0.74, PAULDRON_TOP))
    a4 = Vector((1.00, -0.40, PAULDRON_TOP))
    a5 = Vector((1.66, -0.44, PAULDRON_TOP))
    front0 = Vector((1.00, -0.54, 7.66))
    front1 = Vector((1.82, -0.56, 7.66))
    low0 = Vector((1.04, -0.50, 7.34))
    low1 = Vector((1.76, -0.50, 7.28))
    low2 = Vector((1.04, 0.44, 7.34))
    ridge = Vector((2.00, 0.10, 8.02))
    m0 = Vector((2.12, -0.16, 7.30))
    m1 = Vector((2.46, 0.98, 7.30))
    m2 = Vector((1.70, 0.92, 7.22))
    m3 = Vector((1.70, 0.10, 7.10))
    pauldron = [a0, a1, a2, a3, a4, a5, front0, front1, low0, low1, low2, ridge, m0, m1, m2, m3]
    b.hull("Arm_sleeve_top_" + tag, part, upper, dark,
           [Vector((1.0 + (p.x - 1.0) * PAULDRON_WIDTH, p.y, p.z)) for p in pauldron], side=side)

    # Forearm guard: a plate on the outer face of the forearm, on its axis, wide at the elbow and narrow at the wrist.
    at = limb_frame(ELBOW, WRIST)
    guard = []
    for t, half_width, inner, outer in ((0.20, 0.24, 0.20, 0.34), (0.30, 0.31, 0.22, 0.42),
                                        (0.64, 0.27, 0.24, 0.42), (0.92, 0.15, 0.20, 0.34)):
        for s in (-1, 1):
            guard.append(at(t, inner, -0.02 + s * half_width))
            guard.append(at(t, outer, -0.02 + s * (half_width - 0.06)))
    b.hull("Arm_guard_" + tag, part, fore, dark, guard, side=side)

    # Hand: a closed fist, the back of the hand faces out, the fingers curl to the inside.
    c = WRIST + (WRIST - ELBOW).normalized() * 0.50
    down = (WRIST - ELBOW).normalized()
    at = limb_frame(WRIST, c)
    b.hull("Arm_palm_" + tag, part, hand, joint,
           box_section(at, 0.20, 0.19, 0.25, ch=0.05) + box_section(at, 1.35, 0.23, 0.31, ch=0.06), side=side)
    # Tan guard on the back of the hand.
    b.hull("Arm_hand_guard_" + tag, part, hand, tan,
           box_section(at, 0.05, 0.08, 0.22, cu=0.24, cv=-0.08, ch=0.04)
           + box_section(at, 1.05, 0.09, 0.27, cu=0.27, cv=-0.08, ch=0.04), side=side)
    # Fingers: three pieces, curled in.
    inward = -at(0, 1, 0) + at(0, 0, 0)
    for f, v in enumerate((-0.24, -0.08, 0.08, 0.24)):
        base = c + Vector((0, v, 0)) + inward * 0.02
        p1 = base + down * 0.24 + inward * 0.05
        p2 = p1 + down * 0.05 + inward * 0.20
        p3 = p2 - down * 0.20 + inward * 0.02
        for s, (a, e) in enumerate(((base, p1), (p1, p2), (p2, p3))):
            r = 0.075
            pts = []
            for du in (-r, r):
                for dv in (-r, r):
                    for q in (a, e):
                        pts.append(q + inward * du + Vector((0, dv, 0)))
                        pts.append(q + down * du + Vector((0, dv, 0)))
            b.hull("Arm_finger_%s_%d_%d" % (tag, f, s), part, hand, joint, pts, side=side, bevel=0.012)
    # Thumb on the front of the hand.
    t0 = WRIST + down * 0.14 + Vector((0, -0.30, 0))
    t1 = t0 + down * 0.20 + Vector((0, -0.08, 0)) + inward * 0.06
    t2 = t1 + down * 0.12 + inward * 0.15 + Vector((0, 0.04, 0))
    for s, (a, e) in enumerate(((t0, t1), (t1, t2))):
        pts = []
        for d in (Vector((0.07, 0, 0)), Vector((-0.07, 0, 0)), Vector((0, 0.07, 0)), Vector((0, -0.07, 0)),
                  Vector((0, 0, 0.07)), Vector((0, 0, -0.07))):
            pts.append(a + d)
            pts.append(e + d)
        b.hull("Arm_thumb_%s_%d" % (tag, s), part, hand, joint, pts, side=side, bevel=0.012)


# ---------------------------------------------------------------- legs

def skirt_plates(b, name, part, tag, side, outline, lean, place):
    """A flat tan plate and a dark plate on top of it, with each edge parallel to the tan edge and an even tan border.
    The border is measured along the leaning plate, so the outline is stretched to the plate's own height for the inset."""
    stretch = math.sqrt(1.0 + lean * lean)
    plate = []
    for w, z in outline:
        plate.append(place(w, z, 0.0))
        plate.append(place(w, z, 0.10))
    cover = []
    for w, s in inset_outline([(w, z * stretch) for w, z in outline], SKIRT_COVER_BORDER):
        cover.append(place(w, s / stretch, 0.08))
        cover.append(place(w, s / stretch, 0.18))
    b.hull(name + "_tan_" + tag, part, "pelvis", "hly_tan", plate, side=side)
    b.hull(name + "_cover_" + tag, part, "pelvis", "hly_armor", cover, side=side)


def build_leg(b, side, tag):
    part = "Legs"
    tan = "hly_tan"
    dark = "hly_armor"
    joint = "hly_joint"
    thigh = "thigh_" + tag
    shin = "shin_" + tag
    foot = "foot_" + tag

    # Hip roller.
    b.rings("Legs_hip_" + tag, part, thigh, joint, Vector((0.58, 0.0, 6.31)), (1, 0, 0),
            [(0.0, 0.26), (0.05, 0.29), (0.20, 0.29), (0.25, 0.24), (0.26, 0.14)], sides=20, side=side)

    # Thigh block: the large dark panel, with a seam two thirds down.
    b.hull("Legs_thigh_top_" + tag, part, thigh, dark, [
        (0.50, -0.56, 5.76), (0.80, -0.56, 5.74), (0.45, -0.78, 5.42), (0.98, -0.78, 5.40),
        (0.47, -0.78, 4.42), (1.08, -0.78, 4.34), (1.25, -0.45, 5.34), (1.36, -0.38, 4.34),
        (0.52, 0.56, 5.66), (0.97, 0.56, 5.64), (0.52, 0.72, 5.36), (1.20, 0.72, 5.36),
        (0.52, 0.76, 3.97), (1.40, 0.76, 3.95),
    ], side=side)
    b.hull("Legs_thigh_low_" + tag, part, thigh, dark, [
        (0.47, -0.78, 4.40), (1.08, -0.78, 4.32), (1.36, -0.38, 4.32), (0.60, -0.62, 3.50), (1.05, -0.62, 3.44),
        (1.34, -0.25, 3.46), (0.52, 0.76, 3.95), (1.40, 0.76, 3.93), (0.70, 0.50, 3.55), (1.28, 0.50, 3.55),
    ], side=side)
    # Inner tan face of the thigh and the column under the block.
    b.hull("Legs_thigh_inner_" + tag, part, thigh, tan, [
        (0.40, -0.40, 5.45), (0.60, -0.42, 5.45), (0.40, 0.25, 5.45), (0.60, 0.25, 5.45),
        (0.50, -0.40, 3.52), (0.76, -0.42, 3.50), (0.50, 0.20, 3.52), (0.76, 0.20, 3.50),
    ], side=side)
    b.hull("Legs_thigh_frame_" + tag, part, thigh, dark,
           box_section(limb_frame(HIP, KNEE), 0.75, 0.26, 0.24, cv=-0.14, ch=0.08)
           + box_section(limb_frame(HIP, KNEE), 1.0, 0.23, 0.20, cv=-0.16, ch=0.08), side=side)

    # Knee: a roller with round caps.
    b.rings("Legs_knee_" + tag, part, shin, joint, KNEE - Vector((0.25, 0, 0)), (1, 0, 0),
            [(0.0, 0.18), (0.03, 0.27), (0.47, 0.27), (0.50, 0.18)], sides=20, side=side)

    at = limb_frame(KNEE, ANKLE)
    for sign in (1, -1):
        b.rings("Legs_knee_cap_%s%d" % (tag, 0 if sign > 0 else 1), part, shin, dark, KNEE + Vector((sign * 0.25, 0, 0)),
                (sign, 0, 0), [(0.0, 0.27), (0.03, 0.27), (0.05, 0.22)], sides=20, side=side)
    b.hull("Legs_knee_block_" + tag, part, shin, dark,
           box_section(at, -0.10, 0.17, 0.26, cv=-0.16, ch=0.08) + box_section(at, 0.10, 0.22, 0.30, cv=-0.16, ch=0.08),
           side=side)
    # Shin column.
    b.hull("Legs_shin_" + tag, part, shin, dark,
           box_section(at, 0.12, 0.20, 0.16, cv=-0.14, ch=0.06) + box_section(at, 0.50, 0.16, 0.22, ch=0.05)
           + box_section(at, 1.0, 0.14, 0.20, ch=0.05), side=side)
    b.hull("Legs_ankle_cap_" + tag, part, shin, dark,
           box_section(at, 0.82, 0.24, 0.26, cv=-0.04, ch=0.08) + box_section(at, 0.95, 0.25, 0.46, cv=-0.14, ch=0.10)
           + box_section(at, 1.04, 0.22, 0.30, cv=-0.08, ch=0.10), side=side)
    # Knee guard: a tan plate in front, a tan plate on each side, the dark corners of the shin between them.
    guard_top = KNEE + Vector((0, 0, 0.10))
    guard = limb_frame(guard_top, guard_top + (ANKLE - guard_top).normalized() * 2.12)
    b.hull("Legs_guard_core_" + tag, part, shin, dark,
           box_section(guard, 0.05, 0.22, 0.16, cv=-0.14, ch=0.06) + box_section(guard, 0.55, 0.38, 0.44, cv=-0.04, ch=0.08),
           side=side)
    b.hull("Legs_guard_front_" + tag, part, shin, tan, [
        guard(0.22, -0.30, -0.60), guard(0.22, 0.30, -0.60), guard(0.30, -0.32, -0.66), guard(0.30, 0.32, -0.66),
        guard(0.48, -0.30, -0.60), guard(0.48, 0.30, -0.60), guard(0.58, 0.0, -0.50),
        guard(0.22, -0.30, -0.20), guard(0.22, 0.30, -0.20), guard(0.50, -0.30, -0.20), guard(0.50, 0.30, -0.20),
    ], side=side)
    b.hull("Legs_calf_" + tag, part, shin, tan, [
        guard(0.24, -0.28, 0.30), guard(0.24, 0.28, 0.30), guard(0.24, -0.25, 0.52), guard(0.24, 0.25, 0.52),
        guard(0.32, -0.33, 0.30), guard(0.32, 0.33, 0.30), guard(0.32, -0.31, 0.66), guard(0.32, 0.31, 0.66),
        guard(0.56, -0.24, 0.30), guard(0.56, 0.24, 0.30), guard(0.56, -0.22, 0.50), guard(0.56, 0.22, 0.50),
    ], side=side)
    b.hull("Legs_shin_strip_" + tag, part, shin, joint,
           box_section(at, 0.45, 0.09, 0.05, cv=0.21) + box_section(at, 0.95, 0.08, 0.05, cv=0.19), side=side)
    for s, sign in ((0, 1), (1, -1)):
        b.hull("Legs_guard_side_%s%d" % (tag, s), part, shin, tan, [
            guard(0.24, sign * 0.42, 0.04), guard(0.07, sign * 0.42, 0.39), guard(0.26, sign * 0.42, 0.68),
            guard(0.50, sign * 0.42, 0.55), guard(0.56, sign * 0.42, 0.33), guard(0.55, sign * 0.42, 0.07),
            guard(0.24, sign * 0.52, 0.04), guard(0.09, sign * 0.52, 0.39), guard(0.26, sign * 0.52, 0.66),
            guard(0.48, sign * 0.52, 0.53), guard(0.54, sign * 0.52, 0.33), guard(0.53, sign * 0.52, 0.07),
            guard(0.20, sign * 0.18, 0.10), guard(0.52, sign * 0.20, 0.10),
        ], side=side)
        b.hull("Legs_guard_dark_%s%d" % (tag, s), part, shin, dark, [
            guard(0.24, sign * 0.42, 0.02), guard(0.11, sign * 0.42, -0.43), guard(0.25, sign * 0.42, -0.70),
            guard(0.42, sign * 0.42, -0.62), guard(0.60, sign * 0.42, -0.06), guard(0.55, sign * 0.42, 0.05),
            guard(0.25, sign * 0.52, 0.02), guard(0.13, sign * 0.52, -0.41), guard(0.26, sign * 0.52, -0.66),
            guard(0.41, sign * 0.52, -0.60), guard(0.57, sign * 0.52, -0.06), guard(0.53, sign * 0.52, 0.05),
            guard(0.20, sign * 0.18, -0.10), guard(0.52, sign * 0.20, -0.10),
        ], side=side)

    # Ankle: an octagon roller and a wide round guard on the outside.
    b.rings("Legs_ankle_" + tag, part, foot, joint, ANKLE - Vector((0.34, 0, 0)), (1, 0, 0),
            [(0.0, 0.17), (0.68, 0.17)], sides=8, side=side)
    b.rings("Legs_ankle_guard_" + tag, part, foot, dark, ANKLE + Vector((0.26, 0, 0)), (1, 0, 0),
            [(0.0, 0.32), (0.13, 0.34), (0.18, 0.28)], sides=8, side=side)
    b.rings("Legs_ankle_guard_in_" + tag, part, foot, dark, ANKLE - Vector((0.26, 0, 0)), (-1, 0, 0),
            [(0.0, 0.32), (0.13, 0.34), (0.18, 0.28)], sides=8, side=side)

    # Foot, in its own frame: u = out, v = toward the toe, w = up.
    f_v = Vector((math.sin(FOOT_SPLAY), -math.cos(FOOT_SPLAY), 0.0))
    f_u = Vector((math.cos(FOOT_SPLAY), math.sin(FOOT_SPLAY), 0.0))
    base = FOOT_BASE

    def fp(u, v, w):
        return base + f_u * u + f_v * v + Vector((0, 0, w))

    def ff(u, v, w):
        return fp(u * FOREFOOT_SCALE, -0.05 + (v + 0.05) * FOREFOOT_SCALE, w * FOREFOOT_SCALE)

    b.hull("Legs_toe_" + tag, part, foot, dark, [
        ff(-0.05, 1.62, 0.02), ff(0.05, 1.62, 0.02), ff(-0.22, 1.40, 0.0), ff(0.22, 1.40, 0.0),
        ff(-0.46, 0.60, 0.0), ff(0.46, 0.60, 0.0), ff(-0.42, 0.62, 0.60), ff(0.42, 0.62, 0.60),
        ff(-0.08, 1.62, 0.12), ff(0.08, 1.62, 0.12),
    ], side=side)
    b.hull("Legs_midfoot_" + tag, part, foot, dark, [
        ff(-0.46, 0.60, 0.0), ff(0.46, 0.60, 0.0), ff(-0.42, 0.62, 0.60), ff(0.42, 0.62, 0.60),
        fp(-0.34, -0.05, 0.30), fp(0.34, -0.05, 0.30), fp(-0.30, -0.20, 0.72), fp(0.30, -0.20, 0.72),
    ], side=side)
    b.hull("Legs_instep_" + tag, part, foot, tan, [
        ff(-0.34, 0.72, 0.56), ff(0.34, 0.72, 0.56), fp(-0.24, 0.10, 0.94), fp(0.24, 0.10, 0.94),
        ff(-0.40, 0.56, 0.46), ff(0.40, 0.56, 0.46), fp(-0.26, -0.02, 0.76), fp(0.26, -0.02, 0.76),
    ], side=side)
    # Heel: a thin post under the ankle.
    b.hull("Legs_heel_" + tag, part, foot, dark, [
        fp(-0.26, -0.52, 0.56), fp(0.26, -0.52, 0.56), fp(-0.27, -0.84, 0.54), fp(0.27, -0.84, 0.54),
        fp(-0.30, -0.72, 0.0), fp(0.30, -0.72, 0.0), fp(-0.36, -1.00, 0.0), fp(0.36, -1.00, 0.0),
    ], side=side)

    b.hull("Legs_heel_tan_" + tag, part, foot, tan, [
        fp(-0.23, -0.72, 0.50), fp(0.23, -0.72, 0.50), fp(-0.23, -0.88, 0.50), fp(0.23, -0.88, 0.50),
        fp(-0.23, -0.72, 0.84), fp(0.23, -0.72, 0.84), fp(-0.20, -0.86, 0.84), fp(0.20, -0.86, 0.84),
    ], side=side)

    # Side skirt: a flat plate pair outside the thigh and as wide as it.
    outline = [(-0.36, 6.50), (0.20, 6.50), (0.64, 5.00), (0.64, 4.20), (0.45, 3.36), (-0.70, 4.20), (-0.94, 5.10)]
    side_lean = 0.27

    def side_place(w, z, height):
        return (1.00 + side_lean * (6.50 - z) + height, w, z)
    skirt_plates(b, "Skirt_side", part, tag, side, outline, side_lean, side_place)
    # Rear skirt: the same shape behind the thigh, as wide as the thigh seen from the back.
    rear_lean = 0.22
    rear_outline = [(0.45 + (y + 0.94) * 1.0 / 1.58, 3.36 + (z - 3.36) * 0.90) for y, z in outline]

    def rear_place(w, z, height):
        return (w, 0.84 + rear_lean * (6.19 - z) + height, z)
    skirt_plates(b, "Skirt_rear", part, tag, side, rear_outline, rear_lean, rear_place)
    # Strap: a tan band as thick as the plates, from the top back edge of the side plate to the top outer edge of the
    # rear plate. Its ends run into the plates, with the faces in the plates' faces, so no seam shows.
    strap = []
    for place, top, low in ((side_place, outline[1], outline[2]), (rear_place, rear_outline[1], rear_outline[2])):
        down = (Vector(low) - Vector(top)).normalized()
        for t in (0.0, SKIRT_STRAP_WIDTH):
            w, z = Vector(top) + down * t
            strap.append(place(w - 0.05, z, 0.0))
            strap.append(place(w - 0.05, z, 0.10))
    b.hull("Skirt_side_strap_" + tag, part, "pelvis", tan, strap, side=side)


def build_back_spike(b):
    part = "Legs"
    b.hull("Skirt_back_top", part, "pelvis", "hly_armor", [
        (-0.34, 0.34, 5.90), (0.34, 0.34, 5.90), (-0.45, 0.40, 5.20), (0.45, 0.40, 5.20),
        (-0.34, 0.56, 5.90), (0.34, 0.56, 5.90), (-0.45, 0.62, 5.20), (0.45, 0.62, 5.20),
    ], bevel=0.012)
    b.hull("Skirt_back_tip", part, "pelvis", "hly_armor", [
        (-0.40, 0.40, 5.18), (0.40, 0.40, 5.18), (-0.40, 0.62, 5.18), (0.40, 0.62, 5.18),
        (-0.28, 0.85, 3.50), (0.28, 0.85, 3.50), (-0.28, 1.05, 3.50), (0.28, 1.05, 3.50),
        (0.0, 1.48, 2.25),
    ], bevel=0.012)


def clean():
    root = bpy.data.collections.get(ROOT_COLLECTION)
    if root is not None:
        for coll in list(root.children):
            for obj in list(coll.objects):
                bpy.data.objects.remove(obj)
            bpy.data.collections.remove(coll)
        bpy.data.collections.remove(root)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def apply_scale(b, factor):
    """Scales the meshes and the joint places, so every object keeps scale 1."""
    matrix = Matrix.Scale(factor, 4)
    bpy.context.view_layer.update()
    places = {name: e.matrix_world.translation * factor for name, e in b.joints.items()}
    for coll in bpy.data.collections[ROOT_COLLECTION].children:
        for obj in coll.objects:
            if obj.type == "MESH":
                obj.data.transform(matrix)
    for name, e in b.joints.items():
        e.matrix_world = Matrix.Translation(places[name])
        bpy.context.view_layer.update()


def build():
    clean()
    root = bpy.data.collections.new(ROOT_COLLECTION)
    bpy.context.scene.collection.children.link(root)
    for name in PARTS:
        root.children.link(bpy.data.collections.new(name))

    b = Build()
    b.joint("pelvis", "Core", Vector((0, 0, 6.10)))
    b.joint("torso", "Core", Vector((0, 0, 6.75)), "pelvis")
    b.joint("head", "Head", Vector((0, 0, 8.42)), "torso")
    for tag, s in (("L", 1), ("R", -1)):
        m = Vector((s, 1, 1))
        mirrored = lambda v: v * m
        b.joint("upper_arm_" + tag, "Arm_" + tag, mirrored(SHOULDER), "torso")
        b.joint("forearm_" + tag, "Arm_" + tag, mirrored(ELBOW), "upper_arm_" + tag)
        b.joint("hand_" + tag, "Arm_" + tag, mirrored(WRIST), "forearm_" + tag)
        b.joint("thigh_" + tag, "Legs", mirrored(HIP), "pelvis")
        b.joint("shin_" + tag, "Legs", mirrored(KNEE), "thigh_" + tag)
        b.joint("foot_" + tag, "Legs", mirrored(ANKLE), "shin_" + tag)

    build_head(b)
    # The meshes hold their points relative to the head joint.
    bpy.context.view_layer.update()
    pivot = HEAD_SCALE_PIVOT - b.joints["head"].matrix_world.translation
    head_matrix = Matrix.Translation(pivot) @ Matrix.Scale(HEAD_SCALE, 4) @ Matrix.Translation(-pivot)
    for obj in bpy.data.collections["Head"].objects:
        if obj.type == "MESH":
            obj.data.transform(head_matrix)
            if obj.name == "Head_neck":
                # Only the top of the neck goes up, so the neck grows and stays seated.
                middle = sum(v.co.z for v in obj.data.vertices) / len(obj.data.vertices)
                for v in obj.data.vertices:
                    if v.co.z > middle:
                        v.co.z += NECK_LENGTH
            else:
                obj.data.transform(Matrix.Translation((0.0, 0.0, NECK_LENGTH)))
    build_core(b)
    for tag, s in (("L", 1), ("R", -1)):
        build_arm(b, s, tag)
        build_leg(b, s, tag)
    build_back_spike(b)
    # The arm pieces are children of the upper arm joint, so moving it moves the whole arm.
    for tag in ("L", "R"):
        joint = b.joints["upper_arm_" + tag]
        joint.matrix_world = Matrix.Translation(joint.matrix_world.translation + Vector((0, 0, ARM_LIFT)))
        bpy.context.view_layer.update()
    apply_scale(b, MODEL_SCALE)
    return b


build()
