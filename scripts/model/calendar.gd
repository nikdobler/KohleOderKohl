class_name Calendar
extends RefCounted
## Calendar — Jahreszeiten aus dem Tick-Zaehler (M-Jahreszeiten, goal §1).
##
## Reine, zustandslose Logik: die Saison ist eine Funktion des Ticks —
## nichts zu speichern, nichts zu synchronisieren (gleiche Eleganz wie die
## Seed-Welt). Ein Jahr sind vier Saisons zu je SEASON_TICKS Ticks, das
## Spiel beginnt im Fruehling von Jahr 1.
##
## Spielwirkung der Saisons liegt DATENGETRIEBEN bei den Gebaeuden
## (buildings.json "seasonal": {Saison -> Produktionsfaktor}, angewandt in
## der Economy) und bei Triggern (TriggerEval-Typ "season").

## Laenge einer Saison in Ticks (1 Tick = 1 Sekunde -> Saison = 15 Minuten,
## Jahr = 1 Stunde; User-Wunsch 2026-07-04: gemaechlicher Jahreslauf).
const SEASON_TICKS: int = 900

## Saisons in Jahresreihenfolge; das Spiel startet im Fruehling.
const SEASONS: Array[StringName] = [&"spring", &"summer", &"autumn", &"winter"]

const _DISPLAY_NAMES: Dictionary = {
	&"spring": "Frühling",
	&"summer": "Sommer",
	&"autumn": "Herbst",
	&"winter": "Winter",
}

## Saison zum Tick (&"spring" ... &"winter").
static func season(tick: int) -> StringName:
	return SEASONS[posmod(int(tick / float(SEASON_TICKS)), SEASONS.size())]

## Jahr zum Tick (beginnt bei 1).
static func year(tick: int) -> int:
	return maxi(0, tick) / (SEASON_TICKS * SEASONS.size()) + 1

## Fortschritt innerhalb der laufenden Saison (0..1).
static func season_progress(tick: int) -> float:
	return posmod(tick, SEASON_TICKS) / float(SEASON_TICKS)

## Deutscher Anzeigename der Saison.
static func season_name(season_id: StringName) -> String:
	return _DISPLAY_NAMES.get(season_id, String(season_id))

## Anzeigetext fuer die UI, z. B. "Herbst, Jahr 2".
static func display(tick: int) -> String:
	return "%s, Jahr %d" % [season_name(season(tick)), year(tick)]

## Tick-Versatz fuer den Beginn einer bestimmten Saison (M-Startsaison):
## Fruehling=0, Sommer=1*SEASON_TICKS, ...  Damit kann ein Szenario direkt
## in einer anderen Saison starten (z. B. Winter -> Felder ruhen ab Tick 0).
## Unbekannte Saison -> Fruehling.
static func season_start_tick(season_id: StringName) -> int:
	var index := SEASONS.find(season_id)
	if index < 0:
		push_warning("Calendar: unbekannte Saison '%s' -> Fruehling." % season_id)
		return 0
	return index * SEASON_TICKS
