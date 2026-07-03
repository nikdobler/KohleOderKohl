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
## Grosse Bergkulissen (§8.2): Wahrscheinlichkeit je Hochland-Zelle und Mindestabstand.
const MOUNTAIN_DENSITY: float = 0.25
const MOUNTAIN_SPACING: int = 3
## Wanderung der Wildtiere: gemaechliches Tempo, Radius um die Startzelle und
## Wahrscheinlichkeit je Frame, spontan die Richtung zu wechseln.
const AMBIENT_SPEED: float = 8.0
const AMBIENT_WANDER_RADIUS: float = 24.0
const AMBIENT_TURN_CHANCE: float = 0.01

var _map: WorldMap
var _ground: TileMapLayer
var _decor: TileMapLayer  # rein dekoratives Gruenzeug (ueber Boden, unter Merkmalen)
var _mountain_root: Node2D  # grosse Bergkulissen (Y-sortiert, hinter der Siedlung)
var _paths: TileMapLayer  # Wegenetz zwischen Gebaeuden (ueber Boden, unter Merkmalen)
var _signs_root: Node2D  # Wegweiser an Weg-Kreuzungen
var _features: TileMapLayer
var _ambient_root: Node2D  # wilde Ambient-Tiere (unter Gebaeuden gezeichnet)
var _buildings_root: Node2D
var _props_root: Node2D  # Kleindeko (Brunnen/Heuhaufen/Zaun) neben Gebaeuden
var _livestock_root: Node2D  # Nutztiere neben Gebaeuden (ueber Gebaeuden gezeichnet)
var _combat_root: Node2D
var _units_root: Node2D
var _bounds := Rect2()
var _tile_sources: Dictionary = {}  # Asset-ID -> Quellen-ID im TileSet
var _unit_sprites: Dictionary = {}  # Einheiten-ID -> Sprite2D
var _enemy_keep_sprite: Sprite2D
var _enemy_campfire: Sprite2D  # Lagerfeuer neben dem gegnerischen Bergfried (§8.6)
var _farmland_cells: Array = []  # aktuell als Acker (tile_farmland) eingefaerbte Bodenzellen
var _selected_unit_id := -1  # per Klick gewaehlte eigene Einheit (M13)
var _last_units: Array = []  # letzter Kampf-Schnappschuss (fuer Klick-Treffer)
var _build_def_id: StringName = &""  # aktiver Bau-Modus (leer = aus)
var _demolish_mode := false  # aktiver Abriss-Modus (M11)
var _ghost: Sprite2D
var _ghost_cell := Vector2i.ZERO  # Zelle, auf der der Geist steht (= Bau-/Abrissziel)

func _ready() -> void:
	_ground = TileMapLayer.new()
	_decor = TileMapLayer.new()
	_mountain_root = Node2D.new()
	_mountain_root.y_sort_enabled = true  # Kulissen verdecken sich nach Basis-Y
	_paths = TileMapLayer.new()
	_signs_root = Node2D.new()
	_features = TileMapLayer.new()
	_ambient_root = Node2D.new()
	_buildings_root = Node2D.new()
	_props_root = Node2D.new()
	_livestock_root = Node2D.new()
	_combat_root = Node2D.new()
	_units_root = Node2D.new()
	for child in [_ground, _decor, _mountain_root, _paths, _features, _ambient_root, _buildings_root, _props_root, _signs_root, _livestock_root, _combat_root, _units_root]:
		add_child(child)
	_ghost = Sprite2D.new()
	_ghost.visible = false
	add_child(_ghost)
	EventBus.world_changed.connect(_on_world_changed)
	EventBus.buildings_changed.connect(_on_buildings_changed)
	EventBus.combat_state_changed.connect(_on_combat_state_changed)
	EventBus.tower_shots.connect(_on_tower_shots)
	EventBus.build_mode_selected.connect(_enter_build_mode)
	EventBus.demolish_mode_selected.connect(_enter_demolish_mode)
	EventBus.build_preview_result.connect(_on_preview_result)

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

func _refresh_unit_highlights() -> void:
	for unit in _last_units:
		var sprite: Sprite2D = _unit_sprites.get(unit["id"])
		if sprite == null:
			continue
		if unit["id"] == _selected_unit_id:
			sprite.modulate = Color(1.6, 1.6, 0.7)  # gelb hervorgehoben
		elif unit["faction"] == &"enemy":
			sprite.modulate = ENEMY_TINT
		else:
			sprite.modulate = Color.WHITE

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

func _process(delta: float) -> void:
	_move_perf_units(delta)
	_move_ambient(delta)
	_follow_mouse_in_build_mode()

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

## Baut die Kachel-Darstellung aus dem Kartenmodell neu auf.
func _on_world_changed(map: WorldMap) -> void:
	_map = map
	_ground.tile_set = _make_tile_set()
	_decor.tile_set = _ground.tile_set
	_paths.tile_set = _ground.tile_set
	_features.tile_set = _ground.tile_set
	_ground.clear()
	_decor.clear()
	_paths.clear()
	_features.clear()
	_farmland_cells.clear()  # Boden wird neu gefuellt -> Acker-Markierungen verwerfen
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var biome := map.get_biome(cell)
			# Fluss vor Wasser vor normalem Biom; Autotile-Maske waehlt die Kantenkachel.
			if map.is_river(cell):
				_set_tile(_ground, cell, "tile_river_%d" % map.water_edge_mask(cell))
			elif biome == &"water":
				_set_tile(_ground, cell, "tile_water_%d" % map.water_edge_mask(cell))
			else:
				_set_tile(_ground, cell, "tile_%s" % biome)
			var feature := map.get_feature(cell)
			if feature != &"":
				# Gameplay bleibt "feature" (z. B. rock); nur die Optik variiert.
				var variant := FeatureVariants.pick(feature, cell, Database.feature_variants, map.seed_value)
				_set_tile(_features, cell, "feature_%s" % variant)
			var decor := map.get_decor(cell)
			if decor != &"":
				_set_tile(_decor, cell, "feature_%s" % decor)
	_update_bounds()
	_spawn_mountains()
	_spawn_ambient_life()

## Setzt grosse Bergkulissen in die Hochlagen (deterministisch, Basis auf der Zelle,
## Y-sortiert via _mountain_root). Sprite-Offset hebt die Grafik nach oben, die
## Node-Position bleibt auf der Zelle -> korrekte Tiefensortierung nach Basis.
func _spawn_mountains() -> void:
	for child in _mountain_root.get_children():
		child.queue_free()
	var biome_mountains: Dictionary = {}
	for biome_id in Database.biomes:
		var variants: Array = Database.biomes[biome_id].get("mountains", [])
		if not variants.is_empty():
			biome_mountains[StringName(biome_id)] = variants
	for spot in MountainScenery.backdrops(_map, biome_mountains, MOUNTAIN_DENSITY, MOUNTAIN_SPACING):
		var sprite := Sprite2D.new()
		var tex := AssetRegistry.get_texture(StringName("feature_%s" % spot["type"]))
		sprite.texture = tex
		sprite.offset = Vector2(0, -tex.get_height() / 2.0)  # Basis auf der Zelle verankern
		sprite.position = _ground.map_to_local(spot["cell"])
		_mountain_root.add_child(sprite)

## Streut wilde Ambient-Tiere in ihre Habitate (deterministisch aus dem Seed).
func _spawn_ambient_life() -> void:
	for child in _ambient_root.get_children():
		child.queue_free()
	var count := clampi(int(_map.width * _map.height * AMBIENT_DENSITY), 0, AMBIENT_MAX)
	for spawn in AmbientLife.spawn_points(_map, Database.animals, count):
		var sprite := Sprite2D.new()
		sprite.texture = AssetRegistry.get_texture(StringName("animal_%s" % spawn["type"]))
		sprite.position = _ground.map_to_local(spawn["cell"]) + Vector2(0, -6)
		# Wander-Zustand: Startpunkt merken, zufaellige Anfangsrichtung.
		sprite.set_meta("home", sprite.position)
		sprite.set_meta("velocity", Vector2.from_angle(randf() * TAU) * AMBIENT_SPEED)
		_ambient_root.add_child(sprite)

## Laesst die Wildtiere gemaechlich um ihre Startzelle wandern (rein kosmetisch);
## am Rand des Wander-Radius werden sie sanft zurueck nach Hause gelenkt.
func _move_ambient(delta: float) -> void:
	for sprite in _ambient_root.get_children():
		var velocity: Vector2 = sprite.get_meta("velocity")
		if randf() < AMBIENT_TURN_CHANCE:
			velocity = Vector2.from_angle(randf() * TAU) * AMBIENT_SPEED
		sprite.position += velocity * delta
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
	# Acker-Kacheln der vorigen Runde auf ihr Biom zuruecksetzen.
	for cell in _farmland_cells:
		_set_tile(_ground, cell, "tile_%s" % _map.get_biome(cell))
	_farmland_cells.clear()
	for entry in building_list:
		# Weizenfelder faerben ihren Bauplatz als Acker ein (unter dem Sprite).
		if String(entry["def_id"]) == "wheat_farm":
			_set_tile(_ground, entry["cell"], "tile_farmland")
			_farmland_cells.append(entry["cell"])
		var sprite := Sprite2D.new()
		sprite.texture = AssetRegistry.get_texture(StringName("building_%s" % entry["def_id"]))
		sprite.position = _ground.map_to_local(entry["cell"]) + Vector2(0, -10)
		_buildings_root.add_child(sprite)
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
		_set_tile(_paths, cell, "tile_path_%d" % mask)
	for junction in PathNetwork.junctions(network):
		if building_set.has(junction):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = AssetRegistry.get_texture(&"feature_signpost")
		sprite.position = _ground.map_to_local(junction) + Vector2(0, -6)
		_signs_root.add_child(sprite)

## Zeichnet Kleindeko (Brunnen/Heuhaufen/Zaun) neben Gebaeuden (§8.6).
func _spawn_props(building_list: Array) -> void:
	for child in _props_root.get_children():
		child.queue_free()
	for prop in SettlementProps.props_for(building_list, Database.buildings):
		var sprite := Sprite2D.new()
		sprite.texture = AssetRegistry.get_texture(StringName("feature_%s" % prop["type"]))
		sprite.position = _ground.map_to_local(prop["cell"]) + Vector2(0, -6)
		_props_root.add_child(sprite)

## Zeichnet Nutztiere auf den Nachbarzellen passender Gebaeude (§8.5).
func _spawn_livestock(building_list: Array) -> void:
	for child in _livestock_root.get_children():
		child.queue_free()
	for spawn in AmbientLife.livestock_points(building_list, Database.animals):
		var sprite := Sprite2D.new()
		sprite.texture = AssetRegistry.get_texture(StringName("animal_%s" % spawn["type"]))
		sprite.position = _ground.map_to_local(spawn["cell"]) + Vector2(0, -6)
		_livestock_root.add_child(sprite)

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
			sprite.texture = AssetRegistry.get_texture(StringName("unit_%s" % unit["type_id"]))
			if unit["faction"] == &"enemy":
				sprite.modulate = ENEMY_TINT
			_combat_root.add_child(sprite)  # NICHT _units_root (das gehoert dem F3-Perf-Test)
			_unit_sprites[unit["id"]] = sprite
		sprite.position = _ground.map_to_local(unit["cell"]) + Vector2(0, -8)
	for id in _unit_sprites.keys():
		if not alive.has(id):
			_unit_sprites[id].queue_free()
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
	_enemy_keep_sprite.position = _ground.map_to_local(keep["cell"]) + Vector2(0, -10)
	_enemy_keep_sprite.visible = keep["hp"] > 0
	# Lagerfeuer als Lager-Stimmung daneben (verschwindet mit dem Bergfried).
	if _enemy_campfire == null:
		_enemy_campfire = Sprite2D.new()
		_enemy_campfire.texture = AssetRegistry.get_texture(&"feature_campfire")
		_combat_root.add_child(_enemy_campfire)
	_enemy_campfire.position = _ground.map_to_local(keep["cell"]) + Vector2(20, 2)
	_enemy_campfire.visible = keep["hp"] > 0

## Isometrisches TileSet mit einer Atlas-Quelle je Asset-ID (lazy befuellt).
func _make_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = AssetRegistry.TILE_SIZE
	_tile_sources.clear()
	return tile_set

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
		unit.texture = AssetRegistry.get_texture(&"unit_villager")
		unit.position = Vector2(
			randf_range(_bounds.position.x, _bounds.end.x),
			randf_range(_bounds.position.y, _bounds.end.y))
		unit.set_meta("velocity", Vector2.from_angle(randf() * TAU) * PERF_UNIT_SPEED)
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
