class_name WorldMap
extends RefCounted
## WorldMap — deterministische, UNENDLICHE Kartengenerierung (M4, M-Unendlich).
##
## Reine, headless testbare Logik ohne Rendering. Jede Zelle der grenzenlosen
## Welt ist eine reine Funktion aus Seed + Koordinate: Biome aus Simplex-Noise,
## Merkmale/Dekor aus koordinatenbasierten Wuerfel-Kanaelen. Es gibt KEINE
## Zell-Arrays mehr — alles wird on demand berechnet, deshalb braucht der
## Spielstand weiterhin nur Seed + Startgroesse (kein Delta-Save noetig:
## das Gelaende wird von Gameplay nie veraendert).
##
## Fluesse sind die Ausnahme: ihr Lauf (Quelle -> See) braucht Nachbarschaft.
## Sie werden je RIVER_REGION x RIVER_REGION grosser, weltfest verankerter
## Region einmalig berechnet und gecacht — deterministisch und unabhaengig
## davon, in welcher Reihenfolge Regionen besucht werden.
##
## [member width]/[member height] beschreiben nur noch das STARTGEBIET
## (Bauplatz-Suche ab Zentrum, Kamera-Start, Ambient-Streuung) — gespielt,
## gebaut und gelaufen werden darf ueberall.

## Mehrschichtiges Hoehenfeld (M-Landschaft): eigene Noise-Kanaele mit Seed-
## Offsets (kollidieren NICHT mit den Feature/Decor-Hash-Kanaelen). Kontinent/
## Meer niederfrequent, Ridged-Kanal fuer zusammenhaengende Bergkaemme, dazu
## rollende Huegel, Kuestendetail und ein Feuchte-Kanal.
const SEED_CONT: int = 0
const SEED_HILL: int = 1000
const SEED_RIDGE: int = 2000
const SEED_MOIST: int = 3000
const SEED_DETAIL: int = 4000
const NOISE_CONT_FREQ: float = 0.006    # Kontinent/Meer (~166 Zellen Wellenlaenge)
const NOISE_HILL_FREQ: float = 0.030    # rollende Huegel
const NOISE_RIDGE_FREQ: float = 0.012   # Bergkaemme (ridged, ~40 Zellen Segmente)
const NOISE_MOIST_FREQ: float = 0.008   # Feuchte
const NOISE_DETAIL_FREQ: float = 0.090  # Kuestenrauheit
const HILL_W: float = 0.28
const RIDGE_W: float = 0.90
const DETAIL_W: float = 0.05
## Grat-Kanal nur auf der Kontinent-Hochzone freischalten (weiche Maske) ->
## Kaemme liegen als zusammenhaengende Wirbelsaeule, nicht verstreut.
const MASK_LO: float = 0.15
const MASK_HI: float = 0.50

## Biom-Zonierungsschwellen auf der Hoehe h (kalibriert per Sampling, siehe
## Kommentar am Ende) und auf der Feuchte m. Ersetzen die alten noise_max-Baender.
const SEA_LEVEL: float = -0.18
const COAST_HI: float = -0.10
const LOWLAND_HI: float = 0.22
const HILL_HI: float = 0.60
const HIGH_HI: float = 1.05
const MOIST_WET: float = 0.12
const MOIST_DRY: float = -0.30  # Wueste/Heide nur im trockensten Bereich (selten)

## Flusslauf (§8.3): Regionsgroesse des Fluss-Caches, Quellen je Region,
## Mindesthoehe einer Quelle (auf der neuen h-Skala) und Mindestabstand.
const RIVER_REGION: int = 128
const RIVERS_PER_REGION: int = 24
const RIVER_SOURCE_MIN: float = 0.65
const RIVER_SOURCE_SPACING: int = 12
## Ab diesem Hoehenabfall zum Wassergruppen-Nachbarn gilt eine Flusszelle als
## Wasserfall. Auf der neuen h-Skala + Interim-Fluss-Code klein gehalten;
## echte Steilst-Abstieg-Fluesse (M2) erlauben spaeter einen groesseren Wert.
const WATERFALL_DROP: float = 0.10

var seed_value: int = 0
var width: int = 0   # Startgebiet (nicht: Weltgrenze)
var height: int = 0

var _biome_defs: Array = []   # [{id, features, decor}] (noise_max deprecated)
var _passable_biomes: Dictionary = {}  # Biom-ID -> bool (Standard: begehbar)
var _noise_cont: FastNoiseLite   # Kontinent/Meer (niederfrequent)
var _noise_hill: FastNoiseLite   # rollende Huegel
var _noise_ridge: FastNoiseLite  # Bergkaemme (ridged)
var _noise_detail: FastNoiseLite # Kuestenrauheit
var _noise_moist: FastNoiseLite  # Feuchte
var _river_regions: Dictionary = {}  # Regions-Koordinate -> {Zelle: true}

## Initialisiert die Welt. [param biome_defs] ist das rohe JSON-Dictionary aus
## biomes.json; die Reihenfolge der Eintraege bestimmt die Noise-Zuordnung.
## [param p_width]/[param p_height] definieren nur das Startgebiet.
func generate(p_seed: int, p_width: int, p_height: int, biome_defs: Dictionary) -> void:
	seed_value = p_seed
	width = p_width
	height = p_height
	_biome_defs = _typed_biome_defs(biome_defs)
	_river_regions.clear()
	_noise_cont = _make_noise(SEED_CONT, NOISE_CONT_FREQ, false)
	_noise_hill = _make_noise(SEED_HILL, NOISE_HILL_FREQ, false)
	_noise_ridge = _make_noise(SEED_RIDGE, NOISE_RIDGE_FREQ, true)
	_noise_detail = _make_noise(SEED_DETAIL, NOISE_DETAIL_FREQ, false)
	_noise_moist = _make_noise(SEED_MOIST, NOISE_MOIST_FREQ, false)

## Ein Noise-Kanal mit Seed-Offset; [param ridged] fuer zusammenhaengende Kaemme.
func _make_noise(seed_offset: int, freq: float, ridged: bool) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value + seed_offset
	n.frequency = freq
	if ridged:
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		n.fractal_octaves = 4
	return n

## Biom einer Zelle — ueberall definiert (M-Unendlich: keine Kartengrenze).
## Aus Hoehe UND Feuchte (M-Landschaft), nicht mehr aus einem Rauschband.
func get_biome(cell: Vector2i) -> StringName:
	if _noise_cont == null:
		return &""
	return _pick_biome2(get_elevation(cell), get_moisture(cell))

## Ressourcen-Merkmal einer Zelle (&"" = keines) — ueberall definiert.
func get_feature(cell: Vector2i) -> StringName:
	return _roll_feature(cell.x, cell.y, get_biome(cell))

## Rein dekoratives Gruenzeug einer Zelle (&"" = keines). Hat KEINE
## Spielwirkung; nur auf merkmalfreien Zellen (belebt kahle Flaechen).
func get_decor(cell: Vector2i) -> StringName:
	if get_feature(cell) != &"":
		return &""
	return _roll_decor(cell.x, cell.y, get_biome(cell))

## Hoehe einer Zelle aus dem mehrschichtigen Feld (M-Landschaft): Kontinent-Basis
## + Huegel + Grat (nur auf der Hochzone via weicher Maske) + Kuestendetail.
## Ueberall definiert; nur intern genutzt (Biomwahl, Fluesse, Wasserfall).
func get_elevation(cell: Vector2i) -> float:
	if _noise_cont == null:
		return 0.0
	var base := _noise_cont.get_noise_2d(cell.x, cell.y)
	var hills := _noise_hill.get_noise_2d(cell.x, cell.y)
	var ridge := _noise_ridge.get_noise_2d(cell.x, cell.y)
	var detail := _noise_detail.get_noise_2d(cell.x, cell.y)
	var mask := smoothstep(MASK_LO, MASK_HI, base)
	return base + HILL_W * hills + RIDGE_W * mask * ridge + DETAIL_W * detail

## Feuchte einer Zelle (M-Landschaft): eigener niederfrequenter Kanal, steuert
## Vegetation (Wald/Moor/Grasland/Heide/Wueste).
func get_moisture(cell: Vector2i) -> float:
	if _noise_moist == null:
		return 0.0
	return _noise_moist.get_noise_2d(cell.x, cell.y)

## Kompatibilitaets-Aliase (M17): seit M-Unendlich ist die ganze Welt
## "peekbar" — get_* und peek_* sind identisch.
func peek_biome(cell: Vector2i) -> StringName:
	return get_biome(cell)

func peek_decor(cell: Vector2i) -> StringName:
	return get_decor(cell)

## Ist die Zelle Teil eines Flusses? (unbegehbar; Region wird lazy berechnet)
func is_river(cell: Vector2i) -> bool:
	var region := Vector2i(floori(cell.x / float(RIVER_REGION)), floori(cell.y / float(RIVER_REGION)))
	if not _river_regions.has(region):
		_river_regions[region] = _compute_rivers(region)
	return _river_regions[region].has(cell)

## 4-Bit-Kantenmaske fuer Autotiling (§8.3): welche der vier Iso-Seitennachbarn
## zur "Wassergruppe" (Wasser ODER Fluss) gehoeren. Gesetztes Bit = Innenkante
## (nahtloser Uebergang), geloeschtes Bit = Uferkante.
## Bit 1 = oben-rechts (0,-1), 2 = unten-rechts (1,0), 4 = unten-links (0,1),
## 8 = oben-links (-1,0) — passend zur Diamant-Kachel (DIAMOND_DOWN).
func water_edge_mask(cell: Vector2i) -> int:
	var mask := 0
	if _is_water_group(cell + Vector2i(0, -1)): mask |= 1
	if _is_water_group(cell + Vector2i(1, 0)): mask |= 2
	if _is_water_group(cell + Vector2i(0, 1)): mask |= 4
	if _is_water_group(cell + Vector2i(-1, 0)): mask |= 8
	return mask

## Gehoert die Zelle zur Wassergruppe (See oder Fluss)?
func _is_water_group(cell: Vector2i) -> bool:
	return get_biome(cell) == &"water" or is_river(cell)

## Uferzelle? (begehbares Land direkt neben Wasser oder Fluss — fuer Sandbaenke
## und nasse Uferdeko. Sumpf/Wasser/Fluss selbst sind KEIN Ufer.)
func is_bank(cell: Vector2i) -> bool:
	if not is_walkable(cell):
		return false
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if _is_water_group(cell + dir):
			return true
	return false

## Wasserfall? (Flusszelle mit steilem Abfall zu einem Wassergruppen-Nachbarn.)
func is_waterfall(cell: Vector2i) -> bool:
	if not is_river(cell):
		return false
	var here := get_elevation(cell)
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Vector2i = cell + dir
		if _is_water_group(n) and here - get_elevation(n) > WATERFALL_DROP:
			return true
	return false

## Ufer-Wasserzelle? (Wasser mit mindestens einem Nicht-Wasser-Nachbarn.)
## Rendert als Flachwasser; Wasser ohne Landnachbar als Tiefwasser.
func is_water_shore(cell: Vector2i) -> bool:
	if get_biome(cell) != &"water":
		return false
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if get_biome(cell + dir) != &"water":
			return true
	return false

## Ist die Zelle fuer Einheiten begehbar? (Biom-Flag "passable", z. B.
## Sumpf/Wasser = false; Fluesse blockieren ebenfalls.) Ueberall definiert.
func is_walkable(cell: Vector2i) -> bool:
	if is_river(cell):
		return false
	return _passable_biomes.get(get_biome(cell), true)

## Alle unbegehbaren Zellen des STARTGEBIETS (Kompatibilitaet fuer feste
## Wegfindungs-Gitter; das wachsende Gitter fragt is_walkable direkt).
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
## ringfoermig vom Zentrum des Startgebiets nach aussen. Stabil: die ersten N
## Plaetze aendern sich nicht, wenn spaeter mehr angefordert werden.
func building_slots(count: int) -> Array:
	var slots: Array = []
	var center := _land_start_center()
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
## gegnerischen Bergfried oder Einheiten-Spawns — ueberall in der Welt.
func nearest_free_cell(target: Vector2i) -> Vector2i:
	for radius in maxi(width, height):
		for cell in _ring_cells(target, radius):
			if is_walkable(cell) and get_feature(cell) == &"":
				return cell
	return target

## Land-nahes Startzentrum (M-Landschaft): das geometrische Zentrum kann jetzt
## im Meer oder auf einem Gipfel liegen. Spiralt vom Zentrum zur naechsten
## begehbaren, merkmalfreien Landzelle — bevorzugt gutes Bauland (Grasland/Tal/
## Kueste/Huegel), sonst die naechste begehbare Landzelle. Deterministisch.
func _land_start_center() -> Vector2i:
	var center := Vector2i(width / 2, height / 2)
	var preferred: Array = [&"grassland", &"valley", &"beach", &"hills"]
	var fallback := center
	var found_fallback := false
	for radius in maxi(width, height) * 4:
		for cell in _ring_cells(center, radius):
			if not is_walkable(cell) or get_feature(cell) != &"":
				continue
			if get_biome(cell) in preferred:
				return cell
			if not found_fallback:
				fallback = cell
				found_fallback = true
	return fallback

## Haelt die Zelle Mindestabstand zu allen bereits vergebenen Plaetzen?
func _far_from_all(cell: Vector2i, slots: Array) -> bool:
	for other in slots:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < SLOT_SPACING:
			return false
	return true

## Serialisiert die Welt fuer den Spielstand: nur Seed + Startgroesse.
## Alles andere ist eine reine Funktion daraus (auch besuchte Gegenden —
## deshalb braucht die unendliche Welt keine Chunk-Deltas).
func to_dict() -> Dictionary:
	return {"seed": seed_value, "width": width, "height": height}

## Stellt die Welt aus einem Spielstand wieder her (regeneriert aus Seed).
func from_dict(d: Dictionary, biome_defs: Dictionary) -> void:
	generate(int(d.get("seed", 0)), int(d.get("width", 64)), int(d.get("height", 64)), biome_defs)

## Biom aus Hoehe h und Feuchte m (M-Landschaft): Zonierung Gipfel -> Meer,
## Feuchte verschiebt die Vegetation. Alle IDs existieren in biomes.json.
func _pick_biome2(h: float, m: float) -> StringName:
	if h < SEA_LEVEL:
		return &"water"                                   # zusammenhaengendes Meer
	if h < COAST_HI:
		return &"swamp" if m > MOIST_WET else &"beach"    # Kuestenmoor vs. Sandkueste
	if h < LOWLAND_HI:
		if m < MOIST_DRY:
			return &"desert"                              # trockenes Oedland
		if m > MOIST_WET:
			return &"forest"                              # dichter Wald
		return &"valley" if m > 0.0 else &"grassland"     # lichter Wald vs. Ebene
	if h < HILL_HI:
		if m > MOIST_WET:
			return &"forest"                              # Bergwald
		if m < MOIST_DRY:
			return &"heath"                               # Heide
		return &"hills"                                   # bewaldete Huegel
	if h < HIGH_HI:
		return &"highlands"                               # Fels-Hochland
	return &"snow"                                        # Gipfel

## Merkmal einer Zelle (Baum/Fels): eigener, koordinatenbasierter RNG-Seed, damit
## das Ergebnis unabhaengig von der Zugriffs-Reihenfolge deterministisch ist.
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

## Berechnet alle Flusszellen EINER Region (weltfest verankertes Quadrat von
## RIVER_REGION Kantenlaenge): von den hoechsten (gespreizten) Quellen jeweils
## dem Wasser-Distanzfeld nach abwaerts bis zum See. Nutzt nur Zellen der
## eigenen Region -> Ergebnis haengt allein von Seed + Region ab.
func _compute_rivers(region: Vector2i) -> Dictionary:
	var origin := region * RIVER_REGION
	var dist := _distance_to_water(origin)
	if dist.is_empty():
		return {}  # Region ohne Wasser -> keine Fluesse
	var rivers: Dictionary = {}
	for source in _river_sources(origin):
		_trace_river(source, origin, dist, rivers)
	return rivers

## Gitterdistanz jeder Regionszelle zum naechsten Wasserbiom (Multi-Source-BFS,
## 4er-Nachbarschaft, innerhalb der Region). Leer, falls die Region kein Wasser hat.
func _distance_to_water(origin: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(RIVER_REGION * RIVER_REGION)
	for i in dist.size():
		dist[i] = -1
	var queue: Array = []
	for y in RIVER_REGION:
		for x in RIVER_REGION:
			if get_biome(origin + Vector2i(x, y)) == &"water":
				dist[y * RIVER_REGION + x] = 0
				queue.append(Vector2i(x, y))
	if queue.is_empty():
		return PackedInt32Array()
	var head := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var cd := dist[current.y * RIVER_REGION + current.x]
		for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = current + dir
			if n.x < 0 or n.y < 0 or n.x >= RIVER_REGION or n.y >= RIVER_REGION:
				continue
			var ni := n.y * RIVER_REGION + n.x
			if dist[ni] != -1:
				continue
			dist[ni] = cd + 1
			queue.append(n)
	return dist

## Bis zu RIVERS_PER_REGION hohe Quellzellen der Region mit Mindestabstand
## (deterministisch: Hoehe zuerst, Gleichstand -> stabile Index-Ordnung).
func _river_sources(origin: Vector2i) -> Array:
	var candidates: Array = []
	for y in RIVER_REGION:
		for x in RIVER_REGION:
			var local := Vector2i(x, y)
			if get_elevation(origin + local) >= RIVER_SOURCE_MIN:
				candidates.append(local)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ea := get_elevation(origin + a)
		var eb := get_elevation(origin + b)
		if ea == eb:
			return (a.y * RIVER_REGION + a.x) < (b.y * RIVER_REGION + b.x)
		return ea > eb)
	var sources: Array = []
	for cell in candidates:
		if sources.size() >= RIVERS_PER_REGION:
			break
		var far := true
		for s in sources:
			if maxi(absi(cell.x - s.x), absi(cell.y - s.y)) < RIVER_SOURCE_SPACING:
				far = false
				break
		if far:
			sources.append(cell)
	return sources

## Verfolgt einen Fluss von der (regionslokalen) Quelle zum naechsten See: je
## Schritt zum Nachbarn mit KLEINERER Wasser-Distanz (Gleichstand -> tiefere
## Zelle). Die Distanz faellt monoton -> schleifenfrei, endet garantiert an
## Wasser (oder muendet in einen bestehenden Fluss).
func _trace_river(source: Vector2i, origin: Vector2i, dist: PackedInt32Array, rivers: Dictionary) -> void:
	var cell := source
	if dist[source.y * RIVER_REGION + source.x] < 0:
		return
	for _step in RIVER_REGION * 2:
		var world_cell := origin + cell
		if rivers.has(world_cell) and cell != source:
			return  # in bestehenden Fluss gemuendet
		if get_biome(world_cell) == &"water":
			return  # See erreicht (Wasserzelle bleibt Wasser)
		rivers[world_cell] = true
		var here_d := dist[cell.y * RIVER_REGION + cell.x]
		var best := cell
		var best_d := 1 << 30
		var best_e: float = INF
		for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cell + dir
			if n.x < 0 or n.y < 0 or n.x >= RIVER_REGION or n.y >= RIVER_REGION:
				continue
			var nd := dist[n.y * RIVER_REGION + n.x]
			if nd < 0 or nd >= here_d:
				continue  # nur echt naeher am Wasser (garantiert Fortschritt)
			var ne := get_elevation(origin + n)
			if nd < best_d or (nd == best_d and ne < best_e):
				best_d = nd
				best_e = ne
				best = n
		if best == cell:
			return  # kein naeherer Nachbar (sollte fuer Nicht-Wasser nie passieren)
		cell = best

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
