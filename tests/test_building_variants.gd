extends RefCounted
## Unit-Tests fuer die Gebaeude-Stilvarianten (M-Gebaeudevarianten).
##
## Prueft deterministische, je Instanz stabile Auswahl, den Basis-Fallback und
## die Daten-Konsistenz von data/settlement_types.json. Leere Liste == bestanden.

const _DEFS := {
	"default": "heartland",
	"types": {
		"heartland": {"building_variants": {
			"house": ["a", "b", "c"],
			"bakery": ["x"],
		}},
	},
}

func run() -> Array:
	var failures: Array = []
	_test_deterministic(failures)
	_test_stable_per_instance(failures)
	_test_base_when_no_variants(failures)
	_test_single_variant_hit(failures)
	_test_data_consistency(failures)
	return failures

## Gleiche Eingaben -> gleiche Variante.
func _test_deterministic(failures: Array) -> void:
	var a := BuildingVariants.pick(&"house", 5, &"heartland", _DEFS, 1234)
	var b := BuildingVariants.pick(&"house", 5, &"heartland", _DEFS, 1234)
	if a != b:
		failures.append("Determinismus: gleiche Eingaben liefern '%s' vs '%s'" % [a, b])

## Je Instanz stabil; ueber viele Instanzen kommen mehrere Varianten vor
## (sonst waere die Verteilung kaputt).
func _test_stable_per_instance(failures: Array) -> void:
	var seen: Dictionary = {}
	for id in range(1, 40):
		var v := BuildingVariants.pick(&"house", id, &"heartland", _DEFS, 7)
		if not ["a", "b", "c"].has(String(v)):
			failures.append("Instanz: unerwartete Variante '%s'" % v)
			return
		seen[String(v)] = true
	if seen.size() < 2:
		failures.append("Instanz: ueber 39 Gebaeude nur %d Variante(n)" % seen.size())

## Unbekannter Siedlungstyp oder Gebaeude ohne Varianten -> Basis (&"").
func _test_base_when_no_variants(failures: Array) -> void:
	if BuildingVariants.pick(&"house", 1, &"nirgendwo", _DEFS, 1) != &"":
		failures.append("Basis: unbekannter Siedlungstyp muss Basis liefern")
	if BuildingVariants.pick(&"keep", 1, &"heartland", _DEFS, 1) != &"":
		failures.append("Basis: Gebaeude ohne Varianten muss Basis liefern")

## Eine einzige Variante wird immer getroffen.
func _test_single_variant_hit(failures: Array) -> void:
	if BuildingVariants.pick(&"bakery", 99, &"heartland", _DEFS, 3) != &"x":
		failures.append("Liste: einzige Variante 'x' muss getroffen werden")

## data/settlement_types.json: default ist definiert, alle Varianten-Gebaeude
## existieren in buildings.json, keine leeren Listen.
func _test_data_consistency(failures: Array) -> void:
	var defs: Dictionary = Database.settlement_types
	if defs.is_empty():
		failures.append("Daten: settlement_types.json fehlt oder ist leer")
		return
	var types: Dictionary = defs.get("types", {})
	if not types.has(String(defs.get("default", ""))):
		failures.append("Daten: default '%s' ist kein definierter Typ" % defs.get("default", ""))
	for type_id in types:
		var by_building: Dictionary = types[type_id].get("building_variants", {})
		for def_id in by_building:
			if not Database.buildings.has(def_id):
				failures.append("Daten: Varianten-Gebaeude '%s' fehlt in buildings.json (%s)"
					% [def_id, type_id])
			var list: Array = by_building[def_id]
			if list.is_empty():
				failures.append("Daten: leere Variantenliste fuer '%s' (%s)" % [def_id, type_id])
