extends Node
## AssetRegistry — zentrales Register fuer alle Grafiken (M4, siehe goal §3).
##
## Einzige Bezugsquelle fuer Texturen: liegt unter res://assets/<id>.png eine
## echte Grafik (spaetere Pixelart), wird sie geladen — sonst wird ein
## Platzhalter generiert. Dadurch sind Assets jederzeit austauschbar, ohne
## dass Spielcode angefasst werden muss.
##
## Namenskonvention: "tile_<biom>", "feature_<merkmal>", "building_<id>",
## "unit_<typ>", "resource_<id>" (HUD-/Kosten-Icon), "npc_<id>" (Portraet) und
## "animal_<typ>" (Ambient-Tiere). Die Platzhalterform richtet sich nach dem Praefix.

## Groesse einer Iso-Bodenkachel (Diamant) in Pixeln.
const TILE_SIZE: Vector2i = Vector2i(64, 32)

## Naturfarbene Platzhalterfarben fuer bekannte IDs; unbekannte IDs bekommen
## eine deterministische Farbe aus ihrem Namens-Hash.
const _PLACEHOLDER_COLORS: Dictionary = {
	&"feature_tree": Color("#3e6b34"),
	&"feature_rock": Color("#736d64"),
	&"feature_flowers": Color("#d9678f"),
	&"feature_grass_tuft": Color("#5f9440"),
	&"feature_bush": Color("#3f6b30"),
	&"feature_fern": Color("#4a7a3a"),
	&"feature_mushroom": Color("#b05a3c"),
	&"feature_reeds": Color("#7a8a3e"),
	&"feature_deadwood": Color("#6e5a3e"),
	&"feature_ruins": Color("#7d756a"),
	&"feature_well": Color("#6f7d86"),
	&"feature_haystack": Color("#cfa94e"),
	&"feature_fence": Color("#8a6a42"),
	&"feature_rock_small": Color("#837d73"),
	&"feature_rock_boulder": Color("#6b665d"),
	&"feature_rock_cluster": Color("#7a746a"),
	&"feature_rock_mossy": Color("#6a7358"),
	&"feature_pebbles": Color("#8b857a"),
	&"feature_crystal": Color("#8fb3c9"),
	&"feature_cliff": Color("#5f5a52"),
	&"feature_snow_drift": Color("#eef2f5"),
	&"feature_ice": Color("#b9d8e6"),
	&"feature_mountain_rocky": Color("#6f6a61"),
	&"feature_mountain_snowy": Color("#8a857c"),
	&"building_woodcutter": Color("#8a5a2b"),
	&"building_wheat_farm": Color("#d9b13b"),
	&"building_bakery": Color("#c07840"),
	&"building_house": Color("#a8794a"),
	&"building_quarry": Color("#8d8d8d"),
	&"building_brewery": Color("#6b4f2e"),
	&"building_keep": Color("#5a5f66"),
	&"building_wall": Color("#77787c"),
	&"building_tower": Color("#4c4f57"),
	&"building_gate": Color("#7a5a33"),
	&"unit_villager": Color("#4a6d8c"),
	&"unit_swordsman": Color("#3f6bab"),
	&"unit_raider": Color("#a03c3c"),
	&"resource_wood": Color("#7a5230"),
	&"resource_wheat": Color("#d9b13b"),
	&"resource_bread": Color("#c98a4b"),
	&"resource_stone": Color("#8d8d8d"),
	&"resource_beer": Color("#b9822f"),
	&"npc_baumeister": Color("#9a7b52"),
	&"tile_farmland": Color("#b98c4a"),
	&"tile_water_deep": Color("#2f6b8f"),
	&"tile_water_shallow": Color("#4f97b8"),
	&"tile_river": Color("#3f80a8"),
	&"feature_lilypad": Color("#5c9a4a"),
	&"ui_demolish": Color("#c23b3b"),
	&"animal_deer": Color("#a5764b"),
	&"animal_rabbit": Color("#b9a48a"),
	&"animal_fox": Color("#c8632a"),
	&"animal_boar": Color("#5f5148"),
	&"animal_bird": Color("#45484d"),
	&"animal_frog": Color("#5f8a3e"),
	&"animal_butterfly": Color("#d98cc0"),
	&"animal_cow": Color("#8a6b4f"),
	&"animal_sheep": Color("#dcd6cc"),
	&"animal_chicken": Color("#cf9f5a"),
}

var _cache: Dictionary = {}  # StringName -> Texture2D

## Liefert die Textur zu einer Asset-ID (Datei vor Platzhalter, gecacht).
func get_texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path := "res://assets/%s.png" % id
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		texture = _make_placeholder(id)
	_cache[id] = texture
	return texture

## Erzeugt den Platzhalter passend zum ID-Praefix.
func _make_placeholder(id: StringName) -> Texture2D:
	var text := String(id)
	if text.begins_with("tile_"):
		# Explizite Kachel-Farbe (z. B. Acker, kein Biom) geht vor der Biom-Farbe.
		if _PLACEHOLDER_COLORS.has(id):
			return _make_diamond(_PLACEHOLDER_COLORS[id])
		return _make_diamond(_tile_color(text.trim_prefix("tile_")))
	if text.begins_with("feature_mountain"):
		# Grosse Kulisse: mehrkacheliges Dreieck, ggf. mit Schneekappe.
		return _make_mountain(_color_for(id), text.contains("snow"))
	if text.begins_with("feature_"):
		return _make_dot(_color_for(id), 10)
	if text.begins_with("unit_"):
		return _make_box(_color_for(id), Vector2i(12, 18))
	if text.begins_with("animal_"):
		return _make_box(_color_for(id), Vector2i(16, 12))
	if text.begins_with("resource_"):
		return _make_box(_color_for(id), Vector2i(24, 24))
	if text.begins_with("npc_"):
		return _make_box(_color_for(id), Vector2i(64, 64))
	return _make_box(_color_for(id), Vector2i(40, 40))

## Kachel-Farbe kommt aus biomes.json; Fallback: Hash-Farbe.
func _tile_color(biome_id: String) -> Color:
	var def: Dictionary = Database.biomes.get(biome_id, {})
	var html: String = def.get("color", "")
	return Color.html(html) if Color.html_is_valid(html) else _color_for(StringName(biome_id))

## Deterministische Ersatzfarbe aus dem Namen (stabil ueber Sessions).
func _color_for(id: StringName) -> Color:
	if _PLACEHOLDER_COLORS.has(id):
		return _PLACEHOLDER_COLORS[id]
	return Color.from_hsv(float(hash(String(id)) % 360) / 360.0, 0.35, 0.72)

## Diamantfoermige Iso-Bodenkachel mit dezent dunklerem Rand.
func _make_diamond(color: Color) -> Texture2D:
	var image := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	var half_h := TILE_SIZE.y / 2.0
	for y in TILE_SIZE.y:
		var row_ratio := 1.0 - absf(y - half_h + 0.5) / half_h
		var half_width := row_ratio * TILE_SIZE.x / 2.0
		for x in TILE_SIZE.x:
			var dist := absf(x - TILE_SIZE.x / 2.0 + 0.5)
			if dist <= half_width:
				var edge := half_width - dist < 2.0
				image.set_pixel(x, y, color.darkened(0.25) if edge else color)
	return ImageTexture.create_from_image(image)

## Gefuellter Kreis (Merkmale wie Baum/Fels), zentriert auf Kachelgroesse.
func _make_dot(color: Color, radius: int) -> Texture2D:
	var image := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(TILE_SIZE.x / 2.0, TILE_SIZE.y / 2.0)
	for y in TILE_SIZE.y:
		for x in TILE_SIZE.x:
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

## Gefuelltes Rechteck mit dunklerem Rand (Gebaeude, Einheiten).
func _make_box(color: Color, size: Vector2i) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var edge := x < 2 or y < 2 or x >= size.x - 2 or y >= size.y - 2
			image.set_pixel(x, y, color.darkened(0.35) if edge else color)
	return ImageTexture.create_from_image(image)

## Groesse einer grossen Bergkulisse (mehrere Kacheln breit/hoch).
const MOUNTAIN_SIZE: Vector2i = Vector2i(128, 96)

## Dreieckige Berg-Silhouette (Spitze oben, Basis unten), dunklerer Rand,
## optional mit Schneekappe im oberen Drittel. Platzhalter fuer die Pixelart.
func _make_mountain(color: Color, snow_capped: bool) -> Texture2D:
	var w := MOUNTAIN_SIZE.x
	var h := MOUNTAIN_SIZE.y
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var peak_x := w / 2.0
	var snow := Color("#eef2f5")
	for y in h:
		var t := float(y) / float(h)          # 0 = Spitze, 1 = Basis
		var half := t * (w / 2.0 - 2.0)
		for x in w:
			var d := absf(x - peak_x + 0.5)
			if d > half:
				continue
			if half - d < 2.0:
				image.set_pixel(x, y, color.darkened(0.3))   # Rand/Kontur
			elif snow_capped and t < 0.32:
				image.set_pixel(x, y, snow)                    # Schneekappe
			else:
				image.set_pixel(x, y, color if int(x + y) % 7 != 0 else color.darkened(0.12))
	return ImageTexture.create_from_image(image)
