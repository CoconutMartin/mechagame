# Backpack research (2026-10-31)

Notes for `tools/blender/backpack_build.py`. The backpack takes the old FCS slot (user decision 2026-10-31). It
carries the aux equipment (pulse scan now) and gives one bonus stat (boost, energy or HP).

## What mecha backpacks show (common genre parts)

- **Mount frame**: a flat plate or a clamp against the torso back. It reads as "bolted on", not grown out of the
  body. A dark color separates it from the armor.
- **Thrusters**: nozzles that point down and back. They show "this pack pushes the mech". Bells widen at the exit.
  A light pack has small nozzles, a heavy pack has big ones.
- **Propellant tanks**: vertical cylinders on the sides, with straps. They give the pack a volume that is not only
  boxes.
- **Radiators and vents**: thin fins in a row, or a grille. They read as "power" and work well as a heavy-pack
  silhouette.
- **Hardpoints**: rails or square pads where equipment fits. Each aux slot gets one visible hardpoint, so the slot
  count shows on the model.
- **Antennas and sensor masts**: thin and tall. They change the outline from the back with few triangles.
- **Handles, rails, lamps, hazard stripes**: small parts for scale. A 10 m mech needs parts that are at least
  0.1 m, or they disappear at game distance.

## Silhouette rules

- The pack is seen mostly from behind and from the side (third-person camera). The outline from behind must
  differ per type: light = narrow and tall with one mast; medium = a box with two side tanks; heavy = a wide
  block with a radiator stack on top and two big tanks.
- Keep the pack inside the shoulder line (the shoulder pods sit at |x| 0.85 to 1.85 m above 8.8 m) and under
  8.8 m, so it does not collide with the back weapons.
- Big shapes first, then panels, then small parts (docs/blender_modeling_notes.md).

## Sizes on the Sagigilid (measured with `tools/godot/measure_back.gd`)

- Torso back face: z 1.37 to 1.40 m behind the mech center, height 7.0 to 8.5 m, |x| < 0.9 m flat.
- The pack's front face (Mount) goes 0.03 m behind it, centered at x 0, y 7.7 m.

| Type | Size w x h x d (m) | Aux slots | Bonus | Shape |
|---|---|---|---|---|
| Light Pack | 1.1 x 1.5 x 0.6 | 1 | boost +6% | narrow tapered body, two small nozzles, slim tanks, one tall mast |
| Aux Pack (medium) | 1.6 x 1.7 x 0.85 | 2 | energy +10% | box with side tanks, two nozzles, a vent grille, two short antennas |
| Heavy Pack | 2.3 x 1.9 x 1.15 | 3 | HP +5% | wide armored block, radiator stack on top, two big tanks, two big nozzles |
| Boost Pack | 2.0 x 2.2 x 1.1 | 1 | boost +12% | center box, four wings with louvered grilles (boost outlets), gunmetal (user picture) |
| Quad Booster | 2.06 x 2.1 x 1.14 | 1 | boost +18% | four octagonal thruster pods with big nozzles, tan spine (user picture) |
| Belt Pack | 1.64 x 2.0 x 1.07 | 1 | none; 8 gun refills | frame box with a handle, an ammo belt down the back (user picture) |
| Power Pack | 1.68 x 2.1 x 0.93 | 1 | energy +25% | center stack with a radiator, towers, battery cells, orange cables (user picture) |

## Colors

The Sagigilid's olive armor, dark olive, black frame, steel nozzles and an orange lamp, so every pack matches the
mech. The PS1 skin keeps the model colors (CLAUDE.md).

## Node names (for the game)

- `Mount`: empty at the center of the front face (on the torso back).
- `Aux1` .. `AuxN`: empties on the hardpoints, one per aux slot (equipment models later).
- `Thruster1` .. : empties at the nozzle exits, pointing down (flames later).
- `Lamp`: the glow mesh (orange, emission off; a script can light it).
