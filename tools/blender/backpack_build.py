"""Builds the backpacks (user request 2026-10-31: "replace FCS with backpack; research and write python to build
backpacks in blender"; 3 types from one script, user choice). Research notes: docs/backpack_research.md.

Run (from the project root):
    blender -b --python tools/blender/backpack_build.py               (all types)
    blender -b --python tools/blender/backpack_build.py -- heavy      (one type)
Writes models/backpacks/backpack_<type>.blend and .glb for each type in TYPES (light, medium, heavy: build_pack;
ammo: build_ammo_pack, six canisters the game removes one by one; missile: build_missile_pack, four upright
missile canisters; boost: build_boost_pack, four winged grilles, the boost outlets; quad: build_quad_pack, four thruster pods with
big nozzles; belt: build_belt_pack, an ammo belt for guns; power: build_power_pack,
battery cells and power cables; field: build_field_pack, a box between two handled pods; jet: build_jet_pack, a
box with two big nozzles).
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
    "boost": dict(kind="boost", body_w=0.45, body_h=0.55, body_d=0.88, wing_x=(0.55, 1.0), wing_y=(-0.15, -1.0),
                  top=1.07, recess=0.09),
    # Quad Booster (user picture models/guides/backpack_quad_ref.png, 2026-10-31: "another booster back pack"): four
    # olive octagonal thruster pods in a 2 x 2 block, each with a big dark nozzle on its back end, a tan spine plate
    # between the columns with dark blocks above and below it, a dark core on the torso side. Built by
    # build_quad_pack. pod_x: inner and outer x of a pod column; pod_z: (bottom, top) of the upper pod (the lower
    # pod mirrors it); pod_y: front and back y of a pod body; noz_r / noz_len: nozzle radius and length behind the
    # pod; noz_hole: radius and depth of the nozzle opening; petals: (count, length, closed tilt in degrees) of the
    # jet nozzle petals on each nozzle's rim (user request 2026-10-31: "the nozzles open and close when boosting and
    # when not, like in jet fighters"). Depth is about 75% of the picture's.
    "quad": dict(kind="quad", pod_x=(0.25, 1.03), pod_z=(0.04, 1.06), pod_y=(-0.08, -0.8), noz_r=0.32,
                 noz_len=0.2, noz_hole=(0.25, 0.1), petals=(10, 0.16, 22.0)),
    # Belt Pack (user picture models/guides/backpack_belt_ref.png, 2026-10-31: "make the next backpack primarily as
    # ballistic support"): a dark frame box with a carry handle, an ammo belt of 16 rounds down the middle of its
    # back face between two dark rails, olive armor blocks either side of the belt, olive side boxes (the lower one
    # with a yellow stripe). Built by build_belt_pack. w / h / d: half width, half height and depth of the frame
    # box; rounds: rounds on the belt; per_canister: rounds per canister (Canister1..N, the top pair first).
    "belt": dict(kind="belt", w=0.46, h=0.92, d=0.86, rounds=16, per_canister=2),
    # Power Pack (user picture models/guides/backpack_power_ref.png, 2026-10-31: "another backpack for energy
    # support"): a gunmetal center stack (top box, a radiator block with a louvered grille in a recess, a bottom
    # block), tall towers on the upper sides, battery cells with terminals on the lower sides, orange power cables
    # from the towers down to the stack and out to the cell terminals. Built by build_power_pack. Sizes in m:
    # body_w: half width of the stack; tower_x / cell_x: inner and outer x; cable_r: cable radius.
    # Field Pack (user picture models/guides/backpack_field_ref.png, 2026-10-31; "build, beautify, add a bit more
    # body"): a sand center box with a recessed grille between two tall octagonal side pods with carry handles over
    # their tops and down their outer sides, dark feet. Built by build_field_pack. box_w: half width of the box;
    # pod_x: inner and outer x of a pod; h: half height of a pod; d: depth.
    "field": dict(kind="field", box_w=0.42, pod_x=(0.44, 1.0), h=0.82, d=0.92),
    # Jet Pack (user picture models/guides/backpack_jet_ref.png, 2026-10-31): a sand box of three columns (raised
    # blocks with sensor windows on the side columns' tops), two big nozzles under it pointing down and back. Built
    # by build_jet_pack. col_x: x where the side columns start and end; h: half height; d: depth; noz: (x, radius,
    # length, tilt back from straight down in degrees).
    "jet": dict(kind="jet", col_x=(0.38, 0.98), h=0.68, d=0.9, noz=(0.55, 0.26, 0.4, 45.0)),
    "power": dict(kind="power", body_w=0.32, tower_x=(0.36, 0.68), cell_x=(0.48, 0.9), d=0.95, cable_r=0.045),
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
    "bp_energy": ((0.45, 0.8, 1.0), 0.5, 0.0, (0.45, 0.8, 1.0)),
    # Belt Pack: brass round tips and bands, a yellow stripe.
    "bp_brass": ((0.85, 0.62, 0.22), 0.35, 0.9, None),
    "bp_yellow": ((0.92, 0.68, 0.12), 0.5, 0.1, None),
    # Power Pack: orange cables, copper bolts.
    "bp_cable": ((0.88, 0.3, 0.12), 0.45, 0.1, None),
    "bp_copper": ((0.72, 0.43, 0.2), 0.35, 0.9, None),
    # Field Pack and Jet Pack: sand armor from their pictures, a darker sand for insets.
    "bp_sand": ((0.62, 0.57, 0.44), 0.6, 0.3, None),
    "bp_sand_dark": ((0.5, 0.46, 0.35), 0.6, 0.3, None),
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
    # More body (user 2026-10-31: "the canister backpack as well": beautify, add body): a raised tan plate on the
    # spine's back face with a seam, bolts and vent slots, dark rails on the spine's back edges, tan rack bars on
    # the outer sides of the columns between the clamps, a dark top rail joining the column caps. The lamp sits on
    # the plate.
    T_ = T
    parts.append(block("SpinePlate", T_, -sw + 0.06, sw - 0.06, y1 - 0.09, y1 - 0.03, low + 0.42, top - 0.04,
                       chamfer=0.05, bevel=0.01))
    parts.append(block("SpinePlateSeam", F, -sw + 0.055, sw - 0.055, y1 - 0.095, y1 - 0.03, top - 0.42, top - 0.4,
                       bevel=0.0))
    for i, (x, z) in enumerate(((-sw + 0.1, top - 0.1), (sw - 0.1, top - 0.1), (-sw + 0.1, low + 0.48),
                                (sw - 0.1, low + 0.48))):
        bolt = prism(f"SpineBolt{i}", "bp_steel", y1 - 0.105, y1 - 0.085, 0.018, 0.018, z=z, sides=6, bevel=0.0)
        bolt.location.x = x
        parts.append(bolt)
    for j in range(4):
        z = top - 0.52 - j * 0.07
        parts.append(block(f"SpineVent{j}", F, -sw + 0.11, sw - 0.11, y1 - 0.1, y1 - 0.085, z - 0.02, z + 0.02,
                           bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        xa, xb = sorted((sx * (sw - 0.035), sx * (sw + 0.01)))
        parts.append(block(f"SpineRail{side}", F, xa, xb, y1 - 0.07, y1 + 0.12, low + 0.1, top + 0.06, chamfer=0.01,
                           bevel=0.0))
        for j, z in enumerate((r + gap / 2, -r - gap / 2)):
            xa, xb = sorted((sx * (col_x + r - 0.02), sx * (col_x + r + 0.07)))
            parts.append(block(f"RackBar{side}{j}", T_, xa, xb, y0 - length * 0.55 + 0.02, -md - 0.16, z - 0.035,
                               z + 0.035, chamfer=0.015, bevel=0.005))
    parts.append(block("TopRail", F, -col_x, col_x, -md - 0.36, -md - 0.08, top + 0.14, top + 0.19, chamfer=0.02,
                       bevel=0.0))
    parts.append(block("Lamp", L, -0.06, 0.06, y1 - 0.105, y1 - 0.09, top - 0.3, top - 0.22, bevel=0.0))
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
                      prism(f"CanBand{n}", CD, half - 0.2, half - 0.12, r + 0.012, r + 0.012, sides=16, bevel=0.0),
                      # Lid detail: a raised boss and a T handle (the user's beautify request), a second band near
                      # the lid and a tan stencil ring.
                      prism(f"CanBoss{n}", CD, -half - 0.06, -half - 0.03, r * 0.3, r * 0.3, sides=12, bevel=0.0),
                      block(f"CanHandle{n}", CD, -r * 0.5, r * 0.5, -half - 0.1, -half - 0.055, -0.03, 0.03,
                            chamfer=0.01, bevel=0.0),
                      prism(f"CanBandLid{n}", CD, -half + 0.1, -half + 0.16, r + 0.01, r + 0.01, sides=16, bevel=0.0),
                      prism(f"CanStencil{n}", T, -0.03, 0.03, r + 0.006, r + 0.006, sides=16, bevel=0.0)]
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
    # More body (user 2026-10-31: beautify, add body): a raised tan plate on the spine's back face with bolts and
    # vents, dark edge rails, a dark base tray under the canisters, dark rack posts on the outer sides joined to the
    # cross arms. The lamp sits on the plate.
    parts.append(block("SpinePlate", T, -sw + 0.05, sw - 0.05, y_end - 0.05, y_end + 0.01, -h * 0.22, h / 2 - 0.16,
                       chamfer=0.04, bevel=0.01))
    for i, (x, z) in enumerate(((-sw + 0.09, h / 2 - 0.22), (sw - 0.09, h / 2 - 0.22), (-sw + 0.09, -h * 0.18),
                                (sw - 0.09, -h * 0.18))):
        bolt = prism(f"SpineBolt{i}", "bp_steel", y_end - 0.065, y_end - 0.045, 0.016, 0.016, z=z, sides=6,
                     bevel=0.0)
        bolt.location.x = x
        parts.append(bolt)
    for j in range(3):
        z = h / 2 - 0.42 - j * 0.07
        parts.append(block(f"SpineVent{j}", F, -sw + 0.09, sw - 0.09, y_end - 0.06, y_end - 0.045, z - 0.02,
                           z + 0.02, bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        xa, xb = sorted((sx * (sw - 0.03), sx * (sw + 0.01)))
        parts.append(block(f"SpineRail{side}", F, xa, xb, y_end - 0.03, y_end + 0.15, -h / 2 + 0.05, h / 2 - 0.02,
                           bevel=0.0))
        # Rack post on the outer side between the two canisters, joined to the cross arms by bars.
        yp = (front_y + back_y) / 2
        xa, xb = sorted((sx * (col_x + r * 0.55), sx * (col_x + r * 0.55 + 0.08)))
        parts.append(block(f"RackPost{side}", F, xa, xb, yp - 0.07, yp + 0.07, -h / 2 - 0.1, h / 2 - 0.16,
                           chamfer=0.025, bevel=0.0))
        for j, z in enumerate((h * 0.25, -h * 0.25)):
            xa, xb = sorted((sx * (col_x + r * 0.15), sx * (col_x + r * 0.6)))
            parts.append(block(f"RackBar{side}{j}", F, xa, xb, yp - 0.05, yp + 0.05, z - 0.05, z + 0.05, bevel=0.0))
    parts.append(block("BaseTray", F, -col_x - r * 0.75, col_x + r * 0.75, back_y - r * 0.8, front_y + r * 0.8,
                       -h / 2 - 0.12, -h / 2 - 0.03, chamfer=0.05, bevel=0.0))
    parts.append(block("Lamp", L, -0.05, 0.05, y_end - 0.065, y_end - 0.05, h / 2 - 0.34, h / 2 - 0.26, bevel=0.0))
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
                      cyl_z(f"CanBand{n}", F, 0.0, 0.0, -0.06, 0.06, r + 0.01, sides=16),
                      # Nose detail and a yellow warning ring (the user's beautify request).
                      cyl_z(f"CanNose{n}", CD, 0.0, 0.0, half + 0.04, half + 0.1, r * 0.28, r * 0.12, sides=12),
                      cyl_z(f"CanWarn{n}", "bp_yellow", 0.0, 0.0, half - 0.3, half - 0.25, r + 0.008, sides=16)]
            # Two raised ribs along the canister, facing away from the spine.
            for j, ry in enumerate((-0.09, 0.09)):
                xa, xb = sorted((sx * (r - 0.02), sx * (r + 0.018)))
                pieces.append(block(f"CanRib{n}{j}", CD, xa, xb, ry - 0.02, ry + 0.02, -half + 0.2, half - 0.34,
                                    bevel=0.0))
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


def grille_flaps(name, pts, face_y, depth, sx, pitch, inset, z_from=-99.0):
    """Louver flaps across a recessed grille (user request 2026-10-31: "turn the grilles into flaps that open when
    boosting and close when not boosting"). Each flap is its own object <name><i>, origin on its hinge (the flap's
    middle line, depth * 0.3 inside the face, so a flap open at a right angle clears the back plate), local X = the
    hinge along the fin's width, local Z = up along the face, local -Y = out of the face. Closed (as built) the flaps lie in the face plane and overlap a little, so
    they cover the recess; the game turns them about local X to open them (BackPackFlaps)."""
    height, thick = pitch + 0.012, 0.014
    z_low = max(min(z for _, z in pts) + 0.01, z_from)
    z_top = max(z for _, z in pts) - 0.01
    parts = []
    i = 0
    z = z_low + height / 2
    while z + height / 2 <= z_top + 0.005:
        lo = poly_x_range(pts, z - height / 2)
        hi = poly_x_range(pts, z + height / 2)
        if lo and hi:
            x0, x1 = max(lo[0], hi[0]) + 0.01, min(lo[1], hi[1]) - 0.01
            if x1 - x0 > 0.04:
                i += 1
                dy = face_y(z + 0.05) - face_y(z - 0.05)
                tilt = math.atan2(-dy, 0.1)
                bm = bmesh.new()
                bmesh.ops.create_cube(bm, size=1.0)
                bmesh.ops.scale(bm, vec=(x1 - x0, thick, height), verts=bm.verts)
                obj = new_object(f"{name}{i}", bm)
                obj.location = (sx * (x0 + x1) / 2, face_y(z) + depth * 0.3, z)
                obj.rotation_euler = (tilt, 0.0, 0.0)
                parts.append(finish(obj, "bp_slat", 0.004))
        z += pitch
    return parts


def grille(name, pts, face_y, sx=1.0, pitch=0.07, inset=0.03, back_name="", cut=None, depth=0.0, flaps="", flaps_from=-99.0):
    """A louvered grille on a face: a black back plate (named back_name, or name + "Back") in the outline pts and
    light gray slats across it. With cut (the part the face belongs to) and depth, the grille sits in a recess:
    a Boolean cuts the outline depth meters into the part (user request 2026-10-31: "push the grills into the fins
    a bit more"), and the plate and slats sit at the bottom of the recess. flaps (a name prefix, needs a recess):
    louver flaps that the game opens (grille_flaps) take the place of the fixed slats."""
    F, S = "bp_frame", "bp_slat"
    bottom = face_y
    if cut is not None and depth > 0.0:
        cutter = face_plate(name + "Cutter", F, pts, face_y, 0.1, back=depth, sx=sx)
        cutter.display_type = "WIRE"
        cutter.hide_render = True
        mod = cut.modifiers.new("Recess", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        cut.modifiers.move(len(cut.modifiers) - 1, 0)  # Cut before the bevel, so the recess edges are beveled.
        face_y = lambda z: bottom(z) + depth
    parts = [face_plate(back_name or name + "Back", F, pts, face_y, 0.015, sx=sx)]
    if flaps:
        return parts + grille_flaps(flaps, pts, bottom, depth, sx, pitch, inset, flaps_from)
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
    # Third bar above the two vent slats: the boost energy light (user request 2026-10-31; BackPackEnergyBar
    # lights it light blue at full energy, dimmer and grayer toward empty).
    parts.append(face_plate("EnergyBar", "bp_energy", [(-0.23, bh - 0.12), (0.23, bh - 0.12), (0.23, bh - 0.085),
                                                       (-0.23, bh - 0.085)], lambda z: -bd - 0.05, 0.035, back=0.0))
    for i, sx in enumerate((-1.0, 1.0)):
        x = sx * 0.16
        parts.append(block(f"Notch{i}", F, x - 0.03, x + 0.03, -bd - 0.04, -bd, -bh + 0.17, -bh + 0.27, bevel=0.0))
        for j, z in enumerate((bh - 0.12, -bh + 0.32)):
            x = sx * (bw - 0.12)
            parts.append(block(f"Bolt{i}{j}", K, x - 0.025, x + 0.025, -bd - 0.04, -bd, z - 0.025, z + 0.025,
                               bevel=0.0))
    # Hardpoint on the box top (aux slot 1).
    # More body (user 2026-10-31: "for the very first backpack, beautify it and add a bit more body as well"): a
    # dark top cap with the hardpoint, raised plates on the box sides, a keel rib down the back face, dark corner
    # guards.
    parts.append(block("BodyCap", AD, -bw + 0.04, bw - 0.04, -bd + 0.08, -0.12, bh - 0.02, bh + 0.06, chamfer=0.04,
                       bevel=0.01))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        xa, xb = sorted((sx * (bw - 0.01), sx * (bw + 0.035)))
        parts.append(block(f"BodySidePlate{side}", A, xa, xb, -bd + 0.12, -0.2, -bh + 0.1, bh - 0.12, chamfer=0.05,
                           bevel=0.01))
        for j, z in enumerate((bh - 0.02, -bh + 0.02)):
            xa, xb = sorted((sx * (bw - 0.1), sx * (bw + 0.015)))
            za, zb = (z - 0.1, z + 0.02) if j == 0 else (z - 0.02, z + 0.1)
            parts.append(block(f"CornerGuard{side}{j}", F, xa, xb, -bd - 0.04, -bd + 0.14, za, zb, chamfer=0.03,
                               bevel=0.0))
    parts.append(block("BodyKeel", AD, -0.06, 0.06, -bd - 0.06, -bd, -bh + 0.32, bh - 0.34, chamfer=0.02, bevel=0.0))
    parts.append(block("Hardpoint1", F, -0.18, 0.18, -0.62, -0.28, bh + 0.06, bh + 0.11, chamfer=0.03))
    parts.append(block("HardpointRail1", S, -0.12, 0.12, -0.58, -0.32, bh + 0.11, bh + 0.13, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.45, bh + 0.13)))
    # Lower box under the center box, a grille on its back face and a seam.
    lb_z0, lb_z1, lb_y = -bh - 0.5, -bh + 0.05, -bd - 0.05
    parts.append(block("LowerBox", A, -0.28, 0.28, lb_y, -0.12, lb_z0, lb_z1, chamfer=0.05, bevel=0.015))
    low_vent = [(-0.2, lb_z1 - 0.3), (0.2, lb_z1 - 0.3), (0.2, lb_z1 - 0.08), (-0.2, lb_z1 - 0.08)]
    parts.append(block("LowerVentFrame", F, -0.23, 0.23, lb_y - 0.04, lb_y, lb_z1 - 0.33, lb_z1 - 0.05, chamfer=0.03))
    parts += grille("LowerVent", low_vent, lambda z: lb_y - 0.03, pitch=0.06, inset=0.02)
    parts.append(block("LowerSeam", F, -0.285, 0.285, lb_y - 0.005, -0.12, lb_z1 - 0.4, lb_z1 - 0.37, bevel=0.0))
    parts.append(block("LowerFoot", F, -0.32, 0.32, lb_y + 0.04, -0.14, lb_z0 - 0.06, lb_z0 + 0.04, chamfer=0.03,
                       bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        xa, xb = sorted((sx * 0.275, sx * 0.305))
        parts.append(block(f"LowerSidePlate{side}", AD, xa, xb, lb_y + 0.1, -0.2, lb_z0 + 0.08, lb_z1 - 0.08,
                           chamfer=0.03, bevel=0.0))
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
                        cut=bpy.data.objects[f"WingUpper{side}"], depth=t["recess"],
                        flaps=f"OutletFlap{n + 1}_", flaps_from=0.29)  # The dark block fills the bottom.
        x0, x1 = sorted((sx * (wx0 + 0.1), sx * (wx0 + 0.27)))
        yb = up_face(0.185)
        parts.append(block(f"GrilleBlock{side}", K, x0, x1, yb - 0.03, yb + t["recess"], 0.1, 0.27, chamfer=0.045,
                           bevel=0.01))
        low_pts = [(wx0 + 0.08, lw_z_bot + 0.06), (wx1 - 0.1, lw_z_bot + 0.06), (wx0 + 0.24, lw_z_top - 0.08),
                   (wx0 + 0.08, lw_z_top - 0.08)]
        parts += grille(f"GrilleLow{side}", low_pts, low_face, sx=sx, back_name=f"OutletGlow{n + 3}",
                        cut=bpy.data.objects[f"WingLower{side}"], depth=t["recess"],
                        flaps=f"OutletFlap{n + 3}_")
        # Fin trims: a dark rib along each fin's inner edge on the back face, an armor plate on the upper fin's outer
        # side, a dark cap on the upper fin's top and on the lower fin's foot.
        parts.append(face_plate(f"FinRibUp{side}", AD, [(wx0 + 0.015, up_z_bot + 0.03), (wx0 + 0.065, up_z_bot + 0.03),
                                                        (wx0 + 0.065, up_top_out - 0.05),
                                                        (wx0 + 0.015, up_top_out - 0.05)], up_face, 0.025, sx=sx))
        parts.append(face_plate(f"FinRibLow{side}", AD, [(wx0 + 0.015, lw_z_bot + 0.03), (wx0 + 0.065, lw_z_bot + 0.03),
                                                         (wx0 + 0.065, lw_z_top - 0.03),
                                                         (wx0 + 0.015, lw_z_top - 0.03)], low_face, 0.025, sx=sx))
        parts.append(loft(f"FinSidePlate{side}", A, [
            (0.66, 0.66, wx1 - 0.01, wx1 + 0.03, up_in(0.66) - 0.07, up_face(0.66) + 0.09),
            (up_top_out - 0.14, up_top_out - 0.14, wx1 - 0.01, wx1 + 0.03, up_in(up_top_out - 0.14) - 0.07,
             up_face(up_top_out - 0.14) + 0.09)], sx=sx, bevel=0.01))
        parts.append(loft(f"FinCap{side}", K, [
            (up_top_in - 0.03, up_top_out - 0.03, wx0 + 0.05, wx1 - 0.05, up_in(up_top_in) - 0.07,
             up_face(up_top_out) + 0.07),
            (up_top_in + 0.02, up_top_out + 0.02, wx0 + 0.08, wx1 - 0.08, up_in(up_top_in) - 0.1,
             up_face(up_top_out) + 0.1)], sx=sx, bevel=0.008))
        parts.append(loft(f"FinFoot{side}", K, [
            (low_bottom - 0.04, low_bottom - 0.04, wx0 + 0.07, wx1 - 0.16, low_in(low_bottom) - 0.07,
             low_face(low_bottom) + 0.08),
            (low_bottom + 0.02, low_bottom + 0.02, wx0 + 0.05, wx1 - 0.13, low_in(low_bottom) - 0.05,
             low_face(low_bottom) + 0.06)], sx=sx, bevel=0.008))
        # Hydraulic struts from the box sides to the fins: a dark sleeve and a steel rod.
        for k, (z, y) in enumerate(((0.2, -0.62), (-0.36, -0.6))):
            x_box, x_fin = bw + 0.03, wx0 + 0.02
            sleeve = cyl_z(f"StrutSleeve{side}{k}", K, 0.0, 0.0, 0.0, (x_fin - x_box) * 0.55, 0.045, sides=10)
            rod = cyl_z(f"StrutRod{side}{k}", S, 0.0, 0.0, 0.0, x_fin - x_box, 0.024, sides=8)
            for obj in (sleeve, rod):
                obj.rotation_euler = (0.0, sx * math.pi / 2, 0.0)
                obj.location = (sx * x_box, y, z)
                parts.append(obj)
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


def nozzle_petal(name, mat, center, y_hinge, phi, r_hinge, length, tilt, count, thick=0.02):
    """One jet nozzle petal: a plate hinged on the nozzle rim (radius r_hinge round center = (x, z), at y_hinge)
    that points back (-Y) and tilts in toward the axis by tilt (closed). Origin on the hinge; local X = the hinge
    (along the rim), local Z = along the petal to its tip, local -Y = out from the axis, so a turn about local X
    swings the tip out (BackPackFlaps opens it). The petals overlap a little when open."""
    axis = Vector((0.0, -1.0, 0.0))
    out = Vector((math.cos(phi), 0.0, math.sin(phi)))
    along = axis * math.cos(tilt) - out * math.sin(tilt)
    normal = out * math.cos(tilt) + axis * math.sin(tilt)
    y_axis = -normal
    x_axis = y_axis.cross(along)
    w0 = 2.0 * math.pi * r_hinge / count * 1.06
    w1 = 2.0 * math.pi * (r_hinge + 0.03) / count * 1.02
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in ((-w0 / 2, 0.0, 0.0), (w0 / 2, 0.0, 0.0), (w1 / 2, 0.0, length),
                                    (-w1 / 2, 0.0, length), (-w0 / 2, thick, 0.0), (w0 / 2, thick, 0.0),
                                    (w1 / 2, thick, length), (-w1 / 2, thick, length))]
    for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = new_object(name, bm)
    hinge = Vector((center[0], y_hinge, center[1])) + out * r_hinge
    m = Matrix((x_axis, y_axis, along)).transposed().to_4x4()
    m.translation = hinge
    obj.matrix_world = m
    return finish(obj, mat, 0.0)


def build_quad_pack(t):
    """The Quad Booster: four octagonal thruster pods (chamfered boxes along Y) with dark bands, a big nozzle on
    each pod's back end (a ring with an opening cut in it, the OutletGlow<n> disc at the bottom, an inner ring, ten
    jet nozzle petals NozzlePetal<n>_<k> on the rim and an Outlet<n> empty past them, +Z out of the nozzle), a tan spine plate on the back between the columns with
    dark blocks above and below and the EnergyBar light near its foot, a dark core and mount plate on the torso side, and one hardpoint on the spine's
    top block."""
    A, AD, F, K, T, S = "bp_armor", "bp_armor_dark", "bp_frame", "bp_dark", "bp_tan", "bp_steel"
    px0, px1 = t["pod_x"]
    pz0, pz1 = t["pod_z"]
    py0, py1 = t["pod_y"]
    r, length = t["noz_r"], t["noz_len"]
    hole_r, hole_d = t["noz_hole"]
    cx = (px0 + px1) / 2
    parts = []
    # Torso side: mount plate and the dark core between the columns.
    parts.append(block("MountPlate", F, -0.36, 0.36, -0.08, 0.0, -0.8, 0.8, chamfer=0.06))
    parts.append(block("Core", K, -0.3, 0.3, -0.42, -0.06, -0.92, 0.92, chamfer=0.08, bevel=0.015))
    for i, z in enumerate((0.6, -0.6)):
        parts.append(block(f"CoreBolt{i}", F, -0.04, 0.04, -0.09, -0.07, z - 0.04, z + 0.04, bevel=0.0))
    # Spine (user request 2026-10-31: "add a bit more body to the center part, as well as the energy indicator;
    # make it beautiful"): a tan keel between the columns, octagonal from the back and as deep as the pods; a raised
    # armor plate on its back face with a center seam and bolts; louvered side vents; dark caps above (with the
    # hardpoint) and below; the energy gauge in a dark bezel near its foot.
    sy0, sy1 = -0.34, py1 - 0.26
    parts.append(loft("Spine", T, [
        (-0.86, -0.86, -0.17, 0.17, sy0 - 0.02, sy1 + 0.08),
        (-0.78, -0.78, -0.24, 0.24, sy0, sy1),
        (0.5, 0.5, -0.24, 0.24, sy0, sy1),
        (0.62, 0.62, -0.17, 0.17, sy0 - 0.02, sy1 + 0.08)], bevel=0.02))
    parts.append(block("SpineArmor", T, -0.17, 0.17, sy1 - 0.05, sy1 + 0.02, -0.5, 0.4, chamfer=0.06, bevel=0.012))
    parts.append(block("SpineArmorTop", T, -0.12, 0.12, sy1 - 0.08, sy1 - 0.03, 0.08, 0.34, chamfer=0.04,
                       bevel=0.01))
    parts.append(block("SpineSeam", F, -0.006, 0.006, sy1 - 0.055, sy1 - 0.04, -0.46, 0.04, bevel=0.0))
    parts.append(block("SpineBand", F, -0.175, 0.175, sy1 - 0.055, sy1 + 0.01, 0.04, 0.07, bevel=0.0))
    for i, (x, z) in enumerate(((-0.12, 0.36), (0.12, 0.36), (-0.12, -0.44), (0.12, -0.44))):
        parts.append(prism(f"SpineBolt{i}", S, sy1 - 0.065, sy1 - 0.04, 0.018, 0.018, z=z, sides=6, bevel=0.0))
        parts[-1].location.x = x
    for side, sx in (("L", -1.0), ("R", 1.0)):
        for j in range(4):
            z = 0.28 - j * 0.09
            xa, xb = sorted((sx * 0.235, sx * 0.255))
            parts.append(block(f"SpineVent{side}{j}", F, xa, xb, sy1 + 0.12, sy0 - 0.12, z - 0.025, z + 0.025,
                               bevel=0.0))
    parts.append(block("SpineTop", K, -0.2, 0.2, sy1 + 0.06, sy0 + 0.02, 0.6, 0.8, chamfer=0.06, bevel=0.012))
    parts.append(block("SpineLow", K, -0.21, 0.21, sy1 + 0.04, sy0 + 0.04, -1.04, -0.84, chamfer=0.06, bevel=0.012))
    parts.append(block("Hardpoint1", F, -0.13, 0.13, -0.68, -0.4, 0.8, 0.84, bevel=0.0))
    parts.append(block("HardpointRail1", S, -0.09, 0.09, -0.65, -0.43, 0.84, 0.86, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.54, 0.86)))
    # Energy gauge: a dark bezel proud of the spine, a steel trim, end caps, and the EnergyBar light inside it, one
    # solid bar (user 2026-10-31: "remove the segments"; BackPackEnergyBar colors it).
    gz0, gz1 = -0.76, -0.58
    parts.append(block("GaugeBezel", F, -0.19, 0.19, sy1 - 0.07, sy1 + 0.02, gz0, gz1, chamfer=0.04, bevel=0.01))
    parts.append(block("GaugeTrim", S, -0.155, 0.155, sy1 - 0.075, sy1 - 0.06, gz0 + 0.03, gz1 - 0.03, chamfer=0.02,
                       bevel=0.0))
    parts.append(block("GaugeWell", F, -0.145, 0.145, sy1 - 0.08, sy1 - 0.06, gz0 + 0.04, gz1 - 0.04, bevel=0.0))
    for i, sx in enumerate((-1.0, 1.0)):
        xa, xb = sorted((sx * 0.155, sx * 0.185))
        parts.append(block(f"GaugeCap{i}", K, xa, xb, sy1 - 0.09, sy1 - 0.06, gz0 + 0.02, gz1 - 0.02, chamfer=0.01,
                           bevel=0.0))
    parts.append(block("EnergyBar", "bp_energy", -0.135, 0.135, sy1 - 0.085, sy1 - 0.07, gz0 + 0.055, gz1 - 0.055,
                       chamfer=0.012, bevel=0.0))
    n = 0
    for row, (z0, z1) in (("U", (pz0, pz1)), ("L", (-pz1, -pz0))):
        zc = (z0 + z1) / 2
        for side, sx in (("L", -1.0), ("R", 1.0)):
            n += 1
            x0, x1 = sorted((sx * px0, sx * px1))
            name = f"{row}{side}"
            # Pod body (octagonal: the chamfer cuts the four edges along Y), a dark band round its middle, a
            # raised panel on its outer side and a dark clamp on its top or bottom.
            parts.append(block(f"Pod{name}", A, x0, x1, py1, py0, z0, z1, chamfer=0.17, bevel=0.02))
            parts.append(block(f"PodBand{name}", AD, x0 - 0.015, x1 + 0.015, py1 * 0.62, py1 * 0.48, z0 - 0.015,
                               z1 + 0.015, chamfer=0.18, bevel=0.01))
            xa, xb = sorted((sx * (px1 - 0.01), sx * (px1 + 0.02)))
            parts.append(block(f"PodPanel{name}", A, xa, xb, py1 * 0.9, py1 * 0.55, zc - 0.22, zc + 0.15,
                               chamfer=0.03, bevel=0.008))
            zc_clamp = z1 if row == "U" else z0
            za, zb = (zc_clamp - 0.01, zc_clamp + 0.05) if row == "U" else (zc_clamp - 0.05, zc_clamp + 0.01)
            parts.append(block(f"PodClamp{name}", K, sx * cx - 0.2, sx * cx + 0.2, py1 * 0.66, py1 * 0.42, za, zb,
                               chamfer=0.02, bevel=0.0))
            # Nozzle: a dark housing ring on the pod's back end, the bell with its opening cut in it, a dark disc
            # at the bottom of the opening (OutletGlow<n>, lit while boosting) and a smaller ring disc on it.
            ny0, ny1 = py1 + 0.04, py1 - length
            housing = prism(f"NozzleHousing{name}", K, py1 - 0.1, ny0, r + 0.03, r + 0.03, z=zc, sides=16)
            bell = prism(f"Nozzle{name}", F, ny1, py1 - 0.08, r, r * 0.95, z=zc, sides=16)
            cutter = prism(f"Nozzle{name}Cutter", F, ny1 - 0.05, ny1 + hole_d, hole_r, hole_r, z=zc, sides=16,
                           bevel=0.0)
            cutter.hide_render = True
            cutter.display_type = "WIRE"
            mod = bell.modifiers.new("Opening", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.solver = "EXACT"
            mod.object = cutter
            bell.modifiers.move(len(bell.modifiers) - 1, 0)
            glow = prism(f"OutletGlow{n}", K, ny1 + hole_d - 0.01, ny1 + hole_d + 0.005, hole_r, hole_r, z=zc,
                         sides=16, bevel=0.0)
            throat = prism(f"NozzleThroat{name}", F, ny1 + hole_d - 0.04, ny1 + hole_d - 0.005, hole_r * 0.6,
                           hole_r * 0.6, z=zc, sides=16, bevel=0.0)
            for obj in (housing, bell, cutter, glow, throat):
                obj.location.x = sx * cx
            parts += [housing, bell, glow, throat]
            # Jet nozzle petals round the exit rim, closed (tilted in) as built; BackPackFlaps opens them.
            count, p_len, tilt = t["petals"]
            for k in range(count):
                parts.append(nozzle_petal(f"NozzlePetal{n}_{k + 1}", K, (sx * cx, zc), ny1, 2.0 * math.pi * k / count,
                                          r * 0.93, p_len, math.radians(tilt), count))
            outlet = empty(f"Outlet{n}", (sx * cx, ny1 - p_len - 0.02, zc))
            outlet.rotation_euler = (math.pi / 2, 0.0, 0.0)
            parts.append(outlet)
            # Dark connector from the pod to the core.
            xa, xb = sorted((sx * 0.28, sx * (px0 + 0.03)))
            parts.append(block(f"PodArm{name}", F, xa, xb, -0.36, -0.12, zc - 0.14, zc + 0.14, chamfer=0.03))
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def build_belt_pack(t):
    """The Belt Pack (more body and detail since the user's request 2026-10-31: "make the belt pack more beautiful,
    add a bit more body to it"): a dark frame box (mount plate and panels on the torso side), a ribbed carry handle,
    a recessed belt channel down the back face between two riveted dark rails, a feed chute at the channel top with
    an olive cap and a curved guide at its foot, 16 rounds on a gentle arc in the channel (each a dark case lying
    across, a brass tip to +X, a brass band, base and a dark link; Canister1..8 empties hold two rounds each, the top
    pair first), four sloped olive armor blocks with inset plates and grip notches beside the belt, thick olive side
    boxes (upper with a slot and a top cap, lower with a yellow stripe, inset panels and bolts) joined by dark
    straps, a dark base skid with feet, orange lamps low on each side, one hardpoint on top."""
    A, AD, F, K, S, B, Y = "bp_armor", "bp_armor_dark", "bp_frame", "bp_dark", "bp_steel", "bp_brass", "bp_yellow"
    w, h, d = t["w"], t["h"], t["d"]
    top = h * 0.92
    sw = w + 0.36  # Outer x of the side boxes.
    parts = []

    def bolt(name, x, y0, y1, z, r=0.018):
        obj = prism(name, S, y0, y1, r, r, z=z, sides=6, bevel=0.0)
        obj.location.x = x
        return obj

    # Frame box, mount plate and panels on the torso side.
    parts.append(block("Frame", F, -w, w, -d, -0.08, -h, top, chamfer=0.08, bevel=0.015))
    parts.append(block("MountPlate", K, -w * 0.72, w * 0.72, -0.08, 0.0, -h * 0.82, h * 0.8, chamfer=0.05))
    for i, (z0, z1) in enumerate(((0.04, h * 0.74), (-h * 0.76, -0.04))):
        parts.append(block(f"MountPanel{i}", F, -w * 0.52, w * 0.52, -0.1, -0.06, z0, z1, chamfer=0.04, bevel=0.0))
    # Belt channel (dark well), the feed chute on top with its olive cap, and a curved guide at the foot.
    cw = 0.19
    parts.append(block("BeltWell", K, -cw, cw, -d - 0.02, -d + 0.1, -h + 0.08, top - 0.06, bevel=0.0))
    parts.append(block("FeedChute", F, -cw - 0.05, cw + 0.05, -d - 0.16, -d + 0.08, top - 0.1, top + 0.08,
                       chamfer=0.04, bevel=0.01))
    parts.append(block("FeedCap", A, -cw - 0.02, cw + 0.02, -d - 0.19, -d - 0.02, top - 0.02, top + 0.11,
                       chamfer=0.04, bevel=0.012))
    parts.append(block("FeedMouth", K, -cw + 0.02, cw - 0.02, -d - 0.165, -d - 0.12, top - 0.09, top - 0.04, bevel=0.0))
    parts.append(loft("BeltGuide", F, [
        (-h - 0.02, -h - 0.02, -cw - 0.04, cw + 0.04, -d + 0.06, -d - 0.04),
        (-h + 0.1, -h + 0.06, -cw - 0.04, cw + 0.04, -d + 0.06, -d - 0.17),
        (-h + 0.16, -h + 0.14, -cw - 0.04, cw + 0.04, -d + 0.06, -d - 0.16)], bevel=0.01))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        # Rails either side of the belt with rivets and caps.
        xa, xb = sorted((sx * cw, sx * (cw + 0.09)))
        parts.append(block(f"Rail{side}", F, xa, xb, -d - 0.13, -d + 0.05, -h - 0.02, top + 0.02, chamfer=0.03,
                           bevel=0.01))
        for j in range(6):
            z = top - 0.2 - j * (top + h - 0.36) / 5
            parts.append(bolt(f"Rivet{side}{j}", sx * (cw + 0.045), -d - 0.14, -d - 0.12, z, r=0.016))
        # Handle post on the rail top.
        xa, xb = sorted((sx * (cw + 0.03), sx * (cw + 0.13)))
        parts.append(block(f"HandlePost{side}", F, xa, xb, -0.64, -0.28, top - 0.02, h + 0.16, chamfer=0.03,
                           bevel=0.01))
        # Sloped olive armor blocks beside the belt (thicker at the outer edge), an inset plate and a grip notch.
        for j, (z0, z1) in enumerate(((0.2, 0.7), (-0.64, -0.12))):
            x_in, x_out = cw + 0.09, w + 0.06
            parts.append(loft(f"Armor{side}{j}", A, [
                (z0, z0, x_in, x_out, -d + 0.04, -d - 0.1),
                (z0 + 0.06, z0 + 0.06, x_in, x_out, -d + 0.04, -d - 0.17),
                (z1 - 0.06, z1 - 0.06, x_in, x_out, -d + 0.04, -d - 0.17),
                (z1, z1, x_in, x_out, -d + 0.04, -d - 0.1)], sx=sx, bevel=0.015))
            xa, xb = sorted((sx * (x_in + 0.05), sx * (x_out - 0.05)))
            parts.append(block(f"ArmorInset{side}{j}", AD, xa, xb, -d - 0.185, -d - 0.16, z0 + 0.12, z1 - 0.16,
                               chamfer=0.02, bevel=0.0))
            xa, xb = sorted((sx * (x_in + 0.07), sx * (x_in + 0.16)))
            parts.append(block(f"ArmorNotch{side}{j}", K, xa, xb, -d - 0.19, -d - 0.16, z1 - 0.13, z1 - 0.09,
                               bevel=0.0))
        # Thick side boxes: the upper with a slot, a top cap and bolts; the lower with an inset panel and the
        # yellow stripe; dark straps between them and round the lower box.
        xa, xb = sorted((sx * (w - 0.02), sx * sw))
        parts.append(block(f"SideBoxUp{side}", A, xa, xb, -d + 0.02, -0.12, 0.4, top, chamfer=0.08, bevel=0.015))
        xa2, xb2 = sorted((sx * (w + 0.06), sx * (sw - 0.06)))
        parts.append(block(f"SideCap{side}", AD, xa2, xb2, -d + 0.1, -0.2, top - 0.01, top + 0.04, chamfer=0.03,
                           bevel=0.0))
        xs0, xs1 = sorted((sx * (sw - 0.01), sx * (sw + 0.012)))
        parts.append(block(f"SideSlot{side}", K, xs0, xs1, -d + 0.22, -0.3, 0.6, 0.7, bevel=0.0))
        for j, y in enumerate((-d + 0.14, -0.24)):
            parts.append(block(f"SideBolt{side}{j}", S, xs0, xs1, y - 0.02, y + 0.02, 0.48, 0.52, bevel=0.0))
        parts.append(block(f"SideBoxLow{side}", A, xa, xb, -d + 0.0, -0.14, -0.7, 0.34, chamfer=0.08, bevel=0.015))
        parts.append(block(f"SidePanel{side}", AD, xs0, xs1, -d + 0.1, -0.58, -0.3, 0.2, chamfer=0.02, bevel=0.0))
        y = (-d - 0.14) / 2
        xy0, xy1 = sorted((sx * (sw + 0.008), sx * (sw + 0.02)))
        parts.append(block(f"Stripe{side}", Y, xy0, xy1, y - 0.035, y + 0.035, -0.64, 0.28, bevel=0.0))
        xa3, xb3 = sorted((sx * (w - 0.03), sx * (sw + 0.015)))
        parts.append(block(f"StrapMid{side}", F, xa3, xb3, -d - 0.01, -0.12, 0.34, 0.42, chamfer=0.02, bevel=0.0))
        parts.append(block(f"StrapLow{side}", F, xa3, xb3, -d - 0.01, -0.12, -0.4, -0.34, chamfer=0.015, bevel=0.0))
        # Feet under the side box and the armor.
        xa, xb = sorted((sx * (w - 0.04), sx * (sw - 0.04)))
        parts.append(block(f"Foot{side}", F, xa, xb, -d + 0.04, -0.16, -h - 0.06, -0.68, chamfer=0.06, bevel=0.01))
        xa, xb = sorted((sx * (cw + 0.1), sx * (w - 0.02)))
        parts.append(block(f"FootBack{side}", F, xa, xb, -d - 0.1, -d + 0.2, -h - 0.06, -h + 0.22, chamfer=0.05,
                           bevel=0.01))
    # Base skid across the bottom, the handle bar with a ribbed grip, the hardpoint.
    parts.append(block("BaseSkid", K, -w - 0.02, w + 0.02, -d + 0.06, -0.12, -h - 0.1, -h + 0.02, chamfer=0.05,
                       bevel=0.0))
    parts.append(block("HandleBar", F, -cw - 0.13, cw + 0.13, -0.64, -0.28, h + 0.05, h + 0.17, chamfer=0.035,
                       bevel=0.01))
    for i in range(4):
        x = -0.12 + i * 0.08
        parts.append(block(f"HandleRib{i}", K, x - 0.02, x + 0.02, -0.62, -0.3, h + 0.165, h + 0.18, bevel=0.0))
    parts.append(block("Hardpoint1", F, -0.12, 0.12, -0.26, -0.14, top - 0.02, top + 0.04, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.2, top + 0.04)))
    lamps = []
    for sx in (-1.0, 1.0):
        xa, xb = sorted((sx * (sw - 0.05), sx * (sw - 0.03)))
        lamps.append(block("Lamp" if sx < 0 else "LampR", "bp_glow", xa, xb, -0.5, -0.4, -h + 0.06, -h + 0.13,
                           bevel=0.0))
    with bpy.context.temp_override(active_object=lamps[0], selected_editable_objects=lamps):
        bpy.ops.object.join()
    parts.append(lamps[0])
    # Rounds: evenly down the channel, the top first, on a gentle arc out of the back face.
    n_rounds, per = t["rounds"], t["per_canister"]
    z_top, z_low = h * 0.92 - 0.12, -h + 0.14
    step = (z_top - z_low) / (n_rounds - 1)
    case_r, case_len, tip_len = 0.052, 0.27, 0.1
    for c in range(n_rounds // per):
        zs = [z_top - (c * per + k) * step for k in range(per)]
        zc = sum(zs) / per
        arc = lambda z: -d - 0.08 - 0.07 * math.cos(math.pi * (z - (z_top + z_low) / 2) / (z_top - z_low))
        pivot = empty(f"Canister{c + 1}", (0.0, arc(zc), zc))
        pieces = []
        for k, z in enumerate(zs):
            i = c * per + k
            y = arc(z) - arc(zc)
            dz = z - zc
            x0 = -(case_len + tip_len) / 2
            case = cyl_z(f"RoundCase{i}", K, 0.0, 0.0, x0, x0 + case_len, case_r, sides=10)
            band = cyl_z(f"RoundBand{i}", B, 0.0, 0.0, x0 + case_len - 0.04, x0 + case_len, case_r + 0.004, sides=10)
            tip = cyl_z(f"RoundTip{i}", B, 0.0, 0.0, x0 + case_len, x0 + case_len + tip_len, case_r, case_r * 0.25,
                        sides=10)
            base = cyl_z(f"RoundBase{i}", B, 0.0, 0.0, x0 - 0.01, x0 + 0.01, case_r * 0.9, sides=10)
            for obj in (case, band, tip, base):
                # Built along Z, turned to lie along +X (the tip to the right, as in the picture).
                obj.rotation_euler = (0.0, math.pi / 2, 0.0)
                obj.location = (0.0, y, dz)
            link = block(f"RoundLink{i}", F, -0.05, 0.05, y + 0.01, y + case_r + 0.02, dz - 0.03, dz + 0.03,
                         bevel=0.0)
            pieces += [case, band, tip, base, link]
        for piece in pieces:
            piece.parent = pivot
        parts.append(pivot)
        parts += pieces
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def tube(name, mat, points, radius, order=3):
    """A round tube (a cable) along a smooth curve through points [(x, y, z), ...], as a mesh."""
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new("NURBS")
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1.0)
    spline.order_u = order
    spline.use_endpoint_u = True
    spline.resolution_u = 6
    tmp = bpy.data.objects.new(name + "Tmp", curve)
    bpy.context.collection.objects.link(tmp)
    mesh = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, mat, 0.0)


def build_power_pack(t):
    """The Power Pack: a gunmetal center stack (a top box with seams, a radiator block with a louvered grille cut
    into its back face, a bottom block), tall towers on the upper sides with hatches, battery cells on the lower sides
    with copper bolts and terminals (the terminal windows are the Lamp), orange power cables (each tower feeds the
    stack through a ribbed sleeve and a cell terminal), a dark mount plate, one hardpoint on the top box."""
    A, AD, F, K, C, Cu = "bp_gun", "bp_gun_dark", "bp_frame", "bp_dark", "bp_cable", "bp_copper"
    bw, d, cr = t["body_w"], t["d"], t["cable_r"]
    tx0, tx1 = t["tower_x"]
    cx0, cx1 = t["cell_x"]
    parts = []

    def bolt(name, x, y, z, along="y"):
        if along == "y":
            obj = prism(name, Cu, y - 0.012, y + 0.012, 0.022, 0.022, z=z, sides=8, bevel=0.0)
            obj.location.x = x
        else:
            obj = cyl_z(name, Cu, 0.0, 0.0, -0.012, 0.012, 0.022, sides=8)
            obj.rotation_euler = (0.0, math.pi / 2, 0.0)
            obj.location = (x, y, z)
        return obj

    # Mount plate and the center stack.
    parts.append(block("MountPlate", F, -bw * 0.9, bw * 0.9, -0.08, 0.0, -0.85, 0.8, chamfer=0.05))
    parts.append(block("TopBox", A, -bw + 0.03, bw - 0.03, -d + 0.12, -0.08, 0.44, 0.88, chamfer=0.07, bevel=0.015))
    parts.append(block("TopSeam", F, -bw + 0.025, bw - 0.025, -d + 0.115, -0.08, 0.64, 0.66, bevel=0.0))
    radiator = block("Radiator", A, -bw, bw, -d, -0.06, -0.6, 0.44, chamfer=0.09, bevel=0.015)
    parts.append(radiator)
    grille_pts = [(-0.18, -0.52), (0.18, -0.52), (0.18, 0.2), (-0.18, 0.2)]
    # A raised dark ring round the grille recess.
    for i, (x0, x1, z0, z1) in enumerate(((-0.23, 0.23, 0.2, 0.25), (-0.23, 0.23, -0.57, -0.52),
                                          (-0.23, -0.18, -0.52, 0.2), (0.18, 0.23, -0.52, 0.2))):
        parts.append(block(f"RadiatorRing{i}", AD, x0, x1, -d - 0.03, -d + 0.01, z0, z1, bevel=0.0))
    parts += grille("RadiatorGrille", grille_pts, lambda z: -d, pitch=0.06, inset=0.015, cut=radiator, depth=0.08)
    parts.append(block("BottomBox", A, -bw + 0.04, bw - 0.04, -d + 0.1, -0.1, -1.03, -0.58, chamfer=0.07,
                       bevel=0.015))
    parts.append(block("BottomSeam", F, -bw + 0.035, bw - 0.035, -d + 0.095, -0.1, -0.82, -0.8, bevel=0.0))
    for i, (x, z) in enumerate(((-0.22, 0.8), (0.22, 0.8), (-0.24, 0.36), (0.24, 0.36), (-0.24, -0.5),
                                (0.24, -0.5), (-0.2, -0.95), (0.2, -0.95))):
        y = -d + 0.11 if abs(z) > 0.7 else -d - 0.005
        parts.append(bolt(f"StackBolt{i}", x, y, z))
    # More body (user 2026-10-31: "beautify and add more body"): a raised top plate with rails, dark ribs either
    # side of the radiator ring, a copper strip under it, and a base skid under the stack and the cells.
    parts.append(block("TopPlate", A, -bw + 0.08, bw - 0.08, -d + 0.2, -0.2, 0.88, 0.93, chamfer=0.04, bevel=0.008))
    for i, sx in enumerate((-1.0, 1.0)):
        x = sx * (bw - 0.11)
        parts.append(block(f"TopRail{i}", F, x - 0.025, x + 0.025, -d + 0.22, -0.22, 0.93, 0.97, chamfer=0.01,
                           bevel=0.0))
        for j in range(5):
            z = 0.12 - j * 0.14
            parts.append(block(f"StackRib{i}{j}", F, sx * 0.235 - 0.02 if sx < 0 else 0.255,
                               sx * 0.255 if sx < 0 else 0.275, -d - 0.03, -d + 0.02, z - 0.03, z + 0.03,
                               bevel=0.0))
    parts.append(block("CopperStrip", Cu, -0.2, 0.2, -d - 0.02, -d + 0.01, -0.58, -0.6, bevel=0.0))
    parts.append(block("BaseSkid", K, -t["cell_x"][1] + 0.26, t["cell_x"][1] - 0.26, -d + 0.2, -0.2, -1.1, -0.98,
                       chamfer=0.04, bevel=0.0))
    parts.append(block("Hardpoint1", F, -0.12, 0.12, -0.6, -0.3, 0.93, 0.97, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.45, 0.97)))
    lamps = []
    for side, sx in (("L", -1.0), ("R", 1.0)):
        # Tower: a tall box whose top slopes down to the back, a hatch on top, a dark collar at its foot.
        parts.append(loft(f"Tower{side}", A, [
            (0.22, 0.22, tx0, tx1, -0.06, -d + 0.06),
            (0.92, 0.84, tx0, tx1, -0.06, -d + 0.06),
            (1.06, 0.96, tx0 + 0.03, tx1 - 0.03, -0.1, -d + 0.1)], sx=sx, bevel=0.02))
        xa, xb = sorted((sx * (tx0 + 0.09), sx * (tx1 - 0.09)))
        parts.append(block(f"TowerHatch{side}", F, xa, xb, -0.36, -0.18, 1.0, 1.06, chamfer=0.02, bevel=0.0))
        xa, xb = sorted((sx * (tx0 - 0.01), sx * (tx1 + 0.01)))
        parts.append(block(f"TowerCollar{side}", AD, xa, xb, -d + 0.04, -0.04, 0.2, 0.3, chamfer=0.03, bevel=0.0))
        xa, xb = sorted((sx * (tx1 - 0.01), sx * (tx1 + 0.03)))
        parts.append(block(f"TowerPanel{side}", A, xa, xb, -d + 0.2, -0.2, 0.36, 0.86, chamfer=0.04, bevel=0.008))
        xa, xb = sorted((sx * (tx1 + 0.03), sx * (tx1 + 0.04)))
        parts.append(block(f"TowerSlot{side}", F, xa, xb, -0.6, -0.36, 0.7, 0.78, bevel=0.0))
        for j, y in enumerate((-d + 0.26, -0.26)):
            parts.append(bolt(f"TowerBolt{side}{j}", sx * (tx1 + 0.042), y, 0.42, along="x"))
        # Vent slots on the tower's back face and a dark top cap.
        for j in range(3):
            z = 0.84 - j * 0.07
            xa, xb = sorted((sx * (tx0 + 0.07), sx * (tx1 - 0.07)))
            parts.append(block(f"TowerVent{side}{j}", F, xa, xb, -d + 0.045, -d + 0.07, z - 0.02, z + 0.02,
                               bevel=0.0))
        xa, xb = sorted((sx * (tx0 + 0.02), sx * (tx1 - 0.02)))
        parts.append(block(f"TowerFoot{side}", K, xa, xb, -d + 0.1, -0.1, 0.16, 0.22, chamfer=0.02, bevel=0.0))
        # Connector arms from the stack to the tower and to the cell.
        xa, xb = sorted((sx * (bw - 0.04), sx * (tx0 + 0.04)))
        parts.append(block(f"TowerArm{side}", F, xa, xb, -0.6, -0.2, 0.5, 0.7, chamfer=0.03))
        xa, xb = sorted((sx * (bw - 0.04), sx * (cx0 + 0.04)))
        parts.append(block(f"CellArm{side}", F, xa, xb, -0.65, -0.25, -0.35, -0.1, chamfer=0.03))
        # Battery cell: an octagonal box, a raised panel with copper bolts, a seam, a terminal with a lamp window.
        xa, xb = sorted((sx * cx0, sx * cx1))
        parts.append(block(f"Cell{side}", A, xa, xb, -d + 0.08, -0.16, -0.74, 0.22, chamfer=0.09, bevel=0.015))
        xa, xb = sorted((sx * (cx0 + 0.05), sx * (cx1 - 0.05)))
        parts.append(block(f"CellPanel{side}", A, xa, xb, -d + 0.04, -d + 0.1, -0.64, 0.12, chamfer=0.05,
                           bevel=0.01))
        parts.append(block(f"CellSeam{side}", F, xa, xb, -d + 0.035, -d + 0.06, -0.27, -0.25, bevel=0.0))
        for j, (bx, bz) in enumerate(((cx0 + 0.1, 0.06), (cx1 - 0.1, 0.06), (cx0 + 0.1, -0.58),
                                      (cx1 - 0.1, -0.58))):
            parts.append(bolt(f"CellBolt{side}{j}", sx * bx, -d + 0.03, bz))
        for j, z in enumerate((0.08, -0.6)):
            parts.append(bolt(f"CellSideBolt{side}{j}", sx * (cx1 + 0.012), -0.5, z, along="x"))
        # Cooling ribs on the cell's outer side, dark caps top and bottom.
        for j in range(6):
            z = 0.0 - j * 0.1
            xa, xb = sorted((sx * (cx1 - 0.01), sx * (cx1 + 0.035)))
            parts.append(block(f"CellRib{side}{j}", AD, xa, xb, -d + 0.2, -0.28, z - 0.02, z + 0.02, bevel=0.0))
        xa, xb = sorted((sx * (cx0 + 0.04), sx * (cx1 - 0.04)))
        parts.append(block(f"CellCapTop{side}", AD, xa, xb, -d + 0.12, -0.2, 0.2, 0.26, chamfer=0.03, bevel=0.0))
        parts.append(block(f"CellCapLow{side}", AD, xa, xb, -d + 0.12, -0.2, -0.8, -0.72, chamfer=0.03, bevel=0.0))
        tcx = sx * (cx0 + cx1) / 2
        parts.append(block(f"Terminal{side}", F, tcx - 0.08, tcx + 0.08, -d + 0.22, -d + 0.42, 0.2, 0.34,
                           chamfer=0.025, bevel=0.0))
        lamps.append(block("Lamp" if sx < 0 else f"Lamp{side}", "bp_glow", tcx - 0.04, tcx + 0.04, -d + 0.205,
                           -d + 0.22, 0.24, 0.3, bevel=0.0))
        # Cables: tower foot to the stack's lower side through a ribbed sleeve, and tower side to the terminal.
        x_c = sx * (tx0 + 0.22)
        y_c = -d + 0.02
        for k in range(5):
            z = 0.18 - k * 0.045
            parts.append(cyl_z(f"Sleeve{side}{k}", K, x_c, y_c, z - 0.02, z + 0.02, cr + 0.012, sides=10))
        # The cables glow with the energy (user 2026-10-31; BackPackEnergyBar lights every EnergyCable mesh).
        parts.append(tube(f"EnergyCableMain{side}", C, [
            (x_c, y_c, 0.2), (x_c, y_c, -0.1), (x_c, y_c - 0.02, -0.55), (x_c, y_c - 0.02, -0.72),
            (sx * (bw + 0.02), y_c, -0.72), (sx * (bw - 0.04), y_c + 0.1, -0.7)], cr))
        x_2 = x_c + sx * 0.1
        parts.append(tube(f"EnergyCableAux{side}", C, [
            (x_2, y_c + 0.01, 0.2), (x_2, y_c + 0.01, -0.2), (x_2, y_c - 0.01, -0.62), (x_2, y_c - 0.01, -0.84),
            (sx * (bw + 0.04), y_c + 0.01, -0.86), (sx * (bw - 0.04), y_c + 0.12, -0.84)], cr * 0.6))
        for k in range(5):
            z = 0.18 - k * 0.045
            parts.append(cyl_z(f"SleeveAux{side}{k}", K, x_2, y_c + 0.01, z - 0.018, z + 0.018, cr * 0.6 + 0.01,
                               sides=10))
        parts.append(tube(f"EnergyCableCell{side}", C, [
            (sx * (tx1 - 0.02), -0.55, 0.42), (sx * (tx1 + 0.1), -0.55, 0.42), (sx * (tx1 + 0.12), -0.55, 0.36),
            (tcx + sx * 0.05, -d + 0.32, 0.4), (tcx, -d + 0.32, 0.34)], cr * 0.85))
        # Clamps holding both cables to the cell, copper collars where the cables enter the stack.
        for k, z in enumerate((-0.2, -0.5)):
            xa, xb = sorted((x_c - sx * 0.07, x_2 + sx * 0.06))
            parts.append(block(f"CableClamp{side}{k}", F, xa, xb, y_c - cr - 0.03, y_c + 0.06, z - 0.035, z + 0.035,
                               chamfer=0.015, bevel=0.0))
        for k, (z, r) in enumerate(((-0.71, cr + 0.015), (-0.85, cr * 0.6 + 0.015))):
            obj = cyl_z(f"CableCollar{side}{k}", Cu, 0.0, 0.0, -0.03, 0.03, r, sides=12)
            obj.rotation_euler = (0.0, math.pi / 2, 0.0)
            obj.location = (sx * (bw + 0.03), y_c + (0.0 if k == 0 else 0.01), z)
            parts.append(obj)
    with bpy.context.temp_override(active_object=lamps[0], selected_editable_objects=lamps):
        bpy.ops.object.join()
    parts.append(lamps[0])
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def build_field_pack(t):
    """The Field Pack: a sand center box (octagonal from the back) with a raised panel, a grille cut into it inside a
    dark ring, bolts, a dark top latch with two hardpoints beside it and a dark skid; two tall octagonal side pods
    with raised back panels, a seam, a dark slot bar, a dark latch with a sand plate, bolts, a carry handle over the
    top that runs down the outer side, a raised side plate with dark brackets, dark feet."""
    Sd, SD, F, K, S = "bp_sand", "bp_sand_dark", "bp_frame", "bp_dark", "bp_steel"
    bw, h, d = t["box_w"], t["h"], t["d"]
    px0, px1 = t["pod_x"]
    pc = (px0 + px1) / 2
    parts = []

    def bolt(name, x, y, z):
        obj = prism(name, S, y - 0.012, y + 0.012, 0.02, 0.02, z=z, sides=6, bevel=0.0)
        obj.location.x = x
        return obj

    # Mount plate and the center box with its raised panel, grille, bolts, latch, hardpoints and skid.
    parts.append(block("MountPlate", K, -bw * 0.9, bw * 0.9, -0.08, 0.0, -h * 0.85, h * 0.85, chamfer=0.05))
    parts.append(block("Box", Sd, -bw, bw, -d + 0.04, -0.06, -h + 0.04, h - 0.1, chamfer=0.1, bevel=0.015))
    panel = block("BoxPanel", Sd, -bw + 0.05, bw - 0.05, -d - 0.01, -d + 0.08, -h + 0.12, h - 0.2, chamfer=0.07,
                  bevel=0.01)
    parts.append(panel)
    grille_pts = [(-0.18, -0.52), (0.18, -0.52), (0.18, 0.3), (-0.18, 0.3)]
    for i, (x0, x1, z0, z1) in enumerate(((-0.23, 0.23, 0.3, 0.35), (-0.23, 0.23, -0.57, -0.52),
                                          (-0.23, -0.18, -0.52, 0.3), (0.18, 0.23, -0.52, 0.3))):
        parts.append(block(f"GrilleRing{i}", F, x0, x1, -d - 0.035, -d, z0, z1, bevel=0.0))
    parts += grille("BoxGrille", grille_pts, lambda z: -d - 0.01, pitch=0.055, inset=0.012, cut=panel, depth=0.07)
    for i, (x, z) in enumerate(((-bw + 0.11, h - 0.28), (bw - 0.11, h - 0.28), (-bw + 0.11, -h + 0.2),
                                (bw - 0.11, -h + 0.2), (-bw + 0.11, -0.1), (bw - 0.11, -0.1))):
        parts.append(bolt(f"BoxBolt{i}", x, -d - 0.02, z))
    parts.append(block("Latch", K, -0.22, 0.22, -0.72, -0.24, h - 0.14, h - 0.02, chamfer=0.03, bevel=0.0))
    parts.append(block("LatchSlot", F, -0.14, 0.14, -0.735, -0.72, h - 0.1, h - 0.06, bevel=0.0))
    for i, sx in enumerate((-1.0, 1.0)):
        x = sx * 0.17
        parts.append(block(f"LatchEar{i}", K, x - 0.035, x + 0.035, -0.76, -0.62, h - 0.16, h + 0.0, chamfer=0.015,
                           bevel=0.0))
        x = sx * 0.33
        parts.append(block(f"Hardpoint{i + 1}", F, x - 0.07, x + 0.07, -0.62, -0.32, h - 0.1, h - 0.06, bevel=0.0))
        parts.append(empty(f"Aux{i + 1}", (x, -0.47, h - 0.06)))
    parts.append(block("Skid", K, -bw + 0.08, bw - 0.08, -d + 0.12, -0.14, -h - 0.04, -h + 0.06, chamfer=0.04,
                       bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * px0, sx * px1))
        c = sx * pc
        # Pod: octagonal block, raised back panel, seam, slot bar, latch with a plate, bolts.
        parts.append(block(f"Pod{side}", Sd, x0, x1, -d, -0.08, -h, h, chamfer=0.14, bevel=0.015))
        xa, xb = sorted((sx * (px0 + 0.05), sx * (px1 - 0.05)))
        parts.append(block(f"PodPanel{side}", Sd, xa, xb, -d - 0.04, -d + 0.03, -h + 0.1, h - 0.1, chamfer=0.09,
                           bevel=0.01))
        parts.append(block(f"PodSeam{side}", F, xa, xb, -d - 0.045, -d, 0.06, 0.08, bevel=0.0))
        parts.append(block(f"PodSlot{side}", K, c - 0.15, c + 0.15, -d - 0.07, -d - 0.03, -0.04, 0.05, chamfer=0.01,
                           bevel=0.0))
        parts.append(block(f"PodLatch{side}", K, c - 0.16, c + 0.16, -d - 0.09, -d - 0.02, -h + 0.12, -h + 0.38,
                           chamfer=0.03, bevel=0.0))
        parts.append(block(f"PodLatchPlate{side}", Sd, c - 0.12, c + 0.12, -d - 0.105, -d - 0.08, -h + 0.15,
                           -h + 0.32, chamfer=0.02, bevel=0.0))
        for j, (bx, bz) in enumerate(((-0.17, h - 0.2), (0.17, h - 0.2), (-0.17, 0.2), (0.17, 0.2))):
            parts.append(bolt(f"PodBolt{side}{j}", c + bx, -d - 0.05, bz))
        # Carry handle: two posts and a bar over the top (near the mount side), and a bar down the outer side.
        for j, x in enumerate((c - sx * 0.2, c + sx * 0.2)):
            parts.append(block(f"HandlePost{side}{j}", K, x - 0.035, x + 0.035, -0.4, -0.3, h - 0.06, h + 0.16,
                               chamfer=0.012, bevel=0.0))
        xa, xb = sorted((c - sx * 0.235, sx * (px1 + 0.04)))
        parts.append(block(f"HandleBar{side}", K, xa, xb, -0.4, -0.3, h + 0.12, h + 0.2, chamfer=0.025, bevel=0.0))
        xa, xb = sorted((sx * (px1 - 0.005), sx * (px1 + 0.07)))
        parts.append(block(f"HandleSide{side}", K, xa, xb, -0.4, -0.3, -h + 0.2, h + 0.2, chamfer=0.02, bevel=0.0))
        # Raised side plate with dark brackets on the outer side, behind the handle.
        xa, xb = sorted((sx * (px1 - 0.01), sx * (px1 + 0.035)))
        parts.append(block(f"SidePlate{side}", Sd, xa, xb, -d + 0.08, -0.45, -h + 0.25, h - 0.25, chamfer=0.05,
                           bevel=0.008))
        for j, z in enumerate((h - 0.35, -h + 0.35)):
            xa, xb = sorted((sx * (px1 + 0.03), sx * (px1 + 0.065)))
            parts.append(block(f"SideBracket{side}{j}", K, xa, xb, -d + 0.2, -0.52, z - 0.05, z + 0.05,
                               chamfer=0.01, bevel=0.0))
        # Feet under the pod (inner half).
        xa, xb = sorted((sx * (px0 + 0.05), sx * (pc + 0.08)))
        parts.append(block(f"Foot{side}", K, xa, xb, -d + 0.1, -0.3, -h - 0.16, -h + 0.04, chamfer=0.05, bevel=0.0))
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def build_jet_pack(t):
    """The Jet Pack, redesigned (user 2026-10-31: "second backpack looks bad, looks like a smiley face; mock up a
    better design, add more heft and body"): a sand center under three overlapping armor shingles (dark lower edges,
    bolts on their lower corners), side columns with thick tapered armor
    (thicker at the inner edge), angled air intakes on their tops (a sloped dark louvered face), heavy outer bolsters
    with vents, a dark top latch with the hardpoint, a dark skid, and two big nozzles under the side columns pointing
    down and back inside heavy armored shrouds (sand collar, dark shroud, ring, bell with the opening cut in it,
    OutletGlow1..2 disc, inner ring, steel lip, Outlet1..2 empties past the exits, +Z out of the nozzle)."""
    Sd, SD, F, K, S = "bp_sand", "bp_sand_dark", "bp_frame", "bp_dark", "bp_steel"
    cx0, cx1 = t["col_x"]
    h, d = t["h"], t["d"]
    nx, nr, nl, ntilt = t["noz"]
    parts = []

    def bolt(name, x, y, z):
        obj = prism(name, S, y - 0.012, y + 0.012, 0.02, 0.02, z=z, sides=6, bevel=0.0)
        obj.location.x = x
        return obj

    parts.append(block("MountPlate", K, -0.34, 0.34, -0.08, 0.0, -h * 0.85, h * 0.85, chamfer=0.05))
    # Center: a sand core under three overlapping armor shingles, each thickest at its lower edge (it stands out
    # further back) and sloping in to the top, the next one tucked under it, with bolts on the lower corners.
    parts.append(block("Center", Sd, -cx0, cx0, -d + 0.06, -0.06, -h + 0.02, h - 0.02, chamfer=0.05, bevel=0.01))
    hw = cx0 - 0.03
    for i, (z0, z1) in enumerate(((-h - 0.02, -0.18), (-0.24, 0.3), (0.24, h + 0.02))):
        parts.append(loft(f"Shingle{i}", Sd, [
            (z0, z0, -hw + 0.03, hw - 0.03, -d + 0.1, -d - 0.1),
            (z0 + 0.05, z0 + 0.05, -hw, hw, -d + 0.1, -d - 0.14),
            (z1, z1, -hw + 0.02, hw - 0.02, -d + 0.1, -d - 0.02)], bevel=0.015))
        parts.append(block(f"ShingleEdge{i}", K, -hw + 0.04, hw - 0.04, -d - 0.15, -d - 0.12, z0 + 0.02, z0 + 0.05,
                           bevel=0.0))
        for j, sx in enumerate((-1.0, 1.0)):
            parts.append(bolt(f"ShingleBolt{i}{j}", sx * (hw - 0.07), -d - 0.145, z0 + 0.11))
    parts.append(block("Latch", K, -0.18, 0.18, -0.5, -0.2, h - 0.02, h + 0.1, chamfer=0.03, bevel=0.0))
    parts.append(block("Hardpoint1", F, -0.1, 0.1, -0.44, -0.26, h + 0.1, h + 0.14, bevel=0.0))
    parts.append(empty("Aux1", (0.0, -0.35, h + 0.14)))
    parts.append(block("Skid", K, -cx0 + 0.04, cx0 - 0.04, -d + 0.1, -0.12, -h - 0.12, -h + 0.02, chamfer=0.05,
                       bevel=0.0))
    for side, sx in (("L", -1.0), ("R", 1.0)):
        x0, x1 = sorted((sx * cx0, sx * cx1))
        parts.append(block(f"Column{side}", Sd, x0, x1, -d + 0.02, -0.06, -h, h - 0.04, chamfer=0.1, bevel=0.015))
        # Thick tapered armor on the back face (thicker at the inner edge), a seam and bolts.
        parts.append(loft(f"ColumnArmor{side}", Sd, [
            (-h + 0.08, -h + 0.08, cx0 + 0.04, cx1 - 0.05, -d + 0.04, -d - 0.06),
            (h - 0.12, h - 0.12, cx0 + 0.04, cx1 - 0.05, -d + 0.04, -d - 0.06)], sx=sx, bevel=0.015))
        xa, xb = sorted((sx * (cx0 + 0.035), sx * (cx0 + 0.07)))
        parts.append(block(f"ColumnEdge{side}", SD, xa, xb, -d - 0.1, -d - 0.02, -h + 0.06, h - 0.1, chamfer=0.012,
                           bevel=0.0))
        xa, xb = sorted((sx * (cx0 + 0.07), sx * (cx1 - 0.05)))
        parts.append(block(f"ColumnSeam{side}", F, xa, xb, -d - 0.065, -d - 0.04, -0.1, -0.08, bevel=0.0))
        for j, (bx, bz) in enumerate(((cx0 + 0.15, h - 0.2), (cx1 - 0.13, h - 0.2), (cx0 + 0.15, -h + 0.2),
                                      (cx1 - 0.13, -h + 0.2))):
            parts.append(bolt(f"ColumnBolt{side}{j}", sx * bx, -d - 0.07, bz))
        # Angled air intake on the column top: a housing whose top slopes down to the back, a dark louvered face.
        xi0, xi1 = cx0 + 0.06, cx1 - 0.08
        parts.append(loft(f"Intake{side}", Sd, [
            (h - 0.08, h - 0.08, xi0, xi1, -0.12, -d + 0.02),
            (h + 0.26, h + 0.06, xi0, xi1, -0.12, -d + 0.02),
            (h + 0.3, h + 0.09, xi0 + 0.03, xi1 - 0.03, -0.16, -d + 0.06)], sx=sx, bevel=0.015))
        y_in, y_out = -0.12, -d + 0.02
        z_in, z_out = h + 0.26, h + 0.06

        def slope_y(z, y_in=y_in, y_out=y_out, z_in=z_in, z_out=z_out):
            return y_in + (y_out - y_in) * (z_in - z) / (z_in - z_out)

        for j in range(5):
            f0 = 0.15 + j * 0.15
            z0 = z_in + (z_out - z_in) * f0
            y0 = slope_y(z0)
            xa, xb = sorted((sx * (xi0 + 0.06), sx * (xi1 - 0.06)))
            vane = block(f"IntakeVane{side}{j}", K, xa, xb, y0 - 0.05, y0 + 0.05, z0 - 0.01, z0 + 0.035, bevel=0.0)
            parts.append(vane)
        xa, xb = sorted((sx * (xi0 + 0.04), sx * (xi1 - 0.04)))
        parts.append(block(f"IntakeWell{side}", F, xa, xb, (y_in + y_out) / 2 - 0.3, (y_in + y_out) / 2 + 0.3,
                           h + 0.05, h + 0.12, bevel=0.0))
        # Heavy outer bolster with vents.
        xa, xb = sorted((sx * (cx1 - 0.02), sx * (cx1 + 0.06)))
        parts.append(block(f"Bolster{side}", Sd, xa, xb, -d + 0.1, -0.16, -h + 0.12, h - 0.16, chamfer=0.06,
                           bevel=0.012))
        for j in range(4):
            z = 0.25 - j * 0.09
            xa, xb = sorted((sx * (cx1 + 0.055), sx * (cx1 + 0.07)))
            parts.append(block(f"BolsterVent{side}{j}", K, xa, xb, -d + 0.2, -0.3, z - 0.025, z + 0.025, bevel=0.0))
    # Nozzles: down and back from housings under the side columns.
    a = math.radians(ntilt)
    direction = Vector((0.0, -math.sin(a), -math.cos(a)))
    theta = math.atan2(-math.cos(a), -math.sin(a))  # Turns a prism's +Y onto direction.
    for n, sx in ((1, -1.0), (2, 1.0)):
        root = Vector((sx * nx, -0.6, -h - 0.02))
        parts.append(block(f"NozzleHousing{n}", Sd, sx * nx - 0.34, sx * nx + 0.34, -0.9, -0.2, -h - 0.16,
                           -h + 0.08, chamfer=0.1, bevel=0.015))
        parts.append(block(f"HousingBand{n}", K, sx * nx - 0.345, sx * nx + 0.345, -0.62, -0.5, -h - 0.165,
                           -h + 0.085, chamfer=0.1, bevel=0.0))
        pieces = []
        collar = prism(f"NozzleCollar{n}", Sd, -0.06, 0.06, nr + 0.12, nr + 0.12, sides=8, bevel=0.012)
        shroud = prism(f"NozzleShroud{n}", K, 0.04, 0.2, nr + 0.07, nr + 0.05, sides=8, bevel=0.01)
        pieces += [collar, shroud]
        ring = prism(f"NozzleRing{n}", F, 0.0, 0.1, nr * 0.95, nr * 0.95, sides=16, bevel=0.0)
        bell = prism(f"Nozzle{n}", K, 0.08, nl, nr * 0.85, nr, sides=16)
        cutter = prism(f"Nozzle{n}Cutter", F, nl - 0.12, nl + 0.05, nr * 0.8, nr * 0.8, sides=16, bevel=0.0)
        glow = prism(f"OutletGlow{n}", K, nl - 0.13, nl - 0.115, nr * 0.8, nr * 0.8, sides=16, bevel=0.0)
        inner = prism(f"NozzleInner{n}", F, nl - 0.15, nl - 0.12, nr * 0.45, nr * 0.45, sides=16, bevel=0.0)
        lip = prism(f"NozzleLip{n}", S, nl - 0.02, nl + 0.005, nr + 0.01, nr + 0.01, sides=16, bevel=0.0)
        for obj in pieces + [ring, bell, cutter, glow, inner, lip]:
            obj.rotation_euler = (theta, 0.0, 0.0)
            obj.location = root
        cutter.hide_render = True
        cutter.display_type = "WIRE"
        mod = bell.modifiers.new("Opening", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        bell.modifiers.move(len(bell.modifiers) - 1, 0)
        parts += pieces + [ring, bell, glow, inner, lip]
        exit_point = root + direction * (nl + 0.03)
        outlet = empty(f"Outlet{n}", tuple(exit_point))
        outlet.rotation_euler = (math.pi - a, 0.0, 0.0)
        parts.append(outlet)
    parts.append(empty("Mount", (0.0, 0.0, 0.0)))
    return parts


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, t in TYPES.items():
        if args and name not in args:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        builders = {"ammo": build_ammo_pack, "missile": build_missile_pack, "boost": build_boost_pack,
                    "quad": build_quad_pack, "belt": build_belt_pack, "power": build_power_pack,
                    "field": build_field_pack, "jet": build_jet_pack}
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
