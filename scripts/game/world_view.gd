extends Node2D
## WorldView — Darstellung der Spielwelt (M4): isometrische Bodenkacheln,
## Ressourcen-Merkmale, Gebaeude-Sprites und der 200-Einheiten-Performance-
## Test (F3). Reines Rendering: bezieht alle Daten ueber [EventBus]-Signale
## und Texturen ausschliesslich ueber das [AssetRegistry].

## Anzahl Test-Einheiten fuer den Performance-Nachweis (goal §2).
const PERF_UNIT_COUNT: int = 200
const PERF_UNIT_SPEED: float = 40.0

## Einfaerbung gegnerischer Einheiten/Gebaeude (bis echte Assets kommen).
const ENEMY_TINT := Color(1.0, 0.72, 0.72)

## Wilde Ambient-Tiere (§8.5): Dichte je Zelle und Obergrenze — rein kosmetisch.
const AMBIENT_DENSITY: float = 0.02
const AMBIENT_MAX: int = 80
## Grosse Bergkulissen (§8.2): Wahrscheinlichkeit je Kulissen-Block und dessen
## Kantenlaenge in Zellen (M-Unendlich: hash-verteilt statt Karten-Scan).
const MOUNTAIN_DENSITY: float = 0.25
const MOUNTAIN_BLOCK: int = 4
## Wanderung der Wildtiere: gemaechliches Tempo, Radius um die Startzelle und
## Wahrscheinlichkeit je Frame, spontan die Richtung zu wechseln.
const AMBIENT_SPEED: float = 8.0
const AMBIENT_WANDER_RADIUS: float = 24.0
const AMBIENT_TURN_CHANCE: float = 0.01
## Chunk-Streaming (M-Unendlich): Chunk-Kantenlaenge in Zellen, Sichtrand-
## Reserve, Pruefintervall und wie viele Chunks Abstand ein gerenderter Chunk
## haben darf, bevor er verworfen wird.
const CHUNK: int = 24
const STREAM_MARGIN_CELLS: int = 12
const STREAM_INTERVAL: float = 0.2
const CHUNK_DROP_GRACE: int = 2
## Kampf-Einheiten gleiten zwischen den Zellen (statt pro Tick zu springen), px/s.
const COMBAT_GLIDE_SPEED: float = 80.0
## Benannte Animations-Zustaende (je Sheet <id>_<state>.png; sonst prozedural).
const ANIM_IDLE: StringName = &"idle"
const ANIM_WALK: StringName = &"walk"
const ANIM_WORK: StringName = &"work"
const ANIM_ATTACK: StringName = &"attack"
const ANIM_SHOOT: StringName = &"shoot"
const ANIM_DIE: StringName = &"die"
## Iso-Blickrichtungen (Sheet-Suffix; Links/Rechts erledigt die Spiegelung).
const ANIM_DOWN: StringName = &"down"  # zur Kamera (vorne)
const ANIM_UP: StringName = &"up"      # von der Kamera weg (hinten)
const FACING_THRESHOLD: float = 0.05
## Sterbe-Animation: Dauer und Absack-Tempo (prozeduraler Fallback ohne die-Sheet).
const DIE_DURATION: float = 0.6
const DIE_SINK: float = 14.0
## Treffer-Zucken: kurzer Aufblitz (modulate) ueber die laufende Zustands-Animation.
const HURT_DURATION: float = 0.18
const HURT_FLASH: Color = Color(2.2, 0.7, 0.7)  # heller Rot-Blitz

## Saison-Toenung der Welt (M-Jahreszeiten): sanfter Farbstich je Saison.
const SEASON_TINTS: Dictionary = {
	&"spring": Color(0.97, 1.0, 0.94),
	&"summer": Color(1.0, 0.98, 0.88),
	&"autumn": Color(1.0, 0.9, 0.78),
	&"winter": Color(0.72, 0.78, 1.0),
}
const SEASON_TINT_DURATION: float = 2.0  # Uebergangsdauer der Toenung

var _map: WorldMap
var _ground: TileMapLayer
var _decor: TileMapLayer  # rein dekoratives Gruenzeug (flach, unter allen Sprites)
var _paths: TileMapLayer  # Wegenetz zwischen Gebaeuden (flach)
var _mountain_root: Node2D  # grosse Bergkulissen
var _signs_root: Node2D  # Wegweiser an Weg-Kreuzungen
var _features_root: Node2D  # Baeume/Fels/Wasserfall als Sprites (global Y-tiefensortiert)
var _ambient_root: Node2D  # wilde Ambient-Tiere (unter Gebaeuden gezeichnet)
var _buildings_root: Node2D
var _props_root: Node2D  # Kleindeko (Brunnen/Heuhaufen/Zaun) neben Gebaeuden
var _livestock_root: Node2D  # Nutztiere neben Gebaeuden (ueber Gebaeuden gezeichnet)
var _villagers_root: Node2D  # pendelnde Dorfbewohner (M16, sichtbares Dorfleben)
var _combat_root: Node2D
var _units_root: Node2D
var _bounds := Rect2()
var _tile_sources: Dictionary = {}  # Asset-ID -> Quellen-ID im TileSet
var _unit_sprites: Dictionary = {}  # Einheiten-ID -> Sprite2D
var _dying: Array = []  # gefallene Einheiten in der Sterbe-Animation (bis Entfernen)
var _enemy_keep_sprite: Sprite2D
var _enemy_campfire: Sprite2D  # Lagerfeuer neben dem gegnerischen Bergfried (§8.6)
var _plot_tiles: Dictionary = {}  # Zelle -> Boden-Asset unter Gebaeuden (Acker/Erde)
var _rendered_chunks: Dictionary = {}  # Chunk-Koordinate -> Sprite-Container (Streaming)
var _stream_accum: float = 0.0
var _biome_mountains: Dictionary = {}  # Biom -> Kulissen-Varianten (aus biomes.json)
var _selected_unit_id := -1  # per Klick gewaehlte eigene Einheit (M13)
var _last_units: Array = []  # letzter Kampf-Schnappschuss (fuer Klick-Treffer)
var _build_def_id: StringName = &""  # aktiver Bau-Modus (leer = aus)
var _demolish_mode := false  # aktiver Abriss-Modus (M11)
var _ghost: Sprite2D
var _ghost_cell := Vector2i.ZERO  # Zelle, auf der der Geist steht (= Bau-/Abrissziel)
var _snow: CPUParticles2D  # Schneefall im Winter (M-Jahreszeiten)
var _season_tween: Tween  # laufender Toenungs-Uebergang
var _village := VillageLife.new()  # Bewegungs-Logik der Dorfbewohner (pures Modell)
var _villager_sprites: Dictionary = {}  # Bewohner-ID -> Sprite2D
var _anim_time: float = 0.0  # gemeinsame Uhr fuer prozedurale Animationen

func _ready() -> void:
	_ground = TileMapLayer.new()
	_decor = TileMapLayer.new()
	_paths = TileMapLayer.new()
	_mountain_root = Node2D.new()
	_signs_root = Node2D.new()
	_features_root = Node2D.new()
	_ambient_root = Node2D.new()
	_buildings_root = Node2D.new()
	_props_root = Node2D.new()
	_livestock_root = Node2D.new()
	_villagers_root = Node2D.new()
	_combat_root = Node2D.new()
	_units_root = Node2D.new()
	# Flache Boden-Layer liegen unter allen stehenden Sprites (die z = Basis-Y setzen);
	# alle Sprite-Roots bleiben bei z 0, ihre Kinder tragen das eigentliche z.
	_ground.z_index = -3
	_decor.z_index = -2
	_paths.z_index = -1
	for child in [_ground, _decor, _paths, _mountain_root, _features_root, _ambient_root, _buildings_root, _props_root, _signs_root, _livestock_root, _villagers_root, _combat_root, _units_root]:
		add_child(child)
	_ghost = Sprite2D.new()
	_ghost.visible = false
	_ghost.z_index = 4000  # Bau-/Abriss-Geist immer obenauf
	add_child(_ghost)
	EventBus.world_changed.connect(_on_world_changed)
	EventBus.buildings_changed.connect(_on_buildings_changed)
	EventBus.workforce_changed.connect(_on_workforce_changed)
	EventBus.combat_state_changed.connect(_on_combat_state_changed)
	EventBus.tower_shots.connect(_on_tower_shots)
	EventBus.build_mode_selected.connect(_enter_build_mode)
	EventBus.demolish_mode_selected.connect(_enter_demolish_mode)
	EventBus.build_preview_result.connect(_on_preview_result)
	EventBus.season_changed.connect(_on_season_changed)
	_setup_snow()

## Pfeil-Animation (M10): kurze, ausblendende Linie je Turmschuss.
func _on_tower_shots(shots: Array) -> void:
	if _map == null:
		return
	for shot in shots:
		var line := Line2D.new()
		line.points = PackedVector2Array([
			_ground.map_to_local(shot["from"]) + Vector2(0, -18),
			_ground.map_to_local(shot["to"]) + Vector2(0, -8),
		])
		line.width = 2.0
		line.default_color = Color(0.95, 0.88, 0.55)
		line.z_index = 3900  # Flugbahn ueber allen Sprites
		_combat_root.add_child(line)
		var tween := line.create_tween()
		tween.tween_property(line, "modulate:a", 0.0, 0.35)
		tween.tween_callback(line.queue_free)

## F3 = Perf-Test; im Bau-Modus: Linksklick platziert, Rechtsklick/Esc beendet.
## Ohne Bau-Modus (M13): Linksklick waehlt eigene Einheit bzw. schickt die
## gewaehlte Einheit auf Posten; Esc hebt die Auswahl auf.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_toggle_perf_units()
		return
	if _build_def_id == &"" and not _demolish_mode:
		_handle_unit_input(event)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Gebaut/abgerissen wird, wo der Geist steht.
			if _demolish_mode:
				EventBus.demolish_requested.emit(_ghost_cell)
			else:
				EventBus.build_requested.emit(_build_def_id, _ghost_cell)
			_move_ghost_to(_ghost_cell)  # Vorschau auffrischen (Zelle geaendert)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_exit_build_mode()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_exit_build_mode()

## Einheiten-Steuerung (M13): Klick auf eigene Einheit = auswaehlen (gelb),
## Klick auf die Karte = Bewegungsbefehl fuer die Auswahl.
func _handle_unit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_select_unit(-1)
		return
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := _mouse_cell()
	var clicked_id := _player_unit_at(cell)
	if clicked_id >= 0:
		_select_unit(clicked_id)
		get_viewport().set_input_as_handled()
	elif _selected_unit_id >= 0:
		EventBus.unit_move_requested.emit(_selected_unit_id, cell)
		get_viewport().set_input_as_handled()

## Eigene Einheit auf/neben der Zelle (Chebyshev <= 1), sonst -1.
func _player_unit_at(cell: Vector2i) -> int:
	for unit in _last_units:
		if unit["faction"] != &"player":
			continue
		var delta: Vector2i = unit["cell"] - cell
		if maxi(absi(delta.x), absi(delta.y)) <= 1:
			return unit["id"]
	return -1

func _select_unit(unit_id: int) -> void:
	_selected_unit_id = unit_id
	_refresh_unit_highlights()

## Setzt die Grundfarbe je Einheit (Auswahl gelb / Gegner rötlich / eigen weiß) als
## base_modulate; der Glide-Loop legt darauf den kurzen Treffer-Blitz.
func _refresh_unit_highlights() -> void:
	for unit in _last_units:
		var sprite: Sprite2D = _unit_sprites.get(unit["id"])
		if sprite == null:
			continue
		if unit["id"] == _selected_unit_id:
			sprite.set_meta("base_modulate", Color(1.6, 1.6, 0.7))  # gelb hervorgehoben
		elif unit["faction"] == &"enemy":
			sprite.set_meta("base_modulate", ENEMY_TINT)
		else:
			sprite.set_meta("base_modulate", Color.WHITE)

## Bau-Modus: Geist erscheint in der Bildschirmmitte (nicht an der Maus, die
## beim Menue-Klick noch ueber dem HUD steht) und folgt danach der Maus auf
## der Karte. Der Controller liefert gruen/rot fuer die Zelle.
func _enter_build_mode(def_id: StringName) -> void:
	_demolish_mode = false
	_build_def_id = def_id
	_ghost.texture = AssetRegistry.get_texture(StringName("building_%s" % def_id))
	_ghost.visible = true
	_move_ghost_to(_screen_center_cell())

## Abriss-Modus (M11): gleicher Geist-Mechanismus, roter Marker.
func _enter_demolish_mode() -> void:
	_build_def_id = &""
	_demolish_mode = true
	_ghost.texture = AssetRegistry.get_texture(&"ui_demolish")
	_ghost.visible = true
	_move_ghost_to(_screen_center_cell())

## Beendet Bau- UND Abriss-Modus.
func _exit_build_mode() -> void:
	_build_def_id = &""
	_demolish_mode = false
	_ghost.visible = false

func _mouse_cell() -> Vector2i:
	return _ground.local_to_map(_ground.get_local_mouse_position())

## Zelle unter der Bildschirmmitte (Kamerazentrum).
func _screen_center_cell() -> Vector2i:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return Vector2i.ZERO
	return _ground.local_to_map(_ground.to_local(camera.get_screen_center_position()))

func _move_ghost_to(cell: Vector2i) -> void:
	if _map == null or (_build_def_id == &"" and not _demolish_mode):
		return
	_ghost_cell = cell
	_ghost.position = _ground.map_to_local(cell) + Vector2(0, -10)
	if _demolish_mode:
		EventBus.demolish_preview_requested.emit(cell)
	else:
		EventBus.build_preview_requested.emit(_build_def_id, cell)

func _on_preview_result(cell: Vector2i, ok: bool) -> void:
	if cell != _ghost_cell:
		return  # veraltete Antwort
	_ghost.modulate = Color(0.5, 1.0, 0.5, 0.7) if ok else Color(1.0, 0.35, 0.35, 0.7)

## Schneefall (M-Jahreszeiten): Partikel-Emitter, der der Kamera folgt und
## dessen Spawn-Rechteck die aktuelle Sicht deckt — so schneit es unabhaengig
## von Zoom und Position, ohne die ganze (grenzenlose) Welt zu beschneien.
func _setup_snow() -> void:
	_snow = CPUParticles2D.new()
	_snow.emitting = false
	_snow.amount = 260
	_snow.lifetime = 5.0
	_snow.preprocess = 5.0  # beim Winterstart/-laden ist der Himmel sofort voll
	_snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_snow.direction = Vector2(0.2, 1.0)
	_snow.gravity = Vector2(8, 42)
	_snow.initial_velocity_min = 6.0
	_snow.initial_velocity_max = 18.0
	_snow.scale_amount_min = 1.5
	_snow.scale_amount_max = 3.0
	_snow.color = Color(1, 1, 1, 0.85)
	_snow.z_index = 3950  # ueber der Welt, unter dem Bau-Geist
	add_child(_snow)

## Saisonwechsel (M-Jahreszeiten): Welt sanft toenen, im Winter schneit es.
func _on_season_changed(season: StringName, _display: String) -> void:
	var tint: Color = SEASON_TINTS.get(season, Color.WHITE)
	if _season_tween != null and _season_tween.is_valid():
		_season_tween.kill()
	_season_tween = create_tween()
	_season_tween.tween_property(self, "modulate", tint, SEASON_TINT_DURATION)
	_snow.emitting = season == &"winter"

## Schnee an der Kamera halten und das Spawn-Rechteck an die Sicht anpassen.
func _update_snow() -> void:
	if not _snow.emitting:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	_snow.position = cam.get_screen_center_position()
	_snow.emission_rect_extents = get_viewport_rect().size / (2.0 * cam.zoom) + Vector2(80, 80)

func _process(delta: float) -> void:
	_anim_time += delta
	_move_perf_units(delta)
	_move_ambient(delta)
	_move_villagers(delta)
	_glide_combat_units(delta)
	_update_dying(delta)
	_update_snow()
	_follow_mouse_in_build_mode()
	_stream_accum += delta
	if _stream_accum >= STREAM_INTERVAL:
		_stream_accum = 0.0
		_update_streaming()

## Geist folgt der Maus per Polling — Bewegungs-Events koennen vom GUI
## verschluckt werden, _process ist davon unabhaengig. Ueber dem HUD
## (gehovertes Control) bleibt der Geist stehen.
func _follow_mouse_in_build_mode() -> void:
	if (_build_def_id == &"" and not _demolish_mode) or _map == null:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var cell := _mouse_cell()
	if cell != _ghost_cell:
		_move_ghost_to(cell)

## Welt gewechselt: Layer leeren, dann streamt der Chunk-Renderer die
## Umgebung der Kamera (M-Unendlich — die Welt hat keinen Rand mehr).
func _on_world_changed(map: WorldMap) -> void:
	_map = map
	_ground.tile_set = _make_tile_set()
	_decor.tile_set = _ground.tile_set
	_paths.tile_set = _ground.tile_set
	_ground.clear()
	_decor.clear()
	_paths.clear()
	for chunk in _rendered_chunks:
		_rendered_chunks[chunk].queue_free()
	_rendered_chunks.clear()
	for child in _features_root.get_children():
		child.queue_free()
	_plot_tiles.clear()  # Bauplatz-Einfaerbungen verwerfen (kommen mit buildings_changed neu)
	_biome_mountains.clear()
	for biome_id in Database.biomes:
		var variants: Array = Database.biomes[biome_id].get("mountains", [])
		if not variants.is_empty():
			_biome_mountains[StringName(biome_id)] = variants
	_update_bounds()
	_spawn_ambient_life()
	_update_streaming()

## Chunk-Streaming (M-Unendlich): rendert alle Chunks im (grosszuegig
## erweiterten) Sichtbereich und verwirft weit entfernte — gezeichnet ist
## immer nur die Umgebung der Kamera, die Welt selbst ist grenzenlos.
func _update_streaming() -> void:
	if _map == null:
		return
	var visible := _visible_chunk_range()
	for y in range(visible.position.y, visible.end.y):
		for x in range(visible.position.x, visible.end.x):
			var chunk := Vector2i(x, y)
			if not _rendered_chunks.has(chunk):
				_render_chunk(chunk)
	var keep := visible.grow(CHUNK_DROP_GRACE)
	for chunk in _rendered_chunks.keys():
		if not keep.has_point(chunk):
			_drop_chunk(chunk)

## Chunk-Bereich, den die Kamera gerade sieht (plus Zellen-Reserve).
func _visible_chunk_range() -> Rect2i:
	var camera := get_viewport().get_camera_2d()
	var center_local := _ground.to_local(camera.get_screen_center_position()) \
		if camera != null else _ground.map_to_local(Vector2i(_map.width / 2, _map.height / 2))
	var zoom_x: float = camera.zoom.x if camera != null else 1.0
	var half := get_viewport_rect().size / (2.0 * zoom_x)
	var lo := Vector2i(1 << 29, 1 << 29)
	var hi := -lo
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		var cell := _ground.local_to_map(center_local + corner)
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	lo -= Vector2i(STREAM_MARGIN_CELLS, STREAM_MARGIN_CELLS)
	hi += Vector2i(STREAM_MARGIN_CELLS, STREAM_MARGIN_CELLS)
	var lo_chunk := Vector2i(floori(lo.x / float(CHUNK)), floori(lo.y / float(CHUNK)))
	var hi_chunk := Vector2i(floori(hi.x / float(CHUNK)), floori(hi.y / float(CHUNK)))
	return Rect2i(lo_chunk, hi_chunk - lo_chunk + Vector2i.ONE)

func _render_chunk(chunk: Vector2i) -> void:
	var container := Node2D.new()
	_features_root.add_child(container)
	_rendered_chunks[chunk] = container
	var origin := chunk * CHUNK
	for y in CHUNK:
		for x in CHUNK:
			_render_cell(origin + Vector2i(x, y), container)

## Eine Zelle zeichnen: Boden (bzw. Bauplatz-Einfaerbung), Merkmal-Sprite,
## Dekor und ggf. Bergkulisse — identisch fuer Start- und Ferngebiet.
func _render_cell(cell: Vector2i, container: Node2D) -> void:
	_set_tile(_ground, cell, _plot_tiles.get(cell, _ground_asset(cell)))
	var feature := _map.get_feature(cell)
	var feat_id := ""
	if _map.is_waterfall(cell):
		feat_id = "feature_waterfall"  # steile Flussstufe (§8.3)
	elif feature != &"":
		# Gameplay bleibt "feature" (z. B. rock); nur die Optik variiert.
		feat_id = "feature_%s" % FeatureVariants.pick(feature, cell, Database.feature_variants, _map.seed_value)
	if feat_id != "":
		_add_sprite(container, StringName(feat_id), cell, Vector2.ZERO)
	elif _map.is_bank(cell) and absi(hash("wet:%d:%d:%d" % [_map.seed_value, cell.x, cell.y])) % 3 == 0:
		_add_sprite(container, &"feature_rock_wet", cell, Vector2.ZERO)  # nasse Ufersteine
	var decor := _map.get_decor(cell)
	if decor != &"":
		_set_tile(_decor, cell, "feature_%s" % decor)
	var mountain := _mountain_variant(cell)
	if mountain != &"":
		var sprite := _add_sprite(container, StringName("feature_%s" % mountain), cell, Vector2.ZERO)
		# Grafik nach oben schieben (Basis bleibt auf der Zelle -> korrektes z).
		sprite.offset = Vector2(0, -sprite.texture.get_height() / 2.0)

## Chunk verwerfen: Kacheln loeschen, Sprite-Container freigeben.
func _drop_chunk(chunk: Vector2i) -> void:
	var origin: Vector2i = chunk * CHUNK
	for y in CHUNK:
		for x in CHUNK:
			_ground.erase_cell(origin + Vector2i(x, y))
			_decor.erase_cell(origin + Vector2i(x, y))
	_rendered_chunks[chunk].queue_free()
	_rendered_chunks.erase(chunk)

## Bergkulisse einer Zelle (M-Unendlich): je Block von MOUNTAIN_BLOCK^2 Zellen
## bestimmt ein Hash hoechstens eine Kulissen-Zelle — deterministisch und ohne
## Nachbarschafts-Wissen chunkuebergreifend konsistent.
func _mountain_variant(cell: Vector2i) -> StringName:
	var variants: Array = _biome_mountains.get(_map.get_biome(cell), [])
	if variants.is_empty():
		return &""
	var block := Vector2i(floori(cell.x / float(MOUNTAIN_BLOCK)), floori(cell.y / float(MOUNTAIN_BLOCK)))
	var roll := absi(hash("mountain:%d:%d:%d" % [_map.seed_value, block.x, block.y]))
	if roll % 100 >= int(MOUNTAIN_DENSITY * 100.0):
		return &""  # Block ohne Kulisse
	var chosen := block * MOUNTAIN_BLOCK + Vector2i((roll / 100) % MOUNTAIN_BLOCK, (roll / 1000) % MOUNTAIN_BLOCK)
	if cell != chosen:
		return &""
	return StringName(variants[(roll / 10000) % variants.size()])

## Streut wilde Ambient-Tiere in ihre Habitate (deterministisch aus dem Seed).
func _spawn_ambient_life() -> void:
	for child in _ambient_root.get_children():
		child.queue_free()
	var count := clampi(int(_map.width * _map.height * AMBIENT_DENSITY), 0, AMBIENT_MAX)
	for spawn in AmbientLife.spawn_points(_map, Database.animals, count):
		var sprite := _add_sprite(_ambient_root, StringName("animal_%s" % spawn["type"]), spawn["cell"], Vector2(0, -6))
		# Wander-Zustand: Startpunkt merken, zufaellige Anfangsrichtung + Anim-Phase.
		sprite.set_meta("home", sprite.position)
		sprite.set_meta("velocity", Vector2.from_angle(randf() * TAU) * AMBIENT_SPEED)
		sprite.set_meta("phase", randf() * TAU)

## Laesst die Wildtiere gemaechlich um ihre Startzelle wandern (rein kosmetisch);
## am Rand des Wander-Radius werden sie sanft zurueck nach Hause gelenkt.
func _move_ambient(delta: float) -> void:
	for sprite in _ambient_root.get_children():
		var velocity: Vector2 = sprite.get_meta("velocity")
		if randf() < AMBIENT_TURN_CHANCE:
			velocity = Vector2.from_angle(randf() * TAU) * AMBIENT_SPEED
		sprite.position += velocity * delta
		sprite.z_index = int(sprite.position.y)  # Tiefe folgt der Bewegung
		_animate(sprite, ANIM_WALK, velocity)  # wandernde Tiere gehen
		var home: Vector2 = sprite.get_meta("home")
		if sprite.position.distance_to(home) > AMBIENT_WANDER_RADIUS:
			velocity = (home - sprite.position).normalized() * AMBIENT_SPEED
		sprite.set_meta("velocity", velocity)

## Zeichnet die Siedlung: ein Sprite je Gebaeude an seiner Zelle (M8).
func _on_buildings_changed(building_list: Array) -> void:
	if _map == null:
		return
	for child in _buildings_root.get_children():
		_buildings_root.remove_child(child)
		child.queue_free()
	# Bauplatz-Kacheln der vorigen Runde auf ihren Untergrund zuruecksetzen.
	# (_plot_tiles ist ein Dictionary, damit der Chunk-Renderer beim erneuten
	# Zeichnen einer Gegend die Einfaerbung unter Gebaeuden erhaelt.)
	for cell in _plot_tiles:
		_set_tile(_ground, cell, _ground_asset(cell))
	_plot_tiles.clear()
	for entry in building_list:
		# Weizenfeld = Acker, jedes andere Gebaeude = gerodete Erde (unter dem Sprite).
		var plot := "tile_farmland" if String(entry["def_id"]) == "wheat_farm" else "tile_dirt"
		_set_tile(_ground, entry["cell"], plot)
		_plot_tiles[entry["cell"]] = plot
		_add_sprite(_buildings_root, StringName("building_%s" % entry["def_id"]), entry["cell"], Vector2(0, -10))
	var building_cells: Array = []
	for entry in building_list:
		building_cells.append(entry["cell"])
	_spawn_paths(building_cells)
	_spawn_props(building_list)
	_spawn_livestock(building_list)

## Verbindet die Gebaeude zu einem Wegenetz und rendert es maskengetrieben
## (`tile_path_<maske>`), Wegweiser an Kreuzungen (§8.4/§8.6).
func _spawn_paths(building_cells: Array) -> void:
	_paths.clear()
	for child in _signs_root.get_children():
		child.queue_free()
	var network := PathNetwork.build(building_cells, _map)
	var building_set: Dictionary = {}
	for cell in building_cells:
		building_set[cell] = true
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for cell in network:
		if building_set.has(cell):
			continue  # Gebaeudezelle: der Bau-Sprite deckt sie ab
		var mask := 0
		for i in 4:
			if network.has(cell + dirs[i]):
				mask |= 1 << i
		# Netz-Zelle auf einem Fluss = Bruecke (Planken), sonst Erd-Weg.
		var kind := "bridge" if _map.is_river(cell) else "path"
		_set_tile(_paths, cell, "tile_%s_%d" % [kind, mask])
	for junction in PathNetwork.junctions(network):
		if building_set.has(junction):
			continue
		_add_sprite(_signs_root, &"feature_signpost", junction, Vector2(0, -6))

## Zeichnet Kleindeko (Brunnen/Heuhaufen/Zaun) neben Gebaeuden (§8.6).
func _spawn_props(building_list: Array) -> void:
	for child in _props_root.get_children():
		child.queue_free()
	for prop in SettlementProps.props_for(building_list, Database.buildings):
		_add_sprite(_props_root, StringName("feature_%s" % prop["type"]), prop["cell"], Vector2(0, -6))

## Zeichnet Nutztiere auf den Nachbarzellen passender Gebaeude (§8.5).
func _spawn_livestock(building_list: Array) -> void:
	for child in _livestock_root.get_children():
		child.queue_free()
	for spawn in AmbientLife.livestock_points(building_list, Database.animals):
		_add_sprite(_livestock_root, StringName("animal_%s" % spawn["type"]), spawn["cell"], Vector2(0, -6))

## Belegschaft hat sich geaendert (M16): Modell abgleichen, Sprites
## verschwundener Bewohner entfernen.
func _on_workforce_changed(building_list: Array) -> void:
	_village.sync(building_list, Database.buildings)
	var alive: Dictionary = {}
	for villager in _village.villagers:
		alive[villager.id] = true
	for id in _villager_sprites.keys():
		if not alive.has(id):
			_villager_sprites[id].queue_free()
			_villager_sprites.erase(id)

## Bewegt und zeichnet die Dorfbewohner: Position aus dem Modell, Animation
## prozedural (Lauf-Wippen, Blickrichtung, Arbeits-Wackeln beim Werken);
## im Gebaeude sind sie unsichtbar — sie treten aus der Tuer und kehren heim.
func _move_villagers(delta: float) -> void:
	if _map == null:
		return
	_village.advance(delta, _map)
	for villager in _village.villagers:
		var sprite: Sprite2D = _villager_sprites.get(villager.id)
		if sprite == null:
			sprite = Sprite2D.new()
			_set_animated_texture(sprite, &"unit_villager")
			sprite.set_meta("phase", villager.phase)
			sprite.set_meta("last_base", _cell_to_local(villager.pos))
			sprite.position = _cell_to_local(villager.pos) + Vector2(0, -10.0)
			_villagers_root.add_child(sprite)
			_villager_sprites[villager.id] = sprite
		sprite.visible = villager.state != VillageLife.STATE_HOME
		if not sprite.visible:
			continue
		var base := _cell_to_local(villager.pos)
		var walking: bool = villager.state == VillageLife.STATE_TO_WORK \
			or villager.state == VillageLife.STATE_TO_HOME
		var last_base: Vector2 = sprite.get_meta("last_base", base)
		var v := base - last_base  # Bewegung dieses Frames
		sprite.set_meta("last_base", base)
		sprite.position = base + Vector2(0, -10.0)
		sprite.z_index = int(base.y)
		var state := ANIM_WALK if walking else \
			(ANIM_WORK if villager.state == VillageLife.STATE_WORKING else ANIM_IDLE)
		_animate(sprite, state, v)
		# Werkeln-Wackeln (Hacken/Saegen) nur als Fallback, wenn kein <id>_work-Sheet.
		if state == ANIM_WORK and int(sprite.get_meta("frames", 1)) == 1:
			sprite.rotation = sin(_anim_time * 10.0 + villager.phase) * 0.12
		else:
			sprite.rotation = 0.0

## Fraktionale Zellkoordinaten -> lokale Pixel (lineare Iso-Abbildung;
## map_to_local kennt nur ganze Zellen).
func _cell_to_local(cell: Vector2) -> Vector2:
	var origin := _ground.map_to_local(Vector2i.ZERO)
	var basis_x := _ground.map_to_local(Vector2i(1, 0)) - origin
	var basis_y := _ground.map_to_local(Vector2i(0, 1)) - origin
	return origin + basis_x * cell.x + basis_y * cell.y

## Bewegt Kampf-Einheiten je Frame sanft zu ihrer Zielzelle und animiert sie
## (Gehen bei Bewegung, sonst Atmen) -> kein Sprung pro Tick.
func _glide_combat_units(delta: float) -> void:
	for unit in _last_units:
		var sprite: Sprite2D = _unit_sprites.get(unit["id"])
		if sprite == null:
			continue
		var target: Vector2 = sprite.get_meta("target", sprite.position)
		var before := sprite.position
		sprite.position = sprite.position.move_toward(target, COMBAT_GLIDE_SPEED * delta)
		sprite.z_index = int(sprite.position.y)
		var moving := sprite.position.distance_to(target) > 0.5
		_animate(sprite, ANIM_WALK if moving else _combat_idle_state(unit), sprite.position - before)
		# Treffer-Blitz ueber der laufenden Zustands-Animation (Grundfarbe -> Rot -> zurueck).
		var base: Color = sprite.get_meta("base_modulate", Color.WHITE)
		var hurt := maxf(0.0, float(sprite.get_meta("hurt", 0.0)) - delta)
		sprite.set_meta("hurt", hurt)
		sprite.modulate = base.lerp(HURT_FLASH, hurt / HURT_DURATION) if hurt > 0.0 else base

## Ruhezustand einer Einheit: schiessen (Fernkampf, Reichweite > 1) bzw. zuschlagen
## (Nahkampf), wenn ein Gegner in Reichweite ist, sonst untaetig.
func _combat_idle_state(unit: Dictionary) -> StringName:
	var reach := int(unit.get("attack_range", 1))
	var cell: Vector2i = unit["cell"]
	for other in _last_units:
		if other["faction"] != unit["faction"] \
				and maxi(absi(cell.x - other["cell"].x), absi(cell.y - other["cell"].y)) <= reach:
			return ANIM_SHOOT if reach > 1 else ANIM_ATTACK
	return ANIM_IDLE

## Startet die Sterbe-Animation eines Sprites (aus _unit_sprites entfernt, in _dying).
func _begin_death(sprite: Sprite2D) -> void:
	_apply_state(sprite, ANIM_DIE, sprite.get_meta("facing", &""))  # Richtung beibehalten
	sprite.scale = Vector2.ONE  # evtl. eingefrorenen Squash zuruecksetzen
	sprite.set_meta("dying", 0.0)
	_dying.append(sprite)

## Spielt die Sterbe-Animation (Sheet einmal ODER prozedural absacken+ausblenden)
## und entfernt das Sprite nach DIE_DURATION.
func _update_dying(delta: float) -> void:
	for i in range(_dying.size() - 1, -1, -1):
		var sprite: Sprite2D = _dying[i]
		var e: float = float(sprite.get_meta("dying", 0.0)) + delta
		sprite.set_meta("dying", e)
		var frames := int(sprite.get_meta("frames", 1))
		if frames > 1:
			sprite.frame = SpriteAnim.play_once_frame(e / DIE_DURATION, frames)
		else:
			sprite.offset = Vector2(0.0, e * DIE_SINK)  # absacken
			var m := sprite.modulate
			m.a = maxf(0.0, 1.0 - e / DIE_DURATION)     # ausblenden
			sprite.modulate = m
		if e >= DIE_DURATION:
			sprite.queue_free()
			_dying.remove_at(i)

## Zeichnet den Kampfzustand: gegnerischer Bergfried und alle Einheiten
## (Sprites werden je Einheiten-ID wiederverwendet; Gefallene verschwinden).
func _on_combat_state_changed(snapshot: Dictionary) -> void:
	if _map == null:
		return
	_update_enemy_keep(snapshot["keeps"][&"enemy"])
	var alive: Dictionary = {}
	for unit in snapshot["units"]:
		alive[unit["id"]] = true
		var sprite: Sprite2D = _unit_sprites.get(unit["id"])
		if sprite == null:
			sprite = Sprite2D.new()
			_set_animated_texture(sprite, StringName("unit_%s" % unit["type_id"]))
			var base := ENEMY_TINT if unit["faction"] == &"enemy" else Color.WHITE
			sprite.modulate = base
			sprite.set_meta("base_modulate", base)
			sprite.set_meta("hp", int(unit["hp"]))
			sprite.set_meta("phase", randf() * TAU)
			sprite.position = _ground.map_to_local(unit["cell"]) + Vector2(0, -8)  # Startpunkt
			_combat_root.add_child(sprite)  # NICHT _units_root (das gehoert dem F3-Perf-Test)
			_unit_sprites[unit["id"]] = sprite
		# Gesunkene HP = Treffer -> Zuck-Timer; Ziel fuers Gleiten setzen.
		if int(unit["hp"]) < int(sprite.get_meta("hp", int(unit["hp"]))):
			sprite.set_meta("hurt", HURT_DURATION)
		sprite.set_meta("hp", int(unit["hp"]))
		sprite.set_meta("target", _ground.map_to_local(unit["cell"]) + Vector2(0, -8))
	for id in _unit_sprites.keys():
		if not alive.has(id):
			_begin_death(_unit_sprites[id])  # Gefallene spielen erst die Sterbe-Animation
			_unit_sprites.erase(id)
	_last_units = snapshot["units"]
	if _selected_unit_id >= 0 and not alive.has(_selected_unit_id):
		_selected_unit_id = -1  # Auswahl ist gefallen
	_refresh_unit_highlights()

func _update_enemy_keep(keep: Dictionary) -> void:
	if _enemy_keep_sprite == null:
		_enemy_keep_sprite = Sprite2D.new()
		_enemy_keep_sprite.texture = AssetRegistry.get_texture(&"building_keep")
		_enemy_keep_sprite.modulate = ENEMY_TINT
		_combat_root.add_child(_enemy_keep_sprite)
	var keep_base := _ground.map_to_local(keep["cell"])
	_enemy_keep_sprite.position = keep_base + Vector2(0, -10)
	_enemy_keep_sprite.z_index = int(keep_base.y)
	_enemy_keep_sprite.visible = keep["hp"] > 0
	# Lagerfeuer als Lager-Stimmung daneben (verschwindet mit dem Bergfried).
	if _enemy_campfire == null:
		_enemy_campfire = Sprite2D.new()
		_enemy_campfire.texture = AssetRegistry.get_texture(&"feature_campfire")
		_combat_root.add_child(_enemy_campfire)
	_enemy_campfire.position = keep_base + Vector2(20, 2)
	_enemy_campfire.z_index = int(keep_base.y)
	_enemy_campfire.visible = keep["hp"] > 0

## Isometrisches TileSet mit einer Atlas-Quelle je Asset-ID (lazy befuellt).
func _make_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = AssetRegistry.TILE_SIZE
	_tile_sources.clear()
	return tile_set

## Erzeugt ein zellverankertes Sprite und tiefensortiert es global ueber alle Roots
## per z_index = Basis-Y der Zelle (weiter unten/naeher = weiter vorn).
func _add_sprite(root: Node2D, asset_id: StringName, cell: Vector2i, offset: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	_set_animated_texture(sprite, asset_id)
	var base := _ground.map_to_local(cell)
	sprite.position = base + offset
	sprite.z_index = int(base.y)
	root.add_child(sprite)
	return sprite

## Korrekte Boden-Kachel einer Zelle: Fluss/Wasser (Autotile-Maske) vor Sandufer
## (Tiefland-Ufer) vor normalem Biom. Auch fuer das Zuruecksetzen von Bauplaetzen.
func _ground_asset(cell: Vector2i) -> String:
	if _map.is_river(cell):
		return "tile_river_%d" % _map.water_edge_mask(cell)
	var biome := _map.get_biome(cell)
	if biome == &"water":
		return "tile_water_%d" % _map.water_edge_mask(cell)
	if _map.is_bank(cell) and (biome == &"grassland" or biome == &"valley"):
		return "tile_sand"  # Sandbank am Tiefland-Ufer (§8.4)
	return "tile_%s" % biome

## Setzt das Basis-Standbild und merkt die Asset-ID (fuer spaetere Zustands-Sheets).
func _set_animated_texture(sprite: Sprite2D, asset_id: StringName) -> void:
	sprite.texture = AssetRegistry.get_texture(asset_id)
	sprite.set_meta("asset_id", asset_id)

## Wechselt bei Zustands- ODER Richtungswechsel auf das passende Sheet (oder Standbild).
## Setzt frame nur zurueck, wenn sich die Textur wirklich aendert (kein Ruckeln, wenn
## z. B. eine nicht-gerichtete Datei fuer down/up dieselbe bleibt).
func _apply_state(sprite: Sprite2D, state: StringName, facing: StringName) -> void:
	if sprite.get_meta("state", &"") == state and sprite.get_meta("facing", &"") == facing:
		return
	var sheet := AssetRegistry.sprite_sheet(sprite.get_meta("asset_id", &""), state, facing)
	if sheet["texture"] != sprite.texture or int(sheet["hframes"]) != sprite.hframes:
		sprite.texture = sheet["texture"]
		sprite.hframes = sheet["hframes"]
		sprite.frame = 0
		sprite.set_meta("frames", sheet["hframes"])
	sprite.set_meta("state", state)
	sprite.set_meta("facing", facing)

## „Lebendige Bewegung" fuer einen Zustand. [param v] = Bewegung dieses Frames:
## v.x -> Links/Rechts-Spiegelung, v.y -> Iso-Richtung (down/up; nur bei Bewegung,
## sonst gehalten). Hat der Zustand+Richtung ein Sheet (frames > 1): Laufband abspielen
## (Verformung neutral). Sonst prozedural — Gehen (ANIM_WALK) = Bob/Squash, sonst Atmen.
## Position & z_index bleiben unberuehrt.
func _animate(sprite: Sprite2D, state: StringName, v: Vector2) -> void:
	if absf(v.x) > FACING_THRESHOLD:
		sprite.flip_h = v.x < 0.0
	var facing: StringName = sprite.get_meta("facing", &"")
	var vf := SpriteAnim.vertical_facing(v.y, FACING_THRESHOLD)
	if vf > 0:
		facing = ANIM_DOWN
	elif vf < 0:
		facing = ANIM_UP
	_apply_state(sprite, state, facing)
	var t := _anim_time + float(sprite.get_meta("phase", 0.0))
	if int(sprite.get_meta("frames", 1)) > 1:
		sprite.frame = SpriteAnim.walk_frame(t, int(sprite.get_meta("frames", 1)))
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE
	else:
		var walking := state == ANIM_WALK
		sprite.offset = SpriteAnim.offset_of(walking, t)
		sprite.scale = SpriteAnim.scale_of(walking, t)

func _set_tile(layer: TileMapLayer, cell: Vector2i, asset_id: String) -> void:
	if not _tile_sources.has(asset_id):
		var source := TileSetAtlasSource.new()
		source.texture = AssetRegistry.get_texture(StringName(asset_id))
		source.texture_region_size = AssetRegistry.TILE_SIZE
		source.create_tile(Vector2i.ZERO)
		_tile_sources[asset_id] = layer.tile_set.add_source(source)
	layer.set_cell(cell, _tile_sources[asset_id], Vector2i.ZERO)

## Ermittelt die Pixelgrenzen der Karte und meldet sie der Kamera.
func _update_bounds() -> void:
	var corners := [
		Vector2i(0, 0), Vector2i(_map.width - 1, 0),
		Vector2i(0, _map.height - 1), Vector2i(_map.width - 1, _map.height - 1),
	]
	_bounds = Rect2(_ground.map_to_local(corners[0]), Vector2.ZERO)
	for corner in corners:
		_bounds = _bounds.expand(_ground.map_to_local(corner))
	_bounds = _bounds.grow(64.0)
	EventBus.camera_bounds_changed.emit(_bounds)

## Performance-Test: 200 wandernde Einheiten spawnen bzw. entfernen.
func _toggle_perf_units() -> void:
	if _units_root.get_child_count() > 0:
		for child in _units_root.get_children():
			child.queue_free()
		return
	for i in PERF_UNIT_COUNT:
		var unit := Sprite2D.new()
		_set_animated_texture(unit, &"unit_villager")
		unit.position = Vector2(
			randf_range(_bounds.position.x, _bounds.end.x),
			randf_range(_bounds.position.y, _bounds.end.y))
		unit.set_meta("velocity", Vector2.from_angle(randf() * TAU) * PERF_UNIT_SPEED)
		unit.set_meta("phase", randf() * TAU)
		unit.z_index = int(unit.position.y)
		_units_root.add_child(unit)

## Bewegt die Test-Einheiten (Abprallen an den Kartengrenzen).
func _move_perf_units(delta: float) -> void:
	for unit in _units_root.get_children():
		var velocity: Vector2 = unit.get_meta("velocity")
		unit.position += velocity * delta
		if not _bounds.has_point(unit.position):
			velocity = -velocity
			unit.set_meta("velocity", velocity)
			unit.position += velocity * delta
		unit.z_index = int(unit.position.y)
		_animate(unit, ANIM_WALK, velocity)
