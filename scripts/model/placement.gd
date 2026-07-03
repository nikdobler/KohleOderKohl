class_name Placement
extends RefCounted
## Placement — datengetriebene Platzierungsregeln fuer das Bau-System (M8).
##
## Jedes baubare Gebaeude traegt in buildings.json einen "placement"-Block:
##   "biomes": erlaubte Untergruende (leer/fehlend = alle)
##   "on_feature": "none" (Zelle muss frei sein, Standard) | "rock" (muss auf
##                 Fels stehen, z. B. Steinbruch) | "rock_or_none" (frei ODER
##                 Fels, z. B. Festungswerke)
##   "near": {"feature": ..., "radius": N} — braucht ein Merkmal in der Naehe
##           (z. B. Holzfaeller braucht Baeume)
##   "near_biome": {"biome": ..., "radius": N} — braucht ein Biom in der Naehe
##           (M13: z. B. Fischersteg braucht Wasser)
## Rein und headless testbar; liefert deutsche Begruendungen fuer die UI.

const _FEATURE_NAMES: Dictionary = {
	&"tree": "Bäume",
	&"rock": "Fels",
}
const _BIOME_NAMES: Dictionary = {
	&"water": "Wasser",
	&"swamp": "Sumpf",
}

## Prueft, ob [param def] auf [param cell] gebaut werden darf.
## [param occupied] ist die Menge belegter Zellen (Vector2i -> true).
## Rueckgabe: {"ok": bool, "reason": String}.
static func can_place(def: Dictionary, cell: Vector2i, world: WorldMap, occupied: Dictionary) -> Dictionary:
	var placement: Dictionary = def.get("placement", {})
	if placement.is_empty():
		return _no("Dieses Gebäude ist nicht baubar.")
	if world.get_biome(cell) == &"":
		return _no("Ausserhalb der Karte.")
	if not world.is_walkable(cell):
		return _no("Auf diesem Untergrund lässt sich nicht bauen.")
	if occupied.has(cell):
		return _no("Hier steht schon etwas.")
	var biomes: Array = placement.get("biomes", [])
	if not biomes.is_empty() and not biomes.has(String(world.get_biome(cell))):
		return _no("Falscher Untergrund.")
	var feature_check := _check_feature(placement, world.get_feature(cell))
	if not feature_check["ok"]:
		return feature_check
	return _check_near(placement, cell, world)

## Untergrund-Merkmal der Zelle gegen die on_feature-Regel pruefen.
static func _check_feature(placement: Dictionary, feature: StringName) -> Dictionary:
	match String(placement.get("on_feature", "none")):
		"none":
			if feature != &"":
				return _no("Der Bauplatz ist nicht frei.")
		"rock":
			if feature != &"rock":
				return _no("Braucht festen Fels als Untergrund.")
		"rock_or_none":
			if feature != &"" and feature != &"rock":
				return _no("Der Bauplatz ist nicht frei.")
		var unknown:
			push_warning("Placement: unbekannte on_feature-Regel '%s'" % unknown)
			return _no("Ungültige Bauregel.")
	return {"ok": true, "reason": ""}

## Umgebungs-Anforderungen pruefen (Merkmal und/oder Biom im Radius).
static func _check_near(placement: Dictionary, cell: Vector2i, world: WorldMap) -> Dictionary:
	var near: Dictionary = placement.get("near", {})
	if not near.is_empty():
		var feature := StringName(near.get("feature", ""))
		if not world.has_feature_near(cell, feature, int(near.get("radius", 1))):
			return _no("Braucht %s in der Nähe." % _FEATURE_NAMES.get(feature, String(feature)))
	var near_biome: Dictionary = placement.get("near_biome", {})
	if not near_biome.is_empty():
		var biome := StringName(near_biome.get("biome", ""))
		if not world.has_biome_near(cell, biome, int(near_biome.get("radius", 1))):
			return _no("Braucht %s in der Nähe." % _BIOME_NAMES.get(biome, String(biome)))
	return {"ok": true, "reason": ""}

static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
