"""Sanggigilid test loadout (key 1 in the urban map). Run from the project root:
    python3 tools/data_gen/loadouts.py
They have no mech_scene: the map's LoadoutSwitcher builds Sanggigilid (its mech_scene) for them."""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
PARTS = ["head", "core", "arm_left", "arm_right", "legs", "booster", "generator", "fcs"]
PART_FILE = {"arm_left": "arm_l", "arm_right": "arm_r"}
LOADOUTS = [
    # The only test loadout (user, 2026-10-13: key 1; the user picks other equipment in the garage).
    ("sanggigilid_beam_rifle", "SGG-101 Sagigilid Beam Rifle", {"weapon_right": "beam_rifle"}),
]


def main():
    os.makedirs(os.path.join(ROOT, "data/loadouts"), exist_ok=True)
    for name, title, weapons in LOADOUTS:
        lines = ['[gd_resource type="Resource" script_class="Loadout" format=3]', "",
                 '[ext_resource type="Script" path="res://scripts/data/loadout.gd" id="script"]']
        for part in PARTS:
            lines.append(f'[ext_resource type="Resource" path="res://data/parts/sanggigilid/sanggigilid_'
                         f'{PART_FILE.get(part, part)}.tres" id="{part}"]')
        files = sorted(set(weapons.values()))
        for f in files:
            lines.append(f'[ext_resource type="Resource" path="res://data/weapons/{f}.tres" id="{f}"]')
        lines += ["", "[resource]", 'script = ExtResource("script")', f'display_name = "{title}"']
        lines += [f'{part} = ExtResource("{part}")' for part in PARTS]
        lines += [f'{slot} = ExtResource("{f}")' for slot, f in weapons.items()]
        with open(os.path.join(ROOT, f"data/loadouts/{name}.tres"), "w") as out:
            out.write("\n".join(lines) + "\n")
        print("wrote", name)


if __name__ == "__main__":
    main()
