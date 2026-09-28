"""Beam rifle for Granpa Gundam. Run from the project root."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Builder, xf
b = Builder()
P = "."
b.part("Stock", P, "rifle", "box", (0.3, 0.6, 1.2), (0, -0.1, -0.6))
b.part("StockPad", P, "dark", "box", (0.36, 0.78, 0.2), (0, -0.1, 0.0))
b.part("Body", P, "rifle", "box", (0.5, 0.8, 3.2), (0, 0.05, -2.8))
b.part("BodyTop", P, "dark", "box", (0.42, 0.12, 2.6), (0, 0.5, -2.9))
b.part("Grip", P, "dark", "box", (0.3, 0.7, 0.35), (0, -0.6, -1.65), (-20, 0, 0))
b.part("TriggerGuard", P, "dark", "box", (0.12, 0.08, 0.7), (0, -0.55, -2.1))
b.part("EnergyCap", P, "rifle", "box", (0.38, 0.5, 0.8), (0, -0.55, -3.0))
b.part("ForeGrip", P, "dark", "box", (0.25, 0.7, 0.3), (0, -0.6, -4.6), (-10, 0, 0))
b.part("Scope", P, "rifle", "box", (0.3, 0.45, 1.6), (0, 0.78, -2.6))
b.part("ScopeFront", P, "dark", "box", (0.34, 0.5, 0.2), (0, 0.78, -3.45))
b.part("ScopeLens", P, "lens", "cyl", (0.24, 0.24, 0.08), (0.2, 0.8, -2.2), (0, 0, 90))
b.part("ScopeLensRim", P, "dark", "cyl", (0.3, 0.3, 0.06), (0.17, 0.8, -2.2), (0, 0, 90))
b.part("Barrel", P, "rifle", "box", (0.3, 0.4, 2.4), (0, 0.05, -5.6))
b.part("BarrelRail", P, "dark", "box", (0.18, 0.16, 2.0), (0, -0.2, -5.4))
b.part("MuzzleBlock", P, "dark", "box", (0.42, 0.52, 0.4), (0, 0.05, -6.8))
b.part("MuzzleTip", P, "rifle", "cyl", (0.12, 0.14, 0.3), (0, 0.05, -7.1), (90, 0, 0))
o = ['[gd_scene format=3]\n',
 '[ext_resource type="Material" path="res://materials/rx78/rifle.tres" id="rifle"]',
 '[ext_resource type="Material" path="res://materials/rx78/dark.tres" id="dark"]',
 '[ext_resource type="Material" path="res://materials/rx78/lens.tres" id="lens"]\n',
 b.sub_text(),
 '[node name="BeamRifle" type="Node3D"]\n']
o += b.nodes
def marker(n, pos): o.append(f'[node name="{n}" type="Marker3D" parent="."]\ntransform = {xf(pos)}\n')
marker("GripRight", (0, -0.55, -1.65))
marker("GripLeft", (0, -0.45, -5.0))
marker("GripLeftRest", (0, -0.45, -4.6))
marker("GripLeftAim", (0, -0.45, -4.2))
marker("Muzzle", (0, 0.05, -7.3))
open("scenes/weapons/beam_rifle.tscn", "w").write("\n".join(o))
