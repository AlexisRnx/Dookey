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
	if not en_deplacement and not chrono_actif:
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
		Vector2i(0, 2), Vector2i(1, 2)
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
	
	# Mouvement initial avec le chiffre de la roue
	print("[%s] Résultat Roue : %+d" % [data["nom"], nb])
	await _deplacer_pion_relatif(data, nb)

	# Vérification de la case d'arrivée pour déclencher un effet (ex: +3, -3)
	var coords_actuelles = parcours[data["case"]]
	var atlas = layer_cases.get_cell_atlas_coords(coords_actuelles)
	
	if EFFETS_CASES.has(atlas):
		var effet = EFFETS_CASES[atlas]
		print("⚡ [%s] Tombe sur une case spéciale ! Effet : %+d" % [data["nom"], effet])
		await get_tree().create_timer(0.4).timeout # Petite pause dramatique
		# Le pion fait un bond direct (en_un_saut = true)
		await _deplacer_pion_relatif(data, effet, true)

	if data["case"] >= parcours.size() - 1:
		print("🎉 %s a atteint l'arrivée !" % data["nom"])

	# Petite pause respiratoire pour voir le pion atterrir avant le changement de caméra
	await get_tree().create_timer(0.8).timeout

	# Vérifier si le pion tombe sur la case du BOSS
	var atlas_boss_check = layer_cases.get_cell_atlas_coords(parcours[data["case"]])
	if atlas_boss_check == BOSS_TILE:
		print("💀 [%s] Tombe sur la case DOOKEY BOSS !" % data["nom"])
		await _sequence_dookey_boss(data)

	en_deplacement = false
	
	# Vérifier la tuile FINAle (après les bonds) pour voir s'il rejoue
	var atlas_final = layer_cases.get_cell_atlas_coords(parcours[data["case"]])
	
	if atlas_final == Vector2i(0, 1):
		print("🔄 [%s] Tombe sur la case Verte ! REJOUE SON TOUR !" % data["nom"])
		# On ne change pas tour_actuel, il va garder la caméra et relancer la roue !
	else:
		# Fin normale du tour, passe au joueur suivant
		tour_actuel = (tour_actuel + 1) % pions.size()
		
	_sauvegarder_partie()
	
	_basculer_camera()
	_afficher_tour()
	_mettre_a_jour_hud()

func _deplacer_pion_relatif(data: Dictionary, nb: int, en_un_saut: bool = false) -> void:
	var case_depart = data["case"]
	var case_cible = clampi(case_depart + nb, 0, parcours.size() - 1)
	
	if case_cible == case_depart:
		return
		
	if en_un_saut:
		# Saut direct à l'arrivée en passant par-dessus le décor
		data["case"] = case_cible
		await _animer_saut_pion(tour_actuel, case_cible)
		_mettre_a_jour_hud()
	else:
		# Avancer case par case
		if case_cible > case_depart:
			for idx in range(case_depart + 1, case_cible + 1):
				data["case"] = idx
				await _animer_pion(tour_actuel, idx)
				_mettre_a_jour_hud()
				
		# Reculer case par case
		elif case_cible < case_depart:
			for idx in range(case_depart - 1, case_cible - 1, -1):
				data["case"] = idx
				await _animer_pion(tour_actuel, idx)
				_mettre_a_jour_hud()

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
	temps_chrono = 10.0
	chrono_actif = true
	temp_label_chrono.text = "10"
	temp_label_chrono.visible = true
	_cacher_roue()
	var msg = "NOUVEAU_TOUR:%d:%s" % [tour_actuel, pions[tour_actuel]["nom"]]
	WebSocketServer.etat_courant = msg
	WebSocketServer.envoyer_message(msg)

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
	boss_votes = {0: 0, 1: 0}
	boss_vote_actif = true
	WebSocketServer.boss_vote_recu.connect(_sur_boss_vote)
	WebSocketServer.envoyer_message("BOSS_EVENT")

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
		await get_tree().create_timer(5.0).timeout
		dial_panel.visible = false

	# 3. Afficher les cartes de vote
	boss_card_0.visible = true
	boss_card_1.visible = true
	boss_timer_lbl.visible = true

	# 4. Chrono 10 secondes
	boss_chrono_actif = true
	boss_chrono_temps = 10.0
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

	# 6. Illuminer en vert la carte gagnante
	_illuminer_carte_boss(gagnant)
	WebSocketServer.envoyer_message("BOSS_RESULT:" + str(gagnant))
	await get_tree().create_timer(2.5).timeout

	# 7. Appliquer le malus
	_appliquer_malus_boss(gagnant, data)

	# 8. Boss repart dans le ciel
	boss_card_0.visible = false
	boss_card_1.visible = false
	var tw_sortie = create_tween()
	tw_sortie.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw_sortie.tween_property(boss_sprite, "position:y", -350.0, 0.9)
	await tw_sortie.finished

	# 9. Nettoyage
	WebSocketServer.envoyer_message("BOSS_END")
	if WebSocketServer.boss_vote_recu.is_connected(_sur_boss_vote):
		WebSocketServer.boss_vote_recu.disconnect(_sur_boss_vote)
	boss_overlay.queue_free()
	boss_overlay = null
	boss_vote_actif = false

func _creer_boss_ui() -> void:
	var sw := get_viewport().get_visible_rect().size.x
	var sh := get_viewport().get_visible_rect().size.y

	# Overlay sombre
	var bg = ColorRect.new()
	bg.name = "BossOverlay"
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(bg)
	boss_overlay = bg

	# Sprite Boss
	boss_sprite = TextureRect.new()
	boss_sprite.texture = BOSS_TEXTURE
	boss_sprite.custom_minimum_size = Vector2(200, 200)
	boss_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	boss_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	boss_sprite.set_anchors_preset(Control.PRESET_TOP_LEFT)
	boss_sprite.position = Vector2(sw / 2.0 - 100.0, -260.0)
	hud_layer.add_child(boss_sprite)

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
	hud_layer.add_child(dial_panel)
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
	hud_layer.add_child(boss_card_0)
	boss_card_0.move_to_front()
	boss_pct_0 = boss_card_0.get_node("VBox/Pct")

	boss_card_1 = _creer_carte_boss(
		" Perdre 10% de l'équipe ",
		"10% des joueurs de l'équipe sont éliminés du vote.",
		Color(0.6, 0.0, 0.0), Vector2(cx + 20.0, cy - 80.0) # Red theme like Card 0
	)
	boss_card_1.visible = false
	hud_layer.add_child(boss_card_1)
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
	hud_layer.add_child(boss_timer_lbl)
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
		var nb_elimines := maxi(1, roundi(membres.size() * 0.1))
		membres.shuffle()
		for i in range(mini(nb_elimines, membres.size())):
			var pseudo = membres[i]
			WebSocketServer.equipes.erase(pseudo)
			print("[Boss] Joueur éliminé du vote : ", pseudo)
			# Notifier le joueur spécifiquement
			WebSocketServer.envoyer_message("ELIMINE:" + pseudo)
		
		# Synchroniser la liste globale des équipes avec le serveur Node
		WebSocketServer.notifier_mises_a_jour_equipes()
		
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

func _sur_boss_vote(option: int) -> void:
	if not boss_vote_actif:
		return
	boss_votes[option] += 1
	print("[Boss] Vote reçu - Option %d | Scores : %s" % [option, str(boss_votes)])
