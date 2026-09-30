"""Builds the Recon Accurate mech in models/recon_accurate/recon_accurate.blend and exports the parts.

Run (from the project root):
    blender -b models/recon_accurate/recon_accurate.blend --python tools/blender/recon_accurate_build.py
It removes the old model pieces (not the socket and pivot empties) and builds them again, so hand
edits in the part collections are lost: after hand edits, export with export_parts.py only.

A closer model of the user's reference picture than recon_build.py (not boxy): the armor pieces are
extruded outlines (chamfered rectangles, hexagons, octagons) that taper toward the front, with an
inset panel line, soft two-step bevels and brass bolts. Joints are stacked cylinders with rings.
  Head: sloped wedge helmet sunk between the shoulders, visor slit with two red eyes, crest, lens,
        small aerial.
  Chest: wide sloped chest with a center plate and vent slots, side blocks, narrow black waist.
  Shoulders: thick black shoulder joints, huge chamfered pauldrons that rise to head height, square
        vent on the outer face.
  Arms: black frame upper arms with an outer plate, stacked elbow joints, big six-sided forearm
        guards, black fists with fingers.
  Legs: black hip joints, tall front thigh plates, big six-sided knee pads, tapered shins with a
        front strip and black calf pistons, round ankles, wedge feet with black toe and heel pads.
  Back: backpack with grilles, two stepped antenna masts, thruster nozzles.
Colors: materials/recon (steel blue armor, dark navy armor_dark, black frame, gunmetal joint, red
eye, amber emblem) and brass bolts (bolt).
Sizes and places are in mech space (meters): x right, y up (feet at 0), -z forward.
"""
import bpy, bmesh, math
from mathutils import Matrix, Vector, Euler

# Game space -> Blender socket empty space (the empties are turned 180 degrees about Z).
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
SOCKETS = {
    "Torso": (0.0, 5.4, 0.0), "ShoulderL": (-2.465, 7.865, 0.0), "ElbowL": (-2.465, 5.57, 0.0),
    "ShoulderR": (2.465, 7.865, 0.0), "ElbowR": (2.465, 5.57, 0.0), "Lower": (0.0, 5.2, 0.0),
    "HipL": (-1.5, 5.2, 0.0), "KneeL": (-1.5, 2.6, 0.0), "HipR": (1.5, 5.2, 0.0), "KneeR": (1.5, 2.6, 0.0),
    "PauldronPivotL": (-2.465, 7.865, 0.0), "PauldronPivotR": (2.465, 7.865, 0.0),
    "FootPivotL": (-1.5, 0.55, 0.0), "FootPivotR": (1.5, 0.55, 0.0),
}
PREVIEW = {"armor": (0.23, 0.34, 0.5), "armor_dark": (0.1, 0.14, 0.22), "frame": (0.05, 0.05, 0.06),
           "joint": (0.17, 0.17, 0.18), "eye": (0.9, 0.08, 0.04), "emblem": (0.95, 0.55, 0.12),
           "lens": (0.35, 0.4, 0.45), "bolt": (0.62, 0.48, 0.25)}

_holder = {}   # socket name -> Blender object that holds the pieces (empty for this part)
_count = {}


# ---- Outlines (2D, centered) ----

def crect(w, h, c=0.15):
    """Rectangle w x h with cut corners. c: one size or (top-left, top-right, bottom-right, bottom-left)."""
    tl, tr, br, bl = (c, c, c, c) if isinstance(c, (int, float)) else c
    x, y = w * 0.5, h * 0.5
    pts = [(-x + tl, y), (x - tr, y), (x, y - tr), (x, -y + br), (x - br, -y), (-x + bl, -y), (-x, -y + bl), (-x, y - tl)]
    out = []
    for p in pts:
        if not out or (abs(out[-1][0] - p[0]) > 1e-4 or abs(out[-1][1] - p[1]) > 1e-4):
            out.append(p)
    if abs(out[0][0] - out[-1][0]) < 1e-4 and abs(out[0][1] - out[-1][1]) < 1e-4:
        out.pop()
    return out


def ngon(r, sides=6, start=90.0, sx=1.0, sy=1.0):
    return [(math.cos(math.radians(start + i * 360.0 / sides)) * r * sx,
             math.sin(math.radians(start + i * 360.0 / sides)) * r * sy) for i in range(sides)]


def trapezoid(top, bottom, h, c=0.1):
    """Wider or narrower at the top, with cut corners."""
    t, b, y = top * 0.5, bottom * 0.5, h * 0.5
    return [(-t + c, y), (t - c, y), (t, y - c), (b, -y + c), (b - c, -y), (-b + c, -y), (-b, -y + c), (-t, y - c)]


# ---- Mesh building ----

def _material_slots(o, mats):
    o.data.materials.clear()
    for m in mats:
        o.data.materials.append(bpy.data.materials[m])


def _finish(name, socket, bm, mats, bevel):
    """Mesh from bm (vertices in mech space), put under the socket holder."""
    offset = Matrix.Translation(-Vector(SOCKETS[socket]))
    bmesh.ops.transform(bm, matrix=C @ offset, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    n = _count.get(name, 0)
    _count[name] = n + 1
    full = name if n == 0 else f"{name}{n}"
    # Origin at the piece center (the game sorts core pieces into center and side torso by it).
    center = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)
    bmesh.ops.translate(bm, vec=-center, verts=bm.verts)
    mesh = bpy.data.meshes.new(full)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(full, mesh)
    holder = _holder[socket]
    for c in holder.users_collection:
        c.objects.link(o)
    o.parent = holder
    o.matrix_parent_inverse = Matrix.Identity(4)
    o.location = center
    _material_slots(o, mats)
    if bevel > 0.0:
        mod = o.modifiers.new("Soft", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = False
    return o


def _axis_point(u, v, w, axis):
    if axis == "z":
        return Vector((u, v, w))
    if axis == "x":
        return Vector((w, v, u))
    return Vector((u, w, v))  # axis y: outline in x-z, extruded up


def _axis_vec(axis, sign):
    return {"z": Vector((0, 0, sign)), "x": Vector((sign, 0, 0)), "y": Vector((0, sign, 0))}[axis]


def plate(name, socket, outline, depth, pos, rot=(0, 0, 0), axis="z", mat="armor", front_scale=0.85,
          back_scale=1.0, panel="front", inset=0.09, bolts=None, bevel=0.035, extra_mats=None):
    """Armor piece: outline extruded along axis (game), front face (-axis) scaled by front_scale.
    panel: face that gets an inset panel line ("front", "back" or None). bolts: list of outline
    points (u, v) on that face. pos: center in mech space. rot: degrees (game X, Y, Z; order Y X Z)."""
    bm = bmesh.new()
    front, back = [], []
    for u, v in outline:
        front.append(bm.verts.new(_axis_point(u * front_scale, v * front_scale, -depth * 0.5, axis)))
        back.append(bm.verts.new(_axis_point(u * back_scale, v * back_scale, depth * 0.5, axis)))
    f_front = bm.faces.new(front)
    f_back = bm.faces.new(list(reversed(back)))
    count = len(outline)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bm.normal_update()
    if panel is not None:
        face = f_front if panel == "front" else f_back
        result = bmesh.ops.inset_individual(bm, faces=[face], thickness=inset, depth=0.0)
        inner = [f for f in result["faces"]] + [face]
        bmesh.ops.inset_individual(bm, faces=[face], thickness=0.035, depth=-0.035)
    if bolts:
        sign = -1 if panel != "back" else 1
        scale = front_scale if sign < 0 else back_scale
        for u, v in bolts:
            p = _axis_point(u * scale, v * scale, sign * depth * 0.5, axis)
            _bolt(bm, p, _axis_vec(axis, sign))
    r = Euler([math.radians(a) for a in rot], "YXZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(pos)) @ r, verts=bm.verts)
    return _finish(name, socket, bm, [mat, "bolt"] + (extra_mats or []), bevel)


def _bolt(bm, point, normal, radius=0.055):
    rot = normal.to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation(point + normal * 0.02) @ rot
    geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=radius,
                                 radius2=radius * 0.8, depth=0.07, matrix=m)
    for v in geom["verts"]:
        for f in v.link_faces:
            f.material_index = 1


def cylinder(name, socket, radius, length, pos, axis="x", mat="joint", sides=20, rings=None, bevel=0.02, rot=(0, 0, 0)):
    """Cylinder along a game axis. rings: list of (offset along the axis, radius, width) extra bands."""
    bm = bmesh.new()
    turn = {"y": Matrix.Identity(4), "x": Matrix.Rotation(math.radians(-90), 4, "Z"),
            "z": Matrix.Rotation(math.radians(90), 4, "X")}[axis]
    # create_cone makes a Z cylinder: turn Z to Y first, then to the axis.
    to_y = Matrix.Rotation(math.radians(-90), 4, "X")
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius,
                          depth=length, matrix=turn @ to_y)
    for off, r2, w in (rings or []):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r2, radius2=r2,
                              depth=w, matrix=turn @ Matrix.Translation((0, off, 0)) @ to_y)
    r = Euler([math.radians(a) for a in rot], "YXZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(pos)) @ r, verts=bm.verts)
    return _finish(name, socket, bm, [mat], bevel)


def mirror(k, p):
    return (p[0] * k, p[1], p[2])


# ---- Parts ----

def head():
    S = "Torso"
    _holder[S] = bpy.data.objects["Torso_head"]
    # Wedge helmet: side outline (z forward/back, y up), extruded across x; sloped top and brow.
    helmet = [(-0.95, -0.25), (-0.95, 0.15), (-0.55, 0.5), (0.45, 0.62), (0.75, 0.3), (0.75, -0.35), (-0.4, -0.45)]
    plate("Helmet", S, helmet, 1.25, (0, 8.55, -0.55), (0, 0, 0), "x", "armor", 0.9, 0.9, None)
    plate("HelmetSideL", S, crect(0.9, 0.55, 0.15), 0.12, (-0.66, 8.5, -0.6), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    plate("HelmetSideR", S, crect(0.9, 0.55, 0.15), 0.12, (0.66, 8.5, -0.6), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    plate("Crest", S, crect(1.1, 0.22, (0.1, 0.05, 0.02, 0.02)), 0.3, (0, 9.12, -0.5), (0, 0, 0), "x", "armor", 1.0, 1.0, None)
    plate("Visor", S, crect(0.95, 0.2, 0.06), 0.2, (0, 8.47, -1.47), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.015)
    for k in (-1, 1):
        plate("Eye", S, crect(0.18, 0.1, 0.03), 0.06, (k * 0.2, 8.47, -1.58), (0, 0, 0), "z", "eye", 1.0, 1.0, None, bevel=0.0)
    plate("Chin", S, trapezoid(0.8, 0.5, 0.35, 0.08), 0.5, (0, 8.18, -1.25), (15, 0, 0), "z", "armor_dark", 0.9, 1.0, None)
    cylinder("Lens", S, 0.09, 0.2, (0.0, 8.2, -1.52), "z", "lens", 12)
    cylinder("Aerial", S, 0.04, 0.55, (-0.45, 9.25, -0.3), "y", "frame", 8)
    cylinder("AerialBase", S, 0.08, 0.12, (-0.45, 9.0, -0.3), "y", "joint", 8)
    plate("Neck", S, crect(0.7, 0.45, 0.1), 0.8, (0, 7.95, -0.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None)


def core():
    S = "Torso"
    _holder[S] = bpy.data.objects["Torso_core"]
    # Chest body: wide octagon from the front, deep, sloped to the front.
    plate("Chest", S, crect(2.6, 2.15, (0.55, 0.55, 0.45, 0.45)), 2.0, (0, 7.33, 0.0), (0, 0, 0), "z", "armor_dark", 0.88, 1.0, None)
    # Upper chest plates beside the head (sloped back), with bolts.
    for k in (-1, 1):
        plate("ChestUpper", S, crect(0.95, 0.9, (0.25, 0.1, 0.15, 0.1) if k < 0 else (0.1, 0.25, 0.1, 0.15)), 0.3,
              (k * 0.72, 8.1, -0.95), (-28, 0, 0), "z", "armor", 0.9, 1.0, "front", 0.08,
              bolts=[(-0.32, 0.32), (0.32, 0.32), (-0.32, -0.32), (0.32, -0.32)])
    # Center chest plate with vent slots.
    plate("ChestCenter", S, trapezoid(1.45, 1.1, 1.15, 0.18), 0.34, (0, 7.05, -1.05), (-6, 0, 0), "z", "armor", 0.92, 1.0, "front", 0.08,
          bolts=[(-0.55, 0.45), (0.55, 0.45)])
    for i in range(3):
        plate("ChestVent", S, crect(0.7, 0.07, 0.02), 0.08, (0, 6.85 - i * 0.14, -1.24), (-6, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
    plate("Belly", S, trapezoid(1.2, 0.9, 0.45, 0.1), 0.3, (0, 6.15, -0.82), (8, 0, 0), "z", "armor", 0.9, 1.0, None)
    plate("ChestMark", S, crect(0.35, 0.06, 0.01), 0.04, (-0.3, 7.52, -1.18), (-6, 0, 0), "z", "emblem", 1.0, 1.0, None, bevel=0.0)
    # Side blocks under the shoulders (side torso hit areas).
    for k in (-1, 1):
        plate("ChestSide", S, crect(1.6, 1.65, 0.3), 0.75, (k * 1.45, 7.2, 0.05), (0, 90, 0), "z", "armor", 0.9, 1.0,
              "front" if k < 0 else "back", 0.1, bolts=[(-0.55, 0.5), (0.55, 0.5), (-0.55, -0.5), (0.55, -0.5)])
    # Black waist and abdomen (narrow).
    plate("Abdomen", S, trapezoid(1.3, 0.95, 0.6, 0.12), 1.1, (0, 6.05, 0.05), (0, 0, 0), "z", "frame", 0.95, 1.0, None)
    cylinder("Waist", S, 0.62, 0.35, (0, 5.75, 0.05), "y", "joint", 24, rings=[(0.12, 0.66, 0.06)])
    plate("Collar", S, crect(1.6, 0.35, 0.1), 1.2, (0, 8.45, 0.35), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
    plate("Back", S, crect(1.9, 1.6, 0.35), 0.5, (0, 7.5, 1.05), (0, 0, 0), "z", "frame", 1.0, 0.9, None)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    _holder["Torso"] = bpy.data.objects[f"Torso_{part}"]
    # Thick black shoulder joint from the chest side to the pauldron.
    cylinder(f"ShoulderJoint{s}", "Torso", 0.52, 0.95, (k * 1.95, 7.865, 0), "x", "frame", 24,
             rings=[(k * -0.25, 0.58, 0.12), (k * 0.2, 0.58, 0.12)])
    # Pauldron: huge chamfered block (outline in the side view), rising to head height.
    P = f"PauldronPivot{s}"
    _holder[P] = bpy.data.objects[P]
    side = [(-1.3, -0.7), (-1.3, 0.6), (-0.9, 1.0), (0.95, 1.0), (1.25, 0.7), (1.25, -0.6), (0.9, -1.0), (-0.95, -1.0)]
    plate(f"Pauldron{s}", P, side, 1.5, (k * 2.95, 7.95, 0.0), (0, 0, 0), "x", "armor",
          1.0 if k < 0 else 0.92, 0.92 if k < 0 else 1.0,
          "back" if k > 0 else "front", 0.12,
          bolts=[(-1.0, 0.6), (0.95, 0.65), (0.95, -0.6), (-1.0, -0.6), (0.0, 0.75), (0.0, -0.75)])
    # Square vent on the outer face, toward the back.
    plate(f"PauldronVent{s}", P, crect(0.55, 0.55, 0.06), 0.14, (k * 3.72, 7.9, 0.5), (0, 90, 0), "z", "frame", 1.0, 1.0, None, bevel=0.01)
    plate(f"PauldronVentIn{s}", P, crect(0.4, 0.4, 0.04), 0.1, (k * 3.76, 7.9, 0.5), (0, 90, 0), "z", "joint", 1.0, 1.0, None, bevel=0.0)
    plate(f"PauldronTop{s}", P, crect(1.2, 1.9, 0.3), 0.2, (k * 2.95, 9.0, -0.05), (90, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
    plate(f"PauldronInner{s}", P, crect(1.7, 1.3, 0.25), 0.12, (k * 2.22, 7.95, 0.0), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    # Upper arm: black frame with an outer armor plate.
    SH = f"Shoulder{s}"
    _holder[SH] = bpy.data.objects[f"{SH}_{part}"]
    cylinder(f"UpperArmFrame{s}", SH, 0.3, 1.8, (k * 2.465, 6.75, 0), "y", "frame", 16, rings=[(0.6, 0.36, 0.14), (-0.4, 0.36, 0.14)])
    plate(f"UpperArm{s}", SH, crect(0.95, 1.2, 0.18), 0.3, (k * 2.9, 6.6, 0), (0, 90, 0), "z", "armor", 0.9, 1.0,
          "front" if k < 0 else "back", 0.08, bolts=[(-0.3, 0.42), (0.3, 0.42)])
    # Elbow and forearm guard (six-sided), wrist, fist.
    EL = f"Elbow{s}"
    _holder[EL] = bpy.data.objects[f"{EL}_{part}"]
    cylinder(f"Elbow{s}", EL, 0.36, 0.75, (k * 2.465, 5.57, 0), "x", "frame", 20, rings=[(0.0, 0.42, 0.18)])
    guard = [(-0.5, 0.35), (-0.3, 0.6), (0.3, 0.6), (0.5, 0.35), (0.5, -0.35), (0.3, -0.6), (-0.3, -0.6), (-0.5, -0.35)]
    plate(f"Forearm{s}", EL, guard, 1.65, (k * 2.5, 4.55, 0.05), (0, 0, 0), "y", "armor", 0.85, 1.0, None)
    plate(f"ForearmFront{s}", EL, crect(0.8, 1.35, 0.2), 0.14, (k * 2.5, 4.6, -0.63), (0, 0, 0), "z", "armor", 1.0, 1.0, "front", 0.08,
          bolts=[(-0.28, 0.5), (0.28, 0.5), (-0.28, -0.5), (0.28, -0.5)])
    plate(f"ForearmOuter{s}", EL, crect(1.0, 1.3, 0.2), 0.12, (k * 3.02, 4.55, 0.05), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    cylinder(f"Wrist{s}", EL, 0.24, 0.35, (k * 2.465, 3.55, 0), "y", "joint", 16)
    plate(f"Fist{s}", EL, crect(0.6, 0.6, 0.12), 0.65, (k * 2.465, 3.1, -0.05), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
    for i in range(4):
        cylinder(f"Knuckle{s}", EL, 0.08, 0.14, (k * 2.465 + (i - 1.5) * 0.14, 2.82, -0.3), "z", "joint", 8)


def legs():
    L = "Lower"
    _holder[L] = bpy.data.objects["Lower_legs"]
    plate("Pelvis", L, crect(1.7, 0.8, 0.2), 1.3, (0, 5.25, 0.0), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
    plate("Skirt", L, trapezoid(0.85, 0.55, 0.9, 0.15), 0.25, (0, 4.95, -0.78), (-10, 0, 0), "z", "armor", 0.9, 1.0, "front", 0.07)
    plate("SkirtMark", L, crect(0.3, 0.35, 0.08), 0.06, (0, 4.95, -0.93), (-10, 0, 0), "z", "armor_dark", 1.0, 1.0, None, bevel=0.0)
    plate("SkirtBack", L, trapezoid(1.0, 0.7, 0.8, 0.12), 0.25, (0, 5.0, 0.75), (10, 0, 0), "z", "armor_dark", 0.9, 1.0, None)
    for s, k in (("L", -1), ("R", 1)):
        cylinder(f"HipJoint{s}", L, 0.5, 0.7, (k * 1.05, 5.2, 0), "x", "frame", 24, rings=[(0.0, 0.55, 0.14)])
        H = f"Hip{s}"
        _holder[H] = bpy.data.objects[f"{H}_legs"]
        cylinder(f"ThighFrame{s}", H, 0.32, 2.3, (k * 1.5, 3.95, 0.15), "y", "frame", 16, rings=[(0.7, 0.38, 0.16)])
        # Tall front thigh plate with cut corners, and a side plate.
        plate(f"Thigh{s}", H, crect(1.5, 2.05, (0.35, 0.35, 0.22, 0.22)), 0.6, (k * 1.5, 4.05, -0.47), (-3, 0, 0), "z", "armor", 0.9, 1.0,
              "front", 0.1, bolts=[(-0.56, 0.82), (0.56, 0.82), (-0.56, -0.82), (0.56, -0.82)])
        plate(f"ThighSide{s}", H, crect(1.2, 1.6, 0.25), 0.2, (k * 2.18, 4.05, -0.05), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
        K = f"Knee{s}"
        _holder[K] = bpy.data.objects[f"{K}_legs"]
        cylinder(f"KneeJoint{s}", K, 0.42, 1.0, (k * 1.5, 2.6, 0), "x", "frame", 20, rings=[(0.3, 0.47, 0.12), (-0.3, 0.47, 0.12)])
        # Big six-sided knee pad.
        plate(f"KneePad{s}", K, ngon(0.72, 6, 90), 0.4, (k * 1.5, 2.75, -0.72), (-8, 0, 0), "z", "armor", 0.85, 1.0, "front", 0.1,
              bolts=[(0.0, 0.5), (0.43, 0.25), (0.43, -0.25), (0.0, -0.5), (-0.43, -0.25), (-0.43, 0.25)])
        # Tapered shin with a front strip; black calf pistons behind.
        plate(f"Shin{s}", K, trapezoid(1.25, 1.0, 1.9, 0.2), 1.15, (k * 1.5, 1.45, -0.1), (0, 0, 0), "z", "armor", 0.88, 1.0,
              "front", 0.1, bolts=[(-0.42, 0.72), (0.42, 0.72)])
        plate(f"ShinStrip{s}", K, crect(0.4, 1.4, 0.1), 0.1, (k * 1.5, 1.4, -0.72), (0, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
        for off in (-0.25, 0.25):
            cylinder(f"Calf{s}", K, 0.12, 1.5, (k * 1.5 + off, 1.5, 0.62), "y", "frame", 10, rings=[(0.35, 0.16, 0.2)])
        plate(f"ShinFrame{s}", K, crect(0.5, 1.9, 0.1), 0.5, (k * 1.5, 1.55, 0.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        F = f"FootPivot{s}"
        _holder[F] = bpy.data.objects[F]
        cylinder(f"Ankle{s}", F, 0.36, 1.0, (k * 1.5, 0.55, 0), "x", "frame", 20, rings=[(0.0, 0.4, 0.2)])
        # Wedge foot: side outline (z forward/back, y up) extruded across x.
        wedge = [(-1.75, 0.0), (-1.75, 0.3), (-1.2, 0.45), (-0.2, 0.75), (0.7, 0.75), (1.05, 0.4), (1.05, 0.0)]
        plate(f"Foot{s}", F, wedge, 1.3, (k * 1.5, 0.0, -0.3), (0, 0, 0), "x", "armor", 1.0, 1.0, None)
        plate(f"FootTop{s}", F, crect(1.0, 0.9, 0.15), 0.12, (k * 1.5, 0.62, -0.9), (-72, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
        plate(f"Toe{s}", F, crect(1.1, 0.3, 0.08), 0.45, (k * 1.5, 0.15, -2.2), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        plate(f"Heel{s}", F, crect(0.9, 0.35, 0.08), 0.5, (k * 1.5, 0.18, 0.95), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        plate(f"FootSole{s}", F, crect(1.25, 2.9, 0.2), 0.12, (k * 1.5, 0.06, -0.35), (90, 0, 0), "z", "frame", 1.0, 1.0, None)


def booster():
    S = "Torso"
    _holder[S] = bpy.data.objects["Torso_booster"]
    plate("Backpack", S, crect(1.5, 1.6, 0.2), 0.75, (0, 7.45, 1.62), (0, 0, 0), "z", "armor_dark", 1.0, 0.9, None)
    for i, (x, y, w, h) in enumerate(((-0.35, 7.8, 0.5, 0.45), (0.35, 7.8, 0.5, 0.45), (-0.35, 7.2, 0.5, 0.4))):
        plate("Grille", S, crect(w, h, 0.05), 0.08, (x, y, 2.02), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
        for j in range(3):
            plate("GrilleBar", S, crect(w * 0.8, 0.04, 0.0), 0.04, (x, y - h * 0.3 + j * h * 0.3, 2.07), (0, 0, 0), "z", "joint", 1.0, 1.0, None, bevel=0.0)
    for k in (-1, 1):
        cylinder("Nozzle", S, 0.3, 0.55, (k * 0.64, 6.25, 1.85), "y", "joint", 16, rot=(25, 0, 0))
        # Stepped antenna masts behind the shoulders.
        plate("MastBase", S, crect(0.45, 0.5, 0.08), 0.45, (k * 0.55, 8.35, 1.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        cylinder("Mast", S, 0.17, 0.9, (k * 0.55, 9.05, 1.3), "y", "frame", 14, rings=[(0.3, 0.21, 0.1)])
        cylinder("Mast", S, 0.11, 1.5, (k * 0.55, 10.2, 1.3), "y", "frame", 12, rings=[(0.55, 0.14, 0.08)])
        cylinder("MastTip", S, 0.14, 0.14, (k * 0.55, 10.98, 1.3), "y", "joint", 12)


def clear_parts():
    keep = set()
    for col in bpy.data.collections:
        if col.name.startswith("part_"):
            for o in col.all_objects:
                if o.type == "EMPTY":
                    keep.add(o.name)
    for col in bpy.data.collections:
        if col.name.startswith("part_"):
            for o in list(col.all_objects):
                if o.name not in keep:
                    bpy.data.objects.remove(o, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def preview_colors():
    for name, color in PREVIEW.items():
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            mat.use_fake_user = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85 if name == "bolt" else 0.45


def build():
    clear_parts()
    preview_colors()
    head()
    core()
    arm("L")
    arm("R")
    legs()
    booster()
    bpy.ops.wm.save_mainfile()
    exec(bpy.data.texts["export_parts.py"].as_string())


build()
