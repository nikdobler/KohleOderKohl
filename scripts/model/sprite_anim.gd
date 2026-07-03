class_name SpriteAnim
extends RefCounted
## SpriteAnim — prozedurale „lebendige Bewegung" fuer stehende Sprites, damit sie
## nicht als starres Bild ueber den Screen gleiten. Rein rechnerisch (kein Node),
## darum headless testbar. Liefert nur den VISUELLEN Versatz/Skalierung; Position
## und z_index bleiben Sache des Aufrufers (Tiefensortierung ungestoert).
##
## Zwei Zustaende:
##  - bewegt: Geh-Hopser (Bob) mit Squash & Stretch, synchron zur Schrittfrequenz.
##  - ruhend: dezentes „Atmen".
## Der Parameter [param t] ist eine (pro Sprite versetzte) Zeit -> die Sprites
## animieren entkoppelt statt im Gleichschritt.
##
## Bewusst der UEBERGANG, nicht das Ziel: sobald ein Asset echte Frame-Animation
## (Sprite-Sheet) hat, uebernimmt diese den Gang; der Bob wird dann uebersprungen.

const WALK_FREQ: float = 9.0      # Schritte pro Zeiteinheit
const WALK_BOB: float = 2.5       # Hopser-Hoehe in px
const WALK_SQUASH: float = 0.10   # Stauch-/Streck-Amplitude
const IDLE_FREQ: float = 2.2      # Atem-Frequenz
const IDLE_BREATHE: float = 0.03  # Atem-Amplitude
const WALK_FPS: float = 8.0       # Bilder/s bei echter Frame-Animation (Laufband)

## Aktueller Laufband-Frame (0 .. frames-1) zur Zeit [param t]. Fuer Assets mit
## echtem Sprite-Sheet; zyklisch, robust gegen negative Zeit.
static func walk_frame(t: float, frames: int) -> int:
	if frames <= 1:
		return 0
	return posmod(int(t * WALK_FPS), frames)

## Vertikale Iso-Blickrichtung aus der Bewegung: +1 = nach unten/vorne (zur Kamera),
## -1 = nach oben/hinten, 0 = unveraendert (zu langsam). Die Links/Rechts-Richtung
## erledigt die Horizontal-Spiegelung -> 4 Iso-Richtungen aus 2 gezeichneten Sheets.
static func vertical_facing(vy: float, threshold: float) -> int:
	if vy > threshold:
		return 1
	if vy < -threshold:
		return -1
	return 0

## Frame einer EINMALIGEN Animation (z. B. Sterben): [param progress] 0..1 laeuft
## einmal durch und bleibt auf dem letzten Frame stehen.
static func play_once_frame(progress: float, frames: int) -> int:
	if frames <= 1:
		return 0
	return clampi(int(progress * frames), 0, frames - 1)

## Frame-Anzahl eines horizontalen Laufband-Sheets: quadratische Frames der Hoehe
## [param height] nebeneinander -> Anzahl = Breite / Hoehe (mind. 1).
static func frames_in_sheet(width: int, height: int) -> int:
	if height <= 0:
		return 1
	return maxi(1, int(float(width) / float(height)))

## Visueller Versatz (nur beim Gehen ein Hopser nach oben; sonst 0).
static func offset_of(moving: bool, t: float) -> Vector2:
	if not moving:
		return Vector2.ZERO
	return Vector2(0.0, -absf(sin(t * WALK_FREQ)) * WALK_BOB)

## Skalierung: beim Gehen Squash&Stretch (unten breit/flach, oben schmal/hoch),
## sonst leichtes Atmen. Naeherungsweise flaechenerhaltend ((1-s)(1+s) = 1-s²).
static func scale_of(moving: bool, t: float) -> Vector2:
	if not moving:
		var b := sin(t * IDLE_FREQ) * IDLE_BREATHE
		return Vector2(1.0 - b, 1.0 + b)
	# lift: 0 am Boden (Fuss aufgesetzt -> Squash), 1 im Scheitel (-> Stretch).
	var lift := absf(sin(t * WALK_FREQ))
	var s := (lift - 0.5) * 2.0 * WALK_SQUASH
	return Vector2(1.0 - s, 1.0 + s)
