class_name AnimationLooper
extends Node
## Plays one animation of an imported model on a loop. Put it under the model instance.
## Finds the first AnimationPlayer inside the model.

## Name of the animation to play (the Blender action name).
@export var animation_name: StringName = &"walk"
## Playback speed (1.0 = as made in Blender).
@export var speed: float = 1.0

var player: AnimationPlayer


func _ready() -> void:
	var found := get_parent().find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("AnimationLooper: no AnimationPlayer under %s" % get_parent().name)
		return
	player = found[0] as AnimationPlayer
	if not player.has_animation(animation_name):
		push_warning("AnimationLooper: no animation '%s' (has %s)" % [animation_name, player.get_animation_list()])
		return
	player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = speed
	player.play(animation_name)
