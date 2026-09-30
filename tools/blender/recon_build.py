"""Builds the Recon mech model in models/recon/recon.blend, then exports the parts.

Run (from the project root):
    blender -b models/recon/recon.blend --python tools/blender/recon_build.py
It removes the old model pieces (not the socket and pivot empties) and builds them again, so edits
made by hand in the part collections are lost: after hand edits, export with export_parts.py only.

Design (user reference picture): slim sensor mech. Chamfered armor plates with bolts, big boxy
pauldrons with a square side vent, a low hooded head with two red eyes, two tall antennas on the
back, black frame limbs with round joints, six-sided knee plates, chunky feet, fists.
Colors: steel blue armor, dark navy armor_dark, black frame, gunmetal joints, red eyes, amber marks.
All sizes and places are in game units (meters) in the socket space: x right, y up, -z forward.
"""
import bpy, math
from mathutils import Matrix, Vector, Euler

# Game socket space -> Blender socket empty space (the empties are turned 180 degrees).
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
C_INV = C.inverted()

PREVIEW = {"armor": (0.23, 0.34, 0.5), "armor_dark": (0.1, 0.14, 0.22), "frame": (0.05, 0.05, 0.06),
           "joint": (0.17, 0.17, 0.18), "eye": (0.9, 0.08, 0.04), "emblem": (0.95, 0.55, 0.12),
           "lens": (0.35, 0.4, 0.45)}


def obj(name):
    return bpy.data.objects[name]


def place(o, parent, pos, rot):
    """Parents o to parent at game position pos with game rotation rot (degrees, order Y X Z)."""
    o.parent = parent
    o.matrix_parent_inverse = Matrix.Identity(4)
    r = Euler((math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2])), "YXZ").to_matrix()
    local = C @ r @ C_INV
    o.matrix_basis = Matrix.Translation(C @ Vector(pos)) @ local.to_4x4()
    for c in o.users_collection:
        c.objects.unlink(o)
    for c in parent.users_collection:
        c.objects.link(o)


def material(o, mat):
    o.data.materials.clear()
    o.data.materials.append(bpy.data.materials[mat])


def box(name, parent, size, pos=(0, 0, 0), rot=(0, 0, 0), mat="armor", chamfer=0.12, bolts=False):
    """Box of game size (x, y, z) with chamfered edges. bolts: four bolts on the front (-Z) face."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    gs = C @ Vector(size)
    o.scale = (abs(gs.x), abs(gs.y), abs(gs.z))
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if chamfer > 0.0:
        bevel = o.modifiers.new("Chamfer", "BEVEL")
        bevel.width = min(chamfer, min(size) * 0.45)
        bevel.segments = 1
        bevel.limit_method = "NONE"
    material(o, mat)
    place(o, parent, pos, rot)
    if bolts:
        hx, hy = size[0] * 0.5 - max(0.14, chamfer + 0.06), size[1] * 0.5 - max(0.14, chamfer + 0.06)
        for i, (bx, by) in enumerate(((-hx, -hy), (hx, -hy), (-hx, hy), (hx, hy))):
            cyl(f"{name}Bolt{i}", o, 0.05, 0.05, (bx, by, -size[2] * 0.5 - 0.01), "z", "joint", 8)
    return o


def cyl(name, parent, radius, length, pos=(0, 0, 0), axis="y", mat="joint", sides=16, rot=(0, 0, 0)):
    """Cylinder along a game axis ("x", "y" or "z")."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=length)
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    # A Blender cylinder runs along local Z = game Y. Turn it to the wanted game axis.
    base = {"y": (0, 0, 0), "x": (0, 0, 90), "z": (90, 0, 0)}[axis]
    material(o, mat)
    place(o, parent, pos, (base[0] + rot[0], base[1] + rot[1], base[2] + rot[2]))
    if sides <= 8:
        return o
    bevel = o.modifiers.new("Chamfer", "BEVEL")
    bevel.width = min(0.04, radius * 0.3)
    bevel.segments = 1
    return o


def hexplate(name, parent, radius, depth, pos, rot=(0, 0, 0), mat="armor"):
    """Six-sided plate facing forward (-Z)."""
    return cyl(name, parent, radius, depth, pos, "z", mat, 6, (rot[0], rot[1], 30 + rot[2]))


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


# ---- Parts ----

def head():
    t = obj("Torso_head")
    # Low hooded head, set forward into the chest (torso space: the Torso socket is 5.4 m up).
    box("HeadHood", t, (1.25, 0.75, 1.45), (0, 2.95, -0.55), (-8, 0, 0), "armor", 0.2)
    box("HeadCrest", t, (0.5, 0.25, 1.2), (0, 3.38, -0.45), (-8, 0, 0), "armor", 0.08)
    box("HeadFace", t, (0.95, 0.45, 0.3), (0, 2.62, -1.2), (0, 0, 0), "armor_dark", 0.06)
    box("HeadVisor", t, (0.8, 0.14, 0.12), (0, 2.72, -1.36), (0, 0, 0), "frame", 0.02)
    for s, x in (("L", -0.2), ("R", 0.2)):
        box(f"HeadEye{s}", t, (0.14, 0.08, 0.05), (x, 2.72, -1.43), (0, 0, 0), "eye", 0.0)
    cyl("HeadCamera", t, 0.09, 0.3, (0.38, 2.5, -1.3), "z", "lens")
    cyl("HeadAerial", t, 0.035, 0.6, (-0.45, 3.45, -0.2), "y", "frame", 8)
    box("HeadNeck", t, (0.7, 0.4, 0.8), (0, 2.45, -0.3), (0, 0, 0), "frame", 0.06)


def core():
    t = obj("Torso_core")
    # Chest: narrow core with slanted front plates, black abdomen, collar, back frame.
    box("ChestCore", t, (1.9, 1.6, 1.8), (0, 1.95, 0.0), (0, 0, 0), "armor_dark", 0.16)
    box("ChestFront", t, (1.5, 1.1, 0.3), (0, 2.1, -0.95), (-12, 0, 0), "armor", 0.12, bolts=True)
    box("ChestLower", t, (1.3, 0.55, 0.3), (0, 1.3, -0.9), (10, 0, 0), "armor", 0.1)
    for s, k in (("L", -1), ("R", 1)):
        box(f"ChestSide{s}", t, (0.75, 1.5, 1.7), (k * 1.25, 2.0, 0.05), (0, 0, k * -4), "armor", 0.16, bolts=True)
        box(f"ChestVent{s}", t, (0.45, 0.35, 0.08), (k * 0.45, 1.45, -1.08), (10, 0, 0), "frame", 0.02)
    box("ChestMark", t, (0.5, 0.08, 0.04), (0, 2.45, -1.12), (-12, 0, 0), "emblem", 0.0)
    box("Collar", t, (1.5, 0.35, 1.3), (0, 2.8, 0.2), (0, 0, 0), "frame", 0.08)
    box("Abdomen", t, (1.15, 0.9, 1.05), (0, 0.85, 0.05), (0, 0, 0), "frame", 0.1)
    cyl("WaistRing", t, 0.7, 0.35, (0, 0.3, 0), "y", "joint")
    box("BackFrame", t, (1.5, 1.5, 0.6), (0, 1.9, 1.05), (0, 0, 0), "frame", 0.08)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    t = obj(f"Torso_{part}")
    sx = k * 2.465
    # Shoulder joint on the torso.
    cyl(f"ShoulderJoint{s}", t, 0.5, 0.9, (k * 1.85, 2.465, 0), "x", "frame")
    cyl(f"ShoulderCap{s}", t, 0.36, 1.05, (k * 1.85, 2.465, 0), "x", "joint")
    # Pauldron: big boxy shell with a square side vent (turns with the arm).
    p = obj(f"PauldronPivot{s}")
    box(f"Pauldron{s}", p, (1.35, 1.35, 1.9), (k * 0.25, 0.4, 0), (0, 0, 0), "armor", 0.2, bolts=True)
    box(f"PauldronTop{s}", p, (1.15, 0.3, 1.6), (k * 0.25, 1.15, 0), (0, 0, 0), "armor_dark", 0.1)
    box(f"PauldronVent{s}", p, (0.1, 0.55, 0.7), (k * 0.96, 0.4, 0.15), (0, 0, 0), "frame", 0.03)
    box(f"PauldronFront{s}", p, (1.1, 0.8, 0.25), (k * 0.25, 0.35, -1.0), (8, 0, 0), "armor", 0.08)
    # Upper arm: black frame with an outer plate.
    sh = obj(f"Shoulder{s}_{part}")
    box(f"UpperArmFrame{s}", sh, (0.5, 1.9, 0.55), (0, -1.1, 0), (0, 0, 0), "frame", 0.08)
    box(f"UpperArm{s}", sh, (0.75, 1.1, 0.85), (k * 0.1, -1.05, 0), (0, 0, 0), "armor", 0.12)
    # Forearm: slim armored shell, elbow joint, fist.
    el = obj(f"Elbow{s}_{part}")
    cyl(f"ElbowJoint{s}", el, 0.33, 0.8, (0, 0, 0), "x", "joint")
    box(f"Forearm{s}", el, (0.9, 1.5, 1.0), (0, -1.0, 0.05), (0, 0, 0), "armor", 0.16, bolts=True)
    box(f"ForearmPlate{s}", el, (0.12, 1.1, 0.75), (k * 0.5, -0.95, 0.05), (0, 0, 0), "armor_dark", 0.04)
    box(f"Wrist{s}", el, (0.45, 0.4, 0.45), (0, -1.9, 0), (0, 0, 0), "frame", 0.05)
    box(f"Hand{s}", el, (0.55, 0.55, 0.6), (0, -2.3, -0.05), (0, 0, 0), "frame", 0.1)
    for i in range(3):
        box(f"Finger{s}{i}", el, (0.15, 0.3, 0.2), ((i - 1) * 0.18, -2.62, -0.2), (-20, 0, 0), "joint", 0.04)


def legs():
    lo = obj("Lower_legs")
    box("Pelvis", lo, (1.7, 0.75, 1.25), (0, 0.1, 0), (0, 0, 0), "frame", 0.12)
    box("Crotch", lo, (0.8, 0.8, 0.35), (0, -0.2, -0.72), (-8, 0, 0), "armor_dark", 0.1)
    box("CrotchMark", lo, (0.3, 0.06, 0.04), (0, -0.05, -0.92), (-8, 0, 0), "emblem", 0.0)
    box("PelvisBack", lo, (1.1, 0.7, 0.3), (0, -0.05, 0.7), (8, 0, 0), "armor_dark", 0.08)
    for s, k in (("L", -1), ("R", 1)):
        cyl(f"HipJoint{s}", lo, 0.42, 0.6, (k * 1.1, 0, 0), "x", "joint")
        hip = obj(f"Hip{s}_legs")
        box(f"ThighFrame{s}", hip, (0.5, 2.4, 0.55), (0, -1.3, 0), (0, 0, 0), "frame", 0.08)
        box(f"ThighPlate{s}", hip, (1.05, 1.7, 1.2), (0, -1.05, -0.08), (-3, 0, 0), "armor", 0.18, bolts=True)
        box(f"ThighSide{s}", hip, (0.12, 1.2, 0.85), (k * 0.58, -1.0, 0), (0, 0, 0), "armor_dark", 0.04)
        knee = obj(f"Knee{s}_legs")
        cyl(f"KneeJoint{s}", knee, 0.4, 0.9, (0, 0, 0), "x", "joint")
        hexplate(f"KneeCap{s}", knee, 0.55, 0.3, (0, -0.1, -0.62), (0, 0, 0), "armor")
        box(f"ShinFrame{s}", knee, (0.45, 1.9, 0.5), (0, -1.0, 0.1), (0, 0, 0), "frame", 0.08)
        box(f"Shin{s}", knee, (1.0, 1.5, 1.15), (0, -1.05, -0.08), (0, 0, 0), "armor", 0.18, bolts=True)
        box(f"Calf{s}", knee, (0.8, 1.3, 0.5), (0, -0.9, 0.6), (-6, 0, 0), "armor_dark", 0.1)
        foot = obj(f"FootPivot{s}")
        cyl(f"Ankle{s}", foot, 0.33, 0.95, (0, 0, 0), "x", "joint")
        box(f"Foot{s}", foot, (1.15, 0.45, 1.9), (0, -0.32, -0.3), (0, 0, 0), "armor", 0.14)
        box(f"Toe{s}", foot, (1.05, 0.38, 0.75), (0, -0.36, -1.5), (6, 0, 0), "armor_dark", 0.12)
        box(f"Heel{s}", foot, (0.75, 0.42, 0.65), (0, -0.33, 0.85), (0, 0, 0), "armor_dark", 0.1)
        box(f"FootFrame{s}", foot, (0.6, 0.2, 2.2), (0, -0.5, -0.3), (0, 0, 0), "frame", 0.04)


def booster():
    t = obj("Torso_booster")
    box("Backpack", t, (1.6, 1.5, 0.75), (0, 1.8, 1.55), (0, 0, 0), "frame", 0.1)
    box("BackpackPlate", t, (1.3, 1.1, 0.2), (0, 1.85, 1.98), (0, 0, 0), "armor_dark", 0.06, bolts=False)
    for s, k in (("L", -1), ("R", 1)):
        cyl(f"Nozzle{s}", t, 0.3, 0.55, (k * 0.64, 0.8, 1.85), "y", "joint", rot=(25, 0, 0))
        # Antennas: tall masts behind the shoulders (a recon mech's sensors).
        box(f"MastBase{s}", t, (0.35, 0.4, 0.35), (k * 0.5, 2.75, 1.3), (0, 0, 0), "frame", 0.05)
        cyl(f"Mast{s}", t, 0.11, 2.3, (k * 0.5, 4.05, 1.3), "y", "frame", 12)
        cyl(f"MastRing{s}", t, 0.16, 0.12, (k * 0.5, 4.6, 1.3), "y", "joint", 12)
        cyl(f"MastTip{s}", t, 0.06, 0.3, (k * 0.5, 5.35, 1.3), "y", "frame", 8)


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
