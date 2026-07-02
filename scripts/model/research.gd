class_name Research
extends RefCounted
## Research — Tech-Tree-Grundgeruest (M3).
##
## Reine, headless testbare Logik: Voraussetzungen, Ressourcenkosten und
## Freischaltungen. Die Definitionen kommen datengetrieben aus
## /data/tech.json (siehe [Database]); diese Klasse haelt einen typisierten
## Schnappschuss davon plus die Menge der erforschten Technologien.
## Was in keiner Technologie als Freischaltung auftaucht, gilt als von
## Beginn an verfuegbar — tech.json ist die einzige Quelle fuer Sperren.

const STATUS_LOCKED: StringName = &"locked"
const STATUS_AVAILABLE: StringName = &"available"
const STATUS_RESEARCHED: StringName = &"researched"
const STATUS_RESEARCHING: StringName = &"researching"

var _defs: Dictionary = {}                 # StringName -> typisierte Def
var _locking_tech_building: Dictionary = {}  # Gebaeude-ID -> Tech-ID
var _locking_tech_resource: Dictionary = {}  # Ressourcen-ID -> Tech-ID
var researched: Array = []                 # Array[StringName]
## Zeitbasierte Forschung (M12): genau ein aktives Projekt.
var active: StringName = &""
var progress_ticks: int = 0

## Baut die Forschung aus den JSON-Definitionen auf (Schluessel: Tech-ID).
static func from_defs(defs: Dictionary) -> Research:
	var r := Research.new()
	for key in defs:
		var id := StringName(key)
		r._defs[id] = r._typed_def(defs[key])
		for b in r._defs[id]["unlock_buildings"]:
			r._locking_tech_building[b] = id
		for res in r._defs[id]["unlock_resources"]:
			r._locking_tech_resource[res] = id
	return r

## Alle bekannten Tech-IDs (in Definitionsreihenfolge).
func tech_ids() -> Array:
	return _defs.keys()

func is_researched(id: StringName) -> bool:
	return researched.has(id)

## Sind alle Voraussetzungen einer Technologie erforscht?
func prerequisites_met(id: StringName) -> bool:
	if not _defs.has(id):
		return false
	for prereq in _defs[id]["prerequisites"]:
		if not is_researched(prereq):
			return false
	return true

## Anzeige-Status fuer die UI (beruecksichtigt keine Kosten — die prueft
## erst der Forschungsversuch).
func status(id: StringName) -> StringName:
	if is_researched(id):
		return STATUS_RESEARCHED
	if active == id:
		return STATUS_RESEARCHING
	return STATUS_AVAILABLE if prerequisites_met(id) else STATUS_LOCKED

## Startet ein zeitbasiertes Forschungsprojekt (M12): prueft wie
## [method try_research] und zieht die Kosten sofort ab; abgeschlossen wird
## per [method tick_research]. Techs ohne duration_ticks sind sofort fertig
## (Rueckgabe enthaelt dann bereits die Freischaltungen).
func start_research(id: StringName, economy: Economy) -> Dictionary:
	if active != &"":
		return _failure("Die Gelehrten sind schon beschäftigt.")
	if not _defs.has(id):
		return _failure("Unbekannte Technologie.")
	if is_researched(id):
		return _failure("Bereits erforscht.")
	if not prerequisites_met(id):
		return _failure("Voraussetzungen fehlen.")
	var cost := get_cost(id)
	for res in cost:
		if economy.get_stock(res) < int(cost[res]):
			return _failure("Nicht genug Ressourcen.")
	for res in cost:
		economy.stock[res] = economy.get_stock(res) - int(cost[res])
	if int(_defs[id]["duration_ticks"]) <= 0:
		researched.append(id)
		return _completed(id)
	active = id
	progress_ticks = 0
	return {"ok": true, "reason": "", "completed": &"",
		"unlocked_buildings": [], "unlocked_resources": []}

## Ein Forschungs-Tick. Rueckgabe: {} oder das Abschluss-Ergebnis
## (wie try_research, plus "completed": Tech-ID).
func tick_research() -> Dictionary:
	if active == &"":
		return {}
	progress_ticks += 1
	if progress_ticks < int(_defs[active]["duration_ticks"]):
		return {}
	var done := active
	active = &""
	progress_ticks = 0
	researched.append(done)
	return _completed(done)

## Fortschritt des aktiven Projekts (0..1; 0 wenn keines laeuft).
func progress_ratio() -> float:
	if active == &"":
		return 0.0
	return clampf(float(progress_ticks) / float(maxi(1, int(_defs[active]["duration_ticks"]))), 0.0, 1.0)

func _completed(id: StringName) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"completed": id,
		"unlocked_buildings": _defs[id]["unlock_buildings"],
		"unlocked_resources": _defs[id]["unlock_resources"],
	}

## Kosten einer Technologie (StringName -> int).
func get_cost(id: StringName) -> Dictionary:
	return _defs.get(id, {}).get("cost", {})

## Ist ein Gebaeude verfuegbar? (Nicht gesperrt oder Sperr-Tech erforscht.)
func is_building_unlocked(id: StringName) -> bool:
	var tech: Variant = _locking_tech_building.get(id)
	return tech == null or is_researched(tech)

## Ist eine Ressource verfuegbar? (Analog zu Gebaeuden.)
func is_resource_unlocked(id: StringName) -> bool:
	var tech: Variant = _locking_tech_resource.get(id)
	return tech == null or is_researched(tech)

## Forschungsversuch: prueft Zustand, Voraussetzungen und Kosten, zieht die
## Kosten von [param economy] ab und markiert die Technologie als erforscht.
## Rueckgabe: {"ok": bool, "reason": String, "unlocked_buildings": Array,
## "unlocked_resources": Array}.
func try_research(id: StringName, economy: Economy) -> Dictionary:
	if not _defs.has(id):
		return _failure("Unbekannte Technologie.")
	if is_researched(id):
		return _failure("Bereits erforscht.")
	if not prerequisites_met(id):
		return _failure("Voraussetzungen fehlen.")
	var cost := get_cost(id)
	for res in cost:
		if economy.get_stock(res) < int(cost[res]):
			return _failure("Nicht genug Ressourcen.")
	for res in cost:
		economy.stock[res] = economy.get_stock(res) - int(cost[res])
	researched.append(id)
	return {
		"ok": true,
		"reason": "",
		"unlocked_buildings": _defs[id]["unlock_buildings"],
		"unlocked_resources": _defs[id]["unlock_resources"],
	}

## Schaltet eine Technologie ohne Kosten frei (FE-Transfer bei Eroberung,
## Spez. 1.4). Rueckgabe wie [method try_research].
func grant(id: StringName) -> Dictionary:
	if not _defs.has(id):
		return _failure("Unbekannte Technologie.")
	if is_researched(id):
		return _failure("Bereits erforscht.")
	researched.append(id)
	return {
		"ok": true,
		"reason": "",
		"unlocked_buildings": _defs[id]["unlock_buildings"],
		"unlocked_resources": _defs[id]["unlock_resources"],
	}

## Guenstigste Technologie, die in [param other_researched] enthalten ist,
## hier aber fehlt (Summe der Ressourcenkosten; Gleichstand: zuerst
## definierte). &"" wenn kein Vorsprung besteht.
func cheapest_missing_from(other_researched: Array) -> StringName:
	var best: StringName = &""
	var best_cost := 0
	for raw_id in other_researched:
		var id := StringName(raw_id)
		if not _defs.has(id) or is_researched(id):
			continue
		var total := 0
		for res in _defs[id]["cost"]:
			total += int(_defs[id]["cost"][res])
		if best == &"" or total < best_cost:
			best = id
			best_cost = total
	return best

## Serialisiert den Forschungsstand fuer den Spielstand.
func to_dict() -> Dictionary:
	var out: Array = []
	for id in researched:
		out.append(String(id))
	return {"researched": out, "active": String(active), "progress_ticks": progress_ticks}

## Stellt den Forschungsstand wieder her (unbekannte IDs werden ignoriert).
func from_dict(d: Dictionary) -> void:
	researched.clear()
	for id in d.get("researched", []):
		var typed := StringName(id)
		if _defs.has(typed):
			researched.append(typed)
	active = StringName(d.get("active", ""))
	if not _defs.has(active) or is_researched(active):
		active = &""
	progress_ticks = int(d.get("progress_ticks", 0)) if active != &"" else 0

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "unlocked_buildings": [], "unlocked_resources": []}

## JSON liefert String-Schluessel/float-Werte -> typisierter Schnappschuss.
func _typed_def(raw: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	for key in raw.get("cost", {}):
		cost[StringName(key)] = int(raw["cost"][key])
	var prereqs: Array = []
	for p in raw.get("prerequisites", []):
		prereqs.append(StringName(p))
	var unlocks: Dictionary = raw.get("unlocks", {})
	var unlock_buildings: Array = []
	for b in unlocks.get("buildings", []):
		unlock_buildings.append(StringName(b))
	var unlock_resources: Array = []
	for res in unlocks.get("resources", []):
		unlock_resources.append(StringName(res))
	return {
		"cost": cost,
		"prerequisites": prereqs,
		"unlock_buildings": unlock_buildings,
		"unlock_resources": unlock_resources,
		"duration_ticks": int(raw.get("duration_ticks", 0)),
	}
