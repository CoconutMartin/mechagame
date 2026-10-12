"""Garage data (Sanggigilid only since 2026-10-11): the Sanggigilid body parts, armor plates, mods and
the garage catalog. The parts have no models (Sanggigilid is one rigged model); their HP sets the
part HP of the matching body parts (MechHealth hit keys, see SkeletalWeaponMount), their other
values feed the garage stat panel.
Run from the project root: python3 tools/data_gen/garage_data.py"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SCRIPT = {
    "head": ("HeadPart", "head_part"), "core": ("CorePart", "core_part"), "arm_l": ("ArmPart", "arm_part"),
    "arm_r": ("ArmPart", "arm_part"), "legs": ("LegPart", "leg_part"), "booster": ("BoosterPart", "booster_part"),
    "generator": ("GeneratorPart", "generator_part"), "fcs": ("FcsPart", "fcs_part"),
}
LABEL = {"head": "Head", "core": "Core", "arm_l": "Arm L", "arm_r": "Arm R", "legs": "Legs",
         "booster": "Booster", "generator": "Generator", "fcs": "FCS"}

# Sanggigilid parts (values of the removed Warden parts; HP = the body part HP the mech had:
# head 400, core 1600 = center torso 960 + side torsos 640 each, arms 600, legs 1400 = groin 560 +
# legs 840 each).
SANGGIGILID = {
    "head": dict(weight_t=4.0, hp=400, sensor_range=600, lock_on_speed=1.0),
    "core": dict(weight_t=18.0, hp=1600, energy_capacity=100, torso_turn_speed_deg=85.35),
    "arm_l": dict(weight_t=5.0, hp=600, recoil_control=1.0, melee_bonus=1.0),
    "arm_r": dict(weight_t=5.0, hp=600, recoil_control=1.0, melee_bonus=1.0),
    "legs": dict(weight_t=16.0, hp=1400, leg_type=0, load_capacity_t=80, base_speed=11.742, jump_height=9,
                 turn_speed_deg=116.1, turn_speed_standing_deg=58.05),
    "booster": dict(weight_t=3.0, hp=200, thrust=1200, boost_speed_multiplier=1.5, energy_per_second=30),
    "generator": dict(weight_t=3.0, hp=200, energy_output=17.5, recharge_delay=2.0),
    "fcs": dict(weight_t=1.0, hp=100, lock_range=500, max_locks=4, aim_assist=0.0),
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
    for part, stats in SANGGIGILID.items():
        cls, script = SCRIPT[part]
        fields = {"display_name": f"Sanggigilid {LABEL[part]}"}
        fields.update({k: (float(x) if isinstance(x, (int, float)) and k not in ("leg_type", "max_locks") else x)
                       for k, x in stats.items()})
        parts[part].append(write(f"data/parts/sanggigilid/sanggigilid_{part}.tres", cls, script, fields))
    plates = [write(f"data/plates/{f}.tres", "PlateData", "plate_data",
                    {"display_name": n, "slot": s, "hp": float(hp), "weight_t": float(w), "thickness": float(t)})
              for f, n, s, hp, w, t in PLATES]
    mods = [write(f"data/mods/{f}.tres", "ModData", "mod_data", {"display_name": n, "stat": s, "percent": p})
            for f, n, s, p in MODS]
    weapons = {
        "weapons_right": ["heavy_rifle", "beam_rifle", "beam_sniper", "pile_bunker", "auto_cannon", "smg"],
        "weapons_left": ["warden_shield", "small_shield"],
        "backs_left": ["missile_pod_l", "auto_cannon_shoulder"],
        "backs_right": ["missile_pod_r", "auto_cannon_shoulder"],
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
