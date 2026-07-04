extends Control
## HUD — Spieloberflaeche (M2–M12): Lager, Arbeiter, Bauen, Forschung,
## Militaer, Politik, Dialoge und Szenario-Menue. Zeilen entstehen dynamisch
## aus den EventBus-Signalen — das HUD kennt weder Controller noch Modelle.

const _RATION_NAMES: Array = ["halb", "normal", "doppelt"]
const _WORK_NAMES: Array = ["kurz", "normal", "lang"]
const _TAX_NAMES: Array = ["keine", "moderat", "hoch"]
## Handels-Losgroesse am Marktplatz (M13).
const _TRADE_LOT: int = 5
## Maximale Eintraege der Chronik (aelteste fliegen raus, M15).
const _LOG_MAX: int = 80
## Zeit-Regler-Stufen (M-Tageszeit): Slider-Index -> Geschwindigkeitsfaktor.
const _SPEED_STEPS: Array = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const _SPEED_LABELS: Array = ["0.25", "0.5", "1", "2", "4", "8"]
## Chronik-Farben je Kategorie.
const _LOG_COLORS: Dictionary = {
	"Kampf": Color(1.0, 0.75, 0.7),
	"Ereignis": Color(1.0, 0.9, 0.6),
	"Hinweis": Color(0.75, 0.75, 0.75),
	"System": Color(0.7, 0.85, 1.0),
}

@onready var _left_vbox: VBoxContainer = $LeftPanel/Scroll/VBox
@onready var _scenario_label: Label = $BottomBar/HBox/InfoBox/ScenarioLabel
@onready var _resources_box: HBoxContainer = $TopBar/HBox/ResourcesBox
@onready var _buildings_box: VBoxContainer = $LeftPanel/Scroll/VBox/WorkersSection/Content/BuildingsBox
@onready var _build_box: VBoxContainer = $LeftPanel/Scroll/VBox/BuildSection/Content/BuildBox
@onready var _research_box: VBoxContainer = $LeftPanel/Scroll/VBox/ResearchSection/Content/ResearchBox
@onready var _keep_label: Label = $LeftPanel/Scroll/VBox/MilitarySection/Content/KeepLabel
@onready var _army_label: Label = $LeftPanel/Scroll/VBox/MilitarySection/Content/ArmyLabel
@onready var _recruit_box: VBoxContainer = $LeftPanel/Scroll/VBox/MilitarySection/Content/RecruitBox
@onready var _stance_button: Button = $LeftPanel/Scroll/VBox/MilitarySection/Content/MilitaryButtons/StanceButton
@onready var _policy_content: VBoxContainer = $LeftPanel/Scroll/VBox/PolicySection/Content
@onready var _ration_label: Label = $LeftPanel/Scroll/VBox/PolicySection/Content/RationRow/RationLabel
@onready var _work_label: Label = $LeftPanel/Scroll/VBox/PolicySection/Content/WorkRow/WorkLabel
@onready var _tax_label: Label = $LeftPanel/Scroll/VBox/PolicySection/Content/TaxRow/TaxLabel
@onready var _productivity_label: Label = $LeftPanel/Scroll/VBox/PolicySection/Content/ProductivityLabel
@onready var _market_section: VBoxContainer = $LeftPanel/Scroll/VBox/MarketSection
@onready var _market_box: VBoxContainer = $LeftPanel/Scroll/VBox/MarketSection/Content/MarketBox
@onready var _game_over_panel: PanelContainer = $GameOverPanel
@onready var _result_title: Label = $GameOverPanel/VBox/ResultTitle
@onready var _result_text: Label = $GameOverPanel/VBox/ResultText
@onready var _housing_label: Label = $TopBar/HBox/HousingLabel
@onready var _satisfaction_label: Label = $TopBar/HBox/SatisfactionLabel
@onready var _save_button: Button = $BottomBar/HBox/Buttons/SaveButton
@onready var _load_button: Button = $BottomBar/HBox/Buttons/LoadButton
@onready var _menu_button: Button = $BottomBar/HBox/Buttons/MenuButton
@onready var _status_label: Label = $BottomBar/HBox/InfoBox/StatusLabel
@onready var _fps_label: Label = $TopBar/HBox/FpsLabel
@onready var _season_label: Label = $TopBar/HBox/SeasonLabel
@onready var _weather_label: Label = $TopBar/HBox/WeatherLabel
@onready var _day_label: Label = $TopBar/HBox/DayLabel
@onready var _speed_label: Label = $TopBar/HBox/SpeedLabel
@onready var _speed_slider: HSlider = $TopBar/HBox/SpeedSlider
@onready var _dialogue_panel: PanelContainer = $DialoguePanel
@onready var _dialogue_portrait: TextureRect = $DialoguePanel/HBox/Portrait
@onready var _dialogue_speaker: Label = $DialoguePanel/HBox/VBox/SpeakerLabel
@onready var _dialogue_text: Label = $DialoguePanel/HBox/VBox/TextLabel
@onready var _dialogue_choices: VBoxContainer = $DialoguePanel/HBox/VBox/ChoicesBox
@onready var _scenario_menu: PanelContainer = $ScenarioMenu
@onready var _campaign_list: VBoxContainer = $ScenarioMenu/VBox/MenuScroll/MenuVBox/CampaignList
@onready var _scenario_list: VBoxContainer = $ScenarioMenu/VBox/MenuScroll/MenuVBox/ScenarioList
@onready var _menu_close: Button = $ScenarioMenu/VBox/CloseButton
@onready var _quest_box: VBoxContainer = $BottomBar/HBox/QuestBox
@onready var _story_panel: PanelContainer = $StoryPanel
@onready var _story_title: Label = $StoryPanel/VBox/StoryTitle
@onready var _story_text: Label = $StoryPanel/VBox/StoryScroll/StoryText
@onready var _story_button: Button = $StoryPanel/VBox/StoryButton
@onready var _log_panel: PanelContainer = $LogPanel
@onready var _log_scroll: ScrollContainer = $LogPanel/VBox/LogScroll
@onready var _log_list: VBoxContainer = $LogPanel/VBox/LogScroll/LogList
@onready var _log_toggle: Button = $LogPanel/VBox/Header/LogToggle
@onready var _title_screen: PanelContainer = $TitleScreen
@onready var _play_button: Button = $TitleScreen/Center/VBox/PlayButton

var _resource_labels: Dictionary = {}  # StringName -> Label
var _worker_labels: Dictionary = {}    # StringName -> Label
var _tech_buttons: Dictionary = {}     # StringName -> Button
var _combat_over := false
var _story_opens_menu := false  # nach dem Story-Text zur Kapitelwahl? (M14)
var _game_started := false  # erst nach der ersten Szenariowahl wird das HUD eingeblendet

func _ready() -> void:
	_save_button.pressed.connect(func() -> void: EventBus.save_requested.emit())
	_load_button.pressed.connect(func() -> void: EventBus.load_requested.emit())
	_stance_button.pressed.connect(func() -> void: EventBus.stance_toggle_requested.emit())
	_menu_button.pressed.connect(func() -> void: _set_menu_visible(true))
	_menu_close.pressed.connect(func() -> void: _set_menu_visible(false))
	_build_scenario_menu()
	_setup_sections()
	_connect_policy_buttons()
	EventBus.combat_state_changed.connect(_on_combat_state_changed)
	EventBus.combat_event.connect(_flash)
	EventBus.scenario_event.connect(_flash)
	EventBus.scenario_state_changed.connect(_on_scenario_state_changed)
	EventBus.build_options_changed.connect(_on_build_options_changed)
	EventBus.recruit_options_changed.connect(_on_recruit_options_changed)
	EventBus.build_failed.connect(_flash)
	EventBus.policy_changed.connect(_on_policy_changed)
	EventBus.market_available.connect(_on_market_available)
	EventBus.campaign_state_changed.connect(_on_campaign_state_changed)
	EventBus.quest_state_changed.connect(_on_quest_state_changed)
	EventBus.story_shown.connect(_show_story)
	_story_button.pressed.connect(_on_story_closed)
	_connect_log()
	$GameOverPanel/VBox/ResultButtons/ContinueButton.pressed.connect(
		func() -> void: _game_over_panel.visible = false)
	$GameOverPanel/VBox/ResultButtons/ToMenuButton.pressed.connect(func() -> void:
		_game_over_panel.visible = false
		_set_menu_visible(true))
	EventBus.stock_changed.connect(_on_stock_changed)
	EventBus.building_state_changed.connect(_on_building_state_changed)
	EventBus.tech_state_changed.connect(_on_tech_state_changed)
	EventBus.research_progress.connect(_on_research_progress)
	EventBus.housing_changed.connect(_on_housing_changed)
	EventBus.satisfaction_changed.connect(_on_satisfaction_changed)
	EventBus.season_changed.connect(
		func(_season: StringName, display: String) -> void: _season_label.text = display)
	EventBus.weather_changed.connect(
		func(_weather: StringName, display: String) -> void: _weather_label.text = display)
	EventBus.daytime_changed.connect(
		func(_tod: float, _phase: StringName, display: String) -> void: _day_label.text = display)
	EventBus.game_speed_changed.connect(_on_game_speed_changed)
	_speed_slider.value_changed.connect(_on_speed_slider_changed)
	EventBus.research_failed.connect(_flash)
	EventBus.game_saved.connect(func() -> void: _flash("Gespeichert."))
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.dialogue_started.connect(_show_dialogue)
	EventBus.dialogue_node_changed.connect(_show_dialogue)
	EventBus.dialogue_ended.connect(func() -> void: _dialogue_panel.visible = false)
	# Spielstart (M17): Titelbildschirm zuerst — die Szenariowahl liegt hinter
	# dem Spielen-Knopf, das HUD wird erst nach der Wahl eingeblendet.
	_set_bars_visible(false)
	_play_button.pressed.connect(func() -> void:
		_title_screen.visible = false
		_set_menu_visible(true))
	EventBus.scenario_menu_visible.emit.call_deferred(true)  # Tick pausiert bis zur Wahl

## Szenario-Menue (M12): eine Zeile je Szenario aus der Datenbank.
## Kampagnen-Kapitel (campaign_only) gehoeren in die Kampagnen-Sektion.
func _build_scenario_menu() -> void:
	for scenario_id in Database.scenarios:
		var def: Dictionary = Database.scenarios[scenario_id]
		if def.get("campaign_only", false):
			continue
		var button := Button.new()
		button.text = "%s — %s" % [def.get("display_name", scenario_id), def.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var id: String = scenario_id
		button.pressed.connect(func() -> void:
			EventBus.scenario_selected.emit(id)
			_set_menu_visible(false))
		_scenario_list.add_child(button)

func _set_menu_visible(menu_visible: bool) -> void:
	_scenario_menu.visible = menu_visible
	# "Weiterspielen" ergibt erst Sinn, wenn ein Spiel laeuft (M17).
	_menu_close.visible = _game_started
	EventBus.scenario_menu_visible.emit(menu_visible)

## HUD-Leisten (oben/links/unten/Chronik) zeigen bzw. verbergen; beim ersten
## Einblenden nach der Szenariowahl weich einblenden (M17).
func _set_bars_visible(bars_visible: bool) -> void:
	for bar in [$TopBar, $LeftPanel, $BottomBar, _log_panel]:
		bar.visible = bars_visible
		if bars_visible:
			bar.modulate.a = 0.0
			bar.create_tween().tween_property(bar, "modulate:a", 1.0, 0.5)

## Kampagnen-Sektion im Menue (M14): ein Knopf je Kapitel; gesperrte Kapitel
## bleiben deaktiviert, abgeschlossene bekommen ein Haekchen.
func _on_campaign_state_changed(chapters: Array) -> void:
	for child in _campaign_list.get_children():
		_campaign_list.remove_child(child)
		child.queue_free()
	for entry in chapters:
		var button := Button.new()
		var title: String = entry.get("title", "")
		if entry.get("completed", false):
			title += " ✓"
		elif not entry.get("unlocked", false):
			title += " (gesperrt)"
		button.text = title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not entry.get("unlocked", false)
		var id: String = entry.get("id", "")
		# Erst Menue schliessen, dann starten: der Controller zeigt sofort das
		# Intro (story_shown pausiert wieder) — umgekehrt wuerde das Schliessen
		# die Story-Pause gleich wieder aufheben.
		button.pressed.connect(func() -> void:
			_set_menu_visible(false)
			EventBus.campaign_chapter_selected.emit(id))
		_campaign_list.add_child(button)

## Quest-Log (M14): eine Zeile je Auftrag des laufenden Szenarios.
func _on_quest_state_changed(quests: Array) -> void:
	for child in _quest_box.get_children():
		_quest_box.remove_child(child)
		child.queue_free()
	for quest in quests:
		var label := Label.new()
		label.text = "%s %s" % ["☑" if quest.get("done", false) else "☐", quest.get("description", "")]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_quest_box.add_child(label)

## Story-Panel (M14): Kapitel-Intro/-Outro; pausiert das Spiel beim Lesen.
func _show_story(title: String, text: String, open_menu_after: bool) -> void:
	_story_opens_menu = open_menu_after
	_story_title.text = title
	_story_text.text = text
	_story_panel.visible = true
	EventBus.scenario_menu_visible.emit(true)  # Tick anhalten

func _on_story_closed() -> void:
	_story_panel.visible = false
	if _story_opens_menu:
		_set_menu_visible(true)  # Kapitelwahl: das naechste Kapitel ist offen
	else:
		EventBus.scenario_menu_visible.emit(false)

## Aufklapp-Sektionen des linken Panels (M17): der Kopf-Knopf zeigt/verbirgt
## den Inhalt; standardmaessig ist alles eingeklappt (nur Kopfzeile sichtbar).
func _setup_sections() -> void:
	for section in _left_vbox.get_children():
		var header: Button = section.get_node("Header")
		var content: Control = section.get_node("Content")
		header.set_meta("title", header.text)
		header.pressed.connect(func() -> void:
			content.visible = not content.visible
			_refresh_section_header(header, content))
		_refresh_section_header(header, content)

func _refresh_section_header(header: Button, content: Control) -> void:
	header.text = "%s %s" % ["▾" if content.visible else "▸", header.get_meta("title")]

func _connect_policy_buttons() -> void:
	_policy_content.get_node("RationRow/RationMinus").pressed.connect(
		func() -> void: EventBus.ration_change_requested.emit(-1))
	_policy_content.get_node("RationRow/RationPlus").pressed.connect(
		func() -> void: EventBus.ration_change_requested.emit(1))
	_policy_content.get_node("WorkRow/WorkMinus").pressed.connect(
		func() -> void: EventBus.work_change_requested.emit(-1))
	_policy_content.get_node("WorkRow/WorkPlus").pressed.connect(
		func() -> void: EventBus.work_change_requested.emit(1))
	_policy_content.get_node("TaxRow/TaxMinus").pressed.connect(
		func() -> void: EventBus.tax_change_requested.emit(-1))
	_policy_content.get_node("TaxRow/TaxPlus").pressed.connect(
		func() -> void: EventBus.tax_change_requested.emit(1))

## FPS-Anzeige fuer den Performance-Nachweis (F3 spawnt 200 Test-Einheiten).
func _process(_delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

## Nach Laden/Neustart: alte dynamische Zeilen entfernen — der Controller
## sendet direkt danach den vollstaendigen neuen Zustand.
func _on_game_loaded() -> void:
	if not _game_started:
		_game_started = true
		_title_screen.visible = false
		_set_bars_visible(true)  # das HUD erscheint erst mit dem ersten Spiel
	for dict in [_resource_labels, _worker_labels, _tech_buttons]:
		dict.clear()
	_game_over_panel.visible = false
	_story_panel.visible = false
	for box in [_resources_box, _buildings_box, _research_box, _build_box, _recruit_box, _market_box, _quest_box, _log_list]:
		for child in box.get_children():
			# Nie free() auf moeglicherweise emittierende Buttons.
			box.remove_child(child)
			child.queue_free()
	_flash("Geladen.")

func _on_stock_changed(resource_id: StringName, amount: int) -> void:
	_ensure_resource_label(resource_id).text = "%s: %d" % [_resource_name(resource_id), amount]

func _on_building_state_changed(def_id: StringName, workers: int, max_workers: int) -> void:
	if max_workers <= 0:  # letztes Gebaeude dieses Typs abgerissen -> Zeile weg
		if _worker_labels.has(def_id):
			var row: Node = _worker_labels[def_id].get_parent()
			_buildings_box.remove_child(row)
			row.queue_free()
			_worker_labels.erase(def_id)
		return
	_ensure_worker_row(def_id).text = "%d / %d" % [workers, max_workers]

func _on_tech_state_changed(tech_id: StringName, status: StringName) -> void:
	var button := _ensure_tech_row(tech_id)
	match status:
		Research.STATUS_RESEARCHED:
			button.disabled = true
			button.text = "Erforscht"
		Research.STATUS_RESEARCHING:
			button.disabled = true
			button.text = "0 %"
		Research.STATUS_AVAILABLE:
			button.disabled = false
			button.text = "Erforschen"
		Research.STATUS_LOCKED:
			button.disabled = true
			button.text = "Gesperrt"

## Fortschritt der laufenden Forschung (M12) auf dem Knopf anzeigen.
func _on_research_progress(tech_id: StringName, ratio: float) -> void:
	if _tech_buttons.has(tech_id):
		_tech_buttons[tech_id].text = "%d %%" % roundi(ratio * 100.0)

## Baumenue neu aufbauen (bei Start und nach Freischaltungen);
## am Ende immer der Abriss-Knopf (M11).
func _on_build_options_changed(def_ids: Array) -> void:
	for child in _build_box.get_children():
		_build_box.remove_child(child)
		child.queue_free()
	for def_id in def_ids:
		var button := Button.new()
		button.text = _build_label(def_id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func() -> void:
			EventBus.build_mode_selected.emit(def_id)
			_flash("Bau-Modus: Linksklick platziert, Rechtsklick beendet."))
		_build_box.add_child(button)
	var demolish := Button.new()
	demolish.text = "Abreissen (50 % Material zurück)"
	demolish.alignment = HORIZONTAL_ALIGNMENT_LEFT
	demolish.pressed.connect(func() -> void:
		EventBus.demolish_mode_selected.emit()
		_flash("Abriss-Modus: Linksklick reisst ab, Rechtsklick beendet."))
	_build_box.add_child(demolish)

## Rekrutierungsmenue (M12): ein Knopf je freigeschaltetem Kriegertyp.
func _on_recruit_options_changed(unit_ids: Array) -> void:
	for child in _recruit_box.get_children():
		_recruit_box.remove_child(child)
		child.queue_free()
	for unit_id in unit_ids:
		var def := Database.get_unit_def(unit_id)
		var button := Button.new()
		button.text = "%s (%s)" % [def.get("display_name", String(unit_id)), _cost_text(def.get("cost", {}))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = _combat_over
		var id: StringName = unit_id
		button.pressed.connect(func() -> void: EventBus.recruit_requested.emit(id))
		_recruit_box.add_child(button)

func _on_policy_changed(ration_level: int, work_policy: int, tax_level: int, productivity: float) -> void:
	_ration_label.text = "Rationen: %s" % _RATION_NAMES[ration_level]
	_work_label.text = "Arbeitszeit: %s" % _WORK_NAMES[work_policy]
	_tax_label.text = "Steuern: %s" % _TAX_NAMES[tax_level]
	_productivity_label.text = "Arbeitsleistung: %d %%" % roundi(productivity * 100.0)

func _on_housing_changed(assigned: int, capacity: int) -> void:
	_housing_label.text = "Wohnraum: %d / %d" % [assigned, capacity]

## Szenario-Zeile: Name + Ziel, Haekchen bei Zielerreichung.
func _on_scenario_state_changed(info: Dictionary) -> void:
	var goal: String = info.get("goal", "")
	var text: String = info.get("display_name", "")
	if not goal.is_empty():
		text += " — Ziel: %s" % goal
	if info.get("completed", false):
		text += " ✓"
	_scenario_label.text = text

func _on_satisfaction_changed(value: int) -> void:
	_satisfaction_label.text = "Zufriedenheit: %d %%" % value

## Zeit-Regler bewegt (M-Tageszeit): Slider-Index -> Geschwindigkeitsfaktor an
## den Controller melden; dieser skaliert den Haupt-Tick fuer alles zugleich.
func _on_speed_slider_changed(value: float) -> void:
	var index := clampi(int(value), 0, _SPEED_STEPS.size() - 1)
	_speed_label.text = "Zeit: %sx" % _SPEED_LABELS[index]
	EventBus.game_speed_change_requested.emit(float(_SPEED_STEPS[index]))

## Controller meldet die aktuelle Geschwindigkeit (Init/Load): Regler auf die
## naechste Stufe stellen, ohne dabei erneut ein Aendern-Signal auszuloesen.
func _on_game_speed_changed(speed: float) -> void:
	var index := 0
	for i in _SPEED_STEPS.size():
		if absf(_SPEED_STEPS[i] - speed) < absf(_SPEED_STEPS[index] - speed):
			index = i
	_speed_slider.set_value_no_signal(float(index))
	_speed_label.text = "Zeit: %sx" % _SPEED_LABELS[index]

## Aktualisiert Bergfried-Anzeige, Soldatenzahl und Haltung-Knopf.
func _on_combat_state_changed(snapshot: Dictionary) -> void:
	var player_keep: Dictionary = snapshot["keeps"][&"player"]
	var enemy_keep: Dictionary = snapshot["keeps"][&"enemy"]
	_keep_label.text = "Bergfried: %d/%d · Feind: %d/%d" % [
		player_keep["hp"], player_keep["max_hp"], enemy_keep["hp"], enemy_keep["max_hp"]]
	var soldiers := 0
	for unit in snapshot["units"]:
		if unit["faction"] == &"player":
			soldiers += 1
	_army_label.text = "Soldaten: %d · Haltung: %s" % [
		soldiers, "Angriff" if snapshot["stance"] == &"assault" else "Wache"]
	_stance_button.text = "Zurückziehen" if snapshot["stance"] == &"assault" else "Angriff!"
	var over: bool = snapshot["status"] != &"active"
	if over != _combat_over:
		_combat_over = over
		for child in _recruit_box.get_children():
			child.disabled = over
		if over:
			_show_game_over(snapshot["status"])
	_stance_button.disabled = over

## Zeigt einen Dialog-Knoten: Portraet, Sprecher, Text und Antwortoptionen
## (bzw. einen "Weiter."-Knopf bei Knoten ohne Optionen).
func _show_dialogue(npc: Dictionary, node: Dictionary) -> void:
	_dialogue_panel.visible = true
	_dialogue_speaker.text = npc.get("display_name", "???")
	_dialogue_portrait.texture = AssetRegistry.get_texture(
		StringName(npc.get("icon", "npc_%s" % npc.get("id", ""))))
	_dialogue_text.text = node.get("text", "")
	# Kein sofortiges free(): der geklickte Button steckt noch in seiner
	# eigenen Signal-Emission (gesperrt) -> aus dem Baum nehmen, spaeter freigeben.
	for child in _dialogue_choices.get_children():
		_dialogue_choices.remove_child(child)
		child.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		_dialogue_choices.add_child(_make_choice_button("Weiter.", -1))
		return
	for i in choices.size():
		_dialogue_choices.add_child(_make_choice_button("> %s" % choices[i].get("text", ""), i))

func _make_choice_button(text: String, choice_index: int) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void: EventBus.dialogue_advance_requested.emit(choice_index))
	return button

## Legt bei Bedarf die Bestandszeile einer Ressource an.
func _ensure_resource_label(resource_id: StringName) -> Label:
	if _resource_labels.has(resource_id):
		return _resource_labels[resource_id]
	var label := Label.new()
	_resources_box.add_child(label)
	_resource_labels[resource_id] = label
	return label

## Legt bei Bedarf die Arbeiterzeile eines Gebaeudetyps an (Name, -, Zahl, +).
func _ensure_worker_row(def_id: StringName) -> Label:
	if _worker_labels.has(def_id):
		return _worker_labels[def_id]
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = _building_name(def_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_make_worker_button("-", def_id, -1))
	var count_label := Label.new()
	count_label.custom_minimum_size = Vector2(48, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_label)
	row.add_child(_make_worker_button("+", def_id, 1))
	_buildings_box.add_child(row)
	_worker_labels[def_id] = count_label
	return count_label

## Legt bei Bedarf die Forschungszeile einer Technologie an (Name+Kosten, Button).
func _ensure_tech_row(tech_id: StringName) -> Button:
	if _tech_buttons.has(tech_id):
		return _tech_buttons[tech_id]
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = _tech_label(tech_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	var button := Button.new()
	button.pressed.connect(func() -> void: EventBus.research_requested.emit(tech_id))
	row.add_child(button)
	_research_box.add_child(row)
	_tech_buttons[tech_id] = button
	return button

func _make_worker_button(text: String, def_id: StringName, delta: int) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: EventBus.worker_change_requested.emit(def_id, delta))
	return button

## Knopftext im Baumenue, z. B. "Mauer (2 Stein)".
func _build_label(def_id: StringName) -> String:
	var def := Database.get_building_def(def_id)
	var display_name: String = def.get("display_name", String(def_id))
	var cost_text := _cost_text(def.get("cost", {}))
	return display_name if cost_text.is_empty() else "%s (%s)" % [display_name, cost_text]

## Anzeigename + Kosten einer Technologie, z. B. "Braukunst (10 Holz, 8 Brot)".
func _tech_label(tech_id: StringName) -> String:
	var def := Database.get_tech_def(tech_id)
	var display_name: String = def.get("display_name", String(tech_id))
	var cost_text := _cost_text(def.get("cost", {}))
	return display_name if cost_text.is_empty() else "%s (%s)" % [display_name, cost_text]

## Kosten-Dictionary als Lesetext, z. B. "10 Holz, 8 Brot".
func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for res in cost:
		parts.append("%d %s" % [int(cost[res]), _resource_name(StringName(res))])
	return ", ".join(parts)

## Liest den Anzeigenamen einer Ressource aus der Datenbank.
func _resource_name(id: StringName) -> String:
	return Database.get_resource_def(id).get("display_name", String(id))

## Liest den Anzeigenamen eines Gebaeudes aus der Datenbank.
func _building_name(id: StringName) -> String:
	return Database.get_building_def(id).get("display_name", String(id))

func _flash(message: String) -> void:
	_status_label.text = message

## Chronik (M15): sammelt alle Meldungen dauerhaft — die Statuszeile bleibt
## der Schnell-Flash, hier geht nichts mehr verloren.
func _connect_log() -> void:
	EventBus.combat_event.connect(func(m: String) -> void: _log("Kampf", m))
	EventBus.scenario_event.connect(func(m: String) -> void: _log("Ereignis", m))
	EventBus.build_failed.connect(func(m: String) -> void: _log("Hinweis", m))
	EventBus.research_failed.connect(func(m: String) -> void: _log("Hinweis", m))
	EventBus.game_saved.connect(func() -> void: _log("System", "Spielstand gespeichert."))
	_log_toggle.pressed.connect(_toggle_log)

## Haengt einen Eintrag an, kappt bei _LOG_MAX und rollt ans Ende.
func _log(category: String, message: String) -> void:
	if message.is_empty():
		return
	var label := Label.new()
	label.text = "[%s] %s" % [category, message]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", _LOG_COLORS.get(category, Color.WHITE))
	_log_list.add_child(label)
	while _log_list.get_child_count() > _LOG_MAX:
		var oldest: Node = _log_list.get_child(0)
		_log_list.remove_child(oldest)
		oldest.queue_free()
	_scroll_log_to_end.call_deferred()

## Ans Ende rollen — erst nach dem Layout-Frame ist max_value aktuell.
func _scroll_log_to_end() -> void:
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)

## Chronik ein-/ausklappen (nur der Titelbalken bleibt sichtbar).
func _toggle_log() -> void:
	_log_scroll.visible = not _log_scroll.visible
	_log_toggle.text = "–" if _log_scroll.visible else "+"
	_log_panel.offset_bottom = 288.0 if _log_scroll.visible else 84.0

## Markt-Sektion (M13): eine Handelszeile je Ware mit Preis
## ("+5" kauft zum doppelten, "−5" verkauft zum einfachen Grundpreis).
func _on_market_available(available: bool) -> void:
	_market_section.visible = available
	for child in _market_box.get_children():
		_market_box.remove_child(child)
		child.queue_free()
	if not available:
		return
	for res_id in Database.resources:
		var price := int(Database.resources[res_id].get("price", 0))
		if price <= 0:
			continue
		_market_box.add_child(_make_trade_row(StringName(res_id), price))

func _make_trade_row(resource_id: StringName, price: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%d G)" % [_resource_name(resource_id), price]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var sell := Button.new()
	sell.text = "−%d" % _TRADE_LOT
	sell.pressed.connect(func() -> void: EventBus.trade_requested.emit(resource_id, -_TRADE_LOT))
	row.add_child(sell)
	var buy := Button.new()
	buy.text = "+%d" % _TRADE_LOT
	buy.pressed.connect(func() -> void: EventBus.trade_requested.emit(resource_id, _TRADE_LOT))
	row.add_child(buy)
	return row

## Sieg-/Niederlage-Abschluss (M13).
func _show_game_over(status: StringName) -> void:
	_game_over_panel.visible = true
	if status == &"victory":
		_result_title.text = "Sieg!"
		_result_text.text = "Der feindliche Bergfried ist gefallen. Die Chronisten schreiben bereits — und Ritter Kunz behauptet, er sei dabei gewesen."
	else:
		_result_title.text = "Niederlage"
		_result_text.text = "Der Bergfried ist gefallen. Der Schwarze Ratgeber lächelt. Versucht es erneut — die Szenarien warten."
