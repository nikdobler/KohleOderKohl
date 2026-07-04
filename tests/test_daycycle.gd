extends RefCounted
## Unit-Tests fuer die Tageszeit (M-Tageszeit).
##
## Prueft das Phasen-Mapping (Tick -> Morgen/Tagsueber/Abend/Nacht), den
## Umlauf am Tagesende, den Tagesfortschritt 0..1 und die Anzeigenamen.
## Ticks relativ zu DAY_TICKS, damit ein Laengen-Tuning die Tests nicht bricht.
## Leere Fehlerliste == bestanden.

func run() -> Array:
	var failures: Array = []
	_test_phase_mapping(failures)
	_test_wraps_each_day(failures)
	_test_time_of_day(failures)
	_test_display_names(failures)
	return failures

## Der Tag beginnt am Morgen; jede Phase ist ein Viertel.
func _test_phase_mapping(failures: Array) -> void:
	var d := DayCycle.DAY_TICKS
	var expected := {
		0: &"morning", d / 4: &"day", d / 2: &"evening", 3 * d / 4: &"night",
		d - 1: &"night",
	}
	for tick in expected:
		if DayCycle.phase(tick) != expected[tick]:
			failures.append("Phase: Tick %d erwartet %s, erhalten %s"
				% [tick, expected[tick], DayCycle.phase(tick)])

## Nach einem vollen Tag beginnt der Zyklus wieder am Morgen.
func _test_wraps_each_day(failures: Array) -> void:
	var d := DayCycle.DAY_TICKS
	if DayCycle.phase(d) != &"morning" or DayCycle.phase(3 * d) != &"morning":
		failures.append("Umlauf: Tick %d/%d muessten Morgen sein (%s/%s)"
			% [d, 3 * d, DayCycle.phase(d), DayCycle.phase(3 * d)])

## Tagesfortschritt laeuft 0..1 und springt am Tagesende zurueck.
func _test_time_of_day(failures: Array) -> void:
	var d := DayCycle.DAY_TICKS
	if not is_equal_approx(DayCycle.time_of_day(0), 0.0):
		failures.append("Fortschritt: Tick 0 erwartet 0.0, erhalten %f" % DayCycle.time_of_day(0))
	if not is_equal_approx(DayCycle.time_of_day(d / 2), 0.5):
		failures.append("Fortschritt: halber Tag erwartet 0.5, erhalten %f"
			% DayCycle.time_of_day(d / 2))
	if not is_equal_approx(DayCycle.time_of_day(d), 0.0):
		failures.append("Fortschritt: voller Tag erwartet 0.0 (Umlauf), erhalten %f"
			% DayCycle.time_of_day(d))

## Anzeigenamen sind deutsch.
func _test_display_names(failures: Array) -> void:
	var d := DayCycle.DAY_TICKS
	if DayCycle.display(0) != "Morgen":
		failures.append("Anzeige: Tick 0 erwartet 'Morgen', erhalten '%s'" % DayCycle.display(0))
	if DayCycle.display(d / 2) != "Abend":
		failures.append("Anzeige: halber Tag erwartet 'Abend', erhalten '%s'"
			% DayCycle.display(d / 2))
