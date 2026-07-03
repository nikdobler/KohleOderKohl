extends Node
## EventBus — zentraler Signal-Knoten (entkoppelt Systeme, keine Gott-Klasse).
##
## Controller sendet Zustandsaenderungen, UI hoert zu — und umgekehrt, ohne
## dass sich beide Seiten direkt kennen.

## Controller -> Welt-Darstellung: neue/geladene Karte (WorldMap-Objekt).
signal world_changed(map: WorldMap)

## Welt-Darstellung -> Kamera: Pixelgrenzen der Karte.
signal camera_bounds_changed(bounds: Rect2)

## Controller -> Welt-Darstellung: Gebaeudeliste der Siedlung
## (Array aus {"def_id": StringName, "cell": Vector2i}).
signal buildings_changed(building_list: Array)

## Controller -> UI: baubare (freigeschaltete) Gebaeude fuer das Baumenue.
signal build_options_changed(def_ids: Array)

## UI -> Welt-Darstellung: Bau-Modus fuer ein Gebaeude starten.
signal build_mode_selected(def_id: StringName)

## Welt-Darstellung -> Controller: Vorschau/Platzierung an einer Zelle.
signal build_preview_requested(def_id: StringName, cell: Vector2i)
signal build_requested(def_id: StringName, cell: Vector2i)

## Controller -> Welt-Darstellung: Ist die Vorschau-Zelle bebaubar?
signal build_preview_result(cell: Vector2i, ok: bool)

## Controller -> UI: Bauversuch abgelehnt (Grund fuer Statuszeile).
signal build_failed(reason: String)

## UI -> Welt-Darstellung: Abriss-Modus starten (M11).
signal demolish_mode_selected()

## Welt-Darstellung -> Controller: Abriss-Vorschau/-Auftrag an einer Zelle.
## (Die Antwort kommt ueber build_preview_result.)
signal demolish_preview_requested(cell: Vector2i)
signal demolish_requested(cell: Vector2i)

## UI -> Controller: Politik-Hebel aendern (-1/+1).
signal ration_change_requested(delta: int)
signal work_change_requested(delta: int)
signal tax_change_requested(delta: int)

## Controller -> UI: Politik & resultierende Arbeitsleistung.
signal policy_changed(ration_level: int, work_policy: int, tax_level: int, productivity: float)

## UI -> Controller: Handel am Marktplatz (amount > 0 kaufen, < 0 verkaufen).
signal trade_requested(resource_id: StringName, amount: int)

## Controller -> UI: Marktplatz vorhanden? (blendet die Handels-Sektion ein).
signal market_available(available: bool)

## Welt-Darstellung -> Controller: Bewegungsbefehl fuer eine Einheit (M13).
signal unit_move_requested(unit_id: int, cell: Vector2i)

## Controller -> UI: Bestand einer Ressource hat sich geaendert.
signal stock_changed(resource_id: StringName, amount: int)

## Controller -> UI: Arbeiterzahl eines Gebaeudes hat sich geaendert.
signal building_state_changed(def_id: StringName, workers: int, max_workers: int)

## Controller -> UI: Wohnraumbelegung hat sich geaendert.
signal housing_changed(assigned: int, capacity: int)

## Controller -> UI: Arbeiterzufriedenheit (0..100) hat sich geaendert.
signal satisfaction_changed(value: int)

## Controller -> UI: Status einer Technologie (locked/available/researched).
signal tech_state_changed(tech_id: StringName, status: StringName)

## UI -> Controller: Arbeiter eines Gebaeudes um delta aendern (+1/-1).
signal worker_change_requested(def_id: StringName, delta: int)

## UI -> Controller: Technologie erforschen.
signal research_requested(tech_id: StringName)

## Controller -> UI: Forschungsversuch abgelehnt (Grund fuer Statuszeile).
signal research_failed(reason: String)

## Controller -> UI/Welt: Kampfzustand (Einheiten, Bergfriede, Status, Haltung).
signal combat_state_changed(snapshot: Dictionary)

## Controller -> UI: Kampfereignis als Meldung (Welle, Sieg, Niederlage ...).
signal combat_event(message: String)

## Controller -> Welt-Darstellung: Turmschuesse dieses Ticks
## (Array aus {"from": Vector2i, "to": Vector2i}) fuer die Pfeil-Animation.
signal tower_shots(shots: Array)

## UI -> Controller: eine Einheit des Typs rekrutieren (M12: mehrere Typen).
signal recruit_requested(unit_type: StringName)

## Controller -> UI: rekrutierbare (freigeschaltete) Einheitentypen.
signal recruit_options_changed(unit_ids: Array)

## Controller -> UI: Fortschritt des laufenden Forschungsprojekts (0..1).
signal research_progress(tech_id: StringName, ratio: float)

## UI -> Controller: neues Spiel mit diesem Szenario starten (M12).
signal scenario_selected(scenario_id: String)

## UI -> Controller: Szenario-Menue offen? (pausiert den Tick).
signal scenario_menu_visible(visible: bool)

## UI -> Controller: Haltung umschalten (Wache <-> Angriff).
signal stance_toggle_requested()

## Controller -> UI: Dialog beginnt bzw. zeigt einen neuen Knoten.
signal dialogue_started(npc: Dictionary, node: Dictionary)
signal dialogue_node_changed(npc: Dictionary, node: Dictionary)

## Controller -> UI: Dialog ist beendet (Panel schliessen).
signal dialogue_ended()

## UI -> Controller: weiterschalten (-1) bzw. Antwortoption waehlen (Index).
signal dialogue_advance_requested(choice_index: int)

## Controller -> UI: Szenario-Ereignis als Meldung (z. B. "Ernteausfall!").
signal scenario_event(message: String)

## Controller -> UI: Szenario-Info ({display_name, goal, completed}).
signal scenario_state_changed(info: Dictionary)

## UI -> Controller: Spielstand speichern bzw. laden.
signal save_requested()
signal load_requested()

## Controller -> UI: Rueckmeldung nach Speichern/Laden.
signal game_saved()
signal game_loaded()
