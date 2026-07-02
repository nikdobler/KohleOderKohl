# Kampfsystem-Spezifikation (Klärungspunkt vor M5)

Ergebnis des Klärungsgesprächs vom 02.07.2026 (siehe `goal_aufbaustrategiespiel.md`,
Abschnitt 9, Klärungspunkt vor M5). Abschnitt 1 ist vom Spieler entschieden und
verbindlich; Abschnitt 2 sind Vorschläge, die vor M5-Start bestätigt oder geändert
werden können.

## 1 Entschieden (verbindlich)

### 1.1 Kampfmodus: Echtzeit auf der Weltkarte
- Kämpfe finden direkt auf der Karte statt, im selben 1-Sekunden-Tick wie die
  Wirtschaft. Kein Moduswechsel, kein separater Kampfbildschirm.
- Einheiten bewegen sich kachelweise (Geschwindigkeit datengetrieben, Kacheln/Tick).
- Angriff, wenn Ziel auf Nachbarkachel (Chebyshev-Distanz 1); ein Angriff pro Tick.

### 1.2 Kampfformel: deterministisch + leichte Streuung
- `Schaden = max(1, Angriff − Verteidigung) × Zufallsfaktor(0.8 … 1.2)`, ganzzahlig gerundet.
- Einheitenwerte (`hp`, `attack`, `defense`, `speed`) datengetrieben in `/data/units.json`.
- Zufall über seedbaren RNG, damit Kämpfe in Tests reproduzierbar sind.

### 1.3 Eroberung: Hauptgebäude fällt
- Jede Siedlung (Spieler und Gegner) hat ein Hauptgebäude (Bergfried) mit Lebenspunkten.
- Wird das gegnerische Hauptgebäude zerstört, ist der Gegner erobert (Sieg-Moment).
- Fällt das eigene Hauptgebäude, ist das Spiel verloren (Niederlagen-Zustand).

### 1.4 FE-Transfer bei Eroberung: genau eine Technologie
- Beim Sieg wird genau **eine** Technologie freigeschaltet, die der Gegner erforscht
  hatte und der Spieler nicht — deterministisch die **günstigste** (Summe der
  Ressourcenkosten; bei Gleichstand die in `tech.json` zuerst definierte).
- Hat der Gegner keinen Forschungsvorsprung, gibt es keinen Transfer (nur Sieg).

## 2 Vorschläge (vor M5-Start bestätigen oder ändern)

- **Rekrutierung:** Einheit kostet Ressourcen **und** zieht einen Bewohner ab
  (belegt Wohnraum, fehlt der Wirtschaft). Krieg hat ökonomische Kosten.
- **Verluste:** Tot ist tot — gefallene Einheiten (und ihr Bewohner) sind endgültig verloren.
- **Gegner-KI (M5):** Eine statische Gegner-Siedlung auf der Karte (Hauptgebäude +
  Verteidiger), die in Intervallen kleine Angriffswellen schickt. Keine simulierte
  Gegner-Wirtschaft in M5; der Forschungsstand des Gegners wird im Szenario/Daten fixiert.

## 3 Scope-Abgrenzung für M5 (aus goal §9)

- Ein Einheitentyp pro Seite (z. B. Schwertkämpfer), datengetrieben.
- Kein Terrain-Bonus, keine Fernkämpfer, keine Belagerungswaffen, keine Formationen —
  alles spätere Erweiterungen auf dem datengetriebenen Fundament.
- Kampflogik als reines Modell (`/scripts/model/`), headless testbar wie Economy/Research.
