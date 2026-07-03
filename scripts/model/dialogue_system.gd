class_name DialogueSystem
extends RefCounted
## DialogueSystem — datengetriebenes Dialogsystem (M6, goal §4).
##
## Trigger-Logik strikt vom Text getrennt: Dialoge liegen in
## /data/dialogues/*.json; diese Klasse wertet nur Bedingungen gegen einen
## neutralen Zustands-Schnappschuss (Dictionary) aus und navigiert durch
## Dialog-Knoten (mit Antwortoptionen). Rein und headless testbar — kein
## Node, kein UI-Bezug. Es laeuft hoechstens ein Dialog gleichzeitig.
##
## Zustands-Schnappschuss (baut der Controller): {"tick": int,
## "stock": {String: int}, "satisfaction": int, "researched": [String],
## "combat_status": String}.

var _npcs: Dictionary = {}       # npc_id (String) -> rohe NPC-Definition
var _seen: Dictionary = {}       # "npc/dialog" -> true (einmalige abgeschlossen)
var _cooldowns: Dictionary = {}  # "npc/dialog" -> fruehester naechster Tick
var _active: Dictionary = {}     # {"npc_id", "dialogue", "node_id"} oder leer

## Baut das System aus den geladenen JSON-Definitionen (npc_id -> Datei-Inhalt).
static func from_defs(defs: Dictionary) -> DialogueSystem:
	var system := DialogueSystem.new()
	system._npcs = defs
	return system

func is_active() -> bool:
	return not _active.is_empty()

## Prueft alle Trigger gegen den Schnappschuss und startet den Dialog mit der
## hoechsten Prioritaet (Gleichstand: Definitionsreihenfolge).
## Rueckgabe: {} oder {"npc": {...}, "node": {...}}.
func check_triggers(state: Dictionary) -> Dictionary:
	if is_active():
		return {}
	var best_npc := ""
	var best: Dictionary = {}
	for npc_id in _npcs:
		for dialogue in _npcs[npc_id].get("dialogues", []):
			if not _eligible(npc_id, dialogue, state):
				continue
			if best.is_empty() or int(dialogue.get("priority", 0)) > int(best.get("priority", 0)):
				best = dialogue
				best_npc = npc_id
	if best.is_empty():
		return {}
	_begin(best_npc, best, state)
	return {"npc": _npcs[best_npc]["npc"], "node": _current_node()}

## Startet einen bestimmten Dialog skriptgesteuert (Kampagnen-Events, M14) —
## unabhaengig von dessen Trigger (auch Typ "scripted"); ein laufender Dialog
## wird ersetzt, denn Story-Momente haben Vorrang.
## Rueckgabe wie bei check_triggers, {} wenn der Dialog fehlt.
func force_start(npc_id: String, dialogue_id: String, state: Dictionary) -> Dictionary:
	for dialogue in _npcs.get(npc_id, {}).get("dialogues", []):
		if String(dialogue.get("id", "")) == dialogue_id:
			_begin(npc_id, dialogue, state)
			return {"npc": _npcs[npc_id]["npc"], "node": _current_node()}
	push_warning("DialogueSystem: Dialog '%s/%s' fehlt." % [npc_id, dialogue_id])
	return {}

## Schaltet weiter: [param choice_index] waehlt eine Antwortoption
## (-1 = einfaches "Weiter" bei Knoten ohne Optionen).
## Rueckgabe: naechster Knoten wie bei check_triggers, {} wenn beendet.
func advance(choice_index: int = -1) -> Dictionary:
	if not is_active():
		return {}
	var node := _current_node()
	var next_id := ""
	var choices: Array = node.get("choices", [])
	if not choices.is_empty():
		if choice_index < 0 or choice_index >= choices.size():
			return {"npc": _npcs[_active["npc_id"]]["npc"], "node": node}  # ungueltig -> bleibt
		next_id = String(choices[choice_index].get("next", ""))
	else:
		next_id = String(node.get("next", ""))
	var nodes: Dictionary = _active["dialogue"].get("nodes", {})
	if next_id == "" or not nodes.has(next_id):
		_active = {}
		return {}
	_active["node_id"] = next_id
	return {"npc": _npcs[_active["npc_id"]]["npc"], "node": nodes[next_id]}

## Serialisiert Gesehen-Status und Cooldowns (ein laufender Dialog wird
## bewusst nicht gespeichert — er endet beim Laden).
func to_dict() -> Dictionary:
	return {"seen": _seen.keys(), "cooldowns": _cooldowns.duplicate()}

func from_dict(d: Dictionary) -> void:
	_seen.clear()
	for key in d.get("seen", []):
		_seen[String(key)] = true
	_cooldowns.clear()
	for key in d.get("cooldowns", {}):
		_cooldowns[String(key)] = int(d["cooldowns"][key])
	_active = {}

## Darf dieser Dialog jetzt starten? (Trigger, einmalig, Cooldown, Sequenz)
func _eligible(npc_id: String, dialogue: Dictionary, state: Dictionary) -> bool:
	var key := "%s/%s" % [npc_id, dialogue.get("id", "")]
	if dialogue.get("once", false) and _seen.has(key):
		return false
	if int(state.get("tick", 0)) < int(_cooldowns.get(key, 0)):
		return false
	# Sequenzierung: setzt einen bereits gesehenen EINMALIGEN Dialog voraus
	# ("id" beim selben NPC oder "npc/id" fuer fremde NPCs).
	var required := String(dialogue.get("requires_seen", ""))
	if required != "":
		var required_key := required if required.contains("/") else "%s/%s" % [npc_id, required]
		if not _seen.has(required_key):
			return false
	# Bedingungs-Auswertung teilt sich das System mit Szenario-Events/-Zielen.
	return TriggerEval.met(dialogue.get("trigger", {}), state)

## Startet einen Dialog: einmalige merken, Cooldown setzen, aktiv schalten.
func _begin(npc_id: String, dialogue: Dictionary, state: Dictionary) -> void:
	var key := "%s/%s" % [npc_id, dialogue.get("id", "")]
	if dialogue.get("once", false):
		_seen[key] = true
	var cooldown := int(dialogue.get("cooldown_ticks", 0))
	if cooldown > 0:
		_cooldowns[key] = int(state.get("tick", 0)) + cooldown
	_active = {
		"npc_id": npc_id,
		"dialogue": dialogue,
		"node_id": String(dialogue.get("start", "start")),
	}

func _current_node() -> Dictionary:
	return _active["dialogue"].get("nodes", {}).get(_active["node_id"], {})
