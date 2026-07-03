extends RefCounted
## Unit-Tests fuer das sichtbare Dorfleben (M16).
##
## Prueft Bestandsabgleich (ein Bewohner je Arbeiter, stabile IDs), den
## Tageszyklus (raus -> arbeiten -> heim -> drinnen), datengetriebene
## Aufgabenorte (Merkmal aus placement.near) und Determinismus.
## Leere Fehlerliste == bestanden.

const _SEED: int = 1234
const _SIZE: int = 48

## Synthetische Gebaeude-Definitionen: "hut" arbeitet am Baum, "farm" streut.
const _DEFS := {
	"hut": {"placement": {"near": {"feature": "tree", "radius": 3}}},
	"farm": {},
}

var _world: WorldMap

func run() -> Array:
	var failures: Array = []
	_world = WorldMap.new()
	_world.generate(_SEED, _SIZE, _SIZE, Database.biomes)
	_test_sync(failures)
	_test_day_cycle(failures)
	_test_wander_fallback(failures)
	_test_determinism(failures)
	return failures

## Zelle, die frei/begehbar ist und einen Baum im Umkreis 3 hat.
func _hut_cell() -> Vector2i:
	for y in _SIZE:
		for x in _SIZE:
			var cell := Vector2i(x, y)
			if _world.is_walkable(cell) and _world.get_feature(cell) == &"" \
					and _world.has_feature_near(cell, &"tree", 3):
				return cell
	return Vector2i(-1, -1)

## Ein Bewohner je Arbeiter; IDs (und Objekte) bleiben beim Abgleich stabil.
func _test_sync(failures: Array) -> void:
	var life := VillageLife.new()
	var cell := _hut_cell()
	life.sync([{"def_id": &"hut", "cell": cell, "workers": 2}], _DEFS)
	if life.villagers.size() != 2:
		failures.append("Sync: 2 Arbeiter muessen 2 Bewohner ergeben")
	var first: VillageLife.Villager = life.villagers[0]
	life.sync([{"def_id": &"hut", "cell": cell, "workers": 1}], _DEFS)
	if life.villagers.size() != 1 or life.villagers[0] != first:
		failures.append("Sync: Reduktion muss den ersten Bewohner (Objekt) behalten")
	life.sync([], _DEFS)
	if not life.villagers.is_empty():
		failures.append("Sync: ohne Gebaeude keine Bewohner")

## Voller Zyklus: tritt heraus, arbeitet am Baum, kehrt heim, verschwindet.
func _test_day_cycle(failures: Array) -> void:
	var life := VillageLife.new()
	var cell := _hut_cell()
	life.sync([{"def_id": &"hut", "cell": cell, "workers": 1}], _DEFS)
	var villager: VillageLife.Villager = life.villagers[0]
	life.advance(VillageLife.HOME_SECONDS + 0.1, _world)
	if villager.state != VillageLife.STATE_TO_WORK:
		failures.append("Zyklus: muss nach der Heimzeit losgehen")
		return
	if _world.get_feature(Vector2i(villager.target)) != &"tree":
		failures.append("Zyklus: Holzfaeller-Ziel muss ein Baum sein")
	for i in 200:  # genug Schritte fuer Radius 3 bei SPEED-Zellen/s
		life.advance(0.1, _world)
		if villager.state == VillageLife.STATE_WORKING:
			break
	if villager.state != VillageLife.STATE_WORKING or villager.pos != villager.target:
		failures.append("Zyklus: muss am Ziel ankommen und arbeiten")
	life.advance(VillageLife.WORK_SECONDS + 0.1, _world)
	if villager.state != VillageLife.STATE_TO_HOME:
		failures.append("Zyklus: nach der Arbeit geht es heim")
	for i in 200:
		life.advance(0.1, _world)
		if villager.state == VillageLife.STATE_HOME:
			break
	if villager.state != VillageLife.STATE_HOME or villager.pos != villager.home:
		failures.append("Zyklus: muss zu Hause ankommen und verschwinden")

## Ohne Platzierungs-Hinweis: begehbares Streuziel nahe dem Gebaeude.
func _test_wander_fallback(failures: Array) -> void:
	var life := VillageLife.new()
	var cell := _hut_cell()  # begehbar mit begehbarer Umgebung
	life.sync([{"def_id": &"farm", "cell": cell, "workers": 1}], _DEFS)
	var villager: VillageLife.Villager = life.villagers[0]
	life.advance(VillageLife.HOME_SECONDS + 0.1, _world)
	if villager.state != VillageLife.STATE_TO_WORK:
		failures.append("Streuen: muss ein Ziel finden")
		return
	var target := Vector2i(villager.target)
	var delta := target - cell
	if maxi(absi(delta.x), absi(delta.y)) > VillageLife.TASK_RADIUS or target == cell:
		failures.append("Streuen: Ziel muss im Radius liegen und nicht daheim sein")
	if not _world.is_walkable(target):
		failures.append("Streuen: Ziel muss begehbar sein")

## Gleiche Eingaben -> gleiche Ziele (hash-basiert, kein RNG-Zustand).
func _test_determinism(failures: Array) -> void:
	var cell := _hut_cell()
	var targets: Array = []
	for run_index in 2:
		var life := VillageLife.new()
		life.sync([{"def_id": &"hut", "cell": cell, "workers": 3}], _DEFS)
		life.advance(VillageLife.HOME_SECONDS + 0.1, _world)
		var run_targets: Array = []
		for villager in life.villagers:
			run_targets.append(villager.target)
		targets.append(run_targets)
	if targets[0] != targets[1]:
		failures.append("Determinismus: Ziele muessen reproduzierbar sein")
