extends RefCounted
## Unit-Tests fuer das Forschungssystem (M3).
##
## Prueft Voraussetzungen, Kosten, Freischaltungen und Speicher-Roundtrip mit
## synthetischen Definitionen sowie die Konsistenz der echten Datendateien.
## Leere Fehlerliste == bestanden.

## Synthetischer Mini-Tech-Tree: b setzt a voraus.
const _DEFS := {
	"tech_a": {
		"cost": {"wood": 5},
		"prerequisites": [],
		"unlocks": {"buildings": ["quarry"], "resources": ["stone"]},
	},
	"tech_b": {
		"cost": {"stone": 3},
		"prerequisites": ["tech_a"],
		"unlocks": {"buildings": [], "resources": ["beer"]},
	},
}

func run() -> Array:
	var failures: Array = []
	_test_prerequisites_gate_research(failures)
	_test_cost_is_checked_and_deducted(failures)
	_test_unlocks_apply(failures)
	_test_no_double_research(failures)
	_test_timed_research(failures)
	_test_grant_and_conquest_transfer(failures)
	_test_roundtrip(failures)
	_test_data_files_consistent(failures)
	return failures

func _make_economy(stock: Dictionary) -> Economy:
	var eco := Economy.new()
	for key in stock:
		eco.stock[StringName(key)] = int(stock[key])
	return eco

## Ohne Voraussetzung gesperrt; nach Erforschen der Vorstufe verfuegbar.
func _test_prerequisites_gate_research(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	var eco := _make_economy({"wood": 10, "stone": 10})
	if r.status(&"tech_b") != Research.STATUS_LOCKED:
		failures.append("Prereq: tech_b muss anfangs gesperrt sein")
	if r.try_research(&"tech_b", eco)["ok"]:
		failures.append("Prereq: tech_b darf ohne tech_a nicht erforschbar sein")
	r.try_research(&"tech_a", eco)
	if r.status(&"tech_b") != Research.STATUS_AVAILABLE:
		failures.append("Prereq: tech_b muss nach tech_a verfuegbar sein")

## Zu wenig Ressourcen -> Ablehnung ohne Abzug; sonst Abzug der Kosten.
func _test_cost_is_checked_and_deducted(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	var eco := _make_economy({"wood": 4})
	var result := r.try_research(&"tech_a", eco)
	if result["ok"] or eco.get_stock(&"wood") != 4:
		failures.append("Kosten: Ablehnung bei Mangel muss ohne Abzug bleiben")
	eco.stock[&"wood"] = 7
	result = r.try_research(&"tech_a", eco)
	if not result["ok"] or eco.get_stock(&"wood") != 2:
		failures.append("Kosten: erwartet Erfolg und Restbestand 2, erhalten %d" % eco.get_stock(&"wood"))

## Freischaltungen: vorher gesperrt, nachher frei; Unbeteiligtes bleibt frei.
func _test_unlocks_apply(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	if r.is_building_unlocked(&"quarry") or r.is_resource_unlocked(&"stone"):
		failures.append("Unlock: quarry/stone muessen anfangs gesperrt sein")
	if not r.is_building_unlocked(&"woodcutter") or not r.is_resource_unlocked(&"wood"):
		failures.append("Unlock: nicht gelistete IDs muessen von Beginn an frei sein")
	var result := r.try_research(&"tech_a", _make_economy({"wood": 5}))
	if not r.is_building_unlocked(&"quarry") or not r.is_resource_unlocked(&"stone"):
		failures.append("Unlock: quarry/stone muessen nach tech_a frei sein")
	if result["unlocked_buildings"] != [&"quarry"]:
		failures.append("Unlock: Rueckgabe unlocked_buildings falsch")

## Doppelte Forschung wird abgelehnt (und kostet nichts).
func _test_no_double_research(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	var eco := _make_economy({"wood": 10})
	r.try_research(&"tech_a", eco)
	if r.try_research(&"tech_a", eco)["ok"] or eco.get_stock(&"wood") != 5:
		failures.append("Doppelt: zweite Forschung darf nicht gelingen/kosten")

## M12: zeitbasierte Forschung — Kosten sofort, Abschluss nach duration_ticks,
## nur ein Projekt gleichzeitig, Zustand uebersteht den Roundtrip.
func _test_timed_research(failures: Array) -> void:
	var defs := {
		"slow": {"cost": {"wood": 4}, "duration_ticks": 3, "prerequisites": [],
			"unlocks": {"buildings": ["quarry"], "resources": []}},
		"other": {"cost": {}, "duration_ticks": 2, "prerequisites": [],
			"unlocks": {"buildings": [], "resources": []}},
	}
	var r := Research.from_defs(defs)
	var eco := _make_economy({"wood": 10})
	var started := r.start_research(&"slow", eco)
	if not started["ok"] or started["completed"] != &"" or eco.get_stock(&"wood") != 6:
		failures.append("Zeit: Start muss Kosten abziehen und offen bleiben")
	if r.status(&"slow") != Research.STATUS_RESEARCHING:
		failures.append("Zeit: Status muss 'researching' sein")
	if r.start_research(&"other", eco)["ok"]:
		failures.append("Zeit: zweites Projekt muss abgelehnt werden")
	if not r.tick_research().is_empty() or not r.tick_research().is_empty():
		failures.append("Zeit: darf nicht vor Ablauf fertig sein")
	var restored := Research.from_defs(defs)
	restored.from_dict(r.to_dict())  # Fortschritt 2/3 uebernehmen
	var done := restored.tick_research()
	if done.get("completed", &"") != &"slow" or not restored.is_researched(&"slow"):
		failures.append("Zeit: Abschluss nach Roundtrip fehlgeschlagen (%s)" % str(done))
	if not restored.is_building_unlocked(&"quarry"):
		failures.append("Zeit: Freischaltung nach Abschluss fehlt")

## FE-Transfer (M5): grant kostet nichts; cheapest_missing_from waehlt die
## guenstigste fehlende Technologie und ignoriert Erforschtes/Unbekanntes.
func _test_grant_and_conquest_transfer(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	# tech_a kostet 5, tech_b kostet 3 -> tech_b ist die guenstigste fehlende
	if r.cheapest_missing_from(["tech_a", "tech_b", "unbekannt"]) != &"tech_b":
		failures.append("Transfer: guenstigste fehlende Tech muss tech_b sein")
	var eco := _make_economy({})
	var result := r.grant(&"tech_a")
	if not result["ok"] or not r.is_researched(&"tech_a") or not r.is_building_unlocked(&"quarry"):
		failures.append("Transfer: grant muss kostenlos freischalten")
	if eco.get_stock(&"wood") != 0:
		failures.append("Transfer: grant darf keine Ressourcen abziehen")
	if r.cheapest_missing_from(["tech_a"]) != &"":
		failures.append("Transfer: kein Vorsprung -> keine Tech")
	if r.grant(&"tech_a")["ok"]:
		failures.append("Transfer: doppeltes grant muss abgelehnt werden")

## Forschungsstand uebersteht einen Speicher-Roundtrip.
func _test_roundtrip(failures: Array) -> void:
	var r := Research.from_defs(_DEFS)
	r.try_research(&"tech_a", _make_economy({"wood": 5}))
	var restored := Research.from_defs(_DEFS)
	restored.from_dict(r.to_dict())
	if not restored.is_researched(&"tech_a") or restored.is_researched(&"tech_b"):
		failures.append("Roundtrip: Forschungsstand falsch wiederhergestellt")
	if not restored.is_building_unlocked(&"quarry"):
		failures.append("Roundtrip: Freischaltung nach Laden verloren")

## Echte Datendateien: alles, was tech.json referenziert, muss existieren.
func _test_data_files_consistent(failures: Array) -> void:
	for tech_id in Database.techs:
		var def: Dictionary = Database.techs[tech_id]
		for res in def.get("cost", {}):
			if not Database.resources.has(res):
				failures.append("Daten: Kosten-Ressource '%s' (%s) fehlt" % [res, tech_id])
		for prereq in def.get("prerequisites", []):
			if not Database.techs.has(prereq):
				failures.append("Daten: Voraussetzung '%s' (%s) fehlt" % [prereq, tech_id])
		var unlocks: Dictionary = def.get("unlocks", {})
		for b in unlocks.get("buildings", []):
			if not Database.buildings.has(b):
				failures.append("Daten: Gebaeude '%s' (%s) fehlt" % [b, tech_id])
		for res in unlocks.get("resources", []):
			if not Database.resources.has(res):
				failures.append("Daten: Ressource '%s' (%s) fehlt" % [res, tech_id])
