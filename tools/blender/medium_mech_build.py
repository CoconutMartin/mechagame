"""Builds the Medium mech game parts in models/medium_mech/medium_mech.blend and exports them.

Run (from the project root):
    blender -b --python tools/blender/mech_kit.py -- medium_mech data/frames/medium_mech_frame.tres
    blender -b models/medium_mech/medium_mech.blend --python tools/blender/medium_mech_build.py
(the first line makes a new kit file; only needed when the frame changes). The build removes the old
model pieces (not the socket and pivot empties) and builds them again from the source files, so hand
edits in the part collections are lost: edit models/medium/medium.blend and build again.

Source: the rigged Medium mech (models/medium/medium.blend, collection Mech_Medium, rig
mech_medium_rig, in its rest pose). The game rest pose has straight limbs (each joint right below the
one above it), so each limb piece is turned about its upper joint until the joint below hangs straight
down: thigh about the hip, shin about the knee, upper arm about the shoulder, forearm about the elbow.
The foot only moves with the ankle (it stays flat). Then the model is lifted so the soles are at Z = 0.
The joint layout this gives must match data/frames/medium_mech_frame.tres (the script checks it).
Booster: the Recon Sheet backpack (models/recon_sheet/recon_sheet.blend, part_booster), moved onto
Medium's back. Materials: Medium keeps its own textured materials; the booster uses the Recon Sheet
names (armor, frame, joint, bolt) for the game library.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Matrix, Vector
import frame_io

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SOURCE = os.path.join(ROOT, "models", "medium", "medium.blend")
BOOSTER_SOURCE = os.path.join(ROOT, "models", "recon_sheet", "recon_sheet.blend")
FRAME = "data/frames/medium_mech_frame.tres"
RIG = "mech_medium_rig"
## Moves the model along Blender Y (depth) so the hips and shoulders sit near the frame line (Y = 0).
Y_SHIFT = -0.06
## The game arm IK (TwoBoneIK) builds the shoulder and elbow turn from the bend direction, which turns
## both arm bones about 155 to 180 degrees about their own length in the usual poses (measured). The arm
## pieces are turned this much about their joint's vertical axis first, so they look like the source
## in the game (without it the left forearm and hand look like the right ones and the other way round).
ARM_IK_TWIST_DEG = 180.0
## Booster: overlap with the torso back (m) and the backpack center height in the torso (0 = bottom).
BOOSTER_OVERLAP = 0.15
BOOSTER_HEIGHT = 0.35
PREFIX = "md_"

# Pieces per part and socket ("L" side; the "R" side is the same with _R). Medium's left side is
# Blender +X, the same as the kit's ShoulderL / HipL.
SIDE_PARTS = {
    "arm": {"Torso": ["shoulder_axle"], "Shoulder": ["upper_arm"],
            "Elbow": ["elbow_cyl", "forearm", "wrist_joint", "hand"]},
    "leg": {"Hip": ["thigh"], "Knee": ["knee_cyl", "shin", "ankle_bracket"], "FootPivot": ["foot"]},
}
CENTER_PARTS = {
    "head": {"Torso": ["head", "neck"]},
    "core": {"Torso": ["torso", "waist", "neck_collar", "shoulder_mount_L", "shoulder_mount_R"]},
    "legs": {"Lower": ["pelvis_core", "pelvis_crotch", "pelvis_belt", "pelvis_back", "hip_axle_L", "hip_axle_R",
                       "waist_ring"]},
}


def socket_name(socket, part):
    """Kit socket empty for a part (pivots keep their own name)."""
    return socket if socket.startswith("FootPivot") else f"{socket}_{part}"


def clear_pieces():
    for col in bpy.data.collections:
        if not col.name.startswith("part_"):
            continue
        for obj in list(col.all_objects):
            if obj.type == "MESH" or (obj.type == "EMPTY" and obj.name.startswith("BoosterFlame")):
                bpy.data.objects.remove(obj)


def rig_space(obj):
    """Matrix of a child of the rig in rig space (the rig may be moved in the scene)."""
    return obj.matrix_parent_inverse @ obj.matrix_basis


def turn_about(pivot, frm, to):
    """Turns the direction frm onto the direction to, about the point pivot."""
    rot = frm.normalized().rotation_difference(to.normalized()).to_matrix().to_4x4()
    return Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot)


def turn_about_z(pivot, degrees):
    """Turn about the vertical line through pivot."""
    return Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(degrees), 4, "Z") @ Matrix.Translation(-pivot)


def load_source():
    names = [RIG]
    for side in "LR":
        for sockets in SIDE_PARTS.values():
            for pieces in sockets.values():
                names += [f"{p}_{side}" for p in pieces]
    for sockets in CENTER_PARTS.values():
        for pieces in sockets.values():
            names += pieces
    with bpy.data.libraries.load(SOURCE, link=False) as (src, dst):
        missing = [n for n in names if n not in src.objects]
        if missing:
            raise RuntimeError(f"missing in {SOURCE}: {missing}")
        dst.objects = names
    return {o.name: o for o in dst.objects}


def chain_transforms(rig, objs):
    """Straightening matrices per piece name (rig space), and the frame values they give."""
    bones = rig.data.bones
    moves, values = {}, {}
    down = Vector((0.0, 0.0, -1.0))
    for side in "LR":
        hip, knee = bones[f"thigh.{side}"].head_local, bones[f"thigh.{side}"].tail_local
        ankle = bones[f"shin.{side}"].tail_local
        t1 = turn_about(hip, knee - hip, down)
        knee2 = t1 @ knee
        t2 = turn_about(knee2, (t1 @ ankle) - knee2, down)
        ankle2 = t2 @ (t1 @ ankle)
        moves[f"thigh_{side}"] = t1
        for p in SIDE_PARTS["leg"]["Knee"]:
            moves[f"{p}_{side}"] = t2 @ t1
        moves[f"foot_{side}"] = Matrix.Translation(ankle2 - ankle)
        shoulder, elbow = bones[f"upper_arm.{side}"].head_local, bones[f"upper_arm.{side}"].tail_local
        hand = objs[f"hand_{side}"]
        hand_points = [rig_space(hand) @ v.co for v in hand.data.vertices]
        grip = sum(hand_points, Vector()) / len(hand_points)
        t3 = turn_about(shoulder, elbow - shoulder, down)
        elbow2 = t3 @ elbow
        t4 = turn_about(elbow2, (t3 @ grip) - elbow2, down)
        moves[f"upper_arm_{side}"] = t3
        for p in SIDE_PARTS["arm"]["Elbow"]:
            moves[f"{p}_{side}"] = t4 @ t3
        if side == "L":
            values.update(hip=hip, thigh=(knee - hip).length, shin=(ankle - knee).length, ankle_drop=ankle2.z - ankle.z,
                          shoulder=shoulder, upper=(elbow - shoulder).length, fore=(grip - elbow).length)
    values["waist"] = bones["torso"].head_local.z
    return moves, values


def lowest_sole(objs, moves):
    low = math.inf
    for side in "LR":
        foot = objs[f"foot_{side}"]
        m = moves[f"foot_{side}"] @ rig_space(foot)
        low = min(low, min((m @ v.co).z for v in foot.data.vertices))
    return low


def check_frame(values, lift):
    frame = frame_io.read(FRAME)
    got = {"hip_height": values["hip"].z + lift, "hip_width": values["hip"].x, "thigh_length": values["thigh"],
           "shin_length": values["shin"], "torso_above_hip": values["waist"] - values["hip"].z,
           "shoulder_width": values["shoulder"].x, "shoulder_height": values["shoulder"].z - values["waist"],
           "upper_arm_length": values["upper"], "forearm_length": values["fore"]}
    bad = {k: (round(v, 3), frame[k]) for k, v in got.items() if abs(v - frame[k]) > 0.01}
    if bad:
        raise RuntimeError(f"{FRAME} does not match the model (model, file): {bad}")
    print("frame matches:", {k: round(v, 3) for k, v in got.items()})


def place(obj, world, socket, name):
    """Turns the source piece into a rigid game piece under a kit socket."""
    bpy.data.collections[f"part_{socket_part[socket]}"].objects.link(obj)
    obj.parent = None
    obj.modifiers.clear()
    obj.vertex_groups.clear()
    obj.matrix_world = world
    sock = bpy.data.objects[socket]
    obj.parent = sock
    obj.matrix_parent_inverse = sock.matrix_world.inverted()
    obj.name = name
    obj.data.name = name


def add_booster(objs, base):
    """Recon Sheet backpack on Medium's back: pieces keep their place relative to the Torso socket,
    then move back onto the torso back and up to BOOSTER_HEIGHT of the torso."""
    with bpy.data.libraries.load(BOOSTER_SOURCE, link=False) as (src, dst):
        dst.collections = ["part_booster"]
    col = dst.collections[0]
    # The kit already has a Torso_booster, so the loaded one is "Torso_booster.001".
    src_sock = next(o for o in col.objects if o.name.split(".")[0] == "Torso_booster")
    src_world = src_sock.matrix_basis
    kit_sock = bpy.data.objects["Torso_booster"]
    pieces = [o for o in col.objects if o.parent == src_sock]
    rel = {o: src_world.inverted() @ (src_world @ o.matrix_parent_inverse @ o.matrix_basis) for o in pieces}
    placed = {o: kit_sock.matrix_world @ r for o, r in rel.items()}
    # Torso back (Blender +Y) and height, from the placed torso.
    torso = objs["torso"]
    tm = base["torso"]
    tz = [(tm @ v.co).z for v in torso.data.vertices]
    z0, z1 = min(tz), max(tz)
    mid = [(tm @ v.co) for v in torso.data.vertices if z0 + 0.25 * (z1 - z0) < (tm @ v.co).z < z0 + 0.6 * (z1 - z0)]
    back = max(p.y for p in mid)
    front = min(min((placed[o] @ v.co).y for v in o.data.vertices) for o in pieces if o.type == "MESH")
    pack = next(o for o in pieces if o.name.startswith("PackCenter"))
    pack_z = placed[pack].translation.z
    offset = Matrix.Translation((0.0, back - front - BOOSTER_OVERLAP, z0 + BOOSTER_HEIGHT * (z1 - z0) - pack_z))
    kit_mats = {m.name: m for m in bpy.data.materials if "." not in m.name}
    for o in pieces:
        bpy.data.collections["part_booster"].objects.link(o)
        world = offset @ placed[o]
        o.parent = kit_sock
        o.matrix_parent_inverse = kit_sock.matrix_world.inverted()
        o.matrix_world = world
        base_name = o.name.split(".")[0]
        o.name = base_name if base_name.startswith("BoosterFlame") else "bst_" + base_name
        if o.type == "MESH":
            o.data.name = o.name
            for slot in o.material_slots:
                if slot.material and slot.material.name.split(".")[0] in kit_mats:
                    slot.material = kit_mats[slot.material.name.split(".")[0]]
    # The loaded collection would export as a second booster part: remove it and its socket.
    bpy.data.objects.remove(src_sock)
    bpy.data.collections.remove(col)
    print("booster moved", tuple(round(x, 2) for x in offset.translation), "torso back", round(back, 2))


socket_part = {}


def build():
    clear_pieces()
    for col in bpy.data.collections:
        if col.name.startswith("part_"):
            for obj in col.objects:
                if obj.type == "EMPTY":
                    socket_part[obj.name] = col.name[len("part_"):]
    bpy.context.view_layer.update()
    objs = load_source()
    rig = objs[RIG]
    moves, values = chain_transforms(rig, objs)
    lift = -lowest_sole(objs, moves)
    check_frame(values, lift)
    shift = Matrix.Translation((0.0, Y_SHIFT, lift))
    base = {}
    for name, obj in objs.items():
        if name == RIG:
            continue
        base[name] = shift @ moves.get(name, Matrix.Identity(4)) @ rig_space(obj)
    jobs = []
    for part, sockets in CENTER_PARTS.items():
        for socket, pieces in sockets.items():
            jobs += [(p, socket_name(socket, part), PREFIX + p) for p in pieces]
    for side in "LR":
        arm = f"arm_{side.lower()}"
        for socket, pieces in SIDE_PARTS["arm"].items():
            sock = "Torso" if socket == "Torso" else f"{socket}{side}"
            jobs += [(f"{p}_{side}", socket_name(sock, arm), PREFIX + f"{p}_{side}") for p in pieces]
        for socket, pieces in SIDE_PARTS["leg"].items():
            for p in pieces:
                name = f"Foot{side}" if p == "foot" else PREFIX + f"{p}_{side}"
                jobs.append((f"{p}_{side}", socket_name(f"{socket}{side}", "legs"), name))
    for src, sock, name in jobs:
        world = base[src]
        if sock.startswith(("Shoulder", "Elbow")):
            pivot = bpy.data.objects[sock].matrix_world.translation
            world = turn_about_z(pivot, ARM_IK_TWIST_DEG) @ world
        place(objs[src], world, sock, name)
    add_booster(objs, base)
    bpy.data.objects.remove(rig)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)  # the source walk is not used by the game
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images, bpy.data.actions):
        for item in list(block):
            if item.users == 0 and not getattr(item, "use_fake_user", False):
                block.remove(item)
    bpy.context.view_layer.update()
    feet = [o for o in bpy.data.objects if o.name in ("FootL", "FootR")]
    print("lowest sole", round(min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in feet), 4))
    bpy.ops.wm.save_mainfile()
    exec(open(os.path.join(ROOT, "tools", "blender", "export_parts.py")).read(), {"__name__": "__main__"})


if __name__ == "__main__":
    build()
