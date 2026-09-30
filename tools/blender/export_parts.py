"""Exports each part collection of a mech .blend as its own .glb, next to the .blend file.
In Blender: Text Editor > export_parts.py > Run Script (save the .blend first).
Headless: blender -b models/<mech>/<mech>.blend --python tools/blender/export_parts.py
Collection part_<id> -> <mech>_<id>.glb. The guide is not exported."""
import bpy, os

blend = bpy.data.filepath
folder = os.path.dirname(blend)
mech = os.path.splitext(os.path.basename(blend))[0]
view_layer = bpy.context.view_layer


def objects_of(col):
    found = list(col.objects)
    for child in col.children:
        found += objects_of(child)
    return found


for col in bpy.data.collections:
    if not col.name.startswith("part_"):
        continue
    part = col.name[len("part_"):]
    bpy.ops.object.select_all(action="DESELECT")
    objs = [o for o in objects_of(col) if o.name in view_layer.objects]
    for obj in objs:
        obj.hide_set(False)
        obj.select_set(True)
    if not objs:
        continue
    view_layer.objects.active = objs[0]
    path = os.path.join(folder, f"{mech}_{part}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_cameras=False, export_lights=False,
                              export_materials="EXPORT")
    print("exported", path, len(objs), "objects")
