"""Reads a MechFrame file (data/frames/<name>.tres, see scripts/data/mech_frame.gd) for the Blender
tools, so a Blender kit uses the same joint places as the game.
    values = read("data/frames/recon_sheet_frame.tres")
    sockets, pivots = layout(values)   # same form as SOCKETS and PIVOTS in mech_kit.py
Game space: x right, y up (feet at 0), -z forward, meters. Missing values use the OG layout."""
import os, re

OG = {"hip_height": 5.2, "hip_width": 1.5, "thigh_length": 2.6, "shin_length": 2.05, "torso_above_hip": 0.2,
      "shoulder_width": 2.465, "shoulder_height": 2.465, "upper_arm_length": 2.295, "forearm_length": 2.55}
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def read(path):
    values = dict(OG)
    if path:
        full = path if os.path.isabs(path) else os.path.join(ROOT, path.replace("res://", ""))
        for name, number in re.findall(r"^(\w+) = ([-0-9.e]+)$", open(full).read(), re.M):
            if name in values:
                values[name] = float(number)
    return values


def layout(v):
    hip, torso = v["hip_height"], v["hip_height"] + v["torso_above_hip"]
    shoulder = torso + v["shoulder_height"]
    knee, ankle = hip - v["thigh_length"], hip - v["thigh_length"] - v["shin_length"]
    sw, hw = v["shoulder_width"], v["hip_width"]
    sockets = {
        "Torso": (0.0, torso, 0.0), "Lower": (0.0, hip, 0.0),
        "ShoulderL": (-sw, shoulder, 0.0), "ShoulderR": (sw, shoulder, 0.0),
        "ElbowL": (-sw, shoulder - v["upper_arm_length"], 0.0), "ElbowR": (sw, shoulder - v["upper_arm_length"], 0.0),
        "HipL": (-hw, hip, 0.0), "HipR": (hw, hip, 0.0), "KneeL": (-hw, knee, 0.0), "KneeR": (hw, knee, 0.0),
    }
    pivots = {
        "arm_l": [("PauldronPivotL", "Torso", (-sw, shoulder, 0.0), 0.0)],
        "arm_r": [("PauldronPivotR", "Torso", (sw, shoulder, 0.0), 0.0)],
        "legs": [("FootPivotL", "KneeL", (-hw, ankle, 0.0), 0.0), ("FootPivotR", "KneeR", (hw, ankle, 0.0), 0.0)],
        # Booster flames keep their place on the torso (OG: 0.493 m above the waist joint).
        "booster": [("BoosterFlameL", "Torso", (-0.6375, torso + 0.493, 1.887), 25.0),
                    ("BoosterFlameR", "Torso", (0.6375, torso + 0.493, 1.887), 25.0)],
    }
    return sockets, pivots
