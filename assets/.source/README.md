# Asset-Quellen (.source)

Rohmaterial für die Asset-Pipeline: KI-generierte Bilder/Animationen (Flux-Renders,
Sprite-Sheets, GIFs/WebP), bevor sie zu spielfertigen Dateien unter `res://assets/`
verarbeitet werden.

Der führende Punkt im Ordnernamen ist Absicht: Godot ignoriert Ordner mit
führendem `.` beim Import vollständig. Rohdateien landen hier also nie als
Godot-Textur im Projekt und werden vom Spiel nie geladen — geladen wird
ausschliesslich `res://assets/<id>.png` direkt im Wurzelverzeichnis (siehe
`scripts/autoload/asset_registry.gd`).

## Struktur

Ein Ordner je Namenskonvention-Kategorie (passend zu den Praefixen aus der
`AssetRegistry`), darin ein Unterordner je Asset-ID mit den Rohdateien:

    .source/<kategorie>/<id>/<zustand>.<ext>

`<kategorie>` ist eine von: `tile`, `feature`, `building`, `unit`, `resource`,
`npc`, `animal`, `ui`. `<zustand>` ist optional (z. B. `walk`, `idle`, `work`,
`attack`, `die` — siehe `asset_erstellungsliste.md`); ein Standbild ohne
Zustand heisst schlicht nach seinem Inhalt, z. B. `standing.png`.

Beispiel: `.source/unit/villager/walk.gif` — Rohanimation fuer `unit_villager`,
Zustand „walk" (wird zu `res://assets/unit_villager_walk.png` verarbeitet).

## Ablauf

1. Rohdatei hier ablegen (beliebiges Format: PNG, GIF, WebP, …).
2. Claude verarbeitet sie (Freistellen, Zuschnitt, Downscale, Sheet-Bau) zur
   spielfertigen Datei in `res://assets/` gemaess Namenskonvention.
3. Die Rohdatei bleibt hier liegen — als Referenz und falls die Verarbeitung
   spaeter mit besserem Zuschnitt wiederholt werden soll.
