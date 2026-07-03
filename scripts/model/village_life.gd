class_name VillageLife
extends RefCounted
## VillageLife — sichtbares Dorfleben (M16, goal §3 "reich an Details").
##
## Reine, headless testbare Logik ohne Rendering: je besetztem Arbeitsplatz
## pendelt ein Dorfbewohner zwischen seinem Gebaeude und einem Aufgabenort.
## Der Aufgabenort kommt datengetrieben aus den Platzierungsregeln des
## Gebaeudes (Holzfaeller -> Baum, Fischersteg -> Ufer); ohne Regel streut
## der Bewohner um sein Gebaeude (Bauer auf dem Feld). Positionen sind
## fraktionale Zellkoordinaten — die WorldView uebersetzt in Pixel.
## Zielwahl ist hash-deterministisch (kein RNG-Zustand noetig).

const STATE_HOME := &"home"          # im Gebaeude (unsichtbar)
const STATE_TO_WORK := &"to_work"    # unterwegs zum Aufgabenort
const STATE_WORKING := &"working"    # arbeitet am Aufgabenort
const STATE_TO_HOME := &"to_home"    # auf dem Heimweg

## Gehtempo in Zellen pro Sekunde und Verweildauern in Sekunden.
const SPEED: float = 0.8
const WORK_SECONDS: float = 6.0
const HOME_SECONDS: float = 3.0
## Streu-Radius um das Gebaeude, wenn keine Platzierungsregel ein Ziel vorgibt.
const TASK_RADIUS: int = 2

## Ein Bewohner; Positionen in (fraktionalen) Zellkoordinaten.
class Villager:
	extends RefCounted
	var id: String
	var def_id: StringName
	var home: Vector2
	var pos: Vector2
	var target: Vector2
	var state: StringName = VillageLife.STATE_HOME
	var timer: float = 0.0
	var trips: int = 0    # zaehlt Ausfluege -> Salz fuer die naechste Zielwahl
	var phase: float = 0.0  # Animations-Versatz fuer die View (0..TAU)
	var task_feature: StringName = &""
	var task_biome: StringName = &""
	var task_radius: int = VillageLife.TASK_RADIUS

var villagers: Array = []

## Gleicht den Bestand mit der Siedlung ab: je Arbeiter eines Gebaeudes ein
## Bewohner (stabile IDs — bestehende behalten Position und Zustand).
## [param building_list]: [{def_id, cell, workers}], [param building_defs]:
## rohe Gebaeude-Definitionen (fuer die Aufgaben-Hinweise aus "placement").
func sync(building_list: Array, building_defs: Dictionary) -> void:
	var desired: Dictionary = {}
	for entry in building_list:
		var def: Dictionary = building_defs.get(String(entry["def_id"]), {})
		for i in int(entry.get("workers", 0)):
			var cell: Vector2i = entry["cell"]
			var id := "%s@%d,%d#%d" % [entry["def_id"], cell.x, cell.y, i]
			desired[id] = {"def_id": StringName(entry["def_id"]), "cell": cell, "def": def}
	var kept: Array = []
	for villager in villagers:
		if desired.has(villager.id):
			kept.append(villager)
			desired.erase(villager.id)
	for id in desired:
		kept.append(_spawn(id, desired[id]))
	villagers = kept

## Bewegt alle Bewohner um [param delta] Sekunden weiter (Zustandsmaschine
## gehen -> arbeiten -> heimgehen -> im Haus). Braucht die Karte fuer die
## Zielwahl beim naechsten Ausflug.
func advance(delta: float, map: WorldMap) -> void:
	for villager in villagers:
		match villager.state:
			STATE_HOME:
				villager.timer -= delta
				if villager.timer <= 0.0:
					_depart(villager, map)
			STATE_WORKING:
				villager.timer -= delta
				if villager.timer <= 0.0:
					villager.state = STATE_TO_HOME
					villager.target = villager.home
			STATE_TO_WORK, STATE_TO_HOME:
				_walk(villager, delta)

## Neuer Bewohner startet im Gebaeude; Timer/Phase hash-gestreut, damit nicht
## alle gleichzeitig aus der Tuer treten.
func _spawn(id: String, info: Dictionary) -> Villager:
	var villager := Villager.new()
	villager.id = id
	villager.def_id = info["def_id"]
	villager.home = Vector2(info["cell"])
	villager.pos = villager.home
	villager.target = villager.home
	var jitter := absi(hash(id)) % 100 / 100.0
	villager.timer = HOME_SECONDS * jitter
	villager.phase = TAU * jitter
	var placement: Dictionary = info["def"].get("placement", {})
	villager.task_feature = StringName(placement.get("near", {}).get("feature", ""))
	villager.task_biome = StringName(placement.get("near_biome", {}).get("biome", ""))
	villager.task_radius = int(placement.get("near", {}).get("radius",
		placement.get("near_biome", {}).get("radius", TASK_RADIUS)))
	return villager

## Naechster Ausflug: Ziel waehlen; ohne erreichbares Ziel bleibt der
## Bewohner drinnen und versucht es spaeter erneut.
func _depart(villager: Villager, map: WorldMap) -> void:
	var task := _pick_task(villager, map)
	villager.trips += 1
	if task == villager.home:
		villager.timer = HOME_SECONDS
		return
	villager.state = STATE_TO_WORK
	villager.target = task

## Schritt Richtung Ziel; Ankunft schaltet den Zustand weiter.
func _walk(villager: Villager, delta: float) -> void:
	var to_target: Vector2 = villager.target - villager.pos
	var step := SPEED * delta
	if to_target.length() > step:
		villager.pos += to_target.normalized() * step
		return
	villager.pos = villager.target
	if villager.state == STATE_TO_WORK:
		villager.state = STATE_WORKING
		villager.timer = WORK_SECONDS
	else:
		villager.state = STATE_HOME
		villager.timer = HOME_SECONDS

## Aufgabenort (deterministisch aus id + Ausflugszaehler):
## Merkmal-Ziel (Baum/Fels) > Ufer-Ziel (near_biome) > Streuen ums Gebaeude.
func _pick_task(villager: Villager, map: WorldMap) -> Vector2:
	var home := Vector2i(villager.home)
	var candidates: Array = []
	for cell in _cells_in_radius(home, villager.task_radius, map):
		if villager.task_feature != &"":
			if map.get_feature(cell) == villager.task_feature:
				candidates.append(cell)
		elif villager.task_biome != &"":
			if map.is_walkable(cell) and map.has_biome_near(cell, villager.task_biome, 1):
				candidates.append(cell)
		elif map.is_walkable(cell) and cell != home:
			candidates.append(cell)
	if candidates.is_empty():
		return villager.home
	var pick: Vector2i = candidates[absi(hash("%s:%d" % [villager.id, villager.trips])) % candidates.size()]
	return Vector2(pick)

## Alle Zellen im Quadrat-Radius um das Zentrum (inkl. Zentrum) — die Welt
## ist seit M-Unendlich grenzenlos, es gibt keinen Kartenrand-Filter mehr.
func _cells_in_radius(center: Vector2i, radius: int, _map: WorldMap) -> Array:
	var cells: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			cells.append(center + Vector2i(dx, dy))
	return cells
