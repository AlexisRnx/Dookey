// 1. CONNEXION WEBSOCKET
const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
const socket = new WebSocket(protocol + window.location.host);

socket.onopen = () => console.log("Connecté au serveur WebSocket !");
socket.onerror = (error) => console.error("Erreur WebSocket : ", error);

// 2. VARIABLES D'ANIMATION
const curseur = document.getElementById('curseur');
const cases = document.querySelectorAll('.case-score');
const ecran = document.getElementById('ecran-cliquable');

let position = 0;
let direction = 1;
let estArrete = false;
const vitesse = 1.5; 

// 3. FONCTIONS LOGIQUES
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

// 4. ÉVÉNEMENT CLIC
ecran.onclick = () => {
    // On vérifie si on n'est pas déjà arrêté et si le socket est prêt
    if (!estArrete && socket.readyState === WebSocket.OPEN) {
        estArrete = true;
        
        let indexArret = Math.min(Math.floor(position / (100 / 6)), 5);
        let scoreObtenu = cases[indexArret].innerText;
        
        // ENVOI AU SERVEUR (qui transmettra à Godot)
        socket.send(scoreObtenu);
        console.log("Score envoyé : " + scoreObtenu);
        
        // Feedback visuel
        document.body.style.backgroundColor = "#4caf50"; 
        
        setTimeout(() => { 
            document.body.style.transition = "background-color 0.5s";
            document.body.style.backgroundColor = "#1a1a1a";
            
            setTimeout(() => { 
                document.body.style.transition = "none";
                estArrete = false; 
                melangerChiffres(); 
                animer(); 
            }, 2000);
        }, 150);
    } else if (socket.readyState !== WebSocket.OPEN) {
        console.warn("Le serveur n'est pas encore prêt...");
    }
};

// LANCEMENT
melangerChiffres();
animer();