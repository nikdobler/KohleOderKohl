extends Node
## GameController — verbindet Wirtschaftslogik, Forschung, Tick-Loop und
## Speichersystem mit der UI (M1–M3). Enthaelt selbst keine Simulationsregeln;
## die liegen in [Economy]/[BuildingInstance]/[Research]. Kommunikation laeuft
## entkoppelt ueber [EventBus].

## Szenario, das beim Spielstart geladen wird (M7: das einzige; ein
## Szenario-Auswahlmenue folgt spaeter).
const DEFAULT_SCENARIO: String = "erste_ernte"
## Laenge eines Produktionsschritts in Sekunden.
const TICK_SECONDS: float = 1.0
## Kartengroesse in Kacheln (quadratisch).
const MAP_SIZE: int = 64
## Feinde innerhalb dieses Radius um den Bergfried gelten als Bedrohung
## (druecken die Laune, M8).
const THREAT_RADIUS: int = 10
## Kampagnen-Fortschritt lebt getrennt vom Spielstand (ueberlebt Neustarts).
const CAMPAIGN_SAVE_PATH: String = "user://campaign.json"

var _economy: Economy
var _research: Research
var _world: WorldMap
var _combat: CombatSystem
var _dialogue: DialogueSystem
var _scenario: Scenario
var _campaign: Campaign
var _campaign_chapter: String = ""  # aktives Kapitel ("" = freies Szenario)
var _timer: Timer

func _ready() -> void:
	_campaign = Campaign.from_def(Database.campaign)
	_campaign.from_dict(SaveManager.load_game(CAMPAIGN_SAVE_PATH))
	_connect_events()
	_start_tick_timer()
	_start_scenario(DEFAULT_SCENARIO)
	# Erst nach dem Bereitmachen der UI senden (HUD ist zu diesem Zeitpunkt
	# evtl. noch nicht verbunden) -> deferred.
	_emit_full_state.call_deferred()

## Startet ein (neues) Spiel mit dem Szenario — auch "Neues Spiel"-Flow (M12).
func _start_scenario(scenario_id: String) -> void:
	if not Database.scenarios.has(scenario_id):
		push_error("GameController: Szenario '%s' fehlt in /data/scenarios." % scenario_id)
	_economy = Economy.new()
	_economy.luxuries = _luxury_defs()
	_research = Research.from_defs(Database.techs)
	_dialogue = DialogueSystem.from_defs(Database.dialogues)
	_scenario = Scenario.from_def(Database.scenarios.get(scenario_id, {}))
	_world = WorldMap.new()
	_world.generate(randi(), MAP_SIZE, MAP_SIZE, Database.biomes)
	_apply_scenario_start()
	_setup_combat()

## Luxusgueter aus resources.json ("luxury_mood") fuer die Economy.
func _luxury_defs() -> Dictionary:
	var luxuries: Dictionary = {}
	for res_id in Database.resources:
		var mood := int(Database.resources[res_id].get("luxury_mood", 0))
		if mood > 0:
			luxuries[StringName(res_id)] = mood
	return luxuries

## Neues Spiel ueber das Szenario-Menue (freies Szenario, keine Kampagne).
func _on_scenario_selected(scenario_id: String) -> void:
	_campaign_chapter = ""
	_start_scenario(scenario_id)
	EventBus.game_loaded.emit()  # UI raeumt dynamische Zeilen
	EventBus.dialogue_ended.emit()
	_emit_full_state()

## Kampagnen-Kapitel starten (M14): Szenario laden + Intro-Text zeigen.
func _on_campaign_chapter_selected(chapter_id: String) -> void:
	var chapter := _campaign.chapter(chapter_id)
	if chapter.is_empty() or not _campaign.is_unlocked(chapter_id):
		return
	_campaign_chapter = chapter_id
	_start_scenario(String(chapter.get("scenario", "")))
	EventBus.game_loaded.emit()
	EventBus.dialogue_ended.emit()
	_emit_full_state()
	EventBus.story_shown.emit(String(chapter.get("title", "")), String(chapter.get("intro", "")), false)

func _on_menu_visible(menu_visible: bool) -> void:
	_timer.paused = menu_visible

## Baut den Kampf gemaess spec_kampfsystem.md auf: Spieler-Bergfried auf
## Bauplatz 0, Gegner-Siedlung versetzt davon (enemy.json, vom Szenario
## ueberschreibbar — z. B. haertere Wellen bei einer Belagerung).
func _setup_combat() -> void:
	_combat = CombatSystem.new()
	var enemy_cfg: Dictionary = Database.enemy.duplicate(true)
	enemy_cfg.merge(_scenario.enemy_override(), true)
	var player_keep_cell: Vector2i = _world.building_slots(1)[0]
	var offset: Array = enemy_cfg.get("keep_offset", [16, 16])
	var enemy_keep_cell := _world.nearest_free_cell(
		player_keep_cell + Vector2i(int(offset[0]), int(offset[1])))
	_combat.setup(Database.units,
		{"cell": player_keep_cell, "hp": int(Database.get_building_def(&"keep").get("hp", 100))},
		{"cell": enemy_keep_cell, "hp": int(enemy_cfg.get("keep_hp", 100))},
		enemy_cfg, randi())
	_combat.setup_grid(_world.width, _world.height, _world.impassable_cells())
	_register_structures()

## Traegt alle Festungswerke der Wirtschaft (hp > 0, ausser Bergfried) als
## Kampf-Hindernisse ein — wichtig fuer Szenarien mit Start-Befestigung.
func _register_structures() -> void:
	for building in _economy.buildings:
		var def := Database.get_building_def(building.def_id)
		if building.def_id == &"keep" or int(def.get("hp", 0)) <= 0:
			continue
		var stats := _ranged_stats(def)
		_combat.add_obstacle(building.cell, building.def_id, int(def["hp"]),
			bool(def.get("passable", false)), stats["attack"], stats["range"])

## Fernkampf-Werte eines Gebaeudes — nur wenn die noetige FE erforscht ist.
func _ranged_stats(def: Dictionary) -> Dictionary:
	var ranged: Dictionary = def.get("ranged", {})
	if ranged.is_empty():
		return {"attack": 0, "range": 0}
	var required := String(ranged.get("requires_tech", ""))
	if required != "" and not _research.is_researched(StringName(required)):
		return {"attack": 0, "range": 0}
	return {"attack": int(ranged.get("attack", 0)), "range": int(ranged.get("range", 0))}

## Nachruestung bestehender Werke, wenn eine Fernkampf-FE erforscht wurde.
func _refresh_ranged_structures() -> void:
	for building in _economy.buildings:
		var stats := _ranged_stats(Database.get_building_def(building.def_id))
		if stats["attack"] > 0:
			_combat.set_obstacle_ranged(building.cell, stats["attack"], stats["range"])

## Wendet die Startbedingungen des Szenarios an: Bestand, Siedlung
## (Reihenfolge = Tick-/Bauplatz-Reihenfolge, Bergfried zuerst) und
## bereits erforschte Technologien (kostenlos, ohne Gebaeude-Spawn).
func _apply_scenario_start() -> void:
	_economy.stock = _scenario.start_stock()
	var entries := _scenario.start_buildings()
	var slots := _world.building_slots(entries.size())
	for i in entries.size():
		var def := Database.get_building_def(entries[i]["id"])
		if def.is_empty():
			push_error("GameController: Gebaeude '%s' fehlt in der Datenbank." % entries[i]["id"])
			continue
		var building := BuildingInstance.from_def(def)
		building.set_workers(int(entries[i]["workers"]))
		building.cell = slots[i] if i < slots.size() else Vector2i.ZERO
		_economy.add_building(building)
	for tech_id in _scenario.start_researched():
		_research.grant(tech_id)

func _connect_events() -> void:
	EventBus.worker_change_requested.connect(_on_worker_change)
	EventBus.research_requested.connect(_on_research_requested)
	EventBus.recruit_requested.connect(_on_recruit)
	EventBus.stance_toggle_requested.connect(_on_stance_toggle)
	EventBus.scenario_selected.connect(_on_scenario_selected)
	EventBus.campaign_chapter_selected.connect(_on_campaign_chapter_selected)
	EventBus.scenario_menu_visible.connect(_on_menu_visible)
	EventBus.dialogue_advance_requested.connect(_on_dialogue_advance)
	EventBus.build_preview_requested.connect(_on_build_preview)
	EventBus.build_requested.connect(_on_build)
	EventBus.demolish_preview_requested.connect(_on_demolish_preview)
	EventBus.demolish_requested.connect(_on_demolish)
	EventBus.ration_change_requested.connect(_on_ration_change)
	EventBus.work_change_requested.connect(_on_work_change)
	EventBus.tax_change_requested.connect(_on_tax_change)
	EventBus.trade_requested.connect(_on_trade)
	EventBus.unit_move_requested.connect(_on_unit_move)
	EventBus.save_requested.connect(_on_save)
	EventBus.load_requested.connect(_on_load)

func _start_tick_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_SECONDS
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)

## Ein Produktionsschritt: Wirtschaft, Kampf und Dialog-Trigger im selben Tick.
func _on_tick() -> void:
	for resource_id in _economy.tick():
		EventBus.stock_changed.emit(resource_id, _economy.get_stock(resource_id))
	EventBus.satisfaction_changed.emit(_economy.satisfaction)
	_research_tick()
	_combat_tick()
	_scenario_tick()
	_check_dialogues()

## Szenario-Events feuern, Auftraege pruefen und Ziel pruefen (Effekte sind
## Daten-Regeln; "wave" loest Angriffswellen aus, "dialogue" laesst einen
## Charakter skriptgesteuert auftreten — M12/M14).
func _scenario_tick() -> void:
	for event in _scenario.pending_events(_game_snapshot()):
		for resource_id in Scenario.apply_effects(event.get("effects", []), _economy):
			EventBus.stock_changed.emit(resource_id, _economy.get_stock(resource_id))
		_apply_controller_effects(event.get("effects", []))
		EventBus.satisfaction_changed.emit(_economy.satisfaction)
		EventBus.scenario_event.emit(String(event.get("message", "")))
	_quest_tick()
	if _scenario.check_goal(_game_snapshot()):
		EventBus.scenario_event.emit("Ziel erreicht: %s" % _scenario.goal_description())
		EventBus.scenario_state_changed.emit(_scenario_info())
		if _campaign_chapter != "":
			_complete_campaign_chapter()

## Effekt-Typen, die Modelle ausserhalb der Wirtschaft brauchen.
func _apply_controller_effects(effects: Array) -> void:
	for effect in effects:
		match String(effect.get("type", "")):
			"wave":
				_combat.force_wave(int(effect.get("size", 1)))
			"dialogue":
				_force_dialogue(String(effect.get("npc", "")), String(effect.get("dialogue", "")))

## Skriptgesteuerter Charakter-Auftritt (Kampagnen-Story, M14).
func _force_dialogue(npc_id: String, dialogue_id: String) -> void:
	var result := _dialogue.force_start(npc_id, dialogue_id, _game_snapshot())
	if not result.is_empty():
		EventBus.dialogue_started.emit(result["npc"], result["node"])

## Abgeschlossene Auftraege (Side-Quests, M14): Belohnung anwenden + melden.
func _quest_tick() -> void:
	var done := _scenario.pending_quests(_game_snapshot())
	if done.is_empty():
		return
	for quest in done:
		for resource_id in Scenario.apply_effects(quest.get("reward", []), _economy):
			EventBus.stock_changed.emit(resource_id, _economy.get_stock(resource_id))
		EventBus.satisfaction_changed.emit(_economy.satisfaction)
		EventBus.scenario_event.emit("Auftrag erledigt: %s" % String(quest.get("description", "")))
	EventBus.quest_state_changed.emit(_scenario.quest_states())

## Kapitel abgeschlossen: Fortschritt dauerhaft sichern, naechstes Kapitel
## freischalten und den Story-Abspann zeigen.
func _complete_campaign_chapter() -> void:
	var chapter := _campaign.chapter(_campaign_chapter)
	_campaign.complete(_campaign_chapter)
	SaveManager.save_game(_campaign.to_dict(), CAMPAIGN_SAVE_PATH)
	EventBus.campaign_state_changed.emit(_campaign.overview())
	EventBus.story_shown.emit(String(chapter.get("title", "")), String(chapter.get("outro", "")),
		_campaign.next_chapter_id(_campaign_chapter) != "")

func _scenario_info() -> Dictionary:
	return {
		"display_name": _scenario.display_name(),
		"goal": _scenario.goal_description(),
		"completed": _scenario.completed,
	}

## Prueft die Dialog-Trigger gegen den aktuellen Spielzustand.
func _check_dialogues() -> void:
	if _dialogue.is_active():
		return
	var result := _dialogue.check_triggers(_game_snapshot())
	if not result.is_empty():
		EventBus.dialogue_started.emit(result["npc"], result["node"])

## Weiterschalten bzw. Antwort waehlen; leeres Ergebnis == Dialog beendet.
func _on_dialogue_advance(choice_index: int) -> void:
	var result := _dialogue.advance(choice_index)
	if result.is_empty():
		EventBus.dialogue_ended.emit()
	else:
		EventBus.dialogue_node_changed.emit(result["npc"], result["node"])

## Neutraler Zustands-Schnappschuss fuer die Trigger-Auswertung
## (String-Schluessel, damit das Dialogsystem JSON-kompatibel bleibt).
func _game_snapshot() -> Dictionary:
	var stock: Dictionary = {}
	for key in _economy.stock:
		stock[String(key)] = int(_economy.stock[key])
	var researched: Array = []
	for id in _research.researched:
		researched.append(String(id))
	var buildings: Dictionary = {}
	for building in _economy.buildings:
		buildings[String(building.def_id)] = int(buildings.get(String(building.def_id), 0)) + 1
	return {
		"tick": _economy.tick_count,
		"stock": stock,
		"satisfaction": _economy.satisfaction,
		"researched": researched,
		"combat_status": String(_combat.status),
		"buildings": buildings,
	}

## Kampfschritt: Ereignisse melden, Gefallene geben Wohnraum frei.
func _combat_tick() -> void:
	_sync_threat()
	var events := _combat.tick()
	var shots: Array = []
	for event in events:
		if event.get("type", "") == "tower_shot":
			shots.append(event)
		else:
			_handle_combat_event(event)
	if not shots.is_empty():
		EventBus.tower_shots.emit(shots)
	_sync_population()
	EventBus.combat_state_changed.emit(_combat.snapshot())

## Uebersetzt Kampfereignisse in Meldungen; Sieg loest den FE-Transfer aus.
func _handle_combat_event(event: Dictionary) -> void:
	match event.get("type", ""):
		"wave":
			EventBus.combat_event.emit("Angriffswelle! %d Feinde im Anmarsch." % int(event["size"]))
		"unit_killed":
			if event["faction"] == CombatSystem.FACTION_PLAYER:
				EventBus.combat_event.emit("Ein Schwertkämpfer ist gefallen.")
		"structure_destroyed":
			_on_structure_destroyed(event)
		"victory":
			_on_conquest()
		"defeat":
			EventBus.combat_event.emit("Niederlage! Der Bergfried ist gefallen.")

## Zerstoertes Festungswerk aus der Siedlung entfernen (tot ist tot).
func _on_structure_destroyed(event: Dictionary) -> void:
	_economy.remove_building_at(event["cell"])
	EventBus.buildings_changed.emit(_building_list())
	_emit_market_state()
	var name: String = Database.get_building_def(event["def_id"]).get("display_name", "Ein Bauwerk")
	EventBus.combat_event.emit("%s wurde zerstört — Bresche!" % name)

## Bedrohungslage: Feinde nahe dem Bergfried druecken die Laune (M8).
func _sync_threat() -> void:
	var keep_cell: Vector2i = _combat.keeps[CombatSystem.FACTION_PLAYER]["cell"]
	for unit in _combat.units:
		if unit.faction == CombatSystem.FACTION_ENEMY and unit.hp > 0 \
				and _combat._cheb(unit.cell, keep_cell) <= THREAT_RADIUS:
			_economy.set_threatened()
			return

## Eroberung (Spez. 1.4): genau eine fehlende Technologie des Gegners
## wird freigeschaltet — deterministisch die guenstigste.
func _on_conquest() -> void:
	var tech_id := _research.cheapest_missing_from(Database.enemy.get("researched", []))
	if tech_id == &"":
		EventBus.combat_event.emit("Sieg! Der Gegner ist erobert.")
		return
	var result := _research.grant(tech_id)
	if result["ok"]:
		_apply_unlocks(result)
		_emit_tech_states()
	var tech_name: String = Database.get_tech_def(tech_id).get("display_name", String(tech_id))
	EventBus.combat_event.emit("Sieg! Erbeutete Technologie: %s." % tech_name)

## Rekrutierung (Spez. Abschnitt 2): kostet Ressourcen UND einen Bewohner.
func _on_recruit(unit_type: StringName) -> void:
	if _combat.status != CombatSystem.STATUS_ACTIVE:
		return
	if not _recruit_options().has(unit_type):
		EventBus.combat_event.emit("Dieser Kriegertyp ist noch nicht verfuegbar.")
		return
	if _economy.free_housing() <= 0:
		EventBus.combat_event.emit("Kein Wohnraum fuer weitere Soldaten.")
		return
	var cost := _typed_cost(Database.get_unit_def(unit_type).get("cost", {}))
	for res in cost:
		if _economy.get_stock(res) < cost[res]:
			EventBus.combat_event.emit("Nicht genug Ressourcen fuer die Rekrutierung.")
			return
	for res in cost:
		_economy.stock[res] = _economy.get_stock(res) - cost[res]
		EventBus.stock_changed.emit(res, _economy.get_stock(res))
	var keep_cell: Vector2i = _combat.keeps[CombatSystem.FACTION_PLAYER]["cell"]
	var spawn_cell := _world.nearest_free_cell(keep_cell + Vector2i(1, 1))
	_combat.add_unit(unit_type, CombatSystem.FACTION_PLAYER, spawn_cell,
		_combat.player_stance, keep_cell)
	_sync_population()
	EventBus.combat_state_changed.emit(_combat.snapshot())

## Rekrutierbare Kriegertypen (M12): hat Kosten (= Spieler-Einheit) und die
## noetige FE ("requires_tech") ist erforscht.
func _recruit_options() -> Array:
	var options: Array = []
	for unit_id in Database.units:
		var def: Dictionary = Database.units[unit_id]
		if not def.has("cost"):
			continue
		var required := String(def.get("requires_tech", ""))
		if required == "" or _research.is_researched(StringName(required)):
			options.append(StringName(unit_id))
	return options

## Haltung aller Spieler-Einheiten umschalten (Wache <-> Angriff).
func _on_stance_toggle() -> void:
	_combat.toggle_player_stance()
	EventBus.combat_state_changed.emit(_combat.snapshot())

## Soldaten belegen Wohnraum; Gefallene geben ihn frei (tot ist tot).
func _sync_population() -> void:
	var count := _combat.player_unit_count()
	if count != _economy.reserved_population:
		_economy.reserved_population = count
		EventBus.housing_changed.emit(_economy.assigned_workers() + count, _economy.housing_capacity())

## JSON-Kosten -> typisiert (StringName -> int).
func _typed_cost(raw: Dictionary) -> Dictionary:
	var cost: Dictionary = {}
	for key in raw:
		cost[StringName(key)] = int(raw[key])
	return cost

## Arbeiter eines Gebaeudetyps aendern (verteilt ueber alle Instanzen);
## Economy prueft max_workers und Wohnraum.
func _on_worker_change(def_id: StringName, delta: int) -> void:
	if not _economy.try_change_workers(def_id, delta):
		return
	EventBus.building_state_changed.emit(def_id, _economy.workers_of(def_id), _economy.max_workers_of(def_id))
	EventBus.housing_changed.emit(
		_economy.assigned_workers() + _economy.reserved_population, _economy.housing_capacity())

## Forschungsauftrag (M12: zeitbasiert): Kosten sofort, Abschluss nach
## duration_ticks; Techs ohne Dauer sind sofort fertig.
func _on_research_requested(tech_id: StringName) -> void:
	var result := _research.start_research(tech_id, _economy)
	if not result["ok"]:
		EventBus.research_failed.emit(result["reason"])
		return
	for res in _research.get_cost(tech_id):
		EventBus.stock_changed.emit(res, _economy.get_stock(res))
	if result["completed"] != &"":
		_finish_research(result)
	else:
		var tech_name: String = Database.get_tech_def(tech_id).get("display_name", String(tech_id))
		EventBus.combat_event.emit("Forschung begonnen: %s." % tech_name)
	_emit_tech_states()

## Forschungs-Tick: laufendes Projekt weiterzaehlen, Abschluss anwenden.
func _research_tick() -> void:
	if _research.active != &"":
		EventBus.research_progress.emit(_research.active, _research.progress_ratio())
	var result := _research.tick_research()
	if not result.is_empty():
		_finish_research(result)
		_emit_tech_states()

func _finish_research(result: Dictionary) -> void:
	_apply_unlocks(result)
	EventBus.recruit_options_changed.emit(_recruit_options())
	var tech_name: String = Database.get_tech_def(result["completed"]).get("display_name", "")
	EventBus.combat_event.emit("Forschung abgeschlossen: %s!" % tech_name)

## Freischaltungen anwenden: Gebaeude werden im Baumenue verfuegbar
## (seit M8 nicht mehr automatisch gebaut), Ressourcen in der UI sichtbar.
func _apply_unlocks(result: Dictionary) -> void:
	for resource_id in result["unlocked_resources"]:
		EventBus.stock_changed.emit(resource_id, _economy.get_stock(resource_id))
	if not result["unlocked_buildings"].is_empty():
		EventBus.build_options_changed.emit(_build_options())
	_refresh_ranged_structures()  # z. B. Bogenschiessen ruestet Tuerme nach

## Baubare Gebaeude fuers Menue: hat Platzierungsregeln und ist erforscht.
func _build_options() -> Array:
	var options: Array = []
	for building_id in Database.buildings:
		var typed := StringName(building_id)
		if Database.buildings[building_id].has("placement") and _research.is_building_unlocked(typed):
			options.append(typed)
	return options

## Belegte Zellen (Gebaeude, Festungswerke, gegnerischer Bergfried).
func _occupied_cells() -> Dictionary:
	var occupied: Dictionary = {}
	for building in _economy.buildings:
		occupied[building.cell] = true
	for cell in _combat.obstacles:
		occupied[cell] = true
	occupied[_combat.keeps[CombatSystem.FACTION_ENEMY]["cell"]] = true
	return occupied

## Vorschau fuer den Bau-Modus (Geist gruen/rot).
func _on_build_preview(def_id: StringName, cell: Vector2i) -> void:
	EventBus.build_preview_result.emit(cell, _can_build(def_id, cell)["ok"])

## Bauversuch: Regeln + Kosten pruefen, Gebaeude platzieren,
## Festungswerke zusaetzlich als Kampf-Hindernis registrieren.
func _on_build(def_id: StringName, cell: Vector2i) -> void:
	var verdict := _can_build(def_id, cell)
	if not verdict["ok"]:
		EventBus.build_failed.emit(verdict["reason"])
		return
	var def := Database.get_building_def(def_id)
	var cost := _typed_cost(def.get("cost", {}))
	for res in cost:
		_economy.stock[res] = _economy.get_stock(res) - cost[res]
		EventBus.stock_changed.emit(res, _economy.get_stock(res))
	var building := BuildingInstance.from_def(def)
	building.cell = cell
	_economy.add_building(building)
	if int(def.get("hp", 0)) > 0:
		var stats := _ranged_stats(def)
		_combat.add_obstacle(cell, def_id, int(def["hp"]),
			bool(def.get("passable", false)), stats["attack"], stats["range"])
	if building.max_workers > 0:
		EventBus.building_state_changed.emit(def_id, _economy.workers_of(def_id), _economy.max_workers_of(def_id))
	if building.housing_capacity > 0:
		EventBus.housing_changed.emit(
			_economy.assigned_workers() + _economy.reserved_population, _economy.housing_capacity())
	EventBus.buildings_changed.emit(_building_list())
	_emit_market_state()

## Bauregeln + Freischaltung + Kosten in einem Urteil.
func _can_build(def_id: StringName, cell: Vector2i) -> Dictionary:
	if not _research.is_building_unlocked(def_id):
		return {"ok": false, "reason": "Noch nicht erforscht."}
	var def := Database.get_building_def(def_id)
	var verdict := Placement.can_place(def, cell, _world, _occupied_cells())
	if not verdict["ok"]:
		return verdict
	var cost := _typed_cost(def.get("cost", {}))
	for res in cost:
		if _economy.get_stock(res) < cost[res]:
			return {"ok": false, "reason": "Nicht genug Ressourcen."}
	return {"ok": true, "reason": ""}

## Abriss-Vorschau: gruen, wenn hier etwas Abreissbares steht.
func _on_demolish_preview(cell: Vector2i) -> void:
	EventBus.build_preview_result.emit(cell, _can_demolish(cell)["ok"])

## Abriss (M11): 50 % Materialrueckgabe, Bergfried tabu, Wohnraum-Verlust
## entlaesst ueberzaehlige Arbeiter (Soldaten blockieren den Abriss).
func _on_demolish(cell: Vector2i) -> void:
	var verdict := _can_demolish(cell)
	if not verdict["ok"]:
		if verdict["reason"] != "":
			EventBus.build_failed.emit(verdict["reason"])
		return
	var building: BuildingInstance = _economy.get_building_at(cell)
	var def := Database.get_building_def(building.def_id)
	var refund_parts: Array = []
	var cost := _typed_cost(def.get("cost", {}))
	for res in cost:
		var amount := int(cost[res] / 2.0)
		if amount > 0:
			_economy.stock[res] = _economy.get_stock(res) + amount
			EventBus.stock_changed.emit(res, _economy.get_stock(res))
			refund_parts.append("+%d %s" % [amount, Database.get_resource_def(res).get("display_name", String(res))])
	_economy.remove_building_at(cell)
	_combat.remove_obstacle(cell)
	var evicted := _economy.evict_overflow_workers()
	_emit_worker_rows()
	# Letztes Gebaeude eines Typs weg -> 0/0 melden, HUD entfernt die Zeile.
	if building.max_workers > 0 and _economy.max_workers_of(building.def_id) == 0:
		EventBus.building_state_changed.emit(building.def_id, 0, 0)
	EventBus.housing_changed.emit(
		_economy.assigned_workers() + _economy.reserved_population, _economy.housing_capacity())
	EventBus.buildings_changed.emit(_building_list())
	_emit_market_state()
	var message: String = "%s abgerissen" % def.get("display_name", "Gebaeude")
	if not refund_parts.is_empty():
		message += " (%s)" % ", ".join(refund_parts)
	if evicted > 0:
		message += " — %d Bewohner entlassen" % evicted
	EventBus.combat_event.emit(message + ".")

## Darf hier abgerissen werden?
func _can_demolish(cell: Vector2i) -> Dictionary:
	var building: BuildingInstance = _economy.get_building_at(cell)
	if building == null:
		return {"ok": false, "reason": ""}  # leere Zelle: still ablehnen
	if building.def_id == &"keep":
		return {"ok": false, "reason": "Der Bergfried bleibt stehen."}
	if building.housing_capacity > 0 \
			and _economy.reserved_population > _economy.housing_capacity() - building.housing_capacity:
		return {"ok": false, "reason": "Zu wenig Wohnraum für die Soldaten."}
	return {"ok": true, "reason": ""}

## Aggregierte Arbeiterzeilen aller Gebaeudetypen an die UI melden.
func _emit_worker_rows() -> void:
	var seen: Dictionary = {}
	for building in _economy.buildings:
		if building.max_workers > 0 and not seen.has(building.def_id):
			seen[building.def_id] = true
			EventBus.building_state_changed.emit(building.def_id,
				_economy.workers_of(building.def_id), _economy.max_workers_of(building.def_id))

## Politik-Hebel (Rationen / Arbeitszeit) im Bereich 0..2 verschieben.
func _on_ration_change(delta: int) -> void:
	_economy.ration_level = clampi(_economy.ration_level + delta, 0, 2)
	_emit_policy()

func _on_work_change(delta: int) -> void:
	_economy.work_policy = clampi(_economy.work_policy + delta, 0, 2)
	_emit_policy()

func _on_tax_change(delta: int) -> void:
	_economy.tax_level = clampi(_economy.tax_level + delta, 0, 2)
	_emit_policy()

func _emit_policy() -> void:
	EventBus.policy_changed.emit(
		_economy.ration_level, _economy.work_policy, _economy.tax_level, _economy.productivity())

## Handel am Marktplatz (M13): Preis aus resources.json, Kaufen = 2x Preis.
func _on_trade(resource_id: StringName, amount: int) -> void:
	if _economy.get_building(&"market") == null:
		EventBus.build_failed.emit("Dafür braucht es einen Marktplatz.")
		return
	var price := int(Database.get_resource_def(resource_id).get("price", 0))
	var result := _economy.trade(resource_id, amount, price)
	if not result["ok"]:
		EventBus.build_failed.emit(result["reason"])
		return
	EventBus.stock_changed.emit(resource_id, _economy.get_stock(resource_id))
	EventBus.stock_changed.emit(&"gold", _economy.get_stock(&"gold"))

## Bewegungsbefehl an eine Einheit (M13): Ziel muss begehbar und frei sein.
func _on_unit_move(unit_id: int, cell: Vector2i) -> void:
	if not _world.is_walkable(cell) or _combat.obstacles.has(cell):
		EventBus.combat_event.emit("Dorthin führt kein Weg.")
		return
	if _combat.command_move(unit_id, cell):
		EventBus.combat_state_changed.emit(_combat.snapshot())

## Meldet der UI, ob ein Marktplatz steht (Handels-Sektion ein-/ausblenden).
func _emit_market_state() -> void:
	EventBus.market_available.emit(_economy.get_building(&"market") != null)

## Spielstand speichern (Wirtschaft + Forschung + Welt + Kampf -> SaveManager).
func _on_save() -> void:
	GameState.data = {
		"economy": _economy.to_dict(),
		"research": _research.to_dict(),
		"world": _world.to_dict(),
		"combat": _combat.to_dict(),
		"dialogues": _dialogue.to_dict(),
		"scenario": _scenario.to_dict(),
		"scenario_id": String(_scenario._def.get("id", DEFAULT_SCENARIO)),
		"campaign_chapter": _campaign_chapter,
	}
	if SaveManager.save_game(GameState.to_dict()) == OK:
		EventBus.game_saved.emit()

## Spielstand laden und Wirtschaft/Forschung/Welt/Kampf wiederherstellen.
func _on_load() -> void:
	GameState.from_dict(SaveManager.load_game())
	# Szenario-Definition zuerst (M12: Spielstand merkt sich das Szenario).
	var scenario_id: String = GameState.data.get("scenario_id", DEFAULT_SCENARIO)
	_scenario = Scenario.from_def(Database.scenarios.get(scenario_id, {}))
	_campaign_chapter = String(GameState.data.get("campaign_chapter", ""))
	var economy_data: Dictionary = GameState.data.get("economy", {})
	if not economy_data.is_empty():
		_economy.from_dict(economy_data)
	_research.from_dict(GameState.data.get("research", {}))
	var world_data: Dictionary = GameState.data.get("world", {})
	if not world_data.is_empty():
		_world.from_dict(world_data, Database.biomes)
	var combat_data: Dictionary = GameState.data.get("combat", {})
	var enemy_cfg: Dictionary = Database.enemy.duplicate(true)
	enemy_cfg.merge(_scenario.enemy_override(), true)
	if combat_data.is_empty():
		_setup_combat()  # aeltere Spielstaende ohne Kampf: frisch aufbauen
	else:
		# Gitter zuerst auf die (regenerierte) Welt setzen, dann laedt
		# from_dict die Hindernisse hinein.
		_combat.setup_grid(_world.width, _world.height, _world.impassable_cells())
		_combat.from_dict(combat_data, Database.units, enemy_cfg)
	_dialogue.from_dict(GameState.data.get("dialogues", {}))
	_scenario.from_dict(GameState.data.get("scenario", {}))
	_sync_population()
	# Erst game_loaded (UI raeumt alte dynamische Zeilen weg), dann Vollzustand.
	# Ein laufender Dialog endet beim Laden (wird nicht mitgespeichert).
	EventBus.game_loaded.emit()
	EventBus.dialogue_ended.emit()
	_emit_full_state()

## Gebaeudeliste der Siedlung fuer die Welt-Darstellung (Typ + Zelle).
func _building_list() -> Array:
	var entries: Array = []
	for building in _economy.buildings:
		entries.append({"def_id": building.def_id, "cell": building.cell})
	return entries

## Sendet den kompletten aktuellen Zustand an die UI (Initialisierung/Reload).
func _emit_full_state() -> void:
	EventBus.world_changed.emit(_world)
	EventBus.buildings_changed.emit(_building_list())
	_emit_market_state()
	_emit_worker_rows()
	# Nur freigeschaltete Ressourcen melden — gesperrte bleiben unsichtbar.
	for resource_id in Database.resources:
		var typed := StringName(resource_id)
		if _research.is_resource_unlocked(typed):
			EventBus.stock_changed.emit(typed, _economy.get_stock(typed))
	EventBus.housing_changed.emit(
		_economy.assigned_workers() + _economy.reserved_population, _economy.housing_capacity())
	EventBus.satisfaction_changed.emit(_economy.satisfaction)
	EventBus.combat_state_changed.emit(_combat.snapshot())
	EventBus.scenario_state_changed.emit(_scenario_info())
	EventBus.quest_state_changed.emit(_scenario.quest_states())
	EventBus.campaign_state_changed.emit(_campaign.overview())
	EventBus.build_options_changed.emit(_build_options())
	EventBus.recruit_options_changed.emit(_recruit_options())
	_emit_policy()
	_emit_tech_states()

## Meldet den Status aller Technologien an die UI.
func _emit_tech_states() -> void:
	for tech_id in _research.tech_ids():
		EventBus.tech_state_changed.emit(tech_id, _research.status(tech_id))
