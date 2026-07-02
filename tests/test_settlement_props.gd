extends RefCounted
## Unit-Tests fuer die Siedlungs-Kleindeko (§8.6).
##
## Prueft, dass Requisiten aus dem "props"-Feld der Gebaeude auf Nachbarzellen
## landen, Gebaeude ohne "props" keine erzeugen, und alles deterministisch ist.
## Nutzt die echten Definitionen aus Database.buildings.

func run() -> Array:
	var failures: Array = []
	_test_props_near_building(failures)
	_test_no_props_without_field(failures)
	_test_deterministic(failures)
	return failures

func _buildings() -> Array:
	return [
		{"def_id": &"keep", "cell": Vector2i(10, 10)},
		{"def_id": &"wheat_farm", "cell": Vector2i(20, 20)},
		{"def_id": &"house", "cell": Vector2i(30, 30)},
	]

## Jedes Prop steht direkt neben seinem Gebaeude und stammt aus dessen props-Feld.
func _test_props_near_building(failures: Array) -> void:
	var props := SettlementProps.props_for(_buildings(), Database.buildings)
	var expect := {&"keep": &"well", &"wheat_farm": &"haystack", &"house": &"fence"}
	var cell_of := {&"keep": Vector2i(10, 10), &"wheat_farm": Vector2i(20, 20), &"house": Vector2i(30, 30)}
	if props.size() != 3:
		failures.append("Props: erwartet 3, erhalten %d" % props.size())
		return
	var seen := {}
	for prop in props:
		seen[prop["type"]] = prop["cell"]
	for building_id in expect:
		var prop_type: StringName = expect[building_id]
		if not seen.has(prop_type):
			failures.append("Props: %s (fuer %s) fehlt" % [prop_type, building_id])
			continue
		var b: Vector2i = cell_of[building_id]
		var dist := maxi(absi(seen[prop_type].x - b.x), absi(seen[prop_type].y - b.y))
		if dist != 1:
			failures.append("Props: %s nicht direkt neben %s (Abstand %d)" % [prop_type, building_id, dist])

## Gebaeude ohne "props" (Holzfaeller) erzeugen keine Requisiten.
func _test_no_props_without_field(failures: Array) -> void:
	var props := SettlementProps.props_for([{"def_id": &"woodcutter", "cell": Vector2i(5, 5)}], Database.buildings)
	if not props.is_empty():
		failures.append("Props: Holzfaeller darf keine Requisiten haben")

## Zweiter Aufruf liefert identische Requisiten (kein RNG).
func _test_deterministic(failures: Array) -> void:
	var a := SettlementProps.props_for(_buildings(), Database.buildings)
	var b := SettlementProps.props_for(_buildings(), Database.buildings)
	if a.size() != b.size():
		failures.append("Props: nicht deterministisch (Anzahl)")
		return
	for i in a.size():
		if a[i]["type"] != b[i]["type"] or a[i]["cell"] != b[i]["cell"]:
			failures.append("Props: Eintrag %d weicht ab" % i)
			return
