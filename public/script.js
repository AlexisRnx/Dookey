// Détection automatique de l'adresse du serveur
const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
const socket = new WebSocket(protocol + window.location.host);

// ... (garde tes variables position, vitesse, estArrete, etc.) ...

ecran.onclick = () => {
    if (!estArrete && socket.readyState === WebSocket.OPEN) {
        estArrete = true;
        
        let indexArret = Math.min(Math.floor(position / (100 / 6)), 5);
        let scoreObtenu = cases[indexArret].innerText;
        
        // On envoie le texte pur
        socket.send(scoreObtenu.toString());
        console.log("Envoyé au serveur : " + scoreObtenu);
        
        // --- Ton animation de couleur ---
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
    }
};

socket.onopen = () => console.log("Site connecté au serveur !");