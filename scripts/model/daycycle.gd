class_name DayCycle
extends RefCounted
## DayCycle — Tageszeit aus dem Tick-Zaehler (M-Tageszeit).
##
## Reine, zustandslose Logik wie [Calendar] und [Weather]: die Tageszeit ist
## eine Funktion des Ticks — nichts zu speichern. Ein voller Tag dauert
## DAY_TICKS Ticks und beginnt am Morgen; die vier Phasen (Morgen, Tagsueber,
## Abend, Nacht) sind je ein Viertel.
##
## Der Tag hat KEINE Spielwirkung — er ist rein optisch (Licht-/Farbverlauf in
## der WorldView, gespeist aus [method time_of_day]). Die Ablaufgeschwindigkeit
## steuert der Spieler ueber den Zeit-Regler, der den Haupt-Tick skaliert
## (GameController) — hier steht nichts davon, weil der Tick selbst schneller
## laeuft.

## Laenge eines vollen Tages in Ticks (bei 1x = 1 Tick/Sekunde -> 2 Minuten).
const DAY_TICKS: int = 120

## Phasen in Tagesreihenfolge; der Tag (und das Spiel) beginnt am Morgen.
const PHASES: Array[StringName] = [&"morning", &"day", &"evening", &"night"]

const _DISPLAY_NAMES: Dictionary = {
	&"morning": "Morgen",
	&"day": "Tagsüber",
	&"evening": "Abend",
	&"night": "Nacht",
}

## Tageszeit als Bruchteil 0..1 (0 = Morgenbeginn, 0.5 = Abendbeginn).
static func time_of_day(tick: int) -> float:
	return posmod(tick, DAY_TICKS) / float(DAY_TICKS)

## Tagesphase zum Tick (&"morning" ... &"night").
static func phase(tick: int) -> StringName:
	return PHASES[int(time_of_day(tick) * PHASES.size())]

## Deutscher Anzeigename der Phase.
static func phase_name(phase_id: StringName) -> String:
	return _DISPLAY_NAMES.get(phase_id, String(phase_id))

## Anzeigetext fuer die UI (der Phasenname, z. B. "Abend").
static func display(tick: int) -> String:
	return phase_name(phase(tick))
