class_name Campaign
extends RefCounted
## Campaign — Kapitelfolge der Hauptstory (M14, goal §1 "Kampagne").
##
## Die Kampagne ist eine geordnete Liste von Kapiteln (/data/campaign.json);
## jedes Kapitel verweist auf ein Szenario und bringt Story-Text (Intro/Outro)
## mit. Kapitel schalten sich strikt nacheinander frei: Kapitel N ist
## spielbar, sobald Kapitel N-1 abgeschlossen ist. Der Fortschritt lebt
## getrennt vom Spielstand (eigene Datei), damit er Neustarts und
## Szenario-Wechsel ueberlebt. Rein und headless testbar.

var _def: Dictionary = {}
var _completed: Dictionary = {}  # chapter_id -> true

static func from_def(def: Dictionary) -> Campaign:
	var campaign := Campaign.new()
	campaign._def = def
	return campaign

func display_name() -> String:
	return _def.get("display_name", "Kampagne")

## Rohe Kapitel-Definitionen in Story-Reihenfolge.
func chapters() -> Array:
	return _def.get("chapters", [])

## Kapitel-Definition per ID (leeres Dictionary, falls unbekannt).
func chapter(chapter_id: String) -> Dictionary:
	for entry in chapters():
		if String(entry.get("id", "")) == chapter_id:
			return entry
	return {}

## Kapitel, das dieses Szenario spielt (leeres Dictionary, falls keines).
func chapter_for_scenario(scenario_id: String) -> Dictionary:
	for entry in chapters():
		if String(entry.get("scenario", "")) == scenario_id:
			return entry
	return {}

func is_completed(chapter_id: String) -> bool:
	return _completed.has(chapter_id)

## Das erste Kapitel ist immer offen, jedes weitere braucht den Abschluss
## seines Vorgaengers.
func is_unlocked(chapter_id: String) -> bool:
	var list := chapters()
	for i in list.size():
		if String(list[i].get("id", "")) == chapter_id:
			return i == 0 or is_completed(String(list[i - 1].get("id", "")))
	return false

func complete(chapter_id: String) -> void:
	if not chapter(chapter_id).is_empty():
		_completed[chapter_id] = true

## ID des naechsten Kapitels ("" nach dem letzten).
func next_chapter_id(chapter_id: String) -> String:
	var list := chapters()
	for i in list.size():
		if String(list[i].get("id", "")) == chapter_id and i + 1 < list.size():
			return String(list[i + 1].get("id", ""))
	return ""

## Kapitel-Uebersicht fuer die UI: [{id, title, unlocked, completed}].
func overview() -> Array:
	var rows: Array = []
	for entry in chapters():
		var id := String(entry.get("id", ""))
		rows.append({
			"id": id,
			"title": entry.get("title", id),
			"unlocked": is_unlocked(id),
			"completed": is_completed(id),
		})
	return rows

## Serialisiert nur den Fortschritt — die Definition kommt aus /data.
func to_dict() -> Dictionary:
	return {"completed": _completed.keys()}

func from_dict(d: Dictionary) -> void:
	_completed.clear()
	for id in d.get("completed", []):
		_completed[String(id)] = true
