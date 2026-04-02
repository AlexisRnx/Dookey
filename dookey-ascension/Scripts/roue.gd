extends Node2D

# Émis quand la roue finit de tourner
signal resultat_roue(chiffre: int)

# Dictionnaire simulant les votes. Les valeurs peuvent être modifiées manuellement.
var votes_manuels = {
	1: 3,
	2: 2,
	3: 0,
	6: 5
}

var total_votes := 0
var donnees_portions := []
var en_rotation := false

# Palette de couleurs pour différencier les portions
var couleurs = [Color.CRIMSON, Color.ROYAL_BLUE, Color.FOREST_GREEN, Color.GOLD, Color.DARK_ORCHID, Color.DARK_ORANGE]

func _ready() -> void:
	# Centre automatiquement le nœud au milieu de l'écran visible
	position = get_viewport_rect().size / 2.0

	# ── Repositionne la flèche indicatrice au-dessus de la roue ─────────
	# Le Sprite2D est enfant du nœud RACINE (pas de ce Node2D),
	# donc il ne tourne pas avec la roue — parfait.
	var fleche: Sprite2D = get_parent().get_node_or_null("Sprite2D")
	if fleche:
		# La roue a un rayon de 200px ; on place la flèche légèrement au-dessus
		fleche.position = position + Vector2(0.0, -(200.0 + fleche.texture.get_height() * fleche.scale.y * 0.5 - 55.0))
		# Sens corrigé : 0° = texture dans son sens naturel (pointe vers le bas)
		fleche.rotation_degrees = 0.0

	_calculer_portions()
	queue_redraw()


# Étape 1 : Calculer la taille de chaque portion selon les votes
func _calculer_portions() -> void:
	total_votes = 0
	for v in votes_manuels.values():
		total_votes += v
		
	if total_votes == 0:
		return
		
	var angle_courant := 0.0
	var index_couleur := 0
	donnees_portions.clear()
	
	for chiffre in votes_manuels.keys():
		var votes_pour_chiffre = votes_manuels[chiffre]
		if votes_pour_chiffre > 0:
			var ratio = float(votes_pour_chiffre) / total_votes
			var angle_portion = ratio * TAU
			
			donnees_portions.append({
				"chiffre": chiffre,
				"angle_debut": angle_courant,
				"angle_fin": angle_courant + angle_portion,
				"couleur": couleurs[index_couleur % couleurs.size()]
			})
			
			angle_courant += angle_portion
			index_couleur += 1

# Étape 2 : Dessiner la roue visuellement
func _draw() -> void:
	if total_votes == 0:
		return

	var centre         = Vector2.ZERO
	var rayon          = 200.0
	var police         = ThemeDB.fallback_font
	var taille_chiffre = 32   # ← plus grand
	var taille_votes   = 16

	# ── PASSE 1 : Toutes les tranches en premier (sans transform) ──────────
	for portion in donnees_portions:
		_dessiner_part_camembert(centre, rayon, portion.angle_debut, portion.angle_fin, portion.couleur)

	# ── PASSE 2 : Tous les textes par-dessus ──────────────────────────────
	for portion in donnees_portions:
		var angle_moyen: float = (portion.angle_debut + portion.angle_fin) / 2.0
		var dir = Vector2(cos(angle_moyen), sin(angle_moyen))

		# Un seul point d'ancrage vers le bord (70% du rayon)
		var pos_ancrage = centre + dir * (rayon * 0.70)
		draw_set_transform(pos_ancrage, angle_moyen + PI / 2.0, Vector2.ONE)

		# Chiffre (en haut dans le repère rotatif)
		draw_string(
			police,
			Vector2(0.0, 0.0),
			str(portion.chiffre),
			HORIZONTAL_ALIGNMENT_CENTER, -1,
			taille_chiffre, Color.WHITE
		)

		# Nombre de votes juste en dessous du chiffre (+taille_chiffre en Y local)
		draw_string(
			police,
			Vector2(0.0, taille_chiffre + 2.0),
			"(%d)" % votes_manuels[portion.chiffre],
			HORIZONTAL_ALIGNMENT_CENTER, -1,
			taille_votes, Color(1.0, 1.0, 1.0, 0.80)
		)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset

func _dessiner_part_camembert(centre: Vector2, rayon: float, angle_debut: float, angle_fin: float, couleur: Color) -> void:
	var points = PackedVector2Array()
	points.append(centre)
	var nb_segments = 32
	
	for i in range(nb_segments + 1):
		var angle = angle_debut + i * (angle_fin - angle_debut) / nb_segments
		points.append(centre + Vector2(cos(angle), sin(angle)) * rayon)
		
	draw_polygon(points, PackedColorArray([couleur]))

# Étape 3 : Logique de probabilité et animation
func lancer_roue() -> void:
	if en_rotation or total_votes == 0:
		return
	en_rotation = true
	
	# Tirage au sort basé sur le poids
	var valeur_aleatoire = randf() * total_votes
	var somme_courante = 0.0
	var portion_gagnante = null
	
	for portion in donnees_portions:
		somme_courante += votes_manuels[portion.chiffre]
		if valeur_aleatoire <= somme_courante:
			portion_gagnante = portion
			break
			
	if portion_gagnante == null:
		en_rotation = false
		return
		
	# Point d'arrêt aléatoire à l'intérieur de la portion gagnante
	var angle_arret = randf_range(portion_gagnante.angle_debut, portion_gagnante.angle_fin)
	
	var tours_complets = 5
	# Calcul de l'angle pour s'aligner avec la flèche positionnée en haut (-PI/2)
	var rotation_cible = -(angle_arret + PI / 2.0) + (tours_complets * TAU)
	
	# Animation fluide
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation_cible, 4.0)
	tween.tween_callback(_fin_rotation.bind(portion_gagnante.chiffre))

func _fin_rotation(chiffre_gagnant: int) -> void:
	en_rotation = false
	# Normalisation de la rotation
	rotation = fmod(rotation, TAU)
	print("La roue s'est arrêtée sur le chiffre : ", chiffre_gagnant)
	resultat_roue.emit(chiffre_gagnant)

# Lancement via clic gauche sur la roue elle-même
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		lancer_roue()
