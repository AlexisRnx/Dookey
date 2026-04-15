extends Node

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
@onready var layer_cases: TileMapLayer = $Deco

const DUREE_PAS   := 0.25
const OFFSET_PION := Vector2(0.0, -10.0)

const ROUE_SCENE  := preload("res://Scenes/roue.tscn")

# Dictionnaire des effets des cases spéciales : Vector2i(AtlasX, AtlasY) : déplacement
const EFFETS_CASES: Dictionary = {
	Vector2i(1, 0):  3,   # Cercle bleu : +3
	Vector2i(2, 0):  4,   # Cercle rouge : +4
	Vector2i(3, 0):  5,   # Cercle jaune : +5
	Vector2i(1, 1): -3,   # Cercle orange : -3
	Vector2i(2, 1): -4,   # Cercle orange : -4
	Vector2i(3, 1): -5    # Cercle orange : -5
}

# Case du Boss
const BOSS_TILE       := Vector2i(0, 2)
const BOSS_TEXTURE    := preload("res://Assets/Dookey_Boss.png")
const BOSS_DIALOGUES : Array[String] = [
	"L'ascension est un privilège que je révoque... MAINTENANT.",
	"Je suis Dookey Boss, le seul maître de ce royaume. Inclinez-vous !",
	"Votre courage n'est qu'un bug dans ma matrice. Je vais vous effacer.",
	"Vous pensiez atteindre le sommet ? Quel optimisme pathétique...",
	"Le désespoir a un goût délicieux. Choisissez votre supplice !"
]
const BOSS_AUDIO      := preload("res://Assets/Soundtrack/One Punch Man OST  - Crisis.mp3")

# Case Dookey Majestueux
const MAJESTUEUX_TILE := Vector2i(1, 2)
const MAJ_TEXTURE     := preload("res://Assets/Dookey_Majestueux.png")
const MAJ_DIALOGUES : Array[String] = [
	"Votre bravoure résonne. Choisissez votre bénédiction.",
	"L'ascension est à votre portée. Quelle est votre volonté ?",
	"Je suis Dookey Majestueux. Avancez, ou punissez les faibles.",
	"Le sommet vous appelle. Un don ou un châtiment, à vous de choisir.",
	"Une once de puissance divine vous est accordée. Faites-en bon usage."
]
const MAJ_AUDIO       := preload("res://Assets/Soundtrack/All Might vs Noumu (Brainless) Theme - My Hero Academia OST [Plus Ultra!].mp3")

# Case Portail (Mini-Jeu)
const PORTAIL_TILE    := Vector2i(2, 2)

# ═══════════════════════════════════════════════════════════════════════════

# DONNÉES INTERNES
# ═══════════════════════════════════════════════════════════════════════════
var parcours       : Array[Vector2i]   = []
var pions          : Array[Dictionary] = []   # { node, case, nom, camera }
var tour_actuel    : int  = 0
var en_deplacement : bool = false
var est_restauration : bool = false

var noms_equipes : Array[String] = ["Équipe 1", "Équipe 2", "Équipe 3", "Équipe 4"]

# HUD
var hud_layer    : CanvasLayer
var hud_label    : Label
var hud_label_steps : Label   # countdown de pas pendant le déplacement
var temp_label_chrono: Label
var roue_instance: Node2D       # instance de la scène Roue dans le HUD

# Chrono & Votes
var temps_chrono := 0.0
var chrono_actif := false
var vote_en_cours: Dictionary = {}

# Boss
var boss_votes        := {0: 0, 1: 0}
var boss_vote_actif   := false
var boss_chrono_actif := false
var boss_chrono_temps := 10.0
var boss_overlay  : Control      = null
var boss_sprite   : TextureRect  = null
var boss_pct_0    : Label        = null
var boss_pct_1    : Label        = null
var boss_card_0   : PanelContainer = null
var boss_card_1   : PanelContainer = null
var boss_timer_lbl: Label        = null
var boss_layer     : CanvasLayer  = null
var boss_audio_player : AudioStreamPlayer = null

# Majestueux
var maj_votes      := {}
var maj_vote_actif := false
var maj_audio_player : AudioStreamPlayer = null

# Portail QTE
var equipes_bloquees_portail : Array[int] = []
var portail_votes : Dictionary = {"success": 0, "fail": 0, "pseudos": []}
var portail_actif : bool = false

# HUD équipes (panneau top-right)

var nb_joueurs_debut    : Dictionary = {}  # {equipe_idx -> nb initial}
var panel_equipes_hud   : PanelContainer = null
var labels_equipes_hud  : Array = []

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

	# Construire les noms d'équipes depuis les assignations WebSocketServer
	_construire_noms_equipes()
	
	for i in range(noeuds.size()):
		var pion_node: Node2D = noeuds[i]
		var cam := _obtenir_ou_creer_camera(pion_node, i == 0)
		pions.append({ "node": pion_node, "case": 0, "nom": noms_equipes[i], "camera": cam })
		_placer_pion(i, 0)

	_restaurer_partie()

	_basculer_camera()
	
	if not est_restauration:
		_afficher_tour()
	else:
		_reprendre_tour()
		
	_mettre_a_jour_hud()
	
	WebSocketServer.verrouiller_salle()
	_initialiser_compteurs_equipes()

# ═══════════════════════════════════════════════════════════════════════════
# Construit les noms d'équipes (Utilise toujours les couleurs fixes maintenant)
# ═══════════════════════════════════════════════════════════════════════════
func _construire_noms_equipes() -> void:
	for i in range(4):
		noms_equipes[i] = WebSocketServer.NOMS_EQUIPES[i]

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

	# Label steps (compte à rebours pendant le déplacement) — sous le label cases
	hud_label_steps = Label.new()
	hud_label_steps.name = "LabelSteps"
	hud_label_steps.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_label_steps.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_label_steps.offset_top    = 58
	hud_label_steps.offset_bottom = 104
	hud_label_steps.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_label_steps.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	hud_label_steps.add_theme_font_size_override("font_size", 40)
	hud_label_steps.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	hud_label_steps.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_label_steps.add_theme_constant_override("outline_size", 9)
	hud_label_steps.text = ""
	hud_layer.add_child(hud_label_steps)

	# Label chronomètre — centré au milieu
	temp_label_chrono = Label.new()
	temp_label_chrono.name = "LabelChrono"
	temp_label_chrono.set_anchors_preset(Control.PRESET_CENTER)
	temp_label_chrono.grow_horizontal = Control.GROW_DIRECTION_BOTH
	temp_label_chrono.grow_vertical = Control.GROW_DIRECTION_BOTH
	temp_label_chrono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	temp_label_chrono.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	temp_label_chrono.add_theme_font_size_override("font_size", 120)
	temp_label_chrono.add_theme_color_override("font_color", Color.WHITE)
	temp_label_chrono.add_theme_color_override("font_outline_color", Color.BLACK)
	temp_label_chrono.add_theme_constant_override("outline_size", 15)
	temp_label_chrono.text = "10"
	temp_label_chrono.visible = false
	hud_layer.add_child(temp_label_chrono)

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

	# ── Connexion du serveur WebSocket → roue ─────────────────────────────
	# WebSocketServer est un Autoload enregistré dans project.godot
	WebSocketServer.votes_recus.connect(_sur_votes_recus)
	WebSocketServer.lancer_roue_web.connect(_sur_lancer_roue_web)
	WebSocketServer.portail_qte_recu.connect(_sur_portail_qte_recu)

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

# ── Reçoit les votes du site Web via WebSocket ────────────────────────────
func _sur_votes_recus(votes: Dictionary) -> void:
	for chiffre in votes:
		if vote_en_cours.has(chiffre):
			vote_en_cours[chiffre] += votes[chiffre]
		else:
			vote_en_cours[chiffre] = votes[chiffre]
	print("[Game] Vote enregistré ! Total des votes agrégés : ", vote_en_cours)

# ── Le site a envoyé CLIC → ignore si chrono en attente ────────────────────
func _sur_lancer_roue_web() -> void:
	if not en_deplacement and not chrono_actif and not boss_vote_actif:
		if roue_instance.visible:
			var noeud_roue: Node2D = roue_instance.get_node("Node2D")
			noeud_roue.lancer_roue_depuis_web()

# ═══════════════════════════════════════════════════════════════════════════
# Gestion du chrono temps réel
# ═══════════════════════════════════════════════════════════════════════════
var dernier_secondes_sauvegardees := 10

func _process(delta: float) -> void:
	# Chrono du tour normal
	if chrono_actif:
		temps_chrono -= delta
		var sec_int = ceili(temps_chrono)
		if sec_int != dernier_secondes_sauvegardees and sec_int >= 0:
			dernier_secondes_sauvegardees = sec_int
			_sauvegarder_partie()
		if temps_chrono <= 0.0:
			chrono_actif = false
			temp_label_chrono.visible = false
			_declencher_roue()
		else:
			temp_label_chrono.text = str(sec_int)
	# Chrono du boss vote
	if boss_chrono_actif:
		boss_chrono_temps -= delta
		if boss_timer_lbl:
			boss_timer_lbl.text = str(ceili(max(boss_chrono_temps, 0.0)))
		_mettre_a_jour_pourcentages_boss()

func _declencher_roue() -> void:
	_montrer_roue()
	var noeud_roue: Node2D = roue_instance.get_node("Node2D")
	
	if vote_en_cours.is_empty():
		# Si aucun vote sur le téléphone, nombre aléatoire
		print("[Game] Aucun vote reçu pendant les 10s. Vote aléatoire appliqué.")
		vote_en_cours = { randi_range(1, 6): 1 }
		WebSocketServer.envoyer_message("TEMPS_ECOULE")
		
	noeud_roue.set_votes_depuis_web(vote_en_cours)
	noeud_roue.lancer_roue_depuis_web()

# ═══════════════════════════════════════════════════════════════════════════
# Construction du parcours (uniquement atlas 5,4 / 6,4 / 5,5 / 6,5)
# ═══════════════════════════════════════════════════════════════════════════
func _construire_parcours() -> void:
	const ATLAS_AUTORISES: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)
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

	var data : Dictionary = pions[tour_actuel]
	
	# 1. Mouvement initial avec le chiffre de la roue
	print("[%s] Résultat Roue : %+d" % [data["nom"], nb])
	await _deplacer_pion_relatif(data, nb)

	# 2. Vérification et application d'un éventuel effet de case spéciale
	var coords_actuelles = parcours[data["case"]]
	var atlas = layer_cases.get_cell_atlas_coords(coords_actuelles)
	
	if EFFETS_CASES.has(atlas):
		var effet = EFFETS_CASES[atlas]
		print("⚡ [%s] Tombe sur une case spéciale ! Effet : %+d" % [data["nom"], effet])
		await get_tree().create_timer(0.4).timeout
		await _deplacer_pion_relatif(data, effet, true)

	if data["case"] >= parcours.size() - 1:
		print("🏁 [%s] Arrive à la ligne d'ARRIVÉE ! Épreuve finale..." % data["nom"])
		var est_equipe_bot = (nb_joueurs_debut.get(tour_actuel, 0) == 0)
		
		# Les joueurs humains ont 3 tentatives, les bots seulement 1
		var nb_tentatives_max = 1 if est_equipe_bot else 3
		
		for t in range(nb_tentatives_max):
			if t > 0:
				print("🔄 [%s] Tentative %d..." % [data["nom"], t + 1])
				await get_tree().create_timer(1.5).timeout
			
			var gagne = await _sequence_portail(data)
			if gagne:
				break # Sort de la boucle si réussite (la redirection se fera dans _sequence_portail)
	else:
		# Pause respiratoire seulement si on n'est pas à l'arrivée
		await get_tree().create_timer(0.8).timeout

	# 3. Vérification UNIQUE du Boss ou Majestueux sur la position finale (après tous les effets)
	var atlas_final_pos = layer_cases.get_cell_atlas_coords(parcours[data["case"]])
	if atlas_final_pos == BOSS_TILE:
		print("💀 [%s] Tombe sur la case DOOKEY BOSS !" % data["nom"])
		await _sequence_dookey_boss(data)
	elif atlas_final_pos == MAJESTUEUX_TILE:
		print("👑 [%s] Tombe sur la case DOOKEY MAJESTUEUX !" % data["nom"])
		await _sequence_dookey_majestueux(data)
	elif atlas_final_pos == PORTAIL_TILE:
		print("🌀 [%s] Entre dans le PORTAIL VIOLET !" % data["nom"])
		await _sequence_portail(data)
		# On laisse la rotation de tour normale se produire à la fin d'avancer_pion

	en_deplacement = false

	
	# 4. Vérifier si la tuile finale est une case "Rejoue" (vert)
	#    Note : on re-lit l'atlas car _appliquer_malus_boss peut avoir déplacé le pion
	var atlas_final = layer_cases.get_cell_atlas_coords(parcours[data["case"]])
	
	if atlas_final == Vector2i(0, 1):
		print("🔄 [%s] Tombe sur la case Verte ! REJOUE SON TOUR !" % data["nom"])
		# On ne change pas tour_actuel, il garde la caméra et relance la roue
	else:
		# Fin normale du tour, passe au joueur suivant
		tour_actuel = (tour_actuel + 1) % pions.size()
		
	_sauvegarder_partie()
	
	_basculer_camera()
	_afficher_tour()
	_mettre_a_jour_hud()

func _deplacer_pion_relatif(data: Dictionary, nb: int, en_un_saut: bool = false) -> void:
	var case_depart : int = data["case"]
	var case_cible : int = clampi(case_depart + nb, 0, parcours.size() - 1)
	
	if case_cible == case_depart:
		return
		
	if en_un_saut:
		# Saut direct à l'arrivée en passant par-dessus le décor
		data["case"] = case_cible
		await _animer_saut_pion(tour_actuel, case_cible)
		_mettre_a_jour_hud()
	else:
		# Avancer case par case avec compte à rebours
		var total_steps : int = abs(case_cible - case_depart)
		var step_count  : int = total_steps
		hud_label_steps.text = str(step_count)

		if case_cible > case_depart:
			for idx in range(case_depart + 1, case_cible + 1):
				data["case"] = idx
				await _animer_pion(tour_actuel, idx)
				_mettre_a_jour_hud()   # met à jour hud_label + hud_label_steps
				step_count -= 1
				# Override : afficher le compte à rebours tant qu'il reste des pas
				if step_count > 0:
					hud_label_steps.text = str(step_count)
			
		# Reculer case par case avec compte à rebours
		elif case_cible < case_depart:
			for idx in range(case_depart - 1, case_cible - 1, -1):
				data["case"] = idx
				await _animer_pion(tour_actuel, idx)
				_mettre_a_jour_hud()
				step_count -= 1
				# Override : afficher le compte à rebours tant qu'il reste des pas
				if step_count > 0:
					hud_label_steps.text = str(step_count)

		hud_label_steps.text = "" # Effacer à la fin du mouvement

# ───────────────────────────────────────────────────────────────────────────
# ANIMATIONS DE DÉPLACEMENT
# ───────────────────────────────────────────────────────────────────────────
func _animer_saut_pion(index_pion: int, index_case: int) -> void:
	var pion_node  : Node2D   = pions[index_pion]["node"]
	var coord      : Vector2i = parcours[index_case]
	var pos_locale : Vector2  = layer_cases.map_to_local(coord)
	var pos_cible  : Vector2  = layer_cases.to_global(pos_locale) + OFFSET_PION

	var pos_depart = pion_node.global_position
	var distance = pos_depart.distance_to(pos_cible)
	var hauteur = max(100.0, distance * 0.25) # Moins haut, plus ras du sol (minimum 100px)

	# Fonction lambda pour calculer la courbe du saut en temps réel (Parabole)
	var arc_saut = func(t: float):
		var pos_base = pos_depart.lerp(pos_cible, t) # Trajectoire droite au sol
		var offset_y = 4.0 * hauteur * t * (1.0 - t) # Formule parabole parfaite
		pion_node.global_position = pos_base - Vector2(0, offset_y) # -y car Godot a le y vers le bas
		
	# Animation de saut en arc
	var tw := create_tween()
	tw.tween_method(arc_saut, 0.0, 1.0, 1.4) # Durée du bond (plus lent, flottant)
	
	# Petit effet de zoom proportionnel à la VRAIE taille du pion (pour éviter le bug géant)
	var base_scale = pion_node.scale
	var tw_scale = create_tween()
	tw_scale.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_scale.tween_property(pion_node, "scale", base_scale * 1.5, 0.7)
	tw_scale.tween_property(pion_node, "scale", base_scale, 0.7)
	
	await tw.finished
	pion_node.scale = base_scale # Sécurité pour être sûr qu'il redescend

# ───────────────────────────────────────────────────────────────────────────
# HOT RELOAD / SAUVEGARDE
# ───────────────────────────────────────────────────────────────────────────
func _sauvegarder_partie() -> void:
	if OS.has_feature("web"):
		var cases = []
		for p in pions:
			cases.append(p["case"])
		var donnees = { 
			"tour": tour_actuel, 
			"cases": cases,
			"chrono": temps_chrono,
			"chrono_actif": chrono_actif,
			"votes": vote_en_cours
		}
		var json_str = JSON.stringify(donnees)
		JavaScriptBridge.eval("window.sessionStorage.setItem('dookeyGameState', '%s');" % json_str)

func _restaurer_partie() -> void:
	if OS.has_feature("web"):
		var save_str = JavaScriptBridge.eval("window.sessionStorage.getItem('dookeyGameState');")
		if save_str and save_str != "":
			est_restauration = true
			var dict = JSON.parse_string(save_str)
			if typeof(dict) == TYPE_DICTIONARY:
				tour_actuel = dict.get("tour", 0)
				temps_chrono = dict.get("chrono", 10.0)
				dernier_secondes_sauvegardees = ceili(temps_chrono)
				chrono_actif = dict.get("chrono_actif", false)
				vote_en_cours = dict.get("votes", {})
				
				var cases_tab = dict.get("cases", [0, 0, 0, 0])
				for i in range(pions.size()):
					if i < cases_tab.size():
						pions[i]["case"] = cases_tab[i]
						_placer_pion(i, cases_tab[i])
				print("[game.gd] Restauration reussie ! Tour = %d, Chrono = %f" % [tour_actuel, temps_chrono])

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
	vote_en_cours.clear()
	_cacher_roue()
	# Envoyer NOUVEAU_TOUR immédiatement (les manettes en sont informées)
	var msg = "NOUVEAU_TOUR:%d:%s" % [tour_actuel, pions[tour_actuel]["nom"]]
	WebSocketServer.etat_courant = msg
	WebSocketServer.envoyer_message(msg)
	_mettre_a_jour_panel_equipes()
	# Banderole d'abord, puis suite selon bot ou humain
	await _animer_debut_tour(tour_actuel)

	if tour_actuel in equipes_bloquees_portail:
		print("[Portail] L'équipe est bloquée ! Déclenchement forcé du mini-jeu.")
		await _sequence_portail(pions[tour_actuel])
		
		# Après l'épreuve forcée, le tour s'arrête quoi qu'il arrive
		# (on ne lance pas la roue ce tour-ci)
		tour_actuel = (tour_actuel + 1) % pions.size()
		_sauvegarder_partie()
		_basculer_camera()
		_afficher_tour()
		_mettre_a_jour_hud()
		return

	var est_bot_tour : bool = (nb_joueurs_debut.get(tour_actuel, 0) == 0)

	if est_bot_tour:
		# BOT : pas de timer, pas de roue — lancer automatique 1-6
		var nb_bot := randi_range(1, 6)
		print("[BOT %s] Lance automatiquement : %d" % [pions[tour_actuel]["nom"], nb_bot])
		await _avancer_pion(nb_bot)
	else:
		# HUMAIN : démarrer le chrono normalement
		temps_chrono = 10.0
		chrono_actif = true
		temp_label_chrono.text = "10"
		temp_label_chrono.visible = true

func _reprendre_tour() -> void:
	print("─── Reprise à chaud du Tour de : %s ───" % pions[tour_actuel]["nom"])
	temp_label_chrono.text = str(ceili(temps_chrono))
	temp_label_chrono.visible = chrono_actif
	_cacher_roue()
	var msg = "NOUVEAU_TOUR:%d:%s" % [tour_actuel, pions[tour_actuel]["nom"]]
	WebSocketServer.etat_courant = msg
	# Les manettes reconnectées verront "NOUVEAU_TOUR" et pourront revoter si elles reconnectent. 
	WebSocketServer.envoyer_message(msg)

# ═══════════════════════════════════════════════════════════════════════════
# DOOKEY BOSS SÉQUENCE
# ═══════════════════════════════════════════════════════════════════════════
func _sequence_dookey_boss(data: Dictionary) -> void:
	# Arreter le chrono du tour en cours pour eviter tout conflit
	chrono_actif = false
	temp_label_chrono.visible = false
	
	# Cacher le sprite de la carte pendant la séquence géante
	var map_boss = get_node_or_null("DookeyBoss")
	if is_instance_valid(map_boss):
		map_boss.visible = false
	
	boss_votes = {0: 0, 1: 0}
	boss_vote_actif = true
	# Garde anti-double-connexion du signal
	if not WebSocketServer.boss_vote_recu.is_connected(_sur_boss_vote):
		WebSocketServer.boss_vote_recu.connect(_sur_boss_vote)
	WebSocketServer.envoyer_message("BOSS_EVENT")

	# 0. Lancer la musique du boss
	boss_audio_player = AudioStreamPlayer.new()
	boss_audio_player.stream = BOSS_AUDIO
	boss_audio_player.volume_db = -12.0
	add_child(boss_audio_player)
	boss_audio_player.play()

	_creer_boss_ui()

	# 1. Boss tombe du ciel
	var sw := get_viewport().get_visible_rect().size.x
	boss_sprite.position = Vector2(sw / 2.0 - 100.0, -260.0)
	var tw_entree = create_tween()
	tw_entree.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw_entree.tween_property(boss_sprite, "position:y", 20.0, 1.2)
	await tw_entree.finished
	
	# Shake camera on impact
	_secouer_camera(15.0, 0.5)

	# 2. Dialogue
	var dial_panel : PanelContainer = boss_sprite.get_parent().get_node_or_null("BossDialPanel")
	if dial_panel:
		dial_panel.get_child(0).text = BOSS_DIALOGUES[randi() % BOSS_DIALOGUES.size()]
		dial_panel.visible = true
		await get_tree().create_timer(2.8).timeout
		dial_panel.visible = false

	# 3. Afficher les cartes de vote
	boss_card_0.visible = true
	boss_card_1.visible = true
	boss_timer_lbl.visible = true

	# 4. Chrono 10 secondes (ou saut si c'est un bot)
	var est_bot : bool = (nb_joueurs_debut.get(tour_actuel, 0) == 0)
	boss_chrono_actif = true
	boss_chrono_temps = 10.0
	
	if est_bot:
		boss_votes[0] = 1 # Le bot vote automatiquement pour le recul
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().create_timer(10.5).timeout  # +0.5s de marge
		
	boss_chrono_actif = false
	boss_timer_lbl.visible = false

	# 5. Trouver le gagnant
	var gagnant := 0
	if boss_votes[0] + boss_votes[1] == 0:
		gagnant = randi() % 2
		print("[Boss] Aucun vote - choix aléatoire : option ", gagnant)
	elif boss_votes[1] > boss_votes[0]:
		gagnant = 1
	
	# Correction anticipée : si option 1 a gagné mais l'équipe est vide → fallback option 0
	if gagnant == 1:
		var membres_check := []
		for pseudo in WebSocketServer.equipes:
			if WebSocketServer.equipes[pseudo] == tour_actuel:
				membres_check.append(pseudo)
		if membres_check.is_empty():
			print("[Boss] Option 1 annulée (équipe vide) → Forçage sur option 0 (recul).")
			gagnant = 0

	# 6. Illuminer en vert la carte gagnante
	_illuminer_carte_boss(gagnant)
	WebSocketServer.envoyer_message("BOSS_RESULT:" + str(gagnant))
	await get_tree().create_timer(2.5).timeout

	# 7. Appliquer le malus (AWAIT obligatoire : contient des await internes)
	await _appliquer_malus_boss(gagnant, data)

	# 8. Boss repart dans le ciel
	boss_card_0.visible = false
	boss_card_1.visible = false
	var tw_sortie = create_tween()
	tw_sortie.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw_sortie.tween_property(boss_sprite, "position:y", -350.0, 0.9)
	await tw_sortie.finished

	# 9. Couper la musique en douceur
	if is_instance_valid(boss_audio_player):
		var tw_audio = create_tween()
		tw_audio.tween_property(boss_audio_player, "volume_db", -40.0, 0.8)
		tw_audio.chain().tween_callback(boss_audio_player.queue_free)
		boss_audio_player = null

	# 10. Nettoyage
	WebSocketServer.envoyer_message("BOSS_END")
	if WebSocketServer.boss_vote_recu.is_connected(_sur_boss_vote):
		WebSocketServer.boss_vote_recu.disconnect(_sur_boss_vote)
	
	boss_layer.queue_free()
	boss_layer = null
	boss_overlay = null
	boss_sprite = null
	boss_card_0 = null
	boss_card_1 = null
	boss_pct_0 = null
	boss_pct_1 = null
	boss_timer_lbl = null
	boss_vote_actif = false
	
	# Réafficher le sprite sur la carte une fois l'événement fini
	var map_boss_fin = get_node_or_null("DookeyBoss")
	if is_instance_valid(map_boss_fin):
		map_boss_fin.visible = true

# ═══════════════════════════════════════════════════════════════════════════
# PORTAIL VIOLET SÉQUENCE
# ═══════════════════════════════════════════════════════════════════════════
# PORTAIL VIOLET SÉQUENCE
# ═══════════════════════════════════════════════════════════════════════════
func _sequence_portail(data: Dictionary) -> bool:
	# Arrêter les chronos
	chrono_actif = false
	temp_label_chrono.visible = false
	
	portail_votes = {"success": 0, "fail": 0, "pseudos": []}
	portail_actif = true
	WebSocketServer.envoyer_message("PORTAIL_QTE_START")
	
	# Afficher un petit chrono ou message
	hud_label.text = "ÉPREUVE DU PORTAIL EN COURS..."
	
	var est_bot = (nb_joueurs_debut.get(tour_actuel, 0) == 0)

	# Attendre (plus court pour les bots)
	if est_bot:
		await get_tree().create_timer(2.0).timeout
	else:
		await get_tree().create_timer(8.0).timeout
	
	portail_actif = false
	WebSocketServer.envoyer_message("PORTAIL_QTE_END")
	
	# Calcul du résultat
	var total_votes = portail_votes["success"] + portail_votes["fail"]
	var a_gagne = false
	
	if est_bot:
		# Bot : 10% de chance de gagner
		a_gagne = (randf() < 0.1)
		print("[Portail] Résultat BOT : ", "GAGNÉ" if a_gagne else "ÉCHEC")
	else:
		if total_votes == 0:
			# Si personne n'a cliqué, on considère un échec
			a_gagne = false
		else:
			# Gagne si 50% ou plus de réussite
			a_gagne = (float(portail_votes["success"]) / float(total_votes)) >= 0.5
		
	if a_gagne:
		await _afficher_banderole_portail("GAGNÉ !")
		if tour_actuel in equipes_bloquees_portail:
			equipes_bloquees_portail.erase(tour_actuel)
		
		# Victoire immédiate si le mini-jeu est réussi !
		await _sequence_victoire(pions[tour_actuel]["nom"])
	else:
		await _afficher_banderole_portail("ÉCHEC !")
		if not tour_actuel in equipes_bloquees_portail:
			equipes_bloquees_portail.append(tour_actuel)
	
	return a_gagne

# ═══════════════════════════════════════════════════════════════════════════
# SÉQUENCE DE VICTOIRE FINALE
# ═══════════════════════════════════════════════════════════════════════════
func _sequence_victoire(gagnant_nom: String) -> void:
	# 1. Notifier tout le monde
	WebSocketServer.envoyer_message("GAME_WIN:" + gagnant_nom)
	chrono_actif = false
	
	# 2. UI plein écran
	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y
	
	var vic_layer = CanvasLayer.new()
	vic_layer.layer = 100
	add_child(vic_layer)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vic_layer.add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	bg.add_child(vbox)
	
	var lbl_vic = Label.new()
	lbl_vic.text = "VICTOIRE !"
	lbl_vic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_vic.add_theme_font_size_override("font_size", 120)
	lbl_vic.add_theme_color_override("font_color", Color.YELLOW)
	lbl_vic.add_theme_constant_override("outline_size", 20)
	lbl_vic.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(lbl_vic)
	
	var lbl_team = Label.new()
	lbl_team.text = gagnant_nom
	lbl_team.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_team.add_theme_font_size_override("font_size", 60)
	lbl_team.add_theme_color_override("font_color", Color.WHITE)
	lbl_team.add_theme_constant_override("outline_size", 10)
	lbl_team.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(lbl_team)
	
	var lbl_info = Label.new()
	lbl_info.text = "Retour au menu dans 10 secondes..."
	lbl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_info.add_theme_font_size_override("font_size", 24)
	vbox.add_child(lbl_info)
	
	# 3. Supprimer la sauvegarde pour permettre une nouvelle partie
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.sessionStorage.removeItem('dookeyGameState');")
	
	# 4. Attendre et rediriger
	await get_tree().create_timer(10.0).timeout
	get_tree().change_scene_to_file("res://Scenes/lobby.tscn")

func _sur_portail_qte_recu(succes: bool, pseudo: String) -> void:
	if not portail_actif: return
	if pseudo in portail_votes["pseudos"]: return # Un seul vote autorisé
	
	# Vérifier que le joueur appartient à l'équipe actuelle
	if WebSocketServer.equipes.has(pseudo) and WebSocketServer.equipes[pseudo] == tour_actuel:
		portail_votes["pseudos"].append(pseudo)
		if succes:
			portail_votes["success"] += 1
		else:
			portail_votes["fail"] += 1
		print("[Portail] Vote de %s : %s" % [pseudo, "SUCCESS" if succes else "FAIL"])

func _afficher_banderole_portail(texte: String) -> void:
	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y
	
	var layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	
	var rect = ColorRect.new()
	rect.color = Color(0, 0, 0, 0.7)
	rect.size = Vector2(sw, 150)
	rect.position = Vector2(0, (sh - 150) / 2.0)
	layer.add_child(rect)
	
	var lbl = Label.new()
	lbl.text = texte
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 80)
	lbl.add_theme_color_override("font_color", Color.GREEN if "GAGNÉ" in texte else Color.RED)
	lbl.add_theme_constant_override("outline_size", 15)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	rect.add_child(lbl)
	
	await get_tree().create_timer(2.0).timeout
	layer.queue_free()

# ═══════════════════════════════════════════════════════════════════════════
# DOOKEY MAJESTUEUX SÉQUENCE
# ═══════════════════════════════════════════════════════════════════════════
func _sequence_dookey_majestueux(data: Dictionary) -> void:
	chrono_actif = false
	temp_label_chrono.visible = false
	
	maj_votes.clear()
	maj_vote_actif = true
	var est_bot : bool = (nb_joueurs_debut.get(tour_actuel, 0) == 0)
	
	if not WebSocketServer.majestueux_vote_recu.is_connected(_sur_majestueux_vote):
		WebSocketServer.majestueux_vote_recu.connect(_sur_majestueux_vote)
	
	# Réutiliser l'UI du Boss
	_creer_boss_ui()
	boss_sprite.texture = MAJ_TEXTURE
	
	maj_audio_player = AudioStreamPlayer.new()
	maj_audio_player.stream = MAJ_AUDIO
	maj_audio_player.volume_db = -5.0
	add_child(maj_audio_player)
	maj_audio_player.play(124.0)
	
	WebSocketServer.envoyer_message("MAJESTUEUX_EVENT_1")
	
	# Modifier les cartes pour les options majestueuses
	var vb0 = boss_card_0.get_node("VBox")
	vb0.get_child(0).text = "Avancer de 10 cases"
	vb0.get_child(1).text = "Propulse le pion en avant sans danger."
	var s0 = boss_card_0.get_theme_stylebox("panel", "PanelContainer") as StyleBoxFlat
	s0.bg_color = Color(0.0, 0.2, 0.4, 0.9)
	s0.border_color = Color(0.0, 0.8, 1.0, 0.8)
	
	var vb1 = boss_card_1.get_node("VBox")
	vb1.get_child(0).text = "Punir un adversaire"
	vb1.get_child(1).text = "Élimine 10% des joueurs d'une cible."
	var s1 = boss_card_1.get_theme_stylebox("panel", "PanelContainer") as StyleBoxFlat
	s1.bg_color = Color(0.0, 0.2, 0.4, 0.9)
	s1.border_color = Color(0.0, 0.8, 1.0, 0.8)
	
	# Animation d'entrée
	var sw := get_viewport().get_visible_rect().size.x
	boss_sprite.position = Vector2(sw / 2.0 - 100.0, -260.0)
	var tw_entree = create_tween()
	tw_entree.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_entree.tween_property(boss_sprite, "position:y", 20.0, 1.8)
	await tw_entree.finished
	
	# Dialogue
	var dial_panel : PanelContainer = boss_sprite.get_parent().get_node_or_null("BossDialPanel")
	if dial_panel:
		dial_panel.get_child(0).text = MAJ_DIALOGUES[randi() % MAJ_DIALOGUES.size()]
		dial_panel.visible = true
		await get_tree().create_timer(3.0).timeout
		dial_panel.visible = false
	
	boss_card_0.visible = true
	boss_card_1.visible = true
	boss_timer_lbl.visible = true
	
	# PHASE 1 : Vote
	boss_chrono_actif = true
	boss_chrono_temps = 10.0
	maj_votes = {0: 0, 1: 0}
	
	if est_bot:
		maj_votes[0] = 1
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().create_timer(10.5).timeout
	
	boss_chrono_actif = false
	boss_timer_lbl.visible = false
	
	var gagnant_ph1 := 0
	if maj_votes[0] + maj_votes.get(1,0) == 0:
		gagnant_ph1 = randi() % 2
	elif maj_votes.get(1,0) > maj_votes[0]:
		gagnant_ph1 = 1
	
	WebSocketServer.envoyer_message("MAJESTUEUX_RESULT:" + str(gagnant_ph1))
	_illuminer_carte_boss(gagnant_ph1)
	await get_tree().create_timer(2.0).timeout
	
	if gagnant_ph1 == 0:
		# Bénédiction +10 
		boss_card_0.visible = false
		boss_card_1.visible = false
		_sortie_majestueux()
		await get_tree().create_timer(1.0).timeout
		var case_avant = data["case"]
		await _deplacer_pion_relatif(data, 10, true)
		if case_avant == data["case"]:
			print("[Majestueux] Pion n'a pas bougé (déjà à la fin ?)")
	else:
		# PHASE 2 : Ciblage
		boss_card_0.visible = false
		boss_card_1.visible = false
		
		var cibles = []
		var strings_ui = []
		for i in range(4):
			if i != tour_actuel:
				cibles.append(i)
				strings_ui.append(str(i) + "=" + noms_equipes[i])
		
		if cibles.is_empty():
			_sortie_majestueux()
			await get_tree().create_timer(1.0).timeout
			return
			
		WebSocketServer.envoyer_message("MAJESTUEUX_EVENT_2:" + "|".join(strings_ui))
		
		if dial_panel:
			dial_panel.get_child(0).text = "Regardez vos manettes pour choisir l'équipe cible !"
			dial_panel.visible = true
			
		maj_votes.clear()
		for c in cibles:
			maj_votes[c] = 0
			
		boss_timer_lbl.visible = true
		boss_chrono_actif = true
		boss_chrono_temps = 10.0
		
		if est_bot:
			maj_votes[cibles[randi() % cibles.size()]] = 1
			await get_tree().create_timer(1.0).timeout
		else:
			await get_tree().create_timer(10.5).timeout
		
		boss_chrono_actif = false
		boss_timer_lbl.visible = false
		
		var cible_elue = cibles[0]
		var max_v = -1
		for c in cibles:
			if maj_votes[c] > max_v:
				max_v = maj_votes[c]
				cible_elue = c
				
		WebSocketServer.envoyer_message("MAJESTUEUX_RESULT:" + str(cible_elue))
		
		if dial_panel:
			dial_panel.get_child(0).text = "L'équipe adverse subit la colère céleste !"
		
		await get_tree().create_timer(2.0).timeout
		
		WebSocketServer.envoyer_message("VIBRER_TOUS")
		await _eliminer_10_pourcent(cible_elue)
		
		if dial_panel: dial_panel.visible = false
		_sortie_majestueux()

func _sortie_majestueux() -> void:
	var tw_sortie = create_tween()
	tw_sortie.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw_sortie.tween_property(boss_sprite, "position:y", -350.0, 1.2)
	await tw_sortie.finished
	
	if is_instance_valid(maj_audio_player):
		var tw_audio = create_tween()
		tw_audio.tween_property(maj_audio_player, "volume_db", -40.0, 0.8)
		tw_audio.chain().tween_callback(maj_audio_player.queue_free)
		maj_audio_player = null
		
	WebSocketServer.envoyer_message("MAJESTUEUX_END")
	if WebSocketServer.majestueux_vote_recu.is_connected(_sur_majestueux_vote):
		WebSocketServer.majestueux_vote_recu.disconnect(_sur_majestueux_vote)

	
	if is_instance_valid(boss_layer):
		boss_layer.queue_free()
	boss_layer = null
	boss_overlay = null
	boss_sprite = null
	boss_card_0 = null
	boss_card_1 = null
	boss_timer_lbl = null
	maj_vote_actif = false

func _sur_majestueux_vote(option: int, pseudo: String) -> void:
	if not maj_vote_actif: return
	if WebSocketServer.equipes.get(pseudo, -1) != tour_actuel: return
	
	if maj_votes.has(option):
		maj_votes[option] += 1
		print("[Majestueux] +1 vote pour option %d" % option)


func _creer_boss_ui() -> void:

	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y

	# Créer le BossLayer au dessus du HUD
	boss_layer = CanvasLayer.new()
	boss_layer.layer = 20
	add_child(boss_layer)

	# Overlay sombre
	var bg = ColorRect.new()
	bg.name = "BossOverlay"
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_layer.add_child(bg)
	boss_overlay = bg

	# Sprite Boss
	boss_sprite = TextureRect.new()
	boss_sprite.texture = BOSS_TEXTURE
	boss_sprite.custom_minimum_size = Vector2(200, 200)
	boss_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boss_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boss_sprite.set_anchors_preset(Control.PRESET_TOP_LEFT)
	boss_sprite.position = Vector2(sw / 2.0 - 100.0, -260.0)
	boss_layer.add_child(boss_sprite)

	# Dialogue
	var dial_panel = PanelContainer.new()
	dial_panel.name = "BossDialPanel"
	var dstyle = StyleBoxFlat.new()
	dstyle.bg_color = Color(0.05, 0.05, 0.05, 1.0) # Obsidian
	dstyle.border_width_bottom = 5
	dstyle.border_color = Color(0.9, 0.0, 0.1) # Crimson
	dstyle.shadow_size = 20
	dstyle.shadow_color = Color(0, 0, 0, 0.8)
	dstyle.corner_radius_top_left = 12
	dstyle.corner_radius_top_right = 12
	dstyle.corner_radius_bottom_left = 12
	dstyle.corner_radius_bottom_right = 12
	dstyle.set_content_margin_all(20)
	dial_panel.add_theme_stylebox_override("panel", dstyle)
	dial_panel.set_anchors_preset(Control.PRESET_TOP_LEFT) # Force Top-Left anchors for manual position
	dial_panel.position = Vector2(sw / 2.0 - 220.0, 240.0)
	dial_panel.custom_minimum_size = Vector2(440, 0)
	var dial_lbl = Label.new()
	dial_lbl.text = ""
	dial_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dial_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dial_lbl.add_theme_font_size_override("font_size", 22)
	dial_lbl.add_theme_color_override("font_color", Color.WHITE)
	dial_lbl.add_theme_constant_override("outline_size", 4)
	dial_lbl.add_theme_color_override("font_outline_color", Color(0.5, 0.0, 0.8))
	dial_panel.add_child(dial_lbl)
	dial_panel.visible = false
	boss_layer.add_child(dial_panel)
	dial_panel.move_to_front() # Ensure it's on top of ORange/Gray

	# Cartes de vote (centrées)
	var cx := sw / 2.0
	var cy := sh / 2.0 + 60.0

	boss_card_0 = _creer_carte_boss(
		" Reculer de 10 cases ",
		"Le pion recule de 10 cases en arrière.",
		Color(0.6, 0.0, 0.0), Vector2(cx - 320.0, cy - 80.0)
	)
	boss_card_0.visible = false
	boss_layer.add_child(boss_card_0)
	boss_card_0.move_to_front()
	boss_pct_0 = boss_card_0.get_node("VBox/Pct")

	boss_card_1 = _creer_carte_boss(
		" Perdre 10% de l'équipe ",
		"10% des joueurs de l'équipe sont éliminés du vote.",
		Color(0.6, 0.0, 0.0), Vector2(cx + 20.0, cy - 80.0) # Red theme like Card 0
	)
	boss_card_1.visible = false
	boss_layer.add_child(boss_card_1)
	boss_card_1.move_to_front()
	boss_pct_1 = boss_card_1.get_node("VBox/Pct")

	# Timer
	boss_timer_lbl = Label.new()
	boss_timer_lbl.text = "10"
	boss_timer_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	boss_timer_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_timer_lbl.offset_bottom = -20
	boss_timer_lbl.offset_top   = -80
	boss_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_timer_lbl.add_theme_font_size_override("font_size", 50)
	boss_timer_lbl.add_theme_color_override("font_color", Color.WHITE)
	boss_timer_lbl.add_theme_constant_override("outline_size", 8)
	boss_timer_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	boss_timer_lbl.visible = false
	boss_layer.add_child(boss_timer_lbl)
	boss_timer_lbl.move_to_front()

func _creer_carte_boss(titre: String, desc: String, couleur: Color, pos: Vector2) -> PanelContainer:
	var pan = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = couleur.darkened(0.3)
	st.border_color = couleur
	st.border_width_bottom = 4
	st.border_width_top = 4
	st.border_width_left = 4
	st.border_width_right = 4
	st.corner_radius_top_left = 16
	st.corner_radius_top_right = 16
	st.corner_radius_bottom_left = 16
	st.corner_radius_bottom_right = 16
	st.set_content_margin_all(20)
	pan.add_theme_stylebox_override("panel", st)
	pan.position = pos
	pan.custom_minimum_size = Vector2(280, 160)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	pan.add_child(vbox)

	var lbl_titre = Label.new()
	lbl_titre.text = titre
	lbl_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_titre.add_theme_font_size_override("font_size", 20)
	lbl_titre.add_theme_color_override("font_color", Color.WHITE)
	var ls = LabelSettings.new()
	ls.font_size = 20
	ls.outline_size = 5
	ls.outline_color = Color.BLACK
	lbl_titre.label_settings = ls
	vbox.add_child(lbl_titre)

	var lbl_desc = Label.new()
	lbl_desc.text = desc
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_desc.add_theme_font_size_override("font_size", 14)
	lbl_desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(lbl_desc)

	var lbl_pct = Label.new()
	lbl_pct.name = "Pct"
	lbl_pct.text = "0%"
	lbl_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_pct.add_theme_font_size_override("font_size", 32)
	lbl_pct.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))  # vert
	vbox.add_child(lbl_pct)

	pan.set_anchors_preset(Control.PRESET_TOP_LEFT) # Important pour que 'pos' soit absolu
	pan.position = pos

	return pan

func _mettre_a_jour_pourcentages_boss() -> void:
	if not boss_pct_0 or not boss_pct_1:
		return
	var total : int = boss_votes[0] + boss_votes[1]
	if total == 0:
		boss_pct_0.text = "0%"
		boss_pct_1.text = "0%"
	else:
		boss_pct_0.text = str(roundi(boss_votes[0] * 100.0 / total)) + "%"
		boss_pct_1.text = str(roundi(boss_votes[1] * 100.0 / total)) + "%"

func _illuminer_carte_boss(gagnant: int) -> void:
	var carte_win : PanelContainer = boss_card_0 if gagnant == 0 else boss_card_1
	var carte_lose: PanelContainer = boss_card_1 if gagnant == 0 else boss_card_0
	var st_win = StyleBoxFlat.new()
	st_win.bg_color = Color(0.1, 0.6, 0.1)
	st_win.border_color = Color(0.2, 1.0, 0.2)
	st_win.border_width_bottom = 6
	st_win.border_width_top = 6
	st_win.border_width_left = 6
	st_win.border_width_right = 6
	st_win.corner_radius_top_left = 16
	st_win.corner_radius_top_right = 16
	st_win.corner_radius_bottom_left = 16
	st_win.corner_radius_bottom_right = 16
	st_win.set_content_margin_all(20)
	carte_win.add_theme_stylebox_override("panel", st_win)
	var st_lose = StyleBoxFlat.new()
	st_lose.bg_color = Color(0.15, 0.15, 0.15)
	st_lose.border_color = Color(0.3, 0.3, 0.3)
	st_lose.border_width_bottom = 4
	st_lose.border_width_top = 4
	st_lose.border_width_left = 4
	st_lose.border_width_right = 4
	st_lose.corner_radius_top_left = 16
	st_lose.corner_radius_top_right = 16
	st_lose.corner_radius_bottom_left = 16
	st_lose.corner_radius_bottom_right = 16
	st_lose.set_content_margin_all(20)
	carte_lose.add_theme_stylebox_override("panel", st_lose)

func _appliquer_malus_boss(gagnant: int, data: Dictionary) -> void:
	if gagnant == 0:
		# Reculer de 10 cases
		print("[Boss] Malus appliqué : RECUL de 10 cases pour %s" % data["nom"])
		await _deplacer_pion_relatif(data, -10, true)
	else:
		# Perdre 10% de l'équipe
		var equipe_idx := tour_actuel
		var membres := []
		for pseudo in WebSocketServer.equipes:
			if WebSocketServer.equipes[pseudo] == equipe_idx:
				membres.append(pseudo)
		
		# Si aucun joueur dans l'équipe, le vote "10%" ne peut pas s'appliquer.
		# Fallback automatique vers le recul de 10 cases.
		if membres.is_empty() and nb_joueurs_debut.get(equipe_idx, 0) > 0:
			print("[Boss] Aucun joueur dans l'équipe %d — Fallback vers RECUL de 10 cases." % equipe_idx)
			await _deplacer_pion_relatif(data, -10, true)
			return
			
		await _eliminer_10_pourcent(equipe_idx)

func _eliminer_10_pourcent(equipe_idx: int) -> void:
	var membres := []
	for pseudo in WebSocketServer.equipes:
		if WebSocketServer.equipes[pseudo] == equipe_idx:
			membres.append(pseudo)
			
	var nb_elimines := ceili(membres.size() * 0.1)
	if nb_elimines == 0:
		print("[Elimination] Personne à éliminer pour l'équipe %d." % equipe_idx)
		return
		
	membres.shuffle()
	var victimes := []
	
	for i in range(mini(nb_elimines, membres.size())):
		var pseudo = membres[i]
		victimes.append(pseudo)
		WebSocketServer.equipes.erase(pseudo)
		print("[Elimination] Joueur éliminé : ", pseudo)
		# Notifier le joueur spécifiquement
		WebSocketServer.envoyer_message("ELIMINE:" + pseudo)
	
	# Séquence visuelle sur Godot
	await _sequence_visuelle_elimination(equipe_idx, victimes)
	
	# Si l'équipe (non-bot) n'a plus de joueurs → explosion du pion !
	var restants := 0
	for p in WebSocketServer.equipes:
		if WebSocketServer.equipes[p] == equipe_idx:
			restants += 1
	if restants == 0 and nb_joueurs_debut.get(equipe_idx, 0) > 0:
		await _exploser_pion(equipe_idx)
	
	# Synchroniser la liste globale des équipes avec le serveur Node
	WebSocketServer.notifier_mises_a_jour_equipes()
	_mettre_a_jour_panel_equipes()  # Mettre à jour le compteur d'équipe
	
	var msg_elim = "BOSS_ELIMINES:" + str(nb_elimines)
	WebSocketServer.envoyer_message(msg_elim)

# ───────────────────────────────────────────────────────────────────────────
# EFFETS VISUELS
# ───────────────────────────────────────────────────────────────────────────
func _secouer_camera(intensite: float, duree: float) -> void:
	var cam : Camera2D = pions[tour_actuel]["camera"]
	var pos_origine = cam.offset
	var tw = create_tween()
	var steps = 8
	for i in range(steps):
		var target_offset = Vector2(randf_range(-intensite, intensite), randf_range(-intensite, intensite))
		tw.tween_property(cam, "offset", target_offset, duree / float(steps))
		intensite *= 0.8 # Diminue l'intensité progressivement
	tw.tween_property(cam, "offset", pos_origine, 0.05)

func _sequence_visuelle_elimination(equipe_idx: int, pseudos: Array) -> void:
	if not boss_layer: return
	
	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y
	
	# 1. Bande de couleur
	var banner = ColorRect.new()
	var team_color = WebSocketServer.COULEURS_EQUIPES[equipe_idx]
	banner.color = team_color.darkened(0.2)
	banner.color.a = 0.9
	banner.custom_minimum_size = Vector2(sw, 150)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	boss_layer.add_child(banner)
	# S'assurer qu'il est bien au milieu (set_anchors_preset center met la position au milieu, - offset)
	banner.position = Vector2(0, sh / 2.0 - 75.0)

	var lbl_title = Label.new()
	lbl_title.text = WebSocketServer.NOMS_EQUIPES[equipe_idx].to_upper() + " - ÉLIMINATION"
	lbl_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl_title.offset_top = 10
	lbl_title.add_theme_font_size_override("font_size", 30)
	lbl_title.add_theme_color_override("font_color", Color.WHITE)
	lbl_title.add_theme_constant_override("outline_size", 8)
	lbl_title.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_child(lbl_title)

	# 2. Affichage séquentiel
	for pseudo in pseudos:
		var lbl_pseudo = Label.new()
		lbl_pseudo.text = pseudo
		# Utiliser FULL_RECT pour que l'alignement centré fonctionne sur toute la largeur de la bande
		lbl_pseudo.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl_pseudo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_pseudo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_pseudo.offset_top = 20 # Décalage pour ne pas chevaucher le titre
		lbl_pseudo.add_theme_font_size_override("font_size", 60)
		lbl_pseudo.add_theme_color_override("font_color", Color.WHITE)
		lbl_pseudo.add_theme_constant_override("outline_size", 12)
		lbl_pseudo.add_theme_color_override("font_outline_color", Color.BLACK)
		banner.add_child(lbl_pseudo)
		
		# Anim apparition
		lbl_pseudo.modulate.a = 0
		var tw = create_tween()
		tw.tween_property(lbl_pseudo, "modulate:a", 1.0, 0.4)
		await tw.finished
		await get_tree().create_timer(2.0).timeout # Plus long pour lire
		
		# Griser
		var tw_gray = create_tween()
		tw_gray.tween_property(lbl_pseudo, "modulate", Color(0.4, 0.4, 0.4, 0.8), 0.6)
		await tw_gray.finished
		await get_tree().create_timer(1.0).timeout # Pause sur le pseudo grisé
		lbl_pseudo.queue_free()

	await get_tree().create_timer(1.0).timeout # Pause finale sur la bande
	banner.queue_free()

func _sur_boss_vote(option: int, pseudo: String) -> void:
	if not boss_vote_actif:
		return
	
	# Vérifier si le joueur appartient à l'équipe qui joue ce tour
	if WebSocketServer.equipes.has(pseudo):
		var team_idx = WebSocketServer.equipes[pseudo]
		if team_idx == tour_actuel:
			boss_votes[option] += 1
			print("[Boss] Vote accepté de %s (Équipe %d) pour l'option %d | Scores : %s" % [pseudo, team_idx, option, str(boss_votes)])
		else:
			print("[Boss] Vote REJETÉ de %s (Équipe %d) - Seule l'équipe %d peut voter !" % [pseudo, team_idx, tour_actuel])
	else:
		print("[Boss] Vote REJETÉ de %s - Équipe inconnue." % pseudo)
# ═══════════════════════════════════════════════════════════════════════════
# PANNEAU ÉQUIPES (TOP-RIGHT HUD)
# ═══════════════════════════════════════════════════════════════════════════
func _initialiser_compteurs_equipes() -> void:
	nb_joueurs_debut = {0: 0, 1: 0, 2: 0, 3: 0}
	for pseudo in WebSocketServer.equipes:
		var idx = WebSocketServer.equipes[pseudo]
		nb_joueurs_debut[idx] = nb_joueurs_debut.get(idx, 0) + 1
	_creer_panel_equipes_hud()
	_mettre_a_jour_panel_equipes()

func _creer_panel_equipes_hud() -> void:
	panel_equipes_hud = PanelContainer.new()
	var pstyle = StyleBoxEmpty.new()
	panel_equipes_hud.add_theme_stylebox_override("panel", pstyle)
	panel_equipes_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel_equipes_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel_equipes_hud.grow_vertical = Control.GROW_DIRECTION_END
	panel_equipes_hud.offset_right = -15
	panel_equipes_hud.offset_top = 15

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel_equipes_hud.add_child(vbox)

	labels_equipes_hud.clear()
	for i in range(4):
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		vbox.add_child(lbl)
		labels_equipes_hud.append(lbl)

	hud_layer.add_child(panel_equipes_hud)

func _mettre_a_jour_panel_equipes() -> void:
	if not panel_equipes_hud:
		return
	for i in range(4):
		if i >= labels_equipes_hud.size():
			break
		var lbl : Label = labels_equipes_hud[i]
		# Compter les joueurs actuels dans l'équipe
		var nb_actuel := 0
		for pseudo in WebSocketServer.equipes:
			if WebSocketServer.equipes[pseudo] == i:
				nb_actuel += 1
		var nb_initial : int = nb_joueurs_debut.get(i, 0)
		var couleur_equipe : Color = WebSocketServer.COULEURS_EQUIPES[i]
		var nom_equipe : String = WebSocketServer.NOMS_EQUIPES[i]
		var compteur : String = "Bot" if nb_initial == 0 else "%d/%d" % [nb_actuel, nb_initial]
		if i == tour_actuel:
			# Équipe active : couleur vive + flèche
			lbl.add_theme_color_override("font_color", couleur_equipe.lightened(0.3))
			lbl.text = ">> %s  %s" % [nom_equipe, compteur]
		else:
			# Équipes inactives : blanc
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.text = "  %s  %s" % [nom_equipe, compteur]

# ═══════════════════════════════════════════════════════════════════════════
# ANIMATION DÉBUT DE TOUR (bande colorée avec les pseudos)
# ═══════════════════════════════════════════════════════════════════════════
func _animer_debut_tour(equipe_idx: int) -> void:
	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y
	var team_color : Color  = WebSocketServer.COULEURS_EQUIPES[equipe_idx]
	var team_name  : String = WebSocketServer.NOMS_EQUIPES[equipe_idx]

	# Collecter les pseudos actifs de l'équipe
	var membres : Array[String] = []
	for pseudo in WebSocketServer.equipes:
		if WebSocketServer.equipes[pseudo] == equipe_idx:
			membres.append(pseudo)

	var est_bot : bool = (nb_joueurs_debut.get(equipe_idx, 0) == 0)

	# Couche temporaire (en dessous du HUD boss, au dessus du HUD normal)
	var anim_layer = CanvasLayer.new()
	anim_layer.layer = 15
	add_child(anim_layer)

	# Bande colorée — toujours aux couleurs de l'équipe
	var strip_h : float = 110.0 if est_bot else 190.0
	var strip_alpha : float = 0.85
	var strip_color := Color(team_color.r, team_color.g, team_color.b, 0.0)

	var strip = ColorRect.new()
	strip.color = strip_color
	strip.size = Vector2(sw, strip_h)
	strip.position = Vector2(0.0, (sh - strip_h) / 2.0)
	anim_layer.add_child(strip)

	var tw_in = create_tween()
	tw_in.tween_property(strip, "color:a", strip_alpha, 0.35)
	await tw_in.finished

	# Nom de l'équipe (texte différent selon bot ou humain)
	var lbl_nom = Label.new()
	if est_bot:
		lbl_nom.text = team_name.to_upper() + " — TOUR DU BOT"
	else:
		lbl_nom.text = team_name.to_upper() + " — À VOUS DE JOUER !"
	lbl_nom.size = Vector2(sw, 55.0)
	lbl_nom.position = Vector2(0.0, 18.0 if not est_bot else 28.0)
	lbl_nom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_nom.add_theme_font_size_override("font_size", 28 if not est_bot else 22)
	lbl_nom.add_theme_color_override("font_color", Color.WHITE)
	lbl_nom.add_theme_constant_override("outline_size", 10)
	lbl_nom.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	strip.add_child(lbl_nom)

	# Pseudos actifs — seulement pour les équipes humaines
	var lbl_pseudos : Label = null
	if not est_bot:
		var texte_pseudos := ""
		if membres.is_empty():
			texte_pseudos = "(aucun joueur)"
		else:
			texte_pseudos = "  \u2022  ".join(membres)
		lbl_pseudos = Label.new()
		lbl_pseudos.text = texte_pseudos
		lbl_pseudos.size = Vector2(sw, 90.0)
		lbl_pseudos.position = Vector2(0.0, 88.0)
		lbl_pseudos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_pseudos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_pseudos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_pseudos.add_theme_font_size_override("font_size", 22)
		lbl_pseudos.add_theme_color_override("font_color", Color.WHITE)
		lbl_pseudos.add_theme_constant_override("outline_size", 7)
		lbl_pseudos.add_theme_color_override("font_outline_color", Color.BLACK)
		strip.add_child(lbl_pseudos)

	# Délai avant de disparaître (plus court pour les bots)
	await get_tree().create_timer(1.5 if est_bot else 3.0).timeout


	# Fade out
	var tw_out = create_tween()
	tw_out.tween_property(strip, "color:a", 0.0, 0.4)
	tw_out.parallel().tween_property(lbl_nom, "modulate:a", 0.0, 0.4)
	tw_out.parallel().tween_property(lbl_pseudos, "modulate:a", 0.0, 0.4)
	await tw_out.finished

	anim_layer.queue_free()

# ═══════════════════════════════════════════════════════════════════════════
# EXPLOSION DU PION (quand toute l’équipe est éliminée)
# ═══════════════════════════════════════════════════════════════════════════
func _exploser_pion(equipe_idx: int) -> void:
	var pion_node : Node2D = pions[equipe_idx]["node"]
	if not is_instance_valid(pion_node):
		return
	
	var base_scale  := pion_node.scale
	var team_color  : Color = WebSocketServer.COULEURS_EQUIPES[equipe_idx]
	var pos_monde   := pion_node.global_position
	
	# 1. Secousse caméra violente
	_secouer_camera(30.0, 0.7)
	
	# 2. Flashs de couleur rapides (orange → blanc, x3)
	var tw_flash = create_tween()
	for _f in range(4):
		tw_flash.tween_property(pion_node, "modulate", Color(2.0, 0.5, 0.0, 1.0), 0.06)
		tw_flash.tween_property(pion_node, "modulate", Color.WHITE, 0.06)
	
	# 3. Gonflement explosif
	var tw_big = create_tween()
	tw_big.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw_big.tween_property(pion_node, "scale", base_scale * 3.5, 0.22)
	await get_tree().create_timer(0.22).timeout
	
	# 4. Débris volants en world space (Polygon2D)
	var couleurs_debris : Array[Color] = [team_color, Color.ORANGE_RED, Color.YELLOW, Color.WHITE]
	for d in range(10):
		var taille : float = randf_range(7.0, 20.0)
		var debris = Polygon2D.new()
		debris.polygon = PackedVector2Array([
			Vector2(-taille, -taille), Vector2(taille, -taille),
			Vector2(taille,  taille),  Vector2(-taille,  taille)
		])
		debris.color = couleurs_debris[d % couleurs_debris.size()]
		debris.global_position = pos_monde
		debris.rotation = randf_range(0.0, TAU)
		get_parent().add_child(debris)
		
		var angle  := (float(d) / 10.0) * TAU + randf_range(-0.5, 0.5)
		var dist   := randf_range(90.0, 260.0)
		var target := pos_monde + Vector2(cos(angle), sin(angle)) * dist
		
		var tw_d = create_tween().set_parallel(true)
		tw_d.tween_property(debris, "global_position", target, 0.65)
		tw_d.tween_property(debris, "rotation", debris.rotation + randf_range(-TAU, TAU), 0.65)
		tw_d.tween_property(debris, "modulate:a", 0.0, 0.65)
		tw_d.chain().tween_callback(debris.queue_free)
	
	# 5. Rétrécissement et disparition du pion
	var tw_out = create_tween().set_parallel(true)
	tw_out.tween_property(pion_node, "scale", Vector2.ZERO, 0.35)
	tw_out.tween_property(pion_node, "modulate:a", 0.0, 0.35)
	await tw_out.finished
	
	# Le pion reste invisible pour le reste de la partie
	pion_node.visible = false
	print("[Équipe %d] Pion éliminé et explosé !" % equipe_idx)
