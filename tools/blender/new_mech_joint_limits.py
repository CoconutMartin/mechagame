"""Sets the joint rotation limits of the new mech rig (MechRig) from part contact.

Run inside Blender with the mech file open (Text Editor: Run Script), after moving parts or bones.
1. Design limits per joint (degrees, in world terms: forward/back, outward/inward, curl).
2. Each body joint is swung through its range with the rest of the mech at rest; a direction stops
   where a part of the moving limb pushes more than TOL deeper into a part of its own parent chain
   than it does at rest (collision proxies: each bone's geometry decimated to about 1500 faces; the
   joint ball or barrel a bone turns on is ignored for that bone).
3. The result is written to each bone's "Joint limit" constraint and to its IK limits.
Fingers keep their design limits (a fist needs finger contact). Limbs touching other limbs depend on
the pose and are not limited here: check animations for clipping instead.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

RIG = "MechRig"
TOL = 0.06  # m of extra push-in allowed
STEP = 3  # degrees per test
PIVOT = {"torso": "Waist_Joint", "head": "Neck_joint", "upper_arm_L": "Arm_L_Shoulder_Joint",
         "upper_arm_R": "Arm_R_Shoulder_Joint", "forearm_L": "Elbow_L_Joint_01", "forearm_R": "Elbow_R_Joint_01",
         "thigh_L": "Leg_L_Hip_Joint", "thigh_R": "Leg_R_Hip_Joint", "shin_L": "Leg_L_Knee_Joint", "shin_R": "Leg_R_Knee_Joint"}
SWEPT = ["torso", "head"] + [f"{b}_{s}" for s in "LR" for b in ("upper_arm", "forearm", "hand", "thigh", "shin", "foot")]
FINGERS = ("index", "middle", "ring", "pinky")
# User decisions that override the contact result (degrees, same form as design_limits).
# Knees: 80 degrees of bend for the run (2026-10-09), although the shin pushes a few cm into the thigh.
OVERRIDES = {"shin_L": ((-80, 0), (0, 0), (0, 0)), "shin_R": ((-80, 0), (0, 0), (0, 0))}


def design_limits(bones):
    fwd = Vector((0, -1, 0))

    def axes(n):
        m = bones[n].matrix_local.to_3x3()
        return m.col[0], m.col[1], m.col[2]

    def pitch(n, f, b):
        z = axes(n)[2]
        return (-b, f) if z.dot(fwd) > 0 else (-f, b)

    def side(n, out_dir, out, inn):
        x = axes(n)[0]
        return (-inn, out) if (-x).dot(out_dir) > 0 else (-out, inn)

    def toward(n, d, to, away):
        z = axes(n)[2]
        return (-away, to) if z.dot(d) > 0 else (-to, away)

    lim = {"torso": (pitch("torso", 35, 20), (-40, 40), (-20, 20)),
           "head": (pitch("head", 30, 30), (-60, 60), (-25, 25))}
    for s in "LR":
        out = Vector((1, 0, 0)) if s == "L" else Vector((-1, 0, 0))
        palm = -out
        lim["upper_arm_" + s] = (pitch("upper_arm_" + s, 120, 60), (-60, 60), side("upper_arm_" + s, out, 100, 15))
        lim["forearm_" + s] = (pitch("forearm_" + s, 135, 0), (0, 0), (0, 0))
        lim["hand_" + s] = (pitch("hand_" + s, 35, 35), (-90, 90), side("hand_" + s, -palm, 45, 60))
        for f in FINGERS:
            for i in (1, 2, 3):
                n = f"{f}_{i:02d}_{s}"
                lim[n] = (toward(n, palm, 95, 10), (0, 0), (-8, 8) if i == 1 else (0, 0))
        lim[f"thumb_01_{s}"] = (toward(f"thumb_01_{s}", palm, 60, 20), (-30, 30), (-35, 35))
        for i in (2, 3):
            n = f"thumb_{i:02d}_{s}"
            lim[n] = (toward(n, palm, 80, 10), (0, 0), (0, 0))
        lim["thigh_" + s] = (pitch("thigh_" + s, 110, 65), (-35, 35), side("thigh_" + s, out, 50, 20))
        lim["shin_" + s] = (pitch("shin_" + s, 0, 140), (0, 0), (0, 0))
        lim["foot_" + s] = (toward("foot_" + s, Vector((0, 0, 1)), 30, 45), (-25, 25), (-15, 15))
    return lim


def proxies(rig):
    """Decimated triangle soups: key = bone name, or "J:<object>" for the joint pieces in PIVOT."""
    joint_objects = set(PIVOT.values())
    soup, owner = {}, {}
    for obj in [o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig]:
        me = obj.data
        me.calc_loop_triangles()
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        m = np.array(obj.matrix_world)
        co = (m[:3, :3] @ co.reshape(-1, 3).astype(float).T).T + m[:3, 3]
        tri = np.empty(len(me.loop_triangles) * 3, np.int32)
        me.loop_triangles.foreach_get("vertices", tri)
        tri = tri.reshape(-1, 3)
        names = {g.index: g.name for g in obj.vertex_groups}
        vgroup = np.array([names[v.groups[0].group] if v.groups else "" for v in me.vertices], dtype=object)
        tri_group = vgroup[tri[:, 0]]
        for bone in set(tri_group) - {""}:
            key = "J:" + obj.name if obj.name in joint_objects else bone
            soup.setdefault(key, []).append(co[tri[tri_group == bone]].reshape(-1, 3))
            owner[key] = bone
    out = {}
    for key, chunks in soup.items():
        pts = np.vstack(chunks)
        n = len(pts) // 3
        me = bpy.data.meshes.new("_proxy")
        me.from_pydata(pts.tolist(), [], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(n)])
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("_proxy", me)
        bpy.context.scene.collection.objects.link(ob)
        if len(me.polygons) > 1500:
            ob.modifiers.new("d", "DECIMATE").ratio = 1500 / len(me.polygons)
        ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        em = ev.to_mesh()
        em.calc_loop_triangles()
        v = np.empty(len(em.vertices) * 3, np.float32)
        em.vertices.foreach_get("co", v)
        t = np.empty(len(em.loop_triangles) * 3, np.int32)
        em.loop_triangles.foreach_get("vertices", t)
        out[key] = (v.reshape(-1, 3).astype(float), t.reshape(-1, 3))
        ev.to_mesh_clear()
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
    return out, owner


def main():
    rig = bpy.data.objects[RIG]
    bones, pb = rig.data.bones, rig.pose.bones
    lim = design_limits(bones)
    px, owner = proxies(rig)
    trees = {k: BVHTree.FromPolygons(v.tolist(), t.tolist(), all_triangles=True) for k, (v, t) in px.items()}
    box = {k: (v.min(0) - 0.05, v.max(0) + 0.05) for k, (v, t) in px.items()}

    def depth(verts, key):
        lo, hi = box[key]
        best = 0.0
        for p in verts[np.all((verts > lo) & (verts < hi), axis=1)]:
            loc, nor, _, d = trees[key].find_nearest(Vector(p))
            if loc is not None and (Vector(p) - loc).dot(nor) < 0 and d > best:
                best = d
        return best

    for b in SWEPT:
        moving = {b} | {c.name for c in bones[b].children_recursive}
        keys = [k for k in px if owner[k] in moving]
        chain, p = set(), bones[b].parent
        while p:
            chain.add(p.name)
            p = p.parent
        static = [k for k in px if owner[k] in chain and k != "J:" + PIVOT.get(b, "")]
        rest = bones[b].matrix_local
        inv = rest.inverted()

        def verts(t):
            m = np.array(t)
            return np.vstack([(m[:3, :3] @ px[k][0].T).T + m[:3, 3] for k in keys])

        base = {s: depth(verts(Matrix.Identity(4)), s) for s in static}
        new = []
        for i, ax in enumerate("XYZ"):
            lo, hi = lim[b][i]
            if (lo, hi) == (0, 0):
                new.append((0, 0))
                continue
            ends = []
            for sign, limit in ((-1, lo), (1, hi)):
                free = abs(limit)
                for d in list(range(STEP, int(abs(limit)), STEP)) + [abs(limit)]:
                    v = verts(rest @ Matrix.Rotation(math.radians(sign * d), 4, ax) @ inv)
                    if any(depth(v, s) > base[s] + TOL for s in static):
                        free = max(0, d - STEP)
                        break
                ends.append(sign * free)
            new.append(tuple(ends))
        lim[b] = OVERRIDES.get(b, tuple(new))
        print(f"{b:12s} {lim[b]}" + ("  (override)" if b in OVERRIDES else ""))
    for name, axes in lim.items():
        c = pb[name].constraints.get("Joint limit") or pb[name].constraints.new("LIMIT_ROTATION")
        c.name = "Joint limit"
        c.owner_space = "LOCAL"
        c.use_transform_limit = True
        for ax, (lo, hi) in zip("xyz", axes):
            setattr(c, "use_limit_" + ax, True)
            setattr(c, "min_" + ax, math.radians(lo))
            setattr(c, "max_" + ax, math.radians(hi))
            setattr(pb[name], "use_ik_limit_" + ax, True)
            setattr(pb[name], "ik_min_" + ax, math.radians(lo))
            setattr(pb[name], "ik_max_" + ax, math.radians(hi))
            setattr(pb[name], "lock_ik_" + ax, (lo, hi) == (0, 0))
    return lim


if __name__ == "__main__":
    main()
