extends Node2D
## Main — leere Startszene (M0).
##
## Einstiegspunkt des Spiels. In M0 ohne Spiellogik: bestaetigt lediglich,
## dass Projekt und Autoloads sauber hochfahren.

func _ready() -> void:
	print("Krone und Kohl — Boot ok. Speicherformat-Version: %d" % SaveManager.SAVE_VERSION)
