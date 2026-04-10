const { app, BrowserWindow } = require('electron');
const path = require('path');
const { spawn } = require('child_process');

let mainWindow;
let pythonProcess;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1280,
        height: 800,
        backgroundColor: '#1a1a1a',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false, // For easier prototyping
        },
    });

    // Load React App (Localhost in dev, file in prod)
    // For now, simpler HTML fallback if React isn't running
    const startUrl = process.env.ELECTRON_START_URL || `file://${path.join(__dirname, 'index.html')}`;
    mainWindow.loadURL(startUrl);

    mainWindow.on('closed', function () {
        mainWindow = null;
    });
}

function startPythonBackend() {
    // Try to start the Python Backend automatically
    // Assuming 'python' is in PATH.
    console.log("Starting Python Backend...");
    const scriptPath = path.join(__dirname, '../backend/main.py');

    // Need to run from root dir
    const rootDir = path.join(__dirname, '../..');

    pythonProcess = spawn('python', ['URB_StrategyFactory/backend/main.py'], {
        cwd: rootDir
    });

    pythonProcess.stdout.on('data', (data) => {
        console.log(`[Python]: ${data}`);
    });

    pythonProcess.stderr.on('data', (data) => {
        console.error(`[Python Err]: ${data}`);
    });
}

app.on('ready', () => {
    // startPythonBackend(); // Disabled for now to avoid conflicts if user runs existing bat
    createWindow();
});

app.on('window-all-closed', function () {
    if (process.platform !== 'darwin') {
        if (pythonProcess) pythonProcess.kill();
        app.quit();
    }
});

app.on('activate', function () {
    if (mainWindow === null) {
        createWindow();
    }
});
