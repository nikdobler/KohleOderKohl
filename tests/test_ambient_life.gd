extends RefCounted
## Unit-Tests fuer die Ambient-Tier-Platzierung (§8.5).
##
## Prueft Determinismus, Habitat-Korrektheit, dass nur wilde Tiere platziert
## werden und dass leere/kleine Eingaben sauber leer bleiben. Nutzt die echten
## Definitionen aus Database.animals und eine echt generierte Karte.

const _SEED: int = 1234
const _SIZE: int = 48
const _COUNT: int = 60

func run() -> Array:
	var failures: Array = []
	var map := _make_map(_SEED)
	_test_deterministic(failures, map)
	_test_habitat_valid(failures, map)
	_test_only_wild(failures, map)
	_test_count_bounded(failures, map)
	_test_empty_on_zero(failures, map)
	_test_livestock_near_building(failures)
	return failures

func _make_map(map_seed: int) -> WorldMap:
	var map := WorldMap.new()
	map.generate(map_seed, _SIZE, _SIZE, Database.biomes)
	return map

## Gleiche Karte + gleicher Seed -> identische Spawn-Liste.
func _test_deterministic(failures: Array, map: WorldMap) -> void:
	var a := AmbientLife.spawn_points(map, Database.animals, _COUNT)
	var b := AmbientLife.spawn_points(map, Database.animals, _COUNT)
	if a.size() != b.size():
		failures.append("Determinismus: unterschiedliche Anzahl (%d vs %d)" % [a.size(), b.size()])
		return
	for i in a.size():
		if a[i]["type"] != b[i]["type"] or a[i]["cell"] != b[i]["cell"]:
			failures.append("Determinismus: Eintrag %d weicht ab" % i)
			return

## Jedes Tier steht in einer Zelle, deren Biom in seinem Habitat liegt.
func _test_habitat_valid(failures: Array, map: WorldMap) -> void:
	var spawns := AmbientLife.spawn_points(map, Database.animals, _COUNT)
	if spawns.is_empty():
		failures.append("Habitat: keine Tiere platziert (erwartet > 0)")
		return
	for spawn in spawns:
		var def := Database.get_animal_def(spawn["type"])
		var habitat: Array = def.get("habitat", [])
		if not habitat.has(String(map.get_biome(spawn["cell"]))):
			failures.append("Habitat: %s auf %s (Biom %s) nicht erlaubt" % [
				spawn["type"], spawn["cell"], map.get_biome(spawn["cell"])])
			return

## Nur wilde Tiere werden platziert, keine Nutztiere (livestock).
func _test_only_wild(failures: Array, map: WorldMap) -> void:
	for spawn in AmbientLife.spawn_points(map, Database.animals, _COUNT):
		if String(Database.get_animal_def(spawn["type"]).get("category", "")) != "wild":
			failures.append("Kategorie: Nicht-Wildtier platziert: %s" % spawn["type"])
			return

## Es werden nie mehr Tiere als angefordert geliefert.
func _test_count_bounded(failures: Array, map: WorldMap) -> void:
	var spawns := AmbientLife.spawn_points(map, Database.animals, _COUNT)
	if spawns.size() > _COUNT:
		failures.append("Anzahl: %d > angefordert %d" % [spawns.size(), _COUNT])

## count <= 0 liefert eine leere Liste (kein Crash).
func _test_empty_on_zero(failures: Array, map: WorldMap) -> void:
	if not AmbientLife.spawn_points(map, Database.animals, 0).is_empty():
		failures.append("Rand: count 0 muss leere Liste liefern")

## Nutztiere stehen direkt neben ihrem near_building; Gebaeude ohne Zuordnung
## (Bergfried) bekommen keine. Deterministisch (kein RNG).
func _test_livestock_near_building(failures: Array) -> void:
	var by_id := {&"wheat_farm": Vector2i(10, 10), &"house": Vector2i(20, 20), &"keep": Vector2i(30, 30)}
	var buildings: Array = []
	for def_id in by_id:
		buildings.append({"def_id": def_id, "cell": by_id[def_id]})
	var live := AmbientLife.livestock_points(buildings, Database.animals)
	# Kuh(1) am Weizenfeld + Schaf+Huhn(2) am Wohnhaus, Bergfried nichts -> 3.
	if live.size() != 3:
		failures.append("Nutztiere: erwartet 3, erhalten %d" % live.size())
		return
	var seen := {}
	for entry in live:
		seen[entry["type"]] = true
		var near := StringName(Database.get_animal_def(entry["type"]).get("near_building", ""))
		if not by_id.has(near):
			failures.append("Nutztiere: %s ohne bekanntes Gebaeude" % entry["type"])
			continue
		var b: Vector2i = by_id[near]
		var dist := maxi(absi(entry["cell"].x - b.x), absi(entry["cell"].y - b.y))
		if dist != 1:
			failures.append("Nutztiere: %s nicht direkt neben %s (Abstand %d)" % [entry["type"], near, dist])
	for expected in [&"cow", &"sheep", &"chicken"]:
		if not seen.has(expected):
			failures.append("Nutztiere: %s wurde nicht platziert" % expected)
	# Zweiter Aufruf muss identisch sein (Determinismus ohne RNG).
	var live2 := AmbientLife.livestock_points(buildings, Database.animals)
	if live2.size() != live.size():
		failures.append("Nutztiere: nicht deterministisch (Anzahl)")
