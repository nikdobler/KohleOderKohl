class_name PathNetwork
extends RefCounted
## PathNetwork — verbindet Gebaeude ueber begehbare Zellen zu einem Wegenetz (§8.4/§8.6).
##
## Reine, headless testbare Logik: Nabe = erstes Gebaeude (i. d. R. Bergfried);
## jedes weitere Gebaeude wird per BFS an die NAECHSTE bereits vernetzte Zelle
## angeschlossen (Baum mit gemeinsamen Stämmen). Wege laufen ueber begehbares Land
## ODER queren einen Fluss (Netz-Zelle auf einem Fluss = Bruecke); Seen/Sumpf bleiben
## unpassierbar. Unerreichbare Gebaeude werden stillschweigend uebersprungen.

## Vier Iso-Seitenrichtungen (gleiche Reihenfolge/Bits wie die Wasser-Kantenmaske).
const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Wegenetz als Menge { Vector2i -> true } (inkl. der Gebaeudezellen als Knoten).
## (Name nicht "connect" — das kollidiert mit Object.connect.)
static func build(building_cells: Array, world: WorldMap) -> Dictionary:
	var network: Dictionary = {}
	if building_cells.is_empty():
		return network
	var hub: Vector2i = building_cells[0]
	network[hub] = true
	var rest: Array = building_cells.slice(1)
	rest.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := maxi(absi(a.x - hub.x), absi(a.y - hub.y))
		var db := maxi(absi(b.x - hub.x), absi(b.y - hub.y))
		if da != db: return da < db
		if a.y != b.y: return a.y < b.y
		return a.x < b.x)
	for target in rest:
		for cell in _bfs_to_network(target, network, world):
			network[cell] = true
	return network

## Kreuzungs-/Nabenzellen (>= 3 Netz-Nachbarn) — dort stehen Wegweiser.
static func junctions(network: Dictionary) -> Array:
	var result: Array = []
	for cell in network:
		var degree := 0
		for dir in _DIRS:
			if network.has(cell + dir):
				degree += 1
		if degree >= 3:
			result.append(cell)
	return result

## Kuerzester begehbarer Weg von [param start] bis zur ersten Netz-Zelle (BFS,
## deterministisch). Leeres Array, wenn das Netz nicht erreichbar ist.
static func _bfs_to_network(start: Vector2i, network: Dictionary, world: WorldMap) -> Array:
	if network.has(start):
		return [start]
	var came_from: Dictionary = {start: start}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for dir in _DIRS:
			var n: Vector2i = current + dir
			# Wege laufen ueber begehbares Land ODER queren einen Fluss (Bruecke);
			# Seen/Sumpf bleiben unpassierbar.
			if came_from.has(n) or not (world.is_walkable(n) or world.is_river(n)):
				continue
			came_from[n] = current
			if network.has(n):
				return _reconstruct(came_from, start, n)
			queue.append(n)
	return []

## Baut den Pfad start..goal aus der came_from-Kette zusammen.
static func _reconstruct(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var path: Array = [goal]
	var current: Vector2i = goal
	while current != start:
		current = came_from[current]
		path.append(current)
	return path
