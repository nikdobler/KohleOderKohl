extends RefCounted
## Unit-Tests fuer das Wetter (M-Wetter).
##
## Prueft das deterministische Perioden-Wetter (Seed+Tick), Saison-
## Konsistenz (kein Regen im Winter, kein Schnee im Sommer), den
## Regen-Bonus in der Economy, die Nebel-Reichweite der Tuerme und die
## Daten-Konsistenz von data/weather.json. Leere Fehlerliste == bestanden.

const _DATA := {
	"types": {
		"clear": {"display_name": "Klar"},
		"rain": {"display_name": "Regen"},
		"fog": {"display_name": "Nebel", "tower_range_factor": 0.5},
		"snow": {"display_name": "Schneefall"},
	},
	"season_weights": {
		"spring": {"clear": 5, "rain": 3, "fog": 2},
		"summer": {"clear": 7, "rain": 2, "fog": 1},
		"autumn": {"clear": 4, "rain": 3, "fog": 3},
		"winter": {"clear": 5, "snow": 4, "fog": 1},
	},
}

const _UNIT_DEFS := {
	"raider": {"hp": 100, "attack": 4, "defense": 1, "speed": 1},
}

func run() -> Array:
	var failures: Array = []
	_test_deterministic(failures)
	_test_stable_within_period(failures)
	_test_season_consistency(failures)
	_test_rain_boosts_production(failures)
	_test_fog_halves_tower_range(failures)
	_test_weather_roundtrip(failures)
	_test_data_consistency(failures)
	return failures

func _make_weather() -> Weather:
	var weather := Weather.new()
	weather.setup(_DATA)
	return weather

## Gleicher Seed + Tick -> gleiche Wetterlage, auch ueber Instanzen hinweg.
func _test_deterministic(failures: Array) -> void:
	var a := _make_weather()
	var b := _make_weather()
	for tick in [0, 30, 500, 3000]:
		var got := a.current(1234, tick)
		if got != b.current(1234, tick):
			failures.append("Determinismus: Tick %d weicht zwischen Instanzen ab" % tick)
		if not _DATA["types"].has(String(got)):
			failures.append("Determinismus: unbekannte Wetterlage '%s'" % got)

## Innerhalb einer Wetterperiode aendert sich das Wetter nicht.
func _test_stable_within_period(failures: Array) -> void:
	var weather := _make_weather()
	var first := weather.current(42, 0)
	for tick in range(Weather.WEATHER_TICKS):
		if weather.current(42, tick) != first:
			failures.append("Periode: Tick %d weicht von Tick 0 ab" % tick)
			return

## Saison-Gewichte greifen: nie Regen im Winter, nie Schnee im Sommer.
func _test_season_consistency(failures: Array) -> void:
	var weather := _make_weather()
	for world_seed in range(50):
		for period_start in [270, 300, 330]:  # Winter von Jahr 1
			if weather.current(world_seed, period_start) == &"rain":
				failures.append("Saison: Regen im Winter (Seed %d)" % world_seed)
				return
		for period_start in [90, 120, 150]:  # Sommer von Jahr 1
			if weather.current(world_seed, period_start) == &"snow":
				failures.append("Saison: Schnee im Sommer (Seed %d)" % world_seed)
				return

## Regen-Faktor hebt die Ausbeute (Faktor 1.5: 2 -> 3 je Tick).
func _test_rain_boosts_production(failures: Array) -> void:
	var eco := Economy.new()
	var field := BuildingInstance.from_def({
		"id": "wheat_farm",
		"produces": "wheat",
		"production_per_tick": 2,
		"max_workers": 2,
		"weather": {"rain": 1.5},
	})
	field.set_workers(1)
	eco.add_building(field)
	eco.current_weather = &"rain"
	eco.tick()
	if eco.get_stock(&"wheat") != 3:
		failures.append("Regen: erwartet 3 Weizen, erhalten %d" % eco.get_stock(&"wheat"))
	var dry := Economy.new()
	var dry_field := BuildingInstance.from_def({
		"id": "wheat_farm",
		"produces": "wheat",
		"production_per_tick": 2,
		"max_workers": 2,
		"weather": {"rain": 1.5},
	})
	dry_field.set_workers(1)
	dry.add_building(dry_field)
	dry.tick()  # current_weather bleibt "clear"
	if dry.get_stock(&"wheat") != 2:
		failures.append("Klar: erwartet 2 Weizen, erhalten %d" % dry.get_stock(&"wheat"))

## Nebel halbiert die Turm-Reichweite: Distanz 3 wird mit Faktor 0.5 nicht
## mehr erreicht (Reichweite 4 -> 2), ohne Nebel schon.
func _test_fog_halves_tower_range(failures: Array) -> void:
	var clear_combat := _make_combat_with_tower()
	clear_combat.tick()
	var clear_hp: int = clear_combat.units[0].hp
	if clear_hp >= 100:
		failures.append("Nebel: Turm muss ohne Nebel treffen (HP %d)" % clear_hp)
	var foggy := _make_combat_with_tower()
	foggy.tower_range_factor = 0.5
	foggy.tick()
	var foggy_hp: int = foggy.units[0].hp
	if foggy_hp != 100:
		failures.append("Nebel: Turm darf im Nebel nicht treffen (HP %d)" % foggy_hp)

## Turm (Reichweite 4) auf (5,5), Feind-Wache in Distanz 3 auf (8,8).
func _make_combat_with_tower() -> CombatSystem:
	var combat := CombatSystem.new()
	combat.setup(_UNIT_DEFS,
		{"cell": Vector2i(0, 0), "hp": 100},
		{"cell": Vector2i(20, 20), "hp": 100},
		{"unit": "raider", "defenders": 0, "wave_interval_ticks": 0, "wave_size": 0}, 42)
	combat.add_obstacle(Vector2i(5, 5), &"tower", 150, false, 5, 4)
	combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(8, 8), CombatSystem.STANCE_GUARD, Vector2i(8, 8))
	return combat

## weather-Faktoren ueberleben Speichern/Laden der Gebaeude-Instanz.
func _test_weather_roundtrip(failures: Array) -> void:
	var field := BuildingInstance.from_def({
		"id": "wheat_farm",
		"produces": "wheat",
		"production_per_tick": 2,
		"max_workers": 2,
		"weather": {"rain": 1.15},
	})
	var restored := BuildingInstance.from_dict(field.to_dict())
	if not is_equal_approx(restored.weather_factor(&"rain"), 1.15) \
			or not is_equal_approx(restored.weather_factor(&"fog"), 1.0):
		failures.append("Roundtrip: weather-Faktoren nach Laden falsch (%s)"
			% str(restored.weather))

## data/weather.json passt zu Kalender und buildings.json.
func _test_data_consistency(failures: Array) -> void:
	var data: Dictionary = Database.weather
	if data.is_empty():
		failures.append("Daten: data/weather.json fehlt oder ist leer")
		return
	var types: Dictionary = data.get("types", {})
	var weights: Dictionary = data.get("season_weights", {})
	for season in Calendar.SEASONS:
		if not weights.has(String(season)):
			failures.append("Daten: Saison '%s' ohne Wetter-Gewichte" % season)
			continue
		for weather_id in weights[String(season)]:
			if not types.has(weather_id):
				failures.append("Daten: Gewicht fuer unbekannten Typ '%s'" % weather_id)
	if weights.get("winter", {}).has("rain"):
		failures.append("Daten: Winter darf keinen Regen kennen (Schnee statt Regen)")
	for building_id in Database.buildings:
		for weather_id in Database.buildings[building_id].get("weather", {}):
			if not types.has(weather_id):
				failures.append("Daten: buildings.json '%s' nutzt unbekanntes Wetter '%s'"
					% [building_id, weather_id])
