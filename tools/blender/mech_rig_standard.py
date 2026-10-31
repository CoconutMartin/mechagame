"""The joint standard of every mech (DESIGN "Swappable mech parts"): the SGG-101 rig MechRig, plus optional
accessory bones for hanging armor (user request 2026-10-31, Haliya HLY-101: skirt at the hips, sleeves over the
shoulders). A mech that has no skirt or sleeves leaves these bones empty; the animations do not key them, and
AccessoryBoneFollow (Godot) turns them away from the legs and with the arms.

Blender space: Z up, the mech faces -Y, its left side is +X. Meters.
"""
import bpy
from mathutils import Vector

## Accessory bone: (parent, head, tail). Head = the pivot at the top of the plate; tail = down the plate.
ACCESSORY_BONES = {
    "skirt_front_L": ("pelvis", (0.62, -0.66, 6.55), (1.05, -0.94, 3.4)),
    "skirt_front_R": ("pelvis", (-0.62, -0.66, 6.55), (-1.05, -0.94, 3.4)),
    "skirt_side_L": ("pelvis", (1.72, 0.0, 6.6), (2.3, 0.05, 2.8)),
    "skirt_side_R": ("pelvis", (-1.72, 0.0, 6.6), (-2.3, 0.05, 2.8)),
    "skirt_back_L": ("pelvis", (0.62, 0.62, 6.55), (1.05, 1.06, 3.5)),
    "skirt_back_R": ("pelvis", (-0.62, 0.62, 6.55), (-1.05, 1.06, 3.5)),
    "sleeve_L": ("torso", (1.6, 0.0, 8.9), (3.3, 0.0, 5.6)),
    "sleeve_R": ("torso", (-1.6, 0.0, 8.9), (-3.3, 0.0, 5.6)),
}


def ensure_accessory_bones(rig):
    """Adds the accessory bones that the rig does not have yet (edit mode). Returns the names added."""
    missing = [n for n in ACCESSORY_BONES if n not in rig.data.bones]
    if not missing:
        return []
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    rig.hide_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    inverse = rig.matrix_world.inverted()
    for name in missing:
        parent, head, tail = ACCESSORY_BONES[name]
        bone = rig.data.edit_bones.new(name)
        bone.head = inverse @ Vector(head)
        bone.tail = inverse @ Vector(tail)
        bone.roll = 0.0
        bone.parent = rig.data.edit_bones[parent]
        bone.use_connect = False
        bone.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    return missing
