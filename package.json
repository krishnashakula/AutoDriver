const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 8080;

// Global sessions storage
const sessions = new Map();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Logging function
function log(message, level = 'INFO') {
    const timestamp = new Date().toISOString();
    const colors = {
        ERROR: '\x1b[31m',
        WARN: '\x1b[33m',
        SUCCESS: '\x1b[32m',
        INFO: '\x1b[37m'
    };
    const reset = '\x1b[0m';
    console.log(`${colors[level]}[${timestamp}] [${level}] ${message}${reset}`);
}

// Mock system information (Linux equivalent)
function getSystemInfo() {
    const cpus = os.cpus();
    const totalMemory = os.totalmem();
    const platform = os.platform();
    const hostname = os.hostname();
    const uptime = os.uptime();
    
    return {
        computerName: hostname,
        operatingSystem: `${platform} ${os.release()}`,
        version: os.release(),
        totalRAM: Math.round(totalMemory / (1024 * 1024 * 1024) * 100) / 100,
        processor: cpus[0]?.model || 'Unknown',
        lastBootTime: new Date(Date.now() - uptime * 1000).toISOString(),
        currentUser: process.env.USER || process.env.USERNAME || 'Unknown',
        nodeVersion: process.version,
        totalDevices: Math.floor(Math.random() * 50) + 20,
        problemDevices: Math.floor(Math.random() * 5)
    };
}

// Mock device data generator
function generateMockDevices() {
    const deviceTypes = [
        'Intel(R) HD Graphics 620',
        'Realtek High Definition Audio',
        'Intel(R) Wireless-AC 9560',
        'Standard SATA AHCI Controller',
        'Intel(R) Management Engine Interface',
        'Synaptics Touchpad',
        'Intel(R) Bluetooth Device',
        'Generic USB Hub',
        'Standard PS/2 Keyboard',
        'HID-compliant mouse'
    ];
    
    const manufacturers = ['Intel Corporation', 'Realtek', 'Microsoft', 'Generic', 'Synaptics'];
    const statuses = ['OK', 'Warning', 'Error'];
    
    return deviceTypes.map((name, index) => ({
        name,
        deviceId: `PCI\\VEN_8086&DEV_${(1000 + index).toString(16).toUpperCase()}`,
        manufacturer: manufacturers[Math.floor(Math.random() * manufacturers.length)],
        status: statuses[Math.floor(Math.random() * statuses.length)],
        errorCode: Math.random() > 0.8 ? Math.floor(Math.random() * 10) + 1 : 0,
        hasProblem: Math.random() > 0.8,
        needsUpdate: Math.random() > 0.7,
        driverVersion: `${Math.floor(Math.random() * 10) + 1}.${Math.floor(Math.random() * 10)}.${Math.floor(Math.random() * 1000)}.${Math.floor(Math.random() * 100)}`
    }));
}

// Mock Windows updates generator
function generateMockUpdates() {
    const updates = [
        'Intel Display Driver Update',
        'Realtek Audio Driver',
        'Network Adapter Driver',
        'USB Controller Driver',
        'Bluetooth Driver Update'
    ];
    
    return updates.map(title => ({
        title,
        description: `Updated driver for ${title}`,
        sizeMB: Math.round(Math.random() * 100 + 10),
        isMandatory: Math.random() > 0.7,
        updateId: uuidv4(),
        categories: 'Drivers, Hardware'
    }));
}

// Simulate background operation
function simulateOperation(sessionId, operationType, settings) {
    const session = sessions.get(sessionId);
    if (!session) return;
    
    log(`Starting ${operationType} operation for session ${sessionId}`);
    
    const steps = [
        'Initializing scan...',
        'Detecting hardware...',
        'Analyzing drivers...',
        'Checking for updates...',
        'Generating report...',
        'Finalizing results...'
    ];
    
    let currentStep = 0;
    const totalSteps = steps.length;
    
    const interval = setInterval(() => {
        if (!sessions.has(sessionId)) {
            clearInterval(interval);
            return;
        }
        
        const session = sessions.get(sessionId);
        
        if (currentStep < totalSteps) {
            session.status = steps[currentStep];
            session.progress = Math.round((currentStep / totalSteps) * 90);
            currentStep++;
        } else {
            // Complete the operation
            session.status = 'Completed';
            session.progress = 100;
            session.success = true;
            
            // Generate results based on operation type
            switch (operationType) {
                case 'driver-scan':
                    const devices = generateMockDevices();
                    session.results = {
                        devices,
                        systemInfo: {
                            totalDevices: devices.length,
                            problemDevices: devices.filter(d => d.hasProblem).length,
                            workingDevices: devices.filter(d => !d.hasProblem).length,
                            scanCompleted: new Date().toISOString()
                        },
                        executionTime: Date.now() - session.startTime.getTime()
                    };
                    break;
                    
                case 'windows-update':
                    const updates = generateMockUpdates();
                    session.results = {
                        updates,
                        totalCount: updates.length,
                        totalSize: updates.reduce((sum, u) => sum + u.sizeMB, 0)
                    };
                    break;
                    
                case 'driver-update':
                    session.results = {
                        devicesUpdated: generateMockDevices().slice(0, 3),
                        updateResults: [
                            { device: 'Intel HD Graphics', result: 'Success', action: 'Updated to version 27.20.100.8681' },
                            { device: 'Realtek Audio', result: 'Success', action: 'Updated to version 6.0.9167.1' }
                        ],
                        executionTime: Date.now() - session.startTime.getTime()
                    };
                    break;
            }
            
            clearInterval(interval);
            log(`Operation ${operationType} completed for session ${sessionId}`);
        }
        
        sessions.set(sessionId, session);
    }, 1000 + Math.random() * 2000); // Random delay between 1-3 seconds
}

// Routes

// Serve main page
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// System information endpoint
app.get('/api/system-info', (req, res) => {
    try {
        const systemInfo = getSystemInfo();
        log('System information requested');
        res.json(systemInfo);
    } catch (error) {
        log(`Error getting system info: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Driver scan endpoint
app.post('/api/driver-scan', (req, res) => {
    try {
        const sessionId = uuidv4();
        const settings = req.body || {};
        
        // Create session
        const session = {
            id: sessionId,
            status: 'Starting',
            progress: 0,
            startTime: new Date(),
            settings,
            results: {},
            success: false
        };
        
        sessions.set(sessionId, session);
        log(`Created driver scan session ${sessionId}`);
        
        // Send immediate response
        res.json({
            sessionId,
            status: 'started',
            message: 'Driver scan initiated',
            timestamp: new Date().toISOString()
        });
        
        // Start background operation
        setTimeout(() => {
            simulateOperation(sessionId, 'driver-scan', settings);
        }, 100);
        
    } catch (error) {
        log(`Error starting driver scan: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Driver update endpoint
app.post('/api/driver-update', (req, res) => {
    try {
        const sessionId = uuidv4();
        const settings = req.body || {};
        
        const session = {
            id: sessionId,
            status: 'Starting',
            progress: 0,
            startTime: new Date(),
            settings,
            results: {},
            success: false
        };
        
        sessions.set(sessionId, session);
        log(`Created driver update session ${sessionId}`);
        
        res.json({
            sessionId,
            status: 'started',
            message: 'Driver update initiated',
            timestamp: new Date().toISOString()
        });
        
        setTimeout(() => {
            simulateOperation(sessionId, 'driver-update', settings);
        }, 100);
        
    } catch (error) {
        log(`Error starting driver update: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Windows update endpoint
app.post('/api/windows-update', (req, res) => {
    try {
        const sessionId = uuidv4();
        const settings = req.body || {};
        
        const session = {
            id: sessionId,
            status: 'Starting',
            progress: 0,
            startTime: new Date(),
            settings,
            results: {},
            success: false
        };
        
        sessions.set(sessionId, session);
        log(`Created Windows update session ${sessionId}`);
        
        res.json({
            sessionId,
            status: 'started',
            message: 'Windows Update scan initiated',
            timestamp: new Date().toISOString()
        });
        
        setTimeout(() => {
            simulateOperation(sessionId, 'windows-update', settings);
        }, 100);
        
    } catch (error) {
        log(`Error starting Windows update: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Status check endpoint
app.get('/api/status/:sessionId', (req, res) => {
    try {
        const sessionId = req.params.sessionId;
        
        if (!sessions.has(sessionId)) {
            return res.status(404).json({ error: 'Session not found' });
        }
        
        const session = sessions.get(sessionId);
        
        const status = {
            sessionId,
            status: session.status,
            progress: session.progress,
            startTime: session.startTime.toISOString(),
            elapsedTime: Math.round((Date.now() - session.startTime.getTime()) / 1000 * 100) / 100
        };
        
        if (session.status === 'Completed') {
            status.results = session.results;
            status.success = session.success;
        }
        
        res.json(status);
        
    } catch (error) {
        log(`Error checking status: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Cancel operation endpoint
app.post('/api/cancel/:sessionId', (req, res) => {
    try {
        const sessionId = req.params.sessionId;
        
        if (!sessions.has(sessionId)) {
            return res.status(404).json({ error: 'Session not found' });
        }
        
        // Mark session as cancelled
        const session = sessions.get(sessionId);
        session.status = 'Cancelled';
        sessions.set(sessionId, session);
        
        log(`Operation cancelled for session ${sessionId}`);
        
        res.json({
            sessionId,
            status: 'cancelled',
            message: 'Operation cancelled successfully'
        });
        
    } catch (error) {
        log(`Error cancelling operation: ${error.message}`, 'ERROR');
        res.status(500).json({ error: error.message });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy', 
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        sessions: sessions.size
    });
});

// Cleanup old sessions periodically
setInterval(() => {
    const now = Date.now();
    const maxAge = 30 * 60 * 1000; // 30 minutes
    
    for (const [sessionId, session] of sessions.entries()) {
        if (now - session.startTime.getTime() > maxAge) {
            sessions.delete(sessionId);
            log(`Cleaned up old session ${sessionId}`);
        }
    }
}, 5 * 60 * 1000); // Check every 5 minutes

// Start server
app.listen(PORT, '0.0.0.0', () => {
    log(`Driver Update Server started successfully`, 'SUCCESS');
    log(`Server URL: http://localhost:${PORT}`, 'INFO');
    log(`Environment: ${process.env.NODE_ENV || 'development'}`, 'INFO');
    log(`Platform: ${os.platform()} ${os.release()}`, 'INFO');
});

// Graceful shutdown
process.on('SIGTERM', () => {
    log('SIGTERM received, shutting down gracefully', 'INFO');
    process.exit(0);
});

process.on('SIGINT', () => {
    log('SIGINT received, shutting down gracefully', 'INFO');
    process.exit(0);
});
