class_name ScanAlert
extends Node
## Warning on a mech that a pulse scan found (user answer 2026-10-14). Its sound and screen warning come
## later; for now other scripts read the signal or the time of the last scan.

signal scanned(by: Node3D)

## Engine time (seconds) of the last scan that found this mech; -1 = never.
var last_scan_time: float = -1.0


## Tells target (it gets a ScanAlert child if it has none) that by found it.
static func notify(target: Node3D, by: Node3D) -> void:
	var alert := target.get_node_or_null(^"ScanAlert") as ScanAlert
	if alert == null:
		alert = ScanAlert.new()
		alert.name = "ScanAlert"
		target.add_child(alert)
	alert.last_scan_time = Time.get_ticks_msec() / 1000.0
	alert.scanned.emit(by)
