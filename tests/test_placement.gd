extends RefCounted
## Unit-Tests fuer die Platzierungsregeln (M8).
##
## Nutzt eine echte generierte Karte und die echten Gebaeude-Definitionen:
## gefundene Zellen je Biom/Merkmal werden gegen die Regeln geprueft.
## Leere Fehlerliste == bestanden.

const _SEED: int = 1234
const _SIZE: int = 48

var _world: WorldMap

func run() -> Array:
	var failures: Array = []
	_world = WorldMap.new()
	_world.generate(_SEED, _SIZE, _SIZE, Database.biomes)
	_test_biome_rule(failures)
	_test_rock_required(failures)
	_test_rock_or_none(failures)
	_test_near_rule(failures)
	_test_occupied_and_bounds(failures)
	_test_not_buildable_without_placement(failures)
	return failures

## Sucht eine Zelle mit Biom/Merkmal (Merkmal "" = frei, "*" = egal).
func _find_cell(biome: StringName, feature: String) -> Vector2i:
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if _world.get_biome(cell) != biome or not _world.is_walkable(cell):
				continue  # Fluss-/unbegehbare Zellen sind keine gueltigen Bauplaetze
			if feature == "*" or String(_world.get_feature(cell)) == feature:
				return cell
	return Vector2i(-1, -1)

## Weizenfeld nur auf Grasland: Huegel/Felsland muessen ablehnen.
func _test_biome_rule(failures: Array) -> void:
	var farm := Database.get_building_def(&"wheat_farm")
	var grass := _find_cell(&"grassland", "")
	if not Placement.can_place(farm, grass, _world, {})["ok"]:
		failures.append("Biom: Weizenfeld muss auf freiem Grasland gehen")
	var hills := _find_cell(&"hills", "")
	if Placement.can_place(farm, hills, _world, {})["ok"]:
		failures.append("Biom: Weizenfeld darf nicht auf Huegel")

## Steinbruch braucht Fels als Untergrund.
func _test_rock_required(failures: Array) -> void:
	var quarry := Database.get_building_def(&"quarry")
	var rock := _find_cell(&"highlands", "rock")
	if not Placement.can_place(quarry, rock, _world, {})["ok"]:
		failures.append("Fels: Steinbruch muss auf Fels gehen")
	var free_cell := _find_cell(&"highlands", "")
	var verdict := Placement.can_place(quarry, free_cell, _world, {})
	if verdict["ok"] or not verdict["reason"].contains("Fels"):
		failures.append("Fels: Steinbruch ohne Fels muss mit Begruendung scheitern")

## Festungswerke: frei ODER auf Fels, auch auf Huegeln — nicht auf Baeumen.
func _test_rock_or_none(failures: Array) -> void:
	var wall := Database.get_building_def(&"wall")
	if not Placement.can_place(wall, _find_cell(&"hills", ""), _world, {})["ok"]:
		failures.append("Festung: Mauer muss auf freiem Huegel gehen")
	if not Placement.can_place(wall, _find_cell(&"highlands", "rock"), _world, {})["ok"]:
		failures.append("Festung: Mauer muss auf Fels gehen")
	var tree := _find_cell(&"grassland", "tree")
	if Placement.can_place(wall, tree, _world, {})["ok"]:
		failures.append("Festung: Mauer darf nicht auf Baeume")

## Holzfaeller braucht Baeume im Umkreis.
func _test_near_rule(failures: Array) -> void:
	var woodcutter := Database.get_building_def(&"woodcutter")
	var near_tree := Vector2i(-1, -1)
	var far_from_tree := Vector2i(-1, -1)
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if _world.get_biome(cell) != &"grassland" or _world.get_feature(cell) != &"" \
					or not _world.is_walkable(cell):
				continue
			if _world.has_feature_near(cell, &"tree", 3):
				if near_tree.x < 0:
					near_tree = cell
			elif far_from_tree.x < 0:
				far_from_tree = cell
	if near_tree.x >= 0 and not Placement.can_place(woodcutter, near_tree, _world, {})["ok"]:
		failures.append("Umgebung: Holzfaeller bei Baeumen muss gehen")
	if far_from_tree.x >= 0 and Placement.can_place(woodcutter, far_from_tree, _world, {})["ok"]:
		failures.append("Umgebung: Holzfaeller ohne Baeume muss scheitern")

## Belegte Zellen und Kartenrand werden abgelehnt.
func _test_occupied_and_bounds(failures: Array) -> void:
	var house := Database.get_building_def(&"house")
	var cell := _find_cell(&"grassland", "")
	if Placement.can_place(house, cell, _world, {cell: true})["ok"]:
		failures.append("Belegt: besetzte Zelle muss abgelehnt werden")
	if Placement.can_place(house, Vector2i(-3, 5), _world, {})["ok"]:
		failures.append("Rand: Zelle ausserhalb muss abgelehnt werden")

## Gebaeude ohne placement-Block (Bergfried) sind nicht baubar.
func _test_not_buildable_without_placement(failures: Array) -> void:
	var keep := Database.get_building_def(&"keep")
	if Placement.can_place(keep, _find_cell(&"grassland", ""), _world, {})["ok"]:
		failures.append("Baubar: Bergfried darf nicht baubar sein")
