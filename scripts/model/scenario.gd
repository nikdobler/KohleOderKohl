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
var _fired: Dictionary = {}  # event_id -> true (Events feuern einmalig)
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

## Zu Beginn bereits erforschte Technologien.
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
			_:
				push_warning("Scenario: unbekannter Effekt-Typ '%s'" % effect.get("type", ""))
	return changed

## Serialisiert Feuer-Status und Zielerreichung fuer den Spielstand.
func to_dict() -> Dictionary:
	return {"fired": _fired.keys(), "completed": completed}

func from_dict(d: Dictionary) -> void:
	_fired.clear()
	for id in d.get("fired", []):
		_fired[String(id)] = true
	completed = bool(d.get("completed", false))
