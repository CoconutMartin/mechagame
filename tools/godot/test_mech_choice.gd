extends RefCounted
## Lets a test run on another mech than the map's (the HLY refit, 2026-11-08). MECH=haliya puts the Haliya HLY-101 head, core, arms
## and legs into the test's loadout (the legs pick scenes/mech/haliya.tscn, as in the garage); without MECH the loadout stays as it
## is. Used by the tests through preload: loadout = MechChoice.apply(loadout) before LoadoutSwitcher.rebuild.

## Mech name -> PartData folder and file prefix.
const FOLDERS := {"haliya": "res://data/parts/haliya/haliya_", "sgg": "res://data/parts/sanggigilid/sanggigilid_"}
## Loadout slot -> file suffix.
const SLOTS := {"head": "head", "core": "core", "arm_left": "arm_l", "arm_right": "arm_r", "legs": "legs"}


## The mech the test runs on ("" = the map's).
static func mech() -> String:
	return OS.get_environment("MECH")


## The loadout with the parts of the MECH mech (the same loadout when MECH is not set).
static func apply(loadout: Loadout) -> Loadout:
	var folder: String = FOLDERS.get(mech(), "")
	if folder == "" or loadout == null:
		return loadout
	for slot: String in SLOTS:
		loadout.set(slot, load(folder + SLOTS[slot] + ".tres"))
	return loadout


## The mech scene of the MECH mech (for tests that place a second mech), else fallback.
static func scene(fallback: String) -> String:
	return "res://scenes/mech/haliya.tscn" if mech() == "haliya" else fallback
