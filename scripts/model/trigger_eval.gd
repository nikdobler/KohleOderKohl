class_name TriggerEval
extends RefCounted
## TriggerEval — zentrale Auswertung datengetriebener Bedingungen (M6/M7).
##
## Dialog-Trigger, Szenario-Events und Szenario-Ziele teilen dasselbe
## Bedingungs-Schema und diese eine Auswertung. Der Zustands-Schnappschuss
## kommt vom Controller (String-Schluessel, JSON-kompatibel): {"tick": int,
## "stock": {String: int}, "satisfaction": int, "researched": [String],
## "combat_status": String}. Neue Bedingungstypen = neuer match-Zweig.

static func met(trigger: Dictionary, state: Dictionary) -> bool:
	match String(trigger.get("type", "")):
		"always":
			return true
		"tick_reached":
			return int(state.get("tick", 0)) >= int(trigger.get("tick", 0))
		"stock_below":
			return _stock(state, trigger) < int(trigger.get("amount", 0))
		"stock_above":
			return _stock(state, trigger) > int(trigger.get("amount", 0))
		"stock_at_least":
			return _stock(state, trigger) >= int(trigger.get("amount", 0))
		"satisfaction_below":
			return int(state.get("satisfaction", 100)) < int(trigger.get("amount", 0))
		"satisfaction_at_least":
			return int(state.get("satisfaction", 0)) >= int(trigger.get("amount", 0))
		"tech_researched":
			return state.get("researched", []).has(trigger.get("tech", ""))
		"combat_status":
			return String(state.get("combat_status", "")) == String(trigger.get("status", ""))
		_:
			push_warning("TriggerEval: unbekannter Bedingungstyp '%s'" % trigger.get("type", ""))
			return false

static func _stock(state: Dictionary, trigger: Dictionary) -> int:
	return int(state.get("stock", {}).get(trigger.get("resource", ""), 0))
