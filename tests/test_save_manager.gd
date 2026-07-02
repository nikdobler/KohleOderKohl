extends RefCounted
## Unit-Tests fuer den SaveManager (M0).
##
## Bewusst ohne externe Abhaengigkeit (kein GUT): einfache Methoden, die
## eine Liste von Fehlermeldungen zurueckgeben. Leere Liste == bestanden.
## Aufgerufen vom test_runner.gd.

const _TEST_PATH: String = "user://test_savegame.json"

## Fuehrt alle Tests aus. Rueckgabe: Array[String] mit Fehlern (leer == ok).
func run() -> Array:
	var failures: Array = []
	_test_save_and_load_roundtrip(failures)
	_test_numbers_roundtrip_as_float(failures)
	_test_load_missing_returns_empty(failures)
	_test_version_is_written(failures)
	_cleanup()
	return failures

## JSON-stabile Daten (Strings, Bools, verschachtelt) muessen unveraendert
## wieder geladen werden.
func _test_save_and_load_roundtrip(failures: Array) -> void:
	var original := {
		"stadt": "Kohlheim",
		"gegruendet": true,
		"vogt": {"name": "Griesgram", "geizig": true},
	}
	var err := SaveManager.save_game(original, _TEST_PATH)
	if err != OK:
		failures.append("Roundtrip: save_game lieferte Fehlercode %d" % err)
		return
	var loaded := SaveManager.load_game(_TEST_PATH)
	if loaded != original:
		failures.append("Roundtrip: geladene Daten weichen ab: %s" % str(loaded))

## Dokumentiert bewusst das JSON-Verhalten: Zahlen kommen als float zurueck
## (42 -> 42.0). Typisierte Rueck-Konvertierung ist Aufgabe der Domaenen-
## schicht (GameState) in spaeteren Meilensteinen, nicht des SaveManagers.
func _test_numbers_roundtrip_as_float(failures: Array) -> void:
	SaveManager.save_game({"gold": 42}, _TEST_PATH)
	var loaded := SaveManager.load_game(_TEST_PATH)
	var gold: Variant = loaded.get("gold")
	if typeof(gold) != TYPE_FLOAT or gold != 42.0:
		failures.append("NumberFloat: erwartet float 42.0, erhalten %s (%d)" % [str(gold), typeof(gold)])

## Fehlende Datei darf kein harter Fehler sein, sondern liefert {}.
func _test_load_missing_returns_empty(failures: Array) -> void:
	var loaded := SaveManager.load_game("user://gibt_es_nicht_12345.json")
	if loaded != {}:
		failures.append("MissingFile: erwartet {}, erhalten %s" % str(loaded))

## Die Datei muss die aktuelle save_version enthalten.
func _test_version_is_written(failures: Array) -> void:
	SaveManager.save_game({"x": 1}, _TEST_PATH)
	var file := FileAccess.open(_TEST_PATH, FileAccess.READ)
	if file == null:
		failures.append("Version: Testdatei nicht lesbar")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("save_version", -1)) != SaveManager.SAVE_VERSION:
		failures.append("Version: save_version fehlt oder falsch")

func _cleanup() -> void:
	if FileAccess.file_exists(_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_PATH))
