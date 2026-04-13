const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
const socket = new WebSocket(`${protocol}//${window.location.host}?clientType=controller`);

const wsStatus = document.getElementById('ws-status');
const wsLabel = document.getElementById('ws-label');

socket.onopen = () => {
    wsStatus.style.background = 'lime';
    wsLabel.innerText = 'Connecté à Godot';
};

socket.onclose = () => {
    wsStatus.style.background = 'red';
    wsLabel.innerText = 'Déconnecté de Godot';
};

socket.onerror = (error) => {
    console.error('WebSocket Error:', error);
};

const curseur = document.getElementById('curseur');
const cases = document.querySelectorAll('.case-score');

let position = 0;
let direction = 1;
let estArrete = false;
let estVerrouille = false;
const vitesse = 1.5; 

let aVoteCeTour = false;
let tourActuel = -1;
let nomEquipeTour = "";

socket.onmessage = (event) => {
    let data = event.data;
    if (data.startsWith("NOUVEAU_TOUR:")) {
        let parts = data.split(":");
        tourActuel = parseInt(parts[1]);
        nomEquipeTour = parts[2];
        aVoteCeTour = false; // Réinitialise pour le nouveau tour
        evaluerVerrouillage();
    } else if (data === "TEMPS_ECOULE") {
        estVerrouille = true;
        document.getElementById("ecran-cliquable").style.opacity = "0.4";
        document.getElementById("txt-info").innerText = "TEMPS ÉCOULÉ - CHOIX ALÉATOIRE DANS LE JEU...";
        estArrete = true;
    }
};

function evaluerVerrouillage() {
    const txtTitre = document.getElementById("nom-equipe-tour");
    
    // Met à jour le titre
    txtTitre.innerText = "Tour : " + nomEquipeTour;
    
    // Vérifier si la personne peut jouer
    if (aVoteCeTour) {
        estVerrouille = true;
        document.getElementById("ecran-cliquable").style.opacity = "0.4";
        document.getElementById("txt-info").innerText = "VOTRE VOTE EST ENREGISTRÉ";
        estArrete = true;
    } else {
        estVerrouille = false;
        document.getElementById("ecran-cliquable").style.opacity = "1.0";
        document.getElementById("txt-info").innerText = "À TOI DE JOUER ! CLIQUE POUR ARRÊTER";
        estArrete = false;
        melangerChiffres();
        // Si estArrete était passé à true, la boucle animer() s'est arrêtée. On la relance :
        animer();
    }
}

function melangerChiffres() {
    let chiffres = [1, 2, 3, 4, 5, 6].sort(() => Math.random() - 0.5);
    
    cases.forEach((elementCase, index) => {
        elementCase.innerText = chiffres[index];
        elementCase.dataset.valeur = chiffres[index]; 
    });
}

function animer() {
    if (estArrete) return;

    position += vitesse * direction;
    
    if (position >= 100) { position = 100; direction = -1; }
    else if (position <= 0) { position = 0; direction = 1; }
    
    curseur.style.left = position + "%";

    let index = Math.min(Math.floor(position / (100 / 6)), 5);
    
    cases.forEach((c, i) => {
        if (i === index) {
            c.classList.add('case-active');
        } else {
            c.classList.remove('case-active');
        }
    });

    requestAnimationFrame(animer);
}

melangerChiffres();
animer();

document.getElementById('ecran-cliquable').onclick = () => {
    if (estVerrouille) return; // Empêche de jouer plusieurs fois par tour

    if (!estArrete && socket.readyState === WebSocket.OPEN) {
        estArrete = true;
        estVerrouille = true;
        
        let indexArret = Math.min(Math.floor(position / (100 / 6)), 5);
        let scoreObtenu = cases[indexArret].innerText;
        
        // Envoie le chiffre obtenu à Godot.
        socket.send("CLIC:" + scoreObtenu);
        
        aVoteCeTour = true;
        document.body.style.backgroundColor = "#4caf50"; 
        
        evaluerVerrouillage(); // Va directement mettre l'UI en attente
        
        setTimeout(() => { 
            document.body.style.transition = "background-color 0.5s";
            document.body.style.backgroundColor = "#1a1a1a";
            setTimeout(() => { 
                document.body.style.transition = "none";
            }, 500);
        }, 150);
        
    } else if (!estArrete && socket.readyState !== WebSocket.OPEN) {
        alert("Attention : Le site n'est pas connecté à Godot. Assurez-vous que le jeu tourne.");
    }
};