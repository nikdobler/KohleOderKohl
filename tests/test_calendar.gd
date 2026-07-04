extends RefCounted
## Unit-Tests fuer die Jahreszeiten (M-Jahreszeiten).
##
## Prueft das Kalender-Mapping (Tick -> Saison/Jahr/Fortschritt/Anzeige)
## und die Saison-Wirkung in der Economy (Winterruhe ohne Verbrauch,
## Herbst-Boost, halbe Winterleistung, Roundtrip der seasonal-Faktoren).
## Leere Fehlerliste == bestanden.

func run() -> Array:
	var failures: Array = []
	_test_season_mapping(failures)
	_test_year_and_progress(failures)
	_test_display(failures)
	_test_winter_stops_field(failures)
	_test_winter_pause_skips_consumption(failures)
	_test_autumn_boosts_field(failures)
	_test_winter_halves_livestock(failures)
	_test_seasonal_roundtrip(failures)
	return failures

## Weizenfeld-Testgebaeude mit den echten Saison-Faktoren aus buildings.json.
func _make_field() -> BuildingInstance:
	return BuildingInstance.from_def({
		"id": "wheat_farm",
		"produces": "wheat",
		"production_per_tick": 2,
		"max_workers": 2,
		"seasonal": {"spring": 1.25, "autumn": 1.5, "winter": 0.0},
	})

## Saisonfolge: Fruehling -> Sommer -> Herbst -> Winter -> wieder Fruehling.
## Ticks relativ zu SEASON_TICKS, damit Laengen-Tuning die Tests nicht bricht.
func _test_season_mapping(failures: Array) -> void:
	var s := Calendar.SEASON_TICKS
	var expected := {
		0: &"spring", s - 1: &"spring",
		s: &"summer", 2 * s: &"autumn", 3 * s: &"winter",
		4 * s: &"spring", 5 * s: &"summer",
	}
	for tick in expected:
		if Calendar.season(tick) != expected[tick]:
			failures.append("Saison: Tick %d erwartet %s, erhalten %s"
				% [tick, expected[tick], Calendar.season(tick)])

## Jahr beginnt bei 1 und wechselt nach 4 Saisons; Fortschritt laeuft 0..1.
func _test_year_and_progress(failures: Array) -> void:
	var s := Calendar.SEASON_TICKS
	if Calendar.year(0) != 1 or Calendar.year(4 * s - 1) != 1 or Calendar.year(4 * s) != 2:
		failures.append("Jahr: erwartet 1/1/2, erhalten %d/%d/%d"
			% [Calendar.year(0), Calendar.year(4 * s - 1), Calendar.year(4 * s)])
	if not is_equal_approx(Calendar.season_progress(s / 2), 0.5):
		failures.append("Fortschritt: halbe Saison erwartet 0.5, erhalten %f"
			% Calendar.season_progress(s / 2))

## Anzeigetext ist deutsch und traegt das Jahr.
func _test_display(failures: Array) -> void:
	if Calendar.display(0) != "Frühling, Jahr 1":
		failures.append("Anzeige: Tick 0 erwartet 'Frühling, Jahr 1', erhalten '%s'"
			% Calendar.display(0))
	if Calendar.display(5 * Calendar.SEASON_TICKS) != "Sommer, Jahr 2":
		failures.append("Anzeige: Sommer Jahr 2 erwartet, erhalten '%s'"
			% Calendar.display(5 * Calendar.SEASON_TICKS))

## Winter (Faktor 0) stoppt das Feld komplett.
func _test_winter_stops_field(failures: Array) -> void:
	var eco := Economy.new()
	eco.tick_count = 3 * Calendar.SEASON_TICKS - 1  # naechster Tick = erster Wintertick
	var field := _make_field()
	field.set_workers(1)
	eco.add_building(field)
	eco.tick()
	if eco.get_stock(&"wheat") != 0:
		failures.append("Winterruhe: erwartet 0 Weizen, erhalten %d" % eco.get_stock(&"wheat"))

## Saisonpause verschwendet keine Eingangsressourcen (return VOR dem Verbrauch).
func _test_winter_pause_skips_consumption(failures: Array) -> void:
	var eco := Economy.new()
	eco.tick_count = 3 * Calendar.SEASON_TICKS - 1
	var press := BuildingInstance.from_def({
		"id": "winery",
		"produces": "wine",
		"production_per_tick": 1,
		"max_workers": 1,
		"consumes": {"grapes": 2},
		"seasonal": {"winter": 0.0},
	})
	press.set_workers(1)
	eco.add_building(press)
	eco.stock[&"grapes"] = 10
	eco.tick()
	if eco.get_stock(&"grapes") != 10 or eco.get_stock(&"wine") != 0:
		failures.append("Winterpause: Verbrauch trotz Pause (Trauben %d, Wein %d)"
			% [eco.get_stock(&"grapes"), eco.get_stock(&"wine")])

## Herbst-Faktor 1.5 hebt die Ausbeute (2 -> 3 je Tick).
func _test_autumn_boosts_field(failures: Array) -> void:
	var eco := Economy.new()
	eco.tick_count = 2 * Calendar.SEASON_TICKS - 1  # naechster Tick = erster Herbsttick
	var field := _make_field()
	field.set_workers(1)
	eco.add_building(field)
	eco.tick()
	if eco.get_stock(&"wheat") != 3:
		failures.append("Herbst: erwartet 3 Weizen, erhalten %d" % eco.get_stock(&"wheat"))

## Winter-Faktor 0.5 halbiert Viehwirtschaft (Bruchteile sammeln sich im Carry).
func _test_winter_halves_livestock(failures: Array) -> void:
	var eco := Economy.new()
	# Die beiden Folgeticks liegen im Winter, sind aber keine Fuetterungs-
	# Ticks (Vielfache von 10) — die Laune bleibt stabil bei Produktivitaet 1.
	eco.tick_count = 3 * Calendar.SEASON_TICKS
	var farm := BuildingInstance.from_def({
		"id": "pig_farm",
		"produces": "pig",
		"production_per_tick": 1,
		"max_workers": 2,
		"seasonal": {"winter": 0.5},
	})
	farm.set_workers(1)
	eco.add_building(farm)
	eco.tick()
	eco.tick()
	if eco.get_stock(&"pig") != 1:
		failures.append("Winterhalb: erwartet 1 Schwein nach 2 Ticks, erhalten %d"
			% eco.get_stock(&"pig"))

## seasonal ueberlebt Speichern/Laden der Gebaeude-Instanz.
func _test_seasonal_roundtrip(failures: Array) -> void:
	var restored := BuildingInstance.from_dict(_make_field().to_dict())
	if not is_equal_approx(restored.season_factor(&"autumn"), 1.5) \
			or not is_equal_approx(restored.season_factor(&"winter"), 0.0) \
			or not is_equal_approx(restored.season_factor(&"summer"), 1.0):
		failures.append("Roundtrip: seasonal-Faktoren nach Laden falsch (%s)"
			% str(restored.seasonal))
