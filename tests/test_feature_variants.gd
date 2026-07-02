extends RefCounted
## Unit-Tests fuer den visuellen Varianten-Wähler (§8.2).
##
## Prueft Determinismus, Gueltigkeit (Variante stammt aus der Tabelle), den
## Durchgriff bei fehlender Tabelle und dass ueber viele Zellen mehrere Varianten
## vorkommen. Nutzt Database.feature_variants.

const _SEED: int = 1234

func run() -> Array:
	var failures: Array = []
	_test_deterministic(failures)
	_test_variant_is_valid(failures)
	_test_passthrough_without_table(failures)
	_test_distribution(failures)
	return failures

## Gleiche Zelle + gleicher Seed -> gleiche Variante.
func _test_deterministic(failures: Array) -> void:
	var cell := Vector2i(7, 3)
	var a := FeatureVariants.pick(&"rock", cell, Database.feature_variants, _SEED)
	var b := FeatureVariants.pick(&"rock", cell, Database.feature_variants, _SEED)
	if a != b:
		failures.append("Variante: nicht deterministisch (%s vs %s)" % [a, b])

## Die gewaehlte Variante steht in der Tabelle des Merkmals.
func _test_variant_is_valid(failures: Array) -> void:
	var allowed: Array = Database.feature_variants.get("rock", [])
	if allowed.is_empty():
		failures.append("Variante: 'rock' fehlt in feature_variants.json")
		return
	for i in 50:
		var v := FeatureVariants.pick(&"rock", Vector2i(i, i * 2), Database.feature_variants, _SEED)
		if not allowed.has(String(v)):
			failures.append("Variante: %s nicht in rock-Tabelle" % v)
			return

## Merkmal ohne Tabelleneintrag liefert sich selbst zurueck (unveraendert).
func _test_passthrough_without_table(failures: Array) -> void:
	var v := FeatureVariants.pick(&"tree", Vector2i(1, 1), Database.feature_variants, _SEED)
	if v != &"tree":
		failures.append("Variante: Merkmal ohne Tabelle muss unveraendert bleiben (erhielt %s)" % v)

## Ueber viele Zellen tauchen mehrere Varianten auf (kein konstanter Wert).
func _test_distribution(failures: Array) -> void:
	if Database.feature_variants.get("rock", []).size() < 2:
		return  # nichts zu streuen
	var seen := {}
	for i in 200:
		seen[FeatureVariants.pick(&"rock", Vector2i(i, 500 - i), Database.feature_variants, _SEED)] = true
	if seen.size() < 2:
		failures.append("Variante: erwartet mehrere rock-Varianten, sah nur %d" % seen.size())
