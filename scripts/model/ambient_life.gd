class_name AmbientLife
extends RefCounted
## AmbientLife — deterministische Platzierung wilder Ambient-Tiere (§8.5).
##
## Reine, headless testbare Logik ohne Rendering: streut aus dem Karten-Seed eine
## feste Menge Tiere in die Zellen, deren Biom im Habitat des Tiers liegt (aus
## /data/animals.json, Kategorie "wild"). Gleicher Seed + gleiche Karte -> exakt
## gleiche Verteilung; das Rendering (WorldView) bleibt reine Anzeige.
##
## Wilde Tiere (spawn_points) haengen am Karten-Seed; Nutztiere (livestock_points)
## haengen an Gebaeuden und stehen auf deren Nachbarzellen (near_building).

## Liefert Spawn-Punkte als Array von {"type": StringName, "cell": Vector2i}.
## [param animal_defs] ist das rohe JSON aus animals.json, [param count] die
## gewuenschte Anzahl (deterministisch aus dem Karten-Seed gezogen).
static func spawn_points(map: WorldMap, animal_defs: Dictionary, count: int) -> Array:
	var result: Array = []
	if map == null or map.width <= 0 or map.height <= 0 or count <= 0:
		return result
	var by_biome := _wild_by_biome(animal_defs)
	if by_biome.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ambient:%d" % map.seed_value)
	# Endliche Versuchszahl: leere Biome (z. B. Schnee) sollen nicht endlos ziehen.
	var attempts := count * 8
	while result.size() < count and attempts > 0:
		attempts -= 1
		var cell := Vector2i(rng.randi_range(0, map.width - 1), rng.randi_range(0, map.height - 1))
		var candidates: Array = by_biome.get(map.get_biome(cell), [])
		if candidates.is_empty():
			continue
		var type: StringName = candidates[rng.randi_range(0, candidates.size() - 1)]
		result.append({"type": type, "cell": cell})
	return result

## Feste Nachbar-Offsets fuer Nutztiere rund ums Gebaeude (deterministisch, kein RNG).
const _LIVESTOCK_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 1),
]

## Nutztiere (Kategorie "livestock") auf Nachbarzellen passender Gebaeude.
## [param building_list] sind die Eintraege aus buildings_changed ({def_id, cell}).
## Rueckgabe wie spawn_points: [{"type": StringName, "cell": Vector2i}].
static func livestock_points(building_list: Array, animal_defs: Dictionary) -> Array:
	var by_building := _livestock_by_building(animal_defs)
	var result: Array = []
	for entry in building_list:
		var here: Array = by_building.get(StringName(entry["def_id"]), [])
		for i in here.size():
			var cell: Vector2i = entry["cell"] + _LIVESTOCK_OFFSETS[i % _LIVESTOCK_OFFSETS.size()]
			result.append({"type": here[i], "cell": cell})
	return result

## Index Gebaeude-ID (StringName) -> [Nutztier-IDs (StringName)] aus near_building.
static func _livestock_by_building(animal_defs: Dictionary) -> Dictionary:
	var by_building: Dictionary = {}
	for id in animal_defs:
		var def: Dictionary = animal_defs[id]
		if String(def.get("category", "")) != "livestock":
			continue
		var near := StringName(def.get("near_building", ""))
		if near == &"":
			continue
		if not by_building.has(near):
			by_building[near] = []
		by_building[near].append(StringName(id))
	return by_building

## Baut den Index Biom (StringName) -> [Tier-IDs (StringName)] fuer wilde Tiere.
static func _wild_by_biome(animal_defs: Dictionary) -> Dictionary:
	var by_biome: Dictionary = {}
	for id in animal_defs:
		var def: Dictionary = animal_defs[id]
		if String(def.get("category", "")) != "wild":
			continue
		for biome in def.get("habitat", []):
			var key := StringName(biome)
			if not by_biome.has(key):
				by_biome[key] = []
			by_biome[key].append(StringName(id))
	return by_biome
