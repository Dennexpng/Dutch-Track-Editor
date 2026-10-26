class_name TouchCAD
extends Node3D
## Touchbesturing voor CAD-plaatsing: slepen om te bouwen, raster- en knoopsnap,
## twee vingers voor pannen/zoomen/draaien, lang indrukken voor wissel/hoogte.

signal segment_voorgesteld(van: Vector3, naar: Vector3, status: Dictionary)
signal segment_bevestigd(van: Vector3, naar: Vector3)

enum Modus { BOUWEN, WISSEL, HOOGTE, VERWIJDEREN, CAMERA }

const RASTER := 5.0              # m
const KNOOP_SNAP_PX := 48.0      # scherm-pixels
const LANG_INDRUKKEN := 0.5      # s

@export var camera: Camera3D
@export var v_max_kmh := 120.0
@export var profiel := ProRailAlignement.Profiel.REIZIGER
@export var knopen: Array[Vector3] = []   # bestaande spoorknopen (wereldcoördinaten)

var modus := Modus.BOUWEN
var _vingers := {}               # index -> huidige schermpositie
var _start: Vector3
var _huidig: Vector3
var _bezig := false
var _druk_tijd := 0.0
var _vorige_afstand := 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_vingers[event.index] = event.position
			if _vingers.size() == 1 and modus != Modus.CAMERA:
				_begin(event.position)
			elif _vingers.size() == 2:
				_bezig = false             # tweede vinger = cameragebaar
				_vorige_afstand = _vinger_afstand()
		else:
			_vingers.erase(event.index)
			if _vingers.is_empty() and _bezig:
				_einde()
	elif event is InputEventScreenDrag:
		_vingers[event.index] = event.position
		if _vingers.size() == 1 and _bezig:
			_sleep(event.position)
		elif _vingers.size() == 2:
			_camera_gebaar(event)

func _process(delta: float) -> void:
	if _bezig and _vingers.size() == 1:
		_druk_tijd += delta
		if _druk_tijd >= LANG_INDRUKKEN and _start.is_equal_approx(_huidig):
			modus = Modus.WISSEL      # lang indrukken zonder slepen: wissel plaatsen
			_druk_tijd = -INF
			Input.vibrate_handheld(30)

# --- Bouwen --------------------------------------------------------------

func _begin(scherm: Vector2) -> void:
	_start = _snap(_naar_grond(scherm), scherm)
	_huidig = _start
	_bezig = true
	_druk_tijd = 0.0

func _sleep(scherm: Vector2) -> void:
	_huidig = _snap(_naar_grond(scherm), scherm)
	if modus == Modus.HOOGTE:
		# verticaal slepen verandert de hoogte (m) van het eindpunt
		_huidig.y = snappedf((_start.y + (_vingers.values()[0].y - scherm.y) * 0.05), 0.1)
	segment_voorgesteld.emit(_start, _huidig, _controleer(_start, _huidig))

func _einde() -> void:
	_bezig = false
	var status := _controleer(_start, _huidig)
	if modus == Modus.BOUWEN and _start.distance_to(_huidig) >= ProRailAlignement.min_elementlengte(v_max_kmh):
		if status.get("geldig", false):
			segment_bevestigd.emit(_start, _huidig)
			if not knopen.has(_huidig):
				knopen.append(_huidig)
		else:
			Input.vibrate_handheld(80)    # ongeldig: haptische afwijzing
	if modus == Modus.WISSEL:
		modus = Modus.BOUWEN

## Controleert hoogteverschil (helling) van het voorgestelde segment.
func _controleer(van: Vector3, naar: Vector3) -> Dictionary:
	var lengte := Vector2(van.x, van.z).distance_to(Vector2(naar.x, naar.z))
	if lengte < 0.1:
		return {"geldig": false, "reden": "Te kort"}
	var helling := (naar.y - van.y) / lengte * 1000.0
	var tekst := ProRailAlignement.check_helling(helling)
	return {"geldig": not tekst.begins_with("Helling >"),
			"helling_promille": helling, "reden": tekst,
			"lengte": lengte}

# --- Snap ----------------------------------------------------------------

func _snap(punt: Vector3, scherm: Vector2) -> Vector3:
	for k in knopen:       # knoopsnap heeft voorrang op rastersnap
		if camera.is_position_behind(k):
			continue
		if camera.unproject_position(k).distance_to(scherm) <= KNOOP_SNAP_PX:
			return k
	return Vector3(snappedf(punt.x, RASTER), punt.y, snappedf(punt.z, RASTER))

func _naar_grond(scherm: Vector2) -> Vector3:
	var o := camera.project_ray_origin(scherm)
	var r := camera.project_ray_normal(scherm)
	if absf(r.y) < 0.0001:
		return Vector3.ZERO
	var t := -o.y / r.y
	return o + r * t

# --- Camera --------------------------------------------------------------

func _vinger_afstand() -> float:
	var v := _vingers.values()
	return (v[0] as Vector2).distance_to(v[1])

func _camera_gebaar(event: InputEventScreenDrag) -> void:
	var afstand := _vinger_afstand()
	var factor := _vorige_afstand / maxf(afstand, 1.0)
	camera.global_position += camera.global_transform.basis.z * (factor - 1.0) * camera.global_position.y
	_vorige_afstand = afstand
	# pannen met gemiddelde verplaatsing
	var pan := event.relative * 0.5 * camera.global_position.y * 0.002
	camera.global_position += camera.global_transform.basis.x * -pan.x
	camera.global_position += Vector3(camera.global_transform.basis.z.x, 0, camera.global_transform.basis.z.z).normalized() * pan.y
