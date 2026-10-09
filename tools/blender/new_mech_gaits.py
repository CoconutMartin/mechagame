"""Builds the body gait actions of the new mech (models/new_mech/*.blend): Walk and Slow_Run.
The full-speed run is built by new_mech_run.py (biped_run_* actions).

Run inside Blender with the mech file open (Text Editor: Run Script). Each action keys the pelvis,
torso, upper arms, forearms, fingers and the IK foot controls; the head is left free for Head_Scan,
which plays on its own NLA layer. Actions loop (Cycles modifiers) and are kept with a fake user, so
the glTF exporter writes them as separate Godot animations.

The swing-foot lift is searched so the leg IK always reaches its target inside the joint limits
(the knee limit comes from shin/thigh contact), then foot dips below the ground are lifted out.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

RIG = "MechRig"
FEET = {"L": "Leg_L_03", "R": "Leg_R_04"}
FPS = 30
GRIP = {"index": (55, 65, 45), "middle": (55, 65, 45), "ring": (58, 65, 45), "pinky": (60, 65, 45), "thumb": (30, 35, 25)}

# cycle: frames per stride (two steps). duty: part of the cycle a foot is on the ground.
# stride: stride length in leg lengths. touch: part of the stance the foot lands ahead of the hip.
# bob: hip bob (m); + = high at mid-stance (walk), - = low at mid-stance (runs).
# lift: largest swing-foot lift tried (m). peak: part of the swing where the foot is highest (0.5 = mid-swing;
# later = the foot rises as the knee drives forward, where the knee limit leaves more room).
# reach: how fast the swing foot comes forward (1 = even ease in and out; above 1 = forward early, so it
# passes under the hip low and rises in front). early: extra lift right after push-off (m), so both feet
# clear the ground during the airborne part.
# The swing foot is also kept between the shortest leg the knee limit allows (shin hits thigh) and 96% of
# the full leg from the hip: a foot too close to the hip is pushed straight away from it (smoothly, so the
# knee never flips; the foot passes lower under the hip).
# swing_keys: leg shapes the swing foot passes through, as (t in the swing, thigh angle from vertical,
# knee bend, foot pitch), degrees; thigh + = forward, foot pitch + = heel up. The swing then ignores lift,
# peak, reach and early; the hips are raised in frames where a foot would go below the ground.
# width: foot distance from the centre line, as a part of the rest stance (user: 30% closer, 2026-10-09).
# fist / fist_sw: finger curl (part of the grip) and its swing. arm_out: arms held out to the side (degrees),
# so the hands clear high knees.
GAITS = {
    "Walk": dict(cycle=60, width=0.7, duty=0.60, stride=1.1, touch=0.50, drop_extra=0.05, bob=0.10, sway=0.15, lean=5, yaw=4,
                 heel=10, toe=15, lift=0.30, arm_bias=0, arm=15, elbow=18, elbow_sw=8, fist=0.2, fist_sw=0.3),
    "Slow_Run": dict(cycle=45, width=0.7, duty=0.42, stride=1.4, touch=0.38, drop_extra=0.05, bob=-0.10, sway=0.03, lean=6, yaw=3,
                     roll=1.0,
                     heel=8, toe=20, lift=0.70, arm_bias=6, arm=22, arm_out=12, elbow=32, elbow_sw=8, fist=0.45, fist_sw=0.1),
}


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
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u * u + 1, u ** 3 - 2 * u * u + u, -2 * u ** 3 + 3 * u * u, u ** 3 - u * u
    return h00 * ys[i] + h10 * h[i] * d[i] + h01 * ys[i + 1] + h11 * h[i] * d[i + 1]


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


class Builder:
    def __init__(self):
        self.rig = bpy.data.objects[RIG]
        self.pb = self.rig.pose.bones
        self.bones = self.rig.data.bones
        self.ad = self.rig.animation_data or self.rig.animation_data_create()
        b = self.bones
        self.leg = min(b["thigh_" + s].length + b["shin_" + s].length for s in "LR")
        self.hip = b["thigh_L"].head_local.z
        self.ankle = max(b["foot_" + s].head_local.z for s in "LR")
        self.rest_ctrl = {s: b["foot_ctrl_" + s].matrix_local.copy() for s in "LR"}
        # Shortest hip-ankle distance the knee limit allows.
        self.dmin = {}
        for s in "LR":
            c = self.pb["shin_" + s].constraints.get("Joint limit")
            bend = max(abs(c.min_x), abs(c.max_x)) if c else math.radians(140)
            t, sh = b["thigh_" + s].length, b["shin_" + s].length
            self.dmin[s] = math.sqrt(t * t + sh * sh + 2 * t * sh * math.cos(bend))
        self.feet = {}
        for s, name in FEET.items():
            w = self.world_verts(name, evaluated=False)
            a = b["foot_" + s].head_local
            self.feet[s] = dict(toe=float(w[:, 1].min() - a.y), heel=float(w[:, 1].max() - a.y), h=float(a.z - w[:, 2].min()))

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

    def limit_sign(self, bone):
        """+1 when the larger X range of the bone's joint limit is positive (forward / bend direction)."""
        c = self.pb[bone].constraints.get("Joint limit")
        return 1 if c is None or c.max_x >= -c.min_x else -1

    def out_sign(self, bone):
        """Sign of a local Z turn that moves the bone's tail away from the body."""
        x = self.bones[bone].matrix_local.to_3x3().col[0]
        side = 1 if self.bones[bone].head_local.x > 0 else -1
        return 1 if (-x).x * side > 0 else -1

    def curl_sign(self, bone):
        c = self.pb[bone].constraints.get("Joint limit")
        return 1 if c is None or c.max_x > 0 else -1

    def planted(self, s, fwd, pitch, width=1.0):
        a = self.bones["foot_" + s].head_local
        f = self.feet[s]
        pivot = Vector((0, f["toe"], -f["h"])) if pitch >= 0 else Vector((0, f["heel"], -f["h"]))
        p = pivot + Matrix.Rotation(math.radians(pitch), 3, "X") @ (-pivot)
        return Vector((a.x * width, a.y - fwd + p.y, a.z + p.z))

    def channelbag_curves(self, act):
        return [fc for layer in act.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]

    def key(self, bone, f, loc=True):
        p = self.pb[bone]
        if loc:
            p.keyframe_insert("location", frame=f, group=bone)
        p.keyframe_insert("rotation_euler", frame=f, group=bone)

    def build(self, name, g, lift):
        cy, duty = g["cycle"], g["duty"]
        stride = g["stride"] * self.leg
        stance = stride * duty
        touch = g["touch"] * stance
        drop = max(0.0, (self.hip - self.ankle) - math.sqrt((0.96 * self.leg) ** 2 - touch ** 2)) + g["drop_extra"]
        shape = math.log(0.5) / math.log(g.get("peak", 0.5))  # sin(pi * t^shape) is highest at t = peak

        def hip_z(s, gph):
            return self.bones["thigh_" + s].head_local.z - drop + g["bob"] * math.cos(2 * math.pi * 2 * (gph - duty / 2))

        def leg_offset(s, thigh, knee):
            """Ankle offset from the hip (forward, down) for a thigh angle and knee bend, degrees."""
            a, b = self.bones["thigh_" + s].length, self.bones["shin_" + s].length
            t1, t2 = math.radians(thigh), math.radians(thigh - knee)
            return a * math.sin(t1) + b * math.sin(t2), a * math.cos(t1) + b * math.cos(t2)

        def side_of(s):
            return self.bones["foot_" + s].head_local.x - self.bones["thigh_" + s].head_local.x

        def leg_angles(s, fw, dn):
            """Thigh angle and knee bend (degrees) that put the ankle at (forward, down) from the hip; the
            ankle also sits side_of(s) out to the side (the legs stand slanted), which counts in the reach."""
            a, b = self.bones["thigh_" + s].length, self.bones["shin_" + s].length
            d = min(max(math.sqrt(fw * fw + dn * dn + side_of(s) ** 2), self.dmin[s] + 0.01), a + b - 0.001)
            knee = math.pi - math.acos(max(-1.0, min(1.0, (a * a + b * b - d * d) / (2 * a * b))))
            alpha = math.acos(max(-1.0, min(1.0, (a * a + d * d - b * b) / (2 * a * d))))
            return math.degrees(math.atan2(fw, dn) + alpha), math.degrees(knee)

        def side_view(s, fw, dn):
            """Shrinks a side-view leg offset so the real (slanted) reach keeps the same knee bend."""
            want = math.hypot(fw, dn)
            flat = math.sqrt(max(want * want - side_of(s) ** 2, 0.01))
            return fw * flat / want, dn * flat / want

        def keyed_swing(s, t, gph, swing_len):
            """Swing through the key leg shapes, blended by joint angle so the knee stays in its range."""
            hip = self.bones["thigh_" + s].head_local
            p0 = self.planted(s, touch - stance, g["toe"], g.get("width", 1.0))
            p1 = self.planted(s, touch, -g["heel"], g.get("width", 1.0))
            start, end = gph - t * swing_len, gph + (1 - t) * swing_len
            pts = [(0.0, *leg_angles(s, hip.y - p0.y, hip_z(s, start) - p0.z), g["toe"])]
            pts += [tuple(k) for k in g["swing_keys"]]
            pts.append((1.0, *leg_angles(s, hip.y - p1.y, hip_z(s, end) - p1.z), -g["heel"]))
            c = self.pb["shin_" + s].constraints.get("Joint limit")
            knee_max = math.degrees(max(abs(c.min_x), abs(c.max_x))) - 3 if c else 135
            ts = [p[0] for p in pts]
            thigh, knee, pitch = (pchip(ts, [p[j] for p in pts], t) for j in (1, 2, 3))
            knee = min(max(knee, 2.0), knee_max)
            fw, dn = side_view(s, *leg_offset(s, thigh, knee))
            return Vector((p0.x, hip.y - fw, hip_z(s, gph) - dn)), pitch

        def foot(s, ph):
            ph %= 1.0
            if ph < duty:
                t = ph / duty
                if t < 0.15:
                    pitch = -g["heel"] * (1 - smooth(t / 0.15))
                elif t > 0.6:
                    pitch = g["toe"] * smooth((t - 0.6) / 0.4)
                else:
                    pitch = 0.0
                return self.planted(s, touch - stance * t, pitch, g.get("width", 1.0)), pitch
            t = (ph - duty) / (1 - duty)
            if "swing_keys" in g:
                return keyed_swing(s, t, (ph - (0.0 if s == "L" else 0.5)) % 1.0, 1 - duty)
            p0 = self.planted(s, touch - stance, g["toe"], g.get("width", 1.0))
            p1 = self.planted(s, touch, -g["heel"], g.get("width", 1.0))
            r = g.get("reach", 1.0)
            h = smooth((t - 0.05) / 0.9) if r == 1.0 else 1 - (1 - min(max((t - 0.03) / 0.85, 0.0), 1.0)) ** r
            y = p0.y + (p1.y - p0.y) * h
            z = (p0.z + (p1.z - p0.z) * t + lift * math.sin(math.pi * t ** shape)
                 + g.get("early", 0.0) * math.sin(math.pi * min(t / 0.6, 1.0)))
            hip = self.bones["thigh_" + s].head_local
            hz = hip.z - drop + g["bob"] * math.cos(2 * math.pi * 2 * ((ph - (0.0 if s == "L" else 0.5)) % 1.0 - duty / 2))
            down = hz - z
            fwd = hip.y - y  # forward is -Y
            near = self.dmin[s] + 0.05
            dist = math.hypot(fwd, down)
            if dist < near:
                # Too close to the hip for the knee limit: push the foot straight away from the hip until
                # it is far enough. This changes smoothly through the swing (the foot passes lower under
                # the hip), so the knee never flips.
                fwd, down = fwd * near / dist, down * near / dist
                y, z = hip.y - fwd, hz - down
            dmax = 0.96 * self.leg
            if fwd * fwd + down * down > dmax * dmax:
                y = hip.y - math.copysign(math.sqrt(max(dmax * dmax - down * down, 0.0)), fwd)
            return Vector((p0.x, y, z)), g["toe"] + (-g["heel"] - g["toe"]) * smooth(t)

        old = bpy.data.actions.get(name)
        if old:
            bpy.data.actions.remove(old)
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.ad.action = act
        self.ad.action_slot = act.slots.new("OBJECT", self.rig.name)
        pel_rest = self.bones["pelvis"].matrix_local
        for f in range(1, cy + 2):
            ph = (f - 1) / cy
            bob = g["bob"] * math.cos(2 * math.pi * 2 * (ph - duty / 2))
            sway = g["sway"] * math.cos(2 * math.pi * (ph - duty / 2))
            side = math.sin(2 * math.pi * (ph + 0.25))
            pel = self.pb["pelvis"]
            pel.matrix = Matrix.Translation(Vector((sway, 0, -drop + bob))) @ pel_rest
            pel.rotation_euler = (math.radians(g["lean"] * 0.4), math.radians(g["yaw"]) * side,
                                  math.radians(g.get("roll", 2.0)) * math.cos(2 * math.pi * (ph - duty / 2)))
            self.pb["torso"].rotation_euler = (math.radians(g["lean"] * 0.6),
                                               -math.radians(g["yaw"] * g.get("twist", 1.8)) * side, 0)
            self.key("pelvis", f)
            self.key("torso", f, loc=False)
            for s, off in (("L", 0.0), ("R", 0.5)):
                pos, pitch = foot(s, ph + off)
                rest = self.rest_ctrl[s]
                self.pb["foot_ctrl_" + s].matrix = (Matrix.Translation(pos) @ Matrix.Rotation(math.radians(pitch), 4, "X")
                                                    @ Matrix.Translation(-rest.translation) @ rest)
                self.key("foot_ctrl_" + s, f)
                sw = math.cos(2 * math.pi * (ph + off))  # +1: this leg forward -> its arm back
                ua, fa = "upper_arm_" + s, "forearm_" + s
                out = math.radians(g.get("arm_out", 0.0)) * self.out_sign(ua)
                self.pb[ua].rotation_euler = (math.radians(self.limit_sign(ua) * (g["arm_bias"] - g["arm"] * sw)), 0, out)
                self.pb[fa].rotation_euler = (math.radians(self.limit_sign(fa) * (g["elbow"] - g["elbow_sw"] * sw)), 0, 0)
                self.key(ua, f, loc=False)
                self.key(fa, f, loc=False)
                k = g["fist"] + g["fist_sw"] * (0.5 - 0.5 * sw)  # closes as the arm swings forward
                for fn, vals in GRIP.items():
                    for i in range(3):
                        n = f"{fn}_{i + 1:02d}_{s}"
                        self.pb[n].rotation_euler = (math.radians(self.curl_sign(n) * vals[i] * k), 0, 0)
                        self.key(n, f, loc=False)
        for fc in self.channelbag_curves(act):
            fc.modifiers.new("CYCLES")
        return act, drop, stride

    def ik_miss(self, cy):
        sc = bpy.context.scene
        worst = 0.0
        for f in range(1, cy + 1):
            sc.frame_set(f)
            for s in "LR":
                worst = max(worst, (self.pb["shin_" + s].tail - self.pb["foot_ctrl_" + s].head).length)
        return worst

    def lift_body(self, act, cy, ground):
        """Raises the pelvis where a foot mesh would go below its rest height during the airborne part
        (the swing foot moves with the hips, so this lifts the whole mech). The raise is spread over the
        neighbouring frames so the body rises and settles smoothly."""
        sc = bpy.context.scene
        curves = self.channelbag_curves(act)
        curve = next(fc for fc in curves if fc.data_path == 'pose.bones["pelvis"].location' and fc.array_index == 1)
        feet = {s: next(fc for fc in curves if fc.data_path == f'pose.bones["foot_ctrl_{s}"].location'
                        and fc.array_index == 2) for s in "LR"}
        duty = GAITS[act.name]["duty"]
        worst = 0.0
        for _ in range(4):
            need = np.zeros(cy)
            for f in range(1, cy + 1):
                ph = (f - 1) / cy
                if not all((ph + off) % 1.0 >= duty for off in (0.0, 0.5)):
                    continue
                sc.frame_set(f)
                need[f - 1] = max(0.0, max(ground[s] - self.world_verts(FEET[s])[:, 2].min() for s in "LR"))
            worst = float(need.max())
            if worst < 0.01:
                break
            spread = np.array([max(need[(i + k) % cy] * (1 - abs(k) / 4) for k in range(-3, 4)) for i in range(cy)])
            # Hips and every swinging foot move up together, so the leg shapes stay the same.
            moved = [(curve, None)] + [(feet[s], off) for s, off in (("L", 0.0), ("R", 0.5))]
            for fc, off in moved:
                for kp in fc.keyframe_points:
                    i = int(round(kp.co.x)) - 1
                    if off is not None and ((i / cy) + off) % 1.0 < duty:
                        continue  # a planted foot stays on the ground
                    d = spread[i % cy]
                    kp.co.y += d
                    kp.handle_left.y += d
                    kp.handle_right.y += d
                fc.update()
        return worst

    def ground_feet(self, act, cy, ground):
        """Lifts the foot control where the foot mesh dips below its rest height."""
        sc = bpy.context.scene
        curves = {s: next(fc for fc in self.channelbag_curves(act)
                          if fc.data_path == f'pose.bones["foot_ctrl_{s}"].location' and fc.array_index == 2) for s in "LR"}
        worst = 0.0
        for _ in range(4):
            worst = 0.0
            for f in range(1, cy + 2):
                sc.frame_set(f)
                for s in "LR":
                    dip = ground[s] - self.world_verts(FEET[s])[:, 2].min()
                    if dip > 0.005:
                        for kp in curves[s].keyframe_points:
                            if abs(kp.co.x - f) < 0.01:
                                kp.co.y += dip
                                kp.handle_left.y += dip
                                kp.handle_right.y += dip
                        worst = max(worst, dip)
            for fc in curves.values():
                fc.update()
            if worst < 0.01:
                break
        return worst

    def make(self, name):
        """Highest swing lift (scanned from the top in 5 cm steps) whose leg IK reaches every foot target."""
        g = GAITS[name]
        if "swing_keys" in g:
            act, drop, stride = self.build(name, g, g["lift"])
            return act, g["lift"], drop, stride
        best = 0.05
        lift = g["lift"]
        while lift >= 0.05:
            self.build(name, g, lift)
            if self.ik_miss(g["cycle"]) < 0.03:
                best = lift
                break
            lift = round(lift - 0.05, 3)
        act, drop, stride = self.build(name, g, best)
        return act, best, drop, stride


def main(names=("Walk", "Slow_Run")):
    """Rebuilds the named gaits and relinks them to their NLA tracks."""
    b = Builder()
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    use_nla = b.ad.use_nla
    b.ad.use_nla = False
    b.ad.action = None
    for p in b.pb:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    ground = {s: b.world_verts(FEET[s])[:, 2].min() for s in "LR"}
    for name in names:
        act, lift, drop, stride = b.make(name)
        if "swing_keys" in GAITS[name]:
            dip = b.lift_body(act, GAITS[name]["cycle"], ground)
        else:
            dip = b.ground_feet(act, GAITS[name]["cycle"], ground)
        cy = GAITS[name]["cycle"]
        print(f"{name}: lift {lift:.2f} m, hip drop {drop:.2f} m, stride {stride:.2f} m, "
              f"speed {stride / (cy / FPS):.2f} m/s, IK miss {b.ik_miss(cy):.3f}, last ground fix {dip:.3f}")
        track = b.ad.nla_tracks.get(name)
        if track is not None:
            for strip in list(track.strips):
                track.strips.remove(strip)
            strip = track.strips.new(name, 1, act)
            strip.action_slot = act.slots[0]
    b.ad.action = None
    b.ad.use_nla = use_nla


if __name__ == "__main__":
    main()
