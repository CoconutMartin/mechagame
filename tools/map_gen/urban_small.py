"""Writes the urban test map: maps/urban_small/urban_small.tscn (about 256 x 256 m).

Run from the project root: python3 tools/map_gen/urban_small.py
(after tools/map_gen/urban_data.py and urban_props.py). The scene holds placed nodes only: buildings
are BuildingGenerator nodes with a BuildingDef, ground pieces are GroundSlab nodes, props are prop
scene instances. Move, add or remove them in the editor; running this script again overwrites the
scene. Layout (x right, -z north, meters, road top at y 0, sidewalks and blocks at 0.15):
  Main avenue north-south: 24 m between curbs (x -12..12), sidewalks 4 m.
  Side street A east-west through the center (4-way intersection): 14 m (z -7..7), sidewalks 3 m.
  Side street B east of the avenue (T junction): 14 m (z 57..71), sidewalks 3 m.
  Alley 4 m wide west of the avenue (z -35..-31): the mech (5.2 m wide) does not fit.
  Plaza 30 x 30 m (x -50..-20, z 14..44) and a parking lot with 12 cars (x 24..60, z -48..-14).
  Edge: tall out-of-bounds buildings (no damage) and invisible walls at +-129 m.
"""
import math, os, random

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = "maps/urban_small/urban_small.tscn"
CURB = 0.15
HALF = 128.0
INNER = 112.0
random.seed(7)

ext = {}       # path -> (type, id)
subs = []      # sub_resource text blocks
nodes = []     # node text blocks
names = {}


def res(path, kind="Resource"):
    if path not in ext:
        ext[path] = (kind, f"r{len(ext) + 1}")
    return f'ExtResource("{ext[path][1]}")'


def name(base):
    names[base] = names.get(base, 0) + 1
    return base if names[base] == 1 else f"{base}{names[base]}"


def xform(x, y, z, rot=0.0):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    r = lambda v: f"{v:.5g}"
    return f"Transform3D({r(c)}, 0, {r(-s)}, 0, 1, 0, {r(s)}, 0, {r(c)}, {r(x)}, {r(y)}, {r(z)})"


def node(text):
    nodes.append(text)


# ---- Ground ----

def slab(parent, label, x0, x1, z0, z1, top, mat, thick=None):
    thick = thick if thick is not None else (1.0 if top <= 0.0 else top + 0.5)
    node(f'[node name="{name(label)}" type="StaticBody3D" parent="{parent}"]\n'
         f'transform = {xform((x0 + x1) / 2, top, (z0 + z1) / 2)}\nscript = {res("res://scripts/environment/ground_slab.gd", "Script")}\n'
         f'size = Vector3({x1 - x0:g}, {thick:g}, {z1 - z0:g})\nmaterial_def = {res(f"res://data/environment/materials/{mat}.tres")}\n')


ROADS = [(-12, 12, -HALF, HALF), (-HALF, HALF, -7, 7), (12, HALF, 57, 71)]
# Blocks between the roads (sidewalk level). Each: x0, x1, z0, z1.
BLOCKS = [(-HALF, -12, -HALF, -7), (12, HALF, -HALF, -7), (-HALF, -12, 7, HALF), (12, HALF, 7, 57), (12, HALF, 71, HALF)]
PLAZA = (-50, -20, 14, 44)
LOT = (24, 60, -48, -14)


def ground():
    node('[node name="Ground" type="Node3D" parent="."]\n')
    slab("Ground", "Road", -HALF, HALF, -HALF, HALF, 0.0, "asphalt")
    for b in BLOCKS:
        slab("Ground", "Block", *b, CURB, "sidewalk")
    # Curbs: 0.3 m strips on the road edges of each block, 1 cm higher than the sidewalk.
    for x0, x1, z0, z1 in BLOCKS:
        for edge in _road_edges(x0, x1, z0, z1):
            slab("Ground", "Curb", *edge, CURB + 0.01, "curb")
    slab("Ground", "Plaza", *PLAZA, CURB + 0.01, "paving")
    slab("Ground", "ParkingLot", *LOT, CURB + 0.01, "asphalt")
    # Fountain: a concrete basin with dark water in the plaza center.
    cx, cz = (PLAZA[0] + PLAZA[1]) / 2, (PLAZA[2] + PLAZA[3]) / 2
    slab("Ground", "FountainBasin", cx - 3.5, cx + 3.5, cz - 3.5, cz + 3.5, 0.8, "concrete")
    slab("Ground", "FountainWater", cx - 3, cx + 3, cz - 3, cz + 3, 0.82, "glass", 0.05)


def _road_edges(x0, x1, z0, z1):
    edges = []
    w = 0.3
    if x1 == -12:
        edges.append((x1 - w, x1, z0, z1))
    if x0 == 12:
        edges.append((x0, x0 + w, z0, z1))
    if z1 in (-7, 57):
        edges.append((x0, x1, z1 - w, z1))
    if z0 in (7, 71):
        edges.append((x0, x1, z0, z0 + w))
    return edges


# ---- Markings (white and yellow paint, one MultiMesh each) ----

def markings():
    white, yellow = [], []
    for zs in ((-INNER, -11.5), (11.5, INNER)):
        for x in (-0.2, 0.2):
            yellow.append((x - 0.075, x + 0.075, *zs))
        for lane_x in (-8, -4, 4, 8):
            z = zs[0]
            while z + 3 <= zs[1]:
                white.append((lane_x - 0.075, lane_x + 0.075, z, z + 3))
                z += 9
    for xs in ((-INNER, -16.6), (16.6, INNER)):
        for z in (-0.2, 0.2):
            yellow.append((*xs, z - 0.075, z + 0.075))
    for z in (63.8, 64.2):
        yellow.append((16.6, INNER, z - 0.075, z + 0.075))
    # Crosswalks: across the avenue (z 7..10 and -10..-7), across street A (x 12..16, -16..-12), across B.
    for z0 in (-10, 7):
        x = -11.5
        while x <= 11.5:
            white.append((x - 0.25, x + 0.25, z0 + 0.2, z0 + 2.8))
            x += 1.0
    for x0 in (-16, 12):
        z = -6.5
        while z <= 6.5:
            white.append((x0 + 0.2, x0 + 3.8, z - 0.25, z + 0.25))
            z += 1.0
    z = 57.5
    while z <= 70.5:
        white.append((12.2, 15.8, z - 0.25, z + 0.25))
        z += 1.0
    # Stop lines.
    white += [(0.4, 11.8, 10.4, 10.8), (-11.8, -0.4, -10.8, -10.4), (16.4, 16.8, -6.8, -0.4), (-16.8, -16.4, 0.4, 6.8)]
    # Parking stalls: two rows of 6 (2.8 m wide, 5.5 m deep).
    for row_z in (-46.5, -21.0):
        for i in range(7):
            x = 28.0 + i * 2.8
            white.append((x - 0.06, x + 0.06, row_z, row_z + 5.5))
    for color, rects in (("white", white), ("yellow", yellow)):
        _multimesh(color, rects, 0.0 if color != "lot" else CURB)
    # The lot lines sit on the raised lot: lift them in place.


def _multimesh(color, rects, base):
    floats = []
    for x0, x1, z0, z1 in rects:
        y = 0.01 if not (LOT[0] <= x0 <= LOT[1] and LOT[2] <= z0 <= LOT[3]) else CURB + 0.02
        floats += [x1 - x0, 0, 0, (x0 + x1) / 2, 0, 0.02, 0, y, 0, 0, z1 - z0, (z0 + z1) / 2]
    r, g, b = (0.85, 0.85, 0.82) if color == "white" else (0.85, 0.65, 0.12)
    subs.append(f'[sub_resource type="StandardMaterial3D" id="paint_{color}"]\nalbedo_color = Color({r}, {g}, {b}, 1)\nroughness = 0.7\n')
    subs.append(f'[sub_resource type="BoxMesh" id="paint_box_{color}"]\n')
    subs.append(f'[sub_resource type="MultiMesh" id="paint_mm_{color}"]\ntransform_format = 1\ninstance_count = {len(rects)}\n'
                f'mesh = SubResource("paint_box_{color}")\nbuffer = PackedFloat32Array({", ".join(f"{v:.4g}" for v in floats)})\n')
    node(f'[node name="Paint{color.capitalize()}" type="MultiMeshInstance3D" parent="Ground"]\n'
         f'material_override = SubResource("paint_{color}")\ngi_mode = 2\nmultimesh = SubResource("paint_mm_{color}")\n')


# ---- Buildings ----

LOW_RISE = [
    ("apartment_4f", -23, -21, -90), ("shop_2f", -22, -42, -90), ("warehouse_2f", -42, -38, -90), ("office_5f", -24, -70, -90),
    ("apartment_3f", -75, -17, 180), ("shop_1f", -98, -16, 180),
    ("shop_2f", 22, -64, 90), ("apartment_3f", 23, -88, 90), ("shop_1f", 76, -16, 180), ("kiosk", 64.5, -12, 180), ("shed", 100, -30, 0),
    ("apartment_4f", -23, 62, -90), ("shop_2f", -22, 86, -90), ("office_5f", -75, 18, 0), ("shop_1f", -100, 16, 0),
    ("warehouse_2f", -78, 62, 0),
    ("apartment_3f", 23, 22, 90), ("shop_2f", 22, 45, 90), ("shop_1f", 50, 16, 0), ("apartment_4f", 82, 17, 0), ("kiosk", 64, 42, 0),
    ("apartment_3f", 40, 81, 0), ("office_5f", 75, 82, 0), ("shed", 100, 100, 0), ("apartment_4f", 23, 95, 90),
]
TOWERS = [("tower_concrete", -80, -70, 0), ("tower_glass", 88, -70, 0)]
FOOTPRINTS = {"kiosk": (5, 4), "shed": (6, 5), "shop_1f": (16, 12), "shop_2f": (14, 12), "apartment_3f": (18, 14),
              "apartment_4f": (20, 14), "office_5f": (22, 16), "warehouse_2f": (24, 18), "tower_glass": (24, 24),
              "tower_concrete": (20, 28), "edge_block": (32, 16)}


def rect_of(kind, x, z, rot):
    fx, fz = FOOTPRINTS[kind]
    if abs(rot) == 90:
        fx, fz = fz, fx
    return (x - fx / 2, x + fx / 2, z - fz / 2, z + fz / 2)


def overlap(a, b, gap=0.0):
    return a[0] < b[1] + gap and b[0] < a[1] + gap and a[2] < b[3] + gap and b[2] < a[3] + gap


def check_layout():
    rects = [(k, rect_of(k, x, z, r)) for k, x, z, r in LOW_RISE + TOWERS]
    keep_out = [("road", (r[0] - 3, r[1] + 3, r[2] - 3, r[3] + 3)) for r in ROADS] + [("plaza", PLAZA), ("lot", LOT)]
    for i, (k, a) in enumerate(rects):
        for k2, b in rects[i + 1:]:
            assert not overlap(a, b, 1.0), f"{k} {a} overlaps {k2} {b}"
        for k2, b in keep_out:
            # Sidewalk-facing walls may touch the sidewalk edge (3 or 4 m from the curb).
            inner = (b[0] + 0.01, b[1] - 0.01, b[2] + 0.01, b[3] - 0.01) if k2 == "road" else b
            assert not overlap(a, inner) or k2 == "road" and _only_touches(a, b), f"{k} {a} is on the {k2}"
        assert all(abs(v) <= INNER for v in a), f"{k} {a} is outside the play area"


def _only_touches(a, road):
    # The road keep-out includes 3 m of sidewalk; avenue sidewalks are 4 m: allow up to 1 m overlap.
    dx = min(a[1], road[1]) - max(a[0], road[0])
    dz = min(a[3], road[3]) - max(a[2], road[2])
    return min(dx, dz) <= 1.01


def buildings():
    node('[node name="Buildings" type="Node3D" parent="."]\n')
    for i, (kind, x, z, rot) in enumerate(LOW_RISE + TOWERS):
        node(f'[node name="{name(kind.title().replace("_", ""))}" type="Node3D" parent="Buildings"]\n'
             f'transform = {xform(x, CURB, z, rot)}\nscript = {res("res://scripts/environment/building_generator.gd", "Script")}\n'
             f'def = {res(f"res://data/environment/buildings/{kind}.tres")}\nvariant_seed = {i}\n')
    node('[node name="EdgeBuildings" type="Node3D" parent="."]\n')
    for c in range(-112, 113, 32):
        for x, z, rot in ((c, -120, 180), (c, 120, 0), (-120, c, -90), (120, c, 90)):
            node(f'[node name="{name("Edge")}" type="Node3D" parent="EdgeBuildings"]\n'
                 f'transform = {xform(x, CURB, z, rot)}\nscript = {res("res://scripts/environment/building_generator.gd", "Script")}\n'
                 f'def = {res("res://data/environment/buildings/edge_block.tres")}\nvariant_seed = {x * 7 + z}\n')


def bounds():
    subs.append('[sub_resource type="BoxShape3D" id="wall_ns"]\nsize = Vector3(260, 120, 2)\n')
    subs.append('[sub_resource type="BoxShape3D" id="wall_ew"]\nsize = Vector3(2, 120, 260)\n')
    node('[node name="WorldBounds" type="StaticBody3D" parent="."]\ncollision_layer = 1\ncollision_mask = 0\n')
    for label, shape, x, z in (("North", "wall_ns", 0, -129), ("South", "wall_ns", 0, 129), ("West", "wall_ew", -129, 0),
                               ("East", "wall_ew", 129, 0)):
        node(f'[node name="{label}" type="CollisionShape3D" parent="WorldBounds"]\n'
             f'transform = {xform(x, 60, z)}\nshape = SubResource("{shape}")\n')


# ---- Props ----

def prop(scene, x, z, rot=0.0, y=CURB, group="Props"):
    node(f'[node name="{name(scene.title().replace("_", ""))}" parent="{group}" instance={res(f"res://scenes/props/urban/{scene}.tscn", "PackedScene")}]\n'
         f'transform = {xform(x, y, z, rot)}\n')


def props():
    node('[node name="Props" type="Node3D" parent="."]\n')
    # Lampposts along both avenue curbs (arm over the road) and along street A.
    for z in range(-104, 105, 16):
        if abs(z) < 14 or 54 <= z <= 74:
            continue
        prop("lamppost", -12.7, z, -90)
        prop("lamppost", 12.7, z, 90)
    for x in list(range(-104, -19, 16)) + list(range(24, 105, 16)):
        prop("lamppost", x, -9.7, 180)
        prop("lamppost", x, 9.7, 0)
    # Traffic lights on the four corners of the intersection (arm over the road).
    for x, z, rot in ((13.2, -10.5, 90), (-13.2, 10.5, -90), (-13.2, -10.5, 0), (13.2, 10.5, 180)):
        prop("traffic_light", x, z, rot)
    # Dense props near the spawn (avenue, z 14..54): trees, benches, hydrants, people, a bus stop.
    for z in (18, 30, 42):
        prop("tree", -15.0, z + 2)
        prop("tree", 15.0, z + 6)
    for z in (22, 36, 48):
        prop("bench", -15.3, z, 90)
    for x, z in ((-12.8, 26), (12.8, 34), (-12.8, 50), (12.8, -22), (-12.8, -40), (20, 9.0)):
        prop("hydrant", x, z)
    prop("bus_stop", 14.6, 28, 90)
    prop("bench", 15.3, 46, -90)
    for x, z in ((-14.2, 19), (-13.5, 33.5), (-14.8, 41), (13.8, 27), (14.2, 31.5), (13.4, 44), (-14.0, 56), (14.6, 18),
                 (-13.2, -18), (13.6, -30)):
        prop(random.choice(("person", "person_b")), x, z, random.uniform(0, 360))
    # Parked cars along the avenue curbs and street A, the bus in a lane.
    for x, z, rot in ((-10.0, 22, 180), (-10.0, 46, 180), (10.0, 40, 0), (10.0, 62, 0), (-10.0, -30, 180), (10.0, -48, 0)):
        prop(random.choice(("car", "car_blue", "car_white", "car_grey")), x, z, rot, 0.0)
    for x, z, rot in ((-30, 5.0, 90), (-52, 5.0, 90), (34, -5.0, -90), (70, -5.0, -90)):
        prop(random.choice(("car", "car_blue", "car_white", "car_grey")), x, z, rot, 0.0)
    prop("bus", 6.0, 50, 0, 0.0)
    # Parking lot: 2 rows of 6 cars and a fence on the north and east sides.
    for row_z, rot in ((-43.75, 0), (-18.25, 180)):
        for i in range(6):
            prop(random.choice(("car", "car_blue", "car_white", "car_grey")), 29.4 + i * 2.8, row_z, rot, CURB + 0.01)
    for x in range(25, 60, 2):
        prop("fence", x, -47.8, 0, CURB + 0.01)
    for z in range(-46, -15, 2):
        prop("fence", 59.8, z + 1, 90, CURB + 0.01)
    # Plaza: benches around the fountain, trees at the corners, people.
    cx, cz = (PLAZA[0] + PLAZA[1]) / 2, (PLAZA[2] + PLAZA[3]) / 2
    for dx, dz, rot in ((0, -6, 0), (0, 6, 180), (-6, 0, 90), (6, 0, -90)):
        prop("bench", cx + dx, cz + dz, rot, CURB + 0.01)
    for dx in (-12, 12):
        for dz in (-12, 12):
            prop("tree", cx + dx, cz + dz, 0, CURB + 0.01)
    for _ in range(6):
        prop(random.choice(("person", "person_b")), cx + random.uniform(-11, 11), cz + random.uniform(-11, 11),
             random.uniform(0, 360), CURB + 0.01)
    # Street A sidewalks: a few trees and benches.
    for x in (-60, -44, 36, 52, 88):
        prop("tree", x + 8, -8.5)
        prop("tree", x, 8.5)


# ---- Decals ----

def decals():
    node('[node name="Decals" type="Node3D" parent="."]\n')
    spots = [("manhole", 1.2, x, z, 0.0) for x, z in ((-6, 30), (6, -24), (-2, 80), (4, -70), (40, 0), (-60, 2), (70, 64), (-2, 4))]
    spots += [("cracks", 4.0, random.uniform(-10, 10), random.uniform(-100, 100), 0.0) for _ in range(10)]
    spots += [("cracks", 3.0, random.choice((-14, 14)), random.uniform(-90, 90), CURB) for _ in range(5)]
    spots += [("oil_stain", 2.2, random.uniform(28, 56), random.choice((-44, -19)), CURB + 0.01) for _ in range(5)]
    spots += [("oil_stain", 2.0, random.uniform(-10, 10), random.uniform(-80, 80), 0.0) for _ in range(5)]
    for tex, size, x, z, y in spots:
        node(f'[node name="{name(tex.title().replace("_", ""))}" type="Decal" parent="Decals"]\n'
             f'transform = {xform(x, y + 0.3, z, random.uniform(0, 360))}\nsize = Vector3({size}, 1, {size})\n'
             f'texture_albedo = {res(f"res://assets/textures/decals/{tex}.png", "Texture2D")}\n'
             f'cull_mask = 1\ndistance_fade_enabled = true\ndistance_fade_begin = 100.0\n')


# ---- Lighting, player and game logic (same nodes as the old test map) ----

def lighting():
    subs.append('[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]\nsky_top_color = Color(0.32, 0.45, 0.62, 1)\n'
                'sky_horizon_color = Color(0.68, 0.7, 0.72, 1)\nground_bottom_color = Color(0.2, 0.19, 0.18, 1)\n'
                'ground_horizon_color = Color(0.68, 0.7, 0.72, 1)\n')
    subs.append('[sub_resource type="Sky" id="sky"]\nsky_material = SubResource("sky_mat")\n')
    # AgX tonemap (4), SDFGI, SSAO, SSR, glow, depth fog that fades the far towers a little at 200 m.
    subs.append('[sub_resource type="Environment" id="env"]\nbackground_mode = 2\nsky = SubResource("sky")\nambient_light_source = 3\n'
                'tonemap_mode = 4\nssr_enabled = true\nssao_enabled = true\nsdfgi_enabled = true\nsdfgi_use_occlusion = true\n'
                'sdfgi_cascades = 5\nsdfgi_min_cell_size = 0.4\nglow_enabled = true\nfog_enabled = true\n'
                'fog_light_color = Color(0.62, 0.65, 0.7, 1)\nfog_density = 0.003\nfog_sky_affect = 0.5\n'
                'volumetric_fog_enabled = true\nvolumetric_fog_density = 0.001\nvolumetric_fog_albedo = Color(0.85, 0.87, 0.9, 1)\n'
                'volumetric_fog_length = 300.0\n')
    node('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("env")\n')
    node('[node name="Sun" type="DirectionalLight3D" parent="."]\n'
         'transform = Transform3D(0.819152, 0.439385, -0.368688, 0, 0.642788, 0.766044, 0.573576, -0.627507, 0.526541, 0, 80, 0)\n'
         'light_energy = 1.3\nshadow_enabled = true\ndirectional_shadow_max_distance = 400.0\n')
    # Bake in the editor (select LightmapGI > Bake Lightmaps): only the ground (static GI) is baked.
    node('[node name="LightmapGI" type="LightmapGI" parent="."]\nquality = 1\ntexel_scale = 0.25\nmax_texture_size = 4096\n')


def logic():
    mech = res("res://scenes/mech/player_mech.tscn", "PackedScene")
    hud = res("res://scenes/ui/debug_hud.tscn", "PackedScene")
    loadouts = ["warden", "warden_sniper", "warden_melee", "warden_missile", "recon", "recon_accurate", "recon_sleek",
                "recon_gen", "recon_sheet"]
    refs = ", ".join(res(f"res://data/loadouts/{l}.tres") for l in loadouts)
    spawner = res("res://scripts/world/mech_spawner.gd", "Script")
    gunner = res("res://data/loadouts/warden.tres")
    node(f'[node name="MouseCapture" type="Node" parent="."]\nscript = {res("res://scripts/core/mouse_capture.gd", "Script")}\n')
    node('[node name="Targets" type="Node3D" parent="."]\n')
    node(f'[node name="DummyMech" type="Node3D" parent="Targets" node_paths=PackedStringArray("player_respawner")]\n'
         f'transform = {xform(-5, 0, -30, 180)}\nscript = {spawner}\nmech_scene = {mech}\nloadout = {gunner}\n'
         f'player_respawner = NodePath("../../PlayerRespawner")\n')
    node(f'[node name="Enemy1" type="Node3D" parent="Targets" node_paths=PackedStringArray("player_respawner")]\n'
         f'transform = {xform(6, 0, -95, 180)}\nscript = {spawner}\nmech_scene = {mech}\nloadout = {gunner}\npilot = 1\n'
         f'player_respawner = NodePath("../../PlayerRespawner")\n')
    # Player on the avenue, south of the intersection, facing north.
    node(f'[node name="PlayerMech" parent="." instance={mech}]\ntransform = {xform(-5, 0, 36)}\n')
    node(f'[node name="DebugHud" parent="." node_paths=PackedStringArray("mech", "mech_aim") instance={hud}]\n'
         f'mech = NodePath("../PlayerMech")\nmech_aim = NodePath("../PlayerMech/MechAim")\n')
    node(f'[node name="LoadoutSwitcher" type="Node" parent="." node_paths=PackedStringArray("mech", "hud")]\n'
         f'script = {res("res://scripts/core/loadout_switcher.gd", "Script")}\nmech_scene = {mech}\n'
         f'loadouts = Array[Resource]([{refs}])\nmech = NodePath("../PlayerMech")\nhud = NodePath("../DebugHud")\n')
    node(f'[node name="PlayerRespawner" type="Node" parent="." node_paths=PackedStringArray("switcher")]\n'
         f'script = {res("res://scripts/core/player_respawner.gd", "Script")}\nswitcher = NodePath("../LoadoutSwitcher")\n')
    node(f'[node name="DebugDamage" type="Node" parent="." node_paths=PackedStringArray("switcher")]\n'
         f'script = {res("res://scripts/core/debug_damage.gd", "Script")}\nswitcher = NodePath("../LoadoutSwitcher")\n')
    node(f'[node name="Garage" type="CanvasLayer" parent="." node_paths=PackedStringArray("switcher")]\n'
         f'script = {res("res://scripts/ui/garage.gd", "Script")}\ncatalog = {res("res://data/garage_catalog.tres")}\n'
         f'switcher = NodePath("../LoadoutSwitcher")\n')


def main():
    check_layout()
    node('[node name="UrbanSmall" type="Node3D"]\n')
    lighting()
    ground()
    markings()
    buildings()
    bounds()
    props()
    decals()
    logic()
    head = ["[gd_scene format=3]", ""]
    head += [f'[ext_resource type="{t}" path="{p}" id="{i}"]' for p, (t, i) in ext.items()]
    text = "\n".join(head) + "\n\n" + "\n".join(subs) + "\n" + "\n".join(nodes)
    full = os.path.join(ROOT, OUT)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write(text)
    print("wrote", OUT, len(nodes), "nodes")


if __name__ == "__main__":
    main()
