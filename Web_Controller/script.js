const socket = new WebSocket('ws://localhost:8080');
const curseur = document.getElementById('curseur');
const cases = document.querySelectorAll('.case-score');

let position = 0;
let direction = 1;
let estArrete = false;
const vitesse = 1.5; 

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
    if (!estArrete && socket.readyState === WebSocket.OPEN) {
        estArrete = true;
        
        let indexArret = Math.min(Math.floor(position / (100 / 6)), 5);
        let scoreObtenu = cases[indexArret].innerText;
        
        socket.send("CLIC:" + scoreObtenu);
        
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