extends RefCounted
## Unit-Tests fuer die Kartengenerierung (M4, M-Landschaft).
##
## Prueft Determinismus, Biom-Vielfalt (Hoehen-/Feuchte-Zonierung), biomabhaengige
## Ressourcenverteilung, Fluesse/Ufer/Wasserfaelle und den Seed-Roundtrip — rein
## logisch, ohne Rendering. Seit M-Landschaft haben Features Kontinent-Groesse;
## die Merkmals-Tests nehmen deshalb ein GROSSES zentriertes Stichprobenfenster
## um den Ursprung (nicht mehr nur das Startgebiet) und einen kuratierten Seed,
## der alle Biome + Fluss-mit-Muendung + Wasserfall zeigt.

const _SEED: int = 1234        # kuratiert: zeigt alle Biome + Fluss + Wasserfall
const _SAMPLE: int = 320       # zentriertes Merkmals-Fenster [-160, 160)
const _DET: int = 64           # kleineres Fenster fuer gleichmaessige Eigenschaften
const _SIZE: int = 48          # Startgebiet (Bauplaetze)

const _EXPECTED_BIOMES: Array = [
	&"water", &"beach", &"swamp", &"desert", &"grassland", &"valley",
	&"forest", &"heath", &"hills", &"highlands", &"snow"]

func run() -> Array:
	var failures: Array = []
	_test_deterministic_generation(failures)
	_test_different_seeds_differ(failures)
	_test_all_biomes_present(failures)
	_test_feature_distribution_differs(failures)
	_test_decor(failures)
	_test_water(failures)
	_test_river(failures)
	_test_water_edge_mask(failures)
	_test_waterfall(failures)
	_test_bank(failures)
	_test_building_slots(failures)
	_test_roundtrip(failures)
	return failures

func _make_map(map_seed: int) -> WorldMap:
	var map := WorldMap.new()
	map.generate(map_seed, _SIZE, _SIZE, Database.biomes)
	return map

## Gleicher Seed -> identische Biome und Merkmale (gleichmaessig, kleines Fenster).
func _test_deterministic_generation(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED)
	var half := _DET / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			if a.get_biome(cell) != b.get_biome(cell) or a.get_feature(cell) != b.get_feature(cell):
				failures.append("Determinismus: Zelle %s weicht ab" % cell)
				return

## Andere Seeds erzeugen (praktisch sicher) eine andere Karte.
func _test_different_seeds_differ(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED + 1)
	var half := _DET / 2
	for y in range(-half, half):
		for x in range(-half, half):
			if a.get_biome(Vector2i(x, y)) != b.get_biome(Vector2i(x, y)):
				return
	failures.append("Seeds: unterschiedliche Seeds ergaben identische Biome")

## Alle Biome kommen im grossen Fenster vor (Hoehen-/Feuchte-Zonierung).
func _test_all_biomes_present(failures: Array) -> void:
	var counts := _biome_counts(_make_map(_SEED))
	for biome_id in _EXPECTED_BIOMES:
		if int(counts.get(biome_id, 0)) == 0:
			failures.append("Biome: '%s' kommt im Fenster nicht vor" % biome_id)
	# Datenkonsistenz: jedes erzeugte Biom existiert in biomes.json.
	for biome_id in counts:
		if not Database.biomes.has(String(biome_id)):
			failures.append("Biome: '%s' fehlt in biomes.json" % biome_id)

## Zaehlt die Zellen je Biom im grossen Fenster.
func _biome_counts(map: WorldMap) -> Dictionary:
	var counts: Dictionary = {}
	var half := _SAMPLE / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var biome := map.get_biome(Vector2i(x, y))
			counts[biome] = int(counts.get(biome, 0)) + 1
	return counts

## Ressourcenverteilung je Biom: Grasland baumreich, Felsland steinreich.
func _test_feature_distribution_differs(failures: Array) -> void:
	var map := _make_map(_SEED)
	var rates := {}
	var half := _SAMPLE / 2
	for y in range(-half, half):
		for x in range(-half, half):
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

## Dekor: deterministisch, nie auf Merkmalszellen, im Biom-Katalog gedeckt, vorhanden.
func _test_decor(failures: Array) -> void:
	var a := _make_map(_SEED)
	var b := _make_map(_SEED)
	var decor_count := 0
	var half := _DET / 2
	for y in range(-half, half):
		for x in range(-half, half):
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

## Wasser: kommt vor, ist unbegehbar, Ufer-Erkennung konsistent.
func _test_water(failures: Array) -> void:
	var map := _make_map(_SEED)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var water := 0
	var half := _SAMPLE / 2
	for y in range(-half, half):
		for x in range(-half, half):
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
		failures.append("Wasser: kein Wasserbiom im Fenster (erwartet > 0)")

## Fluesse: kommen vor, unbegehbar, muenden mindestens einmal in einen See/das Meer.
func _test_river(failures: Array) -> void:
	var map := _make_map(_SEED)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var count := 0
	var mouths := 0
	var half := _SAMPLE / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			if not map.is_river(cell):
				continue
			count += 1
			if map.is_walkable(cell):
				failures.append("Fluss: %s muss unbegehbar sein" % cell)
				return
			for d in dirs:
				if map.get_biome(cell + d) == &"water":
					mouths += 1
					break
	if count == 0:
		failures.append("Fluss: kein Flusslauf im Fenster (erwartet > 0)")
	if mouths == 0:
		failures.append("Fluss: keine Muendung ins Wasser (erwartet >= 1)")
	# Determinismus der Fluesse (kleines Fenster, teuer): gleiche Karte gleich.
	var b := _make_map(_SEED)
	var dh := _DET / 2
	for y in range(-dh, dh):
		for x in range(-dh, dh):
			if map.is_river(Vector2i(x, y)) != b.is_river(Vector2i(x, y)):
				failures.append("Fluss: nicht deterministisch bei %s" % Vector2i(x, y))
				return

## Autotile-Kantenmaske spiegelt genau die Wassergruppen-Nachbarschaft.
func _test_water_edge_mask(failures: Array) -> void:
	var map := _make_map(_SEED)
	var bit_dir := {1: Vector2i(0, -1), 2: Vector2i(1, 0), 4: Vector2i(0, 1), 8: Vector2i(-1, 0)}
	var checked := 0
	var half := _DET / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			if map.get_biome(cell) != &"water" and not map.is_river(cell):
				continue
			checked += 1
			var expected := 0
			for bit in bit_dir:
				var n: Vector2i = cell + bit_dir[bit]
				if map.get_biome(n) == &"water" or map.is_river(n):
					expected |= int(bit)
			if map.water_edge_mask(cell) != expected:
				failures.append("Kantenmaske: %s falsch (%d != %d)" % [cell, map.water_edge_mask(cell), expected])
				return
	if checked == 0:
		failures.append("Kantenmaske: keine Wasser-/Flusszellen im Fenster")

## Wasserfaelle: kommen vor, sind Flusszellen mit steilem Abfall zum Wasser.
func _test_waterfall(failures: Array) -> void:
	var map := _make_map(_SEED)
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var count := 0
	var half := _SAMPLE / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			if not map.is_waterfall(cell):
				continue
			count += 1
			if not map.is_river(cell):
				failures.append("Wasserfall: %s ist keine Flusszelle" % cell)
				return
			var steep := false
			for d in dirs:
				var n: Vector2i = cell + d
				if (map.get_biome(n) == &"water" or map.is_river(n)) \
						and map.get_elevation(cell) - map.get_elevation(n) > WorldMap.WATERFALL_DROP:
					steep = true
			if not steep:
				failures.append("Wasserfall: %s ohne steilen Abfall" % cell)
				return
	if count == 0:
		failures.append("Wasserfall: keiner im Fenster (erwartet > 0)")

## Ufer: begehbares Land direkt neben Wasser/Fluss, kommt vor.
func _test_bank(failures: Array) -> void:
	var map := _make_map(_SEED)
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var count := 0
	var half := _DET / 2
	for y in range(-half, half):
		for x in range(-half, half):
			var cell := Vector2i(x, y)
			if not map.is_bank(cell):
				continue
			count += 1
			if not map.is_walkable(cell):
				failures.append("Ufer: %s muss begehbar sein" % cell)
				return
			var touches_water := false
			for d in dirs:
				if map.get_biome(cell + d) == &"water" or map.is_river(cell + d):
					touches_water = true
			if not touches_water:
				failures.append("Ufer: %s ohne Wasser-/Fluss-Nachbar" % cell)
				return
	if count == 0:
		failures.append("Ufer: kein Ufer im Fenster (erwartet > 0)")

## Bauplaetze: eindeutig, begehbares merkmalfreies Land, stabiler Praefix.
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
		if not map.is_walkable(cell) or map.get_feature(cell) != &"":
			failures.append("Bauplatz %s ungueltig (unbegehbar oder belegt)" % cell)
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
	var sample := Vector2i(37, -22)
	if restored.width != _SIZE or restored.get_biome(sample) != original.get_biome(sample) \
			or restored.get_feature(sample) != original.get_feature(sample):
		failures.append("Roundtrip: regenerierte Karte weicht ab")
