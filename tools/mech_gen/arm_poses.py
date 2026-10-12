"""Sanggigilid arm poses from the user's drawing (2026-10-12), torso space (shoulders 2.465 m above the
origin, -Z forward, mech left = -X). The upper arm hangs under the flat shoulder block (the rig keeps the
block flat); only the elbow bends, in the side view:
  one-hand guns, auto cannon, pile bunker, free left hand, small shield: elbow 45 deg at neutral
  one-hand guns, auto cannon, pile bunker: elbow 90 deg (forearm level, forward) when aiming
  large shield (Hex Shield): elbow 90 deg all the time
A one-hand gun lies on top of the forearm, along it; the auto cannon lies under it.
At neutral the auto cannon's forearm turns CANNON_OUT_DEG out to the side, so the cannon under it clears
the thigh (the side view stays the drawing's).
"""
import math

## Elbows under the flat shoulder blocks (measured in the game), and the elbow-to-palm length.
ELBOW_R = (2.18, 1.16, -0.05)
ELBOW_L = (-2.10, 1.10, -0.03)
FOREARM = 2.71
NEUTRAL_DEG = 45.0
AIM_DEG = 90.0
CANNON_OUT_DEG = 12.0


def forearm_dir(bend_deg, out_deg=0.0, side=1.0):
    """Elbow to palm, for an elbow bent bend_deg forward from hanging straight down, and turned out_deg
    out to the side (side +1 = right arm, -1 = left; the side view stays the same)."""
    a, o = math.radians(bend_deg), math.radians(out_deg)
    return (side * math.sin(o), -math.cos(a) * math.cos(o), -math.sin(a) * math.cos(o))


def top_side(bend_deg):
    """The forearm's top side (up from the forearm, in the side view)."""
    a = math.radians(bend_deg)
    return (0.0, math.sin(a), -math.cos(a))


def hand(elbow, bend_deg, out_deg=0.0, side=1.0):
    d = forearm_dir(bend_deg, out_deg, side)
    return tuple(e + FOREARM * c for e, c in zip(elbow, d))


## The hollow of the closed fist from the grip_R socket bone (its frame: +X out to the right, +Y along
## the fist from the pinky to the index, +Z toward the wrist; measured from the curled finger bones). The
## socket bone sits at the front of the fist (user picture 2026-10-12: the pistol grip showed in front of
## the knuckles), so a gun's GripRight marker goes this much off its grip: the grip then sits in the palm.
PALM_HOLLOW = (0.2, 0.0, 0.18)


def palm_socket(grip):
    """GripRight marker place (weapon space) for a pistol grip hold point at grip: the fist hollow on it.
    The weapon axes match the socket bone's in the one-hand poses (gun along the forearm, top up)."""
    return minus(grip, PALM_HOLLOW)


def minus(a, b):
    return tuple(x - y for x, y in zip(a, b))
