extends RefCounted
## Unit-Tests fuer das Dialogsystem (M6).
##
## Prueft Trigger-Auswertung, Prioritaet, einmalig/Cooldown, Knoten-Navigation
## mit Antwortoptionen und Roundtrip mit synthetischen Definitionen sowie die
## Konsistenz der echten Dialogdateien. Leere Fehlerliste == bestanden.

const _DEFS := {
	"tester": {
		"npc": {"id": "tester", "display_name": "Tester"},
		"dialogues": [
			{
				"id": "low_wood",
				"trigger": {"type": "stock_below", "resource": "wood", "amount": 5},
				"requires_seen": "intro",
				"once": false, "cooldown_ticks": 10, "priority": 5, "start": "start",
				"nodes": {"start": {"text": "Holz knapp."}},
			},
			{
				"id": "intro",
				"trigger": {"type": "tick_reached", "tick": 3},
				"once": true, "priority": 9, "start": "start",
				"nodes": {
					"start": {"text": "Hallo.", "choices": [
						{"text": "A", "next": "a"}, {"text": "B", "next": "b"}]},
					"a": {"text": "Antwort A.", "next": "ende"},
					"b": {"text": "Antwort B."},
					"ende": {"text": "Schluss."},
				},
			},
		],
	},
}

func run() -> Array:
	var failures: Array = []
	_test_trigger_types(failures)
	_test_requires_seen_gates_dialogue(failures)
	_test_priority_and_once(failures)
	_test_cooldown(failures)
	_test_navigation_with_choices(failures)
	_test_force_start(failures)
	_test_roundtrip(failures)
	_test_data_files_consistent(failures)
	return failures

## force_start (M14): startet unabhaengig vom Trigger; "scripted" feuert
## nie von selbst; einmalige gelten danach als gesehen.
func _test_force_start(failures: Array) -> void:
	var defs := {"tester": {"npc": {"id": "tester", "display_name": "Tester"}, "dialogues": [
		{"id": "story", "trigger": {"type": "scripted"}, "once": true, "start": "start",
			"nodes": {"start": {"text": "Story."}}}]}}
	var d := DialogueSystem.from_defs(defs)
	if not d.check_triggers(_state()).is_empty():
		failures.append("Scripted: darf nie von selbst feuern")
	var result := d.force_start("tester", "story", _state())
	if result.get("node", {}).get("text", "") != "Story." or not d.is_active():
		failures.append("Force: Story-Dialog muss starten")
	d.advance(-1)
	if not d.to_dict().get("seen", []).has("tester/story"):
		failures.append("Force: einmaliger Dialog muss als gesehen gelten")
	if not d.force_start("tester", "fehlt", _state()).is_empty():
		failures.append("Force: unbekannter Dialog muss leer zurueckkommen")

func _state(overrides: Dictionary = {}) -> Dictionary:
	var state := {"tick": 100, "stock": {"wood": 100}, "satisfaction": 100,
		"researched": [], "combat_status": "active"}
	state.merge(overrides, true)
	return state

## Jeder Bedingungstyp wertet korrekt aus (inkl. unbekannt -> false).
## Zentrale Auswertung in TriggerEval (geteilt mit Szenario-Events/-Zielen).
func _test_trigger_types(failures: Array) -> void:
	var checks := [
		[{"type": "always"}, _state(), true],
		[{"type": "tick_reached", "tick": 5}, _state({"tick": 4}), false],
		[{"type": "stock_below", "resource": "wood", "amount": 5}, _state({"stock": {"wood": 4}}), true],
		[{"type": "stock_above", "resource": "wood", "amount": 50}, _state(), true],
		[{"type": "stock_at_least", "resource": "wood", "amount": 100}, _state(), true],
		[{"type": "stock_at_least", "resource": "wood", "amount": 101}, _state(), false],
		[{"type": "satisfaction_below", "amount": 30}, _state({"satisfaction": 29}), true],
		[{"type": "tech_researched", "tech": "brewing"}, _state({"researched": ["brewing"]}), true],
		[{"type": "combat_status", "status": "victory"}, _state(), false],
		[{"type": "gibt_es_nicht"}, _state(), false],
	]
	for check in checks:
		if TriggerEval.met(check[0], check[1]) != check[2]:
			failures.append("Trigger: %s falsch ausgewertet" % str(check[0]))

## requires_seen: Dialog bleibt gesperrt, bis der vorausgesetzte einmalige
## Dialog gesehen wurde (verhindert Noergeln vor der Vorstellung).
func _test_requires_seen_gates_dialogue(failures: Array) -> void:
	var d := DialogueSystem.from_defs(_DEFS)
	# Tick 1: low_wood-Trigger erfuellt (0 Holz), intro noch nicht (tick < 3).
	if not d.check_triggers(_state({"tick": 1, "stock": {"wood": 0}})).is_empty():
		failures.append("Sequenz: low_wood darf vor dem Intro nicht feuern")

## Hoehere Prioritaet gewinnt; einmalige Dialoge feuern nur einmal.
func _test_priority_and_once(failures: Array) -> void:
	var d := DialogueSystem.from_defs(_DEFS)
	var state := _state({"stock": {"wood": 0}})  # beide Trigger erfuellt
	var result := d.check_triggers(state)
	if result.get("node", {}).get("text", "") != "Hallo.":
		failures.append("Prioritaet: intro (9) muss vor low_wood (5) feuern")
	d.advance(0)
	d.advance(-1)
	d.advance(-1)  # intro durchspielen bis Ende
	if d.is_active():
		failures.append("Prioritaet: Dialog muss beendet sein")
	result = d.check_triggers(state)
	if result.get("node", {}).get("text", "") != "Holz knapp.":
		failures.append("Once: intro darf nicht erneut feuern, low_wood ist dran")

## Cooldown blockiert Wiederholungen bis zum Ablauf.
func _test_cooldown(failures: Array) -> void:
	var d := DialogueSystem.from_defs(_DEFS)
	var state := _state({"tick": 50, "stock": {"wood": 0}})
	state["tick"] = 50
	d.check_triggers(state)  # intro
	while d.is_active():
		d.advance(0)
	d.check_triggers(state)  # low_wood, Cooldown bis 60
	while d.is_active():
		d.advance(-1)
	if not d.check_triggers(_state({"tick": 55, "stock": {"wood": 0}})).is_empty():
		failures.append("Cooldown: low_wood darf bei Tick 55 nicht erneut feuern")
	if d.check_triggers(_state({"tick": 60, "stock": {"wood": 0}})).is_empty():
		failures.append("Cooldown: low_wood muss ab Tick 60 wieder feuern")

## Antwortoptionen fuehren zu unterschiedlichen Pfaden; Ende raeumt auf.
func _test_navigation_with_choices(failures: Array) -> void:
	var d := DialogueSystem.from_defs(_DEFS)
	d.check_triggers(_state())  # intro (tick 100)
	var result := d.advance(99)  # ungueltige Wahl -> bleibt stehen
	if result.get("node", {}).get("text", "") != "Hallo.":
		failures.append("Navigation: ungueltige Wahl muss am Knoten bleiben")
	result = d.advance(0)  # Wahl A
	if result.get("node", {}).get("text", "") != "Antwort A.":
		failures.append("Navigation: Wahl A muss zu Knoten a fuehren")
	result = d.advance(-1)  # next -> ende
	if result.get("node", {}).get("text", "") != "Schluss.":
		failures.append("Navigation: next muss zu 'ende' fuehren")
	if not d.advance(-1).is_empty() or d.is_active():
		failures.append("Navigation: Dialog muss nach letztem Knoten enden")

## Gesehen-Status und Cooldowns ueberstehen einen Speicher-Roundtrip.
func _test_roundtrip(failures: Array) -> void:
	var d := DialogueSystem.from_defs(_DEFS)
	d.check_triggers(_state({"stock": {"wood": 0}}))  # intro (once) + aktiv
	var restored := DialogueSystem.from_defs(_DEFS)
	restored.from_dict(d.to_dict())
	if restored.is_active():
		failures.append("Roundtrip: laufender Dialog darf nicht ueberleben")
	var result := restored.check_triggers(_state({"stock": {"wood": 0}}))
	if result.get("node", {}).get("text", "") != "Holz knapp.":
		failures.append("Roundtrip: intro muss als gesehen gelten")

## Echte Dialogdateien: Startknoten existiert, jedes next/choices-Ziel auch,
## referenzierte Ressourcen/Techs ebenfalls.
func _test_data_files_consistent(failures: Array) -> void:
	for npc_id in Database.dialogues:
		for dialogue in Database.dialogues[npc_id].get("dialogues", []):
			var label := "%s/%s" % [npc_id, dialogue.get("id", "?")]
			var nodes: Dictionary = dialogue.get("nodes", {})
			if not nodes.has(dialogue.get("start", "start")):
				failures.append("Daten: Startknoten fehlt in %s" % label)
			for node_id in nodes:
				var targets: Array = []
				for choice in nodes[node_id].get("choices", []):
					targets.append(choice.get("next", ""))
				if nodes[node_id].has("next"):
					targets.append(nodes[node_id]["next"])
				for target in targets:
					if target != "" and not nodes.has(target):
						failures.append("Daten: Ziel '%s' fehlt in %s" % [target, label])
			var trigger: Dictionary = dialogue.get("trigger", {})
			if trigger.has("resource") and not Database.resources.has(trigger["resource"]):
				failures.append("Daten: Trigger-Ressource '%s' fehlt (%s)" % [trigger["resource"], label])
			if trigger.has("tech") and not Database.techs.has(trigger["tech"]):
				failures.append("Daten: Trigger-Tech '%s' fehlt (%s)" % [trigger["tech"], label])
			_check_requires_seen(npc_id, dialogue, label, failures)

## requires_seen muss auf einen existierenden EINMALIGEN Dialog zeigen.
func _check_requires_seen(npc_id: String, dialogue: Dictionary, label: String, failures: Array) -> void:
	var required := String(dialogue.get("requires_seen", ""))
	if required == "" or required.contains("/"):
		return  # fremde NPCs pruefen wir erst, wenn es mehrere gibt
	for other in Database.dialogues[npc_id].get("dialogues", []):
		if other.get("id", "") == required:
			if not other.get("once", false):
				failures.append("Daten: requires_seen-Ziel '%s' ist nicht einmalig (%s)" % [required, label])
			return
	failures.append("Daten: requires_seen-Ziel '%s' fehlt (%s)" % [required, label])
