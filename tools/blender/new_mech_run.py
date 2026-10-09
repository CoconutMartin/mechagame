"""Builds the full-speed run of the new mech (models/new_mech/new_mech_exploded.blend) from the user's run
brief (2026-10-09): biped_run_full (free arm swing) and biped_run_full_unarmed (small additive arm layer for
an aim layer; the user swapped the brief's two names on 2026-10-09). 30 fps, in place (root stays at the origin), forward = -Y.

Run inside Blender with the mech file open (Text Editor: Run Script). Prints the brief's quality checks.

Brief numbers are for a 5.0 m hip height; every distance is scaled by (real hip height / 5.0).
Rig mapping (no spine split, neck, toe or piston bones): spine_lower + spine_upper = torso, neck + head
= head; legs use the leg IK (foot_ctrl, knee_pole).
Stance: the planted foot is placed by position (lands LAND ahead of the hip, moves back exactly
SPEED / FPS per frame, sole flat at 0). Swing: the leg passes through the brief's key shapes, given as
thigh angle from vertical and knee bend, blended with a monotone curve. The pelvis height is solved so
the contact knee bend is KNEE_CONTACT; the heel lifts at push-off as far as the leg needs to reach.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

RIG = "MechRig"
FEET = {"L": "Leg_L_03", "R": "Leg_R_04"}
FPS = 30
CYCLE, STEP, STANCE = 30, 15, 12  # frames
# Brief values at 5.0 m hip height (metres, degrees).
SPEED, LAND, LEAVE, SPACING = 12.0, 2.0, 2.8, 0.6
SPACING_SCALE = 1.5  # user: feet 50% further apart than the brief
BOB_LOW, BOB_HIGH, JOLT = -0.30, 0.10, -0.05
SHIFT, LEAN, YAW, ROLL = 0.06, 12.0, 4.0, 1.5  # user: less hip sway than the brief (0.15 m, 7, 3 deg)
SPINE_YAW, CHEST_PITCH, HEAD_SHARE = 5.0, 2.0, 0.3
KNEE_CONTACT, CONTACT_TOE_UP = 12.0, 8.0
# Swing shapes for the left leg: (frame, thigh angle from vertical (+ forward), knee bend, foot pitch
# (+ heel up)). Toe-off (frame 12) and contact (frame 30) come from the planted foot.
SWING = [(15, -26, 74, 30), (18, -7, 79, 8), (21, 7, 79, 0), (24, 27, 64, -12), (26, 35, 40, -12),
         (28, 32, 20, -9)]
# Heel lift during push-off (degrees, + heel up), raised further if the leg needs it to reach. Frames 7 and
# 8 lift a little early: the shin leans so far forward there that the ankle reaches its toe-up limit.
HEEL_RAMP = {7: 5.0, 8: 8.0, 9: 11.0, 10: 14.0, 11: 19.0, 12: 25.0}
ARM_SWING, ELBOW = 4.0, 55.0
UNARMED_SWING, UNARMED_ELBOW = 25.0, (40.0, 55.0)
GRIP = {"index": (55, 65, 45), "middle": (55, 65, 45), "ring": (58, 65, 45), "pinky": (60, 65, 45),
        "thumb": (30, 35, 25)}


def pchip(xs, ys, x):
    """Smooth curve through the points that never overshoots them (monotone cubic, Fritsch-Carlson)."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    m = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    d = [m[0]] + [0.0] * (n - 2) + [m[-1]]
    for i in range(1, n - 1):
        if m[i - 1] * m[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            d[i] = (w1 + w2) / (w1 / m[i - 1] + w2 / m[i])
    i = max(k for k in range(n - 1) if xs[k] <= x) if x > xs[0] else 0
    u = (x - xs[i]) / h[i]
    return ((2 * u ** 3 - 3 * u * u + 1) * ys[i] + (u ** 3 - 2 * u * u + u) * h[i] * d[i]
            + (-2 * u ** 3 + 3 * u * u) * ys[i + 1] + (u ** 3 - u * u) * h[i] * d[i + 1])


class Run:
    def __init__(self):
        self.rig = bpy.data.objects[RIG]
        self.pb, self.bones = self.rig.pose.bones, self.rig.data.bones
        self.ad = self.rig.animation_data or self.rig.animation_data_create()
        b = self.bones
        self.hip_rest = {s: b["thigh_" + s].head_local.copy() for s in "LR"}
        self.scale = (self.hip_rest["L"].z + self.hip_rest["R"].z) / 2 / 5.0
        k = self.scale
        self.travel = SPEED * k / FPS
        self.land, self.leave, self.spacing = LAND * k, LEAVE * k, SPACING * SPACING_SCALE * k
        self.thigh = {s: b["thigh_" + s].length for s in "LR"}
        self.shin = {s: b["shin_" + s].length for s in "LR"}
        self.rest_ctrl = {s: b["foot_ctrl_" + s].matrix_local.copy() for s in "LR"}
        self.pel_rest = b["pelvis"].matrix_local.copy()
        self.foot = {}
        for s, name in FEET.items():
            w = self.world_verts(name, evaluated=False)
            a = b["foot_" + s].head_local
            self.foot[s] = dict(toe=float(w[:, 1].min() - a.y), heel=float(w[:, 1].max() - a.y),
                                h=float(a.z - w[:, 2].min()))
        self.drop = 0.0

    # ---- geometry helpers ----
    def world_verts(self, name, evaluated=True):
        obj = bpy.data.objects[name]
        if evaluated:
            ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = ev.to_mesh()
        else:
            mesh = obj.data
        co = np.empty(len(mesh.vertices) * 3, np.float32)
        mesh.vertices.foreach_get("co", co)
        if evaluated:
            ev.to_mesh_clear()
        m = np.array(obj.matrix_world)
        return (m[:3, :3] @ co.reshape(-1, 3).T).T + m[:3, 3]

    def side(self, s):
        return 1.0 if s == "L" else -1.0

    def leg_frame(self, s, f):
        """Frame of the left-leg cycle that leg s is in at frame f (the right leg is 15 frames later)."""
        return (f - (0 if s == "L" else STEP)) % CYCLE

    # ---- pelvis ----
    def bob(self, f):
        u = f % STEP
        k = self.scale
        low, high = BOB_LOW * k, BOB_HIGH * k
        start = high - 0.35 * (high - low)  # on the fast drop from the flight peak to the next low
        base = pchip([0, 4, 13, 15], [start, low, high, start], u)
        jolt = JOLT * k * (u if u < 1 else max(0.0, (4 - u) / 3))  # 1-frame shock at contact, back in 3
        return base + jolt

    def pelvis_delta(self, f):
        """Pelvis motion as a matrix about the pelvis head (armature space)."""
        ph = 2 * math.pi * f / CYCLE
        yaw = -YAW * math.cos(ph)  # left hip forward at the left contact (frame 0)
        roll = -ROLL * math.cos(2 * math.pi * (f - 4) / CYCLE)  # swing-side hip drops, peak at loading
        shift = SHIFT * self.scale * math.cos(2 * math.pi * (f - 6) / CYCLE)  # toward the stance foot
        rot = (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(roll), 4, "Y")
               @ Matrix.Rotation(math.radians(LEAN), 4, "X"))
        head = self.pel_rest.translation
        off = Vector((shift, 0.0, -self.drop + self.bob(f)))
        return Matrix.Translation(head + off) @ rot @ Matrix.Translation(-head), yaw, roll

    def hip(self, s, f):
        return self.pelvis_delta(f)[0] @ self.hip_rest[s]

    # ---- feet ----
    def planted(self, s, y_flat, pitch):
        """Ankle position for a foot whose flat ankle point is at y_flat, pitched about the toe (heel up,
        +) or the heel (toe up, -)."""
        f = self.foot[s]
        pivot = Vector((0, f["toe"], -f["h"])) if pitch >= 0 else Vector((0, f["heel"], -f["h"]))
        p = pivot + Matrix.Rotation(math.radians(pitch), 3, "X") @ (-pivot)
        return Vector((self.side(s) * self.spacing, y_flat + p.y, f["h"] + p.z))

    def reach(self, s, knee):
        a, b = self.thigh[s], self.shin[s]
        return math.sqrt(a * a + b * b + 2 * a * b * math.cos(math.radians(knee)))

    def stance_pitch(self, s, k, f):
        """Foot pitch at stance frame k: heel strike, flat, then heel lift as far as the leg needs."""
        if k == 0:
            return -CONTACT_TOE_UP
        if k < min(HEEL_RAMP):
            return 0.0
        pitch = HEEL_RAMP[k]
        hip = self.hip(s, f)
        y_flat = -self.land + self.travel * k
        while (self.planted(s, y_flat, pitch) - hip).length > self.reach(s, 3.0) and pitch < 80:
            pitch += 1.0
        return pitch

    def stance_ankle(self, s, k, f):
        return self.planted(s, -self.land + self.travel * k, self.stance_pitch(s, k, f))

    def leg_angles(self, s, rel):
        """Thigh angle from vertical and knee bend for an ankle offset rel (from the hip)."""
        a, b = self.thigh[s], self.shin[s]
        d = min(rel.length, a + b - 0.001)
        knee = math.pi - math.acos(max(-1.0, min(1.0, (a * a + b * b - d * d) / (2 * a * b))))
        alpha = math.acos(max(-1.0, min(1.0, (a * a + d * d - b * b) / (2 * a * d))))
        flat = math.hypot(rel.y, rel.z)
        return math.degrees(math.atan2(-rel.y, -rel.z) + alpha * flat / d), math.degrees(knee)

    def swing_ankle(self, s, lf, f):
        """Ankle position for leg s at left-cycle frame lf (12..30) of the swing."""
        hip = self.hip(s, f)
        f12 = f - (lf - STANCE)
        f30 = f + (CYCLE - lf)
        a12 = self.stance_ankle(s, STANCE, f12)
        a30 = self.stance_ankle(s, 0, f30)
        th12, kn12 = self.leg_angles(s, a12 - self.hip(s, f12))
        th30, kn30 = self.leg_angles(s, a30 - self.hip(s, f30))
        pts = [(STANCE, th12, kn12, self.stance_pitch(s, STANCE, f12))] + list(SWING) \
            + [(CYCLE, th30, kn30, -CONTACT_TOE_UP)]
        xs = [p[0] for p in pts]
        thigh, knee, pitch = (pchip(xs, [p[j] for p in pts], lf) for j in (1, 2, 3))
        knee = min(max(knee, 3.0), 79.5)
        a, b = self.thigh[s], self.shin[s]
        t1, t2 = math.radians(thigh), math.radians(thigh - knee)
        fw, dn = a * math.sin(t1) + b * math.sin(t2), a * math.cos(t1) + b * math.cos(t2)
        lateral = self.side(s) * self.spacing - hip.x
        flat = math.sqrt(max(fw * fw + dn * dn - lateral * lateral, 0.01))  # slanted legs: keep the reach
        scale = flat / math.hypot(fw, dn)
        return Vector((hip.x + lateral, hip.y - fw * scale, hip.z - dn * scale)), pitch

    def ankle(self, s, f):
        lf = self.leg_frame(s, f)
        if lf <= STANCE:
            return self.stance_ankle(s, lf, f), self.stance_pitch(s, lf, f)
        return self.swing_ankle(s, lf, f)

    def solve_drop(self):
        """Pelvis drop from standing so the contact knee bend is KNEE_CONTACT."""
        lo, hi = 0.0, 2.5
        target = self.reach("L", KNEE_CONTACT)
        for _ in range(40):
            self.drop = (lo + hi) / 2
            d = (self.stance_ankle("L", 0, 0) - self.hip("L", 0)).length
            lo, hi = (self.drop, hi) if d > target else (lo, self.drop)
        return self.drop

    # ---- keys ----
    def limit_sign(self, bone):
        c = self.pb[bone].constraints.get("Joint limit")
        return 1 if c is None or c.max_x >= -c.min_x else -1

    def curl_sign(self, bone):
        c = self.pb[bone].constraints.get("Joint limit")
        return 1 if c is None or c.max_x > 0 else -1

    def key(self, bone, f, loc=True):
        p = self.pb[bone]
        if loc:
            p.keyframe_insert("location", frame=f, group=bone)
        p.keyframe_insert("rotation_euler", frame=f, group=bone)

    def build(self, name, armed):
        old = bpy.data.actions.get(name)
        if old:
            bpy.data.actions.remove(old)
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.ad.action = act
        self.ad.action_slot = act.slots.new("OBJECT", self.rig.name)
        pb = self.pb
        for p in pb:
            p.location = (0, 0, 0)
            p.rotation_euler = (0, 0, 0)
        for f in range(0, CYCLE + 1):
            delta, yaw, roll = self.pelvis_delta(f)
            pb["pelvis"].matrix = delta @ self.pel_rest
            self.key("pelvis", f)
            # Spine: counter-turns the pelvis (chest a little the other way), leans in at loading, and
            # reaches its lowest point 2 frames after the pelvis.
            u = f % STEP
            pitch = CHEST_PITCH * math.exp(-((u - 4) ** 2) / 6.0)
            chest_yaw = -SPINE_YAW * yaw / YAW
            lag = max(-0.04, min(0.04, 0.3 * (self.bob(f - 2) - self.bob(f))))
            pb["torso"].location = (0, lag, 0)
            pb["torso"].rotation_euler = (math.radians(pitch), math.radians(chest_yaw - yaw), 0)
            self.key("torso", f)
            pb["head"].rotation_euler = (0, 0, 0)
            for s in "LR":
                pos, ptch = self.ankle(s, f)
                rest = self.rest_ctrl[s]
                pb["foot_ctrl_" + s].matrix = (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(ptch), 4, "X")
                                               @ Matrix.Translation(-rest.translation) @ rest)
                self.key("foot_ctrl_" + s, f)
            bpy.context.view_layer.update()
            # Head: gyro-stabilised, keeps 30% of the pelvis turn and roll, sensor level.
            head = pb["head"]
            r = (Matrix.Rotation(math.radians(HEAD_SHARE * yaw), 3, "Z")
                 @ Matrix.Rotation(math.radians(HEAD_SHARE * roll), 3, "Y"))
            head.matrix = Matrix.Translation(head.head) @ (r @ self.bones["head"].matrix_local.to_3x3()).to_4x4()
            head.location = (0, 0, 0)
            self.key("head", f, loc=False)
            # Arms: opposite to the leg on the same side.
            for s, off in (("L", 0), ("R", STEP)):
                sw = math.cos(2 * math.pi * (f - off) / CYCLE)  # +1: this leg forward -> its arm back
                ua, fa, hd = "upper_arm_" + s, "forearm_" + s, "hand_" + s
                if armed:
                    swing, elbow = -ARM_SWING * sw, ELBOW
                    # Weapon and hand lag the torso by 2 frames.
                    elbow += math.degrees((self.bob(f) - self.bob(f - 2)) * 0.5 / self.bones[fa].length)
                    grip = 1.0
                else:
                    swing = -UNARMED_SWING * sw
                    elbow = UNARMED_ELBOW[0] + (UNARMED_ELBOW[1] - UNARMED_ELBOW[0]) * (0.5 - 0.5 * sw)
                    grip = 0.6
                pb[ua].rotation_euler = (math.radians(self.limit_sign(ua) * swing), 0, 0)
                pb[fa].rotation_euler = (math.radians(self.limit_sign(fa) * elbow), 0, 0)
                pb[hd].rotation_euler = (0, 0, 0)
                for n in (ua, fa, hd):
                    self.key(n, f, loc=False)
                for fn, vals in GRIP.items():
                    for i in range(3):
                        n = f"{fn}_{i + 1:02d}_{s}"
                        pb[n].rotation_euler = (math.radians(self.curl_sign(n) * vals[i] * grip), 0, 0)
                        self.key(n, f, loc=False)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        fc.modifiers.new("CYCLES")
        act.pose_markers.new("footstep_L").frame = 0
        act.pose_markers.new("footstep_R").frame = STEP
        return act

    # ---- quality checks ----
    def check(self, act):
        sc = bpy.context.scene
        pb = self.pb
        self.ad.action = act
        self.ad.action_slot = act.slots[0]
        rows = {}
        for f in range(0, CYCLE + 1):
            sc.frame_set(f)
            row = {}
            for s in "LR":
                knee = pb["shin_" + s].head
                hip, ank = pb["thigh_" + s].head, pb["shin_" + s].tail
                a, b = (knee - hip).length, (ank - knee).length
                d = (ank - hip).length
                bend = 180 - math.degrees(math.acos(max(-1, min(1, (a * a + b * b - d * d) / (2 * a * b)))))
                row[s] = dict(ankle=ank.copy(), bend=bend, low=float(self.world_verts(FEET[s])[:, 2].min()),
                              miss=(ank - pb["foot_ctrl_" + s].head).length,
                              knee=knee.copy(), hip=hip.copy())
            row["pose"] = [p.matrix.copy() for p in pb]
            rows[f] = row
        out = {}
        slide = []
        for s in "LR":
            for k in range(2, min(HEEL_RAMP)):  # flat-foot frames: the ankle moves back one travel per frame
                f0, f1 = [(k - 1 + (0 if s == "L" else STEP)) % CYCLE, (k + (0 if s == "L" else STEP)) % CYCLE]
                slide.append(rows[f1][s]["ankle"].y - rows[f0][s]["ankle"].y - self.travel)
        out["slide error max (m)"] = round(max(abs(x) for x in slide), 4)
        flat = [rows[(k + (0 if s == "L" else STEP)) % CYCLE][s]["low"] for s in "LR" for k in range(1, min(HEEL_RAMP))]
        out["sole height in contact (m)"] = (round(min(flat), 3), round(max(flat), 3))
        out["lowest sole any frame (m)"] = round(min(rows[f][s]["low"] for f in rows for s in "LR"), 3)
        bends = [rows[f][s]["bend"] for f in rows for s in "LR"]
        out["knee bend range (deg)"] = (round(min(bends), 1), round(max(bends), 1))
        out["IK miss max (m)"] = round(max(rows[f][s]["miss"] for f in rows for s in "LR"), 3)
        loop = max((a.translation - b.translation).length for a, b in zip(rows[0]["pose"], rows[CYCLE]["pose"]))
        out["loop pop frame 0 vs 30 (m)"] = round(loop, 5)
        mirror = 0.0
        for f in range(CYCLE):
            for key in ("knee", "ankle"):
                l = rows[f]["L"][key] - rows[f]["L"]["hip"]
                r = rows[(f + STEP) % CYCLE]["R"][key] - rows[(f + STEP) % CYCLE]["R"]["hip"]
                mirror = max(mirror, (Vector((-l.x, l.y, l.z)) - r).length)
        out["L/R mirror difference max (m)"] = round(mirror, 3)
        clear = max(rows[f]["L"]["low"] for f in rows)
        out["swing foot peak clearance (m)"] = round(clear, 2)
        out["contact / loading / midstance knee (deg)"] = tuple(round(rows[f]["L"]["bend"], 1) for f in (0, 4, 6))
        out["pelvis drop from standing (m)"] = round(self.drop, 3)
        return out


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.render.fps = FPS
    run = Run()
    use_nla = run.ad.use_nla
    run.ad.use_nla = False
    run.solve_drop()
    results = {}
    for name, armed in (("biped_run_full", False), ("biped_run_full_unarmed", True)):
        act = run.build(name, armed)
        results[name] = run.check(act)
    run.ad.action = None
    run.ad.use_nla = use_nla
    print(f"scale {run.scale:.3f}: travel {run.travel:.3f} m/frame, land {run.land:.2f} m ahead, "
          f"leave {run.leave:.2f} m behind, feet {run.spacing:.2f} m from the centre line")
    for name, r in results.items():
        print(name)
        for k, v in r.items():
            print(f"  {k}: {v}")
    return run, results


if __name__ == "__main__":
    main()
