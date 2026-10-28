# Blender modeling notes

Rules for new mech parts, weapons and equipment built by Python scripts in `tools/blender/`
(`blender -b --python <script>`). Parts of these rules come from the hard-surface, reference-match and
pixel-art skills of https://github.com/arjun988/blender-skills (MIT), changed for this project:
no Blender MCP, no open Blender window, and the PS1 skin is made in Godot (CLAUDE.md).

## Model from a picture

1. Before the script, write down from the picture: the forward axis, the big masses and their length,
   width and height ratios, the parts that move, and the colors (3 to 6).
2. Big shapes first, then panel breaks and recesses, then small details. Small details never change
   the outline.
3. Render the model from the picture's view angle and compare (side, front, top and 3/4 renders,
   like `tools/blender/pile_bunker_build.py` work). Make a list of the differences, fix them, render
   again. Stop after 3 passes and show the user.
4. A script change rebuilds the model from an empty file. Do not hand edit the `.blend`.

## Shapes and edges

- Panel lines go where real parts would join: seams, hatches, places where the material changes.
  Make them as a thin dark strip or a small inset, not as a cut through the whole part.
- Bevel widths by size: big outer edges 0.02 to 0.1 m (chamfer), panel edges 0.01 to 0.02 m,
  small parts 0.005 to 0.01 m (sizes for a 10 m mech). Do not use one bevel width on the whole model.
- Bevel with `limit_method = "ANGLE"` (about 35 deg) and `harden_normals`, so flat faces stay flat.
- Moving parts (stake, slide, magazine, hinge) are separate objects with their own empty as the pivot,
  so the weapon script can move them.
- Glowing parts are separate meshes with their own material (the weapon scripts light them; the PS1
  skin leaves emissive materials alone).
- A hand grip: an empty at the center of the fist contact (like `Grip` in `auto_cannon_build.py`).
- Repeated small parts (bolts, vents): one function in the script that makes them, called in a loop.
  Keep them few: they must not make most of the triangle count.

## Size and export

- 1 unit = 1 m. Blender +Y = forward (Godot -Z), +Z = up. Origin on a named point (the butt, the
  mount or the grip), written at the top of the script.
- Export GLB with `export_yup=True` and `export_apply=True` (modifiers applied).
- Print the triangle count at export. Weapons so far: 2,700 to 3,500 triangles.
- Check the outline from several sides (every 45 deg) before details.

## Pixel-art look (open reminder, not started)

- Pick one texel size for all models and textures (for example 16 or 32 pixels per meter) and keep it.
- Nearest filtering, no blurry mipmaps where the pixel look is wanted.
- A small color palette.
- No long thin triangles: they flicker at low resolution.
- Fixed or few camera angles read best.
