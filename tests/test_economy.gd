extends RefCounted
## Unit-Tests fuer die Wirtschaftslogik (M1/M2).
##
## Prueft Produktion, Verbrauchskette (Weizen -> Brot), Wohnraum-Regel,
## Versorgung/Zufriedenheit und Speicher-Roundtrip rein logisch (ohne UI).
## Leere Fehlerliste == bestanden.

func run() -> Array:
	var failures: Array = []
	_test_production_with_worker(failures)
	_test_no_production_without_worker(failures)
	_test_worker_clamp(failures)
	_test_chain_needs_input(failures)
	_test_chain_consumes_and_produces(failures)
	_test_housing_limits_assignment(failures)
	_test_reserved_population_blocks_housing(failures)
	_test_feeding_raises_and_lowers_satisfaction(failures)
	_test_worker_distribution_over_instances(failures)
	_test_demolition_evicts_overflow_workers(failures)
	_test_productivity_scales_output(failures)
	_test_policies_affect_feeding_and_mood(failures)
	_test_threat_lowers_mood(failures)
	_test_luxuries_boost_mood(failures)
	_test_taxes_and_trade(failures)
	_test_economy_roundtrip(failures)
	return failures

## Baut eine Test-Holzfaellerhuette (2 Holz/Tick, max 1 Arbeiter).
func _make_woodcutter() -> BuildingInstance:
	return BuildingInstance.from_def({
		"id": "woodcutter",
		"produces": "wood",
		"production_per_tick": 2,
		"max_workers": 1,
	})

## Baut eine Test-Baeckerei (verbraucht 2 Weizen -> 1 Brot je Arbeiter).
func _make_bakery() -> BuildingInstance:
	return BuildingInstance.from_def({
		"id": "bakery",
		"produces": "bread",
		"production_per_tick": 1,
		"max_workers": 2,
		"consumes": {"wheat": 2},
	})

## Baut ein Test-Wohnhaus mit gegebener Kapazitaet.
func _make_house(capacity: int) -> BuildingInstance:
	return BuildingInstance.from_def({"id": "house", "housing_capacity": capacity})

## Mit Arbeiter wird pro Tick produziert.
func _test_production_with_worker(failures: Array) -> void:
	var eco := Economy.new()
	var b := _make_woodcutter()
	b.set_workers(1)
	eco.add_building(b)
	eco.tick()
	eco.tick()
	if eco.get_stock(&"wood") != 4:
		failures.append("Produktion: erwartet 4 Holz, erhalten %d" % eco.get_stock(&"wood"))

## Ohne Arbeiter keine Produktion.
func _test_no_production_without_worker(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_woodcutter())
	eco.tick()
	if eco.get_stock(&"wood") != 0:
		failures.append("OhneArbeiter: erwartet 0 Holz, erhalten %d" % eco.get_stock(&"wood"))

## Arbeiterzahl wird auf max_workers begrenzt.
func _test_worker_clamp(failures: Array) -> void:
	var b := _make_woodcutter()
	b.set_workers(5)
	if b.workers != 1:
		failures.append("Clamp: erwartet 1 Arbeiter (max), erhalten %d" % b.workers)

## Kette: ohne Eingangsressource keine Produktion (keine Teilproduktion).
func _test_chain_needs_input(failures: Array) -> void:
	var eco := Economy.new()
	var bakery := _make_bakery()
	bakery.set_workers(1)
	eco.add_building(bakery)
	eco.tick()
	if eco.get_stock(&"bread") != 0:
		failures.append("KetteOhneInput: erwartet 0 Brot, erhalten %d" % eco.get_stock(&"bread"))

## Kette: Eingaenge werden verbraucht, Ausgang erzeugt (skaliert mit Arbeitern).
func _test_chain_consumes_and_produces(failures: Array) -> void:
	var eco := Economy.new()
	var bakery := _make_bakery()
	bakery.set_workers(2)  # verbraucht 4 Weizen, erzeugt 2 Brot
	eco.add_building(bakery)
	eco.stock[&"wheat"] = 5
	eco.tick()
	if eco.get_stock(&"bread") != 2 or eco.get_stock(&"wheat") != 1:
		failures.append("Kette: erwartet 2 Brot/1 Weizen, erhalten %d/%d" % [
			eco.get_stock(&"bread"), eco.get_stock(&"wheat")])
	eco.tick()  # nur noch 1 Weizen -> reicht nicht fuer 2 Arbeiter
	if eco.get_stock(&"bread") != 2:
		failures.append("KetteMangel: Teilproduktion trotz Weizenmangel")

## Wohnraum begrenzt die Gesamtzahl zugeteilter Arbeiter.
func _test_housing_limits_assignment(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(1))
	eco.add_building(_make_woodcutter())
	eco.add_building(_make_bakery())
	if not eco.try_change_workers(&"woodcutter", 1):
		failures.append("Wohnraum: erste Zuteilung muss gelingen")
	if eco.try_change_workers(&"bakery", 1):
		failures.append("Wohnraum: Zuteilung ueber Kapazitaet darf nicht gelingen")
	if not eco.try_change_workers(&"woodcutter", -1):
		failures.append("Wohnraum: Abziehen muss gelingen")
	if not eco.try_change_workers(&"bakery", 1):
		failures.append("Wohnraum: frei gewordener Platz muss nutzbar sein")

## Soldaten (reserved_population) belegen Wohnraum und essen mit (M5).
func _test_reserved_population_blocks_housing(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(2))
	eco.add_building(_make_woodcutter())
	eco.reserved_population = 2
	if eco.try_change_workers(&"woodcutter", 1):
		failures.append("Reserve: Soldaten muessen Wohnraum blockieren")
	eco.reserved_population = 1
	if not eco.try_change_workers(&"woodcutter", 1):
		failures.append("Reserve: freier Platz muss nutzbar bleiben")
	eco.stock[&"bread"] = 2
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.get_stock(&"bread") != 0:
		failures.append("Reserve: Soldat muss mitessen (Brot uebrig: %d)" % eco.get_stock(&"bread"))

## Versorgung: satt -> Zufriedenheit steigt; hungrig -> sie sinkt.
func _test_feeding_raises_and_lowers_satisfaction(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(1))
	var b := _make_woodcutter()
	b.set_workers(1)
	eco.add_building(b)
	eco.stock[&"bread"] = 1
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.satisfaction != Economy.SATISFACTION_START + Economy.SATISFACTION_FED_GAIN:
		failures.append("Versorgung: erwartet %d, erhalten %d" % [
			Economy.SATISFACTION_START + Economy.SATISFACTION_FED_GAIN, eco.satisfaction])
	if eco.get_stock(&"bread") != 0:
		failures.append("Versorgung: Brot muss gegessen sein, Bestand %d" % eco.get_stock(&"bread"))
	for i in Economy.FOOD_INTERVAL:
		eco.tick()  # kein Brot mehr -> Hunger
	var expected := Economy.SATISFACTION_START + Economy.SATISFACTION_FED_GAIN - Economy.SATISFACTION_HUNGER_LOSS
	if eco.satisfaction != expected:
		failures.append("Hunger: erwartet %d, erhalten %d" % [expected, eco.satisfaction])

## M8: +1 fuellt die erste freie Instanz, -1 leert die letzte besetzte.
func _test_worker_distribution_over_instances(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(4))
	eco.add_building(_make_woodcutter())
	eco.add_building(_make_woodcutter())
	eco.try_change_workers(&"woodcutter", 1)
	eco.try_change_workers(&"woodcutter", 1)
	if eco.workers_of(&"woodcutter") != 2 or eco.max_workers_of(&"woodcutter") != 2:
		failures.append("Verteilung: 2/2 erwartet, erhalten %d/%d" % [
			eco.workers_of(&"woodcutter"), eco.max_workers_of(&"woodcutter")])
	if eco.buildings[1].workers != 1 or eco.buildings[2].workers != 1:
		failures.append("Verteilung: beide Instanzen muessen je 1 Arbeiter haben")
	eco.try_change_workers(&"woodcutter", -1)
	if eco.buildings[2].workers != 0 or eco.buildings[1].workers != 1:
		failures.append("Verteilung: -1 muss die letzte Instanz leeren")

## M11: Wohnraum-Abriss entlaesst ueberzaehlige Arbeiter (nicht mehr, als
## noetig); Soldaten bleiben unangetastet.
func _test_demolition_evicts_overflow_workers(failures: Array) -> void:
	var eco := Economy.new()
	var house_a := _make_house(2)
	house_a.cell = Vector2i(1, 1)
	eco.add_building(house_a)
	eco.add_building(_make_house(2))
	var wc_a := _make_woodcutter()
	wc_a.set_workers(1)
	eco.add_building(wc_a)
	var wc_b := _make_woodcutter()
	wc_b.set_workers(1)
	eco.add_building(wc_b)
	eco.reserved_population = 1  # 3 Bewohner auf 4 Plaetzen
	if not eco.remove_building_at(Vector2i(1, 1)):
		failures.append("Abriss: Haus auf (1,1) muss entfernbar sein")
	if eco.evict_overflow_workers() != 1:  # 3 Bewohner, 2 Plaetze -> 1 Arbeiter geht
		failures.append("Abriss: genau 1 Arbeiter muss entlassen werden")
	if eco.assigned_workers() + eco.reserved_population != eco.housing_capacity():
		failures.append("Abriss: Belegung muss der Kapazitaet entsprechen")
	if eco.reserved_population != 1:
		failures.append("Abriss: Soldaten duerfen nicht entlassen werden")
	if eco.get_building_at(Vector2i(1, 1)) != null:
		failures.append("Abriss: get_building_at muss leer melden")

## M8: Arbeitsleistung skaliert die Ausbeute (0.5..1.5 je nach Laune).
func _test_productivity_scales_output(failures: Array) -> void:
	var eco := Economy.new()
	var b := _make_woodcutter()  # 2 Holz/Tick Basis
	b.set_workers(1)
	eco.add_building(b)
	eco.satisfaction = 100  # Faktor 1.5 -> 3 Holz/Tick
	eco.tick()
	eco.tick()
	if eco.get_stock(&"wood") != 6:
		failures.append("Leistung: bei 100%% Laune erwartet 6 Holz, erhalten %d" % eco.get_stock(&"wood"))
	eco.satisfaction = 0  # Faktor 0.5 -> 1 Holz/Tick
	eco.tick()
	if eco.get_stock(&"wood") != 7:
		failures.append("Leistung: bei 0%% Laune erwartet +1 Holz, erhalten %d" % eco.get_stock(&"wood"))

## M8: Rationen aendern Verbrauch und Laune, Arbeitszeit Laune und Leistung.
func _test_policies_affect_feeding_and_mood(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(4))
	var b := _make_woodcutter()
	b.set_workers(1)
	eco.add_building(b)
	eco.ration_level = 2  # doppelt: 1 Arbeiter isst 2, Laune +5 extra
	eco.stock[&"bread"] = 2
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.get_stock(&"bread") != 0:
		failures.append("Rationen: doppelt muss 2 Brot verbrauchen")
	if eco.satisfaction != 60:  # 50 +5 (satt) +5 (doppelte Rationen)
		failures.append("Rationen: erwartet 60, erhalten %d" % eco.satisfaction)
	eco.work_policy = 2  # lange Arbeit: Laune -8 je Versorgung, Leistung x1.2
	if not is_equal_approx(eco.productivity(), clampf((0.5 + 0.6) * 1.2, 0.25, 1.5)):
		failures.append("Arbeitszeit: Leistungsfaktor falsch: %f" % eco.productivity())
	eco.stock[&"bread"] = 2
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.satisfaction != 62:  # 60 +5 (satt) +5 (Rationen) -8 (lange Arbeit)
		failures.append("Arbeitszeit: erwartet 62, erhalten %d" % eco.satisfaction)

## M8: Bedrohung seit der letzten Versorgung drueckt die Laune einmalig.
func _test_threat_lowers_mood(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(4))
	var b := _make_woodcutter()
	b.set_workers(1)
	eco.add_building(b)
	eco.stock[&"bread"] = 10
	eco.set_threatened()
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.satisfaction != 47:  # 50 +5 (satt) -8 (Bedrohung)
		failures.append("Bedrohung: erwartet 47, erhalten %d" % eco.satisfaction)
	for i in Economy.FOOD_INTERVAL:
		eco.tick()  # keine neue Bedrohung -> nur +5
	if eco.satisfaction != 52:
		failures.append("Bedrohung: Malus darf nur einmal wirken (%d)" % eco.satisfaction)

## M12: Luxusgueter heben die Laune, wenn genug fuer alle da ist —
## und werden dabei verbraucht; zu wenig bleibt unangetastet.
func _test_luxuries_boost_mood(failures: Array) -> void:
	var eco := Economy.new()
	eco.luxuries = {&"beer": 2, &"wine": 3}
	eco.add_building(_make_house(4))
	var b := _make_woodcutter()
	b.set_workers(2)  # max 1 -> 1 Arbeiter... Werte pruefen
	b.max_workers = 2
	b.set_workers(2)
	eco.add_building(b)
	eco.stock[&"bread"] = 10
	eco.stock[&"beer"] = 5   # reicht fuer 2 Bewohner
	eco.stock[&"wine"] = 1   # reicht NICHT
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.satisfaction != 57:  # 50 +5 satt +2 Bier
		failures.append("Luxus: erwartet 57, erhalten %d" % eco.satisfaction)
	if eco.get_stock(&"beer") != 3 or eco.get_stock(&"wine") != 1:
		failures.append("Luxus: Verbrauch falsch (Bier %d, Wein %d)" % [
			eco.get_stock(&"beer"), eco.get_stock(&"wine")])

## M13: Steuern bringen Gold je Bewohner und druecken die Laune;
## Handel kauft zum doppelten und verkauft zum einfachen Grundpreis.
func _test_taxes_and_trade(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(4))
	var b := _make_woodcutter()
	b.max_workers = 2
	b.set_workers(2)
	eco.add_building(b)
	eco.stock[&"bread"] = 10
	eco.tax_level = 2  # hoch: 2 Gold/Bewohner, Laune -8
	for i in Economy.FOOD_INTERVAL:
		eco.tick()
	if eco.get_stock(&"gold") != 4:  # 2 Bewohner x 2 Gold
		failures.append("Steuern: erwartet 4 Gold, erhalten %d" % eco.get_stock(&"gold"))
	if eco.satisfaction != 47:  # 50 +5 satt -8 Steuern
		failures.append("Steuern: erwartet Laune 47, erhalten %d" % eco.satisfaction)
	# Handel: kaufen kostet 2x Preis, verkaufen bringt 1x (frische Economy
	# ohne Produktion, damit die Bestaende exakt bleiben)
	var markt := Economy.new()
	markt.stock[&"gold"] = 20
	if not markt.trade(&"wood", 5, 1)["ok"] or markt.get_stock(&"gold") != 10 or markt.get_stock(&"wood") != 5:
		failures.append("Handel: Kauf falsch (Gold %d, Holz %d)" % [markt.get_stock(&"gold"), markt.get_stock(&"wood")])
	if not markt.trade(&"wood", -5, 1)["ok"] or markt.get_stock(&"gold") != 15 or markt.get_stock(&"wood") != 0:
		failures.append("Handel: Verkauf falsch (Gold %d)" % markt.get_stock(&"gold"))
	if markt.trade(&"wood", -1, 1)["ok"]:
		failures.append("Handel: Verkauf ohne Ware muss scheitern")
	if markt.trade(&"wood", 100, 1)["ok"]:
		failures.append("Handel: Kauf ohne Gold muss scheitern")
	if markt.trade(&"gold", 1, 0)["ok"]:
		failures.append("Handel: Ware ohne Preis darf nicht handelbar sein")

## Bestand, Gebaeude und Zufriedenheit ueberstehen einen Speicher-Roundtrip.
func _test_economy_roundtrip(failures: Array) -> void:
	var eco := Economy.new()
	eco.add_building(_make_house(4))
	var bakery := _make_bakery()
	bakery.set_workers(1)
	eco.add_building(bakery)
	eco.stock[&"wheat"] = 10
	eco.tick()  # 8 Weizen, 1 Brot
	eco.satisfaction = 73
	var restored := Economy.new()
	restored.from_dict(eco.to_dict())
	if restored.get_stock(&"wheat") != 8 or restored.get_stock(&"bread") != 1:
		failures.append("Roundtrip: Bestand falsch (%d Weizen, %d Brot)" % [
			restored.get_stock(&"wheat"), restored.get_stock(&"bread")])
	if restored.satisfaction != 73 or restored.tick_count != 1:
		failures.append("Roundtrip: Zufriedenheit/Tick falsch")
	var rb := restored.get_building(&"bakery")
	if rb == null or rb.workers != 1 or rb.input_needed(&"wheat") != 2:
		failures.append("Roundtrip: Baeckerei nicht korrekt wiederhergestellt")
	if restored.housing_capacity() != 4:
		failures.append("Roundtrip: Wohnraum falsch: %d" % restored.housing_capacity())
