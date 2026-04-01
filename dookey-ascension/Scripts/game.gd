extends Node

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
@onready var layer_cases: TileMapLayer = $Deco

const DUREE_PAS   := 0.25
const OFFSET_PION := Vector2(0.0, -10.0)

const ROUE_SCENE  := preload("res://Scenes/roue.tscn")

# ═══════════════════════════════════════════════════════════════════════════
# DONNÉES INTERNES
# ═══════════════════════════════════════════════════════════════════════════
var parcours       : Array[Vector2i]   = []
var pions          : Array[Dictionary] = []   # { node, case, nom, camera }
var tour_actuel    : int  = 0
var en_deplacement : bool = false

var noms_equipes := ["Équipe 1", "Équipe 2", "Équipe 3", "Équipe 4"]

# HUD
var hud_layer    : CanvasLayer
var hud_label    : Label
var roue_instance: Node2D       # instance de la scène Roue dans le HUD

# ═══════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_creer_hud()
	_construire_parcours()

	if parcours.is_empty():
		push_error("Aucune case trouvée sur le layer '%s'." % layer_cases.name)
		return

	var noeuds := [
		$Equipes/Pion,
		$Equipes/Pion2,
		$Equipes/Pion3,
		$Equipes/Pion4,
	]

	for i in range(noeuds.size()):
		var pion_node: Node2D = noeuds[i]
		var cam := _obtenir_ou_creer_camera(pion_node, i == 0)
		pions.append({ "node": pion_node, "case": 0, "nom": noms_equipes[i], "camera": cam })
		_placer_pion(i, 0)

	_basculer_camera()
	_afficher_tour()
	_mettre_a_jour_hud()
	_montrer_roue()   # Affiche la roue pour le premier tour

# ═══════════════════════════════════════════════════════════════════════════
# HUD  (CanvasLayer avec label + conteneur pour la roue)
# ═══════════════════════════════════════════════════════════════════════════
func _creer_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)

	# Label cases restantes — centré en haut
	hud_label = Label.new()
	hud_label.name = "LabelCases"
	hud_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_label.offset_top      = 12
	hud_label.offset_bottom   = 56
	hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	hud_label.add_theme_font_size_override("font_size", 32)
	hud_label.add_theme_color_override("font_color", Color.WHITE)
	hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label.add_theme_constant_override("outline_size", 8)
	hud_label.text = ""
	hud_layer.add_child(hud_label)

	# Instance de la roue — centrée dans le HUD
	roue_instance = ROUE_SCENE.instantiate()
	# La scène Roue place son Node2D (roue dessinée) en position (1252, 295)
	# On la recentre au milieu de l'écran depuis le CanvasLayer
	roue_instance.visible = false
	hud_layer.add_child(roue_instance)

	# Connexion du signal : quand la roue donne un résultat → on avance le pion
	# Le Node2D qui a le script roue.gd est l'enfant "Node2D" de la scène Roue
	var noeud_roue: Node2D = roue_instance.get_node("Node2D")
	noeud_roue.resultat_roue.connect(_sur_resultat_roue)

# ═══════════════════════════════════════════════════════════════════════════
# Affiche / cache la roue
# ═══════════════════════════════════════════════════════════════════════════
func _montrer_roue() -> void:
	roue_instance.visible = true

func _cacher_roue() -> void:
	roue_instance.visible = false

# Appelé quand la roue émet resultat_roue(chiffre)
func _sur_resultat_roue(chiffre: int) -> void:
	_cacher_roue()
	_avancer_pion(chiffre)

# ═══════════════════════════════════════════════════════════════════════════
# Construction du parcours (uniquement atlas 5,4 / 6,4 / 5,5 / 6,5)
# ═══════════════════════════════════════════════════════════════════════════
func _construire_parcours() -> void:
	const ATLAS_AUTORISES: Array[Vector2i] = [
		Vector2i(5, 4), Vector2i(6, 4),
		Vector2i(5, 5), Vector2i(6, 5),
	]

	var toutes_cellules: Array = Array(layer_cases.get_used_cells())

	var cellules: Array = []
	for c: Vector2i in toutes_cellules:
		if layer_cases.get_cell_atlas_coords(c) in ATLAS_AUTORISES:
			cellules.append(c)

	if cellules.is_empty():
		print("[game.gd] Aucune tile avec les atlas autorisés sur '", layer_cases.name, "'")
		return

	print("[game.gd] %d tiles filtrées sur '%s'" % [cellules.size(), layer_cases.name])

	var depart: Vector2i = cellules[0]
	for c: Vector2i in cellules:
		if c.y > depart.y or (c.y == depart.y and c.x < depart.x):
			depart = c

	var restantes: Array = cellules.duplicate()
	restantes.erase(depart)
	parcours.clear()
	parcours.append(depart)
	var courante: Vector2i = depart

	while not restantes.is_empty():
		var prochaine: Vector2i = _plus_proche(courante, restantes)
		parcours.append(prochaine)
		restantes.erase(prochaine)
		courante = prochaine

	print("[game.gd] Parcours : %d cases  |  Départ=%s  |  Arrivée=%s" % [
		parcours.size(), parcours[0], parcours[parcours.size() - 1]
	])

func _plus_proche(depuis: Vector2i, liste: Array) -> Vector2i:
	var meilleure: Vector2i = liste[0]
	var dist_min: float = (Vector2(liste[0]) - Vector2(depuis)).length()
	for c: Vector2i in liste:
		var d: float = (Vector2(c) - Vector2(depuis)).length()
		if d < dist_min:
			dist_min = d
			meilleure = c
	return meilleure

# ═══════════════════════════════════════════════════════════════════════════
# Plus de saisie clavier — c'est la roue qui déclenche le déplacement
# ═══════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════
# Déplacement case par case avec animation
# ═══════════════════════════════════════════════════════════════════════════
func _avancer_pion(nb: int) -> void:
	en_deplacement = true

	var data         : Dictionary = pions[tour_actuel]
	var case_depart  : int = data["case"]
	var case_arrivee : int = mini(case_depart + nb, parcours.size() - 1)

	print("[%s] +%d → case %d/%d" % [data["nom"], nb, case_arrivee, parcours.size() - 1])

	for idx in range(case_depart + 1, case_arrivee + 1):
		data["case"] = idx
		await _animer_pion(tour_actuel, idx)
		_mettre_a_jour_hud()

	if case_arrivee >= parcours.size() - 1:
		print("🎉 %s a atteint l'arrivée !" % data["nom"])

	en_deplacement = false
	tour_actuel    = (tour_actuel + 1) % pions.size()
	_basculer_camera()
	_afficher_tour()
	_mettre_a_jour_hud()
	_montrer_roue()   # Réaffiche la roue pour le prochain tour

# ───────────────────────────────────────────────────────────────────────────
func _animer_pion(index_pion: int, index_case: int) -> void:
	var pion_node  : Node2D   = pions[index_pion]["node"]
	var coord      : Vector2i = parcours[index_case]
	var pos_locale : Vector2  = layer_cases.map_to_local(coord)
	var pos_cible  : Vector2  = layer_cases.to_global(pos_locale) + OFFSET_PION

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(pion_node, "global_position", pos_cible, DUREE_PAS)
	await tw.finished

func _placer_pion(index_pion: int, index_case: int) -> void:
	var pion_node  : Node2D   = pions[index_pion]["node"]
	var coord      : Vector2i = parcours[index_case]
	var pos_locale : Vector2  = layer_cases.map_to_local(coord)
	pion_node.global_position = layer_cases.to_global(pos_locale) + OFFSET_PION

# ═══════════════════════════════════════════════════════════════════════════
# HUD – label cases restantes
# ═══════════════════════════════════════════════════════════════════════════
func _mettre_a_jour_hud() -> void:
	var data          : Dictionary = pions[tour_actuel]
	var case_actuelle : int  = data["case"]
	var restantes     : int  = parcours.size() - 1 - case_actuelle
	var mot           : String = "case" if restantes <= 1 else "cases"
	hud_label.text = "%s — %d %s restante%s" % [data["nom"], restantes, mot, "s" if restantes > 1 else ""]

# ═══════════════════════════════════════════════════════════════════════════
# Caméras
# ═══════════════════════════════════════════════════════════════════════════
func _obtenir_ou_creer_camera(pion_node: Node2D, actif: bool) -> Camera2D:
	for child in pion_node.get_children():
		if child is Camera2D:
			child.enabled = actif
			return child as Camera2D

	var cam := Camera2D.new()
	cam.zoom    = Vector2(2, 2)
	cam.enabled = actif
	pion_node.add_child(cam)
	return cam

func _basculer_camera() -> void:
	for i in range(pions.size()):
		var cam: Camera2D = pions[i]["camera"]
		cam.enabled = (i == tour_actuel)

func _afficher_tour() -> void:
	print("─── Tour de : %s — tourne la roue ! ───" % pions[tour_actuel]["nom"])
