extends Camera2D
## CameraController — Karten-Navigation (M4/M17): Scrollen per WASD/Pfeiltasten,
## Ziehen mit rechter/mittlerer Maustaste oder Trackpad-Wischen; Zoomen mit
## Mausrad, Trackpad-Pinch oder +/−. Die Klammer ist zoomabhaengig: der
## sichtbare Ausschnitt bleibt komplett innerhalb der gemeldeten Grenzen,
## und weiter heraus als "Karte fuellt den Bildschirm" geht es nie —
## zusammen mit der Randlandschaft der Welt ist so nie Kartenrand zu sehen.

const ZOOM_MAX: float = 2.5
const ZOOM_STEP: float = 1.1
const PAN_SPEED: float = 700.0
## Trackpad-Wischen (Pan-Geste) liefert kleine Deltas -> verstaerken.
const PAN_GESTURE_SPEED: float = 24.0

var _bounds := Rect2()

func _ready() -> void:
	EventBus.camera_bounds_changed.connect(_on_bounds_changed)

func _on_bounds_changed(bounds: Rect2) -> void:
	_bounds = bounds
	position = bounds.get_center()  # Start: Blick auf die Siedlung (Kartenmitte)
	_set_zoom_level(zoom.x)  # Zoom-Untergrenze der neuen Karte durchsetzen

func _process(delta: float) -> void:
	# Ueber Input-Actions (project.godot) — damit spaeter umbelegbar (M12).
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if direction != Vector2.ZERO:
		# Bei starkem Zoom langsamer schwenken, damit es kontrollierbar bleibt.
		position += direction.normalized() * PAN_SPEED * delta / zoom.x
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_mouse(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_mouse(1.0 / ZOOM_STEP)
	elif event is InputEventMagnifyGesture:
		_zoom_at_mouse(event.factor)  # Trackpad-Pinch (macOS)
	elif event is InputEventPanGesture:
		position += event.delta * PAN_GESTURE_SPEED / zoom.x  # Zwei-Finger-Wischen
		_clamp_position()
	elif event is InputEventMouseMotion and _is_drag(event):
		position -= event.relative / zoom.x
		_clamp_position()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_PLUS or event.keycode == KEY_EQUAL:
			_set_zoom_level(zoom.x * ZOOM_STEP)
		elif event.keycode == KEY_MINUS:
			_set_zoom_level(zoom.x / ZOOM_STEP)

func _is_drag(event: InputEventMouseMotion) -> bool:
	return event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE) != 0

## Zoomt zur Mausposition: der Punkt unter dem Zeiger bleibt stehen.
func _zoom_at_mouse(factor: float) -> void:
	var before := get_global_mouse_position()
	_set_zoom_level(zoom.x * factor)
	position += before - get_global_mouse_position()
	_clamp_position()

## Setzt den Zoom innerhalb [Untergrenze, ZOOM_MAX] und klammert die Position.
func _set_zoom_level(level: float) -> void:
	var clamped := clampf(level, _min_zoom(), ZOOM_MAX)
	zoom = Vector2(clamped, clamped)
	_clamp_position()

## Zoom-Untergrenze: der Ausschnitt darf nie groesser werden als die Karte —
## sonst waere zwangslaeufig Rand zu sehen.
func _min_zoom() -> float:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return 0.1
	var viewport := get_viewport_rect().size
	return maxf(viewport.x / _bounds.size.x, viewport.y / _bounds.size.y)

## Haelt den SICHTBAREN AUSSCHNITT (nicht nur das Zentrum) in den Grenzen.
func _clamp_position() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var half_view := get_viewport_rect().size / (2.0 * zoom.x)
	var low := _bounds.position + half_view
	var high := _bounds.end - half_view
	position.x = _bounds.get_center().x if low.x > high.x else clampf(position.x, low.x, high.x)
	position.y = _bounds.get_center().y if low.y > high.y else clampf(position.y, low.y, high.y)
