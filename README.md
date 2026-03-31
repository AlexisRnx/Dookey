# Dookey

## Description
Bienvenue sur le dépôt officiel de **Dookey**, notre projet développé avec [Godot Engine](https://godotengine.org/). 
Ce dépôt sert d'espace centralisé pour le développement, l'échange de fichiers et le suivi des versions de notre jeu.

---

## Prérequis
Pour garantir la compatibilité entre tous les collaborateurs, veuillez vous assurer de disposer des éléments suivants :

* **Godot Engine :** Version 4.4.1
* **Git :** Pour la gestion du code source et des assets.

---

## Installation et Démarrage
Voici les instructions pour configurer l'environnement de travail sur votre machine locale :

1.  **Cloner le dépôt :**
  
2.  **Ouvrir le projet dans Godot :**
    * Lancez Godot Engine.
    * Cliquez sur le bouton **Importer**.
    * Naviguez jusqu'au dossier `dookey` nouvellement cloné et sélectionnez le fichier `project.godot`.
    * Cliquez sur **Importer et Éditer**.

---

## Guide de Collaboration
Travailler à plusieurs sur Godot nécessite un peu d'organisation pour éviter les conflits de fusion (merge conflicts), particulièrement sur les fichiers de scènes. 

* **Scènes indépendantes :** Évitez de travailler à plusieurs sur la même scène (`.tscn`) simultanément. Divisez le travail en instanciant des scènes plus petites.
* **Commits descriptifs :** Rédigez des messages de commit clairs pour expliquer les modifications apportées.
* **Validation avant l'envoi :** Assurez-vous que le jeu se lance sans erreur critique avant de pousser (push) vos modifications sur le dépôt principal.

> **Note importante :** Vérifiez que le dépôt contient bien un fichier `.gitignore` adapté à Godot. Il est crucial d'exclure le dossier `.godot/` (qui contient des données locales et temporaires) pour ne pas polluer le dépôt.

---

## Structure du Projet
Afin de garder le projet organisé, veuillez respecter l'arborescence suivante lors de l'ajout de nouveaux fichiers :

| Dossier | Contenu principal |
| :--- | :--- |
| `Assets/` | Modèles, textures, musiques, effets sonores et polices. |
| `Scenes/` | Niveaux, interfaces et scènes instanciables (joueur, ennemis). |
| `Scripts/` | Fichiers de code source. |
| `UI/` | Éléments d'interface utilisateur spécifiques. |
