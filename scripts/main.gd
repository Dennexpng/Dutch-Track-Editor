extends Node3D
## Startpunt: bouwt camera, licht, grond en de CAD-touchbesturing in code op,
## zodat er geen editor nodig is.

var cad: TouchCAD
var rails := Node3D.new()

func _ready() -> void:
	# Licht (zon)
	var zon := DirectionalLight3D.new()
	zon.rotation_degrees = Vector3(-50, 30, 0)
	zon.shadow_enabled = true
	add_child(zon)

	# Camera schuin van boven
	var cam := Camera3D.new()
	cam.position = Vector3(0, 80, 80)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	cam.far = 3000.0
	add_child(cam)

	# Grond
	var grond := MeshInstance3D.new()
	var vlak := PlaneMesh.new()
	vlak.size = Vector2(2000, 2000)
	grond.mesh = vlak
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.4, 0.2)
	grond.material_override = mat
	add_child(grond)

	add_child(rails)

	# CAD-touchbesturing
	cad = TouchCAD.new()
	cad.camera = cam
	cad.segment_bevestigd.connect(_plaats_spoor)
	add_child(cad)

func _plaats_spoor(van: Vector3, naar: Vector3) -> void:
	var lengte := van.distance_to(naar)
	var bak := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.3, lengte)
	bak.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.33, 0.3)
	m.metallic = 0.4
	bak.material_override = m
	rails.add_child(bak)
	bak.global_position = (van + naar) / 2.0 + Vector3(0, 0.15, 0)
	bak.look_at(naar + Vector3(0, 0.15, 0), Vector3.UP)
