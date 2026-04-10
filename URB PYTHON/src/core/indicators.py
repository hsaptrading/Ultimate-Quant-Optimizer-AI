
import numpy as np
from numba import jit

@jit(nopython=True)
def rma_numba(src, length):
    """Running Moving Average (Wilder's SMMA) used in RSI and ADX."""
    alpha = 1.0 / length
    out = np.empty_like(src)
    out[:] = np.nan
    
    # Initialize with SMA
    s = 0.0
    valid_count = 0
    start_idx = -1
    
    for i in range(len(src)):
        val = src[i]
        if not np.isnan(val):
            s += val
            valid_count += 1
            if valid_count == length:
                out[i] = s / length
                start_idx = i
                break
    
    if start_idx != -1:
        prev = out[start_idx]
        for i in range(start_idx + 1, len(src)):
            val = src[i]
            if np.isnan(val):
                out[i] = prev
            else:
                out[i] = alpha * val + (1.0 - alpha) * prev
                prev = out[i]
                
    return out

@jit(nopython=True)
def calculate_rsi(prices, period=14):
    """Relative Strength Index matching MT5."""
    delta = np.zeros_like(prices)
    delta[1:] = prices[1:] - prices[:-1]
    
    gain = np.where(delta > 0, delta, 0.0)
    loss = np.where(delta < 0, -delta, 0.0)
    
    avg_gain = rma_numba(gain, period)
    avg_loss = rma_numba(loss, period)
    
    rs = avg_gain / avg_loss
    rsi = 100.0 - (100.0 / (1.0 + rs))
    
    # Fill NaNs
    return np.where(np.isnan(rsi), 50.0, rsi)

@jit(nopython=True)
def calculate_atr(highs, lows, closes, period=14):
    """Average True Range."""
    tr = np.zeros_like(closes)
    
    # TR[0] is high-low
    tr[0] = highs[0] - lows[0]
    
    for i in range(1, len(closes)):
        h = highs[i]
        l = lows[i]
        pc = closes[i-1]
        
        hl = h - l
        hc = abs(h - pc)
        lc = abs(l - pc)
        
        if hl > hc and hl > lc:
            tr[i] = hl
        elif hc > lc:
            tr[i] = hc
        else:
            tr[i] = lc
            
    return rma_numba(tr, period)

@jit(nopython=True)
def calculate_adx(highs, lows, closes, period=14):
    """Average Directional Index."""
    n = len(closes)
    
    plus_dm = np.zeros(n)
    minus_dm = np.zeros(n)
    tr = np.zeros(n)
    
    tr[0] = highs[0] - lows[0]
    
    for i in range(1, n):
        h = highs[i]
        l = lows[i]
        ph = highs[i-1]
        pl = lows[i-1]
        pc = closes[i-1]
        
        # True Range
        hl = h - l
        hc = abs(h - pc)
        lc = abs(l - pc)
        val_tr = max(hl, max(hc, lc))
        tr[i] = val_tr
        
        # DM
        up = h - ph
        down = pl - l
        
        if up > down and up > 0:
            plus_dm[i] = up
        else:
            plus_dm[i] = 0.0
            
        if down > up and down > 0:
            minus_dm[i] = down
        else:
            minus_dm[i] = 0.0
            
    tr_smooth = rma_numba(tr, period)
    plus_dm_smooth = rma_numba(plus_dm, period)
    minus_dm_smooth = rma_numba(minus_dm, period)
    
    plus_di = 100 * plus_dm_smooth / tr_smooth
    minus_di = 100 * minus_dm_smooth / tr_smooth
    
    dx = 100 * np.abs(plus_di - minus_di) / (plus_di + minus_di)
    adx = rma_numba(dx, period)
    
    return np.where(np.isnan(adx), 0.0, adx)
