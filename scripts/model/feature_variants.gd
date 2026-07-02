class_name FeatureVariants
extends RefCounted
## FeatureVariants — waehlt deterministisch eine VISUELLE Variante eines
## Gameplay-Merkmals (§8.2). Beispiel: die Zelle bleibt spielmechanisch "rock"
## (Steinbruch, has_feature_near), wird aber als "rock_boulder", "rock_mossy" ...
## gezeichnet. Rein kosmetisch — das Spielmodell (get_feature) bleibt unberuehrt.
##
## Tabelle aus /data/feature_variants.json: Merkmal-ID -> [Varianten-IDs]. Merkmale
## ohne Eintrag liefern sich selbst zurueck (unveraendertes Rendering).

## Visuelle Varianten-ID (StringName) fuer [param feature] auf [param cell];
## stabil ueber Sessions (Seed + Zelle). [param variant_defs] ist die Tabelle,
## [param seed_value] der Karten-Seed.
static func pick(feature: StringName, cell: Vector2i, variant_defs: Dictionary, seed_value: int) -> StringName:
	var variants: Array = variant_defs.get(String(feature), [])
	if variants.is_empty():
		return feature
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("variant:%d:%d:%d" % [seed_value, cell.x, cell.y])
	return StringName(variants[rng.randi_range(0, variants.size() - 1)])
