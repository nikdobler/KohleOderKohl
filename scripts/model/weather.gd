class_name Weather
extends RefCounted
## Wetter (M-Wetter) — deterministisch aus Welt-Seed + Tick, wie Kalender
## und Welt: nichts zu speichern, Save/Load ergibt automatisch dieselbe
## Wetterlage. Je WEATHER_TICKS-Periode wird einmal gegen die Saison-Gewichte
## aus data/weather.json gewuerfelt (eigener "weather:"-Hash-Salz, gleiches
## Kanal-Muster wie die WorldMap-RNGs).
##
## Spielwirkung liegt datengetrieben bei den Gebaeuden (buildings.json
## "weather": {Wetter -> Produktionsfaktor}, angewandt in der Economy) und
## bei den Wettertypen selbst (weather.json "tower_range_factor" fuer Nebel,
## angewandt im CombatSystem via Controller).

## Dauer einer Wetterlage in Ticks (3 Minuten, "alle paar Minuten" —
## User-Wunsch 2026-07-04). Muss SEASON_TICKS ganzzahlig teilen, damit
## keine Lage einen Saisonwechsel ueberspannt (sonst Herbstregen im
## Winter); der Datencheck in test_weather erzwingt das.
const WEATHER_TICKS: int = 180

const DEFAULT: StringName = &"clear"

var types: Dictionary = {}  # Wetter-ID -> Def (display_name, tower_range_factor, ...)
var season_weights: Dictionary = {}  # Saison-ID -> {Wetter-ID -> Gewicht}

## Uebernimmt Typen und Saison-Gewichte (Inhalt von data/weather.json).
func setup(data: Dictionary) -> void:
	types = {}
	season_weights = {}
	var raw_types: Dictionary = data.get("types", {})
	for key in raw_types:
		types[StringName(key)] = raw_types[key]
	var raw_weights: Dictionary = data.get("season_weights", {})
	for season in raw_weights:
		var typed: Dictionary = {}
		for weather_id in raw_weights[season]:
			typed[StringName(weather_id)] = float(raw_weights[season][weather_id])
		season_weights[StringName(season)] = typed

## Wetterlage zum Tick — reine Funktion aus Welt-Seed + Tick.
func current(world_seed: int, tick: int) -> StringName:
	var weights: Dictionary = season_weights.get(Calendar.season(tick), {})
	if weights.is_empty():
		return DEFAULT
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather:%d:%d" % [world_seed, int(floor(tick / float(WEATHER_TICKS)))])
	var total := 0.0
	for weather_id in weights:
		total += weights[weather_id]
	var roll := rng.randf() * total
	for weather_id in weights:
		roll -= weights[weather_id]
		if roll <= 0.0:
			return weather_id
	return DEFAULT

## Definition eines Wettertyps (leer, falls unbekannt).
func type_def(weather_id: StringName) -> Dictionary:
	return types.get(weather_id, {})

## Deutscher Anzeigename der Wetterlage.
func display_name(weather_id: StringName) -> String:
	return String(type_def(weather_id).get("display_name", String(weather_id)))
