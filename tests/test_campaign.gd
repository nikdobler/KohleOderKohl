extends RefCounted
## Unit-Tests fuer die Kampagne (M14).
##
## Prueft die Freischalt-Kette (Kapitel N braucht N-1), Fortschritts-Roundtrip
## und die Konsistenz von /data/campaign.json samt referenzierter Szenarien,
## Dialoge und Quest-Regeln. Leere Fehlerliste == bestanden.

const _DEF := {
	"id": "test_kampagne",
	"display_name": "Testkampagne",
	"chapters": [
		{"id": "k1", "scenario": "s1", "title": "Eins", "intro": "i1", "outro": "o1"},
		{"id": "k2", "scenario": "s2", "title": "Zwei", "intro": "i2", "outro": "o2"},
		{"id": "k3", "scenario": "s3", "title": "Drei", "intro": "i3", "outro": "o3"},
	],
}

func run() -> Array:
	var failures: Array = []
	_test_unlock_chain(failures)
	_test_overview_and_next(failures)
	_test_roundtrip(failures)
	_test_data_file_consistent(failures)
	return failures

## Kapitel 1 ist immer offen; jedes weitere braucht den Vorgaenger.
func _test_unlock_chain(failures: Array) -> void:
	var c := Campaign.from_def(_DEF)
	if not c.is_unlocked("k1") or c.is_unlocked("k2") or c.is_unlocked("k3"):
		failures.append("Freischaltung: nur k1 darf zu Beginn offen sein")
	c.complete("k1")
	if not c.is_unlocked("k2") or c.is_unlocked("k3"):
		failures.append("Freischaltung: k1-Abschluss oeffnet genau k2")
	c.complete("gibt_es_nicht")
	if c.is_completed("gibt_es_nicht"):
		failures.append("Freischaltung: unbekannte Kapitel duerfen nicht abschliessen")
	if c.is_unlocked("gibt_es_nicht"):
		failures.append("Freischaltung: unbekannte Kapitel sind nie offen")

## Uebersicht fuer die UI und Kapitelfolge.
func _test_overview_and_next(failures: Array) -> void:
	var c := Campaign.from_def(_DEF)
	c.complete("k1")
	var rows := c.overview()
	if rows.size() != 3 or not rows[0]["completed"] or not rows[1]["unlocked"] or rows[2]["unlocked"]:
		failures.append("Uebersicht: Zustaende falsch: %s" % str(rows))
	if c.next_chapter_id("k1") != "k2" or c.next_chapter_id("k3") != "":
		failures.append("Folge: next_chapter_id falsch")
	if c.chapter_for_scenario("s2").get("id", "") != "k2":
		failures.append("Folge: chapter_for_scenario falsch")

## Fortschritt uebersteht einen Speicher-Roundtrip.
func _test_roundtrip(failures: Array) -> void:
	var c := Campaign.from_def(_DEF)
	c.complete("k1")
	c.complete("k2")
	var restored := Campaign.from_def(_DEF)
	restored.from_dict(c.to_dict())
	if not restored.is_completed("k2") or not restored.is_unlocked("k3"):
		failures.append("Roundtrip: Fortschritt verloren")

## Echte Kampagnendatei: Kapitel vollstaendig, Szenarien vorhanden und als
## campaign_only markiert, Dialog-Effekte und Quests zeigen auf Existierendes.
func _test_data_file_consistent(failures: Array) -> void:
	var chapters: Array = Database.campaign.get("chapters", [])
	if chapters.is_empty():
		failures.append("Daten: campaign.json hat keine Kapitel")
	var seen_scenarios: Dictionary = {}
	for chapter in chapters:
		var label: String = chapter.get("id", "?")
		for field in ["id", "scenario", "title", "intro", "outro"]:
			if String(chapter.get(field, "")).is_empty():
				failures.append("Daten: Kapitel '%s' ohne '%s'" % [label, field])
		var scenario_id := String(chapter.get("scenario", ""))
		if seen_scenarios.has(scenario_id):
			failures.append("Daten: Szenario '%s' doppelt verwendet" % scenario_id)
		seen_scenarios[scenario_id] = true
		var scenario: Dictionary = Database.scenarios.get(scenario_id, {})
		if scenario.is_empty():
			failures.append("Daten: Kapitel-Szenario '%s' fehlt (%s)" % [scenario_id, label])
			continue
		if not scenario.get("campaign_only", false):
			failures.append("Daten: '%s' muss campaign_only sein (%s)" % [scenario_id, label])
		_check_scenario_extras(scenario_id, scenario, failures)

## Quest- und Dialog-Regeln eines Kampagnen-Szenarios.
func _check_scenario_extras(scenario_id: String, scenario: Dictionary, failures: Array) -> void:
	for quest in scenario.get("quests", []):
		var label := "%s/%s" % [scenario_id, quest.get("id", "?")]
		if String(quest.get("description", "")).is_empty():
			failures.append("Daten: Quest ohne Beschreibung (%s)" % label)
		if quest.get("trigger", {}).is_empty():
			failures.append("Daten: Quest ohne Trigger (%s)" % label)
		var building := String(quest.get("trigger", {}).get("building", ""))
		if building != "" and not Database.buildings.has(building):
			failures.append("Daten: Quest-Gebaeude '%s' fehlt (%s)" % [building, label])
		for effect in quest.get("reward", []):
			if effect.has("resource") and not Database.resources.has(effect["resource"]):
				failures.append("Daten: Belohnungs-Ressource '%s' fehlt (%s)" % [effect["resource"], label])
	for event in scenario.get("events", []):
		for effect in event.get("effects", []):
			if String(effect.get("type", "")) != "dialogue":
				continue
			var npc := String(effect.get("npc", ""))
			var dialogue_id := String(effect.get("dialogue", ""))
			if not _dialogue_exists(npc, dialogue_id):
				failures.append("Daten: Dialog '%s/%s' fehlt (%s)" % [npc, dialogue_id, scenario_id])

func _dialogue_exists(npc_id: String, dialogue_id: String) -> bool:
	for dialogue in Database.dialogues.get(npc_id, {}).get("dialogues", []):
		if String(dialogue.get("id", "")) == dialogue_id:
			return true
	return false
