# Handoff: HP indicators per part

Written 2026-10-14 for the next session. Branch: `ccr-04329fbb-pi985o` (last commit before this file: f1a6936).

## Task

Add polished HP indicators per part, set into the mech's body parts (SGG-101 Sagigilid,
`scenes/mech/sanggigilid.tscn`). Each part shows its own HP. Colors: green at 100%, orange at 50%,
red at 10% (tune the gradient as needed). The user wants the look to belong to the armor, and asked
if all imported mech models can get it with no extra work.

## What the user rejected (do not repeat)

All 3 were a `MechHpMarks` node (`scripts/effects/mech_hp_marks.gd`, now deleted) that put marks
on the armor's back, seen from the third person camera.

1. Plain colored stripes per part (commit 4daaa47). User: "look terrible".
2. Dead Space style cell gauges with a housing, glow, low HP flicker and hit flash (a3c8e5a).
3. One square lamp per part with a bezel, glowing core, halo, low HP pulse and hit flash (82587c3).
   User: "These are terrible."

Read the old code with `git show 82587c3:scripts/effects/mech_hp_marks.gd` for the part and
bone hookup. Do not reuse its look.

## Before you build

- Ask the user to send the annotated screenshot again (the one with the HP marks and crosshair).
  It is not in the repo.
- Show 2 or 3 look options as renders first (xvfb render, see below) and let the user pick.
  Do not commit a look before the user approves it.
- Ideas not tried yet: a color tint or emissive edge on the part's own mesh (shader overlay on
  `part_meshes`), panel line glow along armor seams, a damage decal, a small mech silhouette in
  the screen corner (a HUD paper doll) as a second option.

## Code hooks

- `scripts/combat/mech_health.gd` (`MechHealth`): `get_fraction(key)`, `is_part_alive(key)`,
  signals `damaged(key, amount)`, `part_destroyed(key)`.
- `scripts/combat/skeletal_hitboxes.gd` (`SkeletalHitboxes`): `part_meshes` (meshes per hit key),
  `mesh_bones` (bone per mesh), `get_attachment(bone)` (a BoneAttachment3D that follows the
  animation), `skeleton`.
- Part keys (`data/mechs/sanggigilid_hit_parts.tres`): Head, Torso C, Torso L, Torso R, Arm L,
  Arm R, Groin, Leg L, Leg R. Display names: "SGG-101 Arm (L)" and so on.
- The crosshair (`scripts/ui/aim_reticle.gd`) already uses a green, orange, red `status_colors`
  gradient for the target. Reuse it so the colors match.
- The map has glow on. Emission above about 1.6 shows as white.
- The PS1 skin rule applies (`PS1SkinLook`, `data/skins/ps1_skin.tres`). Keep the model's own colors.
- Add the node in `tools/godot/build_sanggigilid.gd` too, or the next build removes it.

## Test and render

- Godot: `/tmp/claude-0/godot/Godot_v4.7.2-stable_linux.x86_64` (download it again if the new
  container does not have it).
- Headless: `--headless --path . --fixed-fps 60 --script <script.gd>`.
- Render: `xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path . --rendering-driver opengl3
  --resolution 1280x720 --script <script.gd>`.
- Test with damage at 100%, 50%, 10% and 0% per part. Check for 0 script errors.

## When done

- Close the reminder in DESIGN.md ("Open (2026-10-14): add HP indicators per part") and update
  the "HP indicators on the armor" entry.
- Commit, push to the branch, and remind the user of the other open reminders in DESIGN.md.

## Prompt for the new session

> Read CLAUDE.md, DESIGN.md and docs/HANDOFF_hp_indicators.md. Then add polished HP indicators
> per part, set into the mech's body parts. Ask me for the reference screenshot and show me
> look options before you commit.
