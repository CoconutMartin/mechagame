"""Mech name list (user list 2026-10-14) -> data/names/mech_names.tres (MechNameCatalog).
Reads the tables in docs/mech_names.md. Run from the project root: python3 tools/data_gen/mech_names.py"""
import re

SECTIONS = {"Status classes": "STATUS_CLASS", "Gods and deities": "DEITY", "Epic heroes": "EPIC_HERO",
            "Folklore creatures": "FOLKLORE", "Animals": "ANIMAL", "Weapons, armor, charms": "WEAPON",
            "Vessels and forts": "VESSEL", "Nature and weather": "NATURE", "Roles and trades": "ROLE"}
GROUPS = ["STATUS_CLASS", "DEITY", "EPIC_HERO", "FOLKLORE", "ANIMAL", "WEAPON", "VESSEL", "NATURE", "ROLE"]
WEIGHT = {"L": 0, "M": 1, "H": 2}


def q(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    group = None
    rows = []
    for line in open("docs/mech_names.md", encoding="utf-8"):
        head = re.match(r"### \d+\. (.+?) \(\d+\)", line)
        if head:
            group = SECTIONS[head.group(1)]
            columns = None
            continue
        if line.startswith("### "):
            group = None
        if group is None or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == "Name":
            columns = cells
            continue
        if set(cells[0]) <= set("-"):
            continue
        row = dict(zip(columns, cells))
        rows.append({"name": row["Name"], "group": group, "weight": WEIGHT[row["Class"]], "code": row["Code"],
                     "origin": row.get("Origin", ""), "meaning": row["Meaning"], "fit": row.get("Fit", ""),
                     "source": row.get("Home", row.get("Size", ""))})
    codes = [r["code"] for r in rows]
    assert len(codes) == len(set(codes)), "duplicate codes"
    out = ['[gd_resource type="Resource" script_class="MechNameCatalog" format=3]\n',
           '[ext_resource type="Script" path="res://scripts/data/mech_name_catalog.gd" id="catalog"]',
           '[ext_resource type="Script" path="res://scripts/data/mech_name.gd" id="name"]\n']
    for i, r in enumerate(rows):
        out.append(f'[sub_resource type="Resource" id="n{i}"]\nscript = ExtResource("name")\nname = {q(r["name"])}\n'
                   f'group = {GROUPS.index(r["group"])}\nweight_class = {r["weight"]}\ncode = {q(r["code"])}\n'
                   f'origin = {q(r["origin"])}\nmeaning = {q(r["meaning"])}\nfit = {q(r["fit"])}\n'
                   f'number_source = {q(r["source"])}\n')
    refs = ", ".join(f'SubResource("n{i}")' for i in range(len(rows)))
    out.append('[resource]\nscript = ExtResource("catalog")\n'
               f'names = Array[ExtResource("name")]([{refs}])\n')
    open("data/names/mech_names.tres", "w", encoding="utf-8").write("\n".join(out))
    print("wrote data/names/mech_names.tres:", len(rows), "names")


if __name__ == "__main__":
    main()
