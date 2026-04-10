import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './styles/App.css';

// Placeholder Views
import ConfigView from './views/ConfigView';
import BuilderView from './views/BuilderView';

function App() {
    const [activeTab, setActiveTab] = useState('config');
    const [backendStatus, setBackendStatus] = useState(false);

    // Check Backend Status
    useEffect(() => {
        const checkStatus = async () => {
            try {
                await axios.get('http://127.0.0.1:8000/health');
                setBackendStatus(true);
            } catch (e) {
                setBackendStatus(false);
            }
        };
        checkStatus();
        const interval = setInterval(checkStatus, 5000);
        return () => clearInterval(interval);
    }, []);

    const renderContent = () => {
        switch (activeTab) {
            case 'config': return <ConfigView onNext={() => setActiveTab('builder')} />;
            case 'builder': return <BuilderView />;
            case 'results': return <div className="card"><h2>Results Coming Soon</h2></div>;
            default: return <ConfigView onNext={() => setActiveTab('builder')} />;
        }
    };

    return (
        <div className="app-container">
            {/* Sidebar */}
            <div className="sidebar">
                <div className="logo-area">
                    <div className="logo-text">URB FACTORY</div>
                    <div style={{ fontSize: '0.8rem', color: '#666' }}>v1.0.0</div>
                </div>

                <div
                    className={`nav-item ${activeTab === 'config' ? 'active' : ''}`}
                    onClick={() => setActiveTab('config')}
                >
                    🔧 Configuration
                </div>
                <div
                    className={`nav-item ${activeTab === 'builder' ? 'active' : ''}`}
                    onClick={() => setActiveTab('builder')}
                >
                    🧬 Strategy Builder
                </div>
                <div
                    className={`nav-item ${activeTab === 'results' ? 'active' : ''}`}
                    onClick={() => setActiveTab('results')}
                >
                    📊 Results & Export
                </div>

                <div style={{ marginTop: 'auto' }}>
                    <div className={`status-box ${backendStatus ? 'connected' : ''}`}>
                        {backendStatus ? '🟢 Engine Online' : '🔴 Engine Offline'}
                    </div>
                </div>
            </div>

            {/* Main Content */}
            <div className="main-content">
                {renderContent()}
            </div>
        </div>
    );
}

export default App;
