"""Builds Shotgun 2 (one-hand electric pulse shotgun with a three-head "hammerhead" emitter) and exports it.

Run (from the project root):
    blender -b --python tools/blender/shotgun_2_build.py
Writes models/shotgun_2/shotgun_2.blend and shotgun_2.glb. The script starts from an empty file.

From the user's picture models/guides/shotgun_2_ref.png (2026-11-01; side, front, back, top, bottom, 3/4 views):
three chunky heads 120 degrees apart around a round emitter (they open at each shot and close again), an olive body
with slanted vents and a yellow panel, a top rail and carry handle, a dark lower receiver with a hose loop, a
dark pistol grip, a dark stock frame with an olive butt plate (yellow stripe) and a dark pad. User rule: no lettering
or decals on the body.

Frame: the first Shotgun's (tools/mech_gen/shotgun.py): Godot -Z forward, the bore on y = 0, the pistol grip at the
same place and size (top (0, -0.2, -1.7), raked 20 degrees, 0.96 m long), so the Shotgun's hand markers and hold fit.
Picture pixels (level side view) go to Godot meters by GZ and GY: 0.005 m per pixel.
Blender +Y = Godot -Z, Blender +Z = Godot +Y.
Nodes for the weapon scene: Head0 (top), Head1, Head2 (empties on the hinges, the head meshes under them),
EmitterRing (blue glow at a shot), ArcRing (the electric arc between the heads, shown at a shot), Muzzle, GripRight.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "shotgun_2")
M = 0.005  # Meters per picture pixel.
BEVEL = 0.014

MATERIALS = {
    "shotgun_2_olive": ((0.27, 0.30, 0.16), 0.6, 0.1, 0.0),
    "shotgun_2_dark": ((0.07, 0.072, 0.078), 0.55, 0.35, 0.0),
    "shotgun_2_grey": ((0.16, 0.165, 0.175), 0.5, 0.45, 0.0),
    "shotgun_2_yellow": ((0.85, 0.62, 0.08), 0.5, 0.1, 0.0),
    "shotgun_2_blue": ((0.3, 0.6, 1.0), 0.3, 0.0, 3.0),
}
OL, D, GR, Y, BL = ("shotgun_2_olive", "shotgun_2_dark", "shotgun_2_grey", "shotgun_2_yellow", "shotgun_2_blue")


def GZ(x):
    """Picture x (level side view) to Godot z: the grip lines up with the first Shotgun's."""
    return -(985 - x) * M - 0.575


def GY(y):
    return -(y - 535) * M


def B(g):
    """Godot (x, y, z) to Blender (x, y, z)."""
    return Vector((g[0], -g[2], g[1]))


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, glow = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = glow
    mat.diffuse_color = (*color, 1.0)
    return mat


def finish(obj, mat, bevel=BEVEL, parent=None):
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        if hasattr(obj.data, "use_auto_smooth"):
            obj.data.use_auto_smooth = True
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_basis.inverted()
    return obj


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def prism(name, mat, outline, width, x=0.0, bevel=BEVEL, parent=None):
    """Side outline [(picture x, picture y)] extruded across X (width m), centered on x."""
    bm = bmesh.new()
    verts = [bm.verts.new(B((x - width / 2, GY(v), GZ(u)))) for u, v in outline]
    face = bm.faces.new(verts)
    out = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [g for g in out["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(width, 0, 0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel, parent)


def box(name, mat, x0, x1, y0, y1, width, x=0.0, bevel=BEVEL, parent=None):
    return prism(name, mat, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], width, x, bevel, parent)


def gbox(name, mat, center, size, basis=None, bevel=BEVEL, parent=None):
    """Box in Godot meters: center, size (x, y, z), optional Godot basis (3 column vectors x, y, z)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        p = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if basis is not None:
            p = basis[0] * p.x + basis[1] * p.y + basis[2] * p.z
        v.co = B(Vector(center) + p)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel, parent)


def gtube(name, mat, z0, z1, radius, center=(0.0, 0.0), sides=32, bevel=0.01, parent=None):
    """Cylinder along Godot z from z0 to z1."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=abs(z1 - z0))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
    bmesh.ops.translate(bm, vec=B((center[0], center[1], (z0 + z1) / 2)), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel, parent)


def gtorus(name, mat, z, major, minor, parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=48, minor_segments=8,
                                     location=B((0.0, 0.0, z)), rotation=(math.radians(90), 0, 0))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return finish(obj, mat, 0.0, parent)


def empty(name, g, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = B(g)
    bpy.context.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


# Heads (Godot meters): hinges on a ring around the bore at the emitter's front; the head blocks farther out.
HEAD_ANGLES = (90.0, 210.0, 330.0)   # Top, lower left (Godot +x is the gun's left), lower right.
HINGE_R, HINGE_Z = 0.27, GZ(205)
HEAD_R = 0.52                        # Radius of the head block's middle.
HEAD_Z0, HEAD_Z1 = GZ(60), GZ(185)   # Front and back of a head block.
HEAD_T, HEAD_W = 0.36, 0.48          # Radial thickness and width of a head block.


def head(i, angle_deg):
    a = math.radians(angle_deg)
    radial = Vector((math.cos(a), math.sin(a), 0.0))
    tangent = Vector((-math.sin(a), math.cos(a), 0.0))
    forward = Vector((0.0, 0.0, 1.0))
    hinge = radial * HINGE_R + Vector((0.0, 0.0, HINGE_Z))
    pivot = empty(f"Head{i}", hinge)
    basis = (tangent, radial, forward)
    zc = (HEAD_Z0 + HEAD_Z1) / 2
    length = abs(HEAD_Z0 - HEAD_Z1)
    block = radial * HEAD_R + Vector((0.0, 0.0, zc))
    gbox(f"HeadBlock{i}", D, block, (HEAD_W, HEAD_T, length), basis, 0.03, pivot)
    # Outer armor plate (olive on the top head, dark grey on the lower ones, like the picture), a yellow front cap on
    # its outer half, a yellow stripe and a dark slot on the outer face.
    plate = radial * (HEAD_R + HEAD_T / 2 + 0.02) + Vector((0.0, 0.0, zc + 0.02))
    gbox(f"HeadPlate{i}", OL if i == 0 else GR, plate, (HEAD_W - 0.04, 0.05, length - 0.1), basis, 0.012, pivot)
    cap = radial * (HEAD_R + 0.05) + Vector((0.0, 0.0, HEAD_Z0 + 0.04))
    gbox(f"HeadCap{i}", Y, cap, (HEAD_W - 0.02, HEAD_T * 0.55, 0.1), basis, 0.012, pivot)
    stripe = radial * (HEAD_R + HEAD_T / 2 + 0.05) + Vector((0.0, 0.0, HEAD_Z0 + 0.2))
    gbox(f"HeadStripe{i}", Y, stripe, (HEAD_W - 0.08, 0.012, 0.08), basis, 0.0, pivot)
    slot = radial * (HEAD_R + HEAD_T / 2 + 0.05) + Vector((0.0, 0.0, zc + 0.12))
    gbox(f"HeadSlot{i}", D, slot, (HEAD_W * 0.45, 0.012, 0.16), basis, 0.0, pivot)
    # Arm from the hinge to the block's back, and the hinge knuckle.
    arm_from = hinge
    arm_to = radial * (HEAD_R - 0.04) + Vector((0.0, 0.0, HEAD_Z1 + 0.05))
    mid = (arm_from + arm_to) / 2
    along = (arm_to - arm_from).normalized()
    side = tangent
    up = side.cross(along).normalized()
    gbox(f"HeadArm{i}", GR, mid, (0.16, 0.12, (arm_to - arm_from).length + 0.06), (side, up, along), 0.012, pivot)
    gbox(f"HeadKnuckle{i}", D, hinge, (0.22, 0.1, 0.1), basis, 0.01, pivot)


def build():
    # Emitter: dark hub, a grey front plate, a blue glow ring and a dark lens; the electric arc ring between the heads.
    gtube("Hub", D, GZ(115), GZ(245), 0.27)
    gtube("HubBand", GR, GZ(205), GZ(225), 0.285, bevel=0.004)
    gtube("EmitterPlate", GR, GZ(108), GZ(118), 0.22, bevel=0.006)
    gtube("EmitterRing", BL, GZ(104), GZ(109), 0.17, bevel=0.0)
    gtube("EmitterLens", D, GZ(102), GZ(106), 0.11, bevel=0.0)
    gtorus("ArcRing", BL, GZ(95), 0.46, 0.025)
    for i, a in enumerate(HEAD_ANGLES):
        head(i, a)

    # Front collar and the olive main body with slanted vents and a yellow panel.
    box("Collar", D, 175, 245, 466, 604, 0.6, bevel=0.025)
    for k, x in enumerate((200, 222)):
        box(f"CollarBand{k}", GR, x, x + 8, 464, 606, 0.612, bevel=0.0)
    prism("Body", OL, [(245, 480), (300, 470), (560, 470), (560, 576), (245, 576)], 0.52)
    prism("BodyPanel", OL, [(262, 486), (304, 478), (548, 478), (548, 506), (262, 506)], 0.55, bevel=0.008)
    for k in range(4):
        x = 300 + k * 22
        prism(f"Vent{k}", D, [(x + 10, 515), (x + 18, 515), (x + 8, 548), (x, 548)], 0.532, bevel=0.0)
    prism("YellowPanel", Y, [(555, 470), (614, 470), (602, 540), (545, 540)], 0.54)
    box("RearUpper", GR, 600, 748, 492, 554, 0.46)
    box("RearPanel", OL, 614, 736, 500, 542, 0.48, bevel=0.008)

    # Top rail with notches, and the carry handle.
    box("TopRail", D, 300, 700, 461, 472, 0.2, bevel=0.004)
    for k in range(10):
        x = 320 + k * 36
        box(f"RailNotch{k}", GR, x, x + 6, 459, 462, 0.21, bevel=0.0)
    box("HandleBar", D, 450, 632, 440, 455, 0.12, bevel=0.01)
    for k, x in enumerate((450, 612)):
        box(f"HandlePost{k}", D, x, x + 20, 446, 466, 0.12, bevel=0.006)

    # Lower receiver, a hose loop under it, the trigger guard and trigger.
    box("LowerReceiver", D, 240, 748, 574, 614, 0.42)
    pts = [(398, 600), (412, 618), (440, 628), (480, 630), (520, 624), (548, 610), (560, 598)]
    for k in range(len(pts) - 1):
        a = Vector((0.0, GY(pts[k][1]), GZ(pts[k][0])))
        b = Vector((0.0, GY(pts[k + 1][1]), GZ(pts[k + 1][0])))
        mid = (a + b) / 2
        along = (b - a).normalized()
        up = Vector((1.0, 0.0, 0.0)).cross(along).normalized()
        gbox(f"Hose{k}", GR, mid, (0.075, 0.075, (b - a).length + 0.03), (Vector((1.0, 0.0, 0.0)), up, along), 0.02)
    box("TriggerGuard", D, 688, 748, 612, 642, 0.2, bevel=0.01)
    box("Trigger", GR, 712, 722, 612, 634, 0.06, bevel=0.0)

    # Pistol grip: the first Shotgun's place and size (dark), grey side panels, a dark base.
    top = Vector((0.0, -0.2, -1.7))
    axis = Vector((0.0, -0.9397, 0.342))
    back = Vector((0.0, 0.342, 0.9397))
    grip_basis = (Vector((1.0, 0.0, 0.0)), axis * -1.0, back)
    gbox("Grip", D, top + axis * 0.48, (0.2, 0.96, 0.24), grip_basis, 0.03)
    for side, sx in (("L", 0.105), ("R", -0.105)):
        gbox(f"GripPanel{side}", GR, top + axis * 0.55 + Vector((sx, 0.0, 0.0)) + back * 0.02, (0.012, 0.55, 0.15),
             grip_basis, 0.0)
    gbox("GripBase", D, top + axis * 0.98, (0.24, 0.07, 0.3), grip_basis, 0.015)

    # Stock: dark frame, lower brace, olive butt plate with a yellow stripe, dark pad with grey ribs.
    prism("StockFrame", D, [(745, 495), (905, 495), (905, 562), (872, 562), (860, 548), (745, 554)], 0.36)
    prism("StockBrace", D, [(800, 552), (842, 552), (905, 598), (905, 612), (878, 612)], 0.32)
    box("ButtPlate", OL, 900, 948, 486, 610, 0.42)
    box("ButtStripe", Y, 924, 938, 498, 598, 0.432, bevel=0.0)
    box("ButtPad", D, 946, 985, 482, 614, 0.46, bevel=0.02)
    for k in range(5):
        y = 500 + k * 22
        box(f"PadRib{k}", GR, 975, 987, y, y + 5, 0.36, bevel=0.0)

    # Markers.
    empty("Muzzle", (0.0, 0.0, GZ(95)))
    empty("GripRight", (-0.2, -0.62287, -1.7261))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "shotgun_2.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "shotgun_2.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    ys = [(o.matrix_world @ Vector(c)).y for o in bpy.data.objects if o.type == "MESH" for c in o.bound_box]
    print("shotgun_2: %d objects, %d triangles, length %.2f m (godot z %.2f to %.2f)" % (
        len(bpy.data.objects), tris, max(ys) - min(ys), -max(ys), -min(ys)))
    for name in ("Head0", "Head1", "Head2", "Muzzle"):
        o = bpy.data.objects[name]
        print("node %s godot (%.3f, %.3f, %.3f)" % (name, o.location.x, o.location.z, -o.location.y))


main()
