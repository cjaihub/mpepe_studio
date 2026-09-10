// Generate a random UUID for the session
function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0, v = c == 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

const sessionId = generateUUID();
const csInterface = new CSInterface();

// --- Firebase Configuration ---
// Note: In a production plugin, you'd securely load these, or use Firebase REST API 
// to avoid exposing client config. For the prototype, we initialize compat.
const firebaseConfig = {
    apiKey: "YOUR_API_KEY",
    authDomain: "YOUR_PROJECT.firebaseapp.com",
    projectId: "YOUR_PROJECT",
    storageBucket: "YOUR_PROJECT.appspot.com",
    messagingSenderId: "123456789",
    appId: "1:123456789:web:abcdef"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

// UI Elements
const statusEl = document.getElementById('status');
const sessionIdEl = document.getElementById('session-id');

window.onload = function() {
    // Generate QR Code
    const qrData = `mpepe://connect?session=${sessionId}`;
    new QRCode(document.getElementById("qrcode"), {
        text: qrData,
        width: 150,
        height: 150,
        colorDark : "#000000",
        colorLight : "#ffffff",
        correctLevel : QRCode.CorrectLevel.L
    });
    
    sessionIdEl.innerText = `Session: ${sessionId}`;
    
    // Register the session in Firestore
    setupFirebaseSession();
};

function setupFirebaseSession() {
    const sessionRef = db.collection('remote_sessions').doc(sessionId);
    
    sessionRef.set({
        desktop_connected: true,
        software: { pr: 'online' }, // Native Premiere Plugin
        status: 'waiting'
    }, { merge: true });
    
    // Listen for mobile connection
    sessionRef.onSnapshot((doc) => {
        if (doc.exists && doc.data().mobile_connected) {
            statusEl.innerText = "Connected to Phone";
            statusEl.className = "status-connected";
        }
    });
    
    // Listen for commands
    sessionRef.collection('commands').where('status', '==', 'pending').onSnapshot((snapshot) => {
        snapshot.docChanges().forEach((change) => {
            if (change.type === "added") {
                const data = change.doc.data();
                if (data.software_id === 'pr') {
                    executePremiereCommand(change.doc.id, data);
                }
            }
        });
    });
}

function executePremiereCommand(docId, data) {
    const command = data.command;
    const payload = JSON.stringify(data.payload || {});
    
    // Update local UI for visual feedback
    if (command === 'render_and_send') {
        statusEl.innerText = "Rendering & Sending to Studio...";
        statusEl.style.color = "#FF9900"; // Processing color
    } else if (command === 'sync_metadata') {
        statusEl.innerText = "Syncing Metadata...";
    }
    
    // Evaluate the ExtendScript function dynamically
    const script = `executeCommand('${command}', '${payload}')`;
    
    csInterface.evalScript(script, function(result) {
        // Mocking a successful response if ExtendScript fails (since this is a prototype)
        if (result === 'EvalScript error.') {
            result = `Mock Success for ${command}`;
        }
        
        // Restore connected status
        statusEl.innerText = "Connected to Phone";
        statusEl.style.color = "#4CAF50";

        // Update Firestore with the result
        const sessionRef = db.collection('remote_sessions').doc(sessionId);
        sessionRef.collection('commands').doc(docId).update({
            status: 'completed',
            result_message: result
        });
    });
}
