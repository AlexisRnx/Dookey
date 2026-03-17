const http = require('http');
const fs = require('fs');
const path = require('path');

// Serveur HTTP pour charger le site sur o2switch
const server = http.createServer((req, res) => {
    let filePath = '.' + req.url;
    if (filePath === './' || filePath === './socket') {
        filePath = './index.html';
    }

    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = {
        '.html': 'text/html',
        '.js': 'text/javascript',
        '.css': 'text/css'
    };
    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) {
            res.writeHead(500);
            res.end('Erreur serveur');
        } else {
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content, 'utf-8');
        }
    });
});

// On se connecte en forçant les options du serveur
const socket = io("https://dookey.tmgdiff.fr", {
    path: "/mon-app-socket/",
    transports: ['polling']
});



io.on('connection', (socket) => {
    console.log('Nouveau client connecté via Socket.io');

    socket.on('score', (data) => {
        console.log('Score reçu: ', data);
        // Renvoie à tout le monde
        socket.broadcast.emit("score", data);
    });

    socket.on('disconnect', () => {
        console.log("Un client s'est déconnecté");
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`Serveur actif sur le port ${PORT}`));
