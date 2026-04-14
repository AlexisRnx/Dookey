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
# Construit les noms d'équipes desde WebSocketServer.equipes
# ═══════════════════════════════════════════════════════════════════════════
func _construire_noms_equipes() -> void:
	var groupes : Array = [[], [], [], []]
	for pseudo in WebSocketServer.equipes:
		var idx : int = WebSocketServer.equipes[pseudo]
		if idx >= 0 and idx < 4:
			groupes[idx].append(pseudo)
	
	for i in range(4):
		var membres = groupes[i]
		if membres.is_empty():
			noms_equipes[i] = WebSocketServer.NOMS_EQUIPES[i] # Fallback si vide
		elif membres.size() == 1:
			noms_equipes[i] = membres[0]  # Solo : affiche le pseudo directement
		else:
			noms_equipes[i] = ", ".join(membres)  # Plusieurs : "Alice, Bob"

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
	if chrono_actif:
		temps_chrono -= delta
		
		# Sauvegarde constante synchronisée chaque seconde écoulée
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
	_sauvegarder_partie()
	
	_basculer_camera()
	_afficher_tour()
	_mettre_a_jour_hud()

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
