extends Control

var qr_texture   : TextureRect
var http_request : HTTPRequest
var code_label   : Label
var joueurs_label: Label
var liste_joueurs: Array[String] = []

func _ready() -> void:
	# Création de l'interface graphique dynamique
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	bg.add_child(vbox)
	
	var titre = Label.new()
	titre.text = "SALLE D'ATTENTE"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 36)
	vbox.add_child(titre)
	
	qr_texture = TextureRect.new()
	qr_texture.custom_minimum_size = Vector2(220, 220)
	qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(qr_texture)
	
	code_label = Label.new()
	code_label.text = "Connexion au serveur..."
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 48)
	code_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	vbox.add_child(code_label)
	
	var sous_titre = Label.new()
	sous_titre.text = "Scannez le QR Code ou entrez ce code sur le site"
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.add_theme_font_size_override("font_size", 18)
	vbox.add_child(sous_titre)
	
	joueurs_label = Label.new()
	joueurs_label.text = "0 joueur(s) connecté(s)\n"
	joueurs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joueurs_label.add_theme_font_size_override("font_size", 24)
	joueurs_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	vbox.add_child(joueurs_label)
	
	var start_label = Label.new()
	start_label.text = "\n[Appuyez sur ESPACE pour lancer le plateau]"
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(start_label)
	
	# Initialiser HTTPRequest pour télécharger le QR Code
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_sur_qr_telecharge)

	# Écoute des signaux du Websocket principal
	WebSocketServer.code_salle_recu.connect(_sur_code_salle_recu)
	WebSocketServer.joueur_rejoint.connect(_sur_joueur_rejoint)
	
	# Si le Websocket s'était déjà connecté (hyper rapide), on interroge le code directement !
	if WebSocketServer.code_salle_actuel != "":
		_sur_code_salle_recu(WebSocketServer.code_salle_actuel)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		# Destruction du lobby et lancement du vrai jeu
		get_tree().change_scene_to_file("res://Scenes/game.tscn")

func _sur_code_salle_recu(code: String) -> void:
	code_label.text = code
	
	var base_url = "https://dookey-h1if.onrender.com"
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol")
		if host and protocol:
			base_url = protocol + "//" + host
			
	var url_cible = base_url + "/controller?code=" + code
	var url_api = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=" + url_cible.uri_encode()
	http_request.request(url_api)

func _sur_qr_telecharge(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		if err == OK:
			qr_texture.texture = ImageTexture.create_from_image(image)

func _sur_joueur_rejoint(pseudo: String) -> void:
	liste_joueurs.append(pseudo)
	var liste_str = "\n".join(liste_joueurs)
	joueurs_label.text = "%d joueur(s) connecté(s)\n%s" % [liste_joueurs.size(), liste_str]
