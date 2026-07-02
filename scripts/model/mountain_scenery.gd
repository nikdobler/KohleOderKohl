class_name MountainScenery
extends RefCounted
## MountainScenery — deterministische Platzierung grosser Bergkulissen (§8.2).
##
## Reine, headless testbare Logik: streut aus dem Karten-Seed sparsam grosse
## Berg-Sprites in die Hochlagen-Biome (Feld "mountains" je Biom in biomes.json)
## und haelt einen Mindestabstand, damit die Kulissen nicht verklumpen. Rein
## kosmetisch — blockiert weder Bau noch Bewegung.

## Bergkulissen als [{"type": StringName, "cell": Vector2i}].
## [param biome_mountains] bildet Biom (StringName) -> [Varianten-IDs] ab,
## [param density] ist die Wahrscheinlichkeit je Hochland-Zelle, [param spacing]
## der Chebyshev-Mindestabstand zwischen zwei Kulissen.
static func backdrops(map: WorldMap, biome_mountains: Dictionary, density: float, spacing: int) -> Array:
	var result: Array = []
	if map == null or map.width <= 0 or map.height <= 0 or density <= 0.0:
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mountains:%d" % map.seed_value)
	var placed: Array = []
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var variants: Array = biome_mountains.get(map.get_biome(cell), [])
			if variants.is_empty():
				continue
			if rng.randf() >= density:
				continue
			if _too_close(cell, placed, spacing):
				continue
			var type: StringName = StringName(variants[rng.randi_range(0, variants.size() - 1)])
			result.append({"type": type, "cell": cell})
			placed.append(cell)
	return result

## Haelt die Zelle den Mindestabstand (Chebyshev) zu allen gesetzten Kulissen?
static func _too_close(cell: Vector2i, placed: Array, spacing: int) -> bool:
	for other in placed:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < spacing:
			return true
	return false
