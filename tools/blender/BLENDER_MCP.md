# Blender MCP on your PC

Blender MCP lets Claude on your PC control your open Blender. You see each change live.
It also has Hyper3D Rodin, an AI that makes a 3D model from a picture.
This cloud session cannot reach your PC, so you run it there.

## 1. Install (one time)

1. Install **uv** (it runs the MCP server).
   Windows PowerShell: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`
   Mac: `brew install uv`
2. Install **Claude Code** on your PC (recommended: it reads CLAUDE.md, runs scripts and commits).
   See https://code.claude.com/docs. Claude Desktop also works, but it cannot commit.
3. Add the MCP server:
   - Claude Code: open a terminal in the project folder and run `claude mcp add blender uvx blender-mcp`
   - Claude Desktop: Settings > Developer > Edit Config, add:
     ```json
     { "mcpServers": { "blender": { "command": "uvx", "args": ["blender-mcp"] } } }
     ```
4. Install the Blender add-on: download `addon.py` from https://github.com/ahujasid/blender-mcp.
   In Blender: Edit > Preferences > Add-ons > Install (Blender 4.2+: the arrow menu > Install from Disk),
   select `addon.py`, then enable "Blender MCP".

## 2. Connect (each time)

1. `git pull` the project.
2. Open the kit file in Blender (make one first with
   `blender -b --python tools/blender/mech_kit.py -- <name>`, or ask Claude to run it).
3. In the 3D view, push N. Open the **BlenderMCP** tab.
4. Tick "Use Hyper3D Rodin 3D model generation". Push "Set Free Trial API Key"
   (the trial has a daily limit; a paid key comes from hyper3d.ai).
5. Push "Connect". Then start Claude Code in the project folder (or open Claude Desktop).
   Use one Claude app at a time.

The add-on runs any Python that Claude sends to Blender. Save your work before a big step.

## 3. Image to 3D, then into the game

Put the reference picture in `models/guides/` (Godot ignores this folder). Then ask Claude, for
example:

> Read CLAUDE.md and DESIGN.md. Make the mech kit file `recon_gen`, open it in Blender.
> Generate a mech with Hyper3D Rodin from models/guides/<picture>. Import it, face it to -Y,
> stand it on the ground and line up its joints with the grey OG guide. Then run
> tools/blender/split_generated.py, show me each part, fix bad cuts, export, add the part data
> (tools/data_gen/garage_data.py) and a loadout key, test in Godot, commit and push.

What `split_generated.py` does: it joins the selected meshes, scales the model to 10.6 m
(`FIT_HEIGHT`), reduces very dense meshes (`MAX_FACES`), and cuts each face to the nearest body
bone (head, core, pauldrons, upper arms, forearms, pelvis, thighs, shins, feet, backpack,
antennas). Each piece goes under its socket or pivot empty. The core is cut into center and side
pieces for the side torso hit areas.

Limits of AI models: one fused surface, so cuts at the joints can look rough and the arms and
legs may clip at the joints when they bend. The AI texture is kept, so the colors come from the
picture (olive for your reference). Part damage looks need materials named `armor` and `frame`.
Claude can fix these by hand in Blender after the cut.
