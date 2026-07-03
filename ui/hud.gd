extends Control
## HUD — Spieloberflaeche (M2–M12): Lager, Arbeiter, Bauen, Forschung,
## Militaer, Politik, Dialoge und Szenario-Menue. Zeilen entstehen dynamisch
## aus den EventBus-Signalen — das HUD kennt weder Controller noch Modelle.

const _RATION_NAMES: Array = ["halb", "normal", "doppelt"]
const _WORK_NAMES: Array = ["kurz", "normal", "lang"]
const _TAX_NAMES: Array = ["keine", "moderat", "hoch"]
## Handels-Losgroesse am Marktplatz (M13).
const _TRADE_LOT: int = 5

@onready var _scenario_label: Label = $Panel/Scroll/VBox/ScenarioLabel
@onready var _resources_box: VBoxContainer = $Panel/Scroll/VBox/ResourcesBox
@onready var _buildings_box: VBoxContainer = $Panel/Scroll/VBox/BuildingsBox
@onready var _build_box: VBoxContainer = $Panel/Scroll/VBox/BuildBox
@onready var _research_box: VBoxContainer = $Panel/Scroll/VBox/ResearchBox
@onready var _keep_label: Label = $Panel/Scroll/VBox/KeepLabel
@onready var _army_label: Label = $Panel/Scroll/VBox/ArmyLabel
@onready var _recruit_box: VBoxContainer = $Panel/Scroll/VBox/RecruitBox
@onready var _stance_button: Button = $Panel/Scroll/VBox/MilitaryButtons/StanceButton
@onready var _ration_label: Label = $Panel/Scroll/VBox/RationRow/RationLabel
@onready var _work_label: Label = $Panel/Scroll/VBox/WorkRow/WorkLabel
@onready var _tax_label: Label = $Panel/Scroll/VBox/TaxRow/TaxLabel
@onready var _productivity_label: Label = $Panel/Scroll/VBox/ProductivityLabel
@onready var _market_title: Label = $Panel/Scroll/VBox/MarketTitle
@onready var _market_box: VBoxContainer = $Panel/Scroll/VBox/MarketBox
@onready var _game_over_panel: PanelContainer = $GameOverPanel
@onready var _result_title: Label = $GameOverPanel/VBox/ResultTitle
@onready var _result_text: Label = $GameOverPanel/VBox/ResultText
@onready var _housing_label: Label = $Panel/Scroll/VBox/HousingLabel
@onready var _satisfaction_label: Label = $Panel/Scroll/VBox/SatisfactionLabel
@onready var _save_button: Button = $Panel/Scroll/VBox/Buttons/SaveButton
@onready var _load_button: Button = $Panel/Scroll/VBox/Buttons/LoadButton
@onready var _menu_button: Button = $Panel/Scroll/VBox/Buttons/MenuButton
@onready var _status_label: Label = $Panel/Scroll/VBox/StatusLabel
@onready var _fps_label: Label = $FpsLabel
@onready var _dialogue_panel: PanelContainer = $DialoguePanel
@onready var _dialogue_portrait: TextureRect = $DialoguePanel/HBox/Portrait
@onready var _dialogue_speaker: Label = $DialoguePanel/HBox/VBox/SpeakerLabel
@onready var _dialogue_text: Label = $DialoguePanel/HBox/VBox/TextLabel
@onready var _dialogue_choices: VBoxContainer = $DialoguePanel/HBox/VBox/ChoicesBox
@onready var _scenario_menu: PanelContainer = $ScenarioMenu
@onready var _scenario_list: VBoxContainer = $ScenarioMenu/VBox/MenuScroll/ScenarioList
@onready var _menu_close: Button = $ScenarioMenu/VBox/CloseButton

var _resource_labels: Dictionary = {}  # StringName -> Label
var _worker_labels: Dictionary = {}    # StringName -> Label
var _tech_buttons: Dictionary = {}     # StringName -> Button
var _combat_over := false

func _ready() -> void:
	_save_button.pressed.connect(func() -> void: EventBus.save_requested.emit())
	_load_button.pressed.connect(func() -> void: EventBus.load_requested.emit())
	_stance_button.pressed.connect(func() -> void: EventBus.stance_toggle_requested.emit())
	_menu_button.pressed.connect(func() -> void: _set_menu_visible(true))
	_menu_close.pressed.connect(func() -> void: _set_menu_visible(false))
	_build_scenario_menu()
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
	EventBus.research_failed.connect(_flash)
	EventBus.game_saved.connect(func() -> void: _flash("Gespeichert."))
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.dialogue_started.connect(_show_dialogue)
	EventBus.dialogue_node_changed.connect(_show_dialogue)
	EventBus.dialogue_ended.connect(func() -> void: _dialogue_panel.visible = false)
	_set_menu_visible.call_deferred(true)  # Spielstart: Szenario waehlen

## Szenario-Menue (M12): eine Zeile je Szenario aus der Datenbank.
func _build_scenario_menu() -> void:
	for scenario_id in Database.scenarios:
		var def: Dictionary = Database.scenarios[scenario_id]
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
	EventBus.scenario_menu_visible.emit(menu_visible)

func _connect_policy_buttons() -> void:
	$Panel/Scroll/VBox/RationRow/RationMinus.pressed.connect(
		func() -> void: EventBus.ration_change_requested.emit(-1))
	$Panel/Scroll/VBox/RationRow/RationPlus.pressed.connect(
		func() -> void: EventBus.ration_change_requested.emit(1))
	$Panel/Scroll/VBox/WorkRow/WorkMinus.pressed.connect(
		func() -> void: EventBus.work_change_requested.emit(-1))
	$Panel/Scroll/VBox/WorkRow/WorkPlus.pressed.connect(
		func() -> void: EventBus.work_change_requested.emit(1))
	$Panel/Scroll/VBox/TaxRow/TaxMinus.pressed.connect(
		func() -> void: EventBus.tax_change_requested.emit(-1))
	$Panel/Scroll/VBox/TaxRow/TaxPlus.pressed.connect(
		func() -> void: EventBus.tax_change_requested.emit(1))

## FPS-Anzeige fuer den Performance-Nachweis (F3 spawnt 200 Test-Einheiten).
func _process(_delta: float) -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

## Nach Laden/Neustart: alte dynamische Zeilen entfernen — der Controller
## sendet direkt danach den vollstaendigen neuen Zustand.
func _on_game_loaded() -> void:
	for dict in [_resource_labels, _worker_labels, _tech_buttons]:
		dict.clear()
	_game_over_panel.visible = false
	for box in [_resources_box, _buildings_box, _research_box, _build_box, _recruit_box, _market_box]:
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

## Markt-Sektion (M13): eine Handelszeile je Ware mit Preis
## ("+5" kauft zum doppelten, "−5" verkauft zum einfachen Grundpreis).
func _on_market_available(available: bool) -> void:
	_market_title.visible = available
	_market_box.visible = available
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
