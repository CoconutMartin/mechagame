"""Builds the backpacks (user request 2026-10-31: "replace FCS with backpack; research and write python to build
backpacks in blender"; 3 types from one script, user choice). Research notes: docs/backpack_research.md.

Run (from the project root):
    blender -b --python tools/blender/backpack_build.py               (all types)
    blender -b --python tools/blender/backpack_build.py -- heavy      (one type)
Writes models/backpacks/backpack_<type>.blend and .glb for each type in TYPES (light, medium, heavy: build_pack;
ammo: build_ammo_pack, six canisters the game removes one by one; missile: build_missile_pack, four upright
missile canisters; boost: build_boost_pack, four winged grilles, the boost outlets).
The script starts from an empty file, so hand edits in the .blend are lost when it runs again.

Axes: Blender +Y = forward (Godot -Z), +Z = up. Origin: the Mount, the center of the pack's front face (it lies on
the mech's torso back); the pack goes back along -Y. Named nodes for the game: Mount, Aux1..AuxN (hardpoints, one
per aux slot), Thruster1..N (nozzle exits, pointing down), Lamp (orange glow mesh, emission off).
Each type is a set of numbers in TYPES; the build functions turn them into the same kinds of parts (mount plate,
body, side armor, tanks, nozzles, hardpoints, vents or radiator, antennas, handles, lamp).
"""
import math, os, sys
import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "backpacks")

## Pack types (sizes in m). w, h, d: width, height, depth of the body. slots: aux hardpoints. tank_r / tank_h:
## side tanks (0 = none; "back" puts them on the back face). nozzle_r: nozzle exit radius. antennas: (count,
## length). vent: "grille", "radiator" or "". taper: how much the body narrows toward the back (0 to 1).
TYPES = {
    "light": dict(w=1.1, h=1.5, d=0.6, slots=1, tank_r=0.11, tank_h=0.9, tanks_on="back", nozzle_r=0.13,
                  antennas=(1, 1.5), vent="", taper=0.25),
    "medium": dict(w=1.6, h=1.7, d=0.85, slots=2, tank_r=0.19, tank_h=1.15, tanks_on="side", nozzle_r=0.17,
                   antennas=(2, 0.6), vent="grille", taper=0.12),
    "heavy": dict(w=2.3, h=1.9, d=1.15, slots=3, tank_r=0.24, tank_h=1.3, tanks_on="side", nozzle_r=0.24,
                  antennas=(0, 0.0), vent="radiator", taper=0.05),
    # Ammo Pack (user picture models/guides/backpack_ammo_ref.png, 2026-10-31): six canisters in two columns of
    # three either side of a tan spine; their lids face back, so a used canister slides out backward. Built by
    # build_ammo_pack. can_r / can_len: canister radius and length; can_gap: space between stacked canisters;
    # spine_w: half width of the spine; mount_d: depth of the mount frame in front of the canisters.
    "ammo": dict(kind="ammo", can_r=0.28, can_len=1.05, can_gap=0.03, spine_w=0.27, mount_d=0.4),
    # Missile Pack (user picture models/guides/backpack_missile_ref.png, 2026-10-31): four tall upright canisters
    # (two rows of two) either side of a tan spine, tan straps with black buckles. Built by build_missile_pack.
    # can_r / can_h: canister radius and height; row_y: the two canister rows (y of their centers).
    "missile": dict(kind="missile", can_r=0.3, can_h=1.7, spine_w=0.2, row_y=(-0.45, -1.12)),
    # Boost Pack (user picture models/guides/backpack_boost_ref.png, 2026-10-31): a gunmetal center box with a
    # lower box, and two wings each side (an upper wing wide at the top, a lower wing that flares out at the
    # bottom), each with a louvered grille on the back face (the boost outlets: they glow and blow wind while
    # boosting, BackPackOutlets). Built by
    # build_boost_pack. body_w / body_h / body_d: half width, half height and depth of the center box; wing_x:
    # inner and outer x of the wings; wing_y: front and back y of the wings; top: top of the upper wings; recess:
    # depth of the fin grilles' recess.
    # Depth is about 60% of the picture's, so the pack stays close to the torso.
    "boost": dict(kind="boost", body_w=0.43, body_h=0.55, body_d=0.85, wing_x=(0.55, 1.0), wing_y=(-0.15, -1.0),
                  top=1.07, recess=0.09),
}

MATERIALS = {
    # name: (sRGB color, roughness, metallic, emission): the Sagigilid colors (olive armor, dark olive, black frame).
    "bp_armor": ((0.47, 0.47, 0.31), 0.6, 0.3, None),
    "bp_armor_dark": ((0.30, 0.31, 0.19), 0.6, 0.3, None),
    "bp_frame": ((0.11, 0.11, 0.12), 0.6, 0.4, None),
    "bp_dark": ((0.22, 0.23, 0.24), 0.55, 0.5, None),
    "bp_steel": ((0.55, 0.55, 0.56), 0.3, 0.9, None),
    "bp_glow": ((0.6, 0.35, 0.05), 0.5, 0.0, (1.0, 0.55, 0.1)),
    # Ammo Pack colors from its picture: tan plates, canister olive, dark lids.
    "bp_tan": ((0.72, 0.66, 0.53), 0.6, 0.3, None),
    "bp_can": ((0.33, 0.37, 0.22), 0.5, 0.4, None),
    "bp_can_dark": ((0.22, 0.25, 0.15), 0.5, 0.4, None),
    # Boost Pack colors from its picture: gunmetal armor, a darker gunmetal and light gray louvers.
    "bp_gun": ((0.33, 0.35, 0.39), 0.55, 0.5, None),
    "bp_gun_dark": ((0.22, 0.23, 0.26), 0.55, 0.5, None),
    "bp_slat": ((0.44, 0.44, 0.45), 0.45, 0.6, None),
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


def cyl_z(name, mat, x, y, z0, z1, r0, r1=None, sides=12, bevel=0.0):
    """Cylinder or cone along Z from z0 (radius r0) to z1 (radius r1)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=r0, radius2=r0 if r1 is None else r1,
                          depth=abs(z1 - z0))
    if z1 < z0:
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi, 3, "X"))
    bmesh.ops.translate(bm, vec=(x, y, (z0 + z1) / 2), verts=bm.verts)
    return finish(new_object(name, bm), mat, bevel)


def body_outline(t):
    """Side view (y, z) of the body: a flat front on the mount, a sloped top back edge and a bottom that rises
    toward the front (room for the nozzles)."""
    h, d = t["h"], t["d"]
    return [(-0.1, h / 2), (-d + 0.18, h / 2), (-d, h / 2 - 0.22), (-d, -h / 2 + 0.28), (-d + 0.2, -h / 2),
            (-0.35 * d, -h / 2), (-0.1, -h / 2 + 0.12)]


def tapered_body(name, mat, t, half_w):
    """The body: the side view outline, half_w wide at the front, narrower at the back by taper."""
    pts = body_outline(t)
    d = t["d"]
    bm = bmesh.new()

    def width(y):
        return half_w * (1.0 - t["taper"] * min(max(-y / d, 0.0), 1.0))

    left = [bm.verts.new((-width(y), y, z)) for y, z in pts]
    right = [bm.verts.new((width(y), y, z)) for y, z in pts]
    n = len(pts)
    bm.faces.new(list(reversed(left)))
    bm.faces.new(right)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([left[i], left[j], right[j], right[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, 0.04)


def build_pack(t):
    A, AD, F, K, S, L = "bp_armor", "bp_armor_dark", "bp_frame", "bp_dark", "bp_steel", "bp_glow"
    w, h, d = t["w"], t["h"], t["d"]
    side_tanks = t["tank_r"] > 0 and t["tanks_on"] == "side"
    half_w = w / 2 - (2.2 * t["tank_r"] if side_tanks else 0.0)
    back_w = half_w * (1.0 - t["taper"])
    parts = []
    # Mount plate and two clamps against the torso back.
    parts.append(block("MountPlate", F, -half_w * 0.75, half_w * 0.75, -0.12, 0.0, -h * 0.38, h * 0.38, chamfer=0.06))
    for i, z in enumerate((h * 0.3, -h * 0.3)):
        parts.append(block(f"Clamp{i}", K, -half_w * 0.9, half_w * 0.9, -0.16, -0.02, z - 0.07, z + 0.07, chamfer=0.03))
    # Body, a dark band round its middle, a top cap plate and seams.
    parts.append(tapered_body("Body", A, t, half_w))
    parts.append(block("BodyBand", AD, -half_w - 0.01, half_w + 0.01, -d * 0.62, -d * 0.48, -h / 2 + 0.05,
                       h / 2 - 0.02, bevel=0.01))
    parts.append(block("TopCap", AD, -half_w * 0.8, half_w * 0.8, -d + 0.25, -0.18, h / 2 - 0.02, h / 2 + 0.06,
                       chamfer=0.04, bevel=0.01))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * (half_w - 0.005), sx * (half_w + 0.012)))
        parts.append(block(f"SideSeam{side}", F, x0, x1, -d * 0.3, -d * 0.28, -h / 2 + 0.2, h / 2 - 0.1, bevel=0.0))
        # Side armor plate on the body flank.
        x0, x1 = sorted((sx * (half_w - 0.02), sx * (half_w + 0.06)))
        parts.append(block(f"SidePlate{side}", AD, x0, x1, -d * 0.45, -0.2, -h * 0.28, h * 0.3, chamfer=0.03,
                           bevel=0.01))
    # Back plate with the hardpoints (one per aux slot) in a row across.
    n = t["slots"]
    ## Hardpoints 0.4 m apart; the back plate is wide enough for them.
    plate_w = max(back_w * 0.85, (n - 1) * 0.2 + 0.25)
    parts.append(block("BackPlate", AD, -plate_w, plate_w, -d - 0.05, -d + 0.01, -h * 0.3, h * 0.32,
                       chamfer=0.05, bevel=0.01))
    for i in range(n):
        x = (i - (n - 1) / 2.0) * 0.4
        parts.append(block(f"Hardpoint{i + 1}", F, x - 0.17, x + 0.17, -d - 0.12, -d - 0.04, 0.0, 0.34, chamfer=0.03))
        parts.append(block(f"HardpointRail{i + 1}", S, x - 0.12, x + 0.12, -d - 0.135, -d - 0.115, 0.04, 0.3,
                           bevel=0.0))
        parts.append(empty(f"Aux{i + 1}", (x, -d - 0.135, 0.17)))
    # Lamp on the back plate, under the hardpoints.
    parts.append(block("Lamp", L, -0.12, 0.12, -d - 0.065, -d - 0.045, -0.12, -0.08, bevel=0.0))
    # Tanks: on the sides (with straps and caps) or on the back face (light pack).
    if t["tank_r"] > 0:
        r, th = t["tank_r"], t["tank_h"]
        if side_tanks:
            places = [(sx * (half_w + r + 0.03), -d * 0.5) for sx in (-1.0, 1.0)]
        else:
            places = [(sx * back_w * 0.55, -d - 0.05 - r) for sx in (-1.0, 1.0)]
            places = [(x, y) for x, y in places]
        for i, (x, y) in enumerate(places):
            parts.append(cyl_z(f"Tank{i}", A, x, y, -th / 2, th / 2, r, sides=12, bevel=0.01))
            parts.append(cyl_z(f"TankCapTop{i}", K, x, y, th / 2, th / 2 + 0.06, r * 0.8, r * 0.55, sides=12))
            parts.append(cyl_z(f"TankCapLow{i}", K, x, y, -th / 2, -th / 2 - 0.06, r * 0.8, r * 0.55, sides=12))
            for j, z in enumerate((-th * 0.28, th * 0.28)):
                parts.append(cyl_z(f"TankStrap{i}{j}", F, x, y, z - 0.035, z + 0.035, r + 0.015, sides=12))
            # Strap arm from the tank to the body.
            x_in = sx_in = (half_w if x > 0 else -half_w) if side_tanks else x
            if side_tanks:
                x0, x1 = sorted((x_in, x))
                parts.append(block(f"TankArm{i}", F, x0, x1, y - 0.06, y + 0.06, -0.06, 0.06, bevel=0.0))
    # Nozzles under the body, pointing down, in black housings; Thruster empties at the exits.
    r = t["nozzle_r"]
    for i, sx in enumerate((-1.0, 1.0)):
        x, y = sx * half_w * 0.5, -d * 0.62
        z_top = -h / 2 + 0.05
        parts.append(block(f"NozzleHousing{i}", F, x - r * 1.2, x + r * 1.2, y - r * 1.2, y + r * 1.2, z_top - 0.12,
                           z_top + 0.1, chamfer=0.04))
        parts.append(cyl_z(f"NozzleThroat{i}", K, x, y, z_top - 0.12, z_top - 0.2, r * 0.6, sides=12))
        parts.append(cyl_z(f"Nozzle{i}", S, x, y, z_top - 0.2, z_top - 0.2 - r * 1.6, r * 0.6, r, sides=12))
        th = empty(f"Thruster{i + 1}", (x, y, z_top - 0.2 - r * 1.6))
        th.rotation_euler = (math.pi, 0.0, 0.0)
        parts.append(th)
    # Vents: a grille on the upper back plate or a radiator stack on the top.
    if t["vent"] == "grille":
        for i in range(5):
            z = h * 0.38 + i * 0.045 - 0.1
            parts.append(block(f"Grille{i}", F, -back_w * 0.6, back_w * 0.6, -d - 0.02, -d + 0.03, z, z + 0.02,
                               bevel=0.0))
    elif t["vent"] == "radiator":
        fins = 9
        for i in range(fins):
            x = -half_w * 0.7 + half_w * 1.4 * i / (fins - 1)
            parts.append(wedge(f"Fin{i}", K, x - 0.025, x + 0.025,
                               [(-0.3, h / 2 + 0.05), (-d + 0.3, h / 2 + 0.05), (-d + 0.4, h / 2 + 0.32),
                                (-0.42, h / 2 + 0.32)], bevel=0.0))
        parts.append(block("RadiatorFrame", F, -half_w * 0.78, half_w * 0.78, -d + 0.28, -0.28, h / 2 + 0.03,
                           h / 2 + 0.08, bevel=0.0))
    # Antennas from the top back corners (one: the left corner, as a mast).
    count, length = t["antennas"]
    for i in range(count):
        x = -back_w * 0.6 if count == 1 else (-1.0 + 2.0 * i) * back_w * 0.6
        parts.append(block(f"AntennaBase{i}", F, x - 0.06, x + 0.06, -d + 0.08, -d + 0.2, h / 2 - 0.1, h / 2 + 0.06,
                           bevel=0.0))
        parts.append(cyl_z(f"Antenna{i}", K, x, -d + 0.14, h / 2 + 0.06, h / 2 + 0.06 + length, 0.025, 0.012,
                           sides=6))
    # Handles on the top.
    for i, sx in enumerate((-1.0, 1.0)):
        x = sx * half_w * 0.45
        parts.append(block(f"HandlePostF{i}", F, x - 0.03, x + 0.03, -0.3, -0.25, h / 2 + 0.04, h / 2 + 0.14, bevel=0.0))
        parts.append(block(f"HandlePostB{i}", F, x - 0.03, x + 0.03, -0.55, -0.5, h / 2 + 0.04, h / 2 + 0.14, bevel=0.0))
        parts.append(block(f"HandleBar{i}", F, x - 0.03, x + 0.03, -0.55, -0.25, h / 2 + 0.12, h / 2 + 0.16, bevel=0.0))
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


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
    print("backpack: %s, %d objects, %d triangles" % (os.path.basename(path), len(objects), tris))


def build_ammo_pack(t):
    """The Ammo Pack: a mount frame (dark center panel, tan side blocks), black clamp frames, a tan spine down the
    middle, feet, and six canisters (Canister1..6 empties at their centers: used top row first, left before right).
    """
    T, F, K, C, CD, L = "bp_tan", "bp_frame", "bp_dark", "bp_can", "bp_can_dark", "bp_glow"
    r, length, gap, sw, md = t["can_r"], t["can_len"], t["can_gap"], t["spine_w"], t["mount_d"]
    col_x = sw + 0.05 + r
    rows = [2 * r + gap, 0.0, -(2 * r + gap)]
    top, low = rows[0] + r + 0.04, rows[2] - r - 0.04
    y0, y1 = -md, -md - length
    parts = []
    # Mount side: dark center panel with an inset plate, tan blocks in two columns (three each), black backing.
    parts.append(block("MountPanel", F, -sw - 0.04, sw + 0.04, -md + 0.02, 0.0, low, top, chamfer=0.06))
    parts.append(block("MountPlate", K, -sw * 0.6, sw * 0.6, 0.0, 0.02, low * 0.5, top * 0.5, bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * (sw + 0.06), sx * (col_x + r * 0.55)))
        parts.append(block(f"MountBacking{side}", F, x0, x1, -md + 0.04, -0.06, low, top, chamfer=0.05))
        for i, z in enumerate(rows):
            x0, x1 = sorted((sx * (col_x - r * 0.45), sx * (col_x + r * 0.45)))
            parts.append(block(f"MountBlock{side}{i}", T, x0, x1, -0.12, 0.0, z - r + 0.02, z + r - 0.02, chamfer=0.04,
                               bevel=0.01))
        # Black clamp frames round the canisters' inner ends, and a second one near their middle.
        for j, (ya, yb) in enumerate(((-md + 0.05, -md - 0.16), (y0 - length * 0.55, y0 - length * 0.55 - 0.12))):
            x0, x1 = sorted((sx * (sw + 0.03), sx * (col_x + r + 0.06)))
            parts.append(block(f"Clamp{side}{j}", F, x0, x1, yb, ya, low - 0.02, top + 0.02, chamfer=0.05))
        # Tan cap on the column top and a black foot under it.
        x0, x1 = sorted((sx * (col_x - r * 0.6), sx * (col_x + r * 0.6)))
        parts.append(block(f"TopCap{side}", T, x0, x1, -md - 0.42, -md - 0.02, top + 0.02, top + 0.16, chamfer=0.04,
                           bevel=0.01))
        parts.append(block(f"Foot{side}", F, x0, x1, -md - 0.6, -0.05, low - 0.2, low + 0.02, chamfer=0.05))
    # Spine: a tall tan box down the middle with a lower block, a latch, a seam, a black top cap, a foot and a lamp.
    parts.append(block("Spine", T, -sw, sw, y1 - 0.04, -0.06, low + 0.1, top + 0.08, chamfer=0.07, bevel=0.015))
    parts.append(block("SpineLow", T, -sw * 0.95, sw * 0.95, y1 - 0.06, y1 + 0.2, low - 0.12, low + 0.32, chamfer=0.05,
                       bevel=0.01))
    parts.append(block("SpineSeam", F, -sw - 0.005, sw + 0.005, y1 - 0.045, y1 + 0.25, low + 0.32, low + 0.35, bevel=0.0))
    parts.append(block("Latch", F, -0.1, 0.1, y1 - 0.09, y1 - 0.05, low + 0.05, low + 0.2, bevel=0.0))
    parts.append(block("SpineTop", F, -sw * 0.9, sw * 0.9, -md - 0.3, -0.1, top + 0.08, top + 0.2, chamfer=0.04))
    parts.append(block("SpineFoot", F, -sw * 0.8, sw * 0.8, y1 + 0.1, -0.1, low - 0.2, low + 0.12, chamfer=0.05))
    parts.append(block("Lamp", L, -0.06, 0.06, y1 - 0.06, y1 - 0.045, top - 0.2, top - 0.12, bevel=0.0))
    # Canisters: Canister<n> empties at the centers; each holds a body, a dark lid ring and a lid at the back (-Y)
    # end, and a band near the front end.
    n = 0
    for z in rows:
        for sx in (-1.0, 1.0):
            n += 1
            pivot = empty(f"Canister{n}", (sx * col_x, (y0 + y1) / 2, z))
            half = length / 2
            pieces = [prism(f"CanBody{n}", C, -half, half, r, r, sides=16, bevel=0.0),
                      prism(f"CanLidRing{n}", CD, -half - 0.02, -half + 0.03, r * 0.96, r * 0.96, sides=16, bevel=0.0),
                      prism(f"CanLid{n}", C, -half - 0.035, -half - 0.015, r * 0.78, r * 0.78, sides=16, bevel=0.0),
                      prism(f"CanBand{n}", CD, half - 0.2, half - 0.12, r + 0.012, r + 0.012, sides=16, bevel=0.0)]
            for piece in pieces:
                piece.parent = pivot
            parts.append(pivot)
            parts += pieces
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def build_missile_pack(t):
    """The Missile Pack: four upright canisters in a 2 x 2 block (Canister1..4 empties at their centers: the back
    row first, left before right), a tan spine between the columns with black end blocks and a foot, black cross
    arms between the canisters, tan straps with black buckles round each canister, and a mount plate."""
    T, F, K, C, CD, L = "bp_tan", "bp_frame", "bp_dark", "bp_can", "bp_can_dark", "bp_glow"
    r, h, sw = t["can_r"], t["can_h"], t["spine_w"]
    col_x = sw + 0.04 + r
    front_y, back_y = t["row_y"]
    parts = []
    # Mount plate on the torso back and the spine (tan box between the columns, full depth).
    parts.append(block("MountPlate", F, -col_x - r * 0.4, col_x + r * 0.4, front_y + r - 0.02, 0.0, -h * 0.4,
                       h * 0.4, chamfer=0.06))
    y_end = back_y - r - 0.04
    parts.append(block("Spine", T, -sw, sw, y_end, front_y + r + 0.02, -h / 2 + 0.05, h / 2 - 0.02, chamfer=0.06,
                       bevel=0.015))
    parts.append(block("SpineSeam", F, -sw - 0.005, sw + 0.005, y_end - 0.005, front_y + r, -h * 0.3,
                       -h * 0.3 + 0.03, bevel=0.0))
    parts.append(block("Latch", F, -0.09, 0.09, y_end - 0.04, y_end, -h * 0.4, -h * 0.3, bevel=0.0))
    for i, (ya, yb) in enumerate(((front_y + r - 0.2, front_y + r + 0.05), (y_end - 0.05, y_end + 0.2))):
        parts.append(block(f"SpineEnd{i}", F, -sw * 0.9, sw * 0.9, ya, yb, h / 2 - 0.12, h / 2 + 0.08, chamfer=0.04))
    parts.append(block("SpineFoot", F, -sw * 0.95, sw * 0.95, y_end - 0.05, front_y + r, -h / 2 - 0.25, -h / 2 + 0.08,
                       chamfer=0.06))
    parts.append(block("Lamp", L, -0.05, 0.05, y_end - 0.02, y_end - 0.005, h / 2 - 0.3, h / 2 - 0.22, bevel=0.0))
    # Black cross arms from the spine to the space between each column's two canisters.
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * sw, sx * (col_x + r * 0.2)))
        for j, z in enumerate((h * 0.25, -h * 0.25)):
            parts.append(block(f"Arm{side}{j}", F, x0, x1, back_y + r * 0.4, front_y - r * 0.4, z - 0.07, z + 0.07,
                               chamfer=0.03))
    # Canisters: body, a narrower shoulder and a lid with a ring on top, a tapered foot, two tan straps with a black
    # buckle facing out.
    n = 0
    for y in (back_y, front_y):
        for sx in (-1.0, 1.0):
            n += 1
            pivot = empty(f"Canister{n}", (sx * col_x, y, 0.0))
            half = h / 2
            pieces = [cyl_z(f"CanBody{n}", C, 0.0, 0.0, -half + 0.12, half - 0.18, r, sides=16),
                      cyl_z(f"CanShoulder{n}", C, 0.0, 0.0, half - 0.18, half - 0.06, r, r * 0.82, sides=16),
                      cyl_z(f"CanLid{n}", CD, 0.0, 0.0, half - 0.06, half, r * 0.82, r * 0.78, sides=16),
                      cyl_z(f"CanCap{n}", C, 0.0, 0.0, half, half + 0.04, r * 0.4, sides=16),
                      cyl_z(f"CanFoot{n}", CD, 0.0, 0.0, -half + 0.12, -half, r, r * 0.8, sides=16),
                      cyl_z(f"CanBand{n}", F, 0.0, 0.0, -0.06, 0.06, r + 0.01, sides=16)]
            for j, z in enumerate((h * 0.25, -h * 0.25)):
                pieces.append(cyl_z(f"CanStrap{n}{j}", T, 0.0, 0.0, z - 0.07, z + 0.07, r + 0.02, sides=16))
                # The buckle faces away from the spine.
                pieces.append(block(f"CanBuckle{n}{j}", F, sx * r * 0.75 - 0.09 if sx < 0 else r * 0.75 - 0.0,
                                    sx * r * 0.75 + 0.0 if sx < 0 else r * 0.75 + 0.09, -0.08, 0.08, z - 0.09,
                                    z + 0.09, chamfer=0.02))
            for piece in pieces:
                piece.parent = pivot
            parts.append(pivot)
            parts += pieces
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def loft(name, mat, levels, sx=1.0, bevel=0.012):
    """Solid through cross sections, bottom to top. Each level is (z_in, z_out, x0, x1, y_in, y_out): a quad with
    its mount side edge (y_in) at z_in and its outer edge (y_out) at z_out, so a level can tilt. sx = -1 mirrors."""
    bm = bmesh.new()
    rings = []
    for z_in, z_out, x0, x1, y_in, y_out in levels:
        rings.append([bm.verts.new((sx * x0, y_in, z_in)), bm.verts.new((sx * x1, y_in, z_in)),
                      bm.verts.new((sx * x1, y_out, z_out)), bm.verts.new((sx * x0, y_out, z_out))])
    bm.faces.new(rings[0])
    bm.faces.new(list(reversed(rings[-1])))
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def face_plate(name, mat, pts, face_y, out, back=0.01, sx=1.0, bevel=0.0):
    """Flat plate on a face y = face_y(z): outline pts = [(x, z), ...] seen from behind, from back (into the face)
    to out (out of the face, toward -Y). Follows a tilted face."""
    bm = bmesh.new()
    inner = [bm.verts.new((sx * x, face_y(z) + back, z)) for x, z in pts]
    outer = [bm.verts.new((sx * x, face_y(z) - out, z)) for x, z in pts]
    n = len(pts)
    bm.faces.new(inner)
    bm.faces.new(list(reversed(outer)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([inner[i], inner[j], outer[j], outer[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return finish(new_object(name, bm), mat, bevel)


def poly_x_range(pts, z):
    """Smallest and largest x where the outline pts crosses the height z."""
    xs = []
    n = len(pts)
    for i in range(n):
        (xa, za), (xb, zb) = pts[i], pts[(i + 1) % n]
        if za != zb and min(za, zb) <= z <= max(za, zb):
            xs.append(xa + (xb - xa) * (z - za) / (zb - za))
    return (min(xs), max(xs)) if xs else None


def grille(name, pts, face_y, sx=1.0, pitch=0.07, inset=0.03, back_name="", cut=None, depth=0.0):
    """A louvered grille on a face: a black back plate (named back_name, or name + "Back") in the outline pts and
    light gray slats across it. With cut (the part the face belongs to) and depth, the grille sits in a recess:
    a Boolean cuts the outline depth meters into the part (user request 2026-10-31: "push the grills into the fins
    a bit more"), and the plate and slats sit at the bottom of the recess."""
    F, S = "bp_frame", "bp_slat"
    if cut is not None and depth > 0.0:
        cutter = face_plate(name + "Cutter", F, pts, face_y, 0.1, back=depth, sx=sx)
        cutter.display_type = "WIRE"
        cutter.hide_render = True
        mod = cut.modifiers.new("Recess", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        cut.modifiers.move(len(cut.modifiers) - 1, 0)  # Cut before the bevel, so the recess edges are beveled.
        bottom = face_y
        face_y = lambda z: bottom(z) + depth
    parts = [face_plate(back_name or name + "Back", F, pts, face_y, 0.015, sx=sx)]
    z_low = min(z for _, z in pts) + inset + 0.01
    z_top = max(z for _, z in pts) - inset
    i = 0
    z = z_low
    while z + 0.035 <= z_top:
        lo = poly_x_range(pts, z)
        hi = poly_x_range(pts, z + 0.035)
        if lo and hi:
            x0, x1 = max(lo[0], hi[0]) + inset, min(lo[1], hi[1]) - inset
            if x1 - x0 > 0.04:
                parts.append(face_plate(f"{name}Slat{i}", S, [(x0, z), (x1, z), (x1, z + 0.035), (x0, z + 0.035)],
                                        face_y, 0.035, back=0.0, sx=sx))
                i += 1
        z += pitch
    return parts


def build_boost_pack(t):
    """The Boost Pack: a center box with a lower box, two wings each side (upper wings wide at the top, lower
    wings flaring out to the back at the bottom), black connectors, louvered grilles on the fins' back faces (the boost
    outlets: Outlet1..4 empties, +Z out of the grille; OutletGlow1..4 recess plates), one hardpoint on the box top, orange lamps on the lower
    wings' sides."""
    A, AD, F, K, S = "bp_gun", "bp_gun_dark", "bp_frame", "bp_dark", "bp_steel"
    bw, bh, bd = t["body_w"], t["body_h"], t["body_d"]
    wx0, wx1 = t["wing_x"]
    wy0, wy1 = t["wing_y"]
    top = t["top"]
    parts = []
    # Mount plate on the torso back, the center box and its details on the back face.
    parts.append(block("MountPlate", F, -bw * 0.78, bw * 0.78, -0.08, 0.0, -bh * 0.78, bh * 0.78, chamfer=0.06))
    parts.append(block("Body", A, -bw, bw, -bd, -0.06, -bh, bh, chamfer=0.08, bevel=0.02))
    parts.append(block("BodyPanel", A, -bw + 0.06, bw - 0.06, -bd - 0.025, -bd + 0.01, -bh + 0.16, bh - 0.06,
                       chamfer=0.05, bevel=0.01))
    vent = [(-0.25, bh - 0.27), (0.25, bh - 0.27), (0.25, bh - 0.08), (-0.25, bh - 0.08)]
    parts.append(block("VentFrame", F, -0.28, 0.28, -bd - 0.06, -bd, bh - 0.3, bh - 0.05, chamfer=0.03))
    parts += grille("Vent", vent, lambda z: -bd - 0.05, pitch=0.06, inset=0.02)
    for i, sx in enumerate((-1.0, 1.0)):
        x = sx * 0.16
        parts.append(block(f"Notch{i}", F, x - 0.03, x + 0.03, -bd - 0.04, -bd, -bh + 0.17, -bh + 0.27, bevel=0.0))
        for j, z in enumerate((bh - 0.12, -bh + 0.32)):
            x = sx * (bw - 0.12)
            parts.append(block(f"Bolt{i}{j}", K, x - 0.025, x + 0.025, -bd - 0.04, -bd, z - 0.025, z + 0.025,
                               bevel=0.0))
    # Hardpoint on the box top (aux slot 1).
    parts.append(block("Hardpoint1", F, -0.18, 0.18, -0.62, -0.28, bh - 0.01, bh + 0.06, chamfer=0.03))
    parts.append(block("HardpointRail1", S, -0.12, 0.12, -0.58, -0.32, bh + 0.06, bh + 0.08, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.45, bh + 0.08)))
    # Lower box under the center box, a grille on its back face and a seam.
    lb_z0, lb_z1, lb_y = -bh - 0.5, -bh + 0.05, -bd - 0.05
    parts.append(block("LowerBox", A, -0.28, 0.28, lb_y, -0.12, lb_z0, lb_z1, chamfer=0.05, bevel=0.015))
    low_vent = [(-0.2, lb_z1 - 0.3), (0.2, lb_z1 - 0.3), (0.2, lb_z1 - 0.08), (-0.2, lb_z1 - 0.08)]
    parts.append(block("LowerVentFrame", F, -0.23, 0.23, lb_y - 0.04, lb_y, lb_z1 - 0.33, lb_z1 - 0.05, chamfer=0.03))
    parts += grille("LowerVent", low_vent, lambda z: lb_y - 0.03, pitch=0.06, inset=0.02)
    parts.append(block("LowerSeam", F, -0.285, 0.285, lb_y - 0.005, -0.12, lb_z1 - 0.4, lb_z1 - 0.37, bevel=0.0))
    # Fins (wings), mirrored, the side profile from the picture's SIDE view, same pack size (user requests
    # 2026-10-31: "the fin shape on the dorsal side should be like in the picture"; "more like an inverted K
    # shape"). Seen from the side the fins are the two arms of an inverted K: both start at a root next to the
    # box, the upper fin leans back toward its top and the lower fin leans back toward its bottom, so a V opens
    # between them on the back. Back view: the upper fin is wide at the top and tapers down, the lower fin is
    # narrow at the top and flares out at the bottom.
    up_top_in, up_top_out = top, top - 0.07
    root_in, root_out = -0.28, -0.62
    up_z_bot, up_tip_in, up_tip_out = -0.06, -0.62, -1.06
    low_bottom = -bh - 0.52
    lw_z_top, lw_z_bot = -0.18, low_bottom + 0.08
    low_tip_in, low_tip_out = -0.62, -1.10

    def up_frac(z):
        return (z - up_z_bot) / (up_top_out - up_z_bot)

    def up_in(z):
        return root_in + (up_tip_in - root_in) * up_frac(z)

    def up_face(z):
        return root_out + (up_tip_out - root_out) * up_frac(z)

    def up_outer_x(z):
        return min(wx1, wx0 + 0.28 + (wx1 - wx0 - 0.28) * (z - up_z_bot) / (0.56 - up_z_bot))

    def low_frac(z):
        return (lw_z_top - z) / (lw_z_top - lw_z_bot)

    def low_in(z):
        return root_in + (low_tip_in - root_in) * low_frac(z)

    def low_face(z):
        return root_out + (low_tip_out - root_out) * low_frac(z)

    def outlet_tilt(dy, dz):
        """X rotation that turns an empty's +Z out of a face whose bottom to top direction is (dy, dz)."""
        return math.atan2(dz, dy)

    for side, sx, n in (("L", -1.0, 0), ("R", 1.0, 1)):
        parts.append(loft(f"WingUpper{side}", A, [
            (up_z_bot - 0.05, up_z_bot - 0.05, wx0 + 0.03, wx0 + 0.24, up_in(up_z_bot) - 0.03,
             up_face(up_z_bot) + 0.03),
            (up_z_bot, up_z_bot, wx0, wx0 + 0.28, up_in(up_z_bot), up_face(up_z_bot)),
            (0.40, 0.40, wx0, up_outer_x(0.40), up_in(0.40), up_face(0.40)),
            (0.59, 0.59, wx0, wx1, up_in(0.59), up_face(0.59)),
            (up_top_in - 0.05, up_top_out - 0.05, wx0, wx1, up_in(up_top_in - 0.05), up_face(up_top_out - 0.05)),
            (up_top_in, up_top_out, wx0 + 0.03, wx1 - 0.03, up_in(up_top_in) - 0.04, up_face(up_top_out) + 0.04)],
            sx=sx, bevel=0.02))
        parts.append(loft(f"WingLower{side}", A, [
            (low_bottom, low_bottom, wx0 + 0.03, wx1 - 0.1, low_in(low_bottom) - 0.03, low_face(low_bottom) + 0.03),
            (lw_z_bot, lw_z_bot, wx0, wx1, low_in(lw_z_bot), low_face(lw_z_bot)),
            (lw_z_top, lw_z_top, wx0, wx0 + 0.27, root_in, root_out),
            (lw_z_top + 0.04, lw_z_top + 0.04, wx0 + 0.03, wx0 + 0.23, root_in - 0.03, root_out + 0.03)], sx=sx,
            bevel=0.02))
        # A dark panel line on the upper fin's outer side.
        x0, x1 = sorted((sx * (wx1 - 0.004), sx * (wx1 + 0.008)))
        parts.append(block(f"WingSeam{side}", AD, x0, x1, wy1 + 0.3, wy1 + 0.33, 0.68, up_top_out - 0.1, bevel=0.0))
        # Outlet grilles (user 2026-10-31: "the outlet is on the fins"): the upper one tapers to the bottom with a
        # dark octagonal block, the lower one widens. The black recess plate of each is OutletGlow<n> (lit while
        # boosting, BackPackOutlets).
        up_pts = [(wx0 + 0.08, 0.06), (wx0 + 0.21, 0.06), (wx1 - 0.08, 0.64), (wx1 - 0.08, up_top_out - 0.12),
                  (wx0 + 0.08, up_top_out - 0.12)]
        parts += grille(f"GrilleUp{side}", up_pts, up_face, sx=sx, back_name=f"OutletGlow{n + 1}",
                        cut=bpy.data.objects[f"WingUpper{side}"], depth=t["recess"])
        x0, x1 = sorted((sx * (wx0 + 0.1), sx * (wx0 + 0.27)))
        yb = up_face(0.185)
        parts.append(block(f"GrilleBlock{side}", K, x0, x1, yb - 0.03, yb + t["recess"], 0.1, 0.27, chamfer=0.045,
                           bevel=0.01))
        low_pts = [(wx0 + 0.08, lw_z_bot + 0.06), (wx1 - 0.1, lw_z_bot + 0.06), (wx0 + 0.24, lw_z_top - 0.08),
                   (wx0 + 0.08, lw_z_top - 0.08)]
        parts += grille(f"GrilleLow{side}", low_pts, low_face, sx=sx, back_name=f"OutletGlow{n + 3}",
                        cut=bpy.data.objects[f"WingLower{side}"], depth=t["recess"])
        # Black connectors between the box and the fins.
        for j, (z0, z1) in enumerate(((0.08, 0.32), (-0.44, -0.22))):
            x0, x1 = sorted((sx * (bw - 0.03), sx * (wx0 + 0.03)))
            parts.append(block(f"Connector{side}{j}", F, x0, x1, -0.62, -0.3, z0, z1, chamfer=0.03))
        # Outlet1..2 on the upper grilles, Outlet3..4 on the lower ones: +Z out of the grille (the wind).
        z = 0.5
        th = empty(f"Outlet{n + 1}", (sx * (wx0 + 0.2), up_face(z) - 0.03, z))
        th.rotation_euler = (outlet_tilt(up_tip_out - root_out, up_top_out - up_z_bot), 0.0, 0.0)
        parts.append(th)
        z = (lw_z_top + lw_z_bot) / 2
        th = empty(f"Outlet{n + 3}", (sx * (wx0 + 0.2), low_face(z) - 0.03, z))
        th.rotation_euler = (outlet_tilt(root_out - low_tip_out, lw_z_top - lw_z_bot), 0.0, 0.0)
        parts.append(th)
    # Orange lamps on the lower wings' outer sides near the top (one object, Lamp).
    lamps = []
    for sx in (-1.0, 1.0):
        x0, x1 = sorted((sx * (wx0 + 0.27), sx * (wx0 + 0.33)))
        lamps.append(block("Lamp" if sx > 0 else "LampL", "bp_glow", x0, x1, -0.62, -0.50, -0.42, -0.3, bevel=0.0))
    with bpy.context.temp_override(active_object=lamps[1], selected_editable_objects=lamps):
        bpy.ops.object.join()
    parts.append(lamps[1])
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, t in TYPES.items():
        if args and name not in args:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        builders = {"ammo": build_ammo_pack, "missile": build_missile_pack, "boost": build_boost_pack}
        objects = builders.get(t.get("kind"), build_pack)(t)
        # Radiator fins and handles stay on the heavy and the other packs; a pack with a radiator has no handles.
        if t.get("vent") == "radiator":
            for obj in [o for o in objects if o.name.startswith("Handle")]:
                objects.remove(obj)
                bpy.data.objects.remove(obj)
        path = os.path.join(OUT_DIR, "backpack_%s" % name)
        bpy.ops.wm.save_as_mainfile(filepath=path + ".blend")
        export(path + ".glb", objects)


main()
