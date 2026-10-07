"""Writes the urban prop scenes (scenes/props/urban/*.tscn) from simple shapes.

Run from the project root: python3 tools/map_gen/urban_props.py
Each scene: UrbanProp root (StaticBody3D, layer 3 props) with its PropDef, a CollisionShape3D box
(PropDef size), a Pivot node at the base with the meshes, and a Contact Area3D (finds mechs, layer 2).
Meshes fade out past 120 m (visibility range) and use dynamic GI.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = "scenes/props/urban"
PROP_LAYER, MECH_LAYER = 4, 2
FADE = 120.0

# Prop size (x, y, z) from data/environment/props (the collision box).
SIZES = {"car": (1.8, 1.5, 4.5), "bus": (2.5, 3.2, 12.0), "lamppost": (0.3, 6.0, 0.3), "traffic_light": (0.35, 5.5, 0.35),
         "bus_stop": (3.0, 2.5, 1.5), "bench": (1.8, 0.8, 0.6), "fence": (2.0, 1.2, 0.1), "hydrant": (0.4, 0.8, 0.4),
         "tree": (0.5, 7.0, 0.5), "person": (0.5, 1.8, 0.5)}

# Colors: (r, g, b, metallic, roughness, emission)
PAINT = {"red": (0.55, 0.1, 0.08, 0.5, 0.35, 0), "blue": (0.1, 0.2, 0.45, 0.5, 0.35, 0), "white": (0.8, 0.8, 0.78, 0.5, 0.35, 0),
         "grey": (0.35, 0.36, 0.38, 0.5, 0.35, 0), "glass": (0.06, 0.08, 0.1, 0.3, 0.1, 0), "tire": (0.05, 0.05, 0.05, 0.0, 0.9, 0),
         "pole": (0.25, 0.27, 0.28, 0.6, 0.5, 0), "lamp": (1.0, 0.9, 0.7, 0.0, 0.5, 2.0), "bus": (0.75, 0.55, 0.1, 0.4, 0.4, 0),
         "wood": (0.4, 0.27, 0.15, 0.0, 0.85, 0), "hydrant": (0.7, 0.1, 0.06, 0.3, 0.5, 0), "bark": (0.25, 0.18, 0.12, 0.0, 0.95, 0),
         "leaves": (0.18, 0.3, 0.12, 0.0, 0.9, 0), "shirt_a": (0.2, 0.3, 0.5, 0.0, 0.9, 0), "shirt_b": (0.5, 0.25, 0.2, 0.0, 0.9, 0),
         "sig_red": (0.9, 0.1, 0.05, 0.0, 0.5, 2.0), "sig_amber": (0.4, 0.3, 0.05, 0.0, 0.5, 0), "sig_green": (0.05, 0.3, 0.1, 0.0, 0.5, 0),
         "shelter_glass": (0.5, 0.6, 0.65, 0.2, 0.1, 0)}


def box(size, pos, paint):
    return ("BoxMesh", f"size = Vector3({size[0]}, {size[1]}, {size[2]})", pos, paint, (0, 0, 0))


def cyl(radius, height, pos, paint, rot=(0, 0, 0), top=None):
    return ("CylinderMesh", f"top_radius = {top if top is not None else radius}\nbottom_radius = {radius}\nheight = {height}\nradial_segments = 12",
            pos, paint, rot)


def sphere(radius, pos, paint):
    return ("SphereMesh", f"radius = {radius}\nheight = {radius * 2}\nradial_segments = 12\nrings = 6", pos, paint, (0, 0, 0))


def capsule(radius, height, pos, paint):
    return ("CapsuleMesh", f"radius = {radius}\nheight = {height}\nradial_segments = 10\nrings = 4", pos, paint, (0, 0, 0))


def wheels(x, z_list, r=0.35, w=0.25):
    return [cyl(r, w, (sx * x, r, z), "tire", (0, 0, 90)) for sx in (-1, 1) for z in z_list]


def car(paint):
    return [box((1.8, 0.75, 4.5), (0, 0.6, 0), paint), box((1.6, 0.6, 2.3), (0, 1.25, 0.2), paint),
            box((1.62, 0.42, 2.0), (0, 1.27, 0.2), "glass")] + wheels(0.8, (-1.4, 1.4))


MODELS = {
    "car": car("red"), "car_blue": car("blue"), "car_white": car("white"), "car_grey": car("grey"),
    "bus": [box((2.5, 2.6, 12.0), (0, 1.75, 0), "bus"), box((2.52, 0.9, 10.6), (0, 2.3, 0.4), "glass"),
            box((2.52, 1.0, 0.1), (0, 2.1, -6.0), "glass")] + wheels(1.1, (-4.0, 3.8), 0.5, 0.35),
    "lamppost": [cyl(0.12, 6.0, (0, 3.0, 0), "pole", top=0.08), box((0.1, 0.1, 1.6), (0, 5.9, -0.75), "pole"),
                 box((0.35, 0.15, 0.6), (0, 5.8, -1.45), "lamp")],
    "traffic_light": [cyl(0.15, 5.5, (0, 2.75, 0), "pole", top=0.12), box((0.12, 0.12, 4.0), (0, 5.3, -2.0), "pole"),
                      box((0.4, 1.0, 0.35), (0, 4.75, -3.7), "pole"), sphere(0.11, (0, 5.05, -3.9), "sig_red"),
                      sphere(0.11, (0, 4.75, -3.9), "sig_amber"), sphere(0.11, (0, 4.45, -3.9), "sig_green")],
    "bus_stop": [box((3.0, 0.1, 1.5), (0, 2.45, 0), "pole"), box((3.0, 2.2, 0.05), (0, 1.25, 0.7), "shelter_glass"),
                 box((0.08, 2.4, 0.08), (-1.45, 1.2, 0.65), "pole"), box((0.08, 2.4, 0.08), (1.45, 1.2, 0.65), "pole"),
                 box((2.0, 0.08, 0.4), (0, 0.45, 0.45), "wood")],
    "bench": [box((1.8, 0.08, 0.45), (0, 0.45, 0), "wood"), box((1.8, 0.4, 0.06), (0, 0.72, 0.22), "wood"),
              box((0.08, 0.45, 0.45), (-0.8, 0.22, 0), "pole"), box((0.08, 0.45, 0.45), (0.8, 0.22, 0), "pole")],
    "fence": [box((0.08, 1.2, 0.08), (-0.96, 0.6, 0), "pole"), box((0.08, 1.2, 0.08), (0.96, 0.6, 0), "pole")]
             + [box((2.0, 0.06, 0.05), (0, y, 0), "pole") for y in (0.3, 0.7, 1.1)],
    "hydrant": [cyl(0.17, 0.65, (0, 0.33, 0), "hydrant"), sphere(0.17, (0, 0.66, 0), "hydrant"),
                cyl(0.06, 0.45, (0, 0.45, 0), "hydrant", (0, 0, 90))],
    "tree": [cyl(0.2, 3.4, (0, 1.7, 0), "bark", top=0.14), sphere(2.0, (0, 4.9, 0), "leaves"),
             sphere(1.4, (0.5, 6.0, 0.3), "leaves")],
    "person": [capsule(0.25, 1.8, (0, 0.9, 0), "shirt_a"), sphere(0.12, (0, 1.68, 0), "wood")],
    "person_b": [capsule(0.23, 1.75, (0, 0.875, 0), "shirt_b"), sphere(0.12, (0, 1.63, 0), "wood")],
}
DEF_OF = {"car_blue": "car", "car_white": "car", "car_grey": "car", "person_b": "person"}


def rot_basis(rot):
    import math
    rx, ry, rz = (math.radians(a) for a in rot)
    if rz:
        c, s = math.cos(rz), math.sin(rz)
        return f"{c:.4f}, {s:.4f}, 0, {-s:.4f}, {c:.4f}, 0, 0, 0, 1"
    return "1, 0, 0, 0, 1, 0, 0, 0, 1"


def scene(name, parts):
    def_name = DEF_OF.get(name, name)
    size = SIZES[def_name]
    paints = sorted({p[3] for p in parts})
    lines = ['[gd_scene format=3]', '',
             '[ext_resource type="Script" path="res://scripts/environment/urban_prop.gd" id="prop"]',
             f'[ext_resource type="Resource" path="res://data/environment/props/{def_name}.tres" id="def"]', '']
    for p in paints:
        r, g, b, metal, rough, emit = PAINT[p]
        lines += [f'[sub_resource type="StandardMaterial3D" id="m_{p}"]', f'albedo_color = Color({r}, {g}, {b}, 1)',
                  f'metallic = {metal}', f'roughness = {rough}']
        if emit:
            lines += ['emission_enabled = true', f'emission = Color({r}, {g}, {b}, 1)', f'emission_energy_multiplier = {emit}']
        lines.append('')
    for i, (kind, params, pos, paint, rot) in enumerate(parts):
        lines += [f'[sub_resource type="{kind}" id="mesh{i}"]', f'material = SubResource("m_{paint}")', params, '']
    lines += ['[sub_resource type="BoxShape3D" id="shape"]', f'size = Vector3({size[0]}, {size[1]}, {size[2]})', '',
              '[sub_resource type="BoxShape3D" id="contact"]',
              f'size = Vector3({size[0] + 0.6}, {size[1] + 0.4}, {size[2] + 0.6})', '']
    root = "".join(w.capitalize() for w in name.split("_"))
    lines += [f'[node name="{root}" type="StaticBody3D"]', f'collision_layer = {PROP_LAYER}', 'collision_mask = 0',
              'script = ExtResource("prop")', 'def = ExtResource("def")', '',
              '[node name="Shape" type="CollisionShape3D" parent="."]',
              f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {size[1] / 2}, 0)', 'shape = SubResource("shape")', '',
              '[node name="Pivot" type="Node3D" parent="."]', '']
    for i, (kind, params, pos, paint, rot) in enumerate(parts):
        lines += [f'[node name="Mesh{i}" type="MeshInstance3D" parent="Pivot"]',
                  f'transform = Transform3D({rot_basis(rot)}, {pos[0]}, {pos[1]}, {pos[2]})',
                  'gi_mode = 2', f'visibility_range_end = {FADE}', 'visibility_range_end_margin = 10.0',
                  'visibility_range_fade_mode = 1', f'mesh = SubResource("mesh{i}")', '']
    lines += ['[node name="Contact" type="Area3D" parent="."]', 'collision_layer = 0', f'collision_mask = {MECH_LAYER}',
              'monitorable = false', '',
              '[node name="Shape" type="CollisionShape3D" parent="Contact"]',
              f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {size[1] / 2}, 0)', 'shape = SubResource("contact")', '']
    full = os.path.join(ROOT, OUT, f"{name}.tscn")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write("\n".join(lines))


if __name__ == "__main__":
    for name, parts in MODELS.items():
        scene(name, parts)
    print("wrote", len(MODELS), "prop scenes")
