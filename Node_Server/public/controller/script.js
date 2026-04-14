// Logique de Connexion Lobby
const inputCode = document.getElementById('input-code');
const inputPseudo = document.getElementById('input-pseudo');
const btnJoin = document.getElementById('btn-join');
const errorLabel = document.getElementById('login-error');

// Remplissage auto si URL = ?code=XYZ
const urlParams = new URLSearchParams(window.location.search);
const codeParam = urlParams.get('code');

let savedCode = sessionStorage.getItem('dookeyRoomCode');
let savedPseudo = sessionStorage.getItem('dookeyPseudo');

if (codeParam) {
    inputCode.value = codeParam.toUpperCase();
} else if (savedCode) {
    inputCode.value = savedCode;
}
if (savedPseudo) {
    inputPseudo.value = savedPseudo;
}

let socket;
let isGameScreenActive = false;
let animFrameId = null;

// Variables pour l'interface de jeu Controller
let aVoteCeTour = false;
let tourActuel = -1;
let nomEquipeTour = "";
let position = 0;
let direction = 1;
let estArrete = false;
let estVerrouille = false;
const vitesse = 1.5; 
const curseur = document.getElementById('curseur');
const cases = document.querySelectorAll('.case-score');

btnJoin.onclick = () => {
    const code = inputCode.value.trim().toUpperCase();
    const pseudo = inputPseudo.value.trim();
    
    if (code.length === 0 || pseudo.length === 0) {
        errorLabel.innerText = "Veuillez remplir le code et le pseudo.";
        errorLabel.style.display = "block";
        return;
    }
    
    btnJoin.innerText = "Connexion...";
    errorLabel.style.display = "none";
    initWebSocket(code, pseudo);
};

// Reconnexion automatique si on actualise !
if (savedCode && savedPseudo && !codeParam) {
    btnJoin.innerText = "Reconnexion...";
    initWebSocket(savedCode, savedPseudo);
}

function initWebSocket(code, pseudo) {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const socketUrl = `${protocol}//${window.location.host}?clientType=controller&roomCode=${code}&pseudo=${encodeURIComponent(pseudo)}`;
    socket = new WebSocket(socketUrl);

    socket.onclose = () => {
        if (isGameScreenActive) {
            document.getElementById('ws-status').style.background = 'red';
            document.getElementById('ws-label').innerText = 'Jeu Déconnecté';
        } else {
            btnJoin.innerText = "Se Connecter";
        }
    };

    socket.onerror = (error) => {
        if (!isGameScreenActive) {
            errorLabel.innerText = "Erreur de connexion au serveur.";
            errorLabel.style.display = "block";
        }
    };

    socket.onmessage = (event) => {
        let data = event.data;

        // Phase 1 : Login en cours
        if (!isGameScreenActive) {
            if (data === "JOIN_SUCCESS") {
                isGameScreenActive = true;
                
                // Mémoriser la session
                sessionStorage.setItem('dookeyRoomCode', code);
                sessionStorage.setItem('dookeyPseudo', pseudo);
                
                document.getElementById('login-screen').style.display = "none";
                document.getElementById('game-screen').style.display = "block";
                document.getElementById('ws-status').style.background = 'lime';
                document.getElementById('ws-label').innerText = 'Connecté (Attente...)';
                
                melangerChiffres();
                animer();
                evaluerVerrouillageBase(); // Bloque tout jusqu'au NOUVEAU_TOUR
            } else if (data === "ERROR:ROOM_NOT_FOUND") {
                sessionStorage.removeItem('dookeyRoomCode');
                sessionStorage.removeItem('dookeyPseudo');
                errorLabel.innerText = "Ce code de salle n'existe pas ou le jeu est fermé.";
                errorLabel.style.display = "block";
                socket.close();
            } else if (data === "ERROR:ROOM_LOCKED") {
                sessionStorage.removeItem('dookeyRoomCode');
                sessionStorage.removeItem('dookeyPseudo');
                errorLabel.innerText = "La partie a déjà commencé, entrée refusée !";
                errorLabel.style.display = "block";
                socket.close();
            } else if (data === "ERROR:PSEUDO_TAKEN") {
                sessionStorage.removeItem('dookeyRoomCode');
                sessionStorage.removeItem('dookeyPseudo');
                errorLabel.innerText = "Ce pseudo est déjà utilisé par un autre joueur !";
                errorLabel.style.display = "block";
                socket.close();
            }
            return;
        }

        // Phase 2 : En Jeu
        if (data.startsWith("NOUVEAU_TOUR:")) {
            let parts = data.split(":");
            tourActuel = parseInt(parts[1]);
            nomEquipeTour = parts[2];
            aVoteCeTour = false;
            document.getElementById('ws-label').innerText = "Tour en cours";
            // L'activation sera gérée par MON_TOUR / PAS_MON_TOUR
        } else if (data === 'MON_TOUR') {
            estVerrouille = false;
            estArrete = false;
            aVoteCeTour = false;
            document.getElementById('ws-label').innerText = "C'est ton tour !";
            document.getElementById("ecran-cliquable").style.opacity = "1.0";
            document.getElementById("txt-info").innerText = "À TOI DE JOUER ! CLIQUE POUR ARRÊTER";
            document.getElementById("nom-equipe-tour").innerText = "🎯 TON ÉQUIPE JOUE !";
            melangerChiffres();
            animer();
        } else if (data === 'PAS_MON_TOUR') {
            estVerrouille = true;
            estArrete = true;
            document.getElementById("ecran-cliquable").style.opacity = "0.3";
            document.getElementById("txt-info").innerText = "Ce n'est pas le tour de ton équipe...";
            document.getElementById("nom-equipe-tour").innerText = "Héros Actif : " + nomEquipeTour;
            document.getElementById('ws-label').innerText = "En attente...";
        } else if (data === "TEMPS_ECOULE") {
            estVerrouille = true;
            document.getElementById("ecran-cliquable").style.opacity = "0.4";
            document.getElementById("txt-info").innerText = "TEMPS ÉCOULÉ - CHOIX ALÉATOIRE DANS LE JEU...";
            estArrete = true;
        } else if (data === "LOBBY_ATTENTE") {
             aVoteCeTour = false;
             tourActuel = -1;
             nomEquipeTour = "";
             evaluerVerrouillageBase();
        }
    };
}

function evaluerVerrouillageBase() {
     document.getElementById("nom-equipe-tour").innerText = "En attente du jeu...";
     document.getElementById("txt-info").innerText = "Regardez l'écran principal";
     estVerrouille = true;
     document.getElementById("ecran-cliquable").style.opacity = "0.4";
}

function evaluerVerrouillage() {
    const txtTitre = document.getElementById("nom-equipe-tour");
    txtTitre.innerText = "Héros Actif : " + nomEquipeTour;
    
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
        animer();
    }
}

function melangerChiffres() {
    let chiffres = [1, 2, 3, 4, 5, 6].sort(() => Math.random() - 0.5);
    cases.forEach((elementCase, index) => {
        elementCase.innerText = chiffres[index];
    });
}

function animer() {
    if (estArrete) {
        if (animFrameId) cancelAnimationFrame(animFrameId);
        return;
    }

    position += vitesse * direction;
    if (position >= 100) { position = 100; direction = -1; }
    else if (position <= 0) { position = 0; direction = 1; }
    
    curseur.style.left = position + "%";

    let index = Math.min(Math.floor(position / (100 / 6)), 5);
    cases.forEach((c, i) => {
        if (i === index) c.classList.add('case-active');
        else c.classList.remove('case-active');
    });

    if (animFrameId) cancelAnimationFrame(animFrameId);
    animFrameId = requestAnimationFrame(animer);
}

document.getElementById('ecran-cliquable').onclick = () => {
    if (estVerrouille || !isGameScreenActive) return;

    if (!estArrete && socket.readyState === WebSocket.OPEN) {
        estArrete = true;
        estVerrouille = true;
        
        let indexArret = Math.min(Math.floor(position / (100 / 6)), 5);
        let scoreObtenu = cases[indexArret].innerText;
        
        socket.send("CLIC:" + scoreObtenu);
        aVoteCeTour = true;
        
        document.body.style.backgroundColor = "#4caf50"; 
        evaluerVerrouillage();
        
        setTimeout(() => { 
            document.body.style.transition = "background-color 0.5s";
            document.body.style.backgroundColor = "#1a1a1a";
            setTimeout(() => document.body.style.transition = "none", 500);
        }, 150);
    }
};