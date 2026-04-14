extends Control

var qr_texture   : TextureRect
var http_request : HTTPRequest
var code_label   : Label
var lien_label   : Label
var joueurs_titre_label: Label
var joueurs_flow : HFlowContainer
var liste_joueurs: Array[String] = []

func _ready() -> void:
	# Création de l'interface graphique dynamique
	var bg = ColorRect.new()
	bg.color = Color(0.96, 0.96, 0.97, 1.0)
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
	
	var titre = Label.new()
	titre.text = "SALLE D'ATTENTE"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 32)
	titre.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	vbox.add_child(titre)
	
	qr_texture = TextureRect.new()
	qr_texture.custom_minimum_size = Vector2(160, 160)
	qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(qr_texture)
	
	code_label = Label.new()
	code_label.text = "Connexion..."
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 42)
	code_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2)) # Dark distinct text
	vbox.add_child(code_label)
	
	lien_label = Label.new()
	lien_label.text = ""
	lien_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lien_label.add_theme_font_size_override("font_size", 20)
	lien_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	vbox.add_child(lien_label)
	
	var sous_titre = Label.new()
	sous_titre.text = "Scannez le QR Code ou entrez l'adresse et le code sur votre navigateur"
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.add_theme_font_size_override("font_size", 16)
	sous_titre.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(sous_titre)
	
	joueurs_titre_label = Label.new()
	joueurs_titre_label.text = "0 joueur(s) connecté(s)\n"
	joueurs_titre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joueurs_titre_label.add_theme_font_size_override("font_size", 24)
	joueurs_titre_label.add_theme_color_override("font_color", Color(0.15, 0.45, 0.75))
	vbox.add_child(joueurs_titre_label)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 100) # Assure au moins 100px d'espace vital
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	joueurs_flow = HFlowContainer.new()
	joueurs_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	joueurs_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joueurs_flow.add_theme_constant_override("h_separation", 10)
	joueurs_flow.add_theme_constant_override("v_separation", 10)
	
	scroll.add_child(joueurs_flow)
	vbox.add_child(scroll)
	
	var btn_start = Button.new()
	btn_start.text = "COMMENCER LA PARTIE"
	btn_start.add_theme_font_size_override("font_size", 22)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.9, 0.3, 0.3)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn_style.set_content_margin_all(15)
	
	btn_start.add_theme_stylebox_override("normal", btn_style)
	btn_start.add_theme_color_override("font_color", Color.WHITE)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.95, 0.4, 0.4)
	btn_start.add_theme_stylebox_override("hover", btn_hover)
	
	btn_start.pressed.connect(_lancer_restauration)
	btn_start.custom_minimum_size = Vector2(300, 0)
	
	var btn_container = CenterContainer.new()
	btn_container.add_child(btn_start)
	vbox.add_child(btn_container)
	
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

func _lancer_restauration() -> void:
	get_tree().change_scene_to_file("res://Scenes/game.tscn")

func _sur_code_salle_recu(code: String) -> void:
	code_label.text = code
	
	var base_url = "https://dookey-h1if.onrender.com"
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol")
		if host and protocol:
			base_url = protocol + "//" + host
			
	lien_label.text = "Adresse : " + base_url + "/controller"
			
	var url_cible = base_url + "/controller?code=" + code
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
	style.bg_color = Color.WHITE
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.85, 0.85, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(10)
	pan.add_theme_stylebox_override("panel", style)
	
	var lbl = Label.new()
	lbl.text = pseudo
	lbl.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))
	lbl.add_theme_font_size_override("font_size", 20)
	pan.add_child(lbl)
	
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
