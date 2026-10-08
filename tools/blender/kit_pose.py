"""Poses a mech kit .blend like the game pose (rifle and shield held), for hand adjustments, and puts it
back to rest for export.

1. Capture the pose in the game (from the project root):
     godot --headless --path . --script res://tools/godot/capture_pose.gd -- <loadout.tres> models/<mech>/pose
2. In Blender, with models/<mech>/<mech>.blend open, run this file with MODE = "pose" (Text Editor
   block "kit_pose.py": set MODE at the top, then Run Script; or headless with -- pose).
   The socket empties turn into the game pose, so the part pieces under them follow, and the held
   weapons come in as a reference (collection "pose_ref", not exported).
3. Move or turn the part pieces (not the socket empties) until they look right in the pose. A piece
   keeps its place on its socket, so the change also holds at rest and in the game.
4. Run with MODE = "rest": the sockets go back to rest exactly, the reference is removed, the .blend
   is saved and the parts are exported (export_parts.py).
Game space: x right, y up, -z forward. Blender kit space: the mech faces -Y, game point (x, y, z) is
Blender (-x, z, y) (mech_kit.py to_blender). Socket empties are turned 180 degrees about Z at rest.
"""
import json, math, os, sys
import bpy
from mathutils import Matrix, Vector

MODE = "pose"
REF = "pose_ref"
# Game -> Blender world (its own inverse).
C = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def pose_folder():
    return os.path.join(os.path.dirname(bpy.data.filepath), "pose")


def game_matrix(v):
    """12 numbers (basis columns x, y, z, origin) to a 4x4 matrix."""
    return Matrix(((v[0], v[3], v[6], v[9]), (v[1], v[4], v[7], v[10]), (v[2], v[5], v[8], v[11]), (0, 0, 0, 1)))


def joint_of(obj):
    """Frame joint an empty follows: "ShoulderL_arm_l" -> ShoulderL; pivots keep their name."""
    return obj.name.split("_")[0].split(".")[0]


def sockets():
    """Socket and pivot empties of the part collections, parents before children."""
    found = []
    for col in bpy.data.collections:
        if col.name.startswith("part_"):
            found += [o for o in col.objects if o.type == "EMPTY"]
    return sorted(found, key=lambda o: 0 if o.parent is None else 1)


def pose():
    if any("kit_rest" in o for o in sockets()):
        rest(export=False)
    data = json.load(open(os.path.join(pose_folder(), "pose.json")))
    joints = data["joints"]
    bpy.context.view_layer.update()
    rests = {o.name: o.matrix_world.copy() for o in sockets()}
    moved = 0
    for obj in sockets():
        joint = joints.get(joint_of(obj))
        if joint is None:
            # Not a frame joint (booster flames, pauldron pivots): it follows its parent socket, and
            # rest() must not undo hand moves made to it while posed.
            continue
        obj["kit_rest"] = [x for row in rests[obj.name] for x in row]
        delta = game_matrix(joint["pose"]) @ game_matrix(joint["rest"]).inverted()
        obj.matrix_world = C @ delta @ C @ rests[obj.name]
        bpy.context.view_layer.update()
        moved += 1
    add_reference(os.path.join(pose_folder(), "weapons.glb"))
    print("posed", moved, "sockets from", data.get("loadout"))


def add_reference(path):
    remove_reference()
    col = bpy.data.collections.new(REF)
    bpy.context.scene.collection.children.link(col)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for obj in new:
        for c in obj.users_collection:
            c.objects.unlink(obj)
        col.objects.link(obj)
        if obj.parent is None:
            # glTF import gives Blender (x, -z, y); the kit uses (-x, z, y): a half turn about Z.
            obj.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ obj.matrix_world
    col.hide_render = True


def remove_reference():
    col = bpy.data.collections.get(REF)
    if col is None:
        return
    for obj in list(col.all_objects):
        bpy.data.objects.remove(obj)
    bpy.data.collections.remove(col)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def rest(export=True):
    for obj in sockets():
        if "kit_rest" not in obj:
            continue
        v = list(obj["kit_rest"])
        obj.matrix_world = Matrix([v[0:4], v[4:8], v[8:12], v[12:16]])
        del obj["kit_rest"]
        bpy.context.view_layer.update()
    remove_reference()
    print("sockets back to rest")
    if export:
        bpy.ops.wm.save_mainfile()
        root = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", ".."))
        exec(open(os.path.join(root, "tools", "blender", "export_parts.py")).read(), {"__name__": "__main__"})


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mode = argv[0] if argv else MODE
    pose() if mode == "pose" else rest()
