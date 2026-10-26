class_name TreinFysica
extends Node
## Lichtgewicht maar fysisch correcte treinsimulatie (1D langs de spooras).
## LET OP: de waarden hieronder zijn indicatief (SNG-achtig) en moeten
## met officiële materieelgegevens worden gecontroleerd.

const G := 9.81
const SPOORWIJDTE_EFF := 1500.0   # mm, afstand tussen rijvlakken (voor verkanting)
const FYSIEKE_DT := 1.0 / 120.0   # vaste tijdstap (s)

# --- Voertuigparameters ---------------------------------------------------
@export var massa := 125000.0            # kg (incl. roterende-massatoeslag)
@export var aangedreven_aandeel := 1.0   # fractie aangedreven asmassa
@export var f_max_trek := 150000.0       # N, maximale trekkracht
@export var vermogen := 2000000.0        # W, continu vermogen
@export var adhesie_mu := 0.25           # droge rail ~0,25–0,30
@export var rem_service := 1.0           # m/s², bedrijfsrem
@export var rem_nood := 1.2              # m/s², noodrem
@export var davis_a := 1800.0            # N          (rollend/lager)
@export var davis_b := 40.0              # N·s/m
@export var davis_c := 6.5               # N·s²/m²    (luchtweerstand ½ρ·Cd·A)
@export var lengte := 64.0               # m

# --- Bestuurderstoestand --------------------------------------------------
var gas := 0.0            # 0..1
var rem := 0.0            # 0..1 (bedrijfsrem)
var noodrem := false
var richting := 1         # reverser: +1 voorwaarts, -1 achterwaarts, 0 neutraal

# --- Toestand -------------------------------------------------------------
var s := 0.0              # positie langs spoor (m)
var v := 0.0              # snelheid langs spoor (m/s), teken = rijrichting
var acc := 0.0
var a_lateraal := 0.0     # onuitgebalanceerde zijwaartse versnelling (m/s²)
var ontspoord := false

var spoor: Object          # moet sample(s) -> Dictionary leveren (zie onder)
var _acc_tijd := 0.0

signal waarschuwing(tekst: String)

## spoor.sample(s) geeft: {"R": boogstraal m (INF bij recht),
##   "D": verkanting mm, "helling": promille (+ = stijgend), "v_max": km/h}

func _physics_process(delta: float) -> void:
	if spoor == null or ontspoord:
		return
	_acc_tijd += delta
	while _acc_tijd >= FYSIEKE_DT:
		_stap(FYSIEKE_DT)
		_acc_tijd -= FYSIEKE_DT

func _stap(dt: float) -> void:
	var p: Dictionary = spoor.sample(s)
	var r: float = p.get("R", INF)
	var d: float = p.get("D", 0.0)
	var helling: float = p.get("helling", 0.0)
	var vabs := absf(v)
	var teken := signf(v) if vabs > 0.01 else float(richting)

	# 1. Trekkracht: begrensd door kracht, vermogen en adhesie
	var f_adhesie := adhesie_mu * massa * aangedreven_aandeel * G
	var f_trek := 0.0
	if richting != 0 and not noodrem:
		var f_vermogen := vermogen / maxf(vabs, 1.0)
		f_trek = gas * minf(minf(f_max_trek, f_vermogen), f_adhesie) * richting

	# 2. Weerstanden (altijd tegen de rijrichting)
	var f_davis := davis_a + davis_b * vabs + davis_c * vabs * vabs
	var f_boog := 0.0
	if not is_inf(r) and r > 55.0:
		# Röckl: w = 650/(R-55) N/kN (R>300), 500/(R-30) bij kleinere R
		var w := 650.0 / (r - 55.0) if r > 300.0 else 500.0 / maxf(r - 30.0, 1.0)
		f_boog = w * massa * G / 1000.0
	var f_weerstand := (f_davis + f_boog) * teken

	# 3. Hellingkracht (promille -> sin(hoek) ≈ helling/1000)
	# Helling is gedefinieerd in +s-richting: stijgend (+) werkt in -s-richting.
	var f_helling_langs := -massa * G * (helling / 1000.0)

	# 4. Remmen: begrensd door adhesie
	var a_rem := rem_nood if noodrem else rem * rem_service
	var f_rem := minf(a_rem * massa, adhesie_mu * massa * G) * -teken if vabs > 0.01 else 0.0

	# 5. Totaalkracht en integratie (semi-impliciete Euler)
	var f_tot := f_trek - f_weerstand + f_helling_langs + f_rem
	var v_oud := v
	acc = f_tot / massa
	v += acc * dt
	# Weerstand/rem mogen de trein niet laten omkeren
	if v_oud != 0.0 and signf(v) != signf(v_oud) and absf(f_trek) < absf(f_weerstand + f_rem):
		v = 0.0
	s += v * dt

	# 6. Zijwaartse krachten uit CAD-geometrie
	if not is_inf(r):
		var a_centrifugaal := v * v / r
		var a_verkanting := G * d / SPOORWIJDTE_EFF
		a_lateraal = a_centrifugaal - a_verkanting     # ≈ verkantingstekort I
		# I = 100 mm ≈ 0,65 m/s² (comfort/limiet)
		if absf(a_lateraal) > 0.65 and absf(a_lateraal) <= 1.0:
			waarschuwing.emit("Verkantingstekort overschreden!")
		elif absf(a_lateraal) > 1.0:
			ontspoord = true
			waarschuwing.emit("Ontspoord of omgevallen: te hoge snelheid in boog.")
	else:
		a_lateraal = 0.0

	var v_lim: float = p.get("v_max", 200.0) / 3.6
	if absf(v) > v_lim * 1.05:
		waarschuwing.emit("Baanvaksnelheid overschreden.")

func snelheid_kmh() -> float:
	return absf(v) * 3.6

## Remweg bij huidige snelheid (m), met bedrijfs- of noodrem.
func remweg(nood := false) -> float:
	var a := rem_nood if nood else rem_service
	return v * v / (2.0 * a)
