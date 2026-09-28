class_name BulletMark
extends Decal
## A dark mark where a bullet hit. Stays for a while, then fades out.
## Only the newest max_marks marks stay; older ones are removed.

## Seconds before the mark starts to fade.
@export var life: float = 20.0
## Fade time, in seconds.
@export var fade_time: float = 3.0
## Most marks in the world at the same time.
@export var max_marks: int = 60

static var _marks: Array[BulletMark] = []

var _age: float = 0.0


func _ready() -> void:
	_marks.append(self)
	while _marks.size() > max_marks:
		var oldest: BulletMark = _marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	rotate_object_local(Vector3.UP, randf() * TAU)


func _exit_tree() -> void:
	_marks.erase(self)


func _process(delta: float) -> void:
	_age += delta
	if _age > life:
		albedo_mix = clampf(1.0 - (_age - life) / fade_time, 0.0, 1.0)
		if albedo_mix <= 0.0:
			queue_free()
