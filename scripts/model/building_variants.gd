class_name BuildingVariants
extends RefCounted
## BuildingVariants — waehlt deterministisch eine VISUELLE Stilvariante eines
## Gebaeudes je Siedlungstyp (M-Gebaeudevarianten), analog [FeatureVariants].
## Rein kosmetisch: die Gameplay-Definition (def_id) bleibt unberuehrt, nur das
## gezeichnete Sprite wechselt.
##
## Tabelle aus data/settlement_types.json:
##   types.<settlement_type>.building_variants.<def_id> -> [Varianten-IDs]
## Fehlt der Eintrag (unbekannter Siedlungstyp / Gebaeude ohne Varianten),
## liefert [method pick] &"" = Basis-Sprite.

## Varianten-ID (StringName) fuer ein Gebaeude; &"" = Basis. Stabil je
## Instanz-ID + Welt-Seed — jedes Gebaeude wuerfelt unabhaengig und
## positionsfrei (anders als FeatureVariants, das die Zelle nutzt).
static func pick(def_id: StringName, instance_id: int, settlement_type: StringName,
		defs: Dictionary, seed_value: int) -> StringName:
	var types: Dictionary = defs.get("types", {})
	var type_def: Dictionary = types.get(String(settlement_type), {})
	var by_building: Dictionary = type_def.get("building_variants", {})
	var variants: Array = by_building.get(String(def_id), [])
	if variants.is_empty():
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bvariant:%d:%d" % [seed_value, instance_id])
	return StringName(variants[rng.randi_range(0, variants.size() - 1)])
