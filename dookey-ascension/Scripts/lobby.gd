extends Control

var qr_texture   : TextureRect
var http_request : HTTPRequest
var code_label   : Label
var lien_label   : Label
var joueurs_titre_label: Label
var joueurs_flow : HFlowContainer
var liste_joueurs: Array[String] = []

var page1_vbox: VBoxContainer
var page2_vbox: VBoxContainer
var equipes_grid: GridContainer

func _ready() -> void:
	# Fond de couleur unie (Ciel Bleu)
	var bg = ColorRect.new()
	bg.color = Color(0.55, 0.82, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	bg.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	var panel_global = PanelContainer.new()
	panel_global.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel_global.custom_minimum_size = Vector2(900, 0)
	var global_style = StyleBoxFlat.new()
	global_style.bg_color = Color(0.96, 0.92, 0.76, 1.0) # Sand / Light Dirt
	global_style.border_width_bottom = 6
	global_style.border_width_top = 6
	global_style.border_width_left = 6
	global_style.border_width_right = 6
	global_style.border_color = Color(0.55, 0.35, 0.15, 1.0) # Bark/Dirt Brown
	global_style.corner_radius_top_left = 12
	global_style.corner_radius_top_right = 12
	global_style.corner_radius_bottom_left = 12
	global_style.corner_radius_bottom_right = 12
	global_style.shadow_color = Color(0.2, 0.4, 0.6, 0.3)
	global_style.shadow_size = 0
	global_style.shadow_offset = Vector2(8, 8) # Hard crisp shadow
	global_style.content_margin_top = 8
	global_style.content_margin_bottom = 8
	global_style.content_margin_left = 20
	global_style.content_margin_right = 20
	panel_global.add_theme_stylebox_override("panel", global_style)
	vbox.add_child(panel_global)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_theme_constant_override("separation", 2)
	panel_global.add_child(inner_vbox)
	
	page1_vbox = VBoxContainer.new()
	page1_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page1_vbox.add_theme_constant_override("separation", 2)
	inner_vbox.add_child(page1_vbox)
	
	page2_vbox = VBoxContainer.new()
	page2_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page2_vbox.add_theme_constant_override("separation", 30)
	page2_vbox.hide()
	inner_vbox.add_child(page2_vbox)
	
	var titre = Label.new()
	titre.text = "SALLE D'ATTENTE"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	var titre_settings = LabelSettings.new()
	titre_settings.font_size = 46
	titre_settings.font_color = Color(1.0, 1.0, 1.0)
	titre_settings.outline_size = 8
	titre_settings.outline_color = Color(0.4, 0.2, 0.05) # Deep brown outline
	titre_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
	titre_settings.shadow_size = 0
	titre_settings.shadow_offset = Vector2(4, 4)
	titre.label_settings = titre_settings
	page1_vbox.add_child(titre)
	
	var qr_margin = MarginContainer.new()
	qr_margin.add_theme_constant_override("margin_top", 0)
	qr_margin.add_theme_constant_override("margin_bottom", 0)
	page1_vbox.add_child(qr_margin)
	
	var qr_bg = PanelContainer.new()
	var qr_style = StyleBoxFlat.new()
	qr_style.bg_color = Color.WHITE
	qr_style.border_width_bottom = 4
	qr_style.border_width_top = 4
	qr_style.border_width_left = 4
	qr_style.border_width_right = 4
	qr_style.border_color = Color(0.55, 0.35, 0.15)
	qr_style.corner_radius_top_left = 8
	qr_style.corner_radius_top_right = 8
	qr_style.corner_radius_bottom_left = 6
	qr_style.corner_radius_bottom_right = 6
	qr_bg.add_theme_stylebox_override("panel", qr_style)
	qr_bg.custom_minimum_size = Vector2(150, 150)
	qr_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var qr_center = CenterContainer.new()
	qr_bg.add_child(qr_center)
	qr_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	qr_texture = TextureRect.new()
	qr_texture.custom_minimum_size = Vector2(160, 160)
	qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_center.add_child(qr_texture)
	qr_margin.add_child(qr_bg)
	
	code_label = Label.new()
	code_label.text = "Connexion..."
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_color_override("font_color", Color.WHITE) 
	var code_settings = LabelSettings.new()
	code_settings.font_size = 40
	code_settings.font_color = Color(1.0, 0.85, 0.2) # Vibrant yellow/gold
	code_settings.outline_size = 8
	code_settings.outline_color = Color(0.4, 0.2, 0.05)
	code_label.label_settings = code_settings
	page1_vbox.add_child(code_label)
	
	lien_label = Label.new()
	lien_label.text = ""
	lien_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lien_label.add_theme_font_size_override("font_size", 20)
	lien_label.add_theme_color_override("font_color", Color(0.4, 0.2, 0.05))
	page1_vbox.add_child(lien_label)
	
	var sous_titre = Label.new()
	sous_titre.text = "Scannez le QR Code ou entrez l'adresse et le code sur votre navigateur"
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.add_theme_font_size_override("font_size", 16)
	sous_titre.add_theme_color_override("font_color", Color(0.5, 0.35, 0.2))
	page1_vbox.add_child(sous_titre)
	
	joueurs_titre_label = Label.new()
	joueurs_titre_label.text = "0 joueur(s) connecté(s)\n"
	joueurs_titre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joueurs_titre_label.add_theme_font_size_override("font_size", 24)
	joueurs_titre_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3)) # Grass green text
	page1_vbox.add_child(joueurs_titre_label)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 80)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	joueurs_flow = HFlowContainer.new()
	joueurs_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	joueurs_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joueurs_flow.add_theme_constant_override("h_separation", 10)
	joueurs_flow.add_theme_constant_override("v_separation", 10)
	
	scroll.add_child(joueurs_flow)
	page1_vbox.add_child(scroll)
	
	var btn_suivant = Button.new()
	btn_suivant.text = "SUIVANT"
	btn_suivant.add_theme_font_size_override("font_size", 24)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.3, 0.8, 0.3) # Bright Grass Green
	btn_style.border_width_bottom = 6
	btn_style.border_width_top = 4
	btn_style.border_width_left = 4
	btn_style.border_width_right = 4
	btn_style.border_color = Color(0.15, 0.5, 0.15) # Dark green border
	btn_style.corner_radius_top_left = 12
	btn_style.corner_radius_top_right = 12
	btn_style.corner_radius_bottom_left = 12
	btn_style.corner_radius_bottom_right = 12
	btn_style.shadow_color = Color(0.2, 0.4, 0.6, 0.2)
	btn_style.shadow_size = 0
	btn_style.shadow_offset = Vector2(4, 4)
	btn_style.content_margin_top = 5
	btn_style.content_margin_bottom = 5
	btn_style.content_margin_left = 20
	btn_style.content_margin_right = 20
	
	btn_suivant.add_theme_stylebox_override("normal", btn_style)
	btn_suivant.add_theme_color_override("font_color", Color.WHITE)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.4, 0.9, 0.4)
	btn_hover.border_color = Color(0.2, 0.6, 0.2)
	btn_suivant.add_theme_stylebox_override("hover", btn_hover)
	
	btn_suivant.pressed.connect(_afficher_page2)
	btn_suivant.custom_minimum_size = Vector2(300, 0)
	
	var btn_container = CenterContainer.new()
	var margin_btn = MarginContainer.new()
	margin_btn.add_theme_constant_override("margin_top", 0)
	margin_btn.add_child(btn_suivant)
	btn_container.add_child(margin_btn)
	page1_vbox.add_child(btn_container)
	
	# -------------- PAGE 2 (STYLE TABLEAU EQUIPES) --------------
	var titre2 = Label.new()
	titre2.text = "COMPOSITION DES ÉQUIPES"
	titre2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre2.label_settings = titre_settings
	page2_vbox.add_child(titre2)
	
	var p2_panel = PanelContainer.new()
	var p2_style = StyleBoxFlat.new()
	p2_style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	p2_style.corner_radius_top_left = 8
	p2_style.corner_radius_top_right = 8
	p2_style.corner_radius_bottom_left = 8
	p2_style.corner_radius_bottom_right = 8
	p2_style.content_margin_left = 20
	p2_style.content_margin_right = 20
	p2_style.content_margin_top = 20
	p2_style.content_margin_bottom = 20
	p2_panel.add_theme_stylebox_override("panel", p2_style)
	
	equipes_grid = GridContainer.new()
	equipes_grid.columns = 4
	equipes_grid.add_theme_constant_override("h_separation", 50)
	p2_panel.add_child(equipes_grid)
	page2_vbox.add_child(p2_panel)
	
	var btn_start = Button.new()
	btn_start.text = "COMMENCER LA PARTIE"
	btn_start.add_theme_font_size_override("font_size", 24)
	btn_start.add_theme_stylebox_override("normal", btn_style)
	btn_start.add_theme_color_override("font_color", Color.WHITE)
	btn_start.add_theme_stylebox_override("hover", btn_hover)
	btn_start.pressed.connect(_lancer_restauration_depuis_page2)
	btn_start.custom_minimum_size = Vector2(300, 0)
	
	var ct_start = CenterContainer.new()
	ct_start.add_child(btn_start)
	page2_vbox.add_child(ct_start)
	# -------------------------------------------------------------
	
	# Initialiser HTTPRequest pour télécharger le QR Code
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_sur_qr_telecharge)

	# Écoute des signaux du Websocket principal
	WebSocketServer.code_salle_recu.connect(_sur_code_salle_recu)
	WebSocketServer.joueur_rejoint.connect(_sur_joueur_rejoint)
	WebSocketServer.joueur_quitte.connect(_sur_joueur_quitte)
	
	# Si le Websocket s'était déjà connecté (hyper rapide), on interroge le code directement !
	if WebSocketServer.code_salle_actuel != "":
		_sur_code_salle_recu(WebSocketServer.code_salle_actuel)
		
	# HOT-START : Si on trouve une sauvegarde du plateau, on zappe le lobby !
	if OS.has_feature("web"):
		var save_str = JavaScriptBridge.eval("window.sessionStorage.getItem('dookeyGameState');")
		if save_str and save_str != "":
			print("[lobby.gd] Sauvegarde trouvée ! Reprise à chaud de la partie...")
			call_deferred("_lancer_restauration")

func _afficher_page2() -> void:
	# 1. Génère la répartition instantanément
	WebSocketServer.assigner_equipes(liste_joueurs)
	
	# 2. Envoyer immédiatement les équipes au serveur
	# → il enverra VOTRE_EQUIPE à chaque téléphone pour afficher la banderole
	var parts = []
	for pseudo in WebSocketServer.equipes:
		parts.append("%s=%d" % [pseudo.uri_encode(), WebSocketServer.equipes[pseudo]])
	if parts.size() > 0:
		WebSocketServer.envoyer_message("EQUIPES:" + ",".join(parts))
	
	# 2. Vider la grille précédente s'il y en avait une
	for child in equipes_grid.get_children():
		child.queue_free()
		
	# 3. Construire les colonnes
	for i in range(4):
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 10)
		
		var lbl_title = Label.new()
		lbl_title.text = WebSocketServer.NOMS_EQUIPES[i]
		lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var ls = LabelSettings.new()
		ls.font_size = 28
		ls.outline_size = 6
		ls.outline_color = Color.BLACK
		ls.font_color = WebSocketServer.COULEURS_EQUIPES[i]
		lbl_title.label_settings = ls
		vb.add_child(lbl_title)
		
		# Séparateur propre
		var sep = HSeparator.new()
		vb.add_child(sep)
		
		var cb_joueurs = 0
		for pseudo in WebSocketServer.equipes:
			if WebSocketServer.equipes[pseudo] == i:
				var lbl = Label.new()
				lbl.text = "• " + pseudo
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", 20)
				lbl.add_theme_color_override("font_color", Color.WHITE)
				vb.add_child(lbl)
				cb_joueurs += 1
				
		if cb_joueurs == 0:
			var lbl = Label.new()
			lbl.text = "---"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			vb.add_child(lbl)
			
		equipes_grid.add_child(vb)
		
	# 4. Basculer les pages
	page1_vbox.hide()
	page2_vbox.show()

func _lancer_restauration_depuis_page2() -> void:
	# Les équipes ont déjà été envoyées lors du clic sur "Suivant", on lance juste la scène
	get_tree().change_scene_to_file("res://Scenes/game.tscn")

func _lancer_restauration() -> void:
	# Utilisé par le Hot-Reload auto depuis l'éditeur
	WebSocketServer.assigner_equipes(liste_joueurs)
	_lancer_restauration_depuis_page2()

func _sur_code_salle_recu(code: String) -> void:
	code_label.text = code
	
	var base_url = "https://dookey-h1if.onrender.com"
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol")
		if host and protocol:
			base_url = protocol + "//" + host
			
	var url_cible = base_url + "/controller?code=" + code
	lien_label.text = "Adresse : " + base_url + "/controller"
	
	var url_api = "https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=" + url_cible.uri_encode()
	http_request.request(url_api)

func _sur_qr_telecharge(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		if err == OK:
			qr_texture.texture = ImageTexture.create_from_image(image)

func _sur_joueur_rejoint(pseudo: String) -> void:
	if pseudo in liste_joueurs:
		return
		
	liste_joueurs.append(pseudo)
	joueurs_titre_label.text = "%d joueur(s) connecté(s)\n" % liste_joueurs.size()
	
	var pan = PanelContainer.new()
	pan.name = "Joueur_" + pseudo.validate_node_name()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.76) # Sand color
	style.border_width_bottom = 4
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.55, 0.35, 0.15) # Brown dirt border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(12)
	pan.add_theme_stylebox_override("panel", style)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pan.add_child(vb)
	
	var lbl = Label.new()
	lbl.text = pseudo
	lbl.add_theme_color_override("font_color", Color.WHITE)
	var lbl_set = LabelSettings.new()
	lbl_set.font_size = 22
	lbl_set.outline_size = 6
	lbl_set.outline_color = Color(0.4, 0.2, 0.05)
	lbl.label_settings = lbl_set
	vb.add_child(lbl)
	
	# Badge équipe (affiché si équipes déjà assignées)
	var badge = Label.new()
	badge.name = "Badge"
	badge.text = "En attente..."
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badge_set = LabelSettings.new()
	badge_set.font_size = 14
	badge_set.font_color = Color(0.5, 0.35, 0.2)
	badge.label_settings = badge_set
	vb.add_child(badge)
	
	joueurs_flow.add_child(pan)

func _sur_joueur_quitte(pseudo: String) -> void:
	if pseudo in liste_joueurs:
		liste_joueurs.erase(pseudo)
		joueurs_titre_label.text = "%d joueur(s) connecté(s)\n" % liste_joueurs.size()
		
	var safe_name = "Joueur_" + pseudo.validate_node_name()
	var node = joueurs_flow.get_node_or_null(safe_name)
	if node:
		node.queue_free()
		joueurs_flow.remove_child(node)
