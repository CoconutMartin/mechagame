"""Writes the urban map resources: data/environment/materials, buildings and props (.tres).

Run from the project root: python3 tools/map_gen/urban_data.py
After that, tune the values in the .tres files (Inspector) or here, and run it again.
Materials: textures in assets/textures (CC0, see CREDITS.md); texture_scale_m = real texture size.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ENV = "data/environment"


def tex(name, kind):
    return f"res://assets/textures/{name}/{name}_{kind}.jpg"


def value(v, key=""):
    if isinstance(v, tuple) and (key == "tint" or key.endswith("_color")):
        return "Color(%s, %s, %s, %s)" % (v + (1.0,) * (4 - len(v)))
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, tuple) and len(v) == 3:
        return "Vector3(%s, %s, %s)" % v
    if isinstance(v, tuple):
        return "Color(%s, %s, %s, %s)" % (v + (1.0,) * (4 - len(v)))
    return repr(v) if isinstance(v, float) else str(v)


def write(path, script_class, script, fields, links=None):
    """links: field -> (type, res path) for ext resources."""
    links = links or {}
    lines = [f'[gd_resource type="Resource" script_class="{script_class}" format=3]', "",
             f'[ext_resource type="Script" path="res://scripts/environment/{script}.gd" id="script"]']
    for key, (kind, link) in links.items():
        lines.append(f'[ext_resource type="{kind}" path="{link}" id="{key}"]')
    lines += ["", "[resource]", 'script = ExtResource("script")']
    lines += [f"{k} = {value(v, k)}" for k, v in fields.items()]
    lines += [f'{k} = ExtResource("{k}")' for k in links]
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write("\n".join(lines) + "\n")
    return "res://" + path


# ---- Materials: name -> (fields, texture folder or None) ----
MATERIALS = {
    # Building materials (strength values from the design brief).
    "glass": (dict(display_name="Glass", hp_per_m3=40.0, damage_threshold=0.0, density=2.5, tint=(0.16, 0.2, 0.24),
                   metallic=0.5, roughness=0.06, debris_color=(0.6, 0.7, 0.75)), None),
    "glass_lit": (dict(display_name="Glass (lit)", hp_per_m3=40.0, damage_threshold=0.0, density=2.5, tint=(0.35, 0.3, 0.22),
                       metallic=0.2, roughness=0.1, emission_energy=0.3, emission_color=(1.0, 0.82, 0.55),
                       debris_color=(0.6, 0.7, 0.75)), None),
    "brick": (dict(display_name="Brick", hp_per_m3=150.0, damage_threshold=30.0, density=1.9, texture_scale_m=1.0,
                   roughness=0.9, debris_color=(0.5, 0.3, 0.24)), "brick"),
    "plaster": (dict(display_name="Plaster (on brick)", hp_per_m3=150.0, damage_threshold=30.0, density=1.9,
                     texture_scale_m=2.0, tint=(0.92, 0.88, 0.8), roughness=0.9, debris_color=(0.75, 0.72, 0.66)), "plaster"),
    "concrete": (dict(display_name="Concrete", hp_per_m3=300.0, damage_threshold=80.0, density=2.4, texture_scale_m=2.0,
                      roughness=0.9, debris_color=(0.6, 0.6, 0.58)), "concrete"),
    "steel_frame": (dict(display_name="Steel frame", hp_per_m3=900.0, damage_threshold=150.0, density=7.8, texture_scale_m=0.5,
                         tint=(0.55, 0.57, 0.6), metallic=0.7, roughness=0.45, debris_color=(0.35, 0.35, 0.37)), "metal"),
    "metal_sheet": (dict(display_name="Metal sheet", hp_per_m3=120.0, damage_threshold=10.0, density=1.0, texture_scale_m=0.5,
                         tint=(0.45, 0.5, 0.48), metallic=0.6, roughness=0.5, debris_color=(0.4, 0.42, 0.4)), "metal"),
    "door": (dict(display_name="Door", hp_per_m3=80.0, damage_threshold=0.0, density=1.0, texture_scale_m=0.5,
                  tint=(0.2, 0.22, 0.24), metallic=0.6, roughness=0.45), "metal"),
    "roof_gravel": (dict(display_name="Roof gravel", hp_per_m3=300.0, damage_threshold=80.0, density=2.4, texture_scale_m=2.25,
                         tint=(0.75, 0.75, 0.75), roughness=0.95), "roof_gravel"),
    "interior": (dict(display_name="Dark interior", hp_per_m3=900.0, damage_threshold=150.0, density=2.4,
                      tint=(0.05, 0.05, 0.06), roughness=1.0), None),
    # Ground materials.
    "asphalt": (dict(display_name="Asphalt", texture_scale_m=3.0, tint=(0.8, 0.8, 0.8), roughness=0.9), "asphalt"),
    "sidewalk": (dict(display_name="Sidewalk slabs", texture_scale_m=1.8, roughness=0.9), "sidewalk"),
    "paving": (dict(display_name="Plaza paving", texture_scale_m=2.0, roughness=0.85), "paving_tiles"),
    "curb": (dict(display_name="Curb stone", texture_scale_m=2.0, tint=(1.1, 1.1, 1.08), roughness=0.85), "concrete"),
    "paint_white": (dict(display_name="Road paint (white)", tint=(0.85, 0.85, 0.82), roughness=0.7), None),
    "paint_yellow": (dict(display_name="Road paint (yellow)", tint=(0.85, 0.65, 0.12), roughness=0.7), None),
    "grass": (dict(display_name="Grass", tint=(0.22, 0.32, 0.14), roughness=1.0), None),
}

# ---- Buildings ----
# name: fields (materials by name).
BUILDINGS = {
    "kiosk": dict(display_name="Kiosk", footprint_x=5.0, footprint_z=4.0, floor_count=1, ground_floor_height=4.0,
                  wall="plaster", frame="concrete", window_ratio=0.6, shop_front=True, roof_type=0, chunk_width=2.5,
                  column_spacing=20.0),
    "shed": dict(display_name="Shed", footprint_x=6.0, footprint_z=5.0, floor_count=1, ground_floor_height=4.5,
                 wall="metal_sheet", frame="steel_frame", window_ratio=0.0, shop_front=False, roof_type=0, chunk_width=3.0,
                 column_spacing=20.0),
    "shop_1f": dict(display_name="Shop (1 floor)", footprint_x=16.0, footprint_z=12.0, floor_count=1, ground_floor_height=4.0,
                    wall="brick", frame="concrete", window_ratio=0.55, shop_front=True, roof_type=1),
    "shop_2f": dict(display_name="Shop (2 floors)", footprint_x=14.0, footprint_z=12.0, floor_count=2, ground_floor_height=4.0,
                    wall="plaster", frame="concrete", window_ratio=0.5, shop_front=True, roof_type=1),
    "apartment_3f": dict(display_name="Apartments (3 floors)", footprint_x=18.0, footprint_z=14.0, floor_count=3,
                         ground_floor_height=4.0, wall="brick", frame="concrete", window_ratio=0.45, shop_front=True, roof_type=1),
    "apartment_4f": dict(display_name="Apartments (4 floors)", footprint_x=20.0, footprint_z=14.0, floor_count=4,
                         ground_floor_height=4.0, wall="plaster", frame="concrete", window_ratio=0.45, shop_front=True, roof_type=2),
    "office_5f": dict(display_name="Office (5 floors)", footprint_x=22.0, footprint_z=16.0, floor_count=5,
                      ground_floor_height=3.2, wall="concrete", frame="concrete", window_ratio=0.6, window_height_ratio=0.55,
                      shop_front=False, roof_type=2),
    "warehouse_2f": dict(display_name="Warehouse (2 floors)", footprint_x=24.0, footprint_z=18.0, floor_count=2,
                         ground_floor_height=4.0, wall="concrete", frame="steel_frame", window_ratio=0.25,
                         window_height_ratio=0.35, shop_front=False, roof_type=0),
    "tower_glass": dict(display_name="Glass tower (55 m)", footprint_x=24.0, footprint_z=24.0, floor_count=17,
                        ground_floor_height=4.0, wall="steel_frame", frame="steel_frame", window_ratio=0.85,
                        window_height_ratio=0.8, shop_front=True, roof_type=1, facade_only=True, integrity_multiplier=3.0),
    "tower_concrete": dict(display_name="Concrete tower (42 m)", footprint_x=20.0, footprint_z=28.0, floor_count=13,
                           ground_floor_height=4.0, wall="concrete", frame="concrete", window_ratio=0.55,
                           window_height_ratio=0.6, shop_front=True, roof_type=2, facade_only=True, integrity_multiplier=3.0),
    "edge_block": dict(display_name="Edge block (out of bounds)", footprint_x=32.0, footprint_z=16.0, floor_count=10,
                       ground_floor_height=3.2, wall="concrete", frame="concrete", window_ratio=0.5, shop_front=False,
                       roof_type=1, indestructible=True, chunk_width=8.0, column_spacing=40.0),
}

# ---- Props (sizes and reactions from the design brief) ----
# reaction: 0 NONE, 1 CRUSH, 2 PUSH, 3 BEND, 4 BREAK, 5 FALL
PROPS = {
    "car": dict(display_name="Car", size=(1.8, 1.5, 4.5), hp=300.0, mass_t=1.4, reaction=1, shake=0.15),
    "bus": dict(display_name="Bus", size=(2.5, 3.2, 12.0), hp=900.0, mass_t=12.0, reaction=2, shake=0.25),
    "lamppost": dict(display_name="Lamppost", size=(0.3, 6.0, 0.3), hp=120.0, mass_t=0.3, reaction=3, shake=0.05),
    "traffic_light": dict(display_name="Traffic light", size=(0.35, 5.5, 0.35), hp=150.0, mass_t=0.4, reaction=3, shake=0.05),
    "bus_stop": dict(display_name="Bus stop", size=(3.0, 2.5, 1.5), hp=120.0, mass_t=0.5, reaction=4, debris_pieces=8, shake=0.06),
    "bench": dict(display_name="Bench", size=(1.8, 0.8, 0.6), hp=40.0, mass_t=0.08, reaction=4, debris_pieces=4, shake=0.02),
    "fence": dict(display_name="Fence section", size=(2.0, 1.2, 0.1), hp=30.0, mass_t=0.05, reaction=4, debris_pieces=3, shake=0.02),
    "hydrant": dict(display_name="Fire hydrant", size=(0.4, 0.8, 0.4), hp=60.0, mass_t=0.1, reaction=4, debris_pieces=3,
                    water_spray=True, shake=0.03),
    "tree": dict(display_name="Tree", size=(0.5, 7.0, 0.5), hp=150.0, mass_t=1.0, reaction=5, shake=0.06),
    "person": dict(display_name="Person", size=(0.5, 1.8, 0.5), hp=10.0, mass_t=0.08, reaction=0, shake=0.0),
}


def main():
    for name, (fields, folder) in MATERIALS.items():
        links = {}
        if folder:
            links = {"albedo_texture": ("Texture2D", tex(folder, "albedo")), "normal_texture": ("Texture2D", tex(folder, "normal")),
                     "roughness_texture": ("Texture2D", tex(folder, "rough"))}
        write(f"{ENV}/materials/{name}.tres", "MaterialDef", "material_def", fields, links)
    for name, b in BUILDINGS.items():
        b = dict(b)
        wall, frame = b.pop("wall"), b.pop("frame")
        mats = {"wall_material": wall, "frame_material": frame, "glass_material": "glass", "roof_material": "roof_gravel",
                "door_material": "door"}
        links = {k: ("Resource", f"res://{ENV}/materials/{v}.tres") for k, v in mats.items()}
        for key in ("footprint_x", "footprint_z", "ground_floor_height", "window_ratio", "window_height_ratio", "chunk_width",
                    "column_spacing", "integrity_multiplier"):
            if key in b:
                b[key] = float(b[key])
        write(f"{ENV}/buildings/{name}.tres", "BuildingDef", "building_def", b, links)
    for name, p in PROPS.items():
        write(f"{ENV}/props/{name}.tres", "PropDef", "prop_def", p)
    print("wrote", len(MATERIALS), "materials,", len(BUILDINGS), "buildings,", len(PROPS), "props")


if __name__ == "__main__":
    main()
