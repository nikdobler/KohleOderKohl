class_name Scenario
extends RefCounted
## Scenario — datengetriebenes Szenario (M7, goal §5).
##
## Eine Datei in /data/scenarios/*.json beschreibt Startbedingungen (Bestand,
## Gebaeude, Forschung), ein Ziel und Events ("Ernteausfall" & Co.) — alles
## als Regeln, kein Sondercode. Bedingungen laufen ueber [TriggerEval] (wie
## Dialoge), Effekte sind typisierte Regeln auf der [Economy]. Rein und
## headless testbar.

var _def: Dictionary = {}
var _fired: Dictionary = {}        # event_id -> true (Events feuern einmalig)
var _quests_done: Dictionary = {}  # quest_id -> true (Auftraege schliessen einmalig ab)
var completed: bool = false

static func from_def(def: Dictionary) -> Scenario:
	var scenario := Scenario.new()
	scenario._def = def
	return scenario

func display_name() -> String:
	return _def.get("display_name", "Freies Spiel")

func goal_description() -> String:
	return _def.get("goal", {}).get("description", "")

## Start-Bestand (StringName -> int).
func start_stock() -> Dictionary:
	var stock: Dictionary = {}
	for key in _def.get("start", {}).get("stock", {}):
		stock[StringName(key)] = int(_def["start"]["stock"][key])
	return stock

## Start-Gebaeude in Bau-Reihenfolge: [{"id": StringName, "workers": int}].
func start_buildings() -> Array:
	var buildings: Array = []
	for entry in _def.get("start", {}).get("buildings", []):
		buildings.append({"id": StringName(entry.get("id", "")), "workers": int(entry.get("workers", 0))})
	return buildings

## Szenario-spezifische Gegner-Anpassung (M12): wird ueber die Standard-
## Konfiguration aus enemy.json gelegt (z. B. haertere Wellen bei Belagerung).
func enemy_override() -> Dictionary:
	return _def.get("enemy", {})

## Kampagnen-Kapitel erscheinen nicht in der freien Szenario-Auswahl (M14).
func campaign_only() -> bool:
	return _def.get("campaign_only", false)

## Zu Beginn bereits erforschte Technologien.
## Saison, in der das Szenario beginnt (Standard Fruehling, M-Startsaison).
## Versetzt den Jahreszeiten-Lauf, sodass z. B. eine Winter-Partie sofort mit
## ruhenden Feldern startet.
func start_season() -> StringName:
	return StringName(_def.get("start", {}).get("season", "spring"))

## Siedlungstyp des Szenarios (Standard "heartland", M-Gebaeudevarianten) —
## bestimmt die optischen Gebaeude-Stile.
func start_settlement_type() -> StringName:
	return StringName(_def.get("start", {}).get("settlement_type", "heartland"))

func start_researched() -> Array:
	var researched: Array = []
	for id in _def.get("start", {}).get("researched", []):
		researched.append(StringName(id))
	return researched

## Prueft alle Event-Trigger gegen den Schnappschuss und liefert die jetzt
## feuernden Events (jedes Event feuert genau einmal).
func pending_events(state: Dictionary) -> Array:
	var fired_now: Array = []
	for event in _def.get("events", []):
		var id := String(event.get("id", ""))
		if _fired.has(id):
			continue
		if not TriggerEval.met(event.get("trigger", {}), state):
			continue
		_fired[id] = true
		fired_now.append(event)
	return fired_now

## Prueft offene Auftraege (Side-Quests, M14) gegen den Schnappschuss und
## liefert die jetzt abgeschlossenen (jeder Auftrag schliesst genau einmal ab).
func pending_quests(state: Dictionary) -> Array:
	var done_now: Array = []
	for quest in _def.get("quests", []):
		var id := String(quest.get("id", ""))
		if _quests_done.has(id):
			continue
		if not TriggerEval.met(quest.get("trigger", {}), state):
			continue
		_quests_done[id] = true
		done_now.append(quest)
	return done_now

## Auftragsliste fuer das Quest-Log der UI: Beschreibung + erledigt?
func quest_states() -> Array:
	var states: Array = []
	for quest in _def.get("quests", []):
		states.append({
			"description": quest.get("description", ""),
			"done": _quests_done.has(String(quest.get("id", ""))),
		})
	return states

## Zielpruefung mit Flanke: true genau in dem Moment, in dem das Ziel
## erstmals erreicht wird; danach bleibt [member completed] gesetzt.
func check_goal(state: Dictionary) -> bool:
	if completed:
		return false
	if TriggerEval.met(_def.get("goal", {}).get("trigger", {}), state):
		completed = true
		return true
	return false

## Wendet Event-Effekte auf die Wirtschaft an (Regel-Typen: stock_add,
## stock_multiply, satisfaction_add). Rueckgabe: veraenderte Ressourcen-IDs.
static func apply_effects(effects: Array, economy: Economy) -> Array:
	var changed: Array = []
	for effect in effects:
		var resource := StringName(effect.get("resource", ""))
		match String(effect.get("type", "")):
			"stock_add":
				economy.stock[resource] = maxi(0, economy.get_stock(resource) + int(effect.get("amount", 0)))
				changed.append(resource)
			"stock_multiply":
				economy.stock[resource] = maxi(0, roundi(economy.get_stock(resource) * float(effect.get("factor", 1.0))))
				changed.append(resource)
			"satisfaction_add":
				economy.satisfaction = clampi(economy.satisfaction + int(effect.get("amount", 0)), 0, 100)
			"wave", "dialogue":
				pass  # behandelt der Controller (Kampfsystem bzw. Dialogsystem)
			_:
				push_warning("Scenario: unbekannter Effekt-Typ '%s'" % effect.get("type", ""))
	return changed

## Serialisiert Feuer-Status, Auftraege und Zielerreichung fuer den Spielstand.
func to_dict() -> Dictionary:
	return {"fired": _fired.keys(), "quests": _quests_done.keys(), "completed": completed}

func from_dict(d: Dictionary) -> void:
	_fired.clear()
	for id in d.get("fired", []):
		_fired[String(id)] = true
	_quests_done.clear()
	for id in d.get("quests", []):
		_quests_done[String(id)] = true
	completed = bool(d.get("completed", false))
