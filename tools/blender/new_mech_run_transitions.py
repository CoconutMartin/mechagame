"""Builds biped_run_start (idle to full speed) and biped_run_stop (full speed to idle) for the new mech, from
the user's run brief (2026-10-09). Run inside Blender with models/new_mech/new_mech_exploded.blend open, after
new_mech_run.py (it uses that script's leg math, and joins biped_run_full exactly: the start ends on its
frame 0, the stop starts on its frame 0).

Both actions are in place (root at the origin): planted feet move back at the body speed of that frame, so
the speed rises step by step in the start and falls in the stop. Brief distances are scaled by the hip
height (/ 5.0 m). Timeline (frames at 30 fps):
  start: 0-8 crouch from Idle (knees 25, lean 20); left swing 6-17 (step 1, right foot planted 16 frames,
         no flight); left stance 17-30 (13 frames), short flight; right lands 33 (step 2); 33-48 step 3 at
         full speed; frame 48 = biped_run_full frame 0.
  stop:  0 = biped_run_full frame 0; right foot brakes 3.0 m ahead at 12 (lean back 12, knees about 50,
         pelvis down 0.6 m), skids forward 1.5 m in the game until 24; left stutter step lands 24 (lean
         back 6); right foot steps in beside it at 36 (idle width); overshoot forward 4, settle to Idle by 48
         (48 frames, not the brief's 45: the body needs that long to slow down over the skidding foot).
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

RUN_SCRIPT = os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "tools", "blender", "new_mech_run.py")
GRIP_IDLE, GRIP_RUN = 0.25, 0.6
SWING_CLEAR = 0.2  # m at 5.0 m hip height: lowest mid-swing sole clearance
ANKLE_UP = 26.0  # degrees the toes can bend up against the shin (joint limit 30, minus a margin)
ANKLE_DOWN = 40.0  # degrees the toes can point down against the shin (joint limit 45, minus a margin)


def load_run():
    g = {"__name__": "new_mech_run"}
    exec(compile(open(os.path.normpath(RUN_SCRIPT)).read(), RUN_SCRIPT, "exec"), g)
    return g


def pchip_keys(keys, f, pchip):
    xs = [k[0] for k in keys]
    if f <= xs[0]:
        return keys[0][1]
    if f >= xs[-1]:
        return keys[-1][1]
    return pchip(xs, [k[1] for k in keys], f)


def make_transition_class(g):
    Run = g["Run"]
    pchip = g["pchip"]
    CYCLE, STEP, STANCE = g["CYCLE"], g["STEP"], g["STANCE"]
    SWING = g["SWING"]

    class Transition(Run):
        """One non-looping action. Subclasses fill: frames, body speed u(f) (m/frame), pelvis channels,
        a run-blend weight w(f), the run frame rf(f) that sets the swing of arms and hips, and per-leg plans."""

        def __init__(self, run):
            super().__init__()
            self.run = run  # solved full run (drop, bob, pelvis)
            self.drop = run.drop
            b = self.bones
            self.rest_ankle = {s: b["foot_" + s].head_local.copy() for s in "LR"}
            self.plans = {}
            self.markers = []
            self._plant_cache = {}

        # ---- pelvis ----
        def pelvis_delta(self, f):
            z, lean, w = self.pelvis_z(f), self.lean(f), self.w(f)
            rf = self.rf(f)
            ph = 2 * math.pi * rf / CYCLE
            yaw = -g["YAW"] * math.cos(ph) * w
            roll = -g["ROLL"] * math.cos(2 * math.pi * (rf - 4) / CYCLE) * w
            shift = g["SHIFT"] * self.scale * math.cos(2 * math.pi * (rf - 6) / CYCLE) * w
            rot = (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(roll), 4, "Y")
                   @ Matrix.Rotation(math.radians(lean), 4, "X"))
            head = self.pel_rest.translation
            return Matrix.Translation(head + Vector((shift, 0.0, z))) @ rot @ Matrix.Translation(-head), yaw, roll

        def run_z(self, rf):
            return -self.run.drop + self.run.bob(rf)

        # ---- feet ----
        def travel_between(self, f0, f1, s):
            return sum(self.u(f, s) for f in range(f0 + 1, f1 + 1))

        def plant_y(self, s, seg, f):
            return seg["y"] + self.travel_between(seg["f0"], f, s)

        def plant_pose(self, s, seg, f):
            """Ankle and pitch of a planted foot: heel strike (if it is a contact), flat, then heel lift as far
            as the leg needs (plus the segment's own lift ramp)."""
            y = self.plant_y(s, seg, f)
            k = f - seg["f0"]
            pitch = 0.0
            if seg.get("contact") and k == 0:
                pitch = -seg.get("toe_up", g["CONTACT_TOE_UP"])
            ramp = seg.get("ramp", {})
            if f - seg["f1"] in ramp:
                pitch = ramp[f - seg["f1"]]
            hip = self.hip(s, f)
            x = seg["x"]
            if pitch >= 0:
                # The ankle can only bend the toes up ANKLE_UP against the shin: when the shin leans further
                # forward over the foot, the heel lifts instead of the foot tipping into the ground.
                th, kn = self.leg_angles(s, self.planted_x(s, x, y, pitch) - hip)
                over = -(th - kn) - ANKLE_UP
                if over > pitch:
                    pitch = over
            # Out of reach: a foot behind the hip lifts its heel (the ankle rolls toward the hip over the
            # toe); a foot ahead of the hip rocks back on its heel, toes up (the ankle rolls back).
            behind = y > hip.y
            step = 1.0 if behind else -1.0
            if not behind and pitch > 0:
                pitch = 0.0
            while -30 < pitch < 80:
                pos = self.planted_x(s, x, y, pitch)
                if (pos - hip).length <= self.reach(s, 3.0):
                    break
                pitch += step
            return self.planted_x(s, x, y, pitch), pitch

        def planted_x(self, s, x, y_flat, pitch):
            f = self.foot[s]
            pivot = Vector((0, f["toe"], -f["h"])) if pitch >= 0 else Vector((0, f["heel"], -f["h"]))
            p = pivot + Matrix.Rotation(math.radians(pitch), 3, "X") @ (-pivot)
            return Vector((x, y_flat + p.y, f["h"] + p.z))

        def swing_pose(self, s, seg, f):
            """Swing from the end of the plant before to the start of the plant after, through the segment's
            key shapes (frame, thigh, knee, pitch) blended by joint angle; a foot too close to the hip for the
            knee limit is pushed straight away from it."""
            before, after = seg["before"], seg["after"]
            a0, p0 = self.plant_pose(s, before, before["f1"])
            a1, p1 = after["fn"](after["f0"]) if after["kind"] == "fn" else self.plant_pose(s, after, after["f0"])
            th0, kn0 = self.leg_angles(s, a0 - self.hip(s, before["f1"]))
            th1, kn1 = self.leg_angles(s, a1 - self.hip(s, after["f0"]))
            pts = [(seg["f0"], th0, kn0, p0)] + [k for k in seg["keys"] if seg["f0"] < k[0] < seg["f1"]] \
                + [(seg["f1"], th1, kn1, p1)]
            xs = [p[0] for p in pts]
            thigh, knee, pitch = (pchip(xs, [p[j] for p in pts], f) for j in (1, 2, 3))
            knee = min(max(knee, 3.0), 79.5)
            pitch = self.ankle_range(thigh - knee, pitch)
            a, b = self.thigh[s], self.shin[s]
            t1, t2 = math.radians(thigh), math.radians(thigh - knee)
            fw, dn = a * math.sin(t1) + b * math.sin(t2), a * math.cos(t1) + b * math.cos(t2)
            hip = self.hip(s, f)
            u = (f - seg["f0"]) / (seg["f1"] - seg["f0"])
            x = a0.x + (a1.x - a0.x) * (u * u * (3 - 2 * u))
            lateral = x - hip.x
            flat = math.sqrt(max(fw * fw + dn * dn - lateral * lateral, 0.01))
            sc = flat / math.hypot(fw, dn)
            fw, dn = fw * sc, dn * sc
            near = self.dmin_knee(s)
            d = math.hypot(fw, dn)
            if d < near:
                fw, dn = fw * near / d, dn * near / d
            return self.above_ground(s, Vector((x, hip.y - fw, hip.z - dn)), pitch, u, hip), pitch

        def above_ground(self, s, pos, pitch, u, hip):
            """Keeps a swinging sole above the ground: at least SWING_CLEAR mid-swing, easing to 0 at the
            push-off and the landing. The lift never brings the foot closer to the hip than the knee limit
            allows (that would over-bend the knee)."""
            floor = self.planted_x(s, pos.x, pos.y, pitch).z + SWING_CLEAR * self.scale * math.sin(math.pi * u) ** 0.6
            near = self.dmin_knee(s)
            flat2 = (pos.x - hip.x) ** 2 + (pos.y - hip.y) ** 2
            floor = min(floor, hip.z - math.sqrt(max(near * near - flat2, 0.0)))
            if pos.z < floor:
                pos = Vector((pos.x, pos.y, floor))
            return pos

        def ankle_range(self, shin, pitch):
            """Foot pitch (+ heel up) the ankle can hold against a shin at `shin` degrees from vertical
            (+ bottom forward): toes up at most ANKLE_UP, down at most ANKLE_DOWN."""
            return min(max(pitch, -shin - ANKLE_UP), -shin + ANKLE_DOWN)

        def dmin_knee(self, s):
            return self.reach(s, 78.0) + 0.05

        def ankle(self, s, f):
            for seg in self.plans[s]:
                if seg["f0"] <= f <= seg["f1"]:
                    if seg["kind"] == "plant":
                        return self.plant_pose(s, seg, f)
                    if seg["kind"] == "swing":
                        return self.swing_pose(s, seg, f)
                    return seg["fn"](f)
            raise ValueError(f"no plan for {s} at frame {f}")

        def link(self):
            for s in "LR":
                segs = self.plans[s]
                for i, seg in enumerate(segs):
                    if seg["kind"] == "swing":
                        seg["before"], seg["after"] = segs[i - 1], segs[i + 1]

        # ---- keys ----
        def build_action(self, name):
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
            for f in range(self.first, self.last + 1):
                delta, yaw, roll = self.pelvis_delta(f)
                pb["pelvis"].matrix = delta @ self.pel_rest
                self.key("pelvis", f)
                w, rf = self.w(f), self.rf(f)
                pitch, torso_yaw, lag = self.torso_pose(f, yaw, w, rf)
                pb["torso"].location = (0, lag, 0)
                pb["torso"].rotation_euler = (math.radians(pitch), math.radians(torso_yaw), 0)
                self.key("torso", f)
                self.extra_keys(f)
                pb["head"].rotation_euler = (0, 0, 0)
                for s in "LR":
                    pos, ptch = self.ankle(s, f)
                    rest = self.rest_ctrl[s]
                    pb["foot_ctrl_" + s].matrix = self.foot_matrix(s, f, pos, ptch)
                    self.key("foot_ctrl_" + s, f)
                bpy.context.view_layer.update()
                head = pb["head"]
                r = self.head_rotation(f, yaw, roll)
                head.matrix = Matrix.Translation(head.head) @ (r @ self.bones["head"].matrix_local.to_3x3()).to_4x4()
                head.location = (0, 0, 0)
                self.key("head", f, loc=False)
                for s, off in (("L", 0), ("R", STEP)):
                    ua, fa, hd = "upper_arm_" + s, "forearm_" + s, "hand_" + s
                    swing, elbow, out = self.arm_pose(s, f, w, rf)
                    pb[ua].rotation_euler = (math.radians(self.limit_sign(ua) * swing), 0,
                                             math.radians(out) * self.out_sign(ua))
                    pb[fa].rotation_euler = (math.radians(self.limit_sign(fa) * elbow), 0, 0)
                    pb[hd].rotation_euler = (0, 0, 0)
                    for n in (ua, fa, hd):
                        self.key(n, f, loc=False)
                    grip = GRIP_IDLE + (GRIP_RUN - GRIP_IDLE) * w
                    for fn, vals in g["GRIP"].items():
                        for i in range(3):
                            n = f"{fn}_{i + 1:02d}_{s}"
                            pb[n].rotation_euler = (math.radians(self.curl_sign(n) * vals[i] * grip), 0, 0)
                            self.key(n, f, loc=False)
            for marker, frame in self.markers:
                act.pose_markers.new(marker).frame = frame
            return act

        def idle_arm(self, s):
            return 3.0, 12.0

        def ground_fix(self, act, passes=4):
            """Last pass: where a sole still dips below the ground (a wide or rolled foot stopped by the ankle
            limit), lift that foot's control until its lowest point sits on the ground."""
            sc = bpy.context.scene
            curves = {s: next(fc for layer in act.layers for st in layer.strips for cb in st.channelbags
                              for fc in cb.fcurves if fc.data_path == f'pose.bones["foot_ctrl_{s}"].location'
                              and fc.array_index == 2) for s in "LR"}
            feet = {"L": "Leg_L_03", "R": "Leg_R_04"}
            for _ in range(passes):
                worst = 0.0
                for f in range(self.first, self.last + 1):
                    sc.frame_set(f)
                    for s in "LR":
                        dip = -float(self.world_verts(feet[s])[:, 2].min())
                        if dip > 0.003:
                            for kp in curves[s].keyframe_points:
                                if abs(kp.co.x - f) < 0.01:
                                    kp.co.y += dip
                                    kp.handle_left.y += dip
                                    kp.handle_right.y += dip
                            worst = max(worst, dip)
                for fc in curves.values():
                    fc.update()
                if worst < 0.005:
                    break

        # ---- hooks (the Akira slide overrides them) ----
        def torso_pose(self, f, yaw, w, rf):
            """Chest pitch, torso turn against the pelvis (degrees) and the 2-frame vertical lag."""
            u = rf % STEP
            pitch = g["CHEST_PITCH"] * math.exp(-((u - 4) ** 2) / 6.0) * w + self.chest_extra(f)
            chest_yaw = -g["SPINE_YAW"] * yaw / g["YAW"] if g["YAW"] else 0.0
            lag = max(-0.04, min(0.04, 0.3 * (self.run.bob(rf - 2) - self.run.bob(rf)))) * w
            return pitch, chest_yaw - yaw, lag

        def foot_matrix(self, s, f, pos, pitch):
            rest = self.rest_ctrl[s]
            return (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(pitch), 4, "X")
                    @ Matrix.Translation(-rest.translation) @ rest)

        def head_rotation(self, f, yaw, roll):
            """Head turn in the world: keeps HEAD_SHARE of the pelvis turn and roll, sensor level."""
            return (Matrix.Rotation(math.radians(g["HEAD_SHARE"] * yaw), 3, "Z")
                    @ Matrix.Rotation(math.radians(g["HEAD_SHARE"] * roll), 3, "Y"))

        def arm_pose(self, s, f, w, rf):
            """Shoulder swing, elbow bend and arm out to the side (degrees): idle blended into the run."""
            off = 0 if s == "L" else STEP
            sw = math.cos(2 * math.pi * (rf - off) / CYCLE)
            run_swing = -g["UNARMED_SWING"] * sw
            lo, hi = g["UNARMED_ELBOW"]
            run_elbow = lo + (hi - lo) * (0.5 - 0.5 * sw)
            idle_swing, idle_elbow = self.idle_arm(s)
            return idle_swing + (run_swing - idle_swing) * w, idle_elbow + (run_elbow - idle_elbow) * w, 0.0

        def extra_keys(self, f):
            pass

        def out_sign(self, bone):
            """Sign of a local Z turn that moves the bone's tail away from the body."""
            x = self.bones[bone].matrix_local.to_3x3().col[0]
            side = 1 if self.bones[bone].head_local.x > 0 else -1
            return 1 if (-x).x * side > 0 else -1

        def chest_extra(self, f):
            return 0.0

    return Transition


def make_start(g, run, Transition):
    pchip = g["pchip"]
    STEP, CYCLE = g["STEP"], g["CYCLE"]
    full = run.travel

    class Start(Transition):
        first, last = 0, 48
        C1, C2, E = 17, 33, 48  # left contact, right contact, left contact = run frame 0

        def __init__(self, run):
            super().__init__(run)
            k = self.scale
            self.step_target = (3.5 * k, 5.0 * k, 6.0 * k)
            self.crouch_z = self.solve_crouch(25.0)
            ra = self.rest_ankle
            # Run frame that drives the hip and arm swing: steps map onto the run's steps.
            self.rf_keys = [(3, -15.0), (self.C1, 0.0), (self.C2, 15.0), (self.E, 30.0)]
            x_run = {s: self.side(s) * self.spacing for s in "LR"}
            # Right foot planted from the start until its toe-off (step 1: long stance, no flight).
            r_plant = dict(kind="plant", f0=0, f1=19, y=ra["R"].y, x=ra["R"].x, ramp={-2: 6.0, -1: 12.0, 0: 20.0})
            # Left foot: leaves the idle stance at 6, lands step 1 at C1 such that the step is 3.5 m (scaled).
            y_r_at_c1 = ra["R"].y + self.travel_between(0, self.C1, "R")
            l_land = y_r_at_c1 - self.step_target[0]
            l_idle = dict(kind="plant", f0=0, f1=6, y=ra["L"].y, x=ra["L"].x, ramp={-1: 6.0, 0: 14.0})
            l_plant = dict(kind="plant", f0=self.C1, f1=30, y=l_land, x=x_run["L"], contact=True,
                           ramp={-3: 11.0, -2: 14.0, -1: 19.0, 0: 25.0})
            r_run_plant = dict(kind="plant", f0=self.C2, f1=self.C2 + 12, y=-run.land, x=x_run["R"], contact=True,
                               ramp={k - 12: v for k, v in g["HEEL_RAMP"].items()})
            # Swings use the run's key shapes, squeezed into their frames.
            def keys(f0, f1):
                return [(f0 + (kf - 12) * (f1 - f0) / 18.0, th, kn, p) for kf, th, kn, p in g["SWING"]]
            l_swing1 = dict(kind="swing", f0=6, f1=self.C1, keys=self.small_keys(6, self.C1))
            r_swing = dict(kind="swing", f0=19, f1=self.C2, keys=keys(19, self.C2))
            # From 33 the left leg is the run's own (its frame 15 on), reached from the toe-off at 30.
            l_run = dict(kind="fn", f0=self.C2, f1=self.E, fn=lambda f: run.ankle("L", (f - self.E) % CYCLE))
            l_swing2 = dict(kind="swing", f0=30, f1=self.C2, keys=[])
            r_end = dict(kind="fn", f0=self.C2 + 13, f1=self.E, fn=lambda f: run.ankle("R", (f - self.E) % CYCLE))
            self.plans = {"L": [l_idle, l_swing1, l_plant, l_swing2, l_run], "R": [r_plant, r_swing, r_run_plant, r_end]}
            self.link()
            self.markers = [("footstep_L", self.C1), ("footstep_R", self.C2)]

        def small_keys(self, f0, f1):
            """First step from standing: a short, low swing."""
            n = f1 - f0
            return [(f0 + 0.35 * n, -12, 45, 15), (f0 + 0.65 * n, 14, 40, 0)]

        def u(self, f, s=None):
            """Body speed in metres per frame: still while crouching, then up to full by the right contact."""
            if f <= 4:
                return 0.0
            return full * min(1.0, (f - 4) / (self.C2 - 4))

        def w(self, f):
            x = min(max((f - 6) / (self.C2 - 6), 0.0), 1.0)
            return x * x * (3 - 2 * x)

        def rf(self, f):
            return pchip_keys(self.rf_keys, f, pchip)

        def lean(self, f):
            return pchip_keys([(0, 1.0), (8, 20.0), (self.C1, 16.0), (self.C2, 12.0)], f, pchip)

        def pelvis_z(self, f):
            idle = -0.12
            crouch = pchip_keys([(0, idle), (8, self.crouch_z)], f, pchip)
            w = self.w(f)
            return crouch * (1 - w) + self.run_z(self.rf(f)) * w

        def solve_crouch(self, knee):
            """Pelvis height (offset from rest) that bends the standing knees to `knee` degrees."""
            s = "R"
            ankle = self.rest_ankle[s]
            hip0 = self.hip_rest[s]
            d = self.reach(s, knee)
            flat2 = (hip0.x - ankle.x) ** 2 + (hip0.y - ankle.y) ** 2
            return (ankle.z + math.sqrt(max(d * d - flat2, 0.0))) - hip0.z

    return Start(run)


def make_stop(g, run, Transition):
    pchip = g["pchip"]
    CYCLE = g["CYCLE"]
    full = run.travel
    k = run.scale

    class Stop(Transition):
        first, last = 0, 48
        BRAKE, SKID_END, STUTTER, STEP_IN = 12, 24, 24, 36

        def __init__(self, run):
            super().__init__(run)
            ra = self.rest_ankle
            self.skid = 1.5 * k / (self.SKID_END - self.BRAKE)  # the braking foot slides forward in the game
            x_run = {s: self.side(s) * self.spacing for s in "LR"}
            # Left foot: planted at run frame 0, until it pushes off at 14.
            l_plant = dict(kind="plant", f0=0, f1=14, y=-run.land, x=x_run["L"], contact=True,
                           ramp={-3: 8.0, -2: 14.0, -1: 20.0, 0: 26.0})
            # Right foot: in the run's early swing at frame 0, brakes 3.0 m ahead at 12, skids, lifts at 28.
            r_brake = dict(kind="plant", f0=self.BRAKE, f1=28, y=-3.0 * k, x=x_run["R"], contact=True, toe_up=15.0,
                           ramp={-1: 6.0, 0: 12.0})
            # Left stutter step lands at 24, placed so it ends on its idle place when the body has stopped.
            y_l = ra["L"].y - self.travel_between(self.STUTTER, self.last, "L")
            l_stutter = dict(kind="plant", f0=self.STUTTER, f1=self.last, y=y_l, x=ra["L"].x, contact=True)
            r_in = dict(kind="plant", f0=self.STEP_IN, f1=self.last, y=ra["R"].y - self.travel_between(self.STEP_IN, self.last, "R"),
                        x=ra["R"].x, contact=True, toe_up=4.0)
            run_keys = [(0 + (kf - 15) * self.BRAKE / 15.0, th, kn, p) for kf, th, kn, p in g["SWING"] if kf > 15]
            r_start = dict(kind="fn", f0=0, f1=0, fn=lambda f: run.ankle("R", 0))
            r_swing1 = dict(kind="swing", f0=0, f1=self.BRAKE, keys=run_keys)
            l_swing = dict(kind="swing", f0=14, f1=self.STUTTER, keys=[(17, -18, 55, 20), (21, 18, 45, -5)])
            r_swing2 = dict(kind="swing", f0=28, f1=self.STEP_IN, keys=[(30, -10, 50, 15), (33, 4, 35, 0)])
            self.plans = {"L": [l_plant, l_swing, l_stutter], "R": [r_start, r_swing1, r_brake, r_swing2, r_in]}
            # the first right swing starts from the run's frame-0 pose
            r_swing1["before"] = None
            self.link_stop()
            self.markers = [("footstep_R", self.BRAKE), ("skid_start", self.BRAKE), ("skid_end", self.SKID_END),
                            ("footstep_L", self.STUTTER), ("footstep_R", self.STEP_IN)]

        def link_stop(self):
            for s in "LR":
                segs = self.plans[s]
                for i, seg in enumerate(segs):
                    if seg["kind"] == "swing":
                        seg["before"], seg["after"] = segs[i - 1], segs[i + 1]

        def plant_pose(self, s, seg, f):
            if seg["kind"] == "fn":
                return seg["fn"](f)
            return super().plant_pose(s, seg, f)

        def swing_pose(self, s, seg, f):
            if seg["before"]["kind"] == "fn":
                # Starts from the run's frame-0 swing: use its pose and angles as the first point.
                a0, p0 = run.ankle(s, 0)
                hip0 = self.hip(s, 0)
                th0, kn0 = self.leg_angles(s, a0 - hip0)
                saved = seg["before"]
                seg["before"] = dict(kind="plant", f0=0, f1=0, y=0, x=a0.x)
                try:
                    self._fixed0 = (a0, p0)
                    return self._swing_from(s, seg, f, (th0, kn0, p0, a0))
                finally:
                    seg["before"] = saved
            return super().swing_pose(s, seg, f)

        def _swing_from(self, s, seg, f, start):
            th0, kn0, p0, a0 = start
            after = seg["after"]
            a1, p1 = self.plant_pose(s, after, after["f0"])
            th1, kn1 = self.leg_angles(s, a1 - self.hip(s, after["f0"]))
            pts = [(seg["f0"], th0, kn0, p0)] + [kk for kk in seg["keys"] if seg["f0"] < kk[0] < seg["f1"]] \
                + [(seg["f1"], th1, kn1, p1)]
            xs = [p[0] for p in pts]
            thigh, knee, pitch = (pchip(xs, [p[j] for p in pts], f) for j in (1, 2, 3))
            knee = min(max(knee, 3.0), 79.5)
            pitch = self.ankle_range(thigh - knee, pitch)
            a, b = self.thigh[s], self.shin[s]
            t1, t2 = math.radians(thigh), math.radians(thigh - knee)
            fw, dn = a * math.sin(t1) + b * math.sin(t2), a * math.cos(t1) + b * math.cos(t2)
            hip = self.hip(s, f)
            lateral = a0.x + (a1.x - a0.x) * ((f - seg["f0"]) / (seg["f1"] - seg["f0"])) - hip.x
            flat = math.sqrt(max(fw * fw + dn * dn - lateral * lateral, 0.01))
            sc = flat / math.hypot(fw, dn)
            fw, dn = fw * sc, dn * sc
            near = self.dmin_knee(s)
            d = math.hypot(fw, dn)
            if d < near:
                fw, dn = fw * near / d, dn * near / d
            u = (f - seg["f0"]) / (seg["f1"] - seg["f0"])
            return self.above_ground(s, Vector((hip.x + lateral, hip.y - fw, hip.z - dn)), pitch, u, hip), pitch

        def ankle(self, s, f):
            if f == 0:
                return run.ankle(s, 0)
            return super().ankle(s, f)

        def u(self, f, s=None):
            """Body speed (m/frame): full until the brake, then falls evenly to 0 at frame 46 (that carries the
            body over the skidding foot and puts both feet on their idle places). The braking foot skids
            forward in the game, so in place it moves back slower than the body."""
            v = full * max(0.0, 1.0 - (f - self.BRAKE) / 34.0) if f > self.BRAKE else full
            if s == "R" and self.BRAKE < f <= self.SKID_END:
                v -= self.skid
            return v

        def w(self, f):
            x = min(max(1.0 - f / 20.0, 0.0), 1.0)
            return x * x * (3 - 2 * x)

        def rf(self, f):
            return min(f, 14.0) * 1.0

        def lean(self, f):
            return pchip_keys([(0, 12.0), (self.BRAKE, -12.0), (self.STUTTER, -6.0), (self.STEP_IN, 4.0),
                               (self.last, 1.0)], f, pchip)

        def pelvis_z(self, f):
            k_ = self.scale
            brake = self.run_z(0) - 0.6 * k_
            # Down 0.6 m at the brake; up again while the left leg passes under the hip (a lower pelvis
            # leaves no room for it with the knee limit), down as it lands, then up to the idle height.
            r0 = self.run_z(0)
            keys = [(0, r0), (5, r0 + 0.06), (8, r0 - 0.03), (self.BRAKE, r0 - 0.25 * k_), (15, brake), (17, brake), (20, r0 + 0.05),
                    (self.STUTTER + 2, r0 - 0.2 * k_), (self.STEP_IN, -0.20), (self.STEP_IN + 4, -0.08),
                    (self.last, -0.12)]
            return pchip_keys(keys, f, pchip)

        def chest_extra(self, f):
            return 0.0

    return Stop(run)


def make_akira(g, run, Transition):
    """Akira-style power slide stop. The body whips 90 degrees to the right and skids sideways (frames 0-30),
    low and leaning back against the slide, left side leading; then it turns back to the original direction
    with two pivot steps (30-52), takes 3 small steps forward (58, 68, 78), steps in (88) and settles on the
    Idle pose facing forward (100). In place: planted feet move back at the body speed of each frame."""
    pchip = g["pchip"]
    k = run.scale
    full = run.travel
    sm = lambda x: x * x * (3 - 2 * x)
    clamp01 = lambda x: min(max(x, 0.0), 1.0)

    def keys_at(keys, f):
        return pchip_keys(keys, f, pchip)

    class Akira(Transition):
        first, last = 0, 100
        PLANT_R, TURN_FULL, SLIDE_END = 8, 22, 30
        CONTACTS = [("R", 40), ("L", 50), ("R", 58), ("L", 68), ("R", 78), ("L", 88)]
        YAW = [(0, 0.0), (4, -8.0), (8, -25.0), (16, -68.0), (22, -90.0), (30, -90.0), (36, -72.0), (42, -42.0),
               (48, -12.0), (52, 0.0), (100, 0.0)]
        LEAN_BACK = [(0, 0.0), (8, 5.4), (14, 12.0), (30, 12.0), (40, 4.0), (50, 0.0), (100, 0.0)]
        LEAN_FWD = [(0, g["LEAN"]), (8, 4.0), (14, 0.0), (40, 0.0), (56, 5.0), (84, 5.0), (90, 6.0), (95, 2.0),
                    (100, 1.0)]
        WALK_SPEED = 0.11  # m/frame at 5.0 m hip height: the small steps

        def __init__(self, run):
            super().__init__(run)
            ra = self.rest_ankle
            self.l_slide, self.r_slide = Vector((2.2 * k / 1.18, -0.2)), Vector((-3.6 * k / 1.18, 1.0))
            self.l_contact = Vector((self.side("L") * self.spacing, -run.land + full * 4))
            self.pole_rest = {s: self.bones["knee_pole_" + s].matrix_local.copy() for s in "LR"}
            self.walk_v = self.WALK_SPEED * k
            wx = 1.6 * k / 1.18
            # After the slide: plants in the root frame (x, landing y, foot turn) and swings between them.
            y_r2 = ra["R"].y - self.travel_between(78, self.last)
            y_l3 = ra["L"].y - self.travel_between(88, self.last)
            self.segs = {
                "L": [dict(kind="slide", f0=0, f1=40),
                      dict(kind="swing", f0=40, f1=50, clear=0.45),
                      dict(kind="plant", f0=50, f1=60, x=wx, y=-0.3, yaw=0.0, toeoff=True),
                      dict(kind="swing", f0=60, f1=68, clear=0.35),
                      dict(kind="plant", f0=68, f1=80, x=wx, y=-0.9, yaw=0.0, contact=True, toeoff=True),
                      dict(kind="swing", f0=80, f1=88, clear=0.3),
                      dict(kind="plant", f0=88, f1=self.last, x=ra["L"].x, y=y_l3, yaw=0.0, contact=True)],
                "R": [dict(kind="slide", f0=0, f1=self.SLIDE_END),
                      dict(kind="swing", f0=self.SLIDE_END, f1=40, clear=0.6),
                      dict(kind="plant", f0=40, f1=50, x=-wx, y=0.7, yaw=-40.0, yaw_end=-5.0, toeoff=True),
                      dict(kind="swing", f0=50, f1=58, clear=0.35),
                      dict(kind="plant", f0=58, f1=70, x=-wx, y=-0.9, yaw=0.0, contact=True, toeoff=True),
                      dict(kind="swing", f0=70, f1=78, clear=0.35),
                      dict(kind="plant", f0=78, f1=self.last, x=ra["R"].x, y=y_r2, yaw=0.0, contact=True)]}
            self.slide_end_pose = {"R": self.placed("R", self.SLIDE_END), "L": self.placed("L", 40)}
            self.plans = {s: [dict(kind="plant", f0=sg["f0"], f1=sg["f1"]) for sg in self.segs[s]
                              if sg["kind"] in ("plant", "slide")] for s in "LR"}
            self.markers = [("footstep_R", self.PLANT_R), ("slide_start", self.PLANT_R), ("slide_end", self.SLIDE_END)] \
                + [("footstep_" + s, f) for s, f in self.CONTACTS]

        # ---- timing ----
        def yaw(self, f):
            return keys_at(self.YAW, f)

        def turn(self, f):
            return Matrix.Rotation(math.radians(self.yaw(f)), 4, "Z")

        def u(self, f, s=None):
            """Body speed (m/frame): still after the slide, up to the small-step speed, then down to 0."""
            if f <= 52:
                return 0.0
            up = clamp01((f - 52) / 6.0)
            down = clamp01((92 - f) / 16.0)
            return self.walk_v * sm(min(up, down))

        def travel_between(self, f0, f1, s=None):
            return sum(self.u(f) for f in range(f0 + 1, f1 + 1))

        def w(self, f):  # run arms, fists and hip sway fade out over the slide
            return sm(clamp01(1.0 - f / 30.0))

        def slide(self, f):  # slide pose weight
            return sm(min(clamp01(f / 10.0), clamp01((44 - f) / 14.0)))

        def walk(self, f):  # small-step weight
            return sm(min(clamp01((f - 50) / 8.0), clamp01((92 - f) / 8.0)))

        def rf(self, f):
            return float(f)

        # ---- pelvis ----
        def pelvis_delta(self, f):
            head = self.pel_rest.translation
            r0 = self.run_z(0)
            z = keys_at([(0, r0), (self.PLANT_R, r0 - 0.3 * k), (14, -0.55 * k), (self.SLIDE_END, -0.55 * k),
                         (40, -0.45 * k), (50, -0.3 * k), (58, -0.28), (78, -0.28), (88, -0.22), (94, -0.08),
                         (self.last, -0.12)], f)
            for s, c in self.CONTACTS:  # each step lands with a small dip
                z -= 0.05 * k * math.exp(-((f - c - 3) ** 2) / 6.0)
            yaw, roll, shift = self.run_sway(f)
            base = (Matrix.Translation(head + Vector((shift, 0.0, z))) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                    @ Matrix.Rotation(math.radians(roll), 4, "Y")
                    @ Matrix.Rotation(math.radians(keys_at(self.LEAN_FWD, f)), 4, "X") @ Matrix.Translation(-head))
            turned = self.turn(f) @ base
            h = turned @ head
            back = (Matrix.Translation(h) @ Matrix.Rotation(math.radians(-keys_at(self.LEAN_BACK, f)), 4, "X")
                    @ Matrix.Translation(-h))
            return back @ turned, yaw, roll

        def run_sway(self, f):
            """The run's own hip turn, roll and side shift, fading out (frame 0 matches the run)."""
            w = self.w(f)
            yaw = -g["YAW"] * math.cos(2 * math.pi * f / g["CYCLE"]) * w
            roll = -g["ROLL"] * math.cos(2 * math.pi * (f - 4) / g["CYCLE"]) * w
            shift = g["SHIFT"] * k * math.cos(2 * math.pi * (f - 6) / g["CYCLE"]) * w
            return yaw, roll, shift

        # ---- feet ----
        def foot_local(self, s, f):
            """Slide foot place in the turning frame (before the turn about the root), and its pitch."""
            if s == "L":
                # Moves back at full run speed for the first frames, then eases out to its slide place
                # (one smooth curve, so the switch into the slide has no jolt).
                xs = [0, 1, 2, 3, 12]
                ys = [-run.land + full * i for i in range(4)] + [self.l_slide.y]
                xx = [self.l_contact.x] * 4 + [self.l_slide.x]
                p = Vector((pchip(xs, xx, min(f, 12)), pchip(xs, ys, min(f, 12))))
                if f > 12:
                    p = self.l_slide.copy()
                pitch = -g["CONTACT_TOE_UP"] if f == 0 else -6.0 * self.slide(f)  # the lead foot braces on its heel
                return p, pitch
            return self.r_slide, 0.0

        def placed(self, s, f):
            """Slide foot on the ground, turned about the root. A foot the ankle cannot keep flat under a
            shin leaning over it rides up on its toes."""
            loc, pitch = self.foot_local(s, f)
            hip = self.turn(f).inverted() @ self.hip(s, f)
            for _ in range(3):
                th, kn = self.leg_angles(s, self.planted_x(s, loc.x, loc.y, pitch) - hip)
                over = -(th - kn) - ANKLE_UP
                if over <= pitch + 0.5:
                    break
                pitch = over
            return self.turn(f) @ self.planted_x(s, loc.x, loc.y, pitch), pitch

        def foot_on_ground(self, s, x, y, pitch, yaw):
            """Ankle of a foot at (x, y) turned by yaw, pitched about its toe (+) or heel (-)."""
            ft = self.foot[s]
            pivot = Vector((0, ft["toe"], -ft["h"])) if pitch >= 0 else Vector((0, ft["heel"], -ft["h"]))
            off = pivot + Matrix.Rotation(math.radians(pitch), 3, "X") @ (-pivot)
            flat = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Vector((0, off.y, 0))
            return Vector((x, y, 0)) + flat + Vector((0, 0, ft["h"] + off.z))

        def plant_state(self, s, sg, f):
            y = sg["y"] + self.travel_between(sg["f0"], f)
            pitch = 0.0
            if sg.get("contact") and f == sg["f0"]:
                pitch = -6.0
            if sg.get("toeoff"):
                pitch = {sg["f1"] - 1: 8.0, sg["f1"]: 15.0}.get(f, pitch)
            # A pivot plant turns on the spot from its landing turn to yaw_end (it follows the body turn).
            yaw = sg["yaw"] + (sg.get("yaw_end", sg["yaw"]) - sg["yaw"]) * sm(clamp01((f - sg["f0"]) / (sg["f1"] - sg["f0"])))
            return self.foot_on_ground(s, sg["x"], y, pitch, yaw), pitch, yaw

        def seg_at(self, s, f):
            for i, sg in enumerate(self.segs[s]):
                if sg["f0"] <= f <= sg["f1"]:
                    return i, sg
            raise ValueError((s, f))

        def end_state(self, s, i, at_start):
            """State of the plant (or slide) next to a swing: its end before the swing, its start after."""
            sg = self.segs[s][i]
            if sg["kind"] == "slide":
                pos, pitch = self.slide_end_pose[s]
                return pos, pitch, self.yaw(sg["f1"])
            return self.plant_state(s, sg, sg["f0"] if at_start else sg["f1"])

        def foot_state(self, s, f):
            i, sg = self.seg_at(s, f)
            if sg["kind"] == "slide":
                if s == "R" and f < self.PLANT_R:
                    return self.r_swing_in(f) + (self.yaw(f) * f / self.PLANT_R,)
                pos, pitch = self.placed(s, f)
                return pos, pitch, self.yaw(f)
            if sg["kind"] == "plant":
                return self.plant_state(s, sg, f)
            p0, q0, y0 = self.end_state(s, i - 1, False)
            p1, q1, y1 = self.end_state(s, i + 1, True)
            u = (f - sg["f0"]) / (sg["f1"] - sg["f0"])
            a = sm(u)
            pos = p0.lerp(p1, a)
            pos.z += sg["clear"] * k * math.sin(math.pi * u)
            pitch = q0 + (q1 - q0) * a
            hip = self.hip(s, f)
            rel = pos - hip
            near = self.dmin_knee(s)
            if rel.length < near:
                pos = hip + rel * (near / rel.length)
            return self.above_ground(s, pos, pitch, u, hip), pitch, y0 + (y1 - y0) * a

        def r_swing_in(self, f):
            """Right foot swings out wide from the run and plants for the slide (frames 0-8)."""
            p0, q0 = run.ankle("R", 0)
            if f == 0:
                return p0, q0
            p1, q1 = self.placed("R", self.PLANT_R)
            u = f / self.PLANT_R
            a = sm(u)
            pos = p0.lerp(p1, a)
            pos.z += 0.9 * k * math.sin(math.pi * u) * (1 - a)
            pitch = q0 + (q1 - q0) * a
            hip = self.hip("R", f)
            rel = pos - hip
            near = self.dmin_knee("R")
            if rel.length < near:
                pos = hip + rel * (near / rel.length)
            return self.above_ground("R", pos, pitch, u, hip), pitch

        def ankle(self, s, f):
            pos, pitch, _ = self.foot_state(s, f)
            return pos, pitch

        def foot_matrix(self, s, f, pos, pitch):
            rest = self.rest_ctrl[s]
            yaw = self.foot_state(s, f)[2]
            return (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                    @ Matrix.Rotation(math.radians(pitch), 4, "X") @ Matrix.Translation(-rest.translation) @ rest)

        # ---- upper body ----
        def torso_pose(self, f, yaw, w, rf):
            base = super().torso_pose(f, yaw, w, rf)
            back = -8.0 * self.slide(f)  # the chest leans back a little more against the slide
            return base[0] * w + back, base[1] * w, base[2] * w

        def head_rotation(self, f, yaw, roll):
            """The head keeps looking down the slide, then turns with the body as it turns back."""
            share = keys_at([(0, 1.0), (8, 0.75), (self.SLIDE_END, 0.75), (52, 1.0), (self.last, 1.0)], f)
            # It follows most of the lean back against the slide (kept level it tips into the left shoulder).
            lean = Matrix.Rotation(math.radians(-0.7 * (keys_at(self.LEAN_BACK, f) + 8.0 * self.slide(f))), 3, "X")
            return (lean @ Matrix.Rotation(math.radians(self.yaw(f) * share + g["HEAD_SHARE"] * yaw), 3, "Z")
                    @ Matrix.Rotation(math.radians(g["HEAD_SHARE"] * roll), 3, "Y"))

        def arm_pose(self, s, f, w, rf):
            run_s, run_e, _ = super().arm_pose(s, f, 1.0, rf)
            idle_s, idle_e = self.idle_arm(s)
            a = self.slide(f)
            if s == "L":   # leading arm out to the side for balance (further forward hits the turned head)
                slide_s, slide_e, slide_o = -10.0, 30.0, 15.0
            else:          # trailing arm back and low
                slide_s, slide_e, slide_o = -30.0, 30.0, 22.0
            free_s = idle_s + (run_s - idle_s) * w
            free_e = idle_e + (run_e - idle_e) * w
            # small steps: arms swing a little against the legs (right foot lands at 58)
            step = 8.0 * math.cos(2 * math.pi * (f - 58) / 20.0) * self.walk(f) * (1 if s == "L" else -1)
            return (free_s + (slide_s - free_s) * a + step, free_e + (slide_e - free_e) * a + 6.0 * self.walk(f),
                    slide_o * a)

        def extra_keys(self, f):
            for s in "LR":
                p = self.pb["knee_pole_" + s]
                p.matrix = self.turn(f) @ self.pole_rest[s]
                self.key("knee_pole_" + s, f)

    return Akira(run)


def check(tr, act, name):
    """Brief checks for a transition. Planted feet are placed so their ground point (flat sole, or the toe
    while the heel lifts) moves back exactly at the body speed (the skid excepted); here we check that the
    rig really follows: ankle on its target (IK), foot turned as its control (not stopped by the ankle limit),
    soles never below the ground, knees bent and inside the limit."""
    sc = bpy.context.scene
    pb = tr.pb
    tr.ad.action = act
    tr.ad.action_slot = act.slots[0]
    foot_err, lowest, bends, miss = 0.0, 9.0, [], 0.0
    for f in range(tr.first, tr.last + 1):
        sc.frame_set(f)
        for s in "LR":
            ank = pb["shin_" + s].tail
            hip, knee = pb["thigh_" + s].head, pb["shin_" + s].head
            a, b, d = (knee - hip).length, (ank - knee).length, (ank - hip).length
            bends.append(180 - math.degrees(math.acos(max(-1, min(1, (a * a + b * b - d * d) / (2 * a * b))))))
            miss = max(miss, (ank - pb["foot_ctrl_" + s].head).length)
            lowest = min(lowest, float(tr.world_verts({"L": "Leg_L_03", "R": "Leg_R_04"}[s])[:, 2].min()))
            planted = any(seg["kind"] == "plant" and seg["f0"] <= f <= seg["f1"] for seg in tr.plans[s])
            if planted:
                q = pb["foot_" + s].matrix.to_quaternion().rotation_difference(pb["foot_ctrl_" + s].matrix.to_quaternion())
                foot_err = max(foot_err, math.degrees(min(q.angle, 2 * math.pi - q.angle)))
    return {"frames": (tr.first, tr.last), "planted foot turn error max (deg)": round(foot_err, 2),
            "lowest sole (m)": round(lowest, 3), "knee bend range (deg)": (round(min(bends), 1), round(max(bends), 1)),
            "IK miss max (m)": round(miss, 3)}


def rest_knee_poles():
    """Keys the knee poles at rest in every rig action that does not key them, so an action that turns them
    (the Akira slide) cannot leave them turned for the others (in Blender a channel without keys keeps its
    last value)."""
    rig = bpy.data.objects["MechRig"]
    for act in bpy.data.actions:
        if not act.slots or act.slots[0].target_id_type != "OBJECT":
            continue
        paths = {fc.data_path for layer in act.layers for st in layer.strips for cb in st.channelbags for fc in cb.fcurves}
        if not any(p.startswith('pose.bones["') for p in paths) or 'pose.bones["knee_pole_L"].location' in paths:
            continue
        ad = rig.animation_data
        saved = (ad.action, ad.action_slot)
        ad.action = act
        ad.action_slot = act.slots[0]
        f0 = act.frame_range[0]
        for s in "LR":
            p = rig.pose.bones["knee_pole_" + s]
            p.location = (0, 0, 0)
            p.rotation_euler = (0, 0, 0)
            p.keyframe_insert("location", frame=f0, group=p.name)
            p.keyframe_insert("rotation_euler", frame=f0, group=p.name)
        ad.action = saved[0]
        if saved[0] is not None:
            ad.action_slot = saved[1]


def main():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    g = load_run()
    run = g["Run"]()
    run.solve_drop()
    Transition = make_transition_class(g)
    use_nla = run.ad.use_nla
    run.ad.use_nla = False
    out = {}
    for name, maker in (("biped_run_start", make_start), ("biped_run_stop", make_stop),
                        ("biped_run_stop_akira", make_akira)):
        tr = maker(g, run, Transition)
        act = tr.build_action(name)
        tr.ground_fix(act)
        out[name] = (tr, act, check(tr, act, name))
    run.ad.action = None
    rest_knee_poles()
    run.ad.use_nla = use_nla
    for name, (tr, act, res) in out.items():
        print(name, res, "markers", [(m.name, m.frame) for m in act.pose_markers])
    return out


if __name__ == "__main__":
    main()
