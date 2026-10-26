class_name ProRailAlignement
extends RefCounted
## ProRail-alignementrekenmodule (bron: OVS00056-4.1-V003, samengesteld door Daan).
## Eenheden: V in km/h, R in m, D / I / ΔD / ΔI in mm, L in m.

enum Profiel { REIZIGER, GEMENGD, LANGZAAM }

const R_MAX := 30000.0          # maximale boogstraal (horizontaal en verticaal)
const D_MAX := 120.0            # maximale verkanting
const I_MAX := 100.0            # maximaal verkantingstekort
const RV_MIN := 2000.0          # minimale verticale boogstraal

# --- 1. Boogstraal en elementlengte -------------------------------------

## Minimale boogstraal. 'uitzondering' = true geeft de uitzonderingswaarde.
static func min_boogstraal(v_max: float, uitzondering := false) -> float:
	if v_max <= 40.0:
		return 150.0 if uitzondering else 190.0
	return 200.0 if uitzondering else 425.0

## Minimale lengte tracéelement (niet voor overgangsbogen). Richtwaarde.
static func min_elementlengte(v_max: float) -> float:
	return v_max / 3.0 if v_max <= 40.0 else v_max / 1.8

# --- 2. Verkanting -------------------------------------------------------

static func theoretische_verkanting(v_max: float, r_h: float) -> float:
	if is_inf(r_h):
		return 0.0
	return 11.8 * v_max * v_max / r_h

## Daadwerkelijke verkanting per profiel; 5 mm omhoog afgerond, max 120 mm.
## Geeft {D, I, geldig, reden} terug.
static func verkanting(v_max: float, r_h: float, profiel: Profiel) -> Dictionary:
	var d_th := theoretische_verkanting(v_max, r_h)
	var d := 0.0
	if d_th > 40.0:
		match profiel:
			Profiel.REIZIGER: d = d_th - 20.0
			Profiel.GEMENGD:  d = 0.7 * d_th
			Profiel.LANGZAAM: d = 0.5 * d_th
		d = ceil(d / 5.0) * 5.0
	var i := d_th - d
	var geldig := true
	var reden := ""
	if d > D_MAX:
		geldig = false
		reden = "Verkanting > 120 mm: kies lagere snelheid of grotere boogstraal."
	elif i > I_MAX:
		geldig = false
		reden = "Verkantingstekort > 100 mm: kies lagere snelheid of grotere boogstraal."
	elif r_h < min_boogstraal(v_max, true):
		geldig = false
		reden = "Boogstraal kleiner dan uitzonderingswaarde."
	elif r_h < min_boogstraal(v_max, false):
		reden = "Waarschuwing: onder normwaarde (uitzonderingswaarde)."
	return {"D_th": d_th, "D": min(d, D_MAX), "I": i, "geldig": geldig, "reden": reden}

## Kleinste boogstraal zonder verkanting (D_th = 40 mm).
static func min_straal_zonder_verkanting(v_max: float) -> float:
	return 11.8 * v_max * v_max / 40.0

## Krapste boogstraal bij maximale verkanting per profiel.
static func min_straal_profiel(v_max: float, profiel: Profiel) -> float:
	var noemer := 100.0
	match profiel:
		Profiel.GEMENGD:  noemer = 84.0
		Profiel.LANGZAAM: noemer = 60.0
	return 11.8 * v_max * v_max / noemer

# --- 3. Overgangsbogen en overgangshelling ------------------------------

static func overgangsboog_nodig(v_max: float, delta_i: float) -> bool:
	var grens := 76.0 if v_max <= 40.0 else 40.0
	return absf(delta_i) > grens

## Minimale lengte (maximum van ruk, kantelsnelheid), begrensd door scheluwte.
## Geeft {L, L_ruk, L_kantel, L_min_scheluw, L_max_scheluw, waarschuwing}.
static func overgangslengte(v_max: float, delta_i: float, delta_d: float,
		met_overgangsboog: bool) -> Dictionary:
	var di := absf(delta_i)
	var dd := absf(delta_d)
	var l_ruk := (di * v_max) / (25.0 * 3.6) if met_overgangsboog else 0.0
	var l_kantel := (dd * v_max) / (25.0 * 3.6)
	var l := maxf(l_ruk, l_kantel)
	var l_min := 0.6 * dd
	var l_max := 3.0 * dd
	var waarschuwing := ""
	if l < l_min:
		l = l_min                       # dichtstbijzijnde grenswaarde
	elif l > l_max:
		l = l_max
		waarschuwing = "Scheluwte-bovengrens < ruk/kantelsnelheid-eis: verlaag Vmax of vergroot R."
	return {"L": l, "L_ruk": l_ruk, "L_kantel": l_kantel,
			"L_min_scheluw": l_min, "L_max_scheluw": l_max, "waarschuwing": waarschuwing}

# --- 4. Verticaal alignement --------------------------------------------

## Maximale helling in promille. 'uitzondering' = 25‰, 'opstelspoor' = 1‰.
static func check_helling(promille: float, opstelspoor := false) -> String:
	var p := absf(promille)
	if opstelspoor:
		return "" if p <= 1.0 else "Opstel-/keerspoor: helling > 1‰."
	if p <= 5.0:
		return ""
	if p <= 25.0:
		return "Uitzonderingswaarde (>5‰): beperkingen goederenverkeer."
	return "Helling > 25‰: niet toegestaan."

static func norm_rv(v_max: float) -> float:
	return maxf(RV_MIN, 0.4 * v_max * v_max)

static func check_rv(r_v: float, v_max: float) -> String:
	if r_v < RV_MIN:
		return "Rv < 2000 m: niet toegestaan."
	if r_v > R_MAX:
		return "Rv > 30000 m: gebruik rechtstand."
	if r_v < 0.4 * v_max * v_max:
		return "Rv onder normwaarde 0,4·V²."
	return ""

## Top- en dalboog direct op elkaar: 1/Rtop + 1/Rdal <= 1/(0,25·V²).
static func check_top_dalboog(r_top: float, r_dal: float, v_max: float) -> bool:
	return (1.0 / r_top + 1.0 / r_dal) <= 1.0 / (0.25 * v_max * v_max)

# --- 5. Combinatie horizontaal + verticaal ------------------------------

## (I/100)² + (0,4·V²/Rv)² <= 1
static func check_combinatie(i_mm: float, v_max: float, r_v: float) -> bool:
	var a := i_mm / 100.0
	var b := (0.4 * v_max * v_max) / r_v
	return a * a + b * b <= 1.0
