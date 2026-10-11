# Project instructions

Godot 4 mecha game. GDScript only. Read DESIGN.md first and keep it updated.
The user is a beginner. Build one phase at a time, then stop and explain how to test it.
Ask before big design changes. Commit after each working phase.

## Reminders

Check "Reminders for the user" in DESIGN.md. Remind the user of each open item when a phase is about to close and when a new phase starts.

## Mech scope (user rule, 2026-10-11)

All new work and adjustments go to the new mech (rigged, `scenes/mech/skeletal_mech.tscn`).
Do not change the old part-built mechs (Warden, Recon mechs, Medium, OG Mech, Granpa Gundam).
Shared code may change only in ways that keep the old mechs working the same (new behavior
behind the new mech's own nodes or settings). Test the old mechs after a shared change.

## Code rules

- Small scripts, one job per script. Use `class_name` and typed GDScript.
- Tuning values are `@export` variables with a short `##` doc comment.
- Data (parts, weapons, mods, plates, skills) are Resources (.tres) in /data.
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
