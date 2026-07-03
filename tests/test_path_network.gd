extends RefCounted
## Unit-Tests fuer das Wegenetz (§8.4/§8.6).
##
## Prueft, dass erreichbare Gebaeude verbunden werden, das Netz nur begehbare
## Zellen nutzt, jedes Gebaeude an eine Netz-Zelle grenzt, und alles deterministisch
## ist. Nutzt eine echte generierte Karte.

const _SEED: int = 1234
const _SIZE: int = 48

var _world: WorldMap

func run() -> Array:
	var failures: Array = []
	_world = WorldMap.new()
	_world.generate(_SEED, _SIZE, _SIZE, Database.biomes)
	_test_connects_and_walkable(failures)
	_test_deterministic(failures)
	_test_empty(failures)
	return failures

## Sucht [param count] begehbare, gegenseitig verbundene Zellen als Test-Gebaeude:
## per BFS von einem Startpunkt, damit alle im selben begehbaren Gebiet liegen.
func _reachable_cells(count: int) -> Array:
	var start := _world.building_slots(1)
	if start.is_empty():
		return []
	var result: Array = [start[0]]
	var seen := {start[0]: true}
	var queue: Array = [start[0]]
	var head := 0
	while head < queue.size() and result.size() < count * 40:
		var current: Vector2i = queue[head]
		head += 1
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = current + dir
			if seen.has(n) or not _world.is_walkable(n):
				continue
			seen[n] = true
			queue.append(n)
			result.append(n)
	# gut verteilte Auswahl aus dem begehbaren Gebiet
	var picked: Array = []
	var step := maxi(1, result.size() / count)
	for i in count:
		if i * step < result.size():
			picked.append(result[i * step])
	return picked

## Erreichbare Gebaeude landen alle im Netz; jede Netz-Zelle ist begehbar.
func _test_connects_and_walkable(failures: Array) -> void:
	var buildings := _reachable_cells(4)
	if buildings.size() < 2:
		failures.append("Wege: zu wenige begehbare Testzellen gefunden")
		return
	var network := PathNetwork.build(buildings, _world)
	for cell in buildings:
		if not network.has(cell):
			failures.append("Wege: erreichbares Gebaeude %s nicht verbunden" % cell)
			return
	for cell in network:
		if not (_world.is_walkable(cell) or _world.is_river(cell)):
			failures.append("Wege: Netz-Zelle %s ist weder begehbar noch Bruecke" % cell)
			return

## Gleiche Eingabe -> gleiches Netz.
func _test_deterministic(failures: Array) -> void:
	var buildings := _reachable_cells(4)
	var a := PathNetwork.build(buildings, _world)
	var b := PathNetwork.build(buildings, _world)
	if a.size() != b.size():
		failures.append("Wege: nicht deterministisch (Groesse %d != %d)" % [a.size(), b.size()])
		return
	for cell in a:
		if not b.has(cell):
			failures.append("Wege: nicht deterministisch (Zelle %s fehlt)" % cell)
			return

## Leere Gebaeudeliste -> leeres Netz (kein Crash).
func _test_empty(failures: Array) -> void:
	if not PathNetwork.build([], _world).is_empty():
		failures.append("Wege: leere Eingabe muss leeres Netz liefern")
