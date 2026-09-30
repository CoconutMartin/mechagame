"""Builds the Recon Gen mech in models/recon_gen/recon_gen.blend and exports the parts.

Run (from the project root):
    blender -b models/recon_gen/recon_gen.blend --python tools/blender/recon_gen_build.py
or in the open file (Blender MCP): p = r"<project>/tools/blender/recon_gen_build.py"; exec(open(p).read(), {"__file__": p})
It removes the old model pieces (not the socket and pivot empties) and builds them again, so hand
edits in the part collections are lost: after hand edits, export with export_parts.py only.

Replaces the split Hunyuan3D model (the generated mesh stays in the file as `recon900_clean`, a shape
guide only). Every piece is a closed solid, so no cut face shows when a joint bends. Joints follow
models/guides/joints.png: a joint piece sits on each joint point and the segments end at it.
  Head: low wedge helmet, one red mono eye in a black ring, no antennas.
  Chest: wide sloped chest, even trap plates from the neck down to the shoulders, side blocks.
  Shoulders: shoulder ball on the shoulder point; the pauldron sits above it with a gap (detached).
  Arms: black upper arm frame with an outer plate, elbow ball, six-sided forearm guard, wrist ball,
        black fist.
  Groin: dark pelvis block, olive front codpiece and back plate, hip joints.
  Legs: hip ball, front thigh plate, knee hinge on the knee axis with a knee roller in front of the
        thigh (user placement), six-sided knee pad on the shin, tapered shin with calf pistons,
        ankle ball, wedge foot.
  Back: backpack with grilles and two nozzles.
Colors: materials/recon_gen (olive armor, dark olive armor_dark, black frame, gunmetal joint, red
eye, brass bolt). Each piece gets the vertex color `Col` (lighter faces up, darker faces down).
The plate, cylinder and outline helpers come from recon_accurate_build.py.
Sizes and places are in mech space (meters): x right (mech left is -x), y up, -z forward.
"""
import os, sys
import bpy, bmesh, math
# exec() from Blender MCP has no __file__: pass it, exec(open(p).read(), {"__file__": p}).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix, Vector
import recon_accurate_build as ra
from recon_accurate_build import crect, ngon, trapezoid, cylinder, plate

ra.BEVEL_SEGMENTS = 3
## Offset of the preview copy (collection "preview", runs the "run" action), meters along Blender X.
PREVIEW_OFFSET = 16.0


_finish_ra = ra._finish


def _finish(name, socket, bm, mats, bevel):
    """ra._finish, but the material slots exist before the mesh is written: Blender 5 sets the
    material index to 0 when the mesh has no slots, and the bolts would lose the brass material."""
    idx = [f.material_index for f in bm.faces]
    o = _finish_ra(name, socket, bm, mats, bevel)
    o.data.polygons.foreach_set("material_index", idx)
    o.data.update()
    return o


ra._finish = _finish


def hold(socket, obj):
    ra._holder[socket] = bpy.data.objects[obj]


def ball(name, socket, radius, pos, mat="frame"):
    """Joint ball on a joint point (mech space)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=radius, matrix=Matrix.Translation(Vector(pos)))
    o = ra._finish(name, socket, bm, [mat], 0.0)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def head():
    S = "Torso"
    hold(S, "Torso_head")
    helmet = [(-0.95, -0.25), (-0.95, 0.15), (-0.55, 0.5), (0.45, 0.62), (0.75, 0.3), (0.75, -0.35), (-0.4, -0.45)]
    plate("Helmet", S, helmet, 1.25, (0, 8.55, -0.55), (0, 0, 0), "x", "armor", 0.9, 0.9, None)
    for k in (-1, 1):
        plate("HelmetSide", S, crect(0.9, 0.55, 0.15), 0.12, (k * 0.66, 8.5, -0.6), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    plate("Crest", S, crect(1.1, 0.22, (0.1, 0.05, 0.02, 0.02)), 0.3, (0, 9.12, -0.5), (0, 0, 0), "x", "armor", 1.0, 1.0, None)
    plate("Chin", S, trapezoid(0.8, 0.5, 0.35, 0.08), 0.5, (0, 8.18, -1.25), (15, 0, 0), "z", "armor_dark", 0.9, 1.0, None)
    # Mono eye: black ring, red glowing lens.
    cylinder("EyeRing", S, 0.26, 0.16, (0, 8.5, -1.45), "z", "frame", 24)
    cylinder("Eye", S, 0.17, 0.1, (0, 8.5, -1.55), "z", "eye", 24, bevel=0.0)
    plate("Neck", S, crect(0.7, 0.45, 0.1), 0.8, (0, 7.95, -0.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None)


def core():
    S = "Torso"
    hold(S, "Torso_core")
    plate("Chest", S, crect(2.6, 2.15, (0.55, 0.55, 0.45, 0.45)), 2.0, (0, 7.33, 0.0), (0, 0, 0), "z", "armor_dark", 0.88, 1.0, None)
    for k in (-1, 1):
        plate("ChestUpper", S, crect(0.95, 0.9, (0.25, 0.1, 0.15, 0.1) if k < 0 else (0.1, 0.25, 0.1, 0.15)), 0.3,
              (k * 0.72, 8.1, -0.95), (-28, 0, 0), "z", "armor", 0.9, 1.0, "front", 0.08,
              bolts=[(-0.32, 0.32), (0.32, 0.32), (-0.32, -0.32), (0.32, -0.32)])
        # Traps: one even slope from the neck down to the shoulder (front view outline, 1.5 m deep).
        trap = [(k * 0.45, 8.25), (k * 0.45, 8.72), (k * 1.8, 8.3), (k * 1.8, 7.95)]
        if k > 0:
            trap.reverse()
        plate("Trap", S, trap, 1.5, (0, 0, 0.15), (0, 0, 0), "z", "armor", 1.0, 1.0, None, bevel=0.08)
    plate("ChestCenter", S, trapezoid(1.45, 1.1, 1.15, 0.18), 0.34, (0, 7.05, -1.05), (-6, 0, 0), "z", "armor", 0.92, 1.0, "front", 0.08,
          bolts=[(-0.55, 0.45), (0.55, 0.45)])
    for i in range(3):
        plate("ChestVent", S, crect(0.7, 0.07, 0.02), 0.08, (0, 6.85 - i * 0.14, -1.24), (-6, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
    plate("Belly", S, trapezoid(1.2, 0.9, 0.45, 0.1), 0.3, (0, 6.15, -0.82), (8, 0, 0), "z", "armor", 0.9, 1.0, None)
    for k in (-1, 1):
        plate("ChestSide", S, crect(1.6, 1.65, 0.3), 0.75, (k * 1.45, 7.2, 0.05), (0, 90, 0), "z", "armor", 0.9, 1.0,
              "front" if k < 0 else "back", 0.1, bolts=[(-0.55, 0.5), (0.55, 0.5), (-0.55, -0.5), (0.55, -0.5)])
    plate("Abdomen", S, trapezoid(1.3, 0.95, 0.6, 0.12), 1.1, (0, 6.05, 0.05), (0, 0, 0), "z", "frame", 0.95, 1.0, None)
    cylinder("Waist", S, 0.62, 0.45, (0, 5.7, 0.05), "y", "joint", 24, rings=[(0.12, 0.66, 0.06)])
    plate("Collar", S, crect(1.6, 0.35, 0.1), 1.2, (0, 8.45, 0.35), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
    plate("Back", S, crect(1.9, 1.6, 0.35), 0.5, (0, 7.5, 1.05), (0, 0, 0), "z", "frame", 1.0, 0.9, None)


def arm(s):
    k = -1 if s == "L" else 1
    part = f"arm_{s.lower()}"
    hold("Torso", f"Torso_{part}")
    cylinder(f"ShoulderJoint{s}", "Torso", 0.4, 0.7, (k * 1.95, 7.865, 0), "x", "frame", 24)
    # Detached pauldron: its lower edge is at 7.7 m, so the lower half of the shoulder ball shows.
    P = f"PauldronPivot{s}"
    hold(P, P)
    side = [(-1.3, -0.6), (-1.3, 0.5), (-0.9, 0.85), (0.95, 0.85), (1.25, 0.55), (1.25, -0.5), (0.9, -0.85), (-0.95, -0.85)]
    plate(f"Pauldron{s}", P, side, 1.45, (k * 3.0, 8.55, 0.0), (0, 0, 0), "x", "armor",
          1.0 if k < 0 else 0.92, 0.92 if k < 0 else 1.0, "back" if k > 0 else "front", 0.12,
          bolts=[(-1.0, 0.5), (0.95, 0.55), (0.95, -0.5), (-1.0, -0.5), (0.0, 0.62), (0.0, -0.62)])
    plate(f"PauldronVent{s}", P, crect(0.55, 0.55, 0.06), 0.14, (k * 3.75, 8.5, 0.5), (0, 90, 0), "z", "frame", 1.0, 1.0, None, bevel=0.01)
    plate(f"PauldronTop{s}", P, crect(1.2, 1.9, 0.3), 0.2, (k * 3.0, 9.42, -0.05), (90, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
    SH = f"Shoulder{s}"
    hold(SH, f"{SH}_{part}")
    ball(f"ShoulderBall{s}", SH, 0.55, (k * 2.465, 7.865, 0), "frame")
    cylinder(f"UpperArmFrame{s}", SH, 0.3, 1.8, (k * 2.465, 6.65, 0), "y", "frame", 16, rings=[(0.5, 0.36, 0.14), (-0.4, 0.36, 0.14)])
    plate(f"UpperArm{s}", SH, crect(0.95, 1.1, 0.18), 0.3, (k * 2.9, 6.55, 0), (0, 90, 0), "z", "armor", 0.9, 1.0,
          "front" if k < 0 else "back", 0.08, bolts=[(-0.3, 0.38), (0.3, 0.38)])
    EL = f"Elbow{s}"
    hold(EL, f"{EL}_{part}")
    ball(f"ElbowBall{s}", EL, 0.45, (k * 2.465, 5.57, 0), "frame")
    guard = [(-0.5, 0.35), (-0.3, 0.6), (0.3, 0.6), (0.5, 0.35), (0.5, -0.35), (0.3, -0.6), (-0.3, -0.6), (-0.5, -0.35)]
    plate(f"Forearm{s}", EL, guard, 1.5, (k * 2.5, 4.45, 0.05), (0, 0, 0), "y", "armor", 0.85, 1.0, None)
    plate(f"ForearmFront{s}", EL, crect(0.8, 1.2, 0.2), 0.14, (k * 2.5, 4.5, -0.63), (0, 0, 0), "z", "armor", 1.0, 1.0, "front", 0.08,
          bolts=[(-0.28, 0.45), (0.28, 0.45), (-0.28, -0.45), (0.28, -0.45)])
    plate(f"ForearmOuter{s}", EL, crect(1.0, 1.15, 0.2), 0.12, (k * 3.02, 4.45, 0.05), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
    ball(f"WristBall{s}", EL, 0.3, (k * 2.465, 3.55, 0), "joint")
    plate(f"Fist{s}", EL, crect(0.6, 0.6, 0.12), 0.65, (k * 2.465, 3.05, -0.05), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
    for i in range(4):
        cylinder(f"Knuckle{s}", EL, 0.08, 0.14, (k * 2.465 + (i - 1.5) * 0.14, 2.77, -0.3), "z", "joint", 8)


def legs():
    L = "Lower"
    hold(L, "Lower_legs")
    # Groin: dark pelvis block, olive codpiece in front, back plate.
    plate("Pelvis", L, crect(1.9, 0.95, 0.25), 1.4, (0, 5.2, 0.0), (0, 0, 0), "z", "armor_dark", 0.95, 1.0, None)
    codpiece = [(-0.55, 0.45), (0.55, 0.45), (0.45, -0.25), (0.0, -0.6), (-0.45, -0.25)]
    plate("Codpiece", L, codpiece, 0.5, (0, 4.75, -0.55), (-8, 0, 0), "z", "armor", 0.88, 1.0, "front", 0.07,
          bolts=[(-0.35, 0.3), (0.35, 0.3)])
    plate("SkirtBack", L, trapezoid(1.2, 0.8, 0.85, 0.12), 0.3, (0, 4.95, 0.72), (10, 0, 0), "z", "armor_dark", 0.9, 1.0, None)
    for s, k in (("L", -1), ("R", 1)):
        cylinder(f"HipJoint{s}", L, 0.45, 0.6, (k * 1.05, 5.2, 0), "x", "frame", 24, rings=[(0.0, 0.5, 0.12)])
        H = f"Hip{s}"
        hold(H, f"{H}_legs")
        ball(f"HipBall{s}", H, 0.52, (k * 1.5, 5.2, 0), "frame")
        cylinder(f"ThighFrame{s}", H, 0.32, 2.1, (k * 1.5, 4.05, 0.15), "y", "frame", 16, rings=[(0.6, 0.38, 0.16)])
        plate(f"Thigh{s}", H, crect(1.5, 1.85, (0.35, 0.35, 0.22, 0.22)), 0.6, (k * 1.5, 4.15, -0.47), (-3, 0, 0), "z", "armor", 0.9, 1.0,
              "front", 0.1, bolts=[(-0.56, 0.72), (0.56, 0.72), (-0.56, -0.72), (0.56, -0.72)])
        plate(f"ThighSide{s}", H, crect(1.2, 1.5, 0.25), 0.2, (k * 2.18, 4.15, -0.05), (0, 90, 0), "z", "armor_dark", 1.0, 1.0, None)
        # Knee roller on the thigh (user placement: 0.7 m above and 0.7 m in front of the knee axis).
        cylinder(f"KneeRoller{s}", H, 0.45, 0.95, (k * 1.47, 3.3, -0.7), "x", "joint", 28)
        K = f"Knee{s}"
        hold(K, f"{K}_legs")
        cylinder(f"KneeJoint{s}", K, 0.42, 1.0, (k * 1.5, 2.6, 0), "x", "frame", 24, rings=[(0.3, 0.47, 0.12), (-0.3, 0.47, 0.12)])
        plate(f"KneePad{s}", K, ngon(0.62, 6, 90), 0.35, (k * 1.5, 2.45, -0.7), (-8, 0, 0), "z", "armor", 0.85, 1.0, "front", 0.1,
              bolts=[(0.0, 0.42), (0.36, 0.21), (0.36, -0.21), (0.0, -0.42), (-0.36, -0.21), (-0.36, 0.21)])
        plate(f"Shin{s}", K, trapezoid(1.25, 1.0, 1.65, 0.2), 1.15, (k * 1.5, 1.4, -0.1), (0, 0, 0), "z", "armor", 0.88, 1.0,
              "front", 0.1, bolts=[(-0.42, 0.6), (0.42, 0.6)])
        plate(f"ShinStrip{s}", K, crect(0.4, 1.2, 0.1), 0.1, (k * 1.5, 1.35, -0.72), (0, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
        for off in (-0.25, 0.25):
            cylinder(f"Calf{s}", K, 0.12, 1.4, (k * 1.5 + off, 1.5, 0.62), "y", "frame", 10, rings=[(0.35, 0.16, 0.2)])
        plate(f"ShinFrame{s}", K, crect(0.5, 1.9, 0.1), 0.5, (k * 1.5, 1.55, 0.3), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        F = f"FootPivot{s}"
        hold(F, F)
        ball(f"AnkleBall{s}", F, 0.4, (k * 1.5, 0.55, 0), "joint")
        wedge = [(-1.75, 0.0), (-1.75, 0.3), (-1.2, 0.45), (-0.2, 0.7), (0.7, 0.7), (1.05, 0.4), (1.05, 0.0)]
        plate(f"Foot{s}", F, wedge, 1.3, (k * 1.5, 0.0, -0.3), (0, 0, 0), "x", "armor", 1.0, 1.0, None)
        plate(f"FootTop{s}", F, crect(1.0, 0.9, 0.15), 0.12, (k * 1.5, 0.6, -0.9), (-72, 0, 0), "z", "armor_dark", 1.0, 1.0, None)
        plate(f"Toe{s}", F, crect(1.1, 0.3, 0.08), 0.45, (k * 1.5, 0.15, -2.2), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        plate(f"Heel{s}", F, crect(0.9, 0.35, 0.08), 0.5, (k * 1.5, 0.18, 0.95), (0, 0, 0), "z", "frame", 1.0, 1.0, None)
        plate(f"FootSole{s}", F, crect(1.25, 2.9, 0.2), 0.12, (k * 1.5, 0.06, -0.35), (90, 0, 0), "z", "frame", 1.0, 1.0, None)


def booster():
    S = "Torso"
    hold(S, "Torso_booster")
    plate("Backpack", S, crect(1.5, 1.6, 0.2), 0.75, (0, 7.45, 1.62), (0, 0, 0), "z", "armor_dark", 1.0, 0.9, None)
    for x, y, w, h in ((-0.35, 7.8, 0.5, 0.45), (0.35, 7.8, 0.5, 0.45), (-0.35, 7.2, 0.5, 0.4)):
        plate("Grille", S, crect(w, h, 0.05), 0.08, (x, y, 2.02), (0, 0, 0), "z", "frame", 1.0, 1.0, None, bevel=0.0)
        for j in range(3):
            plate("GrilleBar", S, crect(w * 0.8, 0.04, 0.0), 0.04, (x, y - h * 0.3 + j * h * 0.3, 2.07), (0, 0, 0), "z", "joint", 1.0, 1.0, None, bevel=0.0)
    for k in (-1, 1):
        cylinder("Nozzle", S, 0.3, 0.55, (k * 0.64, 6.25, 1.85), "y", "joint", 16, rot=(25, 0, 0))


def ensure_materials():
    """The olive materials are in the file already; add bolt (brass) if it is missing."""
    if bpy.data.materials.get("bolt") is None:
        m = bpy.data.materials.new("bolt")
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0.35, 0.2, 0.05, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85


def shade_vertices():
    """Vertex color Col: faces up 1.0, faces down 0.7 (the Godot materials use it as albedo)."""
    for col in bpy.data.collections:
        if not col.name.startswith("part_"):
            continue
        for o in col.all_objects:
            if o.type != "MESH":
                continue
            me = o.data
            if "Col" in me.color_attributes:
                me.color_attributes.remove(me.color_attributes["Col"])
            ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
            rot = o.matrix_world.to_3x3().normalized()
            for v in me.vertices:
                up = (rot @ v.normal).z
                g = 0.85 + 0.15 * up
                ca.data[v.index].color = (g, g, g, 1.0)
            me.color_attributes.active_color = ca


def rebuild_preview():
    """Linked copies of the pieces on the preview rig (its bones play the run action)."""
    rig = bpy.data.objects.get("recon_gen_preview_rig")
    col = bpy.data.collections.get("preview")
    if rig is None or col is None:
        return
    for o in [o for o in col.objects if o.name.startswith("pv_")]:
        bpy.data.objects.remove(o, do_unlink=True)
    act = rig.animation_data.action if rig.animation_data else None
    slot = getattr(rig.animation_data, "action_slot", None) if rig.animation_data else None
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bone = {"Torso_core": "Torso", "Torso_head": "HeadMount", "Torso_booster": "BoosterMount", "Lower_legs": "Lower",
            "Torso_arm_l": "Torso", "Torso_arm_r": "Torso"}
    for s, a in (("L", "l"), ("R", "r")):
        bone.update({f"Shoulder{s}_arm_{a}": f"Shoulder{s}", f"Elbow{s}_arm_{a}": f"Elbow{s}", f"PauldronPivot{s}": f"PauldronPivot{s}",
                     f"Hip{s}_legs": f"Hip{s}", f"Knee{s}_legs": f"Knee{s}", f"FootPivot{s}": f"FootPivot{s}"})
    for c in bpy.data.collections:
        if not c.name.startswith("part_"):
            continue
        for o in c.all_objects:
            if o.type != "MESH" or o.parent is None or o.parent.name not in bone:
                continue
            p = o.copy()
            p.name = "pv_" + o.name
            p.modifiers.clear()
            for m in o.modifiers:
                pm = p.modifiers.new(m.name, m.type)
                for attr in ("width", "segments", "limit_method", "angle_limit"):
                    setattr(pm, attr, getattr(m, attr))
            for uc in list(p.users_collection):
                uc.objects.unlink(p)
            col.objects.link(p)
            world = Matrix.Translation((PREVIEW_OFFSET, 0, 0)) @ o.matrix_world
            p.parent = rig
            p.parent_type = "BONE"
            p.parent_bone = bone[o.parent.name]
            bpy.context.view_layer.update()
            p.matrix_world = world
    if act is not None:
        rig.animation_data.action = act
        if slot is not None:
            rig.animation_data.action_slot = slot
    bpy.context.scene.frame_set(0)


def build():
    bpy.context.scene.frame_set(0)
    ra.clear_parts()
    ra._count.clear()
    ensure_materials()
    head()
    core()
    arm("L")
    arm("R")
    legs()
    booster()
    shade_vertices()
    rebuild_preview()
    bpy.ops.wm.save_mainfile()
    exec(bpy.data.texts["export_parts.py"].as_string())


build()
