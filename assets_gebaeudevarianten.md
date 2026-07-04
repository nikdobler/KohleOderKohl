# Gebäude-Stilvarianten — offene Assets (M-Gebäudevarianten)

Code-fertig, aber noch nicht gezeichnet. Bis die PNG existiert, rendert das Spiel
automatisch das **Basis-Sprite** `building_<id>.png` (Kaskade in
`AssetRegistry.building_asset_id`). Datei ablegen unter `res://assets/<dateiname>.png`
in der Iso-Auflösung/-Ausrichtung der bestehenden `building_*`-Sprites — kein Code
nötig, die Registry zieht die Datei automatisch.

Auswahl erfolgt datengetrieben über `data/settlement_types.json`
(`types.<siedlungstyp>.building_variants.<gebäude>`). Aktuell nur Siedlungstyp
**heartland** ("Kernland", mitteleuropäisch-mittelalterlich).

## Siedlungstyp „heartland" (Kernland)

| Dateiname | Gebäude | Beschreibung |
|---|---|---|
| `building_house_fachwerk.png` | Wohnhaus | Fachwerkhaus: dunkle Holzbalken über hellem Lehmputz, steiles Satteldach mit rötlichen Ziegeln, kleiner Rauchfang. |
| `building_house_strohdach.png` | Wohnhaus | Kate mit dicht gebundenem, goldbraunem Strohdach, niedrige Lehmwände, schlicht — ärmlicher wirkend. |
| `building_house_stein.png` | Wohnhaus | Steinhaus aus grauem Bruchstein, wenige kleine Fenster, flacheres Schieferdach — wohlhabender wirkend. |
| `building_woodcutter_blockhaus.png` | Holzfällerhütte | Blockhütte aus liegenden Rundstämmen, Axt im Hauklotz davor, Holzstapel an der Wand. |
| `building_woodcutter_schindeldach.png` | Holzfällerhütte | Bretterhütte mit Holzschindeldach, offener Sägebock, gestapelte Bretter. |
| `building_wheat_farm_scheune.png` | Weizenfeld | Kleine Feldscheune am Ackerrand: großes Tor, Fachwerk, Heu-Andeutung im Giebel. |
| `building_wheat_farm_speicher.png` | Weizenfeld | Kornspeicher auf Pfählen (Mäuseschutz), Leiter, geschlossene Bretterwand. |
| `building_bakery_holzofen.png` | Bäckerei | Backhaus mit vorspringendem Lehm-Kuppelofen, sichtbarer Rauch, Brennholz gestapelt. |
| `building_bakery_steinofen.png` | Bäckerei | Steinerne Backstube mit gemauertem Kamin, Fensterluke mit Brotlaib-Andeutung. |

Weitere Siedlungstypen (z. B. nördlich, südlich) kommen später additiv hinzu und
bringen je eigene Varianten-Assets mit — dann als eigener Abschnitt hier.
