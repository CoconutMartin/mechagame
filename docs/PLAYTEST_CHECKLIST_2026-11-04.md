# Play test checklist (2026-11-04)

Get the build: `git pull origin ccr-c2198b2d-613uc0`, then `git lfs pull`. Open the project in Godot and run the urban map.
Mark each box. Write notes for each item that is wrong.

## Pile Bunker (any Pile Bunker, Shift+1)

- [ ] Hold the button: the charge pose stays still and the forearm is level.
- [ ] Walk while you charge: the mech walks slower and cannot run or boost.
- [ ] Release at a target 10 to 20 m away: the mech leaps (12 m at most), the arm swings, and the stakes hit at the landing.
- [ ] No fist goes into the face.
- [ ] Shift+2 does nothing.
- [ ] Shift+3: the jump is about 70% higher, and the landing is correct.
- [ ] Two Pile Bunkers: Shift+number changes the clip on both arms.
- [ ] A Pile Bunker in one hand plays that hand's clip.

## Shotguns

- [ ] Shotgun 2 and 3: heat in place of ammo; the heat bar shows; an overheat locks the gun (Shotgun 2 after about 10 fast shots, Shotgun 3 after about 7).
- [ ] Electric pellets: crackling blue orbs, lightning between the pellets, trails and sparks, blue hit forks and flash.
- [ ] Shotgun 3 fires in the left hand.
- [ ] Shotgun 3 heads snap a quarter turn at each shot and do not spin.
- [ ] Screen disruption when Shotgun 2 or 3 pellets hit you (an AI enemy with one of them).

## Beam rifles

- [ ] Beam Rifle 4: the shot leaves at the release; the cool down is 6 s.
- [ ] Beam Rifle 3: the rings light back to front, then the tips; the glow fades over 1 s; no shot during the fade.
- [ ] Beam Rifle 2: the coil goes from dull red to bright red at max heat, then cools down.
- [ ] Beam Rifle 1: a very slight kick on the charged shot.

## Mech

- [ ] Hit reactions: a normal hit does not stop the walk; the torso and head flinch at half strength.
- [ ] A full stagger bar still stuns; a very large hit still knocks the mech down.
- [ ] Ctrl kneel: the right knee goes down and the left foot goes forward; the camera lowers with the body; Ctrl or W stands up.
- [ ] Aim down (RMB) and fire: the head stays steady.

## Backpacks

- [ ] The Light, Aux and Heavy Packs are gone; the default pack is the Field Pack.
- [ ] Boost Pack: light blue fire from the whole grille panels.
- [ ] Quad Booster and Jet Pack: orange rocket plume; a gust of thin air streaks (no bubbles); dust behind the mech on the ground.
- [ ] Nozzles heat up with use and cool down after.
- [ ] Quad petals close as the jump charge builds and snap open at the launch.
- [ ] No boost fire on a dodge step.

## Drones (Drone Pack: lock with T, release)

- [ ] The drones fly flat like a saucer, lean into the motion and bob a little.
- [ ] The barrel port in the rim faces the target.
- [ ] After each burst, the drone hops about 2.5 m in 0.5 s at most (3 bursts, 3 hops).

## Known open points (no need to report)

- While kneeling, a tall rifle at its rest hold touches the ground with its muzzle.
- The AI holds the Beam Rifle 4 trigger like a gun when it shoots at drones.
- Pile Bunker clip 3 misses with the left hand at 12 m (this was true before).

## Older open items

- Upload the Haliya HLY-101 model.
- Play test SGG after the part split.
- Fix the thumb grip in Blender.
- The PS1 look is off.
- Decide on the broken-part look.
