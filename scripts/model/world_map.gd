class_name WorldMap
extends RefCounted
## WorldMap — deterministische Kartengenerierung (M4).
##
## Reine, headless testbare Logik ohne Rendering: erzeugt aus einem Seed eine
## Biom-Verteilung (Simplex-Noise) plus Ressourcen-Merkmale (Baeume, Felsen)
## gemaess datengetriebener Dichten aus /data/biomes.json. Gleicher Seed ->
## exakt gleiche Karte; deshalb genuegt es, im Spielstand nur Seed und
## Groesse zu sichern (siehe [method to_dict]).

## Frequenz des Biom-Rauschens (kleiner = groessere zusammenhaengende Gebiete).
const NOISE_FREQUENCY: float = 0.06

var seed_value: int = 0
var width: int = 0
var height: int = 0

var _biome_defs: Array = []   # [{id, noise_max, features, decor}]
var _cell_biomes: Array = []  # StringName je Zelle (Index y*width+x)
var _cell_features: Array = []  # StringName je Zelle (&"" = kein Merkmal)
var _cell_decor: Array = []   # StringName je Zelle: rein dekoratives GrUenzeug (&"" = keines)
var _cell_elevation: Array = []  # float je Zelle: Roh-Rauschwert (fuer Flusslauf)
var _cell_river: Array = []   # bool je Zelle: Teil eines Flusses (unbegehbar)
var _passable_biomes: Dictionary = {}  # Biom-ID -> bool (Standard: begehbar)
var _noise: FastNoiseLite  # bleibt nach generate() erhalten (peek_* ausserhalb der Karte)

## Flusslauf (§8.3): Anzahl Quellen, Mindesthoehe einer Quelle, Laengenlimit.
const RIVER_COUNT: int = 2
const RIVER_SOURCE_MIN: float = 0.3

## Erzeugt die Karte. [param biome_defs] ist das rohe JSON-Dictionary aus
## biomes.json; die Reihenfolge der Eintraege bestimmt die Noise-Zuordnung.
func generate(p_seed: int, p_width: int, p_height: int, biome_defs: Dictionary) -> void:
	seed_value = p_seed
	width = p_width
	height = p_height
	_biome_defs = _typed_biome_defs(biome_defs)
	_cell_biomes.resize(width * height)
	_cell_features.resize(width * height)
	_cell_decor.resize(width * height)
	_cell_elevation.resize(width * height)
	_cell_river.resize(width * height)
	var _n := FastNoiseLite.new()
	_n.seed = p_seed
	_n.frequency = NOISE_FREQUENCY
	_noise = _n
	for y in height:
		for x in width:
			var elevation := _noise.get_noise_2d(x, y)
			var biome := _pick_biome(elevation)
			var idx := y * width + x
			var feature := _roll_feature(x, y, biome)
			_cell_biomes[idx] = biome
			_cell_features[idx] = feature
			_cell_elevation[idx] = elevation
			# Dekor nur auf merkmalfreien Zellen (belebt kahle Flaechen, blockiert nichts).
			_cell_decor[idx] = _roll_decor(x, y, biome) if feature == &"" else &""
	_generate_rivers()

## Biom einer Zelle (&"" ausserhalb der Karte).
func get_biome(cell: Vector2i) -> StringName:
	if not _in_bounds(cell):
		return &""
	return _cell_biomes[cell.y * width + cell.x]

## Biom OHNE Kartengrenze (M17): ausserhalb wird dieselbe Noise-Welt
## weitergerechnet — fuer die rein visuelle Randlandschaft, damit die Karte
## endlos wirkt. Kein Spielinhalt: Merkmale/Fluesse gibt es dort nicht.
func peek_biome(cell: Vector2i) -> StringName:
	if _in_bounds(cell):
		return _cell_biomes[cell.y * width + cell.x]
	if _noise == null:
		return &""
	return _pick_biome(_noise.get_noise_2d(cell.x, cell.y))

## Dekor OHNE Kartengrenze (M17): gleicher Wuerfel-Kanal wie im Inneren.
func peek_decor(cell: Vector2i) -> StringName:
	if _in_bounds(cell):
		return get_decor(cell)
	return _roll_decor(cell.x, cell.y, peek_biome(cell))

## Ressourcen-Merkmal einer Zelle (&"" = keines/ausserhalb).
func get_feature(cell: Vector2i) -> StringName:
	if not _in_bounds(cell):
		return &""
	return _cell_features[cell.y * width + cell.x]

## Rein dekoratives Gruenzeug einer Zelle (&"" = keines/ausserhalb). Hat KEINE
## Spielwirkung: blockiert weder Bau noch Bewegung, ist nur Anzeige.
func get_decor(cell: Vector2i) -> StringName:
	if not _in_bounds(cell):
		return &""
	return _cell_decor[cell.y * width + cell.x]

## Ist die Zelle Teil eines Flusses? (unbegehbar; ausserhalb der Karte = false)
func is_river(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	return _cell_river[cell.y * width + cell.x]

## Roh-Hoehe (Rauschwert) einer Zelle; ausserhalb der Karte = 0.
func get_elevation(cell: Vector2i) -> float:
	if not _in_bounds(cell):
		return 0.0
	return _cell_elevation[cell.y * width + cell.x]

## 4-Bit-Kantenmaske fuer Autotiling (§8.3): welche der vier Iso-Seitennachbarn
## zur "Wassergruppe" (Wasser ODER Fluss) gehoeren. Gesetztes Bit = Innenkante
## (nahtloser Uebergang), geloeschtes Bit = Uferkante (Land / Kartenrand).
## Bit 1 = oben-rechts (0,-1), 2 = unten-rechts (1,0), 4 = unten-links (0,1),
## 8 = oben-links (-1,0) — passend zur Diamant-Kachel (DIAMOND_DOWN).
func water_edge_mask(cell: Vector2i) -> int:
	var mask := 0
	if _is_water_group(cell + Vector2i(0, -1)): mask |= 1
	if _is_water_group(cell + Vector2i(1, 0)): mask |= 2
	if _is_water_group(cell + Vector2i(0, 1)): mask |= 4
	if _is_water_group(cell + Vector2i(-1, 0)): mask |= 8
	return mask

## Gehoert die Zelle zur Wassergruppe (See oder Fluss)? Kartenrand = nein.
func _is_water_group(cell: Vector2i) -> bool:
	return get_biome(cell) == &"water" or is_river(cell)

## Ufer-Wasserzelle? (Wasser mit mindestens einem Nicht-Wasser-Nachbarn, inkl.
## Kartenrand). Rendert als Flachwasser; Wasser ohne Landnachbar als Tiefwasser.
func is_water_shore(cell: Vector2i) -> bool:
	if get_biome(cell) != &"water":
		return false
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_biome(cell + dir) != &"water":  # &"" (ausserhalb) zaehlt als Land
			return true
	return false

## Ist die Zelle fuer Einheiten begehbar? (Biom-Flag "passable", z. B.
## Sumpf/Wasser = false; Fluesse blockieren ebenfalls; ausserhalb = false.)
func is_walkable(cell: Vector2i) -> bool:
	if not _in_bounds(cell):
		return false
	if _cell_river[cell.y * width + cell.x]:
		return false
	return _passable_biomes.get(get_biome(cell), true)

## Alle unbegehbaren Zellen (fuer das Pathfinding-Gitter des Kampfsystems).
func impassable_cells() -> Array:
	var cells: Array = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if not is_walkable(cell):
				cells.append(cell)
	return cells

## Mindestabstand zwischen Bauplaetzen (Chebyshev), damit Gebaeude nicht
## aneinanderkleben.
const SLOT_SPACING: int = 2

## Deterministische Bauplaetze: freie Zellen (ohne Merkmal) mit Mindestabstand,
## ringfoermig von der Kartenmitte nach aussen. Stabil: die ersten N Plaetze
## aendern sich nicht, wenn spaeter mehr angefordert werden.
func building_slots(count: int) -> Array:
	var slots: Array = []
	var center := Vector2i(width / 2, height / 2)
	var radius := 0
	var max_radius := maxi(width, height)
	while slots.size() < count and radius <= max_radius:
		for cell in _ring_cells(center, radius):
			if is_walkable(cell) and get_feature(cell) == &"" and _far_from_all(cell, slots):
				slots.append(cell)
				if slots.size() == count:
					break
		radius += 1
	return slots

## Gibt es das Merkmal im (quadratischen) Umkreis um die Zelle?
func has_feature_near(cell: Vector2i, feature: StringName, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if get_feature(cell + Vector2i(dx, dy)) == feature:
				return true
	return false

## Gibt es das Biom im (quadratischen) Umkreis um die Zelle?
## (M13: z. B. Fischersteg braucht Wasser in der Naehe.)
func has_biome_near(cell: Vector2i, biome: StringName, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if get_biome(cell + Vector2i(dx, dy)) == biome:
				return true
	return false

## Naechste begehbare, merkmalfreie Zelle ab [param target] (ringfoermig,
## deterministisch). Fuer kartenabhaengige Platzierungen wie den
## gegnerischen Bergfried oder Einheiten-Spawns.
func nearest_free_cell(target: Vector2i) -> Vector2i:
	var clamped := target.clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	for radius in maxi(width, height):
		for cell in _ring_cells(clamped, radius):
			if is_walkable(cell) and get_feature(cell) == &"":
				return cell
	return clamped

## Haelt die Zelle Mindestabstand zu allen bereits vergebenen Plaetzen?
func _far_from_all(cell: Vector2i, slots: Array) -> bool:
	for other in slots:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < SLOT_SPACING:
			return false
	return true

## Serialisiert die Welt fuer den Spielstand (nur Seed + Groesse; die Karte
## wird beim Laden deterministisch neu erzeugt).
func to_dict() -> Dictionary:
	return {"seed": seed_value, "width": width, "height": height}

## Stellt die Welt aus einem Spielstand wieder her (regeneriert aus Seed).
func from_dict(d: Dictionary, biome_defs: Dictionary) -> void:
	generate(int(d.get("seed", 0)), int(d.get("width", 64)), int(d.get("height", 64)), biome_defs)

func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

## Erstes Biom, dessen noise_max den Rauschwert abdeckt (Definitionsreihenfolge).
func _pick_biome(noise_value: float) -> StringName:
	for def in _biome_defs:
		if noise_value <= def["noise_max"]:
			return def["id"]
	return _biome_defs[-1]["id"] if not _biome_defs.is_empty() else &""

## Merkmal einer Zelle (Baum/Fels): eigener, koordinatenbasierter RNG-Seed, damit
## das Ergebnis unabhaengig von der Iterationsreihenfolge deterministisch ist.
func _roll_feature(x: int, y: int, biome: StringName) -> StringName:
	return _weighted_pick(_biome_densities(biome, &"features"), "%d:%d:%d" % [seed_value, x, y])

## Dekor einer Zelle (Blumen, Gras, Busch ...): eigener RNG-Kanal ("decor:"-Salt),
## damit die Merkmals-Rolls (und deren Tests) unveraendert bleiben.
func _roll_decor(x: int, y: int, biome: StringName) -> StringName:
	return _weighted_pick(_biome_densities(biome, &"decor"), "decor:%d:%d:%d" % [seed_value, x, y])

## Dichten-Dictionary (StringName->Wahrscheinlichkeit) eines Biom-Kanals.
func _biome_densities(biome: StringName, channel: StringName) -> Dictionary:
	for def in _biome_defs:
		if def["id"] == biome:
			return def[channel]
	return {}

## Gewichtete Auswahl aus [param densities]; [param seed_key] macht das Ergebnis
## koordinaten- und kanalstabil. Leere Summe/kein Treffer -> &"".
func _weighted_pick(densities: Dictionary, seed_key: String) -> StringName:
	if densities.is_empty():
		return &""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var roll := rng.randf()
	var cumulative := 0.0
	for key in densities:
		cumulative += densities[key]
		if roll < cumulative:
			return key
	return &""

## Legt die Fluesse: von den hoechsten (gespreizten) Quellen jeweils dem
## Steilgefaelle nach abwaerts bis Wasser, Kartenrand, lokales Minimum oder einen
## bestehenden Fluss. Deterministisch (Hoehe + feste Richtungsreihenfolge).
func _generate_rivers() -> void:
	for i in _cell_river.size():
		_cell_river[i] = false
	for source in _river_sources():
		_trace_river(source)

## Bis zu RIVER_COUNT hohe Quellzellen mit Mindestabstand (deterministisch).
func _river_sources() -> Array:
	var candidates: Array = []
	for y in height:
		for x in width:
			if _cell_elevation[y * width + x] >= RIVER_SOURCE_MIN:
				candidates.append(Vector2i(x, y))
	candidates.sort_custom(_higher_first)
	var sources: Array = []
	var spacing := maxi(width, height) / 3
	for cell in candidates:
		if sources.size() >= RIVER_COUNT:
			break
		var far := true
		for s in sources:
			if maxi(absi(cell.x - s.x), absi(cell.y - s.y)) < spacing:
				far = false
				break
		if far:
			sources.append(cell)
	return sources

## Sortier-Praedikat: hoehere Zelle zuerst, bei Gleichstand stabile Index-Ordnung.
func _higher_first(a: Vector2i, b: Vector2i) -> bool:
	var ea: float = _cell_elevation[a.y * width + a.x]
	var eb: float = _cell_elevation[b.y * width + b.x]
	if ea == eb:
		return (a.y * width + a.x) < (b.y * width + b.x)
	return ea > eb

## Verfolgt einen Fluss vom Quellpunkt streng abwaerts (je Schritt zum tiefsten
## echt tieferen Nachbarn). Die Hoehe faellt monoton -> schleifenfrei und kurz.
## Endet an Wasser, dem Kartenrand, einem bestehenden Fluss oder dem lokalen
## Minimum (tiefste Senken sind per Hoehenband Sumpf/Wasser -> muendet ins Feuchte).
func _trace_river(source: Vector2i) -> void:
	var cell := source
	for _step in width + height:
		var idx := cell.y * width + cell.x
		if _cell_river[idx] and cell != source:
			return  # in bestehenden Fluss gemuendet
		_cell_river[idx] = true
		if get_biome(cell) == &"water":
			return  # See erreicht
		var next := cell
		var lowest: float = _cell_elevation[idx]
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + dir
			if not _in_bounds(n):
				continue
			var e: float = _cell_elevation[n.y * width + n.x]
			if e < lowest:
				lowest = e
				next = n
		if next == cell:
			return  # lokales Minimum -> Fluss endet (Senke/Feuchtgebiet)
		cell = next

## Zellen des quadratischen Rings mit Radius r um center (deterministisch).
func _ring_cells(center: Vector2i, radius: int) -> Array:
	if radius == 0:
		return [center]
	var cells: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) == radius:
				cells.append(center + Vector2i(dx, dy))
	return cells

## JSON -> typisierte Biom-Liste (StringNames, floats gesichert).
func _typed_biome_defs(raw: Dictionary) -> Array:
	var defs: Array = []
	_passable_biomes.clear()
	for key in raw:
		var entry: Dictionary = raw[key]
		var features: Dictionary = {}
		for f in entry.get("features", {}):
			features[StringName(f)] = float(entry["features"][f])
		var decor: Dictionary = {}
		for d in entry.get("decor", {}):
			decor[StringName(d)] = float(entry["decor"][d])
		_passable_biomes[StringName(key)] = bool(entry.get("passable", true))
		defs.append({
			"id": StringName(key),
			"noise_max": float(entry.get("noise_max", 1.0)),
			"features": features,
			"decor": decor,
		})
	return defs
