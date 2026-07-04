extends RefCounted
## Unit-Tests fuer das Kampfsystem (M5, spec_kampfsystem.md).
##
## Prueft Schadensformel, Bewegung, Haltungen, Wellen, Sieg/Niederlage und
## Speicher-Roundtrip mit synthetischen Definitionen und festem RNG-Seed —
## rein logisch, ohne UI. Leere Fehlerliste == bestanden.

const _UNIT_DEFS := {
	"swordsman": {"hp": 30, "attack": 6, "defense": 3, "speed": 1},
	"raider": {"hp": 12, "attack": 4, "defense": 1, "speed": 1},
	"archer": {"hp": 20, "attack": 5, "defense": 1, "speed": 1, "attack_range": 3},
}

func run() -> Array:
	var failures: Array = []
	_test_damage_bounds(failures)
	_test_movement_stops_adjacent(failures)
	_test_guard_ignores_distant_enemies(failures)
	_test_assault_reaches_victory(failures)
	_test_waves_lead_to_defeat(failures)
	_test_obstacle_blocks_enemy_and_falls(failures)
	_test_own_obstacle_does_not_block_player(failures)
	_test_pathfinding_walks_around_walls(failures)
	_test_gate_semantics(failures)
	_test_gate_blocks_enemy(failures)
	_test_terrain_blocks_and_paths_around(failures)
	_test_enclosed_enemy_breaches(failures)
	_test_tower_shoots_nearest_enemy_in_range(failures)
	_test_tower_ignores_player_and_out_of_range(failures)
	_test_tower_stats_roundtrip(failures)
	_test_ranged_unit_strikes_from_distance(failures)
	_test_command_move_posts_unit(failures)
	_test_grid_grows_with_distant_target(failures)
	_test_remove_obstacle_reopens_path(failures)
	_test_roundtrip(failures)
	return failures

## M-Unendlich: das Wegfindungs-Gitter waechst mit — ein Marschziel weit
## ausserhalb des Startgebiets (auch negative Koordinaten) wird erreicht.
func _test_grid_grows_with_distant_target(failures: Array) -> void:
	var map := WorldMap.new()
	map.generate(99, 24, 24, Database.biomes)
	var combat := _make_system(100, 100)
	combat.setup_grid_map(map, Rect2i(0, 0, 12, 12))
	var start := map.nearest_free_cell(Vector2i(2, 2))
	# Fernes ERREICHBARES Ziel per BFS ueber begehbares Land (seit M-Landschaft
	# blockiert Wasser -> ein fixes Ziel koennte auf einer anderen Landmasse liegen).
	var target := _reachable_far_cell(map, start, 60)
	var start_dist := maxi(absi(start.x - target.x), absi(start.y - target.y))
	if start_dist < 20:
		failures.append("Unendlich: kein fernes erreichbares Ziel gefunden (Landmasse zu klein)")
		return
	var unit := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		start, CombatSystem.STANCE_GUARD, start)
	if not combat.command_move(unit.id, target):
		failures.append("Unendlich: Marschbefehl muss angenommen werden")
		return
	for i in 500:
		combat.tick()
		if unit.cell == target:
			break
	var end_dist := maxi(absi(unit.cell.x - target.x), absi(unit.cell.y - target.y))
	if end_dist > 1:
		failures.append("Unendlich: Einheit muss das ferne Ziel erreichen (Gitter waechst mit) (%d -> %d)" % [start_dist, end_dist])

## Entferntestes per begehbarem Land (4er-BFS) erreichbares Feld in einer Box
## um [param start] — garantiert ein zusammenhaengend erreichbares Marschziel.
func _reachable_far_cell(map: WorldMap, start: Vector2i, radius: int) -> Vector2i:
	var visited := {start: true}
	var queue: Array = [start]
	var head := 0
	var best := start
	var best_dist := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d := maxi(absi(c.x - start.x), absi(c.y - start.y))
		if d > best_dist:
			best_dist = d
			best = c
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dir
			if visited.has(n) or absi(n.x - start.x) > radius or absi(n.y - start.y) > radius:
				continue
			if not map.is_walkable(n):
				continue
			visited[n] = true
			queue.append(n)
	return best

## System ohne Wellen/Verteidiger; Bergfriede an gegebenen Zellen.
func _make_system(player_hp: int, enemy_hp: int, enemy_cfg: Dictionary = {}) -> CombatSystem:
	var combat := CombatSystem.new()
	var cfg := {"unit": "raider", "defenders": 0, "wave_interval_ticks": 0, "wave_size": 0}
	cfg.merge(enemy_cfg, true)
	combat.setup(_UNIT_DEFS,
		{"cell": Vector2i(0, 0), "hp": player_hp},
		{"cell": Vector2i(8, 8), "hp": enemy_hp},
		cfg, 42)
	return combat

## Schaden bleibt in der Spanne max(1, ATK-DEF) x 0.8..1.2 (und mind. 1).
func _test_damage_bounds(failures: Array) -> void:
	var combat := _make_system(100, 100)
	var attacker := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 0), CombatSystem.STANCE_GUARD, Vector2i(0, 0))
	var defender := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(1, 0), CombatSystem.STANCE_GUARD, Vector2i(1, 0))
	combat.tick()  # angrenzend -> beide schlagen zu
	var dealt := 12 - defender.hp  # Basis 6-1=5 -> 4..6
	if dealt < 4 or dealt > 6:
		failures.append("Schaden: erwartet 4..6, erhalten %d" % dealt)
	var taken := 30 - attacker.hp  # Basis max(1, 4-3)=1 -> immer 1
	if taken != 1:
		failures.append("Schaden: Mindestschaden 1 erwartet, erhalten %d" % taken)

## Angreifer laeuft auf das Ziel zu und haelt angrenzend an.
func _test_movement_stops_adjacent(failures: Array) -> void:
	var combat := _make_system(100, 100)
	var unit := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 0), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	combat.tick()
	if unit.cell != Vector2i(1, 1):
		failures.append("Bewegung: erwartet (1,1), erhalten %s" % unit.cell)
	for i in 20:
		combat.tick()
	if combat._cheb(unit.cell, Vector2i(8, 8)) != 1:
		failures.append("Bewegung: muss angrenzend am Bergfried halten, steht auf %s" % unit.cell)

## Wache verfolgt keine Feinde ausserhalb des GUARD_RANGE um den Posten.
func _test_guard_ignores_distant_enemies(failures: Array) -> void:
	var combat := _make_system(100, 100)
	var guard := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 0), CombatSystem.STANCE_GUARD, Vector2i(0, 0))
	combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(8, 8), CombatSystem.STANCE_GUARD, Vector2i(8, 8))
	combat.tick()
	if guard.cell != Vector2i(0, 0):
		failures.append("Wache: darf fernem Feind nicht folgen, steht auf %s" % guard.cell)

## Angriff zerstoert den gegnerischen Bergfried -> Sieg (inkl. Verteidiger).
func _test_assault_reaches_victory(failures: Array) -> void:
	var combat := _make_system(100, 20, {"defenders": 1})
	combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 0), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 1), CombatSystem.STANCE_ASSAULT, Vector2i(0, 1))
	var saw_kill := false
	for i in 60:
		for event in combat.tick():
			if event["type"] == "unit_killed" and event["faction"] == CombatSystem.FACTION_ENEMY:
				saw_kill = true
		if combat.status == CombatSystem.STATUS_VICTORY:
			break
	if combat.status != CombatSystem.STATUS_VICTORY:
		failures.append("Sieg: nicht erreicht (Status %s)" % combat.status)
	if not saw_kill:
		failures.append("Sieg: Verteidiger muss gefallen sein (unit_killed-Ereignis)")

## Unverteidigte Siedlung: Angriffswellen zerstoeren den Bergfried -> Niederlage.
func _test_waves_lead_to_defeat(failures: Array) -> void:
	var combat := _make_system(10, 100, {"wave_interval_ticks": 2, "wave_size": 2})
	var saw_wave := false
	for i in 60:
		for event in combat.tick():
			if event["type"] == "wave":
				saw_wave = true
		if combat.status == CombatSystem.STATUS_DEFEAT:
			break
	if not saw_wave:
		failures.append("Wellen: kein wave-Ereignis gesendet")
	if combat.status != CombatSystem.STATUS_DEFEAT:
		failures.append("Niederlage: nicht erreicht (Status %s)" % combat.status)

## M8: Mauern blockieren Feinde; sie schlagen eine Bresche und ziehen weiter.
func _test_obstacle_blocks_enemy_and_falls(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.add_obstacle(Vector2i(4, 4), &"wall", 10)
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(8, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	var destroyed := false
	for i in 30:
		for event in combat.tick():
			if event["type"] == "structure_destroyed" and event["cell"] == Vector2i(4, 4):
				destroyed = true
		if destroyed:
			break
		if raider.cell.x < 4:
			failures.append("Mauer: Feind kam an intakter Mauer vorbei (%s)" % raider.cell)
			return
	if not destroyed or not combat.obstacles.is_empty():
		failures.append("Mauer: muss faellbar sein und gemeldet werden")
		return
	for i in 10:
		combat.tick()
	if combat._cheb(raider.cell, Vector2i(0, 0)) > 1:
		failures.append("Mauer: Feind muss nach der Bresche weiterziehen (%s)" % raider.cell)

## Eigene Festungswerke behindern eigene Einheiten nicht.
func _test_own_obstacle_does_not_block_player(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.add_obstacle(Vector2i(2, 2), &"wall", 999)
	combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(0, 0), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	for i in 20:
		combat.tick()
	var unit: CombatSystem.Unit = combat.units[0]
	if combat._cheb(unit.cell, Vector2i(8, 8)) != 1:
		failures.append("Eigenes Werk: Spieler-Einheit muss durchkommen (%s)" % unit.cell)
	if combat.obstacles[Vector2i(2, 2)]["hp"] != 999:
		failures.append("Eigenes Werk: darf nicht beschaedigt werden")

## M9: Mit Wegfindung laufen Feinde um eine Mauerlinie mit Luecke herum,
## statt sie anzugreifen.
func _test_pathfinding_walks_around_walls(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	# Mauerlinie x=0..5 auf y=4 — Luecke ab x=6: Weg aussen herum existiert.
	for x in 6:
		combat.add_obstacle(Vector2i(x, 4), &"wall", 60)
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(0, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	for i in 40:
		combat.tick()
		if combat._cheb(raider.cell, Vector2i(0, 0)) <= 1:
			break
	if combat._cheb(raider.cell, Vector2i(0, 0)) > 1:
		failures.append("Pfad: Feind muss um die Mauer herum ankommen (%s)" % raider.cell)
	for x in 6:
		if not combat.obstacles.has(Vector2i(x, 4)):
			failures.append("Pfad: Mauer darf bei freiem Weg nicht angegriffen werden")
			return

## M9: Tor laesst Spieler-Einheiten durch (Wand stoppt sie sonst).
func _test_gate_semantics(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	# Wand quer ueber die ganze Karte auf y=4, Tor bei x=5.
	for x in 12:
		if x == 5:
			combat.add_obstacle(Vector2i(x, 4), &"gate", 90, true)
		else:
			combat.add_obstacle(Vector2i(x, 4), &"wall", 999)
	# Spieler startet noerdlich, Ziel (gegnerischer Bergfried 8,8) liegt
	# suedlich der Wand -> einziger Weg fuehrt durchs Tor.
	var sword := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(5, 0), CombatSystem.STANCE_ASSAULT, Vector2i(5, 0))
	var crossed_wall := false
	for i in 30:
		combat.tick()
		if sword.cell == Vector2i(5, 4):
			crossed_wall = true  # exakt auf der Torzelle
		if combat._cheb(sword.cell, Vector2i(8, 8)) <= 1:
			break
	if combat._cheb(sword.cell, Vector2i(8, 8)) > 1:
		failures.append("Tor: Spieler-Einheit muss durchs Tor zum Ziel kommen (%s)" % sword.cell)
	if not crossed_wall:
		failures.append("Tor: Weg muss ueber die Torzelle fuehren")
	if combat.obstacles[Vector2i(5, 4)]["hp"] != 90:
		failures.append("Tor: Spieler darf das eigene Tor nicht beschaedigen")

## M9: Feinde koennen das Tor nicht passieren — sie greifen die Wand an.
func _test_gate_blocks_enemy(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	for x in 12:
		if x == 5:
			combat.add_obstacle(Vector2i(x, 4), &"gate", 900, true)
		else:
			combat.add_obstacle(Vector2i(x, 4), &"wall", 900)
	# Ziel (Spieler-Bergfried 0,0) liegt noerdlich; Feind startet suedlich.
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(5, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	var struck := false
	for i in 25:
		combat.tick()
		if raider.cell.y < 4:
			failures.append("Tor: Feind kam ueber die intakte Wand (%s)" % raider.cell)
			return
	for cell in combat.obstacles:
		if combat.obstacles[cell]["hp"] < 900:
			struck = true
	if not struck:
		failures.append("Tor: eingeschlossener Feind muss ein Werk angreifen")

## M9: Unbegehbares Gelaende (Sumpf) wird umlaufen.
func _test_terrain_blocks_and_paths_around(failures: Array) -> void:
	var combat := _make_system(100, 100)
	var swamp: Array = []
	for x in range(0, 6):
		swamp.append(Vector2i(x, 4))
	combat.setup_grid(12, 12, swamp)
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(0, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	var entered_swamp := false
	for i in 40:
		combat.tick()
		if swamp.has(raider.cell):
			entered_swamp = true
		if combat._cheb(raider.cell, Vector2i(0, 0)) <= 1:
			break
	if entered_swamp:
		failures.append("Sumpf: Einheit darf unbegehbares Gelaende nicht betreten")
	if combat._cheb(raider.cell, Vector2i(0, 0)) > 1:
		failures.append("Sumpf: Einheit muss aussen herum ankommen (%s)" % raider.cell)

## M9: Komplett eingemauert -> Feind schlaegt eine Bresche (kein Weg) und
## erreicht danach den Bergfried (0,0).
func _test_enclosed_enemy_breaches(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	for x in 12:  # durchgehende Wand, keine Luecke
		combat.add_obstacle(Vector2i(x, 4), &"wall", 8)
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(5, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	var breached := false
	for i in 40:
		for event in combat.tick():
			if event["type"] == "structure_destroyed":
				breached = true
		if combat._cheb(raider.cell, Vector2i(0, 0)) <= 1:
			break
	if not breached:
		failures.append("Bresche: eingemauerter Feind muss ein Werk zerstoeren")
	if combat._cheb(raider.cell, Vector2i(0, 0)) > 1:
		failures.append("Bresche: Feind muss danach durchkommen (%s)" % raider.cell)

## M10: Turm beschiesst den naechsten Feind in Reichweite bis zum Tod;
## entferntere Feinde bleiben unbehelligt.
func _test_tower_shoots_nearest_enemy_in_range(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.add_obstacle(Vector2i(5, 5), &"tower", 150, false, 5, 4)
	var near := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(8, 5), CombatSystem.STANCE_GUARD, Vector2i(8, 5))  # Distanz 3
	var far := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(11, 5), CombatSystem.STANCE_GUARD, Vector2i(11, 5))  # Distanz 6
	var events := combat.tick()
	var shot_seen := false
	for event in events:
		if event.get("type", "") == "tower_shot" and event["to"] == Vector2i(8, 5):
			shot_seen = true
	if not shot_seen or near.hp >= 12:
		failures.append("Turm: muss den nahen Feind beschiessen (hp %d)" % near.hp)
	var killed := false
	for i in 30:
		for event in combat.tick():
			if event.get("type", "") == "unit_killed" and event["faction"] == CombatSystem.FACTION_ENEMY:
				killed = true
		if killed:
			break
	if not killed:
		failures.append("Turm: naher Feind muss fallen")
	if far.hp != 12:
		failures.append("Turm: ferner Feind (Distanz 6 > 4) darf nichts abbekommen (hp %d)" % far.hp)

## M10: Tuerme beschiessen keine eigenen Einheiten; attack 0 == passiv.
func _test_tower_ignores_player_and_out_of_range(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.add_obstacle(Vector2i(5, 5), &"tower", 150, false, 5, 4)
	combat.add_obstacle(Vector2i(6, 6), &"wall", 60)  # attack 0: schiesst nie
	var sword := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(6, 5), CombatSystem.STANCE_GUARD, Vector2i(6, 5))
	for i in 5:
		for event in combat.tick():
			if event.get("type", "") == "tower_shot":
				failures.append("Turm: darf ohne Feinde nicht schiessen")
				return
	if sword.hp != 30:
		failures.append("Turm: eigene Einheit darf nicht getroffen werden (hp %d)" % sword.hp)

## M10: Fernkampf-Werte und Nachruestung ueberstehen den Speicher-Roundtrip.
func _test_tower_stats_roundtrip(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.add_obstacle(Vector2i(5, 5), &"tower", 150, false, 0, 0)  # noch ohne Bogen-FE
	combat.set_obstacle_ranged(Vector2i(5, 5), 5, 4)  # Nachruestung
	var restored := CombatSystem.new()
	restored.from_dict(combat.to_dict(), _UNIT_DEFS,
		{"unit": "raider", "wave_interval_ticks": 0, "wave_size": 0})
	var tower: Dictionary = restored.obstacles.get(Vector2i(5, 5), {})
	if int(tower.get("attack", 0)) != 5 or int(tower.get("range", 0)) != 4:
		failures.append("Turm-Roundtrip: Fernkampf-Werte verloren (%s)" % str(tower))
	var raider := restored.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(7, 5), CombatSystem.STANCE_GUARD, Vector2i(7, 5))
	restored.tick()
	if raider.hp >= 12:
		failures.append("Turm-Roundtrip: wiederhergestellter Turm muss schiessen")

## M12: Fernkampf-Einheiten schiessen aus der Distanz, ohne heranzuruecken.
func _test_ranged_unit_strikes_from_distance(failures: Array) -> void:
	var combat := _make_system(100, 100)
	var archer := combat.add_unit(&"archer", CombatSystem.FACTION_PLAYER,
		Vector2i(2, 2), CombatSystem.STANCE_GUARD, Vector2i(2, 2))
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(5, 2), CombatSystem.STANCE_GUARD, Vector2i(5, 2))  # Distanz 3
	combat.tick()
	if archer.cell != Vector2i(2, 2):
		failures.append("Fernkampf: Schuetze darf nicht heranruecken (%s)" % archer.cell)
	if raider.hp >= 12:
		failures.append("Fernkampf: Ziel muss auf Distanz 3 getroffen werden (hp %d)" % raider.hp)
	# Nahkampf-Gegner muss erst heran: Schuetze bleibt, Raider naehert sich.
	if combat._cheb(raider.cell, archer.cell) >= 3:
		failures.append("Fernkampf: Nahkaempfer muss aufschliessen (%s)" % raider.cell)

## M13: Bewegungsbefehl — Einheit marschiert zum neuen Posten (mit
## Wegfindung um Mauern), haelt dort Wache und verteidigt den Posten.
func _test_command_move_posts_unit(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	for x in range(2, 6):
		combat.add_obstacle(Vector2i(x, 4), &"wall", 900)  # Mauerstueck im Weg
	var sword := combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(3, 2), CombatSystem.STANCE_ASSAULT, Vector2i(3, 2))
	if not combat.command_move(sword.id, Vector2i(3, 7)):
		failures.append("Befehl: gueltige Einheit muss Befehl annehmen")
	if combat.command_move(999, Vector2i(1, 1)):
		failures.append("Befehl: unbekannte ID muss abgelehnt werden")
	for i in 20:
		combat.tick()
	if sword.cell != Vector2i(3, 7):
		failures.append("Befehl: Einheit muss den Posten erreichen (%s)" % sword.cell)
	for cell in combat.obstacles:
		if combat.obstacles[cell]["hp"] < 900:
			failures.append("Befehl: eigene Mauer darf beim Marsch nicht leiden")
			return
	# Feind nahe dem Posten wird angegriffen (Wache am neuen Standort).
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(5, 8), CombatSystem.STANCE_GUARD, Vector2i(5, 8))
	for i in 6:
		combat.tick()
	if raider.hp >= 12:
		failures.append("Befehl: Posten muss nahe Feinde bekaempfen (hp %d)" % raider.hp)

## M11: Abriss (remove_obstacle) oeffnet den Weg im Gitter wieder —
## der Feind laeuft durch die Luecke, ohne anzugreifen.
func _test_remove_obstacle_reopens_path(failures: Array) -> void:
	var combat := _make_system(100, 100)
	combat.setup_grid(12, 12, [])
	for x in 12:
		combat.add_obstacle(Vector2i(x, 4), &"wall", 900)
	combat.remove_obstacle(Vector2i(6, 4))
	var raider := combat.add_unit(&"raider", CombatSystem.FACTION_ENEMY,
		Vector2i(5, 8), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	for i in 40:
		combat.tick()
		if combat._cheb(raider.cell, Vector2i(0, 0)) <= 1:
			break
	if combat._cheb(raider.cell, Vector2i(0, 0)) > 1:
		failures.append("Abriss: Feind muss durch die Luecke ankommen (%s)" % raider.cell)
	for cell in combat.obstacles:
		if combat.obstacles[cell]["hp"] < 900:
			failures.append("Abriss: bei freiem Weg darf keine Mauer leiden")
			return

## Kompletter Kampfzustand uebersteht einen Speicher-Roundtrip.
func _test_roundtrip(failures: Array) -> void:
	var combat := _make_system(100, 100, {"defenders": 1})
	combat.add_unit(&"swordsman", CombatSystem.FACTION_PLAYER,
		Vector2i(2, 3), CombatSystem.STANCE_ASSAULT, Vector2i(0, 0))
	combat.tick()
	var restored := CombatSystem.new()
	restored.from_dict(combat.to_dict(), _UNIT_DEFS,
		{"unit": "raider", "wave_interval_ticks": 0, "wave_size": 0})
	if restored.units.size() != combat.units.size() or restored.tick_count != 1:
		failures.append("Roundtrip: Einheiten/Tick falsch")
		return
	var original: CombatSystem.Unit = combat.units[-1]
	var copy: CombatSystem.Unit = restored.units[-1]
	if copy.cell != original.cell or copy.hp != original.hp or copy.stance != original.stance:
		failures.append("Roundtrip: Einheit nicht korrekt wiederhergestellt")
	if restored.keeps[CombatSystem.FACTION_ENEMY]["hp"] != combat.keeps[CombatSystem.FACTION_ENEMY]["hp"]:
		failures.append("Roundtrip: Bergfried-HP weichen ab")
