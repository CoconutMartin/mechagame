# Project instructions

Godot 4 mecha game. GDScript only. Read DESIGN.md first and keep it updated.
The user is a beginner. Build one phase at a time, then stop and explain how to test it.
Ask before big design changes. Commit after each working phase.

## Reminders

Check "Reminders for the user" in DESIGN.md. Remind the user of each open item when a phase is about to close and when a new phase starts.

## Mech scope (user rule, updated 2026-11-05)

The game has 3 rigs: light, medium and heavy. Every mech uses one of them. All 3 rigs play the same animations, and
parts swap across all 3 rigs (DESIGN "Three rigs"): same bones and rest rotations, only offsets differ. A mech's parts are files on its rig.

- Medium: SGG-101 Sagigilid (in-game name since 2026-10-14; files and code keep the old name "sanggigilid"). Rig
  `MechRig`, scene `scenes/mech/sanggigilid.tscn`, built by `tools/godot/build_sanggigilid.gd`. The default mech. No mech is on a number key (user 2026-11-06).
- Light: Haliya HLY-101. Model built by `tools/blender/haliya_ref_build.py`; rigged by `tools/blender/haliya_rig_light.py` into
  `models/haliya/haliya.blend`; exported to `models/mechs/haliya/source_light_rig/`, then refit by `tools/godot/refit_haliya_parts.gd`
  and `make_haliya_rig.gd` into `models/mechs/haliya/`: since 2026-11-08 SGG's leg chain, Haliya's own offsets above the pelvis
  (DESIGN "HLY refit, legs only"). Do not export from Blender straight into `models/mechs/haliya/`. In the game through the garage (the legs part picks its scene `scenes/mech/haliya.tscn`, built with `MECH=haliya` on `build_sanggigilid.gd`).
- Heavy: no mech and no rig yet.

Mech names: `docs/mech_names.md`.

## PS1 skin (user rule, 2026-10-11)

Every new mech, weapon and equipment gets the PS1 skin: uploaded models and everything modelled in
Blender. Keep the model's own colors. Use `PS1SkinLook` / `PS1Skin` and `data/skins/ps1_skin.tres`.

## Code rules

- Small scripts, one job per script. Use `class_name` and typed GDScript.
- Tuning values are `@export` variables with a short `##` doc comment.
- Data (parts, weapons, mods, plates) are Resources (.tres) in /data.
- 1 unit = 1 meter. Mech height about 10 m.

## Chat reply style

No antithesis. No corrective negation. No paragraph pinning. No parataxis. No summary beats.
No rhetorical crutches. No negative parallelisms. No negative anaphoras. No contrasting pairs.
No rule of three. No em dashes. No throat-clearing openers. No landing sentences.
No setup/payoff constructions. No parallel sentence structures within a paragraph.
Vary sentence length unpredictably. No stacked noun phrases.
Be concise when explaining unless asked for further clarification.

Use ASD-STE100 Simplified Technical English (STE) for chat replies. Also consider ELI18 and TLDR.
Apart from that: silence is gold.

## Agents and model routing

Follow the routing policy in AGENTS.md (imported below). Subagent definitions are in `.claude/agents/`.

@AGENTS.md
