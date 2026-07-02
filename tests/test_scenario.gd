extends RefCounted
## Unit-Tests fuer das Szenariosystem (M7).
##
## Prueft Startbedingungen, Event-Regeln (einmalig, Effekte), Zielpruefung
## und Roundtrip mit synthetischen Definitionen sowie die Konsistenz der
## echten Szenariodateien. Leere Fehlerliste == bestanden.

const _DEF := {
	"id": "test",
	"display_name": "Testszenario",
	"start": {
		"stock": {"wood": 7},
		"researched": ["stonemasonry"],
		"buildings": [{"id": "keep", "workers": 0}, {"id": "woodcutter", "workers": 1}],
	},
	"goal": {
		"description": "10 Holz sammeln.",
		"trigger": {"type": "stock_at_least", "resource": "wood", "amount": 10},
	},
	"events": [
		{
			"id": "frost",
			"trigger": {"type": "tick_reached", "tick": 5},
			"message": "Frost!",
			"effects": [
				{"type": "stock_multiply", "resource": "wheat", "factor": 0.0},
				{"type": "satisfaction_add", "amount": -10},
			],
		},
	],
}

func run() -> Array:
	var failures: Array = []
	_test_start_config(failures)
	_test_events_fire_once(failures)
	_test_apply_effects(failures)
	_test_goal_edge(failures)
	_test_roundtrip(failures)
	_test_data_files_consistent(failures)
	return failures

func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {"tick": 1, "stock": {}, "satisfaction": 50,
		"researched": [], "combat_status": "active"}
	state.merge(overrides, true)
	return state

## Startbedingungen werden typisiert ausgelesen.
func _test_start_config(failures: Array) -> void:
	var s := Scenario.from_def(_DEF)
	if s.start_stock().get(&"wood", 0) != 7:
		failures.append("Start: Bestand falsch")
	var buildings := s.start_buildings()
	if buildings.size() != 2 or buildings[0]["id"] != &"keep" or buildings[1]["workers"] != 1:
		failures.append("Start: Gebaeudeliste falsch")
	if s.start_researched() != [&"stonemasonry"]:
		failures.append("Start: Forschung falsch")

## Events feuern beim Trigger — und genau einmal.
func _test_events_fire_once(failures: Array) -> void:
	var s := Scenario.from_def(_DEF)
	if not s.pending_events(_state({"tick": 4})).is_empty():
		failures.append("Events: darf vor Tick 5 nicht feuern")
	var fired := s.pending_events(_state({"tick": 5}))
	if fired.size() != 1 or fired[0].get("message", "") != "Frost!":
		failures.append("Events: Frost muss bei Tick 5 feuern")
	if not s.pending_events(_state({"tick": 6})).is_empty():
		failures.append("Events: darf nur einmal feuern")

## Effekt-Regeln veraendern die Wirtschaft korrekt (inkl. Klammerung bei 0).
func _test_apply_effects(failures: Array) -> void:
	var eco := Economy.new()
	eco.stock[&"wheat"] = 42
	eco.satisfaction = 5
	var changed := Scenario.apply_effects([
		{"type": "stock_multiply", "resource": "wheat", "factor": 0.0},
		{"type": "stock_add", "resource": "wood", "amount": -10},
		{"type": "satisfaction_add", "amount": -20},
	], eco)
	if eco.get_stock(&"wheat") != 0:
		failures.append("Effekte: stock_multiply 0 muss Weizen leeren")
	if eco.get_stock(&"wood") != 0:
		failures.append("Effekte: Bestand darf nicht negativ werden")
	if eco.satisfaction != 0:
		failures.append("Effekte: Zufriedenheit muss bei 0 klammern")
	if changed != [&"wheat", &"wood"]:
		failures.append("Effekte: veraenderte Ressourcen falsch: %s" % str(changed))

## Zielpruefung: true nur auf der Flanke, danach completed.
func _test_goal_edge(failures: Array) -> void:
	var s := Scenario.from_def(_DEF)
	if s.check_goal(_state({"stock": {"wood": 9}})):
		failures.append("Ziel: darf bei 9 Holz nicht erreicht sein")
	if not s.check_goal(_state({"stock": {"wood": 10}})):
		failures.append("Ziel: muss bei 10 Holz erreicht werden")
	if s.check_goal(_state({"stock": {"wood": 10}})) or not s.completed:
		failures.append("Ziel: Flanke darf nur einmal true liefern")

## Feuer-Status und Zielerreichung ueberstehen einen Speicher-Roundtrip.
func _test_roundtrip(failures: Array) -> void:
	var s := Scenario.from_def(_DEF)
	s.pending_events(_state({"tick": 5}))
	s.check_goal(_state({"stock": {"wood": 10}}))
	var restored := Scenario.from_def(_DEF)
	restored.from_dict(s.to_dict())
	if not restored.completed:
		failures.append("Roundtrip: completed verloren")
	if not restored.pending_events(_state({"tick": 6})).is_empty():
		failures.append("Roundtrip: gefeuertes Event darf nicht erneut feuern")

## Echte Szenariodateien: alles Referenzierte muss existieren, der Bergfried
## muss das erste Gebaeude sein (Kampfsystem erwartet ihn auf Bauplatz 0).
func _test_data_files_consistent(failures: Array) -> void:
	for scenario_id in Database.scenarios:
		var def: Dictionary = Database.scenarios[scenario_id]
		var start: Dictionary = def.get("start", {})
		for res in start.get("stock", {}):
			if not Database.resources.has(res):
				failures.append("Daten: Start-Ressource '%s' fehlt (%s)" % [res, scenario_id])
		for tech in start.get("researched", []):
			if not Database.techs.has(tech):
				failures.append("Daten: Start-Tech '%s' fehlt (%s)" % [tech, scenario_id])
		var buildings: Array = start.get("buildings", [])
		if buildings.is_empty() or buildings[0].get("id", "") != "keep":
			failures.append("Daten: erstes Gebaeude muss 'keep' sein (%s)" % scenario_id)
		for entry in buildings:
			if not Database.buildings.has(entry.get("id", "")):
				failures.append("Daten: Gebaeude '%s' fehlt (%s)" % [entry.get("id", ""), scenario_id])
		if def.get("goal", {}).get("trigger", {}).is_empty():
			failures.append("Daten: Ziel ohne Trigger (%s)" % scenario_id)
		for event in def.get("events", []):
			if String(event.get("message", "")).is_empty():
				failures.append("Daten: Event '%s' ohne Meldung (%s)" % [event.get("id", "?"), scenario_id])
			for effect in event.get("effects", []):
				if effect.has("resource") and not Database.resources.has(effect["resource"]):
					failures.append("Daten: Effekt-Ressource '%s' fehlt (%s)" % [effect["resource"], scenario_id])
