class_name BuildingInstance
extends RefCounted
## BuildingInstance — ein platziertes Gebaeude im Spiel (M1/M2).
##
## Reine Datenklasse ohne Godot-Node/UI, damit die Wirtschaftslogik
## headless testbar bleibt. Wird aus einer datengetriebenen Definition
## (siehe /data/buildings.json) erzeugt und traegt einen Schnappschuss
## der relevanten Werte, damit die [Economy] unabhaengig von der
## [Database] laeuft.

var def_id: StringName = &""
var produces: StringName = &""
var production_per_tick: int = 0
## Verbrauch pro Tick und Arbeiter: StringName -> int (z. B. Weizen der Baeckerei).
var consumes: Dictionary = {}
var max_workers: int = 0
var workers: int = 0
## Wohnplaetze, die dieses Gebaeude bereitstellt (z. B. Wohnhaus).
var housing_capacity: int = 0
## Position auf der Karte (M8: Gebaeude werden platziert).
var cell := Vector2i.ZERO
## Bruchteil-Uebertrag der Produktion (Produktivitaet skaliert die Ausbeute;
## ganze Einheiten gehen ins Lager, der Rest wird hier angespart).
var production_carry: float = 0.0
## Saison-Faktoren der Produktion (M-Jahreszeiten): Saison-ID -> Faktor,
## z. B. {&"winter": 0.0, &"autumn": 1.5}; fehlende Saisons zaehlen als 1.0.
var seasonal: Dictionary = {}

## Erzeugt eine Instanz aus einer Gebaeude-Definition (Dictionary aus JSON).
static func from_def(def: Dictionary) -> BuildingInstance:
	var b := BuildingInstance.new()
	b.def_id = StringName(def.get("id", ""))
	b.produces = StringName(def.get("produces", ""))
	b.production_per_tick = int(def.get("production_per_tick", 0))
	b.consumes = _typed_consumes(def.get("consumes", {}))
	b.max_workers = int(def.get("max_workers", 0))
	b.housing_capacity = int(def.get("housing_capacity", 0))
	b.seasonal = _typed_seasonal(def.get("seasonal", {}))
	return b

## Produktionsfaktor der Saison (1.0, wenn das Gebaeude saisonunabhaengig ist).
func season_factor(season: StringName) -> float:
	return float(seasonal.get(season, 1.0))

## Setzt die Arbeiterzahl, begrenzt auf [0, max_workers].
## Achtung: prueft KEINEN Wohnraum — das ist Regel der [Economy]
## (siehe Economy.try_change_workers).
func set_workers(count: int) -> void:
	workers = clampi(count, 0, max_workers)

## Produktionsmenge pro Tick unter Beruecksichtigung der Arbeiter.
func production() -> int:
	return production_per_tick * workers

## Benoetigte Eingangsmenge einer Ressource pro Tick (skaliert mit Arbeitern).
func input_needed(resource_id: StringName) -> int:
	return int(consumes.get(resource_id, 0)) * workers

## Serialisiert die Instanz fuer den Spielstand.
func to_dict() -> Dictionary:
	var consumes_out: Dictionary = {}
	for key in consumes:
		consumes_out[String(key)] = int(consumes[key])
	return {
		"def_id": String(def_id),
		"produces": String(produces),
		"production_per_tick": production_per_tick,
		"consumes": consumes_out,
		"max_workers": max_workers,
		"workers": workers,
		"housing_capacity": housing_capacity,
		"cell": [cell.x, cell.y],
		"production_carry": production_carry,
		"seasonal": _seasonal_out(),
	}

func _seasonal_out() -> Dictionary:
	var out: Dictionary = {}
	for key in seasonal:
		out[String(key)] = float(seasonal[key])
	return out

## Stellt eine Instanz aus einem gespeicherten Dictionary wieder her.
static func from_dict(d: Dictionary) -> BuildingInstance:
	var b := BuildingInstance.new()
	b.def_id = StringName(d.get("def_id", ""))
	b.produces = StringName(d.get("produces", ""))
	b.production_per_tick = int(d.get("production_per_tick", 0))
	b.consumes = _typed_consumes(d.get("consumes", {}))
	b.max_workers = int(d.get("max_workers", 0))
	b.workers = int(d.get("workers", 0))
	b.housing_capacity = int(d.get("housing_capacity", 0))
	var cell_data: Array = d.get("cell", [0, 0])
	b.cell = Vector2i(int(cell_data[0]), int(cell_data[1]))
	b.production_carry = float(d.get("production_carry", 0.0))
	b.seasonal = _typed_seasonal(d.get("seasonal", {}))
	return b

## JSON liefert String-Schluessel und float-Werte -> nach StringName/int wandeln.
static func _typed_consumes(raw: Dictionary) -> Dictionary:
	var typed: Dictionary = {}
	for key in raw:
		typed[StringName(key)] = int(raw[key])
	return typed

static func _typed_seasonal(raw: Dictionary) -> Dictionary:
	var typed: Dictionary = {}
	for key in raw:
		typed[StringName(key)] = float(raw[key])
	return typed
