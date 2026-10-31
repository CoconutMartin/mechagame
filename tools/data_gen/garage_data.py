"""Garage data (Sanggigilid only since 2026-10-11): the Sanggigilid body parts, mods and
the garage catalog. The parts have no models (Sanggigilid is one rigged model); their HP sets the
part HP of the matching body parts (MechHealth hit keys, see SkeletalWeaponMount), their other
values feed the garage stat panel.
Run from the project root: python3 tools/data_gen/garage_data.py"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SCRIPT = {
    "head": ("HeadPart", "head_part"), "core": ("CorePart", "core_part"), "arm_l": ("ArmPart", "arm_part"),
    "arm_r": ("ArmPart", "arm_part"), "legs": ("LegPart", "leg_part"), "booster": ("BoosterPart", "booster_part"),
    "generator": ("GeneratorPart", "generator_part"),
}
LABEL = {"head": "Head", "core": "Core", "arm_l": "Arm L", "arm_r": "Arm R", "legs": "Legs",
         "booster": "Booster", "generator": "Generator"}

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
}

# Back packs (user decision 2026-10-31, replace the FCS slot): file, name, weight, HP, aux slots,
# bonus (BackPackPart.Bonus: 1 energy, 2 HP, 3 boost), bonus percent.
BACK_PACKS = [
    ("backpack_light", "Light Pack", 0.4, 120.0, 1, 3, 6.0),
    ("backpack_medium", "Aux Pack", 0.8, 200.0, 2, 1, 10.0),
    ("backpack_heavy", "Heavy Pack", 1.6, 320.0, 3, 2, 5.0),
    # Ammo Pack (user picture 2026-10-31): no aux slot, no bonus, six ammo canisters (ammo_canisters, written below).
    ("backpack_ammo", "Ammo Pack", 2.4, 260.0, 0, 0, 0.0),
    # Missile Pack (user picture 2026-10-31): four canisters for missile pods only (canister_kinds, written below).
    ("backpack_missile", "Missile Pack", 2.2, 240.0, 0, 0, 0.0),
    # Boost Pack (user picture 2026-10-31): four winged grilles (the boost outlets), one aux slot, boost +12%.
    ("backpack_boost", "Boost Pack", 1.4, 240.0, 1, 3, 12.0),
    # Quad Booster (user picture 2026-10-31): four thruster pods with big nozzles, one aux slot, boost +18%.
    ("backpack_quad", "Quad Booster", 2.0, 280.0, 1, 3, 18.0),
    # Belt Pack (user picture 2026-10-31, "ballistic support"): an ammo belt, 8 canisters for guns only, 1 aux slot.
    ("backpack_belt", "Belt Pack", 2.6, 300.0, 1, 0, 0.0),
    # Power Pack (user picture 2026-10-31, "energy support"): battery cells, 1 aux slot, energy capacity +25%.
    ("backpack_power", "Power Pack", 1.8, 260.0, 1, 1, 25.0),
    # Field Pack (user picture 2026-10-31): a box between two handled pods, 2 aux slots, part HP +6%.
    ("backpack_field", "Field Pack", 1.6, 340.0, 2, 2, 6.0),
    # Jet Pack (user picture 2026-10-31): a light booster with two big nozzles, 1 aux slot, boost +10%.
    ("backpack_jet", "Jet Pack", 1.0, 200.0, 1, 3, 10.0),
    # Drone Pack (user picture 2026-10-31): two big discs on the sides (Drone1..2, attack drones later), 1 aux slot,
    # no bonus yet.
    ("backpack_drone", "Drone Pack", 2.2, 300.0, 1, 0, 0.0),
]
## Ammo canisters per pack (BackPackPart.ammo_canisters); packs not listed carry none.
AMMO_CANISTERS = {"backpack_ammo": 6, "backpack_missile": 4, "backpack_belt": 8}
## Weapon kinds a pack's canisters fit (WeaponData.Kind; 3 = missile pod); packs not listed fit every ammo weapon.
CANISTER_KINDS = {"backpack_missile": [3], "backpack_belt": [0]}

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
    if isinstance(v, list):
        return "Array[int]([%s])" % ", ".join(str(x) for x in v)
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
        fields.update({k: (float(x) if isinstance(x, (int, float)) and k != "leg_type" else x)
                       for k, x in stats.items()})
        parts[part].append(write(f"data/parts/sanggigilid/sanggigilid_{part}.tres", cls, script, fields))
    back_packs = [write(f"data/parts/backpacks/{f}.tres", "BackPackPart", "back_pack_part",
                        dict({"display_name": n, "weight_t": w, "hp": hp, "aux_slots": slots, "bonus": b, "bonus_percent": pc},
                             **({"ammo_canisters": AMMO_CANISTERS[f]} if f in AMMO_CANISTERS else {}),
                             **({"canister_kinds": CANISTER_KINDS[f]} if f in CANISTER_KINDS else {})),
                        scene=f"res://models/backpacks/{f}.glb")
                  for f, n, w, hp, slots, b, pc in BACK_PACKS]
    mods = [write(f"data/mods/{f}.tres", "ModData", "mod_data", {"display_name": n, "stat": s, "percent": p})
            for f, n, s, p in MODS]
    weapons = {
        "weapons_right": ["heavy_rifle", "beam_rifle", "beam_sniper", "pile_bunker", "pile_bunker_2", "pile_bunker_3", "pile_bunker_4", "pile_bunker_5", "auto_cannon", "smg", "shotgun",
                          "fist", "hammer", "baton"],
        # Left hand (user rules 2026-10-15): shields, one-hand guns, the Pile Bunker and the Fist.
        "weapons_left": ["warden_shield", "small_shield", "smg", "shotgun", "auto_cannon", "pile_bunker", "pile_bunker_2", "pile_bunker_3", "pile_bunker_4", "pile_bunker_5", "fist"],
        "backs_left": ["missile_pod_l", "auto_cannon_shoulder"],
        "backs_right": ["missile_pod_r", "auto_cannon_shoulder"],
    }
    lists = {"heads": parts["head"], "cores": parts["core"], "arms_left": parts["arm_l"],
             "arms_right": parts["arm_r"], "legs": parts["legs"], "boosters": parts["booster"],
             "generators": parts["generator"], "back_packs": back_packs}
    for key, names in weapons.items():
        lists[key] = [f"res://data/weapons/{n}.tres" for n in names]
    lists["mods"] = mods
    # Aux equipment for the back pack's aux slot (user 2026-10-31: pulse scans and drone mods, interchangeable).
    lists["aux_items"] = [f"res://data/equipment/{n}.tres" for n in
                          ["pulse_scan_g1", "pulse_scan_g2", "pulse_scan_g3", "drone_recall", "drone_swarm"]]
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
             "legs": "LegPart", "boosters": "BoosterPart", "generators": "GeneratorPart", "back_packs": "BackPackPart",
             "weapons_right": "WeaponData", "weapons_left": "WeaponData", "backs_left": "WeaponData",
             "backs_right": "WeaponData", "mods": "ModData", "aux_items": "EquipmentData"}
    lines += ["", "[resource]", 'script = ExtResource("script")']
    for key, paths in lists.items():
        items = ", ".join(f'ExtResource("{ids[p]}")' for p in paths)
        lines.append(f"{key} = Array[{types[key]}]([{items}])")
    with open(os.path.join(ROOT, "data/garage_catalog.tres"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote data/garage_catalog.tres")


if __name__ == "__main__":
    main()
