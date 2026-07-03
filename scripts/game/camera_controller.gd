extends Camera2D
## CameraController — Karten-Navigation (M4/M17/M-Unendlich): Scrollen per
## WASD/Pfeiltasten, Ziehen mit rechter/mittlerer Maustaste oder Trackpad-
## Wischen; Zoomen mit Mausrad, Trackpad-Pinch oder +/−. Die Welt ist seit
## M-Unendlich grenzenlos — es gibt keine Positions-Klammer mehr; die
## Welt-Darstellung streamt die Umgebung der Kamera nach. Die gemeldeten
## "Grenzen" dienen nur noch dem Startblick auf die Siedlung.

const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 6.0
const ZOOM_STEP: float = 1.05
const PAN_SPEED: float = 700.0
## Trackpad-Wischen (Pan-Geste) liefert kleine Deltas -> verstaerken.
const PAN_GESTURE_SPEED: float = 24.0
## Pinch-Gesten daempfen: nur dieser Anteil des rohen Faktors wirkt,
## sonst rast der Trackpad-Zoom durch den ganzen Bereich.
const MAGNIFY_DAMPING: float = 0.4

func _ready() -> void:
	EventBus.camera_bounds_changed.connect(_on_bounds_changed)

func _on_bounds_changed(bounds: Rect2) -> void:
	position = bounds.get_center()  # Start: Blick auf die Siedlung

func _process(delta: float) -> void:
	# Ueber Input-Actions (project.godot) — damit spaeter umbelegbar (M12).
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if direction != Vector2.ZERO:
		# Bei starkem Zoom langsamer schwenken, damit es kontrollierbar bleibt.
		position += direction.normalized() * PAN_SPEED * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_mouse(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_mouse(1.0 / ZOOM_STEP)
	elif event is InputEventMagnifyGesture:
		# Trackpad-Pinch (macOS), gedaempft fuer feinfuehliges Zoomen.
		_zoom_at_mouse(1.0 + (event.factor - 1.0) * MAGNIFY_DAMPING)
	elif event is InputEventPanGesture:
		position += event.delta * PAN_GESTURE_SPEED / zoom.x  # Zwei-Finger-Wischen
	elif event is InputEventMouseMotion and _is_drag(event):
		position -= event.relative / zoom.x
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

func _set_zoom_level(level: float) -> void:
	var clamped := clampf(level, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(clamped, clamped)
