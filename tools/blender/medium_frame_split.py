"""Splits the dark inner frame from the armor on the Medium game parts, so a destroyed part keeps its
skeleton in the game (PartBreaker keeps meshes whose material name starts with "frame" or "joint").

Run (from the project root), then export:
    blender -b models/medium_mech/medium_mech.blend --python tools/blender/medium_frame_split.py

Medium's pieces come from AI models with one painted texture each: olive armor and dark grey frame in
the same mesh. Each mesh island (a connected piece) is sorted by its texture brightness (area-weighted
mean of the base color under each face): darker than FRAME_LUMINANCE = frame. Frame islands move to a
new object "<piece>_frame" on the same socket, with a copy of the material named "frame_<piece>" (same
texture, so the look does not change). A piece with only frame islands gets the frame material. Pieces
already split are skipped, so the script can run again.
It also refreshes the text blocks kit_pose_POSE.py, kit_pose_REST_and_export.py and export_parts.py.
"""
import os, re
import bmesh
import bpy
import numpy as np

## Island brightness (linear luminance 0 to 1) below which an island counts as frame. Measured on the
## Medium textures: frame about 0.09 to 0.16, olive armor 0.2 and up.
FRAME_LUMINANCE = 0.18
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
_pixels = {}


def base_image(mat):
    if mat is None or not mat.use_nodes:
        return None
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None or not bsdf.inputs["Base Color"].links:
        return None
    node = bsdf.inputs["Base Color"].links[0].from_node
    while node is not None and node.type != "TEX_IMAGE":
        node = node.inputs[0].links[0].from_node if node.inputs and node.inputs[0].links else None
    return node.image if node is not None else None


def pixels(image):
    if image.name not in _pixels:
        w, h = image.size
        data = np.empty(w * h * 4, np.float32)
        image.pixels.foreach_get(data)
        _pixels[image.name] = (data.reshape(h, w, 4), w, h)
    return _pixels[image.name]


def islands(bm):
    bm.faces.ensure_lookup_table()
    seen, out = set(), []
    for face in bm.faces:
        if face.index in seen:
            continue
        stack, group = [face], []
        seen.add(face.index)
        while stack:
            f = stack.pop()
            group.append(f)
            for edge in f.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        out.append(group)
    return out


def frame_faces(obj, textured_slot, image):
    """Indexes of the faces of frame islands (islands on the textured slot darker than the limit)."""
    px, w, h = pixels(image)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.active
    found = []
    for group in islands(bm):
        total, weight = 0.0, 0.0
        for f in group:
            if f.material_index != textured_slot:
                continue
            u = sum(l[uv].uv.x for l in f.loops) / len(f.loops)
            v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
            c = px[int((v % 1.0) * (h - 1)), int((u % 1.0) * (w - 1))]
            area = f.calc_area()
            total += (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) * area
            weight += area
        if weight > 0.0 and total / weight < FRAME_LUMINANCE:
            found += [f.index for f in group]
    count = len(bm.faces)
    bm.free()
    return set(found), count


def keep_faces(obj, keep):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def split(obj):
    mats = list(obj.data.materials)
    slot = next((i for i, m in enumerate(mats) if base_image(m) is not None), None)
    if slot is None:
        return "no texture"
    frame, count = frame_faces(obj, slot, base_image(mats[slot]))
    if not frame:
        return "no frame"
    frame_mat = mats[slot].copy()
    frame_mat.name = "frame_" + obj.name
    if len(frame) == count:
        obj.data.materials[slot] = frame_mat
        return "all frame"
    copy = obj.copy()
    copy.data = obj.data.copy()
    copy.name = obj.name + "_frame"
    copy.data.name = copy.name
    for col in obj.users_collection:
        col.objects.link(copy)
    keep_faces(copy, frame)
    copy.data.materials[slot] = frame_mat
    keep_faces(obj, set(range(count)) - frame)
    return f"{len(frame)} of {count} faces to {copy.name}"


def refresh_texts():
    src = open(os.path.join(ROOT, "tools", "blender", "kit_pose.py")).read()
    for name, mode in (("kit_pose_POSE.py", "pose"), ("kit_pose_REST_and_export.py", "rest")):
        text = bpy.data.texts.get(name) or bpy.data.texts.new(name)
        text.from_string(re.sub(r'^MODE = "pose"$', f'MODE = "{mode}"', src, count=1, flags=re.M))
    text = bpy.data.texts.get("export_parts.py") or bpy.data.texts.new("export_parts.py")
    text.from_string(open(os.path.join(ROOT, "tools", "blender", "export_parts.py")).read())


def main():
    if any("kit_rest" in o for o in bpy.data.objects):
        raise RuntimeError("The kit is posed: run kit_pose.py with MODE = \"rest\" first.")
    pieces = [o for c in bpy.data.collections if c.name.startswith("part_") for o in c.objects
              if o.type == "MESH" and (o.name.startswith("md_") or o.name.startswith("Foot"))
              and not o.name.endswith("_frame") and (o.name + "_frame") not in bpy.data.objects
              and not any(m and m.name == "frame_" + o.name for m in o.data.materials)]
    for obj in pieces:
        print("split", obj.name, "->", split(obj))
    refresh_texts()
    bpy.ops.wm.save_mainfile()


if __name__ == "__main__":
    main()
