"""Heavy rifle for the Warden. Run from the project root.
The barrel is one straight cylinder on the bore line, so it points exactly along -Z.
SCALE sets the size (revision 43: 0.6, for one-hand holding)."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapes import Builder, xf
SCALE = 0.6
BORE_Y = 0.05
b = Builder()
P = "."
_part = b.part


def scaled_part(name, parent, mat, kind, params, pos=(0, 0, 0), rot=(0, 0, 0)):
    n = 3 if kind in ("box", "cyl", "prism") else 1
    params = tuple(v * SCALE for v in params[:n]) + tuple(params[n:])
    _part(name, parent, mat, kind, params, tuple(v * SCALE for v in pos), rot)


b.part = scaled_part
b.part("Stock", P, "rifle", "box", (0.4, 0.75, 1.3), (0, -0.05, -0.55))
b.part("StockPad", P, "dark", "box", (0.44, 0.9, 0.2), (0, -0.05, 0.05))
b.part("StockRail", P, "dark", "box", (0.2, 0.2, 1.2), (0, 0.35, -0.7))
b.part("Receiver", P, "rifle", "box", (0.6, 0.95, 2.6), (0, 0.05, -2.4))
b.part("ReceiverSide", P, "dark", "box", (0.66, 0.35, 2.2), (0, -0.05, -2.5))
b.part("Grip", P, "dark", "box", (0.32, 0.75, 0.38), (0, -0.62, -1.65), (-20, 0, 0))
b.part("Magazine", P, "dark", "box", (0.4, 1.0, 0.55), (0, -0.85, -2.75), (8, 0, 0))
b.part("Rail", P, "dark", "box", (0.3, 0.12, 3.2), (0, 0.58, -3.0))
b.part("Scope", P, "rifle", "box", (0.34, 0.42, 1.3), (0, 0.9, -2.3))
b.part("ScopeHoodFront", P, "dark", "box", (0.4, 0.5, 0.25), (0, 0.9, -3.0))
b.part("ScopeHoodRear", P, "dark", "box", (0.4, 0.5, 0.2), (0, 0.9, -1.6))
b.part("ScopeLens", P, "lens", "cyl", (0.14, 0.14, 0.05), (0, 0.9, -3.14), (90, 0, 0))
b.part("Handguard", P, "rifle", "box", (0.52, 0.7, 2.2), (0, 0.05, -4.8))
b.part("HandguardRail", P, "dark", "box", (0.2, 0.15, 2.0), (0, -0.35, -4.8))
b.part("ForeGrip", P, "dark", "box", (0.26, 0.65, 0.3), (0, -0.62, -4.6), (-10, 0, 0))
b.part("BarrelCollar", P, "dark", "cyl", (0.26, 0.26, 0.4), (0, BORE_Y, -6.05), (90, 0, 0))
b.part("Barrel", P, "rifle", "cyl", (0.19, 0.19, 2.6), (0, BORE_Y, -7.5), (90, 0, 0))
b.part("MuzzleRing", P, "dark", "cyl", (0.22, 0.22, 0.2), (0, BORE_Y, -8.8), (90, 0, 0))
o = ['[gd_scene format=3]\n',
 '[ext_resource type="Material" path="res://materials/warden/rifle.tres" id="rifle"]',
 '[ext_resource type="Material" path="res://materials/warden/rifle_dark.tres" id="dark"]',
 '[ext_resource type="Material" path="res://materials/warden/lens.tres" id="lens"]',
 '[ext_resource type="Material" path="res://materials/effects/muzzle_flash.tres" id="flash"]',
 '[ext_resource type="Script" path="res://scripts/effects/muzzle_flash.gd" id="flash_script"]\n',
 '[sub_resource type="CylinderMesh" id="flash_cone"]\ntop_radius = 0.0\nbottom_radius = 0.35\nheight = 1.3\nradial_segments = 8\nrings = 1\n',
 '[sub_resource type="SphereMesh" id="flash_core"]\nradius = 0.28\nheight = 0.56\nradial_segments = 8\nrings = 4\n',
 b.sub_text(),
 '[node name="HeavyRifle" type="Node3D"]\n']
o += b.nodes
def marker(n, pos): o.append(f'[node name="{n}" type="Marker3D" parent="."]\ntransform = {xf(tuple(v * SCALE for v in pos))}\n')
marker("GripRight", (0, -0.55, -1.65))
marker("GripLeft", (0, -0.45, -5.0))
marker("GripLeftRest", (0, -0.45, -4.6))
marker("GripLeftAim", (0, -0.45, -4.2))
marker("Muzzle", (0, BORE_Y, -8.9))
o.append(f'''[node name="MuzzleFlash" type="Node3D" parent="Muzzle" node_paths=PackedStringArray("light")]
script = ExtResource("flash_script")
light = NodePath("Light")

[node name="Cone" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
transform = {xf((0, 0, -0.65), (-90, 0, 0))}
cast_shadow = 0
mesh = SubResource("flash_cone")
surface_material_override/0 = ExtResource("flash")

[node name="Core" type="MeshInstance3D" parent="Muzzle/MuzzleFlash"]
cast_shadow = 0
mesh = SubResource("flash_core")
surface_material_override/0 = ExtResource("flash")

[node name="Light" type="OmniLight3D" parent="Muzzle/MuzzleFlash"]
light_color = Color(1, 0.7, 0.35, 1)
omni_range = 10.0
''')
open("scenes/weapons/heavy_rifle.tscn", "w").write("\n".join(o))
print("wrote scenes/weapons/heavy_rifle.tscn")
