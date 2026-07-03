extends RefCounted
## Unit-Tests fuer die prozedurale Bewegungsanimation (SpriteAnim).
##
## Prueft: Ruhe = kein Versatz; Gehen = Hopser nach oben in Grenzen; Squash/Stretch
## gegenlaeufig (naeherungsweise flaechenerhaltend); Ruhe-Atmen schwaecher als Gehen;
## alles deterministisch.

func run() -> Array:
	var failures: Array = []
	_test_idle_no_offset(failures)
	_test_walk_bob_bounds(failures)
	_test_squash_opposes(failures)
	_test_idle_gentler(failures)
	_test_deterministic(failures)
	_test_walk_frame(failures)
	_test_frames_in_sheet(failures)
	_test_play_once(failures)
	_test_vertical_facing(failures)
	return failures

## Vertikale Blickrichtung: unten=+1, oben=-1, dazwischen unveraendert (0).
func _test_vertical_facing(failures: Array) -> void:
	if SpriteAnim.vertical_facing(1.0, 0.1) != 1:
		failures.append("facing: nach unten muss +1 sein")
	if SpriteAnim.vertical_facing(-1.0, 0.1) != -1:
		failures.append("facing: nach oben muss -1 sein")
	if SpriteAnim.vertical_facing(0.05, 0.1) != 0 or SpriteAnim.vertical_facing(-0.05, 0.1) != 0:
		failures.append("facing: unter Schwelle muss 0 (unveraendert) sein")

## Einmal-Animation: 0->Frame 0, Ende->letzter Frame, darueber hinaus gehalten.
func _test_play_once(failures: Array) -> void:
	if SpriteAnim.play_once_frame(0.0, 4) != 0:
		failures.append("play_once: Start muss Frame 0 sein")
	if SpriteAnim.play_once_frame(0.5, 4) != 2:
		failures.append("play_once: Mitte falsch")
	if SpriteAnim.play_once_frame(1.0, 4) != 3 or SpriteAnim.play_once_frame(9.0, 4) != 3:
		failures.append("play_once: muss auf letztem Frame halten")
	if SpriteAnim.play_once_frame(0.5, 1) != 0:
		failures.append("play_once: 1 Frame muss 0 sein")

## Laufband-Frame: im Bereich 0..frames-1, zyklisch, 1-Frame -> immer 0.
func _test_walk_frame(failures: Array) -> void:
	if SpriteAnim.walk_frame(3.7, 1) != 0:
		failures.append("walk_frame: 1 Frame muss 0 sein")
	for i in 200:
		var t := i * 0.05
		var f := SpriteAnim.walk_frame(t, 6)
		if f < 0 or f >= 6:
			failures.append("walk_frame: %d ausserhalb 0..5" % f)
			return
		# Zyklus: nach frames/WALK_FPS Sekunden wieder gleicher Frame.
		if SpriteAnim.walk_frame(t + 6.0 / SpriteAnim.WALK_FPS, 6) != f:
			failures.append("walk_frame: nicht zyklisch bei t=%.2f" % t)
			return

## Frame-Anzahl aus Sheet-Maßen (quadratische Frames der Höhe H).
func _test_frames_in_sheet(failures: Array) -> void:
	var cases := {"108x18": [108, 18, 6], "72x18": [72, 18, 4], "18x18": [18, 18, 1],
		"10x18": [10, 18, 1], "0hoehe": [64, 0, 1]}
	for name in cases:
		var c: Array = cases[name]
		if SpriteAnim.frames_in_sheet(c[0], c[1]) != c[2]:
			failures.append("frames_in_sheet %s: erwartet %d, erhielt %d" % [name, c[2], SpriteAnim.frames_in_sheet(c[0], c[1])])

## Ruhend: kein vertikaler Versatz.
func _test_idle_no_offset(failures: Array) -> void:
	for i in 20:
		if SpriteAnim.offset_of(false, i * 0.37) != Vector2.ZERO:
			failures.append("Ruhe: Versatz muss 0 sein")
			return

## Gehend: Versatz nur nach oben (y <= 0) und im Rahmen der Hopser-Hoehe.
func _test_walk_bob_bounds(failures: Array) -> void:
	for i in 200:
		var o := SpriteAnim.offset_of(true, i * 0.11)
		if o.x != 0.0 or o.y > 0.0 or o.y < -SpriteAnim.WALK_BOB - 0.001:
			failures.append("Gehen: Bob ausserhalb [-%.1f, 0] bei %d (%s)" % [SpriteAnim.WALK_BOB, i, o])
			return

## Squash/Stretch: horizontale und vertikale Skalierung laufen gegenlaeufig.
func _test_squash_opposes(failures: Array) -> void:
	for i in 200:
		var s := SpriteAnim.scale_of(true, i * 0.09)
		if s.x <= 0.0 or s.y <= 0.0:
			failures.append("Skalierung: nicht positiv (%s)" % s)
			return
		# (x-1) und (y-1) muessen entgegengesetzte Vorzeichen haben (oder ~0).
		if (s.x - 1.0) * (s.y - 1.0) > 0.0001:
			failures.append("Skalierung: x und y nicht gegenlaeufig (%s)" % s)
			return

## Ruhe-Atmen ist deutlich schwaecher als der Geh-Squash.
func _test_idle_gentler(failures: Array) -> void:
	var max_idle := 0.0
	var max_walk := 0.0
	for i in 400:
		max_idle = maxf(max_idle, absf(SpriteAnim.scale_of(false, i * 0.05).y - 1.0))
		max_walk = maxf(max_walk, absf(SpriteAnim.scale_of(true, i * 0.05).y - 1.0))
	if not (max_idle < max_walk):
		failures.append("Atmen: Ruhe (%.3f) muss schwaecher sein als Gehen (%.3f)" % [max_idle, max_walk])

## Gleicher Zeitwert -> gleiches Ergebnis.
func _test_deterministic(failures: Array) -> void:
	if SpriteAnim.offset_of(true, 1.23) != SpriteAnim.offset_of(true, 1.23) \
			or SpriteAnim.scale_of(true, 1.23) != SpriteAnim.scale_of(true, 1.23):
		failures.append("Determinismus: gleiche Eingabe muss gleich sein")
