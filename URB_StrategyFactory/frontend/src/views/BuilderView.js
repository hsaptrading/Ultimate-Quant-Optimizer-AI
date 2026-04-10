import React, { useState, useEffect } from 'react';
import axios from 'axios';

const BuilderView = () => {
    const [running, setRunning] = useState(false);
    const [progress, setProgress] = useState(0);
    const [stats, setStats] = useState({ found_count: 0, best_profit: 0, recent_logs: [] });
    const [strategies, setStrategies] = useState([]);

    // Config Form Inputs
    const maxCores = navigator.hardwareConcurrency || 8;
    const defaultCores = Math.max(1, Math.floor(maxCores * 0.8));

    const [config, setConfig] = useState({
        symbol: 'Auto',
        cores: defaultCores,
        population: 100,
        generations: 30,
        timeframe: 'M15',
        optimize_timeframes: ['M15', 'H1'],
        direction: 'Both (Symmetric)',
        optimize_directions: ['Both (Symmetric)', 'Long Only']
    });

    const [dataReady, setDataReady] = useState(false);
    const fileInputRef = React.useRef(null);
    const [loadedFile, setLoadedFile] = useState(null);

    // Check Data Status on Mount
    useEffect(() => {
        const checkData = async () => {
            try {
                const res = await axios.get('http://127.0.0.1:8000/api/data/status');
                setDataReady(res.data.loaded);
            } catch (e) {
                setDataReady(false);
            }
        };
        checkData();
    }, []);

    // Polling for Status
    useEffect(() => {
        const poll = setInterval(async () => {
            if (!running) return;
            try {
                const res = await axios.get('http://127.0.0.1:8000/api/builder/status');
                const s = res.data;

                // If backend says not running, but frontend thinks it is, sync up
                if (!s.running && running && s.progress === 0 && s.found_count === 0) {
                    // Likely aborted due to error or no data
                    setRunning(false);
                    if (!dataReady) alert("Generation aborted: No Data Loaded!");
                } else {
                    setRunning(s.running);
                    setProgress(s.progress);
                    setStats(s);
                    if (s.found_count > strategies.length) refreshStrategies();
                }
            } catch (e) { console.error(e); }
        }, 1000);
        return () => clearInterval(poll);
    }, [running, strategies.length, dataReady]);

    const refreshStrategies = async () => {
        const res = await axios.get('http://127.0.0.1:8000/api/builder/strategies');
        setStrategies(res.data);
    };

    const handleStart = async () => {
        if (!dataReady) {
            alert("⚠️ Please load Historical Data in 'Configuration' tab first!");
            return;
        }
        try {
            // Include defined params in the configuration payload
            await axios.post('http://127.0.0.1:8000/api/builder/start', { ...config, params: paramState });
            setRunning(true);
            setStrategies([]);
        } catch (e) { alert("Error starting: " + e.message); }
    };

    const handleStop = async () => {
        await axios.post('http://127.0.0.1:8000/api/builder/stop');
        setRunning(false);
    };

    // Load Strategies & Schema
    const [strategiesList, setStrategiesList] = useState([]);
    const [activeStrategy, setActiveStrategy] = useState('');
    const [strategySchema, setStrategySchema] = useState([]);
    const [paramState, setParamState] = useState({});
    const defaultParamsRef = React.useRef(null);
    const [optCriterion, setOptCriterion] = useState('Net Profit');

    // 1. Fetch available strategies
    useEffect(() => {
        const fetchStrats = async () => {
            try {
                const res = await axios.get('http://127.0.0.1:8000/api/strategies/list');
                setStrategiesList(res.data);
                if (res.data.length > 0) {
                    // Default to Custom Strategy if one is loaded, otherwise the first default
                    const customStrat = res.data.find(s => s.description.includes("Custom"));
                    if (customStrat) {
                        setActiveStrategy(customStrat.slug);
                    } else {
                        setActiveStrategy(res.data[0].slug);
                    }
                }
            } catch (e) {
                console.error("Failed to fetch strategies", e);
            }
        };
        fetchStrats();
    }, []);

    // 2. Load Schema when Active Strategy changes
    useEffect(() => {
        if (!activeStrategy) return;

        const loadSchema = async () => {
            try {
                // Determine active strategy on backend
                await axios.post('http://127.0.0.1:8000/api/strategies/set_active', { slug: activeStrategy });

                // Fetch Schema for this strategy
                // NOTE: Backend needs to return correct schema based on active state
                const res = await axios.get(`http://127.0.0.1:8000/api/config/schema?strategy=${activeStrategy}`);

                // If schema is empty (Python strategy without explicit schema), 
                // we might need to handle it or show "Import .set"
                setStrategySchema(res.data);

                // Initialize Param State
                const initial = {};
                // Handle empty or valid schema
                if (res.data && Array.isArray(res.data)) {
                    res.data.forEach(cat => {
                        cat.params.forEach(p => {
                            initial[p.name] = {
                                opt: false,
                                value: p.default,
                                start: p.default,
                                step: p.type === 'int' ? 1 : 0.5,
                                stop: p.type === 'int' ? p.default + 5 : p.default + 5.0,
                                steps: 0,
                                type: p.type, // Store type for helper
                                options: p.options // Store options for helper
                            };
                        });
                    });
                }
                setParamState(initial);
                defaultParamsRef.current = JSON.parse(JSON.stringify(initial));

                // Clear loaded file on strategy switch
                setLoadedFile(null);

            } catch (e) {
                console.error("Failed to load schema", e);
            }
        };
        loadSchema();
    }, [activeStrategy]);

    // Helper to update param state (Refactored to handle Enums)
    // Helper to update param state (Refactored to handle Enums/Bools correctly)
    const updateParam = (p, field, val) => {
        setParamState(prev => {
            const current = prev[p.name];
            // Merge new value first
            let updated = { ...current, [field]: val };

            const isEnum = p.type === 'enum' && p.options?.length > 0;
            const isBool = p.type === 'bool' || p.original_type === 'bool';

            // 1. Enforce Step=1 for Enums/Bools if Optimizing
            if (updated.opt && (isEnum || isBool)) {
                updated.step = 1;
            }

            // 2. Recalculate Steps
            if (updated.opt) {
                if (isEnum) {
                    const startIdx = p.options.findIndex(o => String(o.value) === String(updated.start));
                    const stopIdx = p.options.findIndex(o => String(o.value) === String(updated.stop));
                    // Default to 0 if not found to avoid NaN
                    const s = startIdx === -1 ? 0 : startIdx;
                    const e = stopIdx === -1 ? 0 : stopIdx;

                    // Count discrete items from start to stop
                    const diff = Math.abs(e - s);
                    updated.steps = Math.floor(diff / Math.max(1, updated.step)) + 1;
                }
                else if (isBool) {
                    // Boolean logic (0 or 1)
                    const s = String(updated.start) === 'true' ? 1 : 0;
                    const e = String(updated.stop) === 'true' ? 1 : 0;
                    const diff = Math.abs(e - s);
                    updated.steps = diff + 1; // Step is always 1
                }
                else {
                    // Numeric Logic
                    const step = parseFloat(updated.step) || 1; // Avoid NaN/Zero
                    const diff = Math.abs(updated.stop - updated.start);
                    // Add epsilon (1e-9) to handle floating point errors
                    updated.steps = Math.floor((diff / step) + 1e-9) + 1;
                }
            } else {
                updated.steps = 0;
            }

            return { ...prev, [p.name]: updated };
        });
    };

    const processSetFile = (file) => {
        if (!file) return;

        const reader = new FileReader();
        reader.onload = async (event) => {
            try {
                const content = event.target.result;
                const res = await axios.post('http://127.0.0.1:8000/api/strategy/parse-set', { content });
                const parsed = res.data;

                // Calculate next state synchronously to catch errors
                let next;
                let changed = false;

                setParamState(prev => {
                    next = JSON.parse(JSON.stringify(prev));
                    const allParams = strategySchema.flatMap(c => c.params);

                    Object.keys(parsed).forEach(key => {
                        // Case-insensitive search to be robust against .set variants
                        const p = allParams.find(x => x.name.toLowerCase() === key.toLowerCase());

                        // We must use p.name (the canonical name in the schema) to index 'next'
                        if (p && next[p.name]) {
                            changed = true;
                            const canonicalKey = p.name;

                            // Merge Updates using the canonical key
                            let newData = { ...parsed[key] };

                            // Clean strings
                            if (typeof newData.value === 'string') {
                                newData.value = newData.value.replace(/["']/g, '').trim();
                            }

                            // --- Enum Mapping: Index -> Value ---
                            if (p.type === 'enum' && p.options?.length > 0) {
                                const mapEnum = (val) => {
                                    if (!isNaN(val) && val !== '') {
                                        const idx = parseInt(val, 10);
                                        if (p.options[idx]) return p.options[idx].value;
                                    }
                                    return val;
                                };
                                if (newData.value !== undefined) newData.value = mapEnum(newData.value);
                                if (newData.start !== undefined) newData.start = mapEnum(newData.start);
                                if (newData.stop !== undefined) newData.stop = mapEnum(newData.stop);
                            }

                            // --- Bool Mapping: 0/1 -> false/true ---
                            if (p.type === 'bool' || p.original_type === 'bool') {
                                const mapBool = (val) => {
                                    const s = String(val).toLowerCase();
                                    if (s === '1' || s === 'true') return true;
                                    if (s === '0' || s === 'false') return false;
                                    return val;
                                };
                                if (newData.value !== undefined) newData.value = mapBool(newData.value);
                                if (newData.start !== undefined) newData.start = mapBool(newData.start);
                                if (newData.stop !== undefined) newData.stop = mapBool(newData.stop);
                            }

                            Object.assign(next[canonicalKey], newData);
                            const current = next[canonicalKey];

                            // Re-Calculate Steps
                            if (current.opt) {
                                const isEnum = p.type === 'enum' && p.options?.length > 0;
                                const isBool = p.type === 'bool' || p.original_type === 'bool';

                                if (isEnum || isBool) current.step = 1;

                                if (isEnum) {
                                    const sIdx = Math.max(0, p.options.findIndex(o => String(o.value) === String(current.start)));
                                    const eIdx = Math.max(0, p.options.findIndex(o => String(o.value) === String(current.stop)));
                                    current.steps = Math.floor(Math.abs(eIdx - sIdx) / Math.max(1, current.step)) + 1;
                                } else if (isBool) {
                                    const s = String(current.start) === 'true' ? 1 : 0;
                                    const e = String(current.stop) === 'true' ? 1 : 0;
                                    current.steps = Math.floor(Math.abs(e - s)) + 1;
                                } else {
                                    const step = parseFloat(current.step) || 1;
                                    const diff = Math.abs(current.stop - current.start);
                                    current.steps = Math.floor((diff / step) + 1e-9) + 1;
                                }
                            } else {
                                current.steps = 0;
                            }
                        }
                    });

                    if (changed) {
                        setLoadedFile(file.name);
                    } else {
                        // Helpful debugging tip if no parameters match
                        alert(`No parameters matched from the .SET file!\nParsed keys: ${Object.keys(parsed).join(', ')}\n\nSchema keys: ${allParams.map(p => p.name).slice(0, 10).join(', ')}...`);
                    }

                    return next;
                });
            } catch (err) {
                alert("Error loading .SET file: " + err.message);
            }
        };
        reader.readAsText(file);
    };

    const calculateTotalCombinations = () => {
        let total = 1;
        let hasOpt = false;
        Object.values(paramState).forEach(p => {
            if (p.opt && p.steps > 0) {
                total *= p.steps;
                hasOpt = true;
            }
        });
        return hasOpt ? total : 0;
    };

    const formatSteps = (n) => {
        if (n === 0) return "-";
        if (n >= 1e9) return n.toExponential(4);
        return n.toLocaleString();
    };

    const handleSetDrop = (e) => {
        e.preventDefault(); e.stopPropagation();
        processSetFile(e.dataTransfer.files[0]);
    };

    const handleFileSelect = (e) => {
        if (e.target.files && e.target.files[0]) {
            processSetFile(e.target.files[0]);
            e.target.value = null;
        }
    };

    const inputStyle = { padding: '8px', borderRadius: '4px', border: '1px solid #444', background: '#222', color: '#fff', fontSize: '0.9rem' };

    const platform = localStorage.getItem('selectedPlatform') || 'mt5';

    let paramsContent = null;
    if (platform === 'pine') {
        paramsContent = (
            <div style={{ background: '#111', padding: '20px', borderRadius: '8px', border: '1px solid #222' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '20px', borderBottom: '1px solid #333', paddingBottom: '10px' }}>
                    <div style={{ fontSize: '0.85rem', color: '#888', letterSpacing: '1px' }}>PARAMETERS TO OPTIMIZE</div>
                    <div style={{ fontSize: '0.85rem', color: '#aaa' }}>{Object.values(paramState).filter(p => p.opt).length} selected · {formatSteps(calculateTotalCombinations())} combinations</div>
                </div>

                {strategySchema.map(cat => (
                    <div key={cat.category} style={{ marginBottom: '15px' }}>
                        {cat.category.toLowerCase() !== 'default' && (
                            <div style={{ fontSize: '0.85rem', color: '#ffaa00', marginBottom: '10px', textTransform: 'uppercase' }}>{cat.category}</div>
                        )}
                        {cat.params.map(p => {
                            const st = paramState[p.name] || {};
                            const isEnum = p.type === 'enum' && p.options?.length > 0;
                            const isBool = p.type === 'bool' || p.original_type === 'bool';

                            return (
                                <div key={p.name} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '10px 0', borderBottom: '1px solid #1a1a1a', background: st.opt ? 'rgba(0,255,136,0.02)' : 'transparent' }}>
                                    <div style={{ display: 'flex', alignItems: 'center', gap: '15px', flex: 1 }}>
                                        <input
                                            type="checkbox"
                                            checked={st.opt || false}
                                            onChange={(e) => updateParam(p, 'opt', e.target.checked)}
                                            style={{ width: '18px', height: '18px', cursor: 'pointer', accentColor: '#ffaa00' }}
                                        />
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                            <span style={{ fontSize: '0.95rem', color: st.opt ? '#fff' : '#aaa' }}>{p.label || p.name}</span>
                                            <span style={{ fontSize: '0.8rem', color: '#555' }}>
                                                {isEnum ? st.value : (isBool ? String(st.value) : st.value)}
                                            </span>
                                        </div>
                                    </div>

                                    <div style={{ display: 'flex', gap: '20px', alignItems: 'center' }}>
                                        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                                            {isEnum || isBool ? (
                                                <div style={{ width: '70px' }}></div>
                                            ) : (
                                                <>
                                                    <input
                                                        type="number" disabled={!st.opt} value={st.start}
                                                        onChange={(e) => updateParam(p, 'start', parseFloat(e.target.value))}
                                                        style={{ ...inputStyle, width: '70px', textAlign: 'center', opacity: st.opt ? 1 : 0.3, background: '#1a1a1a', border: '1px solid #333' }}
                                                    />
                                                    <span style={{ fontSize: '0.65rem', color: '#666', marginTop: '4px' }}>Min</span>
                                                </>
                                            )}
                                        </div>
                                        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                                            {isEnum || isBool ? (
                                                <>
                                                    <span style={{ fontSize: '0.8rem', color: '#555', marginTop: '10px' }}>{isBool ? "Boolean" : "Enum"}</span>
                                                </>
                                            ) : (
                                                <>
                                                    <input
                                                        type="number" disabled={!st.opt} value={st.stop}
                                                        onChange={(e) => updateParam(p, 'stop', parseFloat(e.target.value))}
                                                        style={{ ...inputStyle, width: '70px', textAlign: 'center', opacity: st.opt ? 1 : 0.3, background: '#1a1a1a', border: '1px solid #333' }}
                                                    />
                                                    <span style={{ fontSize: '0.65rem', color: '#666', marginTop: '4px' }}>Max</span>
                                                </>
                                            )}
                                        </div>
                                        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                                            {isEnum || isBool ? (
                                                <div style={{ width: '70px' }}></div>
                                            ) : (
                                                <>
                                                    <input
                                                        type="number" disabled={!st.opt || isEnum || isBool} value={(isEnum || isBool) ? 1 : st.step}
                                                        onChange={(e) => updateParam(p, 'step', parseFloat(e.target.value))}
                                                        style={{ ...inputStyle, width: '70px', textAlign: 'center', opacity: (st.opt && !isEnum && !isBool) ? 1 : 0.3, background: '#1a1a1a', border: '1px solid #333' }}
                                                    />
                                                    <span style={{ fontSize: '0.65rem', color: '#666', marginTop: '4px' }}>Step</span>
                                                </>
                                            )}
                                        </div>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                ))}
            </div>
        );
    } else {
        paramsContent = strategySchema.map(cat => (
            <div key={cat.category} style={{ marginBottom: '20px' }}>
                <div style={{ padding: '8px 10px', background: '#333', color: '#fff', fontWeight: 'bold', borderRadius: '4px 4px 0 0', fontSize: '0.85rem' }}>
                    🔹 {cat.category.toUpperCase()}
                </div>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.9rem' }}>
                    <thead>
                        <tr style={{ color: '#666', textAlign: 'left', borderBottom: '1px solid #444' }}>
                            <th style={{ padding: '10px', width: '40px' }}>Opt</th>
                            <th style={{ padding: '10px' }}>Parameter</th>
                            <th style={{ padding: '10px' }}>Value</th>
                            <th style={{ padding: '10px' }}>Start</th>
                            <th style={{ padding: '10px' }}>Step</th>
                            <th style={{ padding: '10px' }}>Stop</th>
                            <th style={{ padding: '10px', width: '60px' }}>Steps</th>
                        </tr>
                    </thead>
                    <tbody>
                        {cat.params.map(p => {
                            const st = paramState[p.name] || {};
                            const isEnum = p.type === 'enum' && p.options?.length > 0;
                            const isBool = p.type === 'bool' || p.original_type === 'bool';

                            return (
                                <tr key={p.name} style={{ borderBottom: '1px solid #2a2a2a', background: st.opt ? 'rgba(0,255,136,0.02)' : 'transparent' }}>
                                    <td style={{ padding: '10px', textAlign: 'center' }}>
                                        <input
                                            type="checkbox"
                                            checked={st.opt || false}
                                            onChange={(e) => updateParam(p, 'opt', e.target.checked)}
                                        />
                                    </td>
                                    <td style={{ padding: '10px', fontWeight: 'bold', color: '#ddd' }}>
                                        {p.label || p.name}
                                        {p.label && p.label !== p.name && <div style={{ fontSize: '0.7rem', color: '#666' }}>{p.name}</div>}
                                    </td>
                                    <td style={{ padding: '10px' }}>
                                        {!st.opt ? (
                                            isEnum ? (
                                                <select
                                                    value={st.value}
                                                    onChange={(e) => updateParam(p, 'value', e.target.value)}
                                                    style={{ ...inputStyle, width: '100%', cursor: 'pointer' }}
                                                >
                                                    {p.options.map((opt, idx) => (
                                                        <option key={idx} value={opt.value}>
                                                            {opt.label || opt.value}
                                                        </option>
                                                    ))}
                                                </select>
                                            ) : isBool ? (
                                                <select
                                                    value={st.value}
                                                    onChange={(e) => updateParam(p, 'value', e.target.value === 'true')}
                                                    style={{ ...inputStyle, width: '100%', cursor: 'pointer' }}
                                                >
                                                    <option value="false">False</option>
                                                    <option value="true">True</option>
                                                </select>
                                            ) : (
                                                <input
                                                    type={p.type === 'int' ? 'number' : 'text'}
                                                    value={st.value}
                                                    onChange={(e) => updateParam(p, 'value', p.type === 'int' ? parseInt(e.target.value) : parseFloat(e.target.value))}
                                                    style={{ ...inputStyle, width: '100%' }}
                                                />
                                            )
                                        ) : <span style={{ color: '#666' }}>-</span>}
                                    </td>
                                    <td style={{ padding: '10px' }}>
                                        {isEnum ? (
                                            <select
                                                disabled={!st.opt}
                                                value={st.start}
                                                onChange={(e) => updateParam(p, 'start', e.target.value)}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            >
                                                {p.options.map((opt, idx) => (
                                                    <option key={idx} value={opt.value}>{opt.label || opt.value}</option>
                                                ))}
                                            </select>
                                        ) : isBool ? (
                                            <select
                                                disabled={!st.opt}
                                                value={st.start}
                                                onChange={(e) => updateParam(p, 'start', e.target.value === 'true')}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            >
                                                <option value="false">False</option>
                                                <option value="true">True</option>
                                            </select>
                                        ) : (
                                            <input
                                                type="number" disabled={!st.opt}
                                                value={st.start}
                                                onChange={(e) => updateParam(p, 'start', parseFloat(e.target.value))}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            />
                                        )}
                                    </td>
                                    <td style={{ padding: '10px' }}>
                                        <input
                                            type="number"
                                            disabled={!st.opt || isEnum || isBool}
                                            value={(isEnum || isBool) ? 1 : st.step}
                                            onChange={(e) => updateParam(p, 'step', parseFloat(e.target.value))}
                                            style={{ ...inputStyle, width: '100%', opacity: (st.opt && !isEnum && !isBool) ? 1 : 0.3, background: (isEnum || isBool) ? '#222' : '#111' }}
                                        />
                                    </td>
                                    <td style={{ padding: '10px' }}>
                                        {isEnum ? (
                                            <select
                                                disabled={!st.opt}
                                                value={st.stop}
                                                onChange={(e) => updateParam(p, 'stop', e.target.value)}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            >
                                                {p.options.map((opt, idx) => (
                                                    <option key={idx} value={opt.value}>{opt.label || opt.value}</option>
                                                ))}
                                            </select>
                                        ) : isBool ? (
                                            <select
                                                disabled={!st.opt}
                                                value={st.stop}
                                                onChange={(e) => updateParam(p, 'stop', e.target.value === 'true')}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            >
                                                <option value="false">False</option>
                                                <option value="true">True</option>
                                            </select>
                                        ) : (
                                            <input
                                                type="number" disabled={!st.opt}
                                                value={st.stop}
                                                onChange={(e) => updateParam(p, 'stop', parseFloat(e.target.value))}
                                                style={{ ...inputStyle, width: '100%', opacity: st.opt ? 1 : 0.3 }}
                                            />
                                        )}
                                    </td>
                                    <td style={{ padding: '10px', color: '#888', textAlign: 'right' }}>
                                        {st.opt && st.steps > 0 ? st.steps : ""}
                                    </td>
                                </tr>
                            );
                        })}
                    </tbody>
                </table>
            </div>
        ));
    }

    return (
        <div style={{ maxWidth: '1400px', margin: '0 auto', paddingBottom: '100px' }}>
            <div className="header">
                {platform === 'pine' ? (
                    <>
                        <h1>Strategy Optimizer (Pine)</h1>
                        <p>Optimize TradingView PineScript parameters directly via vectorized backend</p>
                    </>
                ) : (
                    <>
                        <h1>Strategy Builder</h1>
                        <p>Define your MT5 optimization landscape and evolve alpha</p>
                    </>
                )}
            </div>

            {/* 1. Engine Setup & Genetic Hyperparameters */}
            <div className="card" style={{ display: 'grid', gridTemplateColumns: 'minmax(250px, 1fr) 2fr', gap: '20px' }}>
                <div style={{ borderRight: '1px solid #333', paddingRight: '20px' }}>
                    <h3>🧬 Genetic Setup</h3>

                    <label style={{ display: 'block', marginBottom: '5px', color: '#aaa', fontSize: '0.85rem' }}>Population Size</label>
                    <input type="number"
                        value={config.population}
                        onChange={(e) => setConfig({ ...config, population: parseInt(e.target.value) || 100 })}
                        style={{ ...inputStyle, width: '100%', marginBottom: '15px' }}
                    />

                    <label style={{ display: 'block', marginBottom: '5px', color: '#aaa', fontSize: '0.85rem' }}>Max Generations</label>
                    <input type="number"
                        value={config.generations}
                        onChange={(e) => setConfig({ ...config, generations: parseInt(e.target.value) || 30 })}
                        style={{ ...inputStyle, width: '100%', marginBottom: '15px' }}
                    />

                    <button
                        className="secondary-btn"
                        onClick={() => {
                            const totalOps = calculateTotalCombinations();
                            if (totalOps === 0) return alert("Select optimization parameters first!");

                            // Simple Auto-Scale heuristic
                            let sugCore = Math.max(1, Math.floor(navigator.hardwareConcurrency * 0.8));
                            let sugPop = Math.min(1000, Math.max(10, Math.floor(Math.pow(totalOps, 0.3))));
                            let sugGen = Math.min(100, Math.max(10, Math.floor(Math.pow(totalOps, 0.25))));

                            setConfig({ ...config, cores: sugCore, population: sugPop, generations: sugGen });
                        }}
                        style={{ width: '100%', fontSize: '0.8rem', padding: '8px', border: '1px solid #00ccff', color: '#00ccff', backgroundColor: 'transparent', cursor: 'pointer', borderRadius: '4px' }}
                    >
                        ✨ Auto-Suggest Config
                    </button>
                    <div style={{ fontSize: '0.75rem', color: '#666', marginTop: '10px' }}>*Auto-suggest estimates optimal size based on your total variable combinations above.</div>
                </div>

                <div>
                    <h3>⚙️ Processing Constraints</h3>
                    <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap' }}>
                        {/* CORES */}
                        <div style={{ flex: '1 1 200px' }}>
                            <label style={{ display: 'flex', justifyContent: 'space-between', color: '#aaa', fontSize: '0.85rem', marginBottom: '5px' }}>
                                <span>CPU Cores (Clones)</span>
                                <span style={{ color: config.cores >= maxCores ? '#ff4444' : '#00ff88' }}>
                                    {config.cores} / {maxCores} ({((config.cores / maxCores) * 100).toFixed(0)}%)
                                </span>
                            </label>
                            <input
                                type="range"
                                min="1" max={maxCores}
                                value={config.cores}
                                onChange={(e) => setConfig({ ...config, cores: parseInt(e.target.value) })}
                                style={{ width: '100%', accentColor: config.cores >= maxCores ? '#ff4444' : '#00ff88' }}
                            />
                            <div style={{ fontSize: '0.75rem', color: '#888', marginTop: '5px' }}>
                                Using {config.cores} core(s). Leaving {Math.max(0, maxCores - config.cores)} free for Windows OS & Multitasking.
                            </div>
                        </div>

                        {/* TIMEFRAME */}
                        <div style={{ flex: '1 1 200px' }}>
                            <label style={{ display: 'block', color: '#aaa', fontSize: '0.85rem', marginBottom: '5px' }}>Execution Timeframe</label>
                            <select
                                value={config.timeframe}
                                onChange={(e) => setConfig({ ...config, timeframe: e.target.value })}
                                style={{ ...inputStyle, width: '100%' }}
                            >
                                <option value="M1">1 Minute (M1)</option>
                                <option value="M5">5 Minutes (M5)</option>
                                <option value="M15">15 Minutes (M15)</option>
                                <option value="M30">30 Minutes (M30)</option>
                                <option value="H1">1 Hour (H1)</option>
                                <option value="H4">4 Hours (H4)</option>
                                <option value="D1">1 Day (D1)</option>
                                <option value="Optimize Multiple">Multi-Timeframe Search</option>
                            </select>

                            {config.timeframe === 'Optimize Multiple' && (
                                <div style={{ marginTop: '10px', background: '#111', padding: '10px', borderRadius: '4px', border: '1px solid #333' }}>
                                    <div style={{ fontSize: '0.75rem', color: '#888', marginBottom: '5px' }}>Select Timeframes to Search:</div>
                                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                                        {['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1'].map(tf => (
                                            <label key={tf} style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.8rem', color: '#fff', cursor: 'pointer' }}>
                                                <input
                                                    type="checkbox"
                                                    checked={config.optimize_timeframes.includes(tf)}
                                                    onChange={(e) => {
                                                        const newTfs = e.target.checked
                                                            ? [...config.optimize_timeframes, tf]
                                                            : config.optimize_timeframes.filter(t => t !== tf);
                                                        setConfig({ ...config, optimize_timeframes: newTfs });
                                                    }}
                                                />
                                                {tf}
                                            </label>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </div>

                        {/* TRADING DIRECTION */}
                        <div style={{ flex: '1 1 200px' }}>
                            <label style={{ display: 'block', color: '#aaa', fontSize: '0.85rem', marginBottom: '5px' }}>Trading Direction</label>
                            <select
                                value={config.direction}
                                onChange={(e) => setConfig({ ...config, direction: e.target.value })}
                                style={{ ...inputStyle, width: '100%' }}
                            >
                                <option value="Both (Symmetric)">Both (Symmetric Params)</option>
                                <option value="Both (Asymmetric)">Both (Asymmetric Params)</option>
                                <option value="Long Only">Long Only</option>
                                <option value="Short Only">Short Only</option>
                                <option value="Optimize Multiple">Multi-Direction Search</option>
                            </select>

                            {config.direction === 'Optimize Multiple' && (
                                <div style={{ marginTop: '10px', background: '#111', padding: '10px', borderRadius: '4px', border: '1px solid #333' }}>
                                    <div style={{ fontSize: '0.75rem', color: '#888', marginBottom: '5px' }}>Select Directions to Search:</div>
                                    <div style={{ display: 'flex', flexDirection: 'column', gap: '5px' }}>
                                        {['Both (Symmetric)', 'Long Only', 'Short Only'].map(dir => (
                                            <label key={dir} style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '0.8rem', color: '#fff', cursor: 'pointer' }}>
                                                <input
                                                    type="checkbox"
                                                    checked={config.optimize_directions.includes(dir)}
                                                    onChange={(e) => {
                                                        const newDirs = e.target.checked
                                                            ? [...config.optimize_directions, dir]
                                                            : config.optimize_directions.filter(d => d !== dir);
                                                        setConfig({ ...config, optimize_directions: newDirs });
                                                    }}
                                                />
                                                {dir}
                                            </label>
                                        ))}
                                    </div>
                                </div>
                            )}

                            <div style={{ fontSize: '0.75rem', color: '#666', marginTop: '5px' }}>
                                *Note: Direction overrides require the EA logic to support external restrictions.
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* 2. Optimization Objective */}
            <div className="card">
                <h3>🎯 Optimization Objective</h3>
                <div style={{ display: 'flex', gap: '15px', flexWrap: 'wrap' }}>
                    {['Net Profit', 'Profit Factor', 'Expected Payoff', 'Drawdown', 'Recovery Factor', 'Sharpe Ratio', 'Custom', 'Complex Criterion'].map(crit => (
                        <button
                            key={crit}
                            onClick={() => setOptCriterion(crit)}
                            style={{
                                flex: '1 1 150px',
                                padding: '15px',
                                background: optCriterion === crit ? 'rgba(0, 255, 136, 0.15)' : '#222',
                                border: optCriterion === crit ? '1px solid #00ff88' : '1px solid #444',
                                borderRadius: '6px',
                                color: optCriterion === crit ? '#00ff88' : '#888',
                                fontWeight: 'bold',
                                cursor: 'pointer',
                                transition: 'all 0.2s'
                            }}
                        >
                            {optCriterion === crit && "✅ "} {crit}
                        </button>
                    ))}
                </div>
            </div>

            {/* 3. Strategy Configuration */}
            <div className="card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '20px' }}>
                        <h3>⚙️ Strategy Configuration</h3>
                        {calculateTotalCombinations() > 0 && (
                            <div style={{ background: '#111', padding: '5px 10px', borderRadius: '4px', fontSize: '0.85rem', color: '#888', border: '1px solid #333' }}>
                                Total Combinations: <span style={{ color: '#00ff88', fontWeight: 'bold' }}>{formatSteps(calculateTotalCombinations())}</span>
                            </div>
                        )}
                    </div>
                    <input
                        type="file"
                        ref={fileInputRef}
                        style={{ display: 'none' }}
                        accept=".set,.txt"
                        onChange={handleFileSelect}
                    />
                    {loadedFile ? (
                        <div
                            title="Click to clear"
                            onClick={() => {
                                if (window.confirm("Undo/Clear loaded configuration?")) {
                                    setLoadedFile(null);
                                    if (defaultParamsRef.current) {
                                        setParamState(JSON.parse(JSON.stringify(defaultParamsRef.current)));
                                    }
                                }
                            }}
                            style={{ padding: '10px 20px', background: 'rgba(0, 255, 136, 0.15)', border: '1px solid #00ff88', borderRadius: '4px', color: '#00ff88', cursor: 'pointer', fontSize: '0.9rem', display: 'flex', alignItems: 'center', gap: '8px' }}
                        >
                            ✅ Loaded: {loadedFile} <span style={{ fontSize: '0.8em', opacity: 0.7 }}> (Click to Reset)</span>
                        </div>
                    ) : (
                        <div
                            onDragOver={(e) => { e.preventDefault(); e.stopPropagation(); }}
                            onDragEnter={(e) => { e.preventDefault(); e.stopPropagation(); }}
                            onDrop={handleSetDrop}
                            onClick={() => fileInputRef.current?.click()}
                            title="Drop .set file or Click to Browse"
                            style={{ padding: '10px 20px', border: '2px dashed #666', borderRadius: '4px', color: '#888', cursor: 'pointer', fontSize: '0.9rem' }}
                        >
                            ☁️ Drag and drop .SET file here (or Click)
                        </div>
                    )}
                </div>

                {/* Loaded Strategy Indicator */}
                <div style={{ marginBottom: '15px', padding: '15px', background: 'rgba(0, 204, 255, 0.05)', borderRadius: '6px', border: '1px solid rgba(0, 204, 255, 0.2)', display: 'flex', alignItems: 'center', gap: '15px' }}>
                    <div style={{ fontSize: '2rem' }}>🤖</div>
                    <div>
                        <div style={{ fontSize: '0.85rem', color: '#00ccff', textTransform: 'uppercase', letterSpacing: '1px', marginBottom: '4px' }}>Target Strategy</div>
                        <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: '#fff' }}>
                            {strategiesList.find(s => s.slug === activeStrategy)?.name || "Loading..."}
                        </div>
                        <div style={{ fontSize: '0.8rem', color: '#888', marginTop: '2px' }}>
                            {strategiesList.find(s => s.slug === activeStrategy)?.description || "Ready for Optimization"}
                        </div>
                    </div>
                </div>
            </div>

            <div style={{ maxHeight: '600px', overflowY: 'auto' }}>
                {paramsContent}
            </div>


            {/* 3. Control Panel (Running State) */}
            <div className="card" style={{ position: 'sticky', bottom: '20px', zIndex: 100, border: '1px solid #00ff88', boxShadow: '0 0 20px rgba(0,255,136,0.1)' }}>
                <div style={{ display: 'flex', gap: '20px', alignItems: 'center' }}>

                    <div style={{ flex: 1 }}>
                        <h4 style={{ margin: 0, color: '#00ff88' }}>{running ? "🚀 Generation in Progress..." : "Ready to Start"}</h4>
                        <div style={{ fontSize: '0.8rem', color: '#888' }}>
                            {running ? `Generation ${stats.recent_logs?.length || 0} / ${config.generations}` : "Configure parameters above and launch optimization."}
                        </div>
                    </div>

                    <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
                        {!running ? (
                            <button
                                className="primary-btn"
                                onClick={handleStart}
                                style={{ marginLeft: '10px', background: '#00cc88', color: '#000', fontWeight: 'bold' }}
                            >
                                ▶ Start Optimization
                            </button>
                        ) : (
                            <button className="primary-btn" onClick={handleStop} style={{ marginLeft: '10px', background: '#ff4444', color: 'white' }}>
                                🛑 Stop
                            </button>
                        )}
                    </div>
                </div>

                {/* Progress Bar if running */}
                {running && (
                    <div style={{ width: '100%', height: '4px', background: '#333', marginTop: '15px', borderRadius: '2px', overflow: 'hidden' }}>
                        <div style={{ width: `${progress}%`, height: '100%', background: '#00ff88', transition: 'width 0.5s' }}></div>
                    </div>
                )}
            </div>

            {/* Results Preview (Simplified for now - user likely wants specific Results tab later) */}
            <div className="card">
                <h3>🏆 Top Strategies Preview</h3>
                {strategies.length === 0 ? (
                    <p style={{ color: '#666', fontStyle: 'italic' }}>No results yet.</p>
                ) : (
                    <div style={{ display: 'flex', gap: '10px', overflowX: 'auto', paddingBottom: '10px' }}>
                        {strategies.slice(0, 5).map((s, i) => (
                            <div key={i} style={{ minWidth: '200px', background: '#222', padding: '15px', borderRadius: '6px', border: '1px solid #444' }}>
                                <div style={{ color: '#00ff88', fontWeight: 'bold', fontSize: '1.1rem' }}>${s.net_profit.toFixed(2)}</div>
                                <div style={{ fontSize: '0.8rem', color: '#aaa' }}>PF: {s.profit_factor || 0} | WR: {s.win_rate}%</div>
                                <div style={{ fontSize: '0.8rem', color: '#666', marginTop: '5px' }}>ID: {s.id}</div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div >
    );
};

// Simple Styles
const inputStyle = {
    padding: '10px',
    background: '#1a1a1a',
    border: '1px solid #333',
    color: 'white',
    borderRadius: 4,
    width: 100
};

const StatBox = ({ label, value, color = 'white' }) => (
    <div style={{ background: '#1a1a1a', padding: 10, borderRadius: 6, textAlign: 'center' }}>
        <div style={{ color: '#666', fontSize: '0.8rem' }}>{label}</div>
        <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: color }}>{value}</div>
    </div>
);

export default BuilderView;
