extends RefCounted
## Unit-Tests fuer die Bergkulissen-Platzierung (§8.2).
##
## Prueft Determinismus, dass Kulissen nur in Hochlagen-Biomen stehen, ihre
## Variante zum Biom passt, der Mindestabstand eingehalten wird und ueberhaupt
## welche vorkommen. Nutzt eine echte Karte und Database.biomes.

const _SEED: int = 1234
## Seit M-Landschaft liegen Gebirge als Ketten verteilt (nicht mehr am Ursprung);
## backdrops scannt [0,width) -> grosses Gebiet, damit eine Kette erfasst wird.
const _SIZE: int = 256
const _DENSITY: float = 0.25
const _SPACING: int = 3

func run() -> Array:
	var failures: Array = []
	var map := _make_map()
	var mountains := _biome_mountains()
	_test_present_and_valid(failures, map, mountains)
	_test_spacing(failures, map, mountains)
	_test_deterministic(failures, map, mountains)
	return failures

func _make_map() -> WorldMap:
	var map := WorldMap.new()
	map.generate(_SEED, _SIZE, _SIZE, Database.biomes)
	return map

## Biom (StringName) -> [Bergvarianten] aus biomes.json.
func _biome_mountains() -> Dictionary:
	var result: Dictionary = {}
	for biome_id in Database.biomes:
		var variants: Array = Database.biomes[biome_id].get("mountains", [])
		if not variants.is_empty():
			result[StringName(biome_id)] = variants
	return result

## Kulissen stehen nur in Bergbiomen, mit passender Variante — und es gibt welche.
func _test_present_and_valid(failures: Array, map: WorldMap, mountains: Dictionary) -> void:
	var spots := MountainScenery.backdrops(map, mountains, _DENSITY, _SPACING)
	if spots.is_empty():
		failures.append("Berge: keine Kulissen platziert (erwartet > 0)")
		return
	for spot in spots:
		var biome := map.get_biome(spot["cell"])
		var allowed: Array = mountains.get(biome, [])
		if not allowed.has(String(spot["type"])):
			failures.append("Berge: %s auf Biom '%s' unzulaessig" % [spot["type"], biome])
			return

## Kein Paar Kulissen naeher als der Mindestabstand (Chebyshev).
func _test_spacing(failures: Array, map: WorldMap, mountains: Dictionary) -> void:
	var spots := MountainScenery.backdrops(map, mountains, _DENSITY, _SPACING)
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			var a: Vector2i = spots[i]["cell"]
			var b: Vector2i = spots[j]["cell"]
			if maxi(absi(a.x - b.x), absi(a.y - b.y)) < _SPACING:
				failures.append("Berge: %s und %s zu nah (< %d)" % [a, b, _SPACING])
				return

## Gleicher Seed + gleiche Karte -> identische Kulissen.
func _test_deterministic(failures: Array, map: WorldMap, mountains: Dictionary) -> void:
	var a := MountainScenery.backdrops(map, mountains, _DENSITY, _SPACING)
	var b := MountainScenery.backdrops(map, mountains, _DENSITY, _SPACING)
	if a.size() != b.size():
		failures.append("Berge: nicht deterministisch (Anzahl %d vs %d)" % [a.size(), b.size()])
		return
	for i in a.size():
		if a[i]["type"] != b[i]["type"] or a[i]["cell"] != b[i]["cell"]:
			failures.append("Berge: Eintrag %d weicht ab" % i)
			return
