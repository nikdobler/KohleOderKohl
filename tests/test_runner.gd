extends SceneTree
## Test-Runner (M0) — startbar ohne Fenster:
##   godot --headless --script res://tests/test_runner.gd
##
## Sammelt alle Test-Suiten, fuehrt sie aus und beendet mit Exit-Code 0
## (alles gruen) oder 1 (mind. ein Fehler), damit CI/Skripte es auswerten.
##
## Ausfuehrung bewusst in der ersten Frame (_process), NICHT in _initialize:
## Autoloads (z. B. SaveManager) sind erst im laufenden Baum garantiert da.

## Liste der Test-Skripte. Neue Suiten hier eintragen.
const _SUITES: Array[String] = [
	"res://tests/test_save_manager.gd",
	"res://tests/test_economy.gd",
	"res://tests/test_research.gd",
	"res://tests/test_world_map.gd",
	"res://tests/test_combat.gd",
	"res://tests/test_dialogue.gd",
	"res://tests/test_scenario.gd",
	"res://tests/test_campaign.gd",
	"res://tests/test_placement.gd",
	"res://tests/test_ambient_life.gd",
	"res://tests/test_settlement_props.gd",
	"res://tests/test_feature_variants.gd",
	"res://tests/test_mountain_scenery.gd",
	"res://tests/test_village_life.gd",
	"res://tests/test_outskirts.gd",
]

var _done: bool = false

func _process(_delta: float) -> bool:
	if _done:
		return true  # true == MainLoop beenden
	_done = true

	var total_failures: Array = []
	for suite_path in _SUITES:
		var suite_script: GDScript = load(suite_path)
		if suite_script == null:
			total_failures.append("Suite nicht ladbar: %s" % suite_path)
			continue
		var suite: RefCounted = suite_script.new()
		var failures: Array = suite.run()
		if failures.is_empty():
			print("PASS  %s" % suite_path)
		else:
			for msg in failures:
				print("FAIL  %s -> %s" % [suite_path, msg])
			total_failures.append_array(failures)

	print("---")
	if total_failures.is_empty():
		print("Alle Tests bestanden.")
		quit(0)
	else:
		print("%d Fehler." % total_failures.size())
		quit(1)
	return true
