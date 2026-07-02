extends Camera2D
## CameraController — Karten-Navigation (M4): Scrollen per WASD/Pfeiltasten
## oder Ziehen mit rechter/mittlerer Maustaste, Zoomen mit dem Mausrad in
## Richtung Mauszeiger. Die Position bleibt innerhalb der Kartengrenzen,
## die die Welt-Darstellung ueber den [EventBus] meldet.

const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 2.5
const ZOOM_STEP: float = 1.1
const PAN_SPEED: float = 700.0

var _bounds := Rect2()

func _ready() -> void:
	EventBus.camera_bounds_changed.connect(_on_bounds_changed)

func _on_bounds_changed(bounds: Rect2) -> void:
	_bounds = bounds
	position = bounds.get_center()  # Start: Blick auf die Siedlung (Kartenmitte)
	_clamp_position()

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
	elif event is InputEventMouseMotion and _is_drag(event):
		position -= event.relative / zoom.x
		_clamp_position()

func _is_drag(event: InputEventMouseMotion) -> bool:
	return event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE) != 0

## Zoomt zur Mausposition: der Punkt unter dem Zeiger bleibt stehen.
func _zoom_at_mouse(factor: float) -> void:
	var before := get_global_mouse_position()
	var new_zoom := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(new_zoom, new_zoom)
	position += before - get_global_mouse_position()
	_clamp_position()

func _clamp_position() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	position = position.clamp(_bounds.position, _bounds.end)
