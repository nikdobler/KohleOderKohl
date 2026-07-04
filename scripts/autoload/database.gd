extends Node
## Database — zentrales Register fuer datengetriebene Definitionen (M1).
##
## Laedt Ressourcen- und Gebaeude-Definitionen aus /data/*.json, damit Werte
## nicht im Skript hartcodiert sind (siehe goal, Abschnitt 2). Schluessel in
## den JSON-Dateien sind Strings; Zugriff erfolgt bequem per StringName.

const RESOURCES_PATH: String = "res://data/resources.json"
const BUILDINGS_PATH: String = "res://data/buildings.json"
const TECH_PATH: String = "res://data/tech.json"
const BIOMES_PATH: String = "res://data/biomes.json"
const FEATURE_VARIANTS_PATH: String = "res://data/feature_variants.json"
const UNITS_PATH: String = "res://data/units.json"
const ANIMALS_PATH: String = "res://data/animals.json"
const ENEMY_PATH: String = "res://data/enemy.json"
const CAMPAIGN_PATH: String = "res://data/campaign.json"
const WEATHER_PATH: String = "res://data/weather.json"
const DIALOGUES_DIR: String = "res://data/dialogues"
const SCENARIOS_DIR: String = "res://data/scenarios"

var resources: Dictionary = {}
var buildings: Dictionary = {}
var techs: Dictionary = {}
var biomes: Dictionary = {}
var feature_variants: Dictionary = {}  # Merkmal-ID -> [visuelle Varianten-IDs]
var units: Dictionary = {}
var animals: Dictionary = {}
var enemy: Dictionary = {}
var campaign: Dictionary = {}  # Kapitelfolge der Hauptstory (M14)
var weather: Dictionary = {}  # Wettertypen + Saison-Gewichte (M-Wetter)
var dialogues: Dictionary = {}  # npc_id -> kompletter Datei-Inhalt
var scenarios: Dictionary = {}  # szenario_id -> kompletter Datei-Inhalt

func _ready() -> void:
	resources = _load_json(RESOURCES_PATH)
	buildings = _load_json(BUILDINGS_PATH)
	techs = _load_json(TECH_PATH)
	biomes = _load_json(BIOMES_PATH)
	feature_variants = _load_json(FEATURE_VARIANTS_PATH)
	units = _load_json(UNITS_PATH)
	animals = _load_json(ANIMALS_PATH)
	enemy = _load_json(ENEMY_PATH)
	campaign = _load_json(CAMPAIGN_PATH)
	weather = _load_json(WEATHER_PATH)
	dialogues = _load_json_dir(DIALOGUES_DIR, func(def: Dictionary) -> String:
		return def.get("npc", {}).get("id", ""))
	scenarios = _load_json_dir(SCENARIOS_DIR, func(def: Dictionary) -> String:
		return def.get("id", ""))

## Laedt alle JSON-Dateien eines Ordners; [param key_of] liefert den
## Dictionary-Schluessel je Datei (leer == Fehler, Datei wird uebersprungen).
func _load_json_dir(path: String, key_of: Callable) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Database: Ordner fehlt: %s" % path)
		return result
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var def := _load_json("%s/%s" % [path, file])
		var key: String = key_of.call(def)
		if key.is_empty():
			push_error("Database: Datei ohne ID: %s/%s" % [path, file])
			continue
		result[key] = def
	return result

## Definition einer Ressource (leeres Dictionary, falls unbekannt).
func get_resource_def(id: StringName) -> Dictionary:
	return resources.get(String(id), {})

## Definition eines Gebaeudes (leeres Dictionary, falls unbekannt).
func get_building_def(id: StringName) -> Dictionary:
	return buildings.get(String(id), {})

## Definition einer Technologie (leeres Dictionary, falls unbekannt).
func get_tech_def(id: StringName) -> Dictionary:
	return techs.get(String(id), {})

## Definition einer Einheit (leeres Dictionary, falls unbekannt).
func get_unit_def(id: StringName) -> Dictionary:
	return units.get(String(id), {})

## Definition eines Tiers (leeres Dictionary, falls unbekannt).
func get_animal_def(id: StringName) -> Dictionary:
	return animals.get(String(id), {})

## Laedt eine JSON-Datei als Dictionary. Fehler werden gemeldet, aber nicht
## hart geworfen — es kommt ein leeres Dictionary zurueck.
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Database: Datei fehlt: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Database: Datei nicht lesbar: %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Database: Ungueltiges JSON in %s" % path)
		return {}
	return parsed
