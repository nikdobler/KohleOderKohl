extends RefCounted
## Unit-Tests fuer die grenzenlose Noise-Welt (M17, peek_biome/peek_decor).
##
## Kernaussage: ausserhalb der Kartengrenze liefert peek_* exakt das, was eine
## GROESSERE Karte mit demselben Seed dort speichert — die Randlandschaft ist
## also eine nahtlose Fortsetzung derselben Welt. Leere Fehlerliste == bestanden.

const _SEED: int = 4711
const _SMALL: int = 32
const _LARGE: int = 48

func run() -> Array:
	var failures: Array = []
	var small := WorldMap.new()
	small.generate(_SEED, _SMALL, _SMALL, Database.biomes)
	var large := WorldMap.new()
	large.generate(_SEED, _LARGE, _LARGE, Database.biomes)
	_test_inside_passthrough(failures, small)
	_test_seamless_continuation(failures, small, large)
	_test_decor_continuation(failures, small, large)
	return failures

## Innerhalb der Karte ist peek_biome identisch mit get_biome.
func _test_inside_passthrough(failures: Array, small: WorldMap) -> void:
	for cell in [Vector2i(0, 0), Vector2i(5, 17), Vector2i(_SMALL - 1, _SMALL - 1)]:
		if small.peek_biome(cell) != small.get_biome(cell):
			failures.append("Innen: peek_biome muss get_biome entsprechen (%s)" % cell)
		if small.peek_decor(cell) != small.get_decor(cell):
			failures.append("Innen: peek_decor muss get_decor entsprechen (%s)" % cell)

## Ausserhalb der kleinen Karte == gespeicherter Wert der grossen Karte.
func _test_seamless_continuation(failures: Array, small: WorldMap, large: WorldMap) -> void:
	var checked := 0
	for y in range(0, _LARGE, 3):
		for x in range(0, _LARGE, 3):
			var cell := Vector2i(x, y)
			if x < _SMALL and y < _SMALL:
				continue  # nur echtes Aussenland pruefen
			checked += 1
			if small.peek_biome(cell) != large.get_biome(cell):
				failures.append("Naht: Biom bei %s weicht ab" % cell)
				return
	if checked == 0:
		failures.append("Naht: keine Aussenzellen geprueft")
	if small.peek_biome(Vector2i(-9, -4)) == &"":
		failures.append("Naht: negatives Aussenland muss ein Biom liefern")

## Dekor setzt sich fort (vergleichbar nur auf merkmalfreien Zellen der
## grossen Karte — peek kennt draussen keine Merkmale).
func _test_decor_continuation(failures: Array, small: WorldMap, large: WorldMap) -> void:
	for y in range(_SMALL, _LARGE):
		for x in range(_SMALL, _LARGE):
			var cell := Vector2i(x, y)
			if large.get_feature(cell) != &"":
				continue
			if small.peek_decor(cell) != large.get_decor(cell):
				failures.append("Dekor: bei %s weicht ab" % cell)
				return
			return  # ein Treffer genuegt
	failures.append("Dekor: keine merkmalfreie Aussenzelle gefunden")
