extends Node
## SaveManager — Grundgeruest des Speichersystems (M0).
##
## JSON-basiert, versioniert ueber [member SAVE_VERSION].
## Enthaelt bewusst KEINE Spiellogik: reines Serialisieren/Deserialisieren
## eines beliebigen Dictionaries plus ein Migrationsgeruest fuer
## Vorwaertskompatibilitaet aelterer Spielstaende.
##
## [b]Wichtig:[/b] JSON kennt nur einen Zahlentyp — ganze Zahlen kommen beim
## Laden als float zurueck (42 -> 42.0). Der SaveManager kennt das Schema
## nicht und konvertiert bewusst nicht zurueck. Typisiertes Einlesen ist
## Aufgabe der Domaenenschicht (GameState) in spaeteren Meilensteinen.

## Aktuelle Speicherformat-Version. Bei inkompatiblen Aenderungen erhoehen
## und einen Migrationsschritt in [method _migrate] ergaenzen.
## v2: Gebaeude tragen stabile Instanz-IDs (economy.buildings[].id +
## economy.next_building_id).
const SAVE_VERSION: int = 2

## Standard-Speicherpfad (Godot user://-Verzeichnis, plattformunabhaengig).
const DEFAULT_SAVE_PATH: String = "user://savegame.json"

## Speichert [param data] als versionierte JSON-Datei.
## Gibt [constant OK] zurueck oder einen Fehlercode.
func save_game(data: Dictionary, path: String = DEFAULT_SAVE_PATH) -> Error:
	var payload := {
		"save_version": SAVE_VERSION,
		"data": data,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Datei nicht schreibbar: %s" % path)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK

## Laedt einen Spielstand und liefert das enthaltene Daten-Dictionary.
## Migriert aeltere Versionen automatisch. Bei fehlender/kaputter Datei
## wird ein leeres Dictionary zurueckgegeben (kein harter Fehler).
func load_game(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Datei nicht lesbar: %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: Ungueltiges Speicherformat in %s" % path)
		return {}

	var payload: Dictionary = parsed
	var version: int = int(payload.get("save_version", 0))
	var data: Dictionary = payload.get("data", {})
	return _migrate(data, version)

## Existiert ein Spielstand unter [param path]?
func has_save(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## Vorwaertskompatibilitaet: hebt Daten von [param from_version] auf
## [constant SAVE_VERSION]. Aktuell keine Migration noetig; jeder kuenftige
## Formatwechsel bekommt hier einen eigenen, klar benannten Schritt.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	if from_version > SAVE_VERSION:
		push_warning("SaveManager: Spielstand-Version %d ist neuer als unterstuetzt (%d)." % [from_version, SAVE_VERSION])
	while from_version < SAVE_VERSION:
		match from_version:
			1: data = _migrate_1_to_2(data)
		from_version += 1
	return data

## v1 -> v2: Gebaeude ohne Instanz-ID bekommen fortlaufende IDs (1..N in
## Listenreihenfolge), der Zaehler wird dahinter gesetzt. Danach identisch zu
## einem regulaer gespeicherten v2-Stand.
func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	var economy: Dictionary = data.get("economy", {})
	var buildings: Array = economy.get("buildings", [])
	var next_id: int = 1
	for building in buildings:
		if not building.has("id") or int(building.get("id", 0)) == 0:
			building["id"] = next_id
		next_id = maxi(next_id, int(building["id"]) + 1)
	economy["next_building_id"] = next_id
	return data
