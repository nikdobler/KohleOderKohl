class_name SettlementProps
extends RefCounted
## SettlementProps — deterministische Kleindeko neben Gebaeuden (§8.6).
##
## Reine, headless testbare Logik: liest je Gebaeude das Feld "props" aus der
## Gebaeude-Definition (buildings.json) und setzt die Requisiten auf feste
## Nachbarzellen (z. B. Brunnen am Bergfried, Heuhaufen am Weizenfeld, Zaun am
## Wohnhaus). Rein kosmetisch — blockiert nichts, aendert kein Gameplay.

## Feste Nachbar-Offsets rund ums Gebaeude (kein RNG -> voll deterministisch).
const _OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
]

## Requisiten fuer alle Gebaeude der Liste als [{"type": StringName, "cell": Vector2i}].
## [param building_list] sind die Eintraege aus buildings_changed ({def_id, cell}),
## [param building_defs] das rohe JSON aus buildings.json (Database.buildings).
static func props_for(building_list: Array, building_defs: Dictionary) -> Array:
	var result: Array = []
	for entry in building_list:
		var def: Dictionary = building_defs.get(String(entry["def_id"]), {})
		var props: Array = def.get("props", [])
		for i in props.size():
			var cell: Vector2i = entry["cell"] + _OFFSETS[i % _OFFSETS.size()]
			result.append({"type": StringName(props[i]), "cell": cell})
	return result
