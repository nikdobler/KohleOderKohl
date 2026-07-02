/goal

## 0 Rolle & technischer Kontext

Du bist ein erfahrener Spieleentwickler mit Fokus auf Godot 4.x und GDScript.
- Zielplattform: macOS (Apple Silicon) und Windows, nativer Export, läuft vollständig lokal, offline.
- Projektstruktur beibehalten: `/scenes`, `/scripts`, `/assets`, `/ui`, `/data`, `/tests`.
- Sprache im Code: englische Bezeichner, deutsche Kommentare erlaubt.
- Du arbeitest inkrementell: kleine, testbare Commits. Kein „grosser Wurf".
- Wenn eine Anforderung unklar oder zu gross ist: nachfragen, bevor du Code schreibst.
- **Jede Session bearbeitet genau einen Meilenstein aus Abschnitt 9. Kein Vorgriff auf spätere Meilensteine, auch wenn die Versuchung besteht.**

## 1 Kern-Gameplay

Aufbau-Strategiespiel mit Simulation von Wirtschaft, Städte- und Festungsbau und Entdeckungs- bzw. Militärkampagne.
Der Spieler muss Ressourcen sammeln, um damit seine Siedlung und Festung zu verbessern.
Ressourcen werden durch Arbeiter gewonnen. Arbeiter brauchen Wohnraum und müssen bei Laune gehalten oder anderweitig kontrolliert werden.
Neue Ressourcen (z. B. Weizen–Brot–Bier) und Technologien (z. B. Bogen–Armbrust–Kanone) werden in Abhängigkeit von Forschung und Entwicklung freigeschaltet.
Für Forschung und Entwicklung (FE) müssen Ressourcen verwendet werden.
FE führt zu verbesserten Arbeitern, zusätzlichen Ressourcen, neuen Technologien, moderneren Waffen/Kriegertypen usw.
Eroberung führt ebenfalls zu FE-Erkenntnissen, wenn ein Gegner erobert wird, der diese schon hat.
Je weiter fortgeschritten die FE des Gegners, desto schwieriger zu besiegen.
Zeitspanne: Bronzezeit bis Renaissance. Europäisches Setting, aber keine realen Länder.
Expansive Map mit verschiedenen Landschaften (Wälder, Seen, Flüsse, Gebirge, Wüsten) und entsprechenden Ressourcen und Gegnern.

**Spielmodi**

Freies Spiel:
- Spieler kann frei spielen, ohne dass Missionen oder Gegner stören.
- Spieler kann im freien Modus entscheiden, wann er einen Gegner angreift oder angegriffen wird.
- Ressourcen sind von Beginn an zugänglich, sofern man die dafür notwendigen Grundlagen (Gebäude zur Erstellung) hat.

Kampagne:
- Die Kampagne ist die Hauptstory des Spiels. Verschiedene Charaktere führen durch die Geschichte des Spiels.
- Der Auftritt der Charaktere richtet sich nach Spielverlauf und Fortschritt.
- Innerhalb der Kampagne gibt es Quests und Side-Quests, die der Spieler bewältigen muss, um Fortschritte zu erzielen.

## 2 Technische Anforderungen

- Kartenmodell: Expansiv
- Kamera: Zoom & Karten-Scroll
- Speichersystem: JSON-basiert, versioniert (`save_version`), Vorwärtskompatibilität bedenken.
- Performance-Ziel: flüssig bei 200 aktiven Einheiten auf einem M-Chip.
- Architektur: modulare Nodes/Autoloads, keine Gott-Klasse; Spiellogik von Rendering getrennt, damit sie ohne UI testbar ist.
- Datengetrieben: Gebäude, Einheiten, Kosten in `/data/*.json`, nicht hartcodiert im Skript.

## 3 Grafik & Art Direction

- Stil: stilisiert 2D-isometrisch, liebevoll verspieltes Design, reich an Details, Pixelart, Mittelalter-Referenzen — kein Fotorealismus.
- Asset-Datenbank: schrittweise aufgebaut, orientiert am jeweiligen Meilenstein (siehe Abschnitt 9), keine Vorab-Vollbestückung.
- Farbpalette/Stimmung: naturfarben, freundliche Stimmung.
- Anforderung an den Code: Assets über ein zentrales Register laden, damit sie austauschbar sind.

## 4 Charaktere, Dialoge & Humor

- Charakter-Archetypen: geiziger Steuervogt, grosssprecherischer Ritter, nörgelnder Baumeister, schlauer Bauer, müffelnder Fischer, dicker Metzger, betrunkener Mönch, bekiffter Hanfbauer, versnobte Adlige, romantische Barden, archetypische Bösewichte usw.
- Dialog-System: datengetrieben in `/data/dialogues/*.json`, Bedingungen (Trigger) trennbar vom Text. Teilweise mit verschiedenen Antwortoptionen.
- Tonvorgabe für Dialoge: trocken-witzig, überzeichnet, aber nie albern. Anspielungen auf berühmte historische Figuren, Filmzitate (z. B. Monty Python – Die Ritter der Kokosnuss, Robin Hood – Helden in Strumpfhosen, Louis de Funès; vor allem Filme aus den 90ern/00ern), Ereignisse und Fussball allgemein.
- Lokalisierung: deutschsprachig (Schweizer Konvention: „ss" statt „ß", Umlaute), Struktur für spätere Sprachen offen halten.

## 5 Szenarien / Level

- Szenario-Format: je Szenario eine `/data/scenarios/*.json` mit Startbedingungen, Zielen, Events.
- Wechselnde Szenarien: „Ernteausfall", „Belagerung", „Handelsembargo", „Feuer", „Erdbeben", „Krieg", „Handelsgesandter", „Zuchterfolg" — als Event-Regeln, nicht als Sondercode.

## 6 Code- & Qualitätsanforderungen

- Kurze, benannte Funktionen; keine Blöcke > ~40 Zeilen.
- Öffentliche Schnittstellen kommentiert; nicht offensichtliche Logik erklärt.
- Kern-Spiellogik mit Unit-Tests absichern (Godot GUT oder eigene Test-Scene).
- Kein toter Code, keine auskommentierten Reste im Commit.

## 7 Erwartetes Output-Format

- Kurzer Plan (Dateien, die entstehen/geändert werden).
- Dateien oder gezielte Diffs.
- Erklärung, wie ich das Ergebnis in Godot starte und teste.
- Offene Punkte/Annahmen explizit auflisten.

## 8 Admin (einmalig, nicht Teil des laufenden Session-Prompts)

- GitHub-Projekt eröffnen.
- Verwaltung und Pflege der Datenstruktur im Projektordner und auf GitHub.
- Wird separat behandelt, nicht bei jedem `/goal`-Aufruf neu angestossen.

## 9 Meilensteine (MVP-Pfad — jede Session bearbeitet genau einen)

**M0 — Projekt-Setup**
Godot-Projekt, Ordnerstruktur gemäss Abschnitt 0, leere Autoloads, Grundgerüst Speichersystem (JSON, `save_version`), keine Spiellogik.

**M1 — Ein Arbeiter, eine Ressource, ein Gebäude**
Kleinstmöglicher spielbarer Loop: ein Gebäudetyp erzeugt eine Ressource durch einen Arbeiter, UI zeigt Bestand. Ziel: in unter 10 Minuten spielbar und testbar.

**M2 — Wirtschafts-Basis**
Mehrere Ressourcen, einfache Gebäude-Kette (z. B. Weizen → Brot), Wohnraum-Mechanik, Arbeiterzufriedenheit als einfacher Wert.

**M3 — Forschungssystem**
Tech-Tree-Grundgerüst (datengetrieben, `/data/tech.json`), Freischaltung von mind. zwei weiteren Ressourcen/Gebäuden über FE.

**M4 — Karte & Kamera**
Zoom/Scroll, mind. zwei Biome mit unterschiedlicher Ressourcenverteilung, Kartennavigation performant bis 200 Einheiten.

**⚠ Klärungspunkt vor M5:** Kampfsystem ist aktuell nicht spezifiziert (rundenbasiert oder Echtzeit? Einheitentypen? Schaden-/Verteidigungsformel? Wie genau löst „Eroberung führt zu FE" konkret aus?). Das muss vor Start von M5 in einem eigenen Klärungsgespräch festgelegt werden — nicht während der Session erraten.

**M5 — Gegner & Kampf-Grundgerüst**
Einfache Gegner-KI, ein Einheitentyp pro Seite, Angriff/Verteidigung gemäss geklärter Spezifikation, FE-Transfer bei Eroberung.

**M6 — Dialogsystem & erster Charakter**
Datengetriebenes Dialogsystem, ein NPC-Archetyp vollständig implementiert und im Spiel testbar, Trigger-Logik von Text getrennt.

**M7 — Erstes Szenario**
Eine vollständige `/data/scenarios/*.json`-Datei mit Startbedingungen, Ziel und mindestens einem Event (z. B. „Ernteausfall"), end-to-end spielbar.

**Danach:** Ausbau auf weitere Ressourcen, Technologien, Charaktere, Szenarien und schliesslich die ca. 6-stündige Kampagne — als Content-Erweiterung auf stabilem System, nicht als technisches Ziel innerhalb der Meilensteine.

## 10 Ziel

Ein fertiges Spiel für Mac und Windows mit detailverliebter 2D-Grafik, vollständig spielbar mit ca. 6 h Spieldauer für die gesamte Kampagne — erreicht über die Meilensteine in Abschnitt 9, nicht durch direkten Sprung ans Endziel.
