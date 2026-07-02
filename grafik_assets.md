# Grafik-Assets — „Krone und Kohl"

Vollständige Liste aller im Code und in den Daten referenzierten Grafik-Objekte,
extrahiert aus `scripts/`, `ui/` und `data/`. Grundlage für die schrittweise
Erstellung der Pixelart (goal §3).

> **Status:** Der Ordner `assets/` ist noch leer. Alle Objekte werden zur Laufzeit
> vom [`AssetRegistry`](scripts/autoload/asset_registry.gd) als farbige Platzhalter
> erzeugt. Sobald unter `res://assets/<id>.png` eine echte Grafik liegt, wird sie
> **automatisch** statt des Platzhalters geladen — Spielcode muss nicht angefasst werden.

---

## 1 Verbindliche technische Vorgaben

| Aspekt | Vorgabe | Quelle |
|---|---|---|
| **Stil** | Stilisiert 2D-**isometrisch**, liebevoll verspielt, detailreich, **Pixelart**, Mittelalter-Referenzen, kein Fotorealismus | goal §3 |
| **Stimmung / Palette** | Naturfarben, freundlich | goal §3 |
| **Dateiformat** | `PNG`, RGBA8 (mit Transparenz) | `asset_registry.gd` (`FORMAT_RGBA8`) |
| **Ablageort** | `res://assets/<id>.png` — **Dateiname = Asset-ID** | `asset_registry.gd:38` |
| **Namenskonvention** | `tile_<biom>`, `feature_<merkmal>`, `building_<id>`, `unit_<typ>`, `resource_<id>`, `npc_<id>`, `animal_<typ>` | `asset_registry.gd:9` |
| **Iso-Kachelgröße** | **64 × 32 px** (Diamant), `TILE_SHAPE_ISOMETRIC`, `LAYOUT_DIAMOND_DOWN` | `asset_registry.gd:13`, `world_view.gd:112` |
| **Fenster / Auflösung** | 1280 × 720 px | `project.godot` |
| **Hintergrundfarbe** | `Color(0.13, 0.15, 0.12)` (dunkles Waldgrün) | `project.godot` |
| **Sprite-Anker** | Godot `Sprite2D` ist standardmäßig **zentriert** — Motiv mittig, Grundlinie beachten (siehe Offsets unten) | `world_view.gd` |

**Wichtig zur Iso-Perspektive:** Bodenkacheln sind exakte Rauten von 64×32 px, die
sich kantenbündig zu einem Diamant-Raster fügen (Layout `DIAMOND_DOWN`). Gebäude-,
Merkmal- und Einheiten-Grafiken sind **freistehende Sprites** über diesem Raster —
sie dürfen höher als 32 px sein (nach oben ragen), sollten aber mit ihrer
**Grundfläche in die 64px-Rautenbreite** passen.

---

## 2 Bodenkacheln (`tile_*`)

Iso-Rauten **64 × 32 px**, kantenbündig. Farbe stammt aus `biomes.json`.

Die Biom-Zuordnung erfolgt über ein **Noise-Band** (`noise_max`, aufsteigend):
`_pick_biome` nimmt das erste Biom, dessen `noise_max` den Rauschwert abdeckt. Die
Biome bilden einen **Höhengradienten** von der feuchten Senke bis zum Schneegipfel.
Das optionale Flag `passable` (Standard `true`) steuert die Einheiten-Begehbarkeit
im Kampf.

| Asset-ID | Biom | Farbe | `noise_max` | Feature (Baum/Fels) | Bebaubar? | Anmerkung |
|---|---|---|---|---|---|---|
| `tile_water_deep`/`_shallow` | Wasser (See) | `#2f6b8f`/`#4f97b8` | −0.53 | — / — | nein | **Unterstes** Band (~17 Zellen); unpassierbar; Ufer flach, innen tief (§8.3) |
| `tile_swamp` | Sumpf | `#5f6b47` | −0.45 | 0.07 / — | nein | Feuchte Senke; **unpassierbar** (`passable:false`) — passt zur Erzählung |
| `tile_valley` | Tal | `#6aa048` | −0.20 | 0.10 / — | **ja** (wie Grasland) | Fruchtbares Tiefland (~18 %), sattes Grün; alle Grasland-Bauten erlaubt |
| `tile_grassland` | Grasland | `#7dae5a` | 0.1 | 0.16 / 0.01 | ja | Flachland, Standardbiom, meiste Bebauung |
| `tile_hills` | Hügel | `#8fa05e` | 0.4 | 0.05 / 0.06 | ja | Höhenlage, leicht gelblicher als Grasland |
| `tile_highlands` | Felsland | `#9a9186` | 0.5 | 0.02 / 0.14 | ja (Fels) | Karg, steinig, viele Felsen (Steinbruch/Festung) |
| `tile_snow` | Schnee | `#e2e8ea` | 1.0 | — / — | nein | Barren Gipfel, oberstes Band (~0,4 %); kahl, kein Gebäude listet `snow` |

- **Varianten empfohlen:** je Biom 2–4 leicht variierte Kacheln gegen sichtbare
  Kachelwiederholung (das System lädt aktuell **eine** ID pro Biom — Varianten
  würden zusätzliche Registry-Logik erfordern; vorerst 1 Kachel pro Biom liefern).
- Ränder dezent abdunkeln (Platzhalter macht `darkened(0.25)` am Rand), damit sich
  Kacheln im Raster leicht abheben.

**Nicht-Biom-Kachel `tile_farmland`** (`#b98c4a`, Ackerbraun): kein generiertes Biom,
sondern eine Boden­kachel, die `world_view` **unter jedes Weizenfeld** malt (und beim
Abriss wieder auf das Biom zurücksetzt). Ihre Platzhalterfarbe kommt aus
`_PLACEHOLDER_COLORS` (der `tile_`-Zweig prüft explizite Farben vor der Biom-Farbe).
Grafik: bestellter Acker mit Furchen, passend unter/um die `building_wheat_farm`-Grafik.

---

## 3 Gelände-Merkmale (`feature_*`)

Overlay-Sprites auf der Kachel (Layer über dem Boden), gezeichnet auf 64×32-Canvas.
Als Ressourcenquelle / Bauvoraussetzung spielrelevant.

| Asset-ID | Merkmal | Platzhalterfarbe | Spielfunktion |
|---|---|---|---|
| `feature_tree` | Baum | `#3e6b34` | Voraussetzung (Radius 3) für **Holzfällerhütte** |
| `feature_rock` | Fels | `#736d64` | Bauplatz-Voraussetzung (`on_feature`) für **Steinbruch** |

- **Varianten empfohlen:** Baum & Fels je 2–3 Formen/Größen für natürliche Streuung.
- Motiv innerhalb der Rautenfläche verankern (Fuß auf Kachelmitte), Transparenz außen.

---

## 4 Gebäude (`building_*`)

Freistehende `Sprite2D`, platziert bei `map_to_local(slot) + (0, −10 px)` — d.h. das
Gebäude sitzt etwas oberhalb der Kachelmitte. Platzhalter = 40×40-Box. **Empfohlene
Realgröße:** Grundfläche ~64 px breit, Höhe je nach Bau (Bergfried/Turm höher).

| Asset-ID | Anzeigename | Funktion | Produziert / Verbraucht | Kosten | HP | Platzierung | Platzhalterfarbe |
|---|---|---|---|---|---|---|---|
| `building_keep` | Bergfried | Zentrum, Militär-Basis | — | (Start) | 120 | Startgebäude | `#5a5f66` |
| `building_woodcutter` | Holzfällerhütte | Holzgewinnung | +1 Holz/Tick | 4 Holz | — | Grasland/Hügel, nahe **Baum** (R3) | `#8a5a2b` |
| `building_wheat_farm` | Weizenfeld | Nahrungsanbau | +2 Weizen/Tick | 6 Holz | — | Grasland | `#d9b13b` |
| `building_bakery` | Bäckerei | Brotherstellung | +1 Brot, −2 Weizen | 8 Holz | — | Grasland | `#c07840` |
| `building_house` | Wohnhaus | Wohnraum (+4) | — | 5 Holz | — | Grasland/Hügel | `#a8794a` |
| `building_quarry` | Steinbruch | Steingewinnung | +1 Stein/Tick | 10 Holz | — | auf **Fels**; Gras/Hügel/Fels | `#8d8d8d` |
| `building_brewery` | Brauerei | Bierherstellung | +1 Bier, −2 Weizen | 8 Holz | — | Grasland | `#6b4f2e` |
| `building_wall` | Mauer | Verteidigung | — | 2 Stein | 60 | Gras/Hügel/Fels, auf Fels/frei | `#77787c` |
| `building_tower` | Wachturm | Verteidigung | — | 6 Stein | 150 | Gras/Hügel/Fels, auf Fels/frei | `#4c4f57` |

**Freischaltung (Tech-Tree, `tech.json`):** `quarry` ← Steinmetzkunst · `brewery` ←
Braukunst · `wall`+`tower` ← Festungsbau. Für UI/Tooltip ggf. relevant, für das
Sprite selbst nicht.

**Gegner-Bergfried:** eigenes Objekt im Kampf, verwendet **dieselbe** Grafik
`building_keep`, aber rot eingefärbt (`modulate = Color(1.0, 0.72, 0.72)`,
`world_view.gd:104`). Kein separates Asset nötig.

> **Hinweis Namenskonvention:** Das `icon`-Feld in `buildings.json` enthält die
> volle Asset-ID (z. B. `"icon": "building_keep"`) und ist damit einheitlich zu
> Ressourcen und NPCs. Das Rendering baut die ID aktuell zwar noch selbst aus dem
> Präfix (`"building_" + id`, `world_view.gd:73`), aber `icon`-Feld und
> konstruierte ID sind nun identisch — beide zeigen auf `res://assets/building_<id>.png`.

---

## 5 Einheiten (`unit_*`)

Kleine `Sprite2D`, platziert bei `map_to_local(cell) + (0, −8 px)`. Platzhalter =
12×18-Box (hochkant). **Empfohlene Realgröße:** klein, ~16–24 px hoch, mit klarer
Silhouette (werden zu vielen gleichzeitig gezeigt — bis 200 im Perf-Test).

| Asset-ID | Anzeigename | Rolle | Werte (HP/Atk/Def/Spd) | Kosten | Platzhalterfarbe |
|---|---|---|---|---|---|
| `unit_villager` | Dorfbewohner | Zivilist / Arbeiter (generisch) | — | — | `#4a6d8c` |
| `unit_swordsman` | Schwertkämpfer | Spieler-Militär | 30 / 6 / 3 / 1 | 5 Holz, 5 Brot | `#3f6bab` |
| `unit_raider` | Plünderer | **Gegner** | 24 / 5 / 2 / 1 | — | `#a03c3c` |

- `unit_villager` wird u. a. für den 200-Einheiten-Performance-Test (Taste **F3**)
  genutzt (`world_view.gd:147`) und als generische Bevölkerung.
- **Gegner-Einfärbung:** feindliche Einheiten nutzen dasselbe Asset, rötlich getönt
  (`ENEMY_TINT`). Ein `unit_raider` ist zwar gegnerspezifisch, wird aber zusätzlich
  getönt — Grafik daher in neutraler Grundfarbe halten.
- **Blickrichtung/Animation:** aktuell statische Sprites ohne Richtungsvarianten.
  Für spätere Meilensteine optional: Geh-/Kampf-Frames, Blickrichtungen.

---

## 6 Ressourcen-Icons (in `data/resources.json` deklariert)

Jede Ressource hat ein `icon`-Feld nach der Konvention **`resource_<id>`**. **Noch
nicht gerendert:** die HUD zeigt Ressourcen aktuell als **Text** (`Name: Menge`,
`hud.gd:95`). Das AssetRegistry erzeugt für `resource_*` bereits Platzhalter
(24×24-Box). Empfohlene Realgröße: kleine quadratische Icons, z. B. **16×16 /
24×24 / 32×32 px**.

| Asset-ID | Ressource | Platzhalterfarbe | Kontext |
|---|---|---|---|
| `resource_wood` | Holz | `#7a5230` | Basisrohstoff, fast alle Baukosten |
| `resource_wheat` | Weizen | `#d9b13b` | Zwischenprodukt (→ Brot, Bier) |
| `resource_bread` | Brot | `#c98a4b` | Nahrung / Zufriedenheit, Rekrutenkosten |
| `resource_stone` | Stein | `#8d8d8d` | Verteidigungsbauten |
| `resource_beer` | Bier | `#b9822f` | Luxus / Zufriedenheit |

---

## 7 NPC-Porträts (Dialoge)

In `data/dialogues/*.json` deklariert über `npc.icon`. **Noch nicht gerendert:**
die Dialog-Box zeigt nur den Sprechernamen als Text (`hud.gd:57`). Für spätere
Porträt-Darstellung vorbereiten. Empfohlene Größe: Porträt, z. B. **64×64 /
96×96 px**, evtl. mehrere Stimmungen.

Konvention **`npc_<id>`**. Das AssetRegistry erzeugt für `npc_*` bereits
Platzhalter (64×64-Box).

| Asset-ID | NPC | Archetyp | Charakter | Platzhalterfarbe |
|---|---|---|---|---|
| `npc_baumeister` | Baumeister Balduin | „nörgelnder Baumeister" | dritte Generation, mürrisch, trockener Humor | `#9a7b52` |

---

## 8 Landschafts-Assets (Ausblick / Vorschlag)

> **Status:** Diese Objekte sind **noch nicht im Code referenziert** — sie sind ein
> Katalog für den Landschafts-/Content-Ausbau. Statische Deko passt in die bestehende
> `feature_*`-Mechanik (lädt ohne Codeänderung, muss aber vom Kartengenerator
> **platziert** werden → `biomes.json` `features` + `world_map.gd` erweitern).
> Gewässer, Flüsse, große Berge und bewegte Tiere brauchen zusätzlich neue
> Render-/Generierungslogik (je Kategorie vermerkt).

**Varianten-Konvention:** Basis-ID + Suffix, z. B. `feature_tree_pine`,
`feature_rock_boulder`. Der Kartengenerator wählt pro Vorkommen zufällig eine
Variante → natürlich wirkende Streuung statt sichtbarer Wiederholung. Empfohlen:
**3–5 Varianten** je Grundtyp (Form, Größe, leichte Farbabweichung).

### 8.1 Vegetation / Pflanzen (`feature_*`) — ✅ umgesetzt

Statische Overlays auf einer Kachel (Fuß auf Kachelmitte, Transparenz außen, Höhe
darf über 32 px ragen). Wichtig: Dekor ist ein **eigener Kanal**, getrennt von den
Gameplay-Merkmalen (`tree`/`rock`).

**Architektur:** Dekor läuft **nicht** über den Merkmals-Slot (der ist ein Merkmal
pro Zelle und blockiert Bau). Stattdessen:
- `biomes.json` hat je Biom ein zweites Dichten-Dict **`decor`** (neben `features`).
- `WorldMap` würfelt es in einem **eigenen RNG-Kanal** (`_roll_decor`, Salt `"decor:"`)
  — nur auf **merkmalfreien** Zellen, damit es Baum/Fels nicht verdrängt; die
  Merkmals-Rolls (und deren Tests) bleiben bit-identisch. `get_decor(cell)`.
- Dekor **blockiert nichts** (Bau/Bewegung/Bauplätze prüfen nur `get_feature`).
- `world_view` rendert es auf eigener `_decor`-Layer (über Boden, unter Merkmalen).
- Test: `test_world_map._test_decor` (nie auf Merkmalszellen, im Katalog gedeckt,
  vorhanden, deterministisch).

| Asset-ID | Objekt | Größe | Biome (Dichte) | Status |
|---|---|---|---|---|
| `feature_flowers` | Blumen | ≤ 16 px | Tal 0.14, Grasland 0.10 | ✅ platziert |
| `feature_grass_tuft` | Grasbüschel | ≤ 16 px | Tal 0.22, Grasland 0.20, Hügel 0.14, Felsland 0.05 | ✅ platziert |
| `feature_bush` | Busch/Strauch | ≤ 32 px | Tal 0.05, Grasland 0.04, Hügel 0.05 | ✅ platziert |
| `feature_fern` | Farn | ≤ 24 px | Tal 0.04, Hügel 0.03 | ✅ platziert |
| `feature_mushroom` | Pilze | ≤ 12 px | Grasland 0.02 | ✅ platziert |
| `feature_reeds` | Schilf | ≤ 32 px | Sumpf 0.22 | ✅ platziert |
| `feature_deadwood` | Totholz/Äste | ≤ 24 px | Sumpf 0.06, Hügel 0.03, Felsland 0.05 | ✅ platziert |

**Noch offen:** echte Pixelart + Varianten (`feature_flowers_red`, `feature_bush_berry`
… → gewichtete Auswahl je Basistyp im Spawner); zusätzliche Baum-Varianten
(`feature_tree_oak/pine/…`, ersetzen `feature_tree`, gameplay-relevant); `feature_stump`
(gehört an die Holzfäller-Abholzung, nicht ins Biom-Dekor — eigener Schritt). Schnee
bleibt kahl (kein `decor`).

### 8.2 Gestein & Berge — ✅ teils umgesetzt (Bergwelt)

**Varianten-Mechanik (neu):** Ein Gameplay-Merkmal kann in mehreren **visuellen
Varianten** erscheinen, ohne seine Spielbedeutung zu verlieren. `data/feature_variants.json`
bildet Merkmal → `[Varianten]` ab; `FeatureVariants.pick` (`scripts/model/feature_variants.gd`,
pur/testbar — `test_feature_variants`) wählt deterministisch (Seed + Zelle) eine
Variante fürs Rendering. **`get_feature` bleibt `rock`** → Steinbruch/`has_feature_near`
und alle Placement-Tests unverändert. Merkmale ohne Tabelleneintrag (z. B. `tree`)
rendern unverändert.

**✅ Gestein-Varianten** (gerendert für Fels-Merkmalzellen in Hügel/Felsland):

| Asset-ID | Objekt | Platzhalterfarbe |
|---|---|---|
| `feature_rock_small` | kleiner Stein | `#837d73` |
| `feature_rock_boulder` | Findling | `#6b665d` |
| `feature_rock_cluster` | Felsgruppe | `#7a746a` |
| `feature_rock_mossy` | bemooster Fels | `#6a7358` |

**✅ Gebirgs- & Schnee-Dekor** (über den Dekor-Kanal §8.1, blockiert nichts):

| Asset-ID | Objekt | Biome (Dichte) |
|---|---|---|
| `feature_pebbles` | Geröll/Kies | Hügel 0.05, Felsland 0.08 |
| `feature_cliff` | Felskante/Abbruch | Felsland 0.05 |
| `feature_crystal` | Kristall/Erz-Ader | Felsland 0.03 |
| `feature_snow_drift` | Schneeverwehung | Schnee 0.16 |
| `feature_ice` | Eisfläche | Schnee 0.06 |

**✅ Große Bergkulissen** (`feature_mountain_large` → Varianten `feature_mountain_rocky`,
`feature_mountain_snowy`): mehrkachelige **Sprites** (128×96 px, kein Kachel-Layer),
nicht die Feature-/Dekor-Mechanik. Platzierung: pures Modell `MountainScenery.backdrops`
(`scripts/model/mountain_scenery.gd`, Test `test_mountain_scenery`) streut sie
deterministisch aus dem Seed sparsam in die Hochlagen-Biome (Feld **`mountains`** je
Biom: Felsland → rocky/snowy, Schnee → snowy) mit **Mindestabstand** (Chebyshev 3,
Dichte 0.25). Render in `world_view` auf eigenem **`_mountain_root` mit `y_sort_enabled`**
(hinter der Siedlung): Node-Position = Zellbasis, Sprite-`offset` hebt die Grafik nach
oben → korrekte gegenseitige Tiefenverdeckung. Blockiert nichts.

| Asset-ID | Objekt | Biome | Platzhalterfarbe |
|---|---|---|---|
| `feature_mountain_rocky` | Felsberg | Felsland | `#6f6a61` |
| `feature_mountain_snowy` | Schneegipfel | Felsland, Schnee | `#8a857c` + weiße Kappe |

**⏸ Noch offen:**
- Echte Pixelart + evtl. gewichtete/weitere Varianten (`feature_tree`-Varianten
  ließen sich **ohne Codeänderung** über `feature_variants.json` einhängen; weitere
  Bergsilhouetten nur über `biomes.json`/Farben).
- **Voll-Szenen-Y-Sort:** Kulissen sind ein Backdrop **hinter** der Siedlung (untereinander
  Y-sortiert). Objekte einzelner Kacheln davor/dahinter global korrekt zu sortieren
  wäre ein größerer Umbau der festen Layer-Reihenfolge — bewusst nicht gemacht.
- `tile_mountain`/`tile_peak_snow` als eigenes Biom **zurückgestellt**: das obere
  Noise-Band ist zu schmal (nur ~24 Zellen über allen Hochlagen bei 48²), ein neues
  Band käme unzuverlässig vor → stattdessen Felsland/Schnee mit Varianten, Dekor und
  Kulissen angereichert.

### 8.3 Gewässer — Seen & Flüsse — ✅ Seen umgesetzt

**Architektur:** Wasser ist **Terrain** → als **Biom** ins Höhen-Noise-Modell
eingehängt. `water` ist das **unterste Band** (`noise_max −0.53`, ~17 Zellen bei 48²)
→ die tiefsten Senken werden Seen, ringsum Sumpf. `passable:false` → unbegehbar
(Kampf-Pathfinding); kein Gebäude listet `water` → unbebaubar. `building_slots`/
`nearest_free_cell` prüfen bereits `is_walkable` → **keine Änderung** an diesen
Systemen (wie beim Sumpf).

**Flach vs. tief (ohne Autotiling):** `WorldMap.is_water_shore` erkennt Wasserzellen
mit Land-Nachbar (inkl. Kartenrand); `world_view` rendert sie als `tile_water_shallow`,
inneres Wasser als `tile_water_deep`. Das gibt einen hellen Ufersaum ohne 8-Richtungs-
Autotiles. Seerosen/Schilf über den Dekor-Kanal (`lilypad` 0.14, `reeds` 0.10 auf Wasser).

| Asset-ID | Objekt | Status |
|---|---|---|
| `tile_water_deep` | Tiefwasser (See-Inneres) | ✅ gerendert (`#2f6b8f`) |
| `tile_water_shallow` | Flachwasser/Ufer | ✅ gerendert (`#4f97b8`, Ufer-Erkennung) |
| `feature_lilypad` | Seerose | ✅ Dekor auf Wasser (`#5c9a4a`) |
| `feature_reeds` | Schilf | ✅ Dekor auf Wasser (bereits vorhanden) |

**⏸ Noch offen (Flüsse & Polish):**
- `tile_water_edge_*` — echte **Iso-Ufer-Autotiles** (weiche Kante statt Rauten-Stufe);
  Godot-`TileSet`-Terrain/Bitmask, größerer Schritt.
- `tile_river_*` — **Flussläufe**: richtungsabhängiges Kachelset + Generator, der einen
  Lauf von Höhenlage zum See legt (Pfad/Bitmask). Der teuerste Teil.
- `feature_waterfall` (an Höhenkante), `feature_bridge_*` (Flussquerung, evtl. baubar
  → eher `building_*`), `feature_rock_wet` (Ufersaum-Deko).
- Schaltet zusätzlich frei: `tile_sand` (Strand am Ufer, §8.4) und `animal_fish` (§8.5).

### 8.4 Gelände- & Bodenvarianten — Täler, Sumpf, Wege (`tile_*`)

Status je Kachel. **Umgesetzt** wurde alles, was in das bestehende Höhen-Noise-Modell
bzw. eine saubere Gebäude-Kopplung passt; die kontextabhängigen Kacheln sind bewusst
**zurückgestellt**, weil sie ein noch fehlendes System bräuchten (sie als Zufallsband
einzubauen wäre falsch).

| Asset-ID | Objekt | Status | Anmerkung |
|---|---|---|---|
| `tile_swamp` | Sumpf/Moor | ✅ **Biom umgesetzt** (§2) | Höhenband −0.45, unpassierbar; nur Grafik+Varianten offen |
| `tile_valley` | Talgrund (fruchtbar) | ✅ **Biom umgesetzt** (§2) | Höhenband −0.20, bebaubar wie Grasland; nur Grafik+Varianten offen |
| `tile_snow` | Schneegipfel | ✅ **Biom umgesetzt** (§2) | oberstes Band 0.5–1.0, kahl/unbebaubar; nur Grafik+Varianten offen |
| `tile_farmland` | Ackerboden (bestellt) | ✅ **umgesetzt** (§2) | Nicht-Biom-Kachel, wird unter Weizenfeldern gemalt; nur Grafik offen |
| `tile_sand` | Sand/Strand | ⏸ zurückgestellt | Übergang Wasser↔Land — **braucht zuerst Gewässer (§8.3)**; ohne Wasser sinnlos |
| `tile_path_*` | Trampelpfad/Weg | ⏸ zurückgestellt | verbindet Gebäude — braucht Wege-/Konnektivitätssystem + Autotiling (kein Zufallsband) |
| `tile_dirt` | Erde/kahler Boden | ⏸ zurückgestellt | überschneidet sich mit Acker/Weg; sinnvoll erst als „gerodete Fläche" mit Weg-System |

*Grafik + Varianten* aller ✅-Kacheln stehen noch aus (aktuell farbige Platzhalter);
mehrere Varianten pro Biom bräuchten zusätzlich eine Registry-Erweiterung (§2, §8).

### 8.5 Tiere — Wildtiere & Nutztiere (neuer Präfix `animal_*`)

Tiere sind **keine Kampfeinheiten** → eigener Präfix `animal_<typ>` (nicht `unit_`).

**✅ Umgesetzt (Wildtiere):** Katalog `data/animals.json` (Habitat je Biom), von
`Database.animals` geladen; `AssetRegistry` hat den `animal_`-Zweig (16×12-Box) mit
Platzhalterfarben. `AmbientLife.spawn_points` (`scripts/model/ambient_life.gd`)
verteilt sie **deterministisch aus dem Karten-Seed** in ihr Habitat (rein, testbar —
`tests/test_ambient_life.gd`); `world_view` rendert sie auf eigenem Root
(unter den Gebäuden), Dichte ~2 % der Zellen (max. 80).

**✅ Umgesetzt (Wanderung):** Wildtiere wandern gemächlich (`_move_ambient`,
8 px/s) um ihre Startzelle und werden am Radius (24 px) sanft zurückgelenkt —
Muster wie der F3-Perf-Mover, rein kosmetisch.

**✅ Umgesetzt (Nutztiere):** `AmbientLife.livestock_points` platziert `livestock`-
Tiere deterministisch auf **Nachbarzellen ihres `near_building`** (gebäudegekoppelt
wie Acker, neu gezeichnet bei `buildings_changed`, eigener Root **über** den Gebäuden).
Nutztiere bleiben ortsfest (grasen am Hof, keine Wanderung).

**⏸ Noch offen:** echte Pixelart je Tier + Varianten; **`animal_fish`** (braucht
Wasser, §8.3); weitere Nutztiere (Schwein/Ziege/Pferd/Ochse) noch nicht im Katalog.

**Wildtiere (Ambient, naturbelebend):**

| Asset-ID | Tier | Status | Größe | Habitat (Biome) |
|---|---|---|---|---|
| `animal_deer` | Reh | ✅ platziert | ≤ 24 px | Tal, Grasland, Hügel |
| `animal_rabbit` | Hase | ✅ platziert | ≤ 12 px | Tal, Grasland |
| `animal_fox` | Fuchs | ✅ platziert | ≤ 16 px | Grasland, Hügel |
| `animal_boar` | Wildschwein | ✅ platziert | ≤ 20 px | Hügel, Felsland |
| `animal_bird` | Vogel | ✅ platziert | ≤ 12 px | Tal, Grasland, Hügel, Felsland |
| `animal_frog` | Frosch | ✅ platziert | ≤ 10 px | Sumpf |
| `animal_butterfly` | Schmetterling | ✅ platziert | ≤ 8 px | Tal, Grasland |
| `animal_fish` | Fisch | ⏸ (braucht Wasser) | ≤ 12 px | Gewässer (§8.3) |

Varianten (z. B. `animal_deer_stag`, `animal_bird_crow`) später; würden eine
gewichtete Auswahl im Spawner brauchen.

**Nutztiere (bei Gebäuden/Höfen) — ✅ platziert (gebäudegekoppelt):**

Im Katalog als `category: "livestock"` mit `near_building` deklariert; stehen auf
Nachbarzellen des passenden Gebäudes.

| Asset-ID | Tier | `near_building` | Größe |
|---|---|---|---|
| `animal_cow` | Kuh | `wheat_farm` | ≤ 24 px |
| `animal_sheep` | Schaf | `house` | ≤ 18 px |
| `animal_chicken` | Huhn | `house` | ≤ 12 px |
| `animal_pig` / `_goat` / `_horse` / `_ox` | weitere | (noch nicht im Katalog) | ≤ 28 px |

### 8.6 Atmosphäre / Kleindeko (`feature_*`) — ✅ teils umgesetzt

§8.6 verteilt sich über die vorhandenen Mechanismen: **Ruinen** über den Dekor-Kanal
(§8.1, reine Daten), **gebäudenahe Requisiten** über eine Gebäude-Kopplung wie bei
Nutztieren, **Wegweiser/Lagerfeuer** zurückgestellt (fehlender Unterbau).

**✅ Ruinen (Dekor-Kanal):** `feature_ruins` als seltenes `decor` (Tal 0.008,
Grasland/Hügel 0.006) — narrativ (versunkene Burgen); blockiert nichts.

**✅ Gebäude-Requisiten:** Gebäude tragen in `buildings.json` ein Feld **`props`**;
`SettlementProps.props_for` (`scripts/model/settlement_props.gd`, pur/testbar —
`test_settlement_props`) setzt sie deterministisch auf Nachbarzellen, `world_view`
rendert sie auf eigenem `_props_root`.

| Asset-ID | Objekt | Gebäude (`props`) | Status |
|---|---|---|---|
| `feature_well` | Brunnen | `keep` | ✅ platziert |
| `feature_haystack` | Heuhaufen | `wheat_farm` | ✅ platziert |
| `feature_fence` | Zaun/Gatter | `house` | ✅ platziert (einzelnes Stück; Richtungs-/Umrandungs-Varianten später) |
| `feature_ruins` | Ruine/altes Gemäuer | — (Dekor) | ✅ platziert |
| `feature_signpost` | Wegweiser | — | ⏸ braucht Wege-System (§8.4) |
| `feature_campfire` | Lagerfeuer | — | ⏸ gehört ans Gegner-Lager (Kampf-Rendering, eigener Schritt) |

> **Konsistenz-Regel für alle Landschafts-Assets:** neutrale Grundfarben (Gegner-
> Tönung möglich), Fuß auf Kachelmitte verankert, Transparenz drumherum, Pixelart-Stil
> und naturfarbene Palette wie in §1. Für Winter-/Jahreszeit-Stimmung optional je
> Objekt eine `_snow`-Variante.

---

## 9 Zusammenfassung / Checkliste

**Sofort spielrelevant (werden bereits als Sprites gezeichnet):**

- [ ] `tile_swamp`, `tile_valley`, `tile_grassland`, `tile_hills`, `tile_highlands`,
      `tile_snow` — 64×32 Iso-Rauten (Höhengradient, alle als Biom aktiv)
- [ ] `tile_farmland` — 64×32, unter Weizenfeldern
- [ ] `feature_tree`, `feature_rock` — Overlay auf 64×32
- [ ] `building_keep`, `building_woodcutter`, `building_wheat_farm`, `building_bakery`,
      `building_house`, `building_quarry`, `building_brewery`, `building_wall`,
      `building_tower`, `building_gate` — Grundfläche ~64px breit
- [ ] `unit_villager`, `unit_swordsman`, `unit_raider` — klein, ~16–24px hoch

**Deklariert, aber noch nicht gerendert (für spätere Meilensteine):**

- [ ] Ressourcen-Icons: `resource_wood`, `resource_wheat`, `resource_bread`,
      `resource_stone`, `resource_beer`
- [ ] NPC-Porträt: `npc_baumeister`

**Landschaft (Ausblick, §8 — noch nicht im Code referenziert):**

- [ ] Vegetation **platziert** (§8.1, eigener Dekor-Kanal): `feature_flowers`,
      `feature_grass_tuft`, `feature_bush`, `feature_fern`, `feature_mushroom`,
      `feature_reeds`, `feature_deadwood` — nur Grafik offen; `feature_tree_*`-Varianten
      + `feature_stump` (Abholzung) noch offen
- [ ] Gestein/Berge **platziert** (§8.2): `feature_rock_small/boulder/cluster/mossy`
      (Varianten-Mechanik), `feature_pebbles/cliff/crystal` (Gebirgs-Dekor),
      `feature_snow_drift/ice` (Schnee), `feature_mountain_rocky/snowy` (große Kulissen,
      Y-sortiert) — nur Grafik offen; `tile_mountain`-Biom zurückgestellt
- [ ] Gewässer **Seen platziert** (§8.3): `tile_water_deep/shallow` (Ufer-Erkennung),
      `feature_lilypad`/`feature_reeds` (Wasser-Dekor) — nur Grafik offen;
      `tile_water_edge_*` (Autotiling), `tile_river_*`, `feature_waterfall/bridge` zurückgestellt
- [ ] Boden/Täler: `tile_sand`, `tile_dirt`, `tile_path_*` — zurückgestellt (§8.4),
      brauchen Wasser- bzw. Wege-System *(`tile_swamp`, `tile_valley`, `tile_snow`,
      `tile_farmland` als Biom/Kachel bereits umgesetzt — nur noch Grafik offen)*
- [ ] Tiere: Wildtiere `animal_deer/rabbit/fox/boar/bird/frog/butterfly` **platziert +
      wandernd**, Nutztiere `animal_cow/sheep/chicken` **an Gebäuden platziert** (nur
      Grafik offen); `animal_fish` (braucht Wasser) + weitere Nutztiere zurückgestellt
- [ ] Kleindeko **platziert** (§8.6): `feature_well`, `feature_haystack`,
      `feature_fence` (an Gebäuden) + `feature_ruins` (Dekor) — nur Grafik offen;
      `feature_signpost` (Wege) + `feature_campfire` (Gegner-Lager) zurückgestellt

**Gesamt: 17 direkt genutzte + 6 vorbereitende + Landschafts-Katalog (§8).**

### Offene Punkte vor der Erstellung
1. **Kachel-Varianten:** Registry lädt derzeit 1 Grafik pro Biom/Merkmal — für
   mehrere Varianten müsste `asset_registry.gd` erweitert werden.
2. **Gegner-Assets:** werden per Rot-Tönung aus Spieler-Assets erzeugt — Grundgrafik
   neutral halten; separate Gegnervarianten nur bei Bedarf.
3. **Landschaft-Platzierung:** neue `feature_*`-Deko braucht Einträge in `biomes.json`
   (`features`) und Streuung im Kartengenerator (`world_map.gd`).
4. **Neue Terrain-/System-Assets:** Gewässer & Flüsse (Autotiling), große Berge
   (mehrkachelige Sprites + Z-Order) und bewegte Tiere (`animal_*`-Zweig + Wander-
   System) erfordern jeweils neue Code-Logik — nicht rein assetseitig.

### Erledigt
- ✅ **§8.3 Gewässer – Seen (komplett bis auf Grafik/Flüsse):** `water` als unterstes
  Biom-Band (`noise_max −0.53`, `passable:false`) in `biomes.json` — die tiefsten Senken
  werden Seen, unbegehbar & unbebaubar ohne Änderung an `building_slots`/Pathfinding.
  `WorldMap.is_water_shore` unterscheidet Flach-/Tiefwasser (Ufer-Erkennung), `world_view`
  rendert `tile_water_shallow`/`_deep`; Seerosen/Schilf über den Dekor-Kanal. Farben im
  `AssetRegistry`, Tests in `test_world_map` (Vorkommen, Unbegehbarkeit, Ufer-Konsistenz).
  Flüsse/Ufer-Autotiles/Wasserfall/Brücke zurückgestellt. Alle Tests grün + Headless fehlerfrei.
- ✅ **§8.2 Bergwelt (Gestein/Schnee, komplett bis auf Grafik):** neue **Varianten-
  Mechanik** — `data/feature_variants.json` + pures Modell `FeatureVariants.pick`
  (deterministisch aus Seed+Zelle, Test `test_feature_variants`); `world_view` rendert
  Fels-Merkmale als eine von 4 Gestein-Varianten, **`get_feature` bleibt `rock`**
  (Gameplay/Tests unberührt). Gebirgs- & Schnee-Dekor über den Dekor-Kanal
  (`pebbles/cliff/crystal` in Hügel/Felsland, `snow_drift/ice` im Schnee). **Große
  Bergkulissen** (`feature_mountain_rocky/snowy`): mehrkachelige Sprites (128×96),
  pures Modell `MountainScenery.backdrops` (deterministisch, Mindestabstand, Test
  `test_mountain_scenery`), gerendert auf `_mountain_root` mit **`y_sort_enabled`**
  hinter der Siedlung. Nur `tile_mountain`-Biom (Noise-Band zu schmal) zurückgestellt.
  Alle Tests grün + Headless fehlerfrei.
- ✅ **§8.6 Kleindeko:** `feature_ruins` als seltenes Streu-Dekor über den
  Dekor-Kanal (reine Daten). Gebäude-Requisiten über neues `props`-Feld in
  `buildings.json` + pures Modell `SettlementProps.props_for` (Test
  `test_settlement_props`) + eigener `_props_root` in `world_view`: Brunnen (keep),
  Heuhaufen (wheat_farm), Zaun (house) auf Nachbarzellen. `feature_signpost` (Wege)
  und `feature_campfire` (Gegner-Lager) zurückgestellt. Alle Tests grün + Headless
  fehlerfrei.
- ✅ **§8.1 Vegetation (komplett bis auf Grafik):** eigener **Dekor-Kanal** getrennt
  von den Gameplay-Merkmalen — `decor`-Dichten je Biom in `biomes.json`, eigener
  RNG-Kanal `WorldMap._roll_decor`/`get_decor` (nur auf merkmalfreien Zellen, Feature-
  Rolls bit-identisch), eigene `_decor`-Layer in `world_view` (über Boden, unter
  Merkmalen), Platzhalterfarben im `AssetRegistry`, Test `test_world_map._test_decor`.
  7 Deko-Typen (Blumen, Gras, Busch, Farn, Pilz, Schilf, Totholz); blockiert nichts.
  Alle Tests grün + Headless-Lauf fehlerfrei.
- ✅ **§8.5 Tiere (komplett bis auf Grafik):** Katalog `data/animals.json` +
  `Database.animals`/`get_animal_def`; `animal_`-Zweig im `AssetRegistry` (16×12-Box,
  10 Platzhalterfarben). Pures Modell `AmbientLife` mit Test `test_ambient_life`:
  `spawn_points` (Wildtiere deterministisch ins Habitat aus dem Seed) und
  `livestock_points` (Nutztiere auf Nachbarzellen ihres `near_building`). `world_view`
  rendert Wildtiere auf eigenem Root (~2 % Zellen, max. 80) mit **gemächlicher
  Wanderung** (`_move_ambient`) um die Startzelle; Nutztiere ortsfest auf eigenem Root
  über den Gebäuden, neu gezeichnet bei `buildings_changed`. Offen: Pixelart,
  `animal_fish` (braucht Wasser), weitere Nutztiere. Alle Tests grün + Headless-Lauf
  (mit aktiver Wanderung) fehlerfrei.
- ✅ **§8.4 Bodenvarianten:** Höhengradient-Biome `tile_valley` (`#6aa048`,
  `noise_max −0.20`, bebaubar wie Grasland — `valley` in alle Grasland-`placement`-
  Listen ergänzt) und `tile_snow` (`#e2e8ea`, oberstes Band 0.5–1.0, kahl/unbebaubar;
  `highlands` dafür auf `noise_max 0.5` verkürzt) in `biomes.json`. Plus
  `tile_farmland` (`#b98c4a`) als Nicht-Biom-Kachel, die `world_view` unter
  Weizenfeldern malt und beim Abriss zurücksetzt (`_farmland_cells`); `_PLACEHOLDER_
  COLORS`-Override im `tile_`-Zweig. Rein datengetrieben bis auf die Farmland-Kopplung.
  Alle Tests grün + Headless-Spielstart fehlerfrei. `tile_sand`/`tile_dirt`/`tile_path_*`
  bewusst zurückgestellt (benötigen Wasser- bzw. Wege-System).
- ✅ **Sumpf-Biom** `tile_swamp` in `biomes.json` ergänzt (Farbe `#5f6b47`,
  `noise_max −0.45`, ~3 % Fläche, unbebaubar & unpassierbar). Rein datengetrieben —
  Generator (`world_map.gd`) und Renderer unverändert. `test_world_map`
  bestätigt: Biom kommt vor.
- ✅ `building_wall` (`#77787c`) / `building_tower` (`#4c4f57`) Platzhalterfarben in
  `_PLACEHOLDER_COLORS` ergänzt.
- ✅ Präfix-Konvention `resource_<id>` / `npc_<id>` im AssetRegistry umgesetzt
  (eigene Platzhalterformen 24×24 bzw. 64×64) und `resources.json`-`icon`-Felder
  angepasst (`npc_baumeister` folgte bereits der Konvention).
