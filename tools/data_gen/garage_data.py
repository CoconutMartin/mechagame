"""Phase 5 garage data: light (Kestrel) and heavy (Bulwark) part variants, armor plates, mods and
the garage catalog. The medium parts are the Warden parts (data/parts/warden).
The variants use the Warden models with a model scale and an armor tint (PartLook).
Run from the project root: python3 tools/data_gen/garage_data.py"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SCRIPT = {
    "head": ("HeadPart", "head_part"), "core": ("CorePart", "core_part"), "arm_l": ("ArmPart", "arm_part"),
    "arm_r": ("ArmPart", "arm_part"), "legs": ("LegPart", "leg_part"), "booster": ("BoosterPart", "booster_part"),
    "generator": ("GeneratorPart", "generator_part"), "fcs": ("FcsPart", "fcs_part"),
}
HAS_SCENE = {"head", "core", "arm_l", "arm_r", "legs", "booster"}

# Variant: name, folder, armor tint, model scale by part (x, y, z).
VARIANTS = {
    "kestrel": {
        "name": "Kestrel", "tint": (1.18, 1.06, 0.82, 1.0),
        "scale": {"head": (0.9, 0.9, 0.9), "core": (0.9, 1.0, 0.9), "arm": (0.85, 1.0, 0.85),
                  "legs": (0.85, 1.0, 0.85), "booster": (0.85, 0.85, 0.85)},
        "stats": {
            "head": dict(weight_t=2.5, hp=280, sensor_range=700, lock_on_speed=1.25),
            "core": dict(weight_t=13, hp=1200, energy_capacity=90, torso_turn_speed_deg=100),
            "arm": dict(weight_t=3.5, hp=450, recoil_control=1.2, melee_bonus=0.9),
            "legs": dict(weight_t=11, hp=1000, leg_type=0, load_capacity_t=65, base_speed=13.5,
                         jump_height=11, turn_speed_deg=135, turn_speed_standing_deg=67.5),
            "booster": dict(weight_t=2, hp=150, thrust=1000, boost_speed_multiplier=1.6, energy_per_second=26),
            "generator": dict(weight_t=2, hp=150, energy_output=14, recharge_delay=1.6),
            "fcs": dict(weight_t=0.5, hp=80, lock_range=400, max_locks=3, aim_assist=0.0),
        },
    },
    "bulwark": {
        "name": "Bulwark", "tint": (0.66, 0.74, 0.64, 1.0),
        "scale": {"head": (1.15, 1.1, 1.15), "core": (1.12, 1.0, 1.12), "arm": (1.18, 1.0, 1.18),
                  "legs": (1.15, 1.0, 1.15), "booster": (1.2, 1.2, 1.2)},
        "stats": {
            "head": dict(weight_t=6, hp=560, sensor_range=500, lock_on_speed=0.85),
            "core": dict(weight_t=24, hp=2100, energy_capacity=120, torso_turn_speed_deg=70),
            "arm": dict(weight_t=7, hp=800, recoil_control=0.8, melee_bonus=1.25),
            "legs": dict(weight_t=22, hp=1900, leg_type=0, load_capacity_t=105, base_speed=10.2,
                         jump_height=7, turn_speed_deg=95, turn_speed_standing_deg=47.5),
            "booster": dict(weight_t=4.5, hp=280, thrust=1600, boost_speed_multiplier=1.45, energy_per_second=38),
            "generator": dict(weight_t=4.5, hp=280, energy_output=22, recharge_delay=2.4),
            "fcs": dict(weight_t=2, hp=150, lock_range=650, max_locks=6, aim_assist=0.0),
        },
    },
}
LABEL = {"head": "Head", "core": "Core", "arm_l": "Arm L", "arm_r": "Arm R", "legs": "Legs",
         "booster": "Booster", "generator": "Generator", "fcs": "FCS"}

# Recon (custom Blender model, models/recon): slim sensor mech between Kestrel and Warden.
# The generator and FCS have no model. The other parts use the .glb files and materials/recon.
RECON = {
    "head": dict(weight_t=3.0, hp=320, sensor_range=900, lock_on_speed=1.35),
    "core": dict(weight_t=15.0, hp=1350, energy_capacity=105, torso_turn_speed_deg=95),
    "arm_l": dict(weight_t=4.0, hp=500, recoil_control=1.0, melee_bonus=0.95),
    "arm_r": dict(weight_t=4.0, hp=500, recoil_control=1.0, melee_bonus=0.95),
    "legs": dict(weight_t=13.0, hp=1150, leg_type=0, load_capacity_t=72, base_speed=12.8,
                 jump_height=10.5, turn_speed_deg=128, turn_speed_standing_deg=64),
    "booster": dict(weight_t=2.5, hp=170, thrust=1150, boost_speed_multiplier=1.6, energy_per_second=28),
    "fcs": dict(weight_t=1.0, hp=100, lock_range=620, max_locks=5, aim_assist=0.0),
}

# Plates: file, name, slot (0 head, 1 core, 2 arm L, 3 arm R, 4 legs), HP, weight, thickness.
PLATES = [
    ("head_plate_light", "Head Plate (light)", 0, 80, 0.5, 0.16),
    ("head_plate_heavy", "Head Plate (heavy)", 0, 150, 1.0, 0.28),
    ("core_plate_light", "Core Plate (light)", 1, 300, 2.0, 0.18),
    ("core_plate_heavy", "Core Plate (heavy)", 1, 550, 4.0, 0.32),
    ("arm_l_plate_light", "Arm L Plate (light)", 2, 120, 0.8, 0.16),
    ("arm_l_plate_heavy", "Arm L Plate (heavy)", 2, 220, 1.5, 0.28),
    ("arm_r_plate_light", "Arm R Plate (light)", 3, 120, 0.8, 0.16),
    ("arm_r_plate_heavy", "Arm R Plate (heavy)", 3, 220, 1.5, 0.28),
    ("leg_plate_light", "Leg Plate (light)", 4, 250, 2.0, 0.18),
    ("leg_plate_heavy", "Leg Plate (heavy)", 4, 450, 3.5, 0.32),
]
# Mods: file, name, stat (ModData.Stat), percent.
# Stat: 0 weight, 1 speed, 2 boost thrust, 3 energy capacity, 4 energy output, 5 turn speed,
# 6 jump height, 7 part HP, 8 recoil.
MODS = [
    ("boost_tuning", "Boost Tuning (+10% thrust)", 2, 10.0),
    ("lightweight_frame", "Lightweight Frame (-5% weight)", 0, -5.0),
    ("reinforced_frame", "Reinforced Frame (+8% part HP)", 7, 8.0),
    ("capacitor_bank", "Capacitor Bank (+15% energy)", 3, 15.0),
    ("overclocked_generator", "Overclocked Generator (+15% recharge)", 4, 15.0),
    ("servo_tuning", "Servo Tuning (+10% turn speed)", 5, 10.0),
    ("recoil_dampers", "Recoil Dampers (-15% recoil)", 8, -15.0),
    ("jump_jet_tuning", "Jump Jet Tuning (+15% jump)", 6, 15.0),
]


def value(v):
    if isinstance(v, str):
        return f'"{v}"'
    if isinstance(v, tuple) and len(v) == 3:
        return "Vector3(%s, %s, %s)" % v
    if isinstance(v, tuple):
        return "Color(%s, %s, %s, %s)" % v
    if isinstance(v, float):
        return repr(v)
    return str(v)


def write(path, cls, script, fields, scene=None):
    lines = [f'[gd_resource type="Resource" script_class="{cls}" format=3]', "",
             f'[ext_resource type="Script" path="res://scripts/data/{script}.gd" id="script"]']
    if scene:
        lines.append(f'[ext_resource type="PackedScene" path="{scene}" id="scene"]')
    # A ("resource", path) field is a link to another resource file.
    links = {k: v[1] for k, v in fields.items() if isinstance(v, tuple) and v and v[0] == "resource"}
    for k, link in links.items():
        lines.append(f'[ext_resource type="Resource" path="{link}" id="{k}"]')
    lines += ["", "[resource]", 'script = ExtResource("script")']
    lines += [f'{k} = ExtResource("{k}")' if k in links else f"{k} = {value(v)}" for k, v in fields.items()]
    if scene:
        lines.append('scene = ExtResource("scene")')
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", path)
    return "res://" + path


def main():
    parts = {k: [] for k in SCRIPT}
    for part in SCRIPT:
        parts[part].append(f"res://data/parts/warden/warden_{part}.tres")
    for folder, v in VARIANTS.items():
        for part, (cls, script) in SCRIPT.items():
            group = "arm" if part.startswith("arm") else part
            fields = {"display_name": f"{v['name']} {LABEL[part]}"}
            fields.update({k: (float(x) if isinstance(x, (int, float)) and k not in ("leg_type", "max_locks") else x)
                           for k, x in v["stats"][group].items()})
            scene = None
            if part in HAS_SCENE:
                scene = f"res://scenes/parts/warden/warden_{part}.tscn"
                fields["model_scale"] = tuple(float(x) for x in v["scale"][group])
                fields["armor_tint"] = v["tint"]
            parts[part].append(write(f"data/parts/{folder}/{folder}_{part}.tres", cls, script, fields, scene))
    # Recon (boxy first model), Recon Accurate (closer to the reference), Recon Sleek (smooth, slim
    # version), Recon Gen (Hunyuan3D model split by split_generated.py) and Recon Sheet (from the
    # user's part sheet): same stats.
    for folder, title in (("recon", "Recon"), ("recon_accurate", "Recon Accurate"), ("recon_sleek", "Recon Sleek"),
                          ("recon_gen", "Recon Gen"), ("recon_sheet", "Recon Sheet")):
        for part, stats in RECON.items():
            if folder != "recon" and part == "fcs":
                continue  # The FCS has no model: the later Recons use the Recon FCS.
            cls, script = SCRIPT[part]
            fields = {"display_name": f"{title} {LABEL[part]}"}
            fields.update({k: (float(x) if isinstance(x, (int, float)) and k not in ("leg_type", "max_locks") else x)
                           for k, x in stats.items()})
            scene = None
            if part in HAS_SCENE:
                scene = f"res://models/{folder}/{folder}_{part}.glb"
                # Recon Gen and Recon Sheet have their own olive colors; the others use the Recon colors.
                fields["material_library"] = {"recon_gen": "res://materials/recon_gen",
                                              "recon_sheet": "res://materials/recon_sheet"}.get(folder, "res://materials/recon")
                # Recon Sheet has its own joint layout (measured from models/guides/recon_sheet_views.png).
                if folder == "recon_sheet" and part in ("core", "arm_l", "arm_r", "legs"):
                    fields["frame"] = ("resource", "res://data/frames/recon_sheet_frame.tres")
            parts[part].append(write(f"data/parts/{folder}/{folder}_{part}.tres", cls, script, fields, scene))
    # Medium (user parts, rigged in Blender, game parts from tools/blender/medium_mech_build.py): the data
    # files are written by hand (Warden stats, Recon Sheet booster stats), so only list them here.
    for part in ("head", "core", "arm_l", "arm_r", "legs", "booster"):
        parts[part].append(f"res://data/parts/medium_mech/medium_mech_{part}.tres")
    plates = [write(f"data/plates/{f}.tres", "PlateData", "plate_data",
                    {"display_name": n, "slot": s, "hp": float(hp), "weight_t": float(w), "thickness": float(t)})
              for f, n, s, hp, w, t in PLATES]
    mods = [write(f"data/mods/{f}.tres", "ModData", "mod_data", {"display_name": n, "stat": s, "percent": p})
            for f, n, s, p in MODS]
    weapons = {
        "weapons_right": ["heavy_rifle", "beam_sniper", "pile_bunker"],
        "weapons_left": ["warden_shield"],
        "backs_left": ["missile_pod_l"],
        "backs_right": ["missile_pod_r"],
    }
    lists = {"heads": parts["head"], "cores": parts["core"], "arms_left": parts["arm_l"],
             "arms_right": parts["arm_r"], "legs": parts["legs"], "boosters": parts["booster"],
             "generators": parts["generator"], "fcs": parts["fcs"]}
    for key, names in weapons.items():
        lists[key] = [f"res://data/weapons/{n}.tres" for n in names]
    lists["plates"] = plates
    lists["mods"] = mods
    # Catalog: every resource once as an ext_resource, then the typed arrays.
    ids = {}
    lines = ['[gd_resource type="Resource" script_class="GarageCatalog" format=3]', "",
             '[ext_resource type="Script" path="res://scripts/data/garage_catalog.gd" id="script"]']
    for paths in lists.values():
        for p in paths:
            if p not in ids:
                ids[p] = f"r{len(ids)}"
                lines.append(f'[ext_resource type="Resource" path="{p}" id="{ids[p]}"]')
    types = {"heads": "HeadPart", "cores": "CorePart", "arms_left": "ArmPart", "arms_right": "ArmPart",
             "legs": "LegPart", "boosters": "BoosterPart", "generators": "GeneratorPart", "fcs": "FcsPart",
             "weapons_right": "WeaponData", "weapons_left": "WeaponData", "backs_left": "WeaponData",
             "backs_right": "WeaponData", "plates": "PlateData", "mods": "ModData"}
    lines += ["", "[resource]", 'script = ExtResource("script")']
    for key, paths in lists.items():
        items = ", ".join(f'ExtResource("{ids[p]}")' for p in paths)
        lines.append(f"{key} = Array[{types[key]}]([{items}])")
    with open(os.path.join(ROOT, "data/garage_catalog.tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote data/garage_catalog.tres")


if __name__ == "__main__":
    main()
