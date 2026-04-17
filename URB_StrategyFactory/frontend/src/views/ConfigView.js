
import React, { useState, useEffect } from 'react';
import axios from 'axios';

// --- Constants ---
const EAS = [
    { id: 'urb', name: 'Ultimate Range Breaker', active: true, desc: 'Breakout Strategy for Indices/Forex' },
    { id: 'trend', name: 'Trend Master', active: false, desc: 'Coming Soon' },
    { id: 'scalp', name: 'Scalp King', active: false, desc: 'Coming Soon' }
];

const ASSET_CATEGORIES = {
    'FOREX MAJORS': ['EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'USDCAD', 'USDCHF', 'NZDUSD'],
    'FOREX MINORS': ['EURGBP', 'EURAUD', 'EURNZD', 'EURCAD', 'EURCHF', 'EURJPY', 'GBPAUD', 'GBPNZD', 'GBPCAD', 'GBPCHF', 'GBPJPY', 'AUDNZD', 'AUDCAD', 'AUDCHF', 'AUDJPY', 'NZDCAD', 'NZDCHF', 'NZDJPY', 'CADCHF', 'CADJPY', 'CHFJPY'],
    'COMMODITIES': ['XAUUSD', 'XAGUSD', 'USOIL', 'UKOIL'],
    'INDICES': ['US100', 'US30', 'US500', 'GER40', 'JPN225', 'UK100', 'FR40', 'AU200', 'EU50'],
    'CRYPTOS': ['BTCUSD', 'ETHUSD', 'BNBUSD', 'LTCUSD', 'XRPUSD', 'SOLUSD']
};

const ConfigView = ({ onNext }) => {
    // Top Level State
    const [terminals, setTerminals] = useState([]);
    const [selectedTerminal, setSelectedTerminal] = useState('');
    const [connectionMsg, setConnectionMsg] = useState('');
    const [accountInfo, setAccountInfo] = useState(null);
    const [initialCapital, setInitialCapital] = useState(100000);
    const [connError, setConnError] = useState(false); // New state for error styling

    // Trading Environment Override Options
    const [brokerDelay, setBrokerDelay] = useState(0); // Ms delay
    const [brokerCommission, setBrokerCommission] = useState(0.0); // Commission per lot

    // Workflow State
    const [workflowMode, setWorkflowMode] = useState(null); // 'builder', 'preloaded', 'import'
    const [selectedPlatform, setSelectedPlatform] = useState(localStorage.getItem('selectedPlatform') || 'mt5');

    // Save platform to localStorage for BuilderView
    useEffect(() => {
        localStorage.setItem('selectedPlatform', selectedPlatform);
    }, [selectedPlatform]); // 'mt5', 'pine', 'ctrader'
    const [selectedEA, setSelectedEA] = useState('urb');
    const [selectedCategory, setSelectedCategory] = useState('FOREX MAJORS'); // Default
    const [selectedSymbol, setSelectedSymbol] = useState('EURUSD'); // Default common name
    const [symbolInfo, setSymbolInfo] = useState(null);
    const [importedStrategy, setImportedStrategy] = useState(null); // New state for custom import
    const [importStatus, setImportStatus] = useState('idle'); // idle, loading, success, error, confirmed
    const [importMsg, setImportMsg] = useState('');

    // AI Translation Settings
    const [aiProvider, setAiProvider] = useState('ollama');

    // Historical Data States for Pine/TradingView
    const [dataSourceType, setDataSourceType] = useState('tv'); // 'tv' or 'mt5'
    const [mt5Timezone, setMt5Timezone] = useState('UTC+2');

    // Load terminals on mount
    useEffect(() => {
        const loadTerminals = async () => {
            try {
                const res = await axios.get('http://127.0.0.1:8000/api/bridge/terminals');
                setTerminals(res.data);
                if (res.data.length > 0) setSelectedTerminal(res.data[0]);
            } catch (e) {
                console.warn("Backend not reachable for terminals");
            }
        };
        loadTerminals();
    }, []);

    // --- Handlers ---

    const handleImport = async (e) => {
        if (e.target.files.length === 0) return;
        const file = e.target.files[0];
        const formData = new FormData();
        formData.append("file", file);
        formData.append("ai_mode", aiProvider);
        // We no longer send a user-provided API key from the frontend

        setImportStatus('loading');
        setImportMsg('⏳ Analyzing logic & compiling Python Twin via AI... (please wait)');

        try {
            const res = await axios.post('http://127.0.0.1:8000/api/strategy/import', formData, {
                headers: { 'Content-Type': 'multipart/form-data' }
            });
            setImportedStrategy(res.data);
            setSelectedEA('custom');
            setImportStatus('success');
            setImportMsg(`✅ Successfully Loaded: ${res.data.filename}`);
        } catch (err) {
            setImportStatus('error');
            setImportMsg("❌ Import Failed: " + (err.response?.data?.detail || err.message));
        }
    };

    const handleAcceptStrategy = async () => {
        if (!importedStrategy) return;
        try {
            await axios.post('http://127.0.0.1:8000/api/strategy/select', importedStrategy);
            setImportStatus('confirmed');
            setImportMsg(`🔒 Strategy Accepted: ${importedStrategy.filename}`);
        } catch (e) {
            alert("Error selecting strategy: " + e.message);
        }
    };

    const handleConnect = async () => {
        try {
            setConnectionMsg("Connecting...");
            setConnError(false);
            if (!selectedTerminal) {
                setConnectionMsg("❌ No Terminal Selected");
                setConnError(true);
                return;
            }
            // Pass the selected path to the backend
            const res = await axios.get(`http://127.0.0.1:8000/api/bridge/connect?path=${encodeURIComponent(selectedTerminal)}`);
            if (res.data.status) {
                if (res.data.account) {
                    setConnectionMsg(`✅ Connected!`);
                    setAccountInfo(res.data.account);
                } else {
                    // Connected but no account info (e.g. login failed / expired)
                    setConnectionMsg(`⚠️ Connected but Login Failed (Expired?)`);
                    setConnError(true);
                    setAccountInfo(null);
                }
            } else {
                setConnectionMsg(`❌ ${res.data.message}`);
                setConnError(true);
                setAccountInfo(null);
            }
        } catch (e) {
            setConnectionMsg("❌ API Error/Offline");
            setConnError(true);
        }
    };

    const handleSelectSymbol = async (commonName) => {
        setSelectedSymbol(commonName);
        setSymbolInfo(null); // Reset while loading/searching

        try {
            // Note: Backend 'find_matching_symbol' handles the mapping common -> broker specific
            const res = await axios.get(`http://127.0.0.1:8000/api/bridge/symbol/${commonName}`);
            if (res.data && !res.data.error) {
                setSymbolInfo(res.data);
            } else {
                // Fallback if backend returns null but 200 OK (Symbol not found in broker)
                setSymbolInfo({ error: res.data.error || "Symbol not found in Broker" });
            }
        } catch (e) {
            setSymbolInfo({ error: "Connection Error or Symbol Offline" });
        }
    };

    // Auto-select US100 info on load or connect? Maybe better wait for user interaction or connection.

    // Calculate effective Step 2 requirement state
    // Step 2 is fully Confirmed if:
    // a) Builder Mode (doesn't exist, always valid)
    // b) Preloaded Mode (a valid EA is selected)
    // c) Import Mode (a valid strat is imported AND confirmed)
    let isStrategyReady = false;
    if (workflowMode === 'builder') isStrategyReady = true;
    if (workflowMode === 'preloaded' && ['urb', 'trend', 'scalp'].includes(selectedEA)) isStrategyReady = true;
    if (workflowMode === 'import' && importStatus === 'confirmed') isStrategyReady = true;

    return (
        <div style={{ maxWidth: '1200px', margin: '0 auto' }}>
            <div className="header">
                <h1>Strategy Factory Setup</h1>
                <p>Configure your environment workflow</p>
            </div>

            {/* STEP 0: PLATFORM SELECTION */}
            <div className="card" style={{ borderTop: '4px solid #ff00ff', marginBottom: '20px' }}>
                <h3 style={{ textAlign: 'center', marginBottom: '20px', color: '#ff00ff' }}>0. Platform / Engine Selection</h3>
                <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap', justifyContent: 'center' }}>

                    <div
                        onClick={() => setSelectedPlatform('mt5')}
                        style={{
                            flex: '1 1 200px', padding: '15px', textAlign: 'center', cursor: 'pointer',
                            background: selectedPlatform === 'mt5' ? 'rgba(255, 0, 255, 0.1)' : '#1a1a1a',
                            border: selectedPlatform === 'mt5' ? '2px solid #ff00ff' : '1px solid #333',
                            borderRadius: '8px', transition: 'all 0.2s',
                            boxShadow: selectedPlatform === 'mt5' ? '0 0 15px rgba(255,0,255,0.3)' : 'none',
                            opacity: selectedPlatform && selectedPlatform !== 'mt5' ? 0.5 : 1
                        }}
                    >
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>🔵</div>
                        <h4 style={{ color: selectedPlatform === 'mt5' ? '#fff' : '#aaa', margin: '0 0 5px 0' }}>MetaTrader 5</h4>
                        <p style={{ fontSize: '0.75rem', color: selectedPlatform === 'mt5' ? '#aaa' : '#666', margin: 0 }}>Python Backend</p>
                    </div>

                    <div
                        onClick={() => setSelectedPlatform('pine')}
                        style={{
                            flex: '1 1 200px', padding: '15px', textAlign: 'center', cursor: 'pointer',
                            background: selectedPlatform === 'pine' ? 'rgba(255, 170, 0, 0.1)' : '#1a1a1a',
                            border: selectedPlatform === 'pine' ? '2px solid #ffaa00' : '1px solid #333',
                            borderRadius: '8px', transition: 'all 0.2s',
                            boxShadow: selectedPlatform === 'pine' ? '0 0 15px rgba(255,170,0,0.3)' : 'none',
                            opacity: selectedPlatform && selectedPlatform !== 'pine' ? 0.5 : 1
                        }}
                    >
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>☁️</div>
                        <h4 style={{ color: selectedPlatform === 'pine' ? '#fff' : '#aaa', margin: '0 0 5px 0' }}>TradingView / Pine</h4>
                        <p style={{ fontSize: '0.75rem', color: selectedPlatform === 'pine' ? '#aaa' : '#666', margin: 0 }}>Vectorized Backend</p>
                    </div>

                    <div
                        onClick={() => setSelectedPlatform('ninjatrader')}
                        style={{
                            flex: '1 1 200px', padding: '15px', textAlign: 'center', cursor: 'pointer',
                            background: selectedPlatform === 'ninjatrader' ? 'rgba(0, 255, 100, 0.1)' : '#1a1a1a',
                            border: selectedPlatform === 'ninjatrader' ? '2px solid #00ff64' : '1px solid #333',
                            borderRadius: '8px', transition: 'all 0.2s',
                            boxShadow: selectedPlatform === 'ninjatrader' ? '0 0 15px rgba(0,255,100,0.3)' : 'none',
                            opacity: selectedPlatform && selectedPlatform !== 'ninjatrader' ? 0.5 : 1
                        }}
                    >
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>🥷</div>
                        <h4 style={{ color: selectedPlatform === 'ninjatrader' ? '#fff' : '#aaa', margin: '0 0 5px 0' }}>NinjaTrader</h4>
                        <p style={{ fontSize: '0.75rem', color: selectedPlatform === 'ninjatrader' ? '#aaa' : '#666', margin: 0 }}>C# / NinjaScript</p>
                    </div>

                    <div
                        onClick={() => setSelectedPlatform('ctrader')}
                        style={{
                            flex: '1 1 200px', padding: '15px', textAlign: 'center', cursor: 'pointer',
                            background: selectedPlatform === 'ctrader' ? 'rgba(50, 150, 255, 0.1)' : '#1a1a1a',
                            border: selectedPlatform === 'ctrader' ? '2px solid #3296ff' : '1px solid #333',
                            borderRadius: '8px', transition: 'all 0.2s',
                            boxShadow: selectedPlatform === 'ctrader' ? '0 0 15px rgba(50,150,255,0.3)' : 'none',
                            opacity: selectedPlatform && selectedPlatform !== 'ctrader' ? 0.5 : 1
                        }}
                    >
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>🟢</div>
                        <h4 style={{ color: selectedPlatform === 'ctrader' ? '#fff' : '#aaa', margin: '0 0 5px 0' }}>cTrader</h4>
                        <p style={{ fontSize: '0.75rem', color: selectedPlatform === 'ctrader' ? '#aaa' : '#666', margin: 0 }}>C# / cAlgo</p>
                    </div>

                    <div
                        onClick={() => setSelectedPlatform('crypto')}
                        style={{
                            flex: '1 1 200px', padding: '15px', textAlign: 'center', cursor: 'pointer',
                            background: selectedPlatform === 'crypto' ? 'rgba(255, 200, 50, 0.1)' : '#1a1a1a',
                            border: selectedPlatform === 'crypto' ? '2px solid #ffc832' : '1px solid #333',
                            borderRadius: '8px', transition: 'all 0.2s',
                            boxShadow: selectedPlatform === 'crypto' ? '0 0 15px rgba(255,200,50,0.3)' : 'none',
                            opacity: selectedPlatform && selectedPlatform !== 'crypto' ? 0.5 : 1
                        }}
                    >
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>🪙</div>
                        <h4 style={{ color: selectedPlatform === 'crypto' ? '#fff' : '#aaa', margin: '0 0 5px 0' }}>Crypto (Binance/Bybit)</h4>
                        <p style={{ fontSize: '0.75rem', color: selectedPlatform === 'crypto' ? '#aaa' : '#666', margin: 0 }}>API / CCXT Engine</p>
                    </div>
                </div>
            </div>

            {/* STEP 1: WORKFLOW MODE SELECTION */}
            {selectedPlatform && selectedPlatform !== 'pine' && (
                <div className="card" style={{ borderTop: '4px solid #00ccff', marginBottom: '20px', animation: 'fadeIn 0.3s' }}>
                    <h3 style={{ textAlign: 'center', marginBottom: '20px', color: '#00ccff' }}>1. Select Engine Operation Mode ({selectedPlatform.toUpperCase()})</h3>
                    <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap' }}>

                        <div
                            onClick={() => { setWorkflowMode('builder'); setSelectedEA('builder'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'builder' ? 'rgba(0, 204, 255, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'builder' ? '2px solid #00ccff' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'builder' ? '0 0 15px rgba(0,204,255,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>🧱</div>
                            <h4 style={{ color: workflowMode === 'builder' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Atom Builder (SQX Style)</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Construct strategies from scratch using atomic building blocks (Indicators, Price Action, Exits). The Engine writes MQL5 natively.
                            </p>
                        </div>

                        <div
                            onClick={() => { setWorkflowMode('preloaded'); setSelectedEA('urb'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'preloaded' ? 'rgba(0, 255, 136, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'preloaded' ? '2px solid #00ff88' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'preloaded' ? '0 0 15px rgba(0,255,136,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>🤖</div>
                            <h4 style={{ color: workflowMode === 'preloaded' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Pre-Loaded Templates</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Optimize pre-built robust URB strategies dynamically mapped into the genetic engine.
                            </p>
                        </div>

                        <div
                            onClick={() => { setWorkflowMode('import'); setSelectedEA('custom'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'import' ? 'rgba(255, 170, 0, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'import' ? '2px solid #ffaa00' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'import' ? '0 0 15px rgba(255,170,0,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📥</div>
                            <h4 style={{ color: workflowMode === 'import' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Custom Strategy Import</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Bring your own existing MQL5 robot or PineScript logic. Our Parser will read its inputs and evolve its parameters.
                            </p>
                        </div>

                    </div>

                </div>
            )}

            {selectedPlatform === 'pine' && (
                <div className="card" style={{ borderTop: '4px solid #ffaa00', marginBottom: '20px', animation: 'fadeIn 0.3s' }}>
                    <h3 style={{ textAlign: 'center', marginBottom: '20px', color: '#ffaa00' }}>1. TradingView / Pine Workflow</h3>
                    <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap' }}>

                        <div
                            onClick={() => { setWorkflowMode('import'); setSelectedEA('custom'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'import' ? 'rgba(255, 170, 0, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'import' ? '2px solid #ffaa00' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'import' ? '0 0 15px rgba(255,170,0,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📥</div>
                            <h4 style={{ color: workflowMode === 'import' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Custom Strategy Import</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Upload a PineScript strategy code. <br /><br /><span style={{ color: '#ffaa00' }}>⚠️ Ensure it compiles successfully in TradingView first.</span>
                            </p>
                        </div>

                        <div
                            onClick={() => { setWorkflowMode('preloaded'); setSelectedEA('urb'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'preloaded' ? 'rgba(0, 255, 136, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'preloaded' ? '2px solid #00ff88' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'preloaded' ? '0 0 15px rgba(0,255,136,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>🤖</div>
                            <h4 style={{ color: workflowMode === 'preloaded' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Pre-Loaded Templates</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Optimize pre-built robust strategies dynamically mapped into the vectorized engine.
                            </p>
                        </div>

                        <div
                            onClick={() => { setWorkflowMode('indicators'); setSelectedEA('indicator'); }}
                            style={{
                                flex: '1 1 250px', padding: '20px', textAlign: 'center', cursor: 'pointer',
                                background: workflowMode === 'indicators' ? 'rgba(0, 204, 255, 0.15)' : '#1a1a1a',
                                border: workflowMode === 'indicators' ? '2px solid #00ccff' : '1px solid #333',
                                borderRadius: '8px', transition: 'all 0.2s',
                                boxShadow: workflowMode === 'indicators' ? '0 0 15px rgba(0,204,255,0.3)' : 'none'
                            }}
                        >
                            <div style={{ fontSize: '2.5rem', marginBottom: '10px' }}>📊</div>
                            <h4 style={{ color: workflowMode === 'indicators' ? '#fff' : '#aaa', margin: '0 0 10px 0' }}>Custom Indicators</h4>
                            <p style={{ fontSize: '0.8rem', color: '#888' }}>
                                Create, upload, and test custom PineScript indicators securely.
                            </p>
                        </div>

                    </div>

                </div>
            )}

            {workflowMode && (
                <div style={{ animation: 'fadeIn 0.5s ease-in' }}>
                    {/* STEP 2: CONNECTION (Only non-Pine) */}
                    {selectedPlatform !== 'pine' && (
                        <div className="card">
                            <h3>1. 🔌 Broker Connection</h3>
                            <div style={{ display: 'flex', gap: '15px', alignItems: 'flex-end', flexWrap: 'wrap' }}>
                                <div style={{ flex: '1 1 300px' }}>
                                    <label>Select MT5 Terminal:</label>
                                    <select
                                        style={{
                                            width: '100%',
                                            padding: '10px',
                                            marginTop: '5px',
                                            background: '#222',
                                            color: '#fff',
                                            border: connError ? '1px solid #ff4444' : '1px solid #444',
                                            borderRadius: '4px'
                                        }}
                                        value={selectedTerminal}
                                        onChange={(e) => {
                                            setSelectedTerminal(e.target.value);
                                            setConnError(false);
                                            setConnectionMsg('');
                                            setAccountInfo(null);
                                        }}
                                    >
                                        {terminals.map((t, idx) => <option key={idx} value={t}>{t}</option>)}
                                    </select>
                                    {/* Error Message directly below select if failed */}
                                    {connError && <div style={{ color: '#ff4444', fontSize: '0.8rem', marginTop: '5px' }}>{connectionMsg}</div>}
                                </div>
                                <button className="primary-btn" onClick={handleConnect} style={{ height: '42px', minWidth: '100px', flex: '0 0 auto', marginRight: '20px' }}>Connect</button>
                                <div style={{ flex: '0 0 120px' }}> {/* Fixed width for capital input */}
                                    <label style={{ fontSize: '0.85rem', color: '#888' }}>Initial Capital ($)</label>
                                    <input
                                        type="number"
                                        value={initialCapital}
                                        onChange={(e) => setInitialCapital(e.target.value)}
                                        style={{ width: '100%', padding: '10px', marginTop: '5px', background: '#222', color: '#fff', border: '1px solid #444', borderRadius: '4px' }}
                                    />
                                </div>
                                <div style={{ flex: '0 0 120px' }}>
                                    <label style={{ fontSize: '0.85rem', color: '#888' }}>Delay (ms)</label>
                                    <input
                                        type="number"
                                        value={brokerDelay}
                                        onChange={(e) => setBrokerDelay(e.target.value)}
                                        placeholder="e.g. 50"
                                        style={{ width: '100%', padding: '10px', marginTop: '5px', background: '#222', color: '#fff', border: '1px solid #444', borderRadius: '4px' }}
                                    />
                                </div>
                                <div style={{ flex: '0 0 120px' }}>
                                    <label style={{ fontSize: '0.85rem', color: '#888' }}>Comms/Lot ($)</label>
                                    <input
                                        type="number"
                                        step="0.1"
                                        value={brokerCommission}
                                        onChange={(e) => setBrokerCommission(e.target.value)}
                                        placeholder="e.g. 7.00"
                                        style={{ width: '100%', padding: '10px', marginTop: '5px', background: '#222', color: '#fff', border: '1px solid #444', borderRadius: '4px' }}
                                    />
                                </div>
                            </div>

                            {/* Account Info Bar */}
                            {accountInfo && (
                                <div style={{ marginTop: '15px', padding: '10px', background: 'rgba(0, 255, 136, 0.1)', border: '1px solid #00ff88', borderRadius: '4px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                    <div style={{ fontWeight: 'bold', color: '#00ff88' }}>✅ Connected: {accountInfo.name} ({accountInfo.company})</div>
                                    <div style={{ color: '#fff', fontSize: '0.9rem' }}>Account: {accountInfo.login} | Server: {accountInfo.server}</div>
                                    <div style={{ fontWeight: 'bold', color: '#fff' }}>Balance: {accountInfo.balance} {accountInfo.currency}</div>
                                </div>
                            )}

                            {!accountInfo && connectionMsg && <div style={{ marginTop: '10px', fontSize: '0.9rem', color: connectionMsg.includes('❌') ? '#ff4444' : '#fff' }}>{connectionMsg}</div>}
                        </div>
                    )}

                    {/* STEP 2: STRATEGY (Conditional) */}
                    {workflowMode === 'preloaded' && (
                        <div className="card" style={{ animation: 'fadeIn 0.3s' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <h3>2. 🤖 Select Pre-Loaded Strategy Template</h3>
                            </div>
                            <div style={{ display: 'flex', gap: '15px', marginBottom: 20, marginTop: 10 }}>
                                {EAS.map(ea => (
                                    <div
                                        key={ea.id}
                                        onClick={() => { if (ea.active) { setSelectedEA(ea.id); setImportedStrategy(null); setImportStatus('idle'); setImportMsg(''); } }}
                                        style={{
                                            flex: 1, padding: '15px',
                                            background: selectedEA === ea.id ? 'rgba(0, 255, 136, 0.1)' : '#222',
                                            border: selectedEA === ea.id ? '2px solid #00ff88' : '1px solid #444',
                                            borderRadius: '8px', cursor: ea.active ? 'pointer' : 'not-allowed',
                                            opacity: ea.active ? 1 : 0.5, transition: 'all 0.2s'
                                        }}
                                    >
                                        <div style={{ fontWeight: 'bold', color: ea.active ? '#fff' : '#888' }}>{ea.name}</div>
                                        <div style={{ fontSize: '0.8rem', color: '#888', marginTop: '5px' }}>{ea.desc}</div>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}

                    {workflowMode === 'import' && (
                        <div className="card" style={{ animation: 'fadeIn 0.3s' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '20px' }}>
                                <h3>2. 📥 Import Custom MQ5 Logic</h3>

                                {/* AI Provider Settings */}
                                <div style={{ display: 'flex', gap: '10px', alignItems: 'center', background: '#222', padding: '10px', borderRadius: '8px', border: '1px solid #444' }}>
                                    <div>
                                        <label style={{ fontSize: '0.8rem', color: '#aaa', display: 'block', marginBottom: '4px' }}>AI Engine</label>
                                        <select
                                            value={aiProvider}
                                            onChange={(e) => setAiProvider(e.target.value)}
                                            style={{ padding: '6px', background: '#111', color: '#fff', border: '1px solid #555', borderRadius: '4px' }}
                                        >
                                            <option value="ollama">Ollama (Local / Free)</option>
                                            <option value="api">URB Cloud AI (Pro/Ultra Fast)</option>
                                        </select>
                                    </div>
                                    {aiProvider === 'api' && (
                                        <div style={{ padding: '6px 12px', background: 'rgba(0, 204, 255, 0.1)', border: '1px solid #00ccff', borderRadius: '4px', fontSize: '0.8rem', color: '#00ccff' }}>
                                            ⚡ Powered by Private Enterprise RAG
                                        </div>
                                    )}
                                </div>

                                {/* Dynamic Upload Section based on Platform */}
                                <div style={{ textAlign: 'right' }}>
                                    <input
                                        type="file"
                                        accept={selectedPlatform === 'pine' ? ".pine,.txt" : ".mq5,.mq4"}
                                        id="strategy-upload"
                                        style={{ display: 'none' }}
                                        onChange={handleImport}
                                        disabled={importStatus === 'loading'}
                                    />
                                    <label htmlFor="strategy-upload" className="secondary-btn" style={{ cursor: importStatus === 'loading' ? 'not-allowed' : 'pointer', border: '1px dashed #ffaa00', color: '#ffaa00', display: 'inline-block', opacity: importStatus === 'loading' ? 0.5 : 1 }}>
                                        {importStatus === 'loading' ? '⏳ Processing AI...' : `📥 Upload ${selectedPlatform === 'pine' ? '.PINE' : '.MQ5'} File`}
                                    </label>
                                    {importMsg && (<div style={{ fontSize: '0.8rem', marginTop: 5, color: importStatus === 'error' ? '#ff5555' : (importStatus === 'loading' ? '#00ccff' : '#00ff88') }}>{importMsg}</div>)}
                                </div>
                            </div>

                            <div style={{ marginTop: '15px', color: '#888', fontSize: '0.9rem' }}>
                                {selectedPlatform === 'pine' ?
                                    (<span>Upload any valid PineScript strategy code. Our engine will map its external parameters and verify logic using the selected AI engine. <strong style={{ color: "#ffaa00" }}>Make sure it works in TradingView first!</strong></span>) :
                                    ("Upload any valid MetaTrader 5 Expert Advisor source code. Our engine will map its external parameters and translate its logic into native Python using the selected AI engine.")
                                }
                            </div>

                            {/* Custom Strategy Card */}
                            {importedStrategy && (() => {
                                const hasAiError = importedStrategy.ai_status && importedStrategy.ai_status.includes('[ERROR');
                                const bgStyle = hasAiError ? 'rgba(255, 85, 85, 0.1)' : (importStatus === 'confirmed' ? 'rgba(0, 255, 136, 0.1)' : 'rgba(255, 170, 0, 0.1)');
                                const borderStyle = hasAiError ? '2px solid #ff5555' : (importStatus === 'confirmed' ? '2px solid #00ff88' : '2px dashed #ffaa00');
                                const statusColor = hasAiError ? '#ff5555' : (importStatus === 'confirmed' ? '#00ff88' : '#ffaa00');

                                return (
                                    <>
                                        <div
                                            onClick={() => !hasAiError && setSelectedEA('custom')}
                                            style={{
                                                marginTop: '15px', padding: '15px',
                                                background: bgStyle,
                                                border: borderStyle,
                                                borderRadius: '8px', cursor: hasAiError ? 'not-allowed' : 'pointer', transition: 'all 0.2s'
                                            }}
                                        >
                                            <div style={{ fontWeight: 'bold', color: '#fff' }}>📄 {importedStrategy.filename}</div>
                                            <div style={{ fontSize: '0.8rem', color: statusColor, marginTop: '5px' }}>
                                                {hasAiError ? 'AI Verification Failed (Cannot Proceed)' : (importStatus === 'confirmed' ? 'Active & Confirmed' : (selectedPlatform === 'pine' ? 'Ready for Parameter Mapping' : 'Ready for Digital Twin Verification'))}
                                            </div>
                                            <div style={{ fontSize: '0.75rem', color: hasAiError ? '#ff77aa' : '#00ccff', marginTop: '4px', wordBreak: 'break-word', whiteSpace: 'pre-wrap' }}>
                                                🤖 AI Status: {importedStrategy.ai_status}
                                            </div>
                                            <div style={{ fontSize: '0.7rem', color: '#888', marginTop: '4px' }}>{importedStrategy.inputs?.length || 0} Inputs Detected</div>
                                        </div>

                                        {/* Digital Twin Preview */}
                                        {selectedEA === 'custom' && !hasAiError && (
                                            <div style={{ marginTop: 15, background: '#1a1a1a', padding: 15, borderRadius: 6, border: '1px solid #333' }}>
                                                <h4 style={{ margin: '0 0 10px 0', color: '#00ccff' }}>🧬 Digital Twin: Logic & Inputs Structure</h4>
                                                <div style={{ maxHeight: '250px', overflowY: 'auto', marginBottom: 15 }}>
                                                    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
                                                        <thead style={{ position: 'sticky', top: 0, background: '#1a1a1a' }}>
                                                            <tr style={{ color: '#888', textAlign: 'left', borderBottom: '1px solid #444' }}>
                                                                <th style={{ padding: 8 }}>Input Name</th>
                                                                <th style={{ padding: 8 }}>Type</th>
                                                                <th style={{ padding: 8 }}>Default</th>
                                                                <th style={{ padding: 8 }}>Comment (Label)</th>
                                                            </tr>
                                                        </thead>
                                                        <tbody>
                                                            {importedStrategy.inputs.map((inp, idx) => (
                                                                <tr key={idx} style={{ borderBottom: '1px solid #2a2a2a' }}>
                                                                    <td style={{ padding: 8, color: '#ff77aa' }}>{inp.name}</td>
                                                                    <td style={{ padding: 8, color: '#aaa' }}>{inp.type}</td>
                                                                    <td style={{ padding: 8, color: '#fff' }}>{String(inp.default)}</td>
                                                                    <td style={{ padding: 8, color: '#00ff88', fontStyle: 'italic' }}>{inp.label}</td>
                                                                </tr>
                                                            ))}
                                                        </tbody>
                                                    </table>
                                                </div>

                                                {/* Accept Button */}
                                                {importStatus !== 'confirmed' && (
                                                    <div style={{ textAlign: 'right' }}>
                                                        <button
                                                            className="primary-btn"
                                                            onClick={handleAcceptStrategy}
                                                            style={{ background: '#00ff88', color: '#000', padding: '10px 30px', fontWeight: 'bold' }}
                                                        >
                                                            ✅ Accept & Use This Strategy
                                                        </button>
                                                    </div>
                                                )}
                                                {importStatus === 'confirmed' && (
                                                    <div style={{ textAlign: 'center', padding: 10, background: 'rgba(0,255,136,0.1)', color: '#00ff88', borderRadius: 4, fontWeight: 'bold' }}>
                                                        Strategy Locked & Ready for Builder
                                                    </div>
                                                )}
                                            </div>
                                        )}
                                    </>
                                );
                            })()}
                        </div>
                    )}

                    {/* STEP 3: ASSET SELECTION (Only non-Pine initially, or modify step numbering later) */}
                    {selectedPlatform !== 'pine' && (
                        <div className="card">
                            <h3>3. 📈 Market Selection</h3>

                            {/* Categories */}
                            <div style={{ display: 'flex', gap: '10px', marginBottom: '15px', borderBottom: '1px solid #333', paddingBottom: '10px' }}>
                                {Object.keys(ASSET_CATEGORIES).map(cat => (
                                    <button
                                        key={cat}
                                        onClick={() => setSelectedCategory(cat)}
                                        style={{
                                            background: 'none',
                                            border: 'none',
                                            borderBottom: selectedCategory === cat ? '2px solid #00ccff' : '2px solid transparent',
                                            color: selectedCategory === cat ? '#00ccff' : '#888',
                                            padding: '5px 15px',
                                            cursor: 'pointer',
                                            fontWeight: 'bold'
                                        }}
                                    >
                                        {cat}
                                    </button>
                                ))}
                            </div>

                            {/* Symbols Grid */}
                            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(100px, 1fr))', gap: '10px', marginBottom: '20px' }}>
                                {ASSET_CATEGORIES[selectedCategory].map(sym => (
                                    <button
                                        key={sym}
                                        onClick={() => handleSelectSymbol(sym)}
                                        style={{
                                            padding: '10px',
                                            background: selectedSymbol === sym ? '#00ccff' : '#333',
                                            color: selectedSymbol === sym ? '#000' : '#fff',
                                            border: 'none',
                                            borderRadius: '4px',
                                            cursor: 'pointer',
                                            fontWeight: 'bold'
                                        }}
                                    >
                                        {sym}
                                    </button>
                                ))}
                            </div>

                            {/* Asset Info Card */}
                            {symbolInfo && !symbolInfo.error && (
                                <div style={{
                                    background: 'linear-gradient(145deg, #1e1e1e 0%, #292929 100%)',
                                    border: '1px solid #444',
                                    borderRadius: '8px',
                                    padding: '24px',
                                    boxShadow: '0 4px 20px rgba(0,0,0,0.5)'
                                }}>
                                    <div style={{ display: 'flex', justifyContent: 'space-between', borderBottom: '1px solid #444', paddingBottom: '15px', marginBottom: '20px' }}>
                                        <div>
                                            <div style={{ fontSize: '0.85rem', color: '#888', letterSpacing: '1px' }}>BROKER SYMBOL</div>
                                            <div style={{ fontSize: '2rem', fontWeight: 'bold', color: '#00ff88', textShadow: '0 0 10px rgba(0, 255, 136, 0.3)' }}>
                                                {symbolInfo.mapped_name}
                                            </div>
                                            <div style={{ fontSize: '0.85rem', color: '#aaa', marginTop: '5px' }}>
                                                {symbolInfo.info.description}
                                            </div>
                                        </div>

                                        <div style={{ textAlign: 'right' }}>
                                            <div style={{ fontSize: '0.85rem', color: '#888' }}>CURRENT PRICE</div>
                                            <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: '#fff' }}>
                                                --.--
                                                {/* Real-time price requires streaming, keep placeholder or fetch once. */}
                                            </div>
                                            <div style={{ fontSize: '0.8rem', color: '#00ccff' }}>
                                                Pending MT5 Stream
                                            </div>
                                        </div>
                                    </div>

                                    {/* Stats Grid */}
                                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }}>
                                        <InfoStat label="SPREAD" value={symbolInfo.info.spread_float ? "Floating" : "Fixed"} highlight="#00ff88" />
                                        <InfoStat label="DIGITS" value={symbolInfo.info.digits} />
                                        <InfoStat label="CONTRACT SIZE" value={symbolInfo.info.contract_size} />
                                        <InfoStat label="MIN LOT" value={symbolInfo.info.volume_min} />

                                        <InfoStat label="MARGIN CCY" value={symbolInfo.info.margin_currency} />
                                        <InfoStat label="PROFIT CCY" value={symbolInfo.info.profit_currency} />
                                        <InfoStat label="TRIPLE SWAP" value={symbolInfo.info.swap_3day} />
                                        <InfoStat label="TICK VALUE" value={symbolInfo.info.tick_value} />

                                        <InfoStat label="SWAP LONG" value={symbolInfo.info.swap_long} />
                                        <InfoStat label="SWAP SHORT" value={symbolInfo.info.swap_short} />
                                        <InfoStat label="COMMISSION" value="N/A" sub="(Complex Calc)" />
                                    </div>
                                </div>
                            )}

                            {symbolInfo && symbolInfo.error && (
                                <div style={{ padding: '15px', background: '#300', color: '#ff5555', borderRadius: '4px', border: '1px solid #f00' }}>
                                    ⚠️ {symbolInfo.error} (Is Broker Connected?)
                                </div>
                            )}
                        </div>
                    )}

                    <DataControlCard
                        onNext={onNext}
                        strategyConfirmed={isStrategyReady}
                        selectedPlatform={selectedPlatform}
                        dataSourceType={dataSourceType}
                        setDataSourceType={setDataSourceType}
                        mt5Timezone={mt5Timezone}
                        setMt5Timezone={setMt5Timezone}
                    />
                </div>
            )}
        </div>
    );
};

// Helper Component for Stats
const InfoStat = ({ label, value, highlight, sub }) => (
    <div style={{ padding: '10px', background: 'rgba(255,255,255,0.03)', borderRadius: '6px' }}>
        <div style={{ fontSize: '0.75rem', color: '#888', marginBottom: '5px', textTransform: 'uppercase' }}>{label}</div>
        <div style={{ fontSize: '1.1rem', fontWeight: 'bold', color: highlight || '#fff' }}>{value}</div>
        {sub && <div style={{ fontSize: '0.7rem', color: '#666' }}>{sub}</div>}
    </div>
);

const DataControlCard = ({
    onNext,
    strategyConfirmed,
    selectedPlatform,
    dataSourceType,
    setDataSourceType,
    mt5Timezone,
    setMt5Timezone
}) => {
    const [dataStatus, setDataStatus] = useState(null);
    const [split, setSplit] = useState(80);
    const [splitMode, setSplitMode] = useState('standard'); // 'standard' or 'adv'
    const [activeTab, setActiveTab] = useState('folder'); // 'folder' or 'upload'
    const [modelingType, setModelingType] = useState('m1_ohlc'); // 'm1_ohlc' or 'tick'

    // Model Confirmation State
    const [modelStatus, setModelStatus] = useState('idle'); // idle, confirmed, error
    const [modelMsg, setModelMsg] = useState("");

    // Folder State
    const [folderPath, setFolderPath] = useState('');
    const [folderFiles, setFolderFiles] = useState([]);
    const [folderError, setFolderError] = useState('');
    const [selectedFile, setSelectedFile] = useState('');

    // Upload State
    const [uploadMsg, setUploadMsg] = useState("");

    const refreshStatus = async () => {
        try {
            const res = await axios.get('http://127.0.0.1:8000/api/data/status');
            setDataStatus(res.data);
            if (res.data.loaded) {
                // Backend stores OOS% (e.g. 0.2). Frontend 'split' is IS% (e.g. 80).
                // So split = 100 - (oos_pct * 100)
                setSplit(100 - (res.data.oos_pct * 100));
                if (res.data.modeling_type) setModelingType(res.data.modeling_type);
            }
        } catch (e) {
            console.warn("Data API offline");
        }
    };

    const refreshFolder = async () => {
        try {
            const res = await axios.get('http://127.0.0.1:8000/api/data/files');
            setFolderPath(res.data.folder || "");
            setFolderFiles(res.data.files || []);
            setFolderError(res.data.error || "");
        } catch (e) {
            console.error("Folder scan error", e);
        }
    };

    useEffect(() => {
        refreshStatus();
        refreshFolder();
    }, []);

    const handleSetFolder = async () => {
        try {
            await axios.post('http://127.0.0.1:8000/api/data/config/directory', null, { params: { path: folderPath } });
            refreshFolder();
        } catch (e) {
            alert("Error setting folder: " + (e.response?.data?.detail || e.message));
        }
    };

    const handleLoadFile = async (filenameOverride) => {
        const filename = filenameOverride || selectedFile;
        if (!filename) return;
        try {
            const payload = {
                filename,
                source_type: 'folder'
            };

            // Add extra metadata for Pine platform (Timezone conversion & format)
            if (selectedPlatform === 'pine') {
                payload.data_format = dataSourceType; // 'tv' or 'mt5'
                payload.timezone_offset = mt5Timezone;
            }

            await axios.post('http://127.0.0.1:8000/api/data/load', payload);
            refreshStatus();
            setModelStatus('idle');
            setModelMsg("");
        } catch (e) {
            alert("Load Failed: " + (e.response?.data?.detail || e.message));
        }
    };

    const updateConfig = async (start, end, currentSplit, currentModel) => {
        if (!dataStatus) return;
        try {
            // Validate limits
            if (start < dataStatus.min_date) start = dataStatus.min_date;
            if (end > dataStatus.max_date) end = dataStatus.max_date;

            // Send OOS Percentage to Backend (1.0 - IS%)
            await axios.post('http://127.0.0.1:8000/api/data/config/range', {
                start_date: start,
                end_date: end,
                oos_pct: (100 - currentSplit) / 100.0,
                modeling_type: currentModel
            });
        } catch (e) {
            console.error("Config update failed", e);
        }
    };

    const handleAcceptModeling = () => {
        if (!dataStatus) return;
        const fname = dataStatus.filename.toLowerCase();

        // 1. Validation Logic
        if (modelingType === 'tick') {
            if (fname.includes('m1') && !fname.includes('tick')) {
                setModelStatus('error');
                setModelMsg("❌ Error: Incompatible! Cannot use Real Ticks on M1 Data.");
                return;
            }
        } else if (modelingType === 'm1_ohlc') {
            if (fname.includes('tick') && !fname.includes('m1')) {
                // Warning typically, but user requested strict "sintonia"
                setModelStatus('error');
                setModelMsg("❌ Error: Incompatible! Should use Tick Modeling for Tick Data.");
                return;
            }
        }

        // 2. Success
        setModelStatus('confirmed');
        setModelMsg(`✅ Modeling Confirmed: ${modelingType === 'tick' ? 'Real Ticks' : 'M1 OHLC'}`);
        // Ensure backend is synced
        updateConfig(dataStatus.active_start, dataStatus.active_end, split, modelingType);
    };

    return (
        <div className="card" style={{ borderTop: '4px solid #00ff88' }}>
            <h3>4. 💾 Historical Data (M1 or Tick)</h3>

            {selectedPlatform === 'pine' && (
                <div style={{ marginBottom: '20px', animation: 'fadeIn 0.3s' }}>
                    <div style={{ display: 'flex', gap: '20px', background: 'rgba(255,170,0,0.03)', padding: '15px', borderRadius: '8px', border: '1px solid #333', marginBottom: '15px' }}>
                        <div style={{ flex: 1 }}>
                            <label style={{ display: 'block', marginBottom: '8px', color: '#ffaa00', fontSize: '0.85rem', fontWeight: 'bold', textTransform: 'uppercase', letterSpacing: '1px' }}>
                                📂 Data Source Format:
                            </label>
                            <div style={{ display: 'flex', gap: '10px' }}>
                                <button
                                    onClick={() => setDataSourceType('tv')}
                                    style={{
                                        flex: 1, padding: '12px', borderRadius: '6px', border: '1px solid',
                                        background: dataSourceType === 'tv' ? 'rgba(0, 255, 136, 0.1)' : '#1a1a1a',
                                        color: dataSourceType === 'tv' ? '#00ff88' : '#888',
                                        borderColor: dataSourceType === 'tv' ? '#00ff88' : '#333',
                                        cursor: 'pointer', transition: 'all 0.2s', fontWeight: 'bold'
                                    }}
                                >
                                    🔵 TradingView Native (CSV)
                                </button>
                                <button
                                    onClick={() => setDataSourceType('mt5')}
                                    style={{
                                        flex: 1, padding: '12px', borderRadius: '6px', border: '1px solid',
                                        background: dataSourceType === 'mt5' ? 'rgba(0, 204, 255, 0.1)' : '#1a1a1a',
                                        color: dataSourceType === 'mt5' ? '#00ccff' : '#888',
                                        borderColor: dataSourceType === 'mt5' ? '#00ccff' : '#333',
                                        cursor: 'pointer', transition: 'all 0.2s', fontWeight: 'bold'
                                    }}
                                >
                                    🔴 MT5 / External CSV
                                </button>
                            </div>
                        </div>

                        {dataSourceType === 'mt5' && (
                            <div style={{ width: '220px', animation: 'slideInRight 0.3s' }}>
                                <label style={{ display: 'block', marginBottom: '8px', color: '#00ccff', fontSize: '0.85rem', fontWeight: 'bold' }}>
                                    🕒 Timezone Conversion:
                                </label>
                                <select
                                    value={mt5Timezone}
                                    onChange={(e) => setMt5Timezone(e.target.value)}
                                    style={{ ...inputStyle, width: '100%', height: '42px', cursor: 'pointer', border: '1px solid #00ccff' }}
                                >
                                    <option value="UTC+0">UTC/GMT (TV Default)</option>
                                    <option value="UTC+1">UTC+1 (London Win)</option>
                                    <option value="UTC+2">UTC+2 (Europe / Broker)</option>
                                    <option value="UTC+3">UTC+3 (Broker Moscow)</option>
                                    <option value="UTC-5">UTC-5 (New York / EST)</option>
                                </select>
                            </div>
                        )}
                    </div>

                    {dataSourceType === 'mt5' && (
                        <div style={{
                            padding: '12px 15px',
                            background: 'rgba(255, 170, 0, 0.1)',
                            borderLeft: '4px solid #ffaa00',
                            borderRadius: '4px',
                            color: '#ffaa00',
                            fontSize: '0.85rem',
                            marginBottom: '20px'
                        }}>
                            <strong>⚠️ IMPORTANT:</strong> You are loading MT5 data for a PineScript logic.
                            Prices, spreads and volume may vary from TradingView providers (OANDA, ICE, etc).
                            <br />
                            <em>Results in small timeframes (M1-M15) might show significant drift. H1+ recommended for cross-platform data.</em>
                        </div>
                    )}
                </div>
            )}

            {!dataStatus?.loaded ? (
                <div>
                    <div style={{ display: 'flex', borderBottom: '1px solid #444', marginBottom: 20 }}>
                        <button
                            onClick={() => setActiveTab('folder')}
                            style={{
                                padding: '10px 20px',
                                background: activeTab === 'folder' ? 'rgba(0,255,136,0.1)' : 'transparent',
                                border: 'none',
                                borderBottom: activeTab === 'folder' ? '2px solid #00ff88' : '2px solid transparent',
                                color: activeTab === 'folder' ? '#00ff88' : '#888',
                                cursor: 'pointer', fontWeight: 'bold'
                            }}
                        >
                            📂 Local Folder Scan
                        </button>
                        <button
                            onClick={() => setActiveTab('upload')}
                            style={{
                                padding: '10px 20px',
                                background: activeTab === 'upload' ? 'rgba(0,204,255,0.1)' : 'transparent',
                                border: 'none',
                                borderBottom: activeTab === 'upload' ? '2px solid #00ccff' : '2px solid transparent',
                                color: activeTab === 'upload' ? '#00ccff' : '#888',
                                cursor: 'pointer', fontWeight: 'bold'
                            }}
                        >
                            📤 Manual Upload
                        </button>
                    </div>

                    {activeTab === 'folder' && (
                        <div style={{ animation: 'fadeIn 0.3s' }}>
                            <div style={{ display: 'flex', gap: 10, marginBottom: 15 }}>
                                <input
                                    type="text"
                                    value={folderPath}
                                    onChange={(e) => setFolderPath(e.target.value)}
                                    placeholder="C:\Path\To\Data"
                                    style={{ ...inputStyle, flex: 1 }}
                                />
                                <button onClick={handleSetFolder} className="secondary-btn" style={{ whiteSpace: 'nowrap' }}>🔄 Scan</button>
                            </div>

                            {folderError && <div style={{ color: '#ff5555', marginBottom: 10, fontSize: '0.9rem' }}>⚠️ {folderError}</div>}

                            {folderFiles.length === 0 ? (
                                <div style={{ padding: 20, textAlign: 'center', color: '#666', border: '1px dashed #444', borderRadius: 4 }}>
                                    No CSV or Parquet files found in this folder.
                                </div>
                            ) : (
                                <div style={{ maxHeight: '200px', overflowY: 'auto', border: '1px solid #333', borderRadius: 4 }}>
                                    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.9rem' }}>
                                        <thead>
                                            <tr style={{ background: '#222', textAlign: 'left', color: '#888' }}>
                                                <th style={{ padding: 8 }}>File Name</th>
                                                <th style={{ padding: 8 }}>Size</th>
                                                <th style={{ padding: 8 }}>Modified</th>
                                                <th style={{ padding: 8 }}>Action</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {folderFiles.map(f => (
                                                <tr key={f.name} style={{ borderBottom: '1px solid #2a2a2a' }}>
                                                    <td style={{ padding: 8, color: '#ddd' }}>{f.name}</td>
                                                    <td style={{ padding: 8, color: '#888' }}>{f.size_mb} MB</td>
                                                    <td style={{ padding: 8, color: '#888' }}>{f.modified}</td>
                                                    <td style={{ padding: 8 }}>
                                                        <button
                                                            onClick={() => {
                                                                setSelectedFile(f.name);
                                                                handleLoadFile(f.name);
                                                            }}
                                                            style={{
                                                                background: '#00cc88', color: '#000', border: 'none',
                                                                padding: '4px 8px', borderRadius: 4, cursor: 'pointer', fontWeight: 'bold'
                                                            }}
                                                        >
                                                            Load
                                                        </button>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </div>
                    )}

                    {activeTab === 'upload' && (
                        <div style={{ animation: 'fadeIn 0.3s', padding: 20, border: '1px dashed #444', borderRadius: 8, textAlign: 'center' }}>
                            <input
                                type="file"
                                accept=".csv,.parquet"
                                id="data-upload"
                                style={{ display: 'none' }}
                                onChange={async (e) => {
                                    if (e.target.files.length === 0) return;
                                    const file = e.target.files[0];
                                    const formData = new FormData();
                                    formData.append("file", file);

                                    // Add extra metadata for Pine platform
                                    if (selectedPlatform === 'pine') {
                                        formData.append("data_format", dataSourceType);
                                        formData.append("timezone_offset", mt5Timezone);
                                    }

                                    try {
                                        setUploadMsg("Uploading & Parsing...");
                                        await axios.post('http://127.0.0.1:8000/api/data/upload', formData, {
                                            headers: { 'Content-Type': 'multipart/form-data' }
                                        });
                                        // Force UI refresh after upload
                                        await refreshStatus();
                                        setModelStatus('idle');
                                        setModelMsg("");
                                        setUploadMsg("✅ Done!");
                                        setTimeout(() => setUploadMsg(""), 2000);
                                    } catch (err) {
                                        console.error(err);
                                        alert("Upload Failed: " + (err.response?.data?.detail || err.message));
                                        setUploadMsg("Error.");
                                    }
                                }}
                            />
                            <label
                                htmlFor="data-upload"
                                className="primary-btn"
                                style={{
                                    display: 'inline-block',
                                    padding: '15px 30px',
                                    cursor: 'pointer',
                                    fontSize: '1.1rem',
                                    border: '2px solid #00ccff',
                                    background: 'rgba(0, 204, 255, 0.1)',
                                    color: '#00ccff'
                                }}
                            >
                                📤 Select CSV / Parquet File
                            </label>
                            <div style={{ color: '#00ccff', marginTop: 10 }}>{uploadMsg}</div>
                            <div style={{ fontSize: '0.8rem', color: '#666', marginTop: 5 }}>Supports: MT5 Export CSV (No Header) or Standard CSV/Parquet</div>
                        </div>
                    )}
                </div>
            ) : (
                <div>
                    {/* Data Success Message */}
                    <div style={{ marginBottom: 20, background: 'rgba(0, 255, 136, 0.1)', border: '1px solid #00ff88', borderRadius: '8px', padding: '20px', textAlign: 'center' }}>
                        <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: '#00ff88', marginBottom: '5px' }}>✅ DATA LOADED SUCCESSFULLY</div>
                        <div style={{ fontSize: '1rem', color: '#fff', marginBottom: '10px' }}>{dataStatus.filename}</div>
                        <div style={{ fontSize: '0.9rem', color: '#aaa' }}>
                            Available Range: <span style={{ color: '#fff' }}>{dataStatus.min_date}</span> to <span style={{ color: '#fff' }}>{dataStatus.max_date}</span>
                        </div>
                        <div style={{ fontSize: '0.8rem', color: '#666', marginTop: '5px' }}>
                            Contains {(dataStatus.total_rows / 1000).toFixed(0)}k M1 Bars
                        </div>
                        {/* Note: In-Sample/Out-Of-Sample config moved to Builder Stage */}
                        <div style={{ fontSize: '0.7rem', color: '#888', marginTop: '10px', fontStyle: 'italic' }}>
                            Ready for analysis in Strategy Builder.
                        </div>

                        <button
                            onClick={() => { if (window.confirm('Clear Data?')) setDataStatus(null); }}
                            style={{ background: 'none', border: 'none', color: '#ff5555', cursor: 'pointer', marginTop: '15px', textDecoration: 'underline' }}
                        >
                            Unload Data
                        </button>
                    </div>

                    {/* Modeling Type Selector */}
                    <div style={{ marginBottom: 20, background: '#222', padding: 15, borderRadius: 4, border: '1px solid #333' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                            <label style={{ color: '#aaa', fontSize: '0.85rem' }}>DATA MODELING TYPE</label>
                            {modelStatus === 'confirmed' && <span style={{ color: '#00ff88', fontWeight: 'bold', fontSize: '0.8rem' }}>🔒 LOCKED</span>}
                        </div>

                        <div style={{ display: 'flex', gap: 20, marginTop: 10, opacity: modelStatus === 'confirmed' ? 0.5 : 1, pointerEvents: modelStatus === 'confirmed' ? 'none' : 'auto' }}>
                            <div
                                onClick={() => { setModelingType('m1_ohlc'); }}
                                style={{
                                    cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
                                    color: modelingType === 'm1_ohlc' ? '#00ff88' : '#666'
                                }}
                            >
                                <div style={{
                                    width: 16, height: 16, borderRadius: '50%', border: '2px solid',
                                    backgroundColor: modelingType === 'm1_ohlc' ? '#00ff88' : 'transparent',
                                    borderColor: modelingType === 'm1_ohlc' ? '#00ff88' : '#666'
                                }}></div>
                                <span>M1 OHLC (Default)</span>
                            </div>

                            <div
                                onClick={() => { setModelingType('tick'); }}
                                style={{
                                    cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8,
                                    color: modelingType === 'tick' ? '#00ccff' : '#666'
                                }}
                            >
                                <div style={{
                                    width: 16, height: 16, borderRadius: '50%', border: '2px solid',
                                    backgroundColor: modelingType === 'tick' ? '#00ccff' : 'transparent',
                                    borderColor: modelingType === 'tick' ? '#00ccff' : '#666'
                                }}></div>
                                <span>Real Ticks (Precision)</span>
                            </div>
                        </div>

                        {/* Confirmation Controls */}
                        <div style={{ marginTop: 15, borderTop: '1px solid #333', paddingTop: 10 }}>
                            {modelStatus !== 'confirmed' && (
                                <button
                                    className="secondary-btn"
                                    onClick={handleAcceptModeling}
                                    style={{
                                        width: '100%',
                                        padding: '12px',
                                        backgroundColor: '#2a2a2a', /* Darker bg */
                                        color: '#00ccff', /* Cyan text for contrast */
                                        border: '1px solid #00ccff',
                                        borderRadius: '4px',
                                        fontWeight: 'bold',
                                        cursor: 'pointer',
                                        textTransform: 'uppercase',
                                        letterSpacing: '1px',
                                        transition: 'all 0.2s ease'
                                    }}
                                    onMouseOver={(e) => { e.currentTarget.style.backgroundColor = 'rgba(0, 204, 255, 0.1)'; }}
                                    onMouseOut={(e) => { e.currentTarget.style.backgroundColor = '#2a2a2a'; }}
                                >
                                    Confirm Modeling Type
                                </button>
                            )}

                            {modelMsg && (
                                <div style={{
                                    marginTop: 10,
                                    padding: 8,
                                    borderRadius: 4,
                                    background: modelStatus === 'error' ? 'rgba(255, 85, 85, 0.2)' : 'rgba(0, 255, 136, 0.2)',
                                    color: modelStatus === 'error' ? '#ff5555' : '#00ff88',
                                    textAlign: 'center',
                                    fontSize: '0.9rem',
                                    fontWeight: 'bold'
                                }}>
                                    {modelMsg}
                                </div>
                            )}
                        </div>
                    </div>

                    {/* DATA PARTITION CONFIGURATION (Appears after Modeling Confirmed) */}
                    {modelStatus === 'confirmed' && (
                        <div style={{ marginBottom: 20, background: '#1a1a1a', padding: 20, borderRadius: 8, border: '1px solid #444', animation: 'fadeIn 0.5s' }}>
                            <h4 style={{ margin: '0 0 15px 0', color: '#fff', borderBottom: '1px solid #333', paddingBottom: 10 }}>
                                📊 Data Sample Partitioning
                            </h4>

                            {/* Section 1: Standard Splits */}
                            <div style={{ marginBottom: 25 }}>
                                <label style={{ color: '#00ff88', fontSize: '0.9rem', fontWeight: 'bold', marginBottom: 10, display: 'block' }}>
                                    Standard Configurations (Recommended)
                                </label>
                                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10 }}>
                                    {[
                                        { label: '80% / 20%', val: 80, oos: 20, rec: true },
                                        { label: '70% / 30%', val: 70, oos: 30 },
                                        { label: '60% / 40%', val: 60, oos: 40 },
                                        { label: '50% / 50%', val: 50, oos: 50 }
                                    ].map(opt => {
                                        const isActive = split === opt.val && splitMode === 'standard';
                                        return (
                                            <button
                                                key={opt.val}
                                                onClick={() => {
                                                    setSplit(opt.val);
                                                    setSplitMode('standard');
                                                    updateConfig(dataStatus.active_start, dataStatus.active_end, opt.val, modelingType);
                                                }}
                                                style={{
                                                    padding: '12px',
                                                    background: isActive ? 'rgba(0, 255, 136, 0.2)' : '#2a2a2a',
                                                    border: isActive ? '2px solid #00ff88' : '1px solid #444',
                                                    color: isActive ? '#00ff88' : '#aaa',
                                                    borderRadius: 4, cursor: 'pointer', fontWeight: 'bold', fontSize: '0.9rem',
                                                    transition: 'all 0.2s'
                                                }}
                                            >
                                                {opt.label}
                                                {opt.rec && <div style={{ fontSize: '0.6rem', color: '#888', marginTop: 2 }}>(Default)</div>}
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>

                            {/* Section 2: Advanced / Custom Splits (SQX Style) */}
                            <div>
                                <label style={{ color: '#00ccff', fontSize: '0.9rem', fontWeight: 'bold', marginBottom: 10, display: 'block' }}>
                                    Advanced / Custom Splits (SQX Style)
                                </label>
                                <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                                    {/* Mock Advanced Options */}
                                    {[
                                        { val: 50, label: '50% Train / 20% Val / 30% Test', segs: ['50%', '20%', '30%'] },
                                        { val: 30, label: '30% Train / 20% Val / 50% Test', segs: ['30%', '20%', '50%'] }
                                    ].map((opt, idx) => {
                                        const isActive = split === opt.val && splitMode === 'adv';
                                        return (
                                            <button
                                                key={idx}
                                                onClick={() => {
                                                    setSplit(opt.val);
                                                    setSplitMode('adv');
                                                    updateConfig(dataStatus.active_start, dataStatus.active_end, opt.val, modelingType);
                                                }}
                                                style={{
                                                    flex: 1, padding: 10,
                                                    background: isActive ? 'rgba(0, 204, 255, 0.15)' : '#222',
                                                    border: isActive ? '2px solid #00ccff' : '1px dashed #666',
                                                    color: isActive ? '#00ccff' : '#888',
                                                    borderRadius: 4, cursor: 'pointer',
                                                    transition: 'all 0.2s'
                                                }}
                                            >
                                                <div style={{ display: 'flex', height: 8, marginBottom: 5, borderRadius: 2, overflow: 'hidden', opacity: isActive ? 1 : 0.6 }}>
                                                    <div style={{ width: opt.segs[0], background: '#fff' }}></div>
                                                    <div style={{ width: opt.segs[1], background: '#00ccff' }}></div>
                                                    <div style={{ width: opt.segs[2], background: '#00ff88' }}></div>
                                                </div>
                                                {opt.label}
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>

                            {/* Visual Bar Summary of Current Split */}
                            <div style={{ marginTop: 20 }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: '#888', marginBottom: 5 }}>
                                    <span>In-Sample (Training)</span>
                                    <span>Out-of-Sample (Unseen)</span>
                                </div>
                                <div style={{ display: 'flex', height: 12, borderRadius: 6, overflow: 'hidden', background: '#333' }}>
                                    <div style={{ width: `${split}%`, background: '#00ff88', transition: 'width 0.3s' }}></div>
                                    <div style={{ width: `${100 - split}%`, background: '#00ccff', transition: 'width 0.3s' }}></div>
                                </div>
                                <div style={{ textAlign: 'right', marginTop: 5, color: '#00ccff', fontWeight: 'bold' }}>
                                    {100 - split}% OOS Reserved
                                </div>
                            </div>

                        </div>
                    )}

                    {/* Next Step Action */}
                    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', marginTop: 30 }}>
                        {!strategyConfirmed && (
                            <div style={{ color: '#ff5555', marginBottom: 5, fontStyle: 'italic', fontSize: '0.9rem' }}>
                                ⚠️ Step 2: Strategy not accepted.
                            </div>
                        )}
                        {modelStatus !== 'confirmed' && (
                            <div style={{ color: '#ff5555', marginBottom: 10, fontStyle: 'italic', fontSize: '0.9rem' }}>
                                ⚠️ Step 4: Modeling Type not confirmed.
                            </div>
                        )}

                        <button
                            className="primary-btn"
                            disabled={!strategyConfirmed || modelStatus !== 'confirmed'}
                            style={{
                                backgroundColor: (strategyConfirmed && modelStatus === 'confirmed') ? '#00cc88' : '#444',
                                color: (strategyConfirmed && modelStatus === 'confirmed') ? '#000' : '#888',
                                padding: '15px 40px',
                                fontSize: '1.2rem',
                                boxShadow: (strategyConfirmed && modelStatus === 'confirmed') ? '0 0 15px rgba(0, 255, 136, 0.4)' : 'none',
                                cursor: (strategyConfirmed && modelStatus === 'confirmed') ? 'pointer' : 'not-allowed',
                                border: 'none', borderRadius: '4px', fontWeight: 'bold'
                            }}
                            onClick={() => (strategyConfirmed && modelStatus === 'confirmed') && onNext && onNext()}
                        >
                            Continue to Strategy Builder ➡
                        </button>
                    </div>
                </div>
            )}
        </div>
    );
};

const inputStyle = { padding: 8, background: '#333', border: '1px solid #444', color: 'white', borderRadius: 4 };

export default ConfigView;
