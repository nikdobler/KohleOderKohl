class_name CombatSystem
extends RefCounted
## CombatSystem — Kampf-Grundgeruest (M5) gemaess spec_kampfsystem.md.
##
## Echtzeit im 1-Sekunden-Tick der Wirtschaft: kachelweise Bewegung, Angriff
## auf Nachbarkachel (Chebyshev 1), ein Angriff pro Tick. Schaden =
## max(1, Angriff - Verteidigung) x 0.8..1.2 ueber seedbaren RNG, damit
## Kaempfe in Tests reproduzierbar sind. Eroberung = gegnerischer Bergfried
## faellt. Rein und headless testbar — kein Node, kein Rendering.

const FACTION_PLAYER: StringName = &"player"
const FACTION_ENEMY: StringName = &"enemy"

## Haltungen: Wache verfolgt nur Feinde nahe dem eigenen Posten,
## Angriff marschiert zum gegnerischen Bergfried.
const STANCE_GUARD: StringName = &"guard"
const STANCE_ASSAULT: StringName = &"assault"

const STATUS_ACTIVE: StringName = &"active"
const STATUS_VICTORY: StringName = &"victory"
const STATUS_DEFEAT: StringName = &"defeat"

## Zufallsspanne der Schadensformel (+-20 %).
const DAMAGE_SPREAD: float = 0.2
## Verfolgungsradius um den Wachposten (Kacheln, Chebyshev).
const GUARD_RANGE: int = 6

## Eine Kampfeinheit (Werte-Schnappschuss aus /data/units.json).
class Unit:
	var id: int = 0
	var type_id: StringName = &""
	var faction: StringName = &""
	var stance: StringName = STANCE_GUARD
	var cell := Vector2i.ZERO
	var home := Vector2i.ZERO  # Wachposten bzw. Marschziel-Basis
	var hp: int = 0
	var max_hp: int = 0
	var attack: int = 0
	var defense: int = 0
	var speed: int = 1
	## Angriffsreichweite in Kacheln (M12): 1 = Nahkampf, >1 = Fernkampf
	## (Bogenschuetze, Kanonier ...).
	var attack_range: int = 1

	func to_dict() -> Dictionary:
		return {
			"id": id, "type_id": String(type_id), "faction": String(faction),
			"stance": String(stance), "cell": [cell.x, cell.y],
			"home": [home.x, home.y], "hp": hp, "max_hp": max_hp, "attack": attack,
			"defense": defense, "speed": speed, "attack_range": attack_range,
		}

	static func from_dict(d: Dictionary) -> Unit:
		var u := Unit.new()
		u.id = int(d.get("id", 0))
		u.type_id = StringName(d.get("type_id", ""))
		u.faction = StringName(d.get("faction", ""))
		u.stance = StringName(d.get("stance", "guard"))
		u.cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
		u.home = Vector2i(int(d["home"][0]), int(d["home"][1]))
		u.hp = int(d.get("hp", 0))
		u.max_hp = int(d.get("max_hp", u.hp))
		u.attack = int(d.get("attack", 0))
		u.defense = int(d.get("defense", 0))
		u.speed = int(d.get("speed", 1))
		u.attack_range = int(d.get("attack_range", 1))
		return u

var units: Array = []  # Array[Unit], Reihenfolge = deterministische Tick-Reihenfolge
var keeps: Dictionary = {}  # faction -> {"cell": Vector2i, "hp": int, "max_hp": int}
## Festungswerke des Spielers (M8): Zelle -> {"def_id", "hp", "max_hp"}.
## Blockieren gegnerische Bewegung; Feinde greifen sie stattdessen an.
var obstacles: Dictionary = {}
var player_stance: StringName = STANCE_GUARD
var status: StringName = STATUS_ACTIVE
var tick_count: int = 0

var _unit_defs: Dictionary = {}  # StringName -> typisierte Werte
var _enemy_unit_type: StringName = &""
var _wave_units: Array = []  # Einheiten-Mix der Angriffswellen (zyklisch)
var _wave_interval: int = 0
var _wave_size: int = 0
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()

## A*-Wegfindung (M9/M-Unendlich): getrennte Gitter je Fraktion, weil Tore nur
## fuer Spieler-Einheiten passierbar sind. Ohne setup_grid (z. B. in aelteren
## Tests) gilt das Legacy-Verhalten: gerade Linie, eigene Werke durchlaessig.
## Mit setup_grid_map WAECHST die Gitter-Region mit dem Geschehen (unendliche
## Karte): verlaesst etwas die Region, wird sie vergroessert neu aufgebaut und
## das Gelaende direkt von der Karte abgefragt.
var _grid_player: AStarGrid2D
var _grid_enemy: AStarGrid2D
var _terrain_map: WorldMap  # Gelaende-Quelle der wachsenden Region (null = festes Gitter)
var _grid_region := Rect2i()

## Reserve rund ums Geschehen beim (Neu-)Aufbau der Gitter-Region.
const GRID_MARGIN: int = 16

## Festes Gitter (Kompatibilitaet): [param blocked_cells] sind unbegehbare
## Gelaendezellen (z. B. Sumpf), die fuer beide Seiten gelten.
func setup_grid(width: int, height: int, blocked_cells: Array) -> void:
	_terrain_map = null
	_grid_region = Rect2i(0, 0, width, height)
	_grid_player = _make_grid(_grid_region, blocked_cells)
	_grid_enemy = _make_grid(_grid_region, blocked_cells)
	for cell in obstacles:
		_set_obstacle_solid(cell)

## Wachsendes Gitter (M-Unendlich): Gelaende kommt aus der Karte, die Region
## startet um [param focus] und waechst bei Bedarf mit.
func setup_grid_map(map: WorldMap, focus: Rect2i) -> void:
	_terrain_map = map
	_rebuild_grids(focus.grow(GRID_MARGIN))

## Vergroessert die Region, falls Zellen ausserhalb liegen (und baut neu auf).
func ensure_grid_covers(cells: Array) -> void:
	if _terrain_map == null or _grid_player == null:
		return
	var region := _grid_region
	var grew := false
	for cell in cells:
		if not region.has_point(cell):
			region = region.expand(cell)
			grew = true
	if grew:
		_rebuild_grids(region.grow(GRID_MARGIN))

## Baut beide Gitter fuer die Region neu: Gelaende-Solids von der Karte,
## danach die Hindernisse (Tore bleiben fuer Spieler frei).
func _rebuild_grids(region: Rect2i) -> void:
	_grid_region = region
	var blocked: Array = []
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, y)
			if not _terrain_map.is_walkable(cell):
				blocked.append(cell)
	_grid_player = _make_grid(region, blocked)
	_grid_enemy = _make_grid(region, blocked)
	for cell in obstacles:
		_set_obstacle_solid(cell)

func _make_grid(region: Rect2i, blocked_cells: Array) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = region
	# Kein Diagonalschritt an Hindernissen vorbei -> kein "Eckenschlupf".
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for cell in blocked_cells:
		grid.set_point_solid(cell, true)
	return grid

func _grid_for(faction: StringName) -> AStarGrid2D:
	return _grid_enemy if faction == FACTION_ENEMY else _grid_player

## Traegt ein Hindernis in die Gitter ein (Tore bleiben fuer Spieler frei).
## Zellen ausserhalb der Region (nur bei festen Legacy-Gittern moeglich)
## werden still uebersprungen — dort gilt ohnehin der Fallback.
func _set_obstacle_solid(cell: Vector2i) -> void:
	if _grid_enemy == null or not _grid_enemy.is_in_boundsv(cell):
		return
	_grid_enemy.set_point_solid(cell, true)
	if not obstacles[cell].get("passable", false):
		_grid_player.set_point_solid(cell, true)

func _clear_obstacle_solid(cell: Vector2i) -> void:
	if _grid_enemy == null or not _grid_enemy.is_in_boundsv(cell):
		return
	_grid_enemy.set_point_solid(cell, false)
	_grid_player.set_point_solid(cell, false)

## Baut den Kampf auf: Bergfriede beider Seiten, Verteidiger des Gegners.
## [param unit_defs] ist das rohe JSON aus units.json, [param enemy_cfg]
## das aus enemy.json (Zellen liefert der Aufrufer kartenabhaengig).
func setup(unit_defs: Dictionary, player_keep: Dictionary, enemy_keep: Dictionary,
		enemy_cfg: Dictionary, rng_seed: int) -> void:
	_unit_defs = _typed_unit_defs(unit_defs)
	_rng.seed = rng_seed
	keeps = {
		FACTION_PLAYER: _make_keep(player_keep),
		FACTION_ENEMY: _make_keep(enemy_keep),
	}
	_read_enemy_cfg(enemy_cfg)
	for i in int(enemy_cfg.get("defenders", 0)):
		add_unit(_enemy_unit_type, FACTION_ENEMY, keeps[FACTION_ENEMY]["cell"],
			STANCE_GUARD, keeps[FACTION_ENEMY]["cell"])

## Wellen-Konfiguration: "units" erlaubt gemischte Wellen (M12), sonst "unit".
func _read_enemy_cfg(enemy_cfg: Dictionary) -> void:
	_enemy_unit_type = StringName(enemy_cfg.get("unit", ""))
	_wave_units.clear()
	for type_id in enemy_cfg.get("units", []):
		_wave_units.append(StringName(type_id))
	if _wave_units.is_empty() and _enemy_unit_type != &"":
		_wave_units.append(_enemy_unit_type)
	_wave_interval = int(enemy_cfg.get("wave_interval_ticks", 0))
	_wave_size = int(enemy_cfg.get("wave_size", 0))

## Fuegt eine Einheit hinzu (auch Rekrutierung). Rueckgabe: die Einheit
## oder null bei unbekanntem Typ.
func add_unit(type_id: StringName, faction: StringName, cell: Vector2i,
		stance: StringName, home: Vector2i) -> Unit:
	var def: Dictionary = _unit_defs.get(type_id, {})
	if def.is_empty():
		return null
	var unit := Unit.new()
	unit.id = _next_id
	_next_id += 1
	unit.type_id = type_id
	unit.faction = faction
	unit.stance = stance
	unit.cell = cell
	unit.home = home
	unit.hp = def["hp"]
	unit.max_hp = def["hp"]
	unit.attack = def["attack"]
	unit.defense = def["defense"]
	unit.speed = def["speed"]
	unit.attack_range = def["attack_range"]
	units.append(unit)
	return unit

## Registriert ein Festungswerk des Spielers als Hindernis.
## [param player_passable]: Tore lassen eigene Einheiten durch.
## [param attack]/[param shot_range]: Fernkampf (M10, 0 = schiesst nicht).
func add_obstacle(cell: Vector2i, def_id: StringName, hp: int, player_passable: bool = false,
		attack: int = 0, shot_range: int = 0) -> void:
	obstacles[cell] = {"def_id": def_id, "hp": hp, "max_hp": hp,
		"passable": player_passable, "attack": attack, "range": shot_range}
	ensure_grid_covers([cell])  # Werke ausserhalb der Region lassen sie wachsen
	_set_obstacle_solid(cell)

## Ruestet ein bestehendes Werk mit Fernkampf nach (FE-Freischaltung).
func set_obstacle_ranged(cell: Vector2i, attack: int, shot_range: int) -> void:
	if obstacles.has(cell):
		obstacles[cell]["attack"] = attack
		obstacles[cell]["range"] = shot_range

## Entfernt ein Festungswerk (M11: Abriss) und gibt den Weg wieder frei.
func remove_obstacle(cell: Vector2i) -> void:
	if obstacles.has(cell):
		obstacles.erase(cell)
		_clear_obstacle_solid(cell)

## Bewegungsbefehl (M13): die Einheit bezieht einen neuen Wachposten und
## marschiert dorthin (Wegfindung inklusive); unterwegs und am Ziel verteidigt
## sie sich gegen Feinde im Wachradius. Rueckgabe: true bei gueltiger Einheit.
func command_move(unit_id: int, cell: Vector2i) -> bool:
	for unit in units:
		if unit.id == unit_id and unit.faction == FACTION_PLAYER and unit.hp > 0:
			ensure_grid_covers([cell])  # Marschziele ohne Weltgrenze (M-Unendlich)
			unit.home = cell
			unit.stance = STANCE_GUARD
			return true
	return false

## Schaltet die Haltung aller Spieler-Einheiten um (Wache <-> Angriff).
func toggle_player_stance() -> StringName:
	player_stance = STANCE_ASSAULT if player_stance == STANCE_GUARD else STANCE_GUARD
	for unit in units:
		if unit.faction == FACTION_PLAYER:
			unit.stance = player_stance
	return player_stance

## Lebende Spieler-Einheiten (belegen Wohnraum in der Economy).
func player_unit_count() -> int:
	var count := 0
	for unit in units:
		if unit.faction == FACTION_PLAYER and unit.hp > 0:
			count += 1
	return count

## Ein Kampfschritt. Rueckgabe: Ereignisliste fuer den Controller
## (z. B. {"type": "wave"}, {"type": "unit_killed", ...}, {"type": "victory"}).
func tick() -> Array:
	if status != STATUS_ACTIVE:
		return []
	tick_count += 1
	var events: Array = []
	if _wave_interval > 0 and _wave_size > 0 and tick_count % _wave_interval == 0:
		_spawn_wave(events)
	_ensure_grid_covers_action()
	for unit in units:
		if unit.hp > 0:
			_act(unit, events)
	_tower_fire(events)
	_collect_deaths(events)
	_check_keeps(events)
	return events

## Region-Wachstum je Tick (M-Unendlich): alle Einheiten samt Zielen und
## beide Bergfriede muessen im Gitter liegen — sonst waechst es.
func _ensure_grid_covers_action() -> void:
	if _terrain_map == null:
		return
	var points: Array = [keeps[FACTION_PLAYER]["cell"], keeps[FACTION_ENEMY]["cell"]]
	for unit in units:
		if unit.hp > 0:
			points.append(unit.cell)
			points.append(unit.home)
	ensure_grid_covers(points)

## Fernkampf der Festungswerke (M10): jeder schiessende Turm feuert einmal
## pro Tick auf den naechsten Feind in Reichweite (gleiche Schadensformel
## wie Einheiten, Verteidigung zaehlt).
func _tower_fire(events: Array) -> void:
	for cell in obstacles:
		var attack := int(obstacles[cell].get("attack", 0))
		if attack <= 0:
			continue
		var target := _nearest_enemy_unit(cell, int(obstacles[cell].get("range", 0)))
		if target == null:
			continue
		var base := maxi(1, attack - target.defense)
		target.hp -= maxi(1, roundi(base * _rng.randf_range(1.0 - DAMAGE_SPREAD, 1.0 + DAMAGE_SPREAD)))
		events.append({"type": "tower_shot", "from": cell, "to": target.cell})

func _nearest_enemy_unit(cell: Vector2i, shot_range: int) -> Unit:
	var best: Unit = null
	for unit in units:
		if unit.faction != FACTION_ENEMY or unit.hp <= 0:
			continue
		if _cheb(cell, unit.cell) > shot_range:
			continue
		if best == null or _cheb(cell, unit.cell) < _cheb(cell, best.cell):
			best = unit
	return best

## Verhalten einer Einheit: Ziel suchen, angreifen (ab M12 auch auf
## Distanz) oder bewegen.
func _act(unit: Unit, events: Array) -> void:
	var target := _select_target(unit)
	if target.is_empty():
		_step_to(unit, unit.home, 0, events)  # zurueck zum Wachposten
		return
	if _cheb(unit.cell, target["cell"]) <= unit.attack_range:
		_strike(unit, target)
	else:
		_step_to(unit, target["cell"], unit.attack_range, events)

## Zielwahl: naechste Feindeinheit; im Angriff zaehlt auch der gegnerische
## Bergfried. Wache verfolgt nur Feinde im GUARD_RANGE um den Posten.
func _select_target(unit: Unit) -> Dictionary:
	var enemy_faction := FACTION_ENEMY if unit.faction == FACTION_PLAYER else FACTION_PLAYER
	var best: Unit = null
	for other in units:
		if other.faction != enemy_faction or other.hp <= 0:
			continue
		if best == null or _cheb(unit.cell, other.cell) < _cheb(unit.cell, best.cell):
			best = other
	if unit.stance == STANCE_GUARD:
		if best != null and _cheb(unit.home, best.cell) <= GUARD_RANGE:
			return {"cell": best.cell, "unit": best}
		return {}
	var keep: Dictionary = keeps[enemy_faction]
	if best != null and _cheb(unit.cell, best.cell) <= _cheb(unit.cell, keep["cell"]):
		return {"cell": best.cell, "unit": best}
	return {"cell": keep["cell"], "keep": enemy_faction}

## Schadensformel gemaess Spezifikation 1.2 (Bergfriede haben Verteidigung 0).
func _strike(attacker: Unit, target: Dictionary) -> void:
	var defense: int = target["unit"].defense if target.has("unit") else 0
	var base := maxi(1, attacker.attack - defense)
	var damage := maxi(1, roundi(base * _rng.randf_range(1.0 - DAMAGE_SPREAD, 1.0 + DAMAGE_SPREAD)))
	if target.has("unit"):
		target["unit"].hp -= damage
	else:
		keeps[target["keep"]]["hp"] = maxi(0, keeps[target["keep"]]["hp"] - damage)

## Bewegt eine Einheit kachelweise Richtung Ziel (speed Schritte pro Tick),
## haelt bei [param stop_distance] an (1 = angrenzend, 0 = auf dem Ziel).
## Mit Gitter (M9): A*-Weg um Mauern/Sumpf herum; gibt es keinen Weg,
## ruecken Feinde geradlinig vor und schlagen eine Bresche ins blockierende
## Werk. Spieler-Einheiten warten vor eigenen Mauern (Tor bauen!).
func _step_to(unit: Unit, destination: Vector2i, stop_distance: int, events: Array) -> void:
	for i in unit.speed:
		if _cheb(unit.cell, destination) <= stop_distance:
			return
		var next := _next_step_cell(unit, destination)
		if next == unit.cell:
			return  # blockiert: warten
		if unit.faction == FACTION_ENEMY and obstacles.has(next):
			_strike_obstacle(unit, next, events)
			return
		unit.cell = next

## Naechste Zelle Richtung Ziel: A*-Pfad, sonst gerade Linie (Fallback und
## Anmarsch auf das blockierende Werk). unit.cell selbst == "kein Schritt".
func _next_step_cell(unit: Unit, destination: Vector2i) -> Vector2i:
	var grid := _grid_for(unit.faction)
	if grid != null and grid.is_in_boundsv(unit.cell) and grid.is_in_boundsv(destination) \
			and not grid.is_point_solid(unit.cell) and not grid.is_point_solid(destination):
		var path := grid.get_id_path(unit.cell, destination)
		if path.size() >= 2:
			return path[1]
	var straight := unit.cell + Vector2i(
		signi(destination.x - unit.cell.x), signi(destination.y - unit.cell.y))
	if grid != null:
		if unit.faction == FACTION_PLAYER:
			# Eigenes undurchlaessiges Werk oder Gelaende: stehen bleiben.
			if obstacles.has(straight) and not obstacles[straight].get("passable", false):
				return unit.cell
			if grid.is_in_boundsv(straight) and grid.is_point_solid(straight):
				return unit.cell
		elif grid.is_in_boundsv(straight) and grid.is_point_solid(straight) and not obstacles.has(straight):
			return unit.cell  # Gelaende blockiert (z. B. Sumpf): warten
	return straight

## Angriff auf ein Festungswerk (Verteidigung 0); Zerstoerung meldet die
## Zelle, damit der Controller das Gebaeude entfernen kann.
func _strike_obstacle(attacker: Unit, cell: Vector2i, events: Array) -> void:
	var damage := maxi(1, roundi(attacker.attack * _rng.randf_range(1.0 - DAMAGE_SPREAD, 1.0 + DAMAGE_SPREAD)))
	obstacles[cell]["hp"] -= damage
	if obstacles[cell]["hp"] <= 0:
		events.append({"type": "structure_destroyed", "cell": cell, "def_id": obstacles[cell]["def_id"]})
		obstacles.erase(cell)
		_clear_obstacle_solid(cell)

## Angriffswelle: Gegner-Einheiten (zyklischer Mix) spawnen am eigenen
## Bergfried und marschieren auf den Spieler-Bergfried zu.
func _spawn_wave(events: Array) -> void:
	force_wave(_wave_size)
	events.append({"type": "wave", "size": _wave_size})

## Welle ausloesen (auch fuer Szenario-Events wie "Krieg", M12).
func force_wave(size: int) -> void:
	if _wave_units.is_empty():
		return
	for i in size:
		add_unit(_wave_units[(tick_count + i) % _wave_units.size()], FACTION_ENEMY,
			keeps[FACTION_ENEMY]["cell"], STANCE_ASSAULT, keeps[FACTION_PLAYER]["cell"])

## Entfernt Gefallene endgueltig (tot ist tot, Spez. Abschnitt 2).
func _collect_deaths(events: Array) -> void:
	var survivors: Array = []
	for unit in units:
		if unit.hp > 0:
			survivors.append(unit)
		else:
			events.append({"type": "unit_killed", "faction": unit.faction, "unit_type": unit.type_id})
	units = survivors

## Sieg/Niederlage pruefen (Spez. 1.3): Bergfried faellt -> Kampf endet.
func _check_keeps(events: Array) -> void:
	if keeps[FACTION_ENEMY]["hp"] <= 0:
		status = STATUS_VICTORY
		events.append({"type": "victory"})
	elif keeps[FACTION_PLAYER]["hp"] <= 0:
		status = STATUS_DEFEAT
		events.append({"type": "defeat"})

## Zustands-Schnappschuss fuer UI und Welt-Darstellung.
func snapshot() -> Dictionary:
	var unit_list: Array = []
	for unit in units:
		unit_list.append({"id": unit.id, "type_id": unit.type_id,
			"faction": unit.faction, "cell": unit.cell, "hp": unit.hp,
			"attack_range": unit.attack_range})
	return {
		"status": status, "stance": player_stance,
		"units": unit_list, "keeps": keeps.duplicate(true),
	}

## Serialisiert den Kampfzustand (RNG-Zustand als String, da int64 die
## JSON-Float-Genauigkeit uebersteigt).
func to_dict() -> Dictionary:
	var unit_list: Array = []
	for unit in units:
		unit_list.append(unit.to_dict())
	var obstacle_list: Array = []
	for cell in obstacles:
		obstacle_list.append({"cell": [cell.x, cell.y], "def_id": String(obstacles[cell]["def_id"]),
			"hp": obstacles[cell]["hp"], "max_hp": obstacles[cell]["max_hp"],
			"passable": obstacles[cell].get("passable", false),
			"attack": obstacles[cell].get("attack", 0), "range": obstacles[cell].get("range", 0)})
	return {
		"units": unit_list,
		"keeps": {
			"player": _keep_to_dict(keeps[FACTION_PLAYER]),
			"enemy": _keep_to_dict(keeps[FACTION_ENEMY]),
		},
		"obstacles": obstacle_list,
		"player_stance": String(player_stance),
		"status": String(status),
		"tick_count": tick_count,
		"next_id": _next_id,
		"rng_state": str(_rng.state),
	}

## Stellt den Kampfzustand wieder her ([param unit_defs]/[param enemy_cfg]
## wie bei [method setup], fuer Werte und Wellen-Konfiguration).
func from_dict(d: Dictionary, unit_defs: Dictionary, enemy_cfg: Dictionary) -> void:
	_unit_defs = _typed_unit_defs(unit_defs)
	_read_enemy_cfg(enemy_cfg)
	units.clear()
	for unit_dict in d.get("units", []):
		units.append(Unit.from_dict(unit_dict))
	keeps = {
		FACTION_PLAYER: _keep_from_dict(d.get("keeps", {}).get("player", {})),
		FACTION_ENEMY: _keep_from_dict(d.get("keeps", {}).get("enemy", {})),
	}
	for cell in obstacles:
		_clear_obstacle_solid(cell)  # alte Eintraege aus den Gittern loesen
	obstacles.clear()
	for entry in d.get("obstacles", []):
		var cell := Vector2i(int(entry["cell"][0]), int(entry["cell"][1]))
		obstacles[cell] = {
			"def_id": StringName(entry.get("def_id", "")),
			"hp": int(entry.get("hp", 1)), "max_hp": int(entry.get("max_hp", 1)),
			"passable": bool(entry.get("passable", false)),
			"attack": int(entry.get("attack", 0)), "range": int(entry.get("range", 0)),
		}
	# Erst die Region ueber alles Geladene spannen, dann Solids setzen
	# (Spielstaende koennen weit ausserhalb des Startgebiets liegen).
	_ensure_grid_covers_action()
	ensure_grid_covers(obstacles.keys())
	for cell in obstacles:
		_set_obstacle_solid(cell)
	player_stance = StringName(d.get("player_stance", "guard"))
	status = StringName(d.get("status", "active"))
	tick_count = int(d.get("tick_count", 0))
	_next_id = int(d.get("next_id", 1))
	_rng.state = int(str(d.get("rng_state", "0")))

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func _make_keep(config: Dictionary) -> Dictionary:
	var hp := int(config.get("hp", 1))
	return {"cell": config.get("cell", Vector2i.ZERO), "hp": hp, "max_hp": hp}

func _keep_to_dict(keep: Dictionary) -> Dictionary:
	return {"cell": [keep["cell"].x, keep["cell"].y], "hp": keep["hp"], "max_hp": keep["max_hp"]}

func _keep_from_dict(d: Dictionary) -> Dictionary:
	var cell: Array = d.get("cell", [0, 0])
	return {"cell": Vector2i(int(cell[0]), int(cell[1])),
		"hp": int(d.get("hp", 1)), "max_hp": int(d.get("max_hp", 1))}

## JSON -> typisierte Einheitenwerte.
func _typed_unit_defs(raw: Dictionary) -> Dictionary:
	var typed: Dictionary = {}
	for key in raw:
		var def: Dictionary = raw[key]
		typed[StringName(key)] = {
			"hp": int(def.get("hp", 1)),
			"attack": int(def.get("attack", 1)),
			"defense": int(def.get("defense", 0)),
			"speed": int(def.get("speed", 1)),
			"attack_range": maxi(1, int(def.get("attack_range", 1))),
		}
	return typed
