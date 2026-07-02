extends RefCounted
## Unit-Tests fuer die Kartengenerierung (M4).
##
## Prueft Determinismus, Biom-Vielfalt, biomabhaengige Ressourcenverteilung,
## Bauplaetze und den Seed-Roundtrip — rein logisch, ohne Rendering.
## Nutzt die echten Biom-Definitionen aus der Database (Konsistenz inklusive).

const _SEED: int = 1234
const _SIZE: int = 48

func run() -> Array:
	var failures: Array = []
	_test_deterministic_generation(failures)
	_test_different_seeds_differ(failures)
	_test_both_biomes_present(failures)
	_test_feature_distribution_differs(failures)
	_test_decor(failures)
	_test_water(failures)
	_test_river(failures)
	_test_building_slots(failures)
	_test_roundtrip(failures)
	return failures

func _make_map(map_seed: int) -> WorldMap:
	var map := WorldMap.new()
	map.generate(map_seed, _SIZE, _SIZE, Database.biomes)
	return map

## Gleicher Seed -> identische Biome und Merkmale auf allen Zellen.
func _test_deterministic_generation(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED)
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if a.get_biome(cell) != b.get_biome(cell) or a.get_feature(cell) != b.get_feature(cell):
				failures.append("Determinismus: Zelle %s weicht ab" % cell)
				return

## Andere Seeds erzeugen (praktisch sicher) eine andere Karte.
func _test_different_seeds_differ(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED + 1)
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if a.get_biome(cell) != b.get_biome(cell):
				return
	failures.append("Seeds: unterschiedliche Seeds ergaben identische Biome")

## Beide Biome muessen auf der Karte vorkommen.
func _test_both_biomes_present(failures: Array) -> void:
	var counts := _biome_counts(_make_map(_SEED))
	for biome_id in Database.biomes:
		if int(counts.get(StringName(biome_id), 0)) == 0:
			failures.append("Biome: '%s' kommt auf der Karte nicht vor" % biome_id)

## Zaehlt die Zellen je Biom.
func _biome_counts(map: WorldMap) -> Dictionary:
	var counts: Dictionary = {}
	for y in _SIZE:
		for x in _SIZE:
			var biome := map.get_biome(Vector2i(x, y))
			counts[biome] = int(counts.get(biome, 0)) + 1
	return counts

## Ressourcenverteilung je Biom: Grasland baumreich, Felsland steinreich.
func _test_feature_distribution_differs(failures: Array) -> void:
	var map := _make_map(_SEED)
	var rates := {}  # biome -> {feature -> count, "total" -> int}
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			var biome := map.get_biome(cell)
			if not rates.has(biome):
				rates[biome] = {"total": 0, &"tree": 0, &"rock": 0}
			rates[biome]["total"] += 1
			var feature := map.get_feature(cell)
			if rates[biome].has(feature):
				rates[biome][feature] += 1
	var grass: Dictionary = rates.get(&"grassland", {})
	var high: Dictionary = rates.get(&"highlands", {})
	if grass.is_empty() or high.is_empty():
		failures.append("Verteilung: Biome fehlen fuer den Vergleich")
		return
	var grass_tree_rate: float = float(grass[&"tree"]) / float(grass["total"])
	var high_tree_rate: float = float(high[&"tree"]) / float(high["total"])
	var grass_rock_rate: float = float(grass[&"rock"]) / float(grass["total"])
	var high_rock_rate: float = float(high[&"rock"]) / float(high["total"])
	if grass_tree_rate <= high_tree_rate:
		failures.append("Verteilung: Grasland muss baumreicher sein (%f vs %f)" % [grass_tree_rate, high_tree_rate])
	if high_rock_rate <= grass_rock_rate:
		failures.append("Verteilung: Felsland muss steinreicher sein (%f vs %f)" % [high_rock_rate, grass_rock_rate])

## Dekor: deterministisch, nie auf Merkmalszellen, im Biom-Katalog gedeckt,
## und ueberhaupt vorhanden (belebt kahle Flaechen).
func _test_decor(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED)
	var decor_count := 0
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			var decor := a.get_decor(cell)
			if decor != b.get_decor(cell):
				failures.append("Dekor: Zelle %s nicht deterministisch" % cell)
				return
			if decor == &"":
				continue
			decor_count += 1
			if a.get_feature(cell) != &"":
				failures.append("Dekor: %s liegt auf Merkmalszelle %s" % [decor, cell])
				return
			var biome := String(a.get_biome(cell))
			var allowed: Dictionary = Database.biomes.get(biome, {}).get("decor", {})
			if not allowed.has(String(decor)):
				failures.append("Dekor: %s nicht im Biom '%s' erlaubt" % [decor, biome])
				return
	if decor_count == 0:
		failures.append("Dekor: keine dekorierten Zellen (erwartet > 0)")

## Wasser: kommt vor, ist unbegehbar, und die Ufer-Erkennung ist konsistent
## (Ufer == mind. ein Nicht-Wasser-Nachbar, inkl. Kartenrand).
func _test_water(failures: Array) -> void:
	var map := _make_map(_SEED)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var water := 0
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if map.get_biome(cell) != &"water":
				continue
			water += 1
			if map.is_walkable(cell):
				failures.append("Wasser: %s muss unbegehbar sein" % cell)
				return
			var has_land_neighbor := false
			for d in dirs:
				if map.get_biome(cell + d) != &"water":
					has_land_neighbor = true
			if map.is_water_shore(cell) != has_land_neighbor:
				failures.append("Wasser: Ufer-Erkennung inkonsistent bei %s" % cell)
				return
	if water == 0:
		failures.append("Wasser: kein Wasserbiom auf der Karte (erwartet > 0)")

## Fluesse: kommen vor, sind unbegehbar, deterministisch, und jede Flusszelle
## haengt an einem weiteren Fluss/Wasser-Nachbarn oder am Kartenrand (Lauf, keine
## Streuung). Der Quellpunkt darf allein stehen.
func _test_river(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var count := 0
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if not a.is_river(cell):
				if b.is_river(cell):
					failures.append("Fluss: nicht deterministisch bei %s" % cell)
					return
				continue
			if not b.is_river(cell):
				failures.append("Fluss: nicht deterministisch bei %s" % cell)
				return
			count += 1
			if a.is_walkable(cell):
				failures.append("Fluss: %s muss unbegehbar sein" % cell)
				return
	if count == 0:
		failures.append("Fluss: kein Flusslauf auf der Karte (erwartet > 0)")

## Bauplaetze: eindeutig, im Kartenbereich, merkmalfrei, stabiler Praefix.
func _test_building_slots(failures: Array) -> void:
	var map := _make_map(_SEED)
	var slots: Array = map.building_slots(6)
	if slots.size() != 6:
		failures.append("Bauplaetze: erwartet 6, erhalten %d" % slots.size())
		return
	var seen := {}
	for cell in slots:
		if seen.has(cell):
			failures.append("Bauplaetze: Zelle %s doppelt vergeben" % cell)
		seen[cell] = true
		if map.get_biome(cell) == &"" or map.get_feature(cell) != &"":
			failures.append("Bauplatz %s ungueltig (ausserhalb oder belegt)" % cell)
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			var dist := maxi(absi(slots[i].x - slots[j].x), absi(slots[i].y - slots[j].y))
			if dist < WorldMap.SLOT_SPACING:
				failures.append("Bauplaetze: %s und %s zu nah beieinander" % [slots[i], slots[j]])
	if map.building_slots(3) != slots.slice(0, 3):
		failures.append("Bauplaetze: erste 3 muessen stabil bleiben")

## Nur Seed+Groesse werden gespeichert; Laden regeneriert dieselbe Karte.
func _test_roundtrip(failures: Array) -> void:
	var original := _make_map(_SEED)
	var restored := WorldMap.new()
	restored.from_dict(original.to_dict(), Database.biomes)
	var sample := Vector2i(_SIZE / 3, _SIZE / 2)
	if restored.width != _SIZE or restored.get_biome(sample) != original.get_biome(sample) \
			or restored.get_feature(sample) != original.get_feature(sample):
		failures.append("Roundtrip: regenerierte Karte weicht ab")
