"""Builds Pile Bunker 2 (user design 2026-10-31: drill stake, olive grip housing, carry handle, tan body).

Run (from the project root):
    blender -b --python tools/blender/pilebunker_2_build.py
Writes models/pilebunker_2/pilebunker_2.blend and pilebunker_2.glb.
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Shapes from the user's picture, models/guides/pilebunker_2_ref.png (3/4, front, side and top views; sizes
are estimated from the side view, about 0.00635 m per pixel). All sizes below are in meters.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the back face, on the drill axis. Same length as
the first Pile Bunker from the back to the nose (2.7 m: elbow to the front of the fist), so the same mount
works. Named pieces the weapon script uses (same names as pile_bunker.glb): Stake (empty, parent of the
drill; it moves along +Y and spins about Y), Drum (top lamp glow), NoseRing (collar ring glow). Empties: Nose (front of the
collar), Mount.
"""
import math, os
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "pilebunker_2")
NAME = "pilebunker_2"

## Front face of the collar (the Nose): back to nose length.
NOSE_Y = 2.7
## Drill length in front of the collar and its base radius.
DRILL_LENGTH = 1.65
DRILL_RADIUS = 0.32
## Steps on the drill (steel rings with the dark core between them), then the pointed tip.
DRILL_STEPS = 7
DRILL_TIP = 0.45
## How far the drill core goes back into the collar (it shows when the drill fires).
DRILL_BACK = 0.6
## Half width of the body.
HALF_W = 0.44

MATERIALS = {
    # name: (sRGB color from the picture, roughness, metallic, emission)
    "pb2_olive": ((0.42, 0.44, 0.32), 0.6, 0.3, None),
    "pb2_tan": ((0.69, 0.65, 0.55), 0.6, 0.3, None),
    "pb2_black": ((0.13, 0.13, 0.14), 0.6, 0.4, None),
    "pb2_steel": ((0.43, 0.42, 0.40), 0.35, 0.85, None),
    "pb2_core": ((0.08, 0.08, 0.09), 0.5, 0.6, None),
    "pb2_glow": ((0.6, 0.35, 0.05), 0.5, 0.0, (1.0, 0.55, 0.1)),
}


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, emission = MATERIALS[name]
    color = tuple(srgb_to_linear(c) for c in color)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 0.0
    mat.diffuse_color = (*color, 1.0)
    return mat


def finish(obj, mat, bevel):
    obj.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = True
        obj.data.use_auto_smooth = True
    return obj


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def block(name, mat, x0, x1, y0, y1, z0, z1, chamfer=0.0, bevel=0.015):
    """Box from x0..x1 (side), y0..y1 (along), z0..z1 (up). Chamfer cuts the four edges along Y."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(x1 - x0, y1 - y0, z1 - z0), verts=bm.verts)
    bmesh.ops.translate(bm, vec=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=bm.verts)
    if chamfer > 0.0:
        along = [e for e in bm.edges if abs((e.verts[0].co - e.verts[1].co).normalized().y) > 0.99]
        bmesh.ops.bevel(bm, geom=along, offset=chamfer, segments=1, affect="EDGES")
    return finish(new_object(name, bm), mat, bevel)


def prism(name, mat, y0, y1, r0, r1, z=0.0, sides=8, bevel=0.01):
    """Prism or frustum along +Y from y0 (radius r0) to y1 (radius r1); 8 sides with a flat face on top."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r0, radius2=r1, depth=y1 - y0)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / sides, 3, "Z"))
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, (y0 + y1) / 2, z), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def wedge(name, mat, x0, x1, pts, bevel=0.012):
    """Flat plate across X from x0 to x1, outline pts = [(y, z), ...] in the side view."""
    bm = bmesh.new()
    left = [bm.verts.new((x0, y, z)) for y, z in pts]
    right = [bm.verts.new((x1, y, z)) for y, z in pts]
    n = len(pts)
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([left[i], left[j], right[j], right[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.3
    obj.location = location
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def panel_marks(prefix, x, items):
    """Small dark panel marks on a side face at x: items = [(y0, y1, z0, z1), ...]."""
    out = []
    x0, x1 = (x - 0.005, x + 0.01) if x > 0 else (x - 0.01, x + 0.005)
    for i, (y0, y1, z0, z1) in enumerate(items):
        out.append(block(f"{prefix}{i}", "pb2_black", x0, x1, y0, y1, z0, z1, bevel=0.0))
    return out


def build_rear():
    """Black end cap, the olive grip housing with its slanted front, the black core and the foot."""
    O, K = "pb2_olive", "pb2_black"
    parts = []
    parts.append(block("RearCap", K, -0.4, 0.4, 0.0, 0.14, -0.3, 0.4, chamfer=0.12))
    # Black side pads at the back (front and top views).
    for side, sx in (("L", -1.0), ("R", 1.0)):
        parts.append(block(f"RearPad{side}", K, *sorted((sx * 0.4, sx * (HALF_W + 0.06))), 0.02, 0.42, -0.05, 0.38,
                           chamfer=0.03))
    # Black core under the olive shells (shows in the gaps).
    parts.append(block("RearCore", K, -0.36, 0.36, 0.1, 1.25, -0.3, 0.36, chamfer=0.1))
    # Olive shells, one per side: the side view's outline with the slanted front.
    outline = [(0.12, 0.42), (0.9, 0.42), (1.18, 0.22), (1.18, -0.05), (1.0, -0.12), (0.9, -0.26), (0.12, -0.26)]
    parts.append(wedge("GripShellL", O, -HALF_W, -0.05, outline, bevel=0.03))
    parts.append(wedge("GripShellR", O, 0.05, HALF_W, outline, bevel=0.03))
    parts.append(block("GripSeam", K, -0.05, 0.05, 0.14, 0.92, 0.3, 0.41, bevel=0.0))
    # Shell panel lines (the raised "Z" line of the picture as thin dark strips).
    for side, x in (("L", -HALF_W), ("R", HALF_W)):
        parts += panel_marks(f"GripMark{side}", x, [(0.35, 0.38, -0.15, 0.3), (0.35, 0.8, 0.27, 0.3),
                                                     (0.77, 0.8, 0.05, 0.3), (0.5, 0.62, -0.2, -0.17)])
    # Black foot under the grip.
    parts.append(block("Foot", K, -0.3, 0.3, 0.55, 1.0, -0.47, -0.24, chamfer=0.05))
    return parts


def build_handle():
    """Carry handle on top: two black posts, the bar and a tan sleeve on the bar."""
    K, T = "pb2_black", "pb2_tan"
    parts = []
    parts.append(block("HandlePostBack", K, -0.1, 0.1, 0.55, 0.75, 0.38, 0.66, chamfer=0.03))
    parts.append(block("HandlePostFront", K, -0.1, 0.1, 1.48, 1.66, 0.28, 0.66, chamfer=0.03))
    parts.append(block("HandleBar", K, -0.07, 0.07, 0.7, 1.52, 0.55, 0.66, chamfer=0.02))
    parts.append(block("HandleSleeve", T, -0.08, 0.08, 0.95, 1.22, 0.54, 0.67, chamfer=0.02, bevel=0.008))
    parts.append(block("HandleBase", K, -0.14, 0.14, 0.5, 0.82, 0.36, 0.44, bevel=0.01))
    return parts


def build_body():
    """Tan main body (two top panels with a seam), side marks, the top lamp and the black collar."""
    T, K, L = "pb2_tan", "pb2_black", "pb2_glow"
    parts = []
    parts.append(block("BodyCore", K, -0.4, 0.4, 1.12, 2.22, -0.36, 0.28, chamfer=0.12))
    parts.append(block("BodyShellL", T, -HALF_W, -0.01, 1.18, 2.2, -0.38, 0.3, chamfer=0.1, bevel=0.025))
    parts.append(block("BodyShellR", T, 0.01, HALF_W, 1.18, 2.2, -0.38, 0.3, chamfer=0.1, bevel=0.025))
    parts.append(block("BodySeam", K, -0.012, 0.012, 1.19, 2.19, 0.2, 0.29, bevel=0.0))
    parts.append(block("BodyRing", K, -HALF_W - 0.005, HALF_W + 0.005, 1.66, 1.69, -0.37, 0.29, bevel=0.0))
    for side, x in (("L", -HALF_W), ("R", HALF_W)):
        parts += panel_marks(f"BodyMark{side}", x, [(1.3, 1.55, -0.3, -0.28), (1.8, 2.08, -0.3, -0.16),
                                                     (1.8, 1.83, -0.16, 0.18), (1.25, 1.29, 0.12, 0.2),
                                                     (2.02, 2.08, 0.05, 0.1)])
    # Small orange lamp on the front top of the body (the picture's light at the collar).
    parts.append(block("Drum", L, -0.06, 0.06, 2.12, 2.2, 0.28, 0.31, bevel=0.0))
    # Black octagonal collar around the drill, with a front ring and the glow ring inside.
    parts.append(prism("CollarBack", K, 2.18, 2.34, 0.44, 0.44, bevel=0.03))
    parts.append(prism("Collar", K, 2.34, NOSE_Y - 0.05, 0.4, 0.4, bevel=0.03))
    parts.append(prism("CollarLip", K, NOSE_Y - 0.05, NOSE_Y, 0.4, 0.36, bevel=0.0))
    parts.append(prism("CollarBore", "pb2_core", NOSE_Y - 0.002, NOSE_Y + 0.001, DRILL_RADIUS + 0.04,
                       DRILL_RADIUS + 0.04, bevel=0.0))
    bm = bmesh.new()
    ring = bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=DRILL_RADIUS + 0.045,
                                 radius2=DRILL_RADIUS + 0.045, depth=0.04)
    bmesh.ops.rotate(bm, verts=ring["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    bmesh.ops.translate(bm, vec=(0.0, NOSE_Y - 0.03, 0.0), verts=ring["verts"])
    parts.append(finish(new_object("NoseRing", bm), L, 0.0))
    return parts


def build_drill():
    """The drill under one Stake empty at the collar front (rest); the empty moves along +Y to fire.
    Stepped steel rings (each with a slanted front) over a dark tapered core, then a pointed tip."""
    S, C = "pb2_steel", "pb2_core"
    stake = empty("Stake", (0.0, NOSE_Y, 0.0))
    parts = []
    body = DRILL_LENGTH - DRILL_TIP
    step = body / DRILL_STEPS
    tip_r = 0.07
    # Core from inside the collar to the tip base.
    parts.append(prism("DrillCore", C, -DRILL_BACK, body, DRILL_RADIUS * 0.8, tip_r, bevel=0.0))
    for i in range(DRILL_STEPS):
        t = i / DRILL_STEPS
        r = DRILL_RADIUS + (tip_r + 0.05 - DRILL_RADIUS) * t
        y0 = i * step
        ring_len = step * 0.78
        parts.append(prism(f"DrillRing{i}", S, y0, y0 + ring_len * 0.7, r, r, bevel=0.008))
        parts.append(prism(f"DrillRingFront{i}", S, y0 + ring_len * 0.7, y0 + ring_len, r, r * 0.82, bevel=0.0))
    # Pointed tip (user request 2026-10-31): a cone from the last ring's size to a sharp point.
    last_r = DRILL_RADIUS + (tip_r + 0.05 - DRILL_RADIUS) * (DRILL_STEPS - 1) / DRILL_STEPS
    parts.append(prism("DrillTip", S, body - 0.02, DRILL_LENGTH, last_r * 0.85, 0.0, bevel=0.0))
    for obj in parts:
        obj.parent = stake
    return [stake] + parts


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True)
    tris = 0
    for obj in objects:
        if obj.type == "MESH":
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("%s: %s, %d objects, %d triangles" % (NAME, os.path.basename(path), len(objects), tris))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build_rear() + build_handle() + build_body() + build_drill()
    objects.append(empty("Nose", (0.0, NOSE_Y, 0.0)))
    objects.append(empty("Mount", (0.0, 0.75, 0.0)))
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, NAME + ".blend"))
    export(os.path.join(OUT_DIR, NAME + ".glb"), objects)


main()
