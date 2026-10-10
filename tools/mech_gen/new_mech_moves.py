"""Writes the start and stop clips of the new mech (SkeletalMoveClip resources) to data/mechs/new_mech_moves/:
run_start, run_stop (two feet), akira_right and akira_left. Run from the project root:
    python3 tools/mech_gen/new_mech_moves.py

The body speed of each frame is the speed made in Blender (tools/blender/new_mech_run_transitions.py:
the u() of each action, in m/frame there, m/s here). Footstep frames come from
models/new_mech/new_mech_markers.json. Run tools/godot/build_skeletal_mech.gd after this.
"""
import json
import os

FPS = 30.0
TRAVEL = 0.472  # m/frame: full run speed of biped_run_full (14.16 m/s)
FULL = TRAVEL * FPS
SCALE = 1.18  # hip height 5.90 / 5.0 (Blender brief scale)
OUT = "data/mechs/new_mech_moves"
MARKERS = "models/new_mech/new_mech_markers.json"


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smooth(x):
    return x * x * (3 - 2 * x)


def start_speed(f):
    """Still while crouching, then up to full speed by the right foot contact (frame 33)."""
    return 0.0 if f <= 4 else FULL * min(1.0, (f - 4) / (33 - 4))


def stop_speed(f):
    """Full until the brake (12), then falls evenly to 0 at frame 46."""
    return FULL * max(0.0, 1.0 - (f - 12) / 34.0) if f > 12 else FULL


def akira_speed(f):
    """Full until the wide foot plants (8). The feet skid while the body slows evenly to 0 at slide_end (30).
    Pivot steps in place, then 3 small steps (frames 52 to 92)."""
    if f <= 8:
        return FULL
    if f <= 30:
        return FULL * (30 - f) / 22.0
    if f <= 52:
        return 0.0
    walk = 0.11 * SCALE * FPS
    return walk * smooth(min(clamp01((f - 52) / 6.0), clamp01((92 - f) / 16.0)))


# file name: animation, frames, speed, extra fields
CLIPS = {
    "run_start": ("biped_run_start", 48, start_speed,
                  dict(blend_in=0.2, blend_out=0.12, ends_in_run="true", hold_hips="false")),
    "run_stop_right": ("biped_run_stop", 48, stop_speed,
                       dict(start_phase=0.0, start_window=12.0, cancel_frame=24.0, blend_in=0.12, blend_out=0.3)),
    "run_stop_left": ("biped_run_stop_L", 48, stop_speed,
                      dict(start_phase=0.5, start_window=12.0, cancel_frame=24.0, blend_in=0.12, blend_out=0.3)),
    "akira_right": ("biped_run_stop_akira", 100, akira_speed,
                    dict(start_phase=0.0, start_window=8.0, cancel_frame=30.0, blend_in=0.12, blend_out=0.35)),
    "akira_left": ("biped_run_stop_akira_L", 100, akira_speed,
                   dict(start_phase=0.5, start_window=8.0, cancel_frame=30.0, blend_in=0.12, blend_out=0.35)),
}


def floats(values):
    return "PackedFloat32Array(" + ", ".join(f"{round(v, 4):g}" for v in values) + ")"


def main():
    with open(MARKERS) as f:
        markers = json.load(f)["animations"]
    os.makedirs(OUT, exist_ok=True)
    for name, (anim, frames, speed, extra) in CLIPS.items():
        steps = [m["frame"] for m in markers.get(anim, []) if m["name"].startswith("footstep")]
        lines = [
            '[gd_resource type="Resource" script_class="SkeletalMoveClip" format=3]',
            "",
            '[ext_resource type="Script" path="res://scripts/data/skeletal_move_clip.gd" id="1"]',
            "",
            "[resource]",
            'script = ExtResource("1")',
            f'animation = &"{anim}"',
            f"fps = {FPS}",
            f"made_for_speed = {FULL:.2f}",
            "body_speeds = " + floats([speed(f) for f in range(frames + 1)]),
            "footstep_frames = " + floats(steps),
        ]
        lines += [f"{k} = {v}" for k, v in extra.items()]
        path = os.path.join(OUT, name + ".tres")
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        print("wrote", path, "footsteps", steps)


if __name__ == "__main__":
    main()
