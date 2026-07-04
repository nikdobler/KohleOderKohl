class_name Economy
extends RefCounted
## Economy — Kern der Wirtschaftssimulation (M1/M2).
##
## Haelt Ressourcenbestand, Gebaeude, Wohnraum und Arbeiterzufriedenheit und
## rechnet pro [method tick] Produktion (inkl. Verbrauchsketten wie
## Weizen -> Brot) und Versorgung aus. Bewusst frei von Godot-Nodes und UI:
## so laesst sich der Spiel-Loop headless mit Unit-Tests absichern
## (siehe tests/test_economy.gd). Bestandsschluessel sind StringNames.

## Alle wie viele Ticks die Arbeiter essen muessen.
const FOOD_INTERVAL: int = 10
## Nahrungsressource der Arbeiter (M2: Brot).
const FOOD_RESOURCE: StringName = &"bread"
const SATISFACTION_START: int = 50
const SATISFACTION_FED_GAIN: int = 5
const SATISFACTION_HUNGER_LOSS: int = 10

## Politik (M8, Stronghold-artig): Index 0/1/2 je Hebel.
## Rationen: halb/normal/doppelt — Brotverbrauch & Laune.
const RATION_MULTIPLIERS: Array = [0.5, 1.0, 2.0]
const RATION_MOOD: Array = [-8, 0, 5]
## Arbeitszeit: kurz/normal/lang — Arbeitsleistung & Laune.
const WORK_MULTIPLIERS: Array = [0.8, 1.0, 1.2]
const WORK_MOOD: Array = [5, 0, -8]
## Steuern (M13): keine/moderat/hoch — Gold je Bewohner & Laune.
const TAX_GOLD: Array = [0, 1, 2]
const TAX_MOOD: Array = [0, -2, -8]
## Laune-Malus je Versorgung, wenn Feinde nahe der Siedlung waren.
const THREAT_MOOD_LOSS: int = 8

var stock: Dictionary = {}  # StringName -> int
var buildings: Array[BuildingInstance] = []
## Zufriedenheit der Arbeiter, einfacher Wert 0..100 (M2).
var satisfaction: int = SATISFACTION_START
var tick_count: int = 0
## Aktuelle Wetterlage (M-Wetter): setzt der Controller vor jedem Tick;
## deterministisch aus Seed+Tick, wird deshalb nicht gespeichert.
var current_weather: StringName = &"clear"
## Bewohner, die als Soldaten dienen (M5): belegen Wohnraum und essen mit,
## stehen der Arbeiterzuteilung aber nicht zur Verfuegung.
var reserved_population: int = 0
## Politik-Hebel (Index in RATION_*/WORK_*-Tabellen, 1 = normal).
var ration_level: int = 1
var work_policy: int = 1
## Steuersatz (Index in TAX_*-Tabellen, 0 = keine Steuern).
var tax_level: int = 0
## Luxusgueter (M12): Ressource -> Laune-Bonus je Versorgung. Wird vom
## Controller aus resources.json befuellt ("luxury_mood"-Feld). Ist genug
## fuer alle Bewohner da, wird verbraucht und die Laune steigt.
var luxuries: Dictionary = {}
## Waren seit der letzten Versorgung Feinde nahe der Siedlung?
var threatened_since_feeding: bool = false

## Fuegt ein Gebaeude zur Simulation hinzu.
func add_building(building: BuildingInstance) -> void:
	buildings.append(building)

## Liefert das erste Gebaeude mit der gegebenen Definitions-ID (oder null).
func get_building(def_id: StringName) -> BuildingInstance:
	for b in buildings:
		if b.def_id == def_id:
			return b
	return null

## Entfernt das Gebaeude auf einer Zelle (z. B. zerstoerte Mauer).
## Rueckgabe: true, wenn eines entfernt wurde.
func remove_building_at(cell: Vector2i) -> bool:
	for i in buildings.size():
		if buildings[i].cell == cell:
			buildings.remove_at(i)
			return true
	return false

## Gebaeude auf einer Zelle (oder null).
func get_building_at(cell: Vector2i) -> BuildingInstance:
	for b in buildings:
		if b.cell == cell:
			return b
	return null

## Nach Wohnraum-Verlust (M11: Abriss): entlaesst Arbeiter, bis alle
## Bewohner wieder Platz haben. Rueckgabe: Zahl der Entlassenen.
## Soldaten (reserved_population) sind unantastbar — das muss der
## Aufrufer VOR dem Abriss pruefen.
func evict_overflow_workers() -> int:
	var evicted := 0
	while assigned_workers() + reserved_population > housing_capacity():
		if not _remove_any_worker():
			break
		evicted += 1
	return evicted

func _remove_any_worker() -> bool:
	for i in range(buildings.size() - 1, -1, -1):
		if buildings[i].workers > 0:
			buildings[i].workers -= 1
			return true
	return false

## Summe der Arbeiter bzw. Plaetze ueber alle Instanzen eines Gebaeudetyps
## (M8: derselbe Typ kann mehrfach gebaut werden).
func workers_of(def_id: StringName) -> int:
	var total := 0
	for b in buildings:
		if b.def_id == def_id:
			total += b.workers
	return total

func max_workers_of(def_id: StringName) -> int:
	var total := 0
	for b in buildings:
		if b.def_id == def_id:
			total += b.max_workers
	return total

## Arbeitsleistung 0.25..1.5: haengt an Zufriedenheit und Arbeitszeit-Politik.
## "Je schlechter es den Leuten geht, desto schlechter arbeiten sie."
func productivity() -> float:
	var base := 0.5 + satisfaction / 100.0
	return clampf(base * float(WORK_MULTIPLIERS[work_policy]), 0.25, 1.5)

## Meldung des Kampfsystems: Feinde nahe der Siedlung (wirkt bei der
## naechsten Versorgung auf die Laune).
func set_threatened() -> void:
	threatened_since_feeding = true

## Aktueller Bestand einer Ressource (0, falls unbekannt).
func get_stock(resource_id: StringName) -> int:
	return int(stock.get(resource_id, 0))

## Summe aller Wohnplaetze.
func housing_capacity() -> int:
	var total := 0
	for b in buildings:
		total += b.housing_capacity
	return total

## Summe aller zugeteilten Arbeiter.
func assigned_workers() -> int:
	var total := 0
	for b in buildings:
		total += b.workers
	return total

## Freie Wohnplaetze (Kapazitaet minus Arbeiter minus Soldaten).
func free_housing() -> int:
	return housing_capacity() - assigned_workers() - reserved_population

## Spielerregel fuer Arbeiterzuteilung (ein Schritt +1/-1 je Aufruf):
## respektiert max_workers UND freien Wohnraum; verteilt ueber Instanzen
## (+1 fuellt die erste freie, -1 leert die letzte besetzte).
## Rueckgabe: true, wenn sich etwas geaendert hat.
func try_change_workers(def_id: StringName, delta: int) -> bool:
	if delta > 0:
		if free_housing() <= 0:
			return false
		for b in buildings:
			if b.def_id == def_id and b.workers < b.max_workers:
				b.workers += 1
				return true
		return false
	if delta < 0:
		for i in range(buildings.size() - 1, -1, -1):
			var b: BuildingInstance = buildings[i]
			if b.def_id == def_id and b.workers > 0:
				b.workers -= 1
				return true
	return false

## Ein Simulationsschritt: Produktion aller Gebaeude, periodisch Versorgung.
## Rueckgabe: Liste der veraenderten Ressourcen-IDs (fuer gezielte UI-Updates).
func tick() -> Array:
	tick_count += 1
	var changed: Array = []
	for b in buildings:
		_produce(b, changed)
	if tick_count % FOOD_INTERVAL == 0:
		_feed_workers(changed)
	return changed

## Produktion eines Gebaeudes: nur wenn alle Eingaenge gedeckt sind
## (keine Teilproduktion), erst verbrauchen, dann erzeugen. Die Ausbeute
## skaliert mit der Arbeitsleistung UND der Saison (M-Jahreszeiten:
## Faktor 0 — z. B. Felder im Winter — stoppt das Gebaeude komplett,
## ohne Eingaenge zu verschwenden); Bruchteile sammeln sich im Uebertrag.
func _produce(b: BuildingInstance, changed: Array) -> void:
	if b.workers == 0 or b.produces == &"":
		return
	var season_factor := b.season_factor(Calendar.season(tick_count))
	if season_factor <= 0.0:
		return  # Saisonpause (Winterruhe): kein Verbrauch, keine Ausbeute
	for res in b.consumes:
		if get_stock(res) < b.input_needed(res):
			return
	for res in b.consumes:
		stock[res] = get_stock(res) - b.input_needed(res)
		_mark_changed(changed, res)
	b.production_carry += (b.production() * productivity() * season_factor
		* b.weather_factor(current_weather))
	var whole := int(b.production_carry)
	if whole > 0:
		b.production_carry -= whole
		stock[b.produces] = get_stock(b.produces) + whole
		_mark_changed(changed, b.produces)

## Versorgung: jeder Bewohner (Arbeiter UND Soldat) isst gemaess Rationen-
## Politik. Laune-Bilanz aus Versorgung, Rationen, Arbeitszeit und Bedrohung.
func _feed_workers(changed: Array) -> void:
	var residents := assigned_workers() + reserved_population
	if residents == 0:
		threatened_since_feeding = false
		return
	var need := int(ceilf(residents * float(RATION_MULTIPLIERS[ration_level])))
	var eaten := mini(need, get_stock(FOOD_RESOURCE))
	if eaten > 0:
		stock[FOOD_RESOURCE] = get_stock(FOOD_RESOURCE) - eaten
		_mark_changed(changed, FOOD_RESOURCE)
	var delta := SATISFACTION_FED_GAIN if eaten == need else -SATISFACTION_HUNGER_LOSS
	delta += int(RATION_MOOD[ration_level]) + int(WORK_MOOD[work_policy])
	delta += int(TAX_MOOD[tax_level])
	var tax_income := int(TAX_GOLD[tax_level]) * residents
	if tax_income > 0:
		stock[&"gold"] = get_stock(&"gold") + tax_income
		_mark_changed(changed, &"gold")
	delta += _consume_luxuries(residents, changed)
	if threatened_since_feeding:
		delta -= THREAT_MOOD_LOSS
		threatened_since_feeding = false
	satisfaction = clampi(satisfaction + delta, 0, 100)

## Handel am Marktplatz (M13): amount > 0 kauft (Kaufpreis = 2x Grundpreis),
## amount < 0 verkauft zum Grundpreis. Rueckgabe: {"ok", "reason"}.
func trade(resource: StringName, amount: int, unit_price: int) -> Dictionary:
	if amount == 0 or unit_price <= 0:
		return {"ok": false, "reason": "Diese Ware wird nicht gehandelt."}
	if amount > 0:
		var cost := amount * unit_price * 2
		if get_stock(&"gold") < cost:
			return {"ok": false, "reason": "Nicht genug Gold."}
		stock[&"gold"] = get_stock(&"gold") - cost
		stock[resource] = get_stock(resource) + amount
	else:
		var sell := -amount
		if get_stock(resource) < sell:
			return {"ok": false, "reason": "Nicht genug Ware im Lager."}
		stock[resource] = get_stock(resource) - sell
		stock[&"gold"] = get_stock(&"gold") + sell * unit_price
	return {"ok": true, "reason": ""}

## Luxusgueter heben die Laune: je Sorte, von der genug fuer alle Bewohner
## da ist, wird eine Einheit pro Kopf verbraucht (Bier, Wein, Kaese ...).
func _consume_luxuries(residents: int, changed: Array) -> int:
	var bonus := 0
	for res in luxuries:
		if get_stock(res) >= residents:
			stock[res] = get_stock(res) - residents
			_mark_changed(changed, res)
			bonus += int(luxuries[res])
	return bonus

func _mark_changed(changed: Array, resource_id: StringName) -> void:
	if not changed.has(resource_id):
		changed.append(resource_id)

## Serialisiert die gesamte Wirtschaft fuer den Spielstand.
func to_dict() -> Dictionary:
	var building_list: Array = []
	for b in buildings:
		building_list.append(b.to_dict())
	var stock_out: Dictionary = {}
	for key in stock:
		stock_out[String(key)] = int(stock[key])
	return {
		"stock": stock_out,
		"buildings": building_list,
		"satisfaction": satisfaction,
		"tick_count": tick_count,
		"reserved_population": reserved_population,
		"ration_level": ration_level,
		"work_policy": work_policy,
		"tax_level": tax_level,
	}

## Stellt die Wirtschaft aus einem gespeicherten Dictionary wieder her.
## Fehlende Felder (aeltere Spielstaende) fallen auf Standardwerte zurueck.
func from_dict(d: Dictionary) -> void:
	stock.clear()
	buildings.clear()
	var stock_in: Dictionary = d.get("stock", {})
	for key in stock_in:
		stock[StringName(key)] = int(stock_in[key])
	for building_dict in d.get("buildings", []):
		buildings.append(BuildingInstance.from_dict(building_dict))
	satisfaction = clampi(int(d.get("satisfaction", SATISFACTION_START)), 0, 100)
	tick_count = int(d.get("tick_count", 0))
	reserved_population = int(d.get("reserved_population", 0))
	ration_level = clampi(int(d.get("ration_level", 1)), 0, 2)
	work_policy = clampi(int(d.get("work_policy", 1)), 0, 2)
	tax_level = clampi(int(d.get("tax_level", 0)), 0, 2)
	threatened_since_feeding = false
