extends Node
## GameState — zentraler, noch leerer Datenbehaelter (M0).
##
## Haelt spaeter den serialisierbaren Spielzustand (Ressourcen, Gebaeude,
## Arbeiter ...). In M0 bewusst ohne Spiellogik: nur ein Dictionary plus
## Konvertierung fuer das Speichersystem.

## Roher Spielzustand. Wird in spaeteren Meilensteinen strukturiert befuellt.
var data: Dictionary = {}

## Serialisiert den Zustand fuer den SaveManager.
func to_dict() -> Dictionary:
	return data.duplicate(true)

## Uebernimmt einen geladenen Zustand aus dem SaveManager.
func from_dict(loaded: Dictionary) -> void:
	data = loaded.duplicate(true)

## Setzt den Zustand auf leer zurueck (neues Spiel).
func reset() -> void:
	data = {}
