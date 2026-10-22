"""Adds the 3 charge indicator lights to the Beam Rifle and exports it again.

Run (from the project root, with pip bpy 5.2.2 because the .blend is saved by Blender 5.2):
    python tools/blender/beam_rifle_indicators.py
Opens models/beam_rifle/beam_rifle.blend, removes any old Indicator* objects, builds the housing and
the 3 lamps, then saves the .blend and writes models/beam_rifle/beam_rifle.glb. Safe to run again.
beam_rifle_build.py starts from an empty file and does not know these parts; run this script after it.

Where: on top of the stock, just behind the scope, where the third-person camera (behind and right
of the mech) sees them. A dark housing carries 3 lamps in a row across the gun. From behind, lamp 1
is on the left and lamp 3 on the right.
Objects: IndicatorHousing, Indicator1, Indicator2, Indicator3. BeamRifleWeapon.lamp_paths names the
three lamps; ChargeLights lights them (1 = a tap, 2 = half charge, 3 = full charge).
The lamp material beam_rifle_lamp is dark teal with no emission: the game adds the glow.

Axes and picture pixels are the same as in beam_rifle_build.py (Blender +Y = forward, +Z = up).
"""
import math, os
import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "models", "beam_rifle")

MUZZLE_PX, BUTT_PX, BORE_PX = 492, 1728, 241
SCALE = 6.0 / (BUTT_PX - MUZZLE_PX)
BEVEL = 0.012

# Stock top surface (picture row 183) and the housing place along the gun.
HOUSING_U0, HOUSING_U1 = 1416, 1462
HOUSING_WIDTH = 0.42
HOUSING_HEIGHT = 0.05
LAMP_WIDTH = 0.11
LAMP_LENGTH = 0.17
LAMP_RISE = 0.022
LAMP_GAP = 0.025
LAMP_BORDER = 0.02


def Y(px):
    return (BUTT_PX - px) * SCALE


def Z(py):
    return (BORE_PX - py) * SCALE


def material(name, color, rough, metal):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    mat.diffuse_color = (*color, 1.0)
    return mat


def box(name, mat, x, y0, y1, z0, z1, width, bevel=BEVEL):
    """Box centered on x, across the gun width m, from y0 to y1 along the gun and z0 to z1 up."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = x + v.co.x * width
        v.co.y = y0 + (v.co.y + 0.5) * (y1 - y0)
        v.co.z = z0 + (v.co.z + 0.5) * (z1 - z0)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def clear_old():
    for obj in list(bpy.data.objects):
        if obj.name.startswith("Indicator"):
            mesh = obj.data
            bpy.data.objects.remove(obj)
            if mesh is not None and mesh.users == 0:
                bpy.data.meshes.remove(mesh)


def build():
    clear_old()
    dark = bpy.data.materials["beam_rifle_dark"]
    lamp = material("beam_rifle_lamp", (0.006, 0.022, 0.03), 0.7, 0.0)
    y0, y1 = Y(HOUSING_U1), Y(HOUSING_U0)
    top = Z(183)
    box("IndicatorHousing", dark, 0.0, y0, y1, top - 0.004, top + HOUSING_HEIGHT, HOUSING_WIDTH)
    pitch = LAMP_WIDTH + LAMP_GAP
    ym = (y0 + y1) / 2
    for i in range(3):
        x = (i - 1) * pitch
        box(f"Indicator{i + 1}", lamp, x, ym - LAMP_LENGTH / 2, ym + LAMP_LENGTH / 2,
            top + HOUSING_HEIGHT - 0.004, top + HOUSING_HEIGHT + LAMP_RISE, LAMP_WIDTH, bevel=0.008)


def main():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle.blend"))
    build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "beam_rifle.blend"))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "beam_rifle.glb"), export_format="GLB",
                              export_apply=True, export_yup=True)
    for obj in bpy.data.objects:
        if obj.name.startswith("Indicator"):
            print(obj.name, tuple(round(v, 3) for v in obj.dimensions))


main()
