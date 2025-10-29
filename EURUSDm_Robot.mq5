//+------------------------------------------------------------------+
//|                                                EURUSDm_Robot.mq5 |
//|                        Production-Ready EURUSDm Trading Robot    |
//|                        Strategy: EMA Crossover + RSI + ATR      |
//|                        Copyright 2025                            |
//+------------------------------------------------------------------+
#property copyright   "2025"
#property version     "1.00"
#property description "Production-ready EURUSDm robot with EMA crossover, RSI filter, ATR-based SL/TP"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//=========================== STRATEGY INPUTS =======================
input group "=== SYMBOL & TIMEFRAME ===";
input string   InpSymbol           = "EURUSDm";     // Trading symbol (auto-detect if empty)
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M1;     // Primary timeframe (M1 for higher accuracy)

input group "=== EMA CROSSOVER STRATEGY ===";
input int      InpEMA_Fast         = 12;            // Fast EMA period (optimized for M1)
input int      InpEMA_Slow         = 26;            // Slow EMA period (optimized for M1)
input int      InpRSI_Period       = 14;            // RSI period
input double   InpRSI_LongMin      = 50.0;          // RSI minimum for long entry (tighter for accuracy)
input double   InpRSI_ShortMax     = 50.0;           // RSI maximum for short entry (tighter for accuracy)
input int      InpSignalConfirmation = 2;           // Require N consecutive bars with signal

input group "=== ATR-BASED EXIT RULES ===";
input int      InpATR_Period       = 14;            // ATR period
input double   InpSL_Multiplier    = 1.5;           // SL = ATR * multiplier (smaller for M1)
input double   InpTP_Multiplier    = 2.5;           // TP = ATR * multiplier (fallback if dynamic TP disabled)
input bool     InpUseTrailing      = true;          // Enable trailing stop
input double   InpTrailStart       = 1.0;           // Start trailing after (ATR multiples - faster for M1)
input double   InpTrailStep        = 5.0;            // Trailing stop step (pips - tighter for M1)
input bool     InpUseBreakEven     = true;          // Move to breakeven after trigger
input double   InpBE_TriggerATR    = 1.5;           // BE trigger (ATR multiples)
input int      InpMaxTradeLifeMin  = 0;             // Max trade duration (0=unlimited)

input group "=== REVERSAL DETECTION & DYNAMIC TP ===";
input bool     InpUseDynamicTP     = true;          // Use dynamic TP based on S/R levels
input bool     InpUseReversalExit  = true;          // Enable early exit on reversal signals
input int      InpReversalSensitivity = 6;         // 1-10: Higher = reacts sooner (default 6)
input int      InpSR_Lookback      = 50;            // Candles to check for S/R levels
input int      InpWaitAfterCloseMinutes = 5;        // Wait N minutes after reversal close
input double   InpTP_BufferPips    = 2.0;           // Pips before S/R level for TP

input group "=== RISK MANAGEMENT ===";
input double   InpRiskPercent      = 0.5;          // Risk % per trade (lower for M1)
input double   InpFixedLotSize     = 0.0;           // Fixed lot size (0=use risk%)
input int      InpMaxOpenTrades    = 1;             // Maximum concurrent trades
input double   InpDailyLossLimit   = 5.0;           // Daily loss limit (%)
input double   InpMaxSpread        = 1.5;           // Maximum spread (pips - tighter for M1)
input double   InpMaxSlippage      = 2.0;           // Maximum slippage (pips - tighter for M1)

input group "=== TRADING HOURS & FILTERS ===";
input bool     InpTradeHoursEnabled = false;        // Enable hour filter
input int      InpTradeStartHour   = 8;             // Start trading hour (server time)
input int      InpTradeEndHour     = 20;            // End trading hour (server time)
input bool     InpAvoidNews        = false;         // Avoid trading ±15min around news
input bool     InpVolatilityFilter = false;         // Enable volatility filter
input double   InpATR_MinThreshold = 0.0001;        // Minimum ATR for trading
input double   InpATR_MaxThreshold = 0.0100;        // Maximum ATR for trading

input group "=== SAFETY & LOGGING ===";
input ulong    InpMagicNumber      = 20250101;      // Unique EA identifier
input bool     InpEnableTrading    = true;          // Master enable/disable
input bool     InpAllowWeekend     = false;         // Allow trading on weekends
input bool     InpLogToCSV         = true;          // Export trades to CSV
input string   InpLogDirectory     = "EURUSDm_Robot"; // Log directory name

//=========================== GLOBALS ===============================
CTrade         g_trade;
CPositionInfo  g_pos;

// Indicator handles
int            h_ema_fast = INVALID_HANDLE;
int            h_ema_slow = INVALID_HANDLE;
int            h_rsi      = INVALID_HANDLE;
int            h_atr      = INVALID_HANDLE;
int            h_macd     = INVALID_HANDLE;  // For reversal detection

// Session tracking
datetime       g_session_start = 0;
double         g_start_balance = 0.0;
double         g_daily_balance_start = 0.0;
datetime       g_last_bar_time = 0;

// Symbol detection
string         g_active_symbol = "";

// Logging
string         g_log_file = "";

// Signal confirmation tracking
int            g_long_signal_count = 0;
int            g_short_signal_count = 0;

// Standby mode (after reversal close)
datetime       g_standby_until = 0;

//=========================== UTILITIES =============================
string DetectEURUSDSymbol()
{
    string symbols[] = {"EURUSDm", "EURUSD", "EURUSD.", "EURUSD_Micro"};
    for(int i = 0; i < ArraySize(symbols); i++)
    {
        if(SymbolSelect(symbols[i], true))
        {
            Print("Detected symbol: ", symbols[i]);
            return symbols[i];
        }
    }
    return _Symbol; // Fallback to current
}

double GetPipValue()
{
    int digits = (int)SymbolInfoInteger(g_active_symbol, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    if(digits == 3 || digits == 5) return point * 10.0; // 5/3 digit pricing
    return point; // 4/2 digit pricing
}

double PipsToPoints(double pips)
{
    return pips * GetPipValue();
}

double GetCurrentSpreadPips()
{
    double ask = SymbolInfoDouble(g_active_symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(g_active_symbol, SYMBOL_BID);
    return (ask - bid) / GetPipValue();
}

bool IsTradingHours()
{
    if(!InpTradeHoursEnabled) return true;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return (dt.hour >= InpTradeStartHour && dt.hour < InpTradeEndHour);
}

bool IsValidSpread()
{
    double spread = GetCurrentSpreadPips();
    return (spread <= InpMaxSpread);
}

bool IsNewsWindow() // Simplified - can be enhanced with actual news API
{
    if(!InpAvoidNews) return false;
    // Placeholder - in production, integrate with economic calendar API
    return false;
}

//=========================== LOGGING ===============================
void InitializeLogging()
{
    if(!InpLogToCSV) return;
    g_log_file = InpLogDirectory + "/trades_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
    
    // Create header if new file
    int h = FileOpen(g_log_file, FILE_WRITE|FILE_CSV|FILE_COMMON, ';');
    if(h != INVALID_HANDLE)
    {
        FileWrite(h, "Time", "Type", "EntryPrice", "SL", "TP", "LotSize", "Reason", 
                  "Balance", "Equity", "Spread", "ATR", "RSI", "EMA_Fast", "EMA_Slow");
        FileClose(h);
    }
}

void LogTrade(string type, double entry, double sl, double tp, double lots, string reason)
{
    if(!InpLogToCSV) return;
    
    double ema_f[], ema_s[], rsi[], atr[];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    ArrayResize(ema_f, 1);
    ArrayResize(ema_s, 1);
    ArrayResize(rsi, 1);
    ArrayResize(atr, 1);
    
    CopyBuffer(h_ema_fast, 0, 0, 1, ema_f);
    CopyBuffer(h_ema_slow, 0, 0, 1, ema_s);
    CopyBuffer(h_rsi, 0, 0, 1, rsi);
    CopyBuffer(h_atr, 0, 0, 1, atr);
    
    int h = FileOpen(g_log_file, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ';');
    if(h != INVALID_HANDLE)
    {
        FileSeek(h, 0, SEEK_END);
        FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                  type, entry, sl, tp, lots, reason,
                  AccountInfoDouble(ACCOUNT_BALANCE),
                  AccountInfoDouble(ACCOUNT_EQUITY),
                  GetCurrentSpreadPips(),
                  atr[0], rsi[0], ema_f[0], ema_s[0]);
        FileClose(h);
    }
}

//=========================== INDICATORS ============================
bool CreateIndicators()
{
    h_ema_fast = iMA(g_active_symbol, InpTimeframe, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    h_ema_slow = iMA(g_active_symbol, InpTimeframe, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    h_rsi      = iRSI(g_active_symbol, InpTimeframe, InpRSI_Period, PRICE_CLOSE);
    h_atr      = iATR(g_active_symbol, InpTimeframe, InpATR_Period);
    h_macd     = iMACD(g_active_symbol, InpTimeframe, 12, 26, 9, PRICE_CLOSE);
    
    if(h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE ||
       h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE || h_macd == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators. Error: ", GetLastError());
        return false;
    }
    
    // Wait for indicators to calculate
    Sleep(1000);
    return true;
}

//=========================== SUPPORT/RESISTANCE =====================
struct SRLevel
{
    double price;
    int strength;  // Number of touches
    bool is_resistance;
};

SRLevel FindNearestSR(ENUM_POSITION_TYPE trade_type, int lookback)
{
    SRLevel sr;
    sr.price = 0.0;
    sr.strength = 0;
    sr.is_resistance = (trade_type == POSITION_TYPE_BUY);
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(g_active_symbol, InpTimeframe, 0, lookback, rates);
    if(copied < 20) return sr;
    
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArrayResize(highs, copied);
    ArrayResize(lows, copied);
    
    for(int i = 0; i < copied; i++)
    {
        highs[i] = rates[i].high;
        lows[i] = rates[i].low;
    }
    
    double current_price = (trade_type == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(g_active_symbol, SYMBOL_ASK) :
                          SymbolInfoDouble(g_active_symbol, SYMBOL_BID);
    
    // Find pivot points (local highs for resistance, local lows for support)
    double best_level = 0.0;
    int best_strength = 0;
    double pip_value = GetPipValue();
    double tolerance = pip_value * 10; // 10 pips tolerance
    
    if(trade_type == POSITION_TYPE_BUY) // Looking for resistance above
    {
        for(int i = 5; i < copied - 5; i++)
        {
            if(highs[i] > current_price && 
               highs[i] > highs[i-1] && highs[i] > highs[i-2] &&
               highs[i] > highs[i+1] && highs[i] > highs[i+2])
            {
                // Count how many times price touched this level
                int touches = 0;
                for(int j = 0; j < copied; j++)
                {
                    if(MathAbs(highs[j] - highs[i]) <= tolerance ||
                       MathAbs(lows[j] - highs[i]) <= tolerance)
                        touches++;
                }
                
                if(touches > best_strength && (best_level == 0.0 || highs[i] < best_level))
                {
                    best_level = highs[i];
                    best_strength = touches;
                }
            }
        }
        sr.is_resistance = true;
    }
    else // Looking for support below
    {
        for(int i = 5; i < copied - 5; i++)
        {
            if(lows[i] < current_price &&
               lows[i] < lows[i-1] && lows[i] < lows[i-2] &&
               lows[i] < lows[i+1] && lows[i] < lows[i+2])
            {
                // Count touches
                int touches = 0;
                for(int j = 0; j < copied; j++)
                {
                    if(MathAbs(highs[j] - lows[i]) <= tolerance ||
                       MathAbs(lows[j] - lows[i]) <= tolerance)
                        touches++;
                }
                
                if(touches > best_strength && (best_level == 0.0 || lows[i] > best_level))
                {
                    best_level = lows[i];
                    best_strength = touches;
                }
            }
        }
        sr.is_resistance = false;
    }
    
    sr.price = best_level;
    sr.strength = best_strength;
    return sr;
}

double CalculateDynamicTP(ENUM_POSITION_TYPE trade_type, double entry_price)
{
    if(!InpUseDynamicTP) return 0.0;
    
    SRLevel sr = FindNearestSR(trade_type, InpSR_Lookback);
    if(sr.price == 0.0 || sr.strength < 2) return 0.0; // Not enough strength
    
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    double buffer = PipsToPoints(InpTP_BufferPips);
    
    if(trade_type == POSITION_TYPE_BUY)
    {
        // For long: TP just below resistance
        double tp = sr.price - buffer;
        if(tp > entry_price + (point * 10)) // Ensure TP is reasonable distance
            return tp;
    }
    else
    {
        // For short: TP just above support
        double tp = sr.price + buffer;
        if(tp < entry_price - (point * 10))
            return tp;
    }
    
    return 0.0;
}

//=========================== POSITION SIZING =======================
double CalculateLotSize(double sl_distance_points)
{
    if(InpFixedLotSize > 0) return InpFixedLotSize;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = balance * InpRiskPercent / 100.0;
    
    double tick_value = SymbolInfoDouble(g_active_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(g_active_symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    
    if(tick_value <= 0 || tick_size <= 0) return 0.0;
    
    double ticks = sl_distance_points * point / tick_size;
    double lots = risk_amount / (ticks * tick_value);
    
    // Normalize to broker constraints
    double min_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_STEP);
    
    lots = MathFloor(lots / lot_step) * lot_step;
    lots = MathMax(min_lot, MathMin(max_lot, lots));
    
    return lots;
}

//=========================== ENTRY LOGIC ===========================
bool CheckLongEntry()
{
    double ema_f[], ema_s[], rsi[], atr[];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    ArrayResize(ema_f, 2);
    ArrayResize(ema_s, 2);
    ArrayResize(rsi, 1);
    ArrayResize(atr, 1);
    
    if(CopyBuffer(h_ema_fast, 0, 0, 2, ema_f) < 2) return false;
    if(CopyBuffer(h_ema_slow, 0, 0, 2, ema_s) < 2) return false;
    if(CopyBuffer(h_rsi, 0, 0, 1, rsi) < 1) return false;
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return false;
    
    double close[];
    ArraySetAsSeries(close, true);
    if(CopyClose(g_active_symbol, InpTimeframe, 0, 1, close) <= 0) return false;
    double close_price = close[0];
    
    // EMA crossover: Fast EMA crosses above Slow EMA
    bool crossover = (ema_f[0] > ema_s[0]) && (ema_f[1] <= ema_s[1]);
    
    // Price above Fast EMA
    bool price_above = (close_price > ema_f[0]);
    
    // RSI filter - require stronger signals for M1
    bool rsi_ok = (rsi[0] > InpRSI_LongMin && rsi[0] < 70); // Avoid overbought
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    // Require both EMA alignment AND price confirmation for better accuracy
    bool ema_aligned = (ema_f[0] > ema_s[0]);
    bool strong_signal = crossover || (price_above && ema_aligned && ema_f[0] > ema_f[1]); // EMA rising
    
    return strong_signal && rsi_ok && vol_ok;
}

bool CheckShortEntry()
{
    double ema_f[], ema_s[], rsi[], atr[];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    ArrayResize(ema_f, 2);
    ArrayResize(ema_s, 2);
    ArrayResize(rsi, 1);
    ArrayResize(atr, 1);
    
    if(CopyBuffer(h_ema_fast, 0, 0, 2, ema_f) < 2) return false;
    if(CopyBuffer(h_ema_slow, 0, 0, 2, ema_s) < 2) return false;
    if(CopyBuffer(h_rsi, 0, 0, 1, rsi) < 1) return false;
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return false;
    
    double close[];
    ArraySetAsSeries(close, true);
    if(CopyClose(g_active_symbol, InpTimeframe, 0, 1, close) <= 0) return false;
    double close_price = close[0];
    
    // EMA crossover: Fast EMA crosses below Slow EMA
    bool crossover = (ema_f[0] < ema_s[0]) && (ema_f[1] >= ema_s[1]);
    
    // Price below Fast EMA
    bool price_below = (close_price < ema_f[0]);
    
    // RSI filter - require stronger signals for M1
    bool rsi_ok = (rsi[0] < InpRSI_ShortMax && rsi[0] > 30); // Avoid oversold
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    // Require both EMA alignment AND price confirmation for better accuracy
    bool ema_aligned = (ema_f[0] < ema_s[0]);
    bool strong_signal = crossover || (price_below && ema_aligned && ema_f[0] < ema_f[1]); // EMA falling
    
    return strong_signal && rsi_ok && vol_ok;
}

int CountOpenTrades()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(g_pos.SelectByIndex(i))
        {
            if(g_pos.Symbol() == g_active_symbol && g_pos.Magic() == InpMagicNumber)
                count++;
        }
    }
    return count;
}

bool CheckDailyLossLimit()
{
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double loss_pct = ((g_daily_balance_start - current_balance) / g_daily_balance_start) * 100.0;
    return (loss_pct < InpDailyLossLimit);
}

//=========================== REVERSAL DETECTION =====================
struct ReversalSignal
{
    bool detected;
    string reason;
    double strength; // 0-1 score
};

ReversalSignal DetectReversal(ENUM_POSITION_TYPE trade_type)
{
    ReversalSignal rev;
    rev.detected = false;
    rev.reason = "";
    rev.strength = 0.0;
    
    if(!InpUseReversalExit) return rev;
    
    // Get indicator values
    double rsi[], macd_main[], macd_signal[], macd_hist[];
    double ema_f[], ema_s[];
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(macd_main, true);
    ArraySetAsSeries(macd_signal, true);
    ArraySetAsSeries(macd_hist, true);
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    
    ArrayResize(rsi, 5);
    ArrayResize(macd_main, 3);
    ArrayResize(macd_signal, 3);
    ArrayResize(macd_hist, 3);
    ArrayResize(ema_f, 3);
    ArrayResize(ema_s, 3);
    
    if(CopyBuffer(h_rsi, 0, 0, 5, rsi) < 5) return rev;
    if(CopyBuffer(h_macd, 0, 0, 3, macd_main) < 3) return rev;
    if(CopyBuffer(h_macd, 1, 0, 3, macd_signal) < 3) return rev;
    if(CopyBuffer(h_macd, 2, 0, 3, macd_hist) < 3) return rev;
    if(CopyBuffer(h_ema_fast, 0, 0, 3, ema_f) < 3) return rev;
    if(CopyBuffer(h_ema_slow, 0, 0, 3, ema_s) < 3) return rev;
    
    // Get candle patterns
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(g_active_symbol, InpTimeframe, 0, 3, rates) < 3) return rev;
    
    double score = 0.0;
    string reason_parts = "";
    int reason_count = 0;
    
    if(trade_type == POSITION_TYPE_BUY)
    {
        // Bearish reversal signals
        
        // 1. RSI overbought and turning down
        if(rsi[0] > 70 && rsi[0] < rsi[1])
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "RSI_overbought_turn";
        }
        // RSI divergence (price makes new high, RSI makes lower high)
        if(rates[0].high > rates[2].high && rsi[0] < rsi[2])
        {
            score += 0.30;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "RSI_bearish_divergence";
        }
        
        // 2. MACD histogram flip negative
        if(macd_hist[0] < 0 && macd_hist[1] > 0)
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "MACD_flip_bearish";
        }
        // MACD crosses below signal
        if(macd_main[0] < macd_signal[0] && macd_main[1] >= macd_signal[1])
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "MACD_cross_bearish";
        }
        
        // 3. EMA fast crosses below slow (trend reversal)
        if(ema_f[0] < ema_s[0] && ema_f[1] >= ema_s[1])
        {
            score += 0.30;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "EMA_cross_bearish";
        }
        
        // 4. Bearish engulfing candle
        double body_now = MathAbs(rates[0].close - rates[0].open);
        double body_prev = MathAbs(rates[1].close - rates[1].open);
        bool bearish_engulf = (body_now > body_prev * 1.2) &&
                             (rates[0].close < rates[0].open) &&
                             (rates[1].close > rates[1].open) &&
                             (rates[0].open > rates[1].close) &&
                             (rates[0].close < rates[1].open);
        if(bearish_engulf)
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "Bearish_engulfing";
        }
        
        // 5. Doji at high (indecision)
        double range = rates[0].high - rates[0].low;
        bool doji = (range > 0 && body_now / range < 0.1 && body_now > 0);
        if(doji && rates[0].high > rates[1].high)
        {
            score += 0.15;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "Doji_at_high";
        }
    }
    else // POSITION_TYPE_SELL
    {
        // Bullish reversal signals
        
        // 1. RSI oversold and turning up
        if(rsi[0] < 30 && rsi[0] > rsi[1])
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "RSI_oversold_turn";
        }
        // RSI divergence (price makes new low, RSI makes higher low)
        if(rates[0].low < rates[2].low && rsi[0] > rsi[2])
        {
            score += 0.30;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "RSI_bullish_divergence";
        }
        
        // 2. MACD histogram flip positive
        if(macd_hist[0] > 0 && macd_hist[1] < 0)
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "MACD_flip_bullish";
        }
        // MACD crosses above signal
        if(macd_main[0] > macd_signal[0] && macd_main[1] <= macd_signal[1])
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "MACD_cross_bullish";
        }
        
        // 3. EMA fast crosses above slow (trend reversal)
        if(ema_f[0] > ema_s[0] && ema_f[1] <= ema_s[1])
        {
            score += 0.30;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "EMA_cross_bullish";
        }
        
        // 4. Bullish engulfing candle
        double body_now = MathAbs(rates[0].close - rates[0].open);
        double body_prev = MathAbs(rates[1].close - rates[1].open);
        bool bullish_engulf = (body_now > body_prev * 1.2) &&
                             (rates[0].close > rates[0].open) &&
                             (rates[1].close < rates[1].open) &&
                             (rates[0].open < rates[1].close) &&
                             (rates[0].close > rates[1].open);
        if(bullish_engulf)
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "Bullish_engulfing";
        }
        
        // 5. Doji at low (indecision)
        double range = rates[0].high - rates[0].low;
        bool doji = (range > 0 && body_now / range < 0.1 && body_now > 0);
        if(doji && rates[0].low < rates[1].low)
        {
            score += 0.15;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "Doji_at_low";
        }
    }
    
    // Normalize score to 0-1 and apply sensitivity
    score = MathMin(1.0, score);
    double threshold = 0.3 + (InpReversalSensitivity * 0.07); // 0.3 to 1.0 scale
    threshold = MathMin(0.9, threshold); // Cap at 0.9
    
    if(score >= threshold)
    {
        rev.detected = true;
        rev.strength = score;
        rev.reason = reason_parts;
    }
    
    return rev;
}

//=========================== EXIT LOGIC ============================
void PlotReversalMarker(double price, string label)
{
    string obj_name = "Reversal_" + TimeToString(TimeCurrent(), TIME_SECONDS);
    ObjectCreate(0, obj_name, OBJ_ARROW_DOWN, 0, TimeCurrent(), price);
    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 234); // Arrow down
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrRed);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 2);
    ObjectSetString(0, obj_name, OBJPROP_TEXT, label);
}

void ManageExits()
{
    double atr[];
    ArraySetAsSeries(atr, true);
    ArrayResize(atr, 1);
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Symbol() != g_active_symbol || g_pos.Magic() != InpMagicNumber) continue;
        
        ulong ticket = g_pos.Ticket();
        double open_price = g_pos.PriceOpen();
        double sl = g_pos.StopLoss();
        double tp = g_pos.TakeProfit();
        ENUM_POSITION_TYPE type = g_pos.PositionType();
        datetime open_time = (datetime)g_pos.Time();
        
        double current_price = (type == POSITION_TYPE_BUY) ? 
                               SymbolInfoDouble(g_active_symbol, SYMBOL_BID) :
                               SymbolInfoDouble(g_active_symbol, SYMBOL_ASK);
        
        double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
        double atr_points = atr[0] / point;
        
        // REVERSAL DETECTION - Check first for early exit
        ReversalSignal rev = DetectReversal(type);
        if(rev.detected)
        {
            double profit = g_pos.Profit();
            string profit_status = (profit > 0) ? "profit" : "loss";
            
            // Close position immediately
            if(g_trade.PositionClose(ticket))
            {
                string reason = StringFormat("Reversal detected: %s (strength=%.2f)", 
                                            rev.reason, rev.strength);
                Print("REVERSAL EXIT: ", reason, " | ", profit_status, "=$", profit);
                LogTrade("REVERSAL_EXIT", current_price, sl, tp, g_pos.Volume(), reason);
                
                // Plot marker on chart
                PlotReversalMarker(current_price, rev.reason);
                
                // Enter standby mode
                g_standby_until = TimeCurrent() + (InpWaitAfterCloseMinutes * 60);
                Print("Entering standby mode until: ", TimeToString(g_standby_until, TIME_MINUTES));
                
                // Close any other open positions
                for(int j = PositionsTotal() - 1; j >= 0; j--)
                {
                    if(g_pos.SelectByIndex(j) && 
                       g_pos.Symbol() == g_active_symbol && 
                       g_pos.Magic() == InpMagicNumber &&
                       g_pos.Ticket() != ticket)
                    {
                        g_trade.PositionClose(g_pos.Ticket());
                        Print("Also closed position ", g_pos.Ticket(), " due to reversal");
                    }
                }
            }
            continue; // Move to next position
        }
        
        // Time-based exit
        if(InpMaxTradeLifeMin > 0)
        {
            long time_diff = (long)(TimeCurrent() - open_time);
            int minutes_open = (int)(time_diff / 60);
            if(minutes_open >= InpMaxTradeLifeMin)
            {
                g_trade.PositionClose(ticket);
                LogTrade("TIME_EXIT", current_price, sl, tp, g_pos.Volume(), "Max time reached");
                continue;
            }
        }
        
        // Break-even move
        if(InpUseBreakEven && sl != 0 && sl != open_price)
        {
            double be_threshold = atr_points * InpBE_TriggerATR;
            double profit_points = 0;
            
            if(type == POSITION_TYPE_BUY)
            {
                profit_points = (current_price - open_price) / point;
                if(profit_points >= be_threshold && sl < open_price)
                {
                    g_trade.PositionModify(ticket, open_price, tp);
                    Print("Moved to breakeven: ", ticket);
                }
            }
            else
            {
                profit_points = (open_price - current_price) / point;
                if(profit_points >= be_threshold && (sl > open_price || sl == 0))
                {
                    g_trade.PositionModify(ticket, open_price, tp);
                    Print("Moved to breakeven: ", ticket);
                }
            }
        }
        
        // Trailing stop
        if(InpUseTrailing)
        {
            double trail_start_points = atr_points * InpTrailStart;
            double trail_step_points = PipsToPoints(InpTrailStep);
            double new_sl = sl;
            bool modify = false;
            
            if(type == POSITION_TYPE_BUY)
            {
                double profit_points = (current_price - open_price) / point;
                if(profit_points >= trail_start_points)
                {
                    double potential_sl = current_price - (atr_points * InpSL_Multiplier);
                    if(potential_sl > sl + trail_step_points)
                    {
                        new_sl = potential_sl;
                        modify = true;
                    }
                }
            }
            else
            {
                double profit_points = (open_price - current_price) / point;
                if(profit_points >= trail_start_points)
                {
                    double potential_sl = current_price + (atr_points * InpSL_Multiplier);
                    if(potential_sl < sl - trail_step_points || sl == 0)
                    {
                        new_sl = potential_sl;
                        modify = true;
                    }
                }
            }
            
            if(modify)
            {
                g_trade.PositionModify(ticket, new_sl, tp);
            }
        }
    }
}

//=========================== TRADE EXECUTION =======================
bool TryEnterLong()
{
    if(CountOpenTrades() >= InpMaxOpenTrades) return false;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    ArrayResize(atr, 1);
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return false;
    
    double ask = SymbolInfoDouble(g_active_symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    double sl_distance = atr[0] * InpSL_Multiplier;
    
    double sl = ask - sl_distance;
    double tp = 0.0;
    
    // Try dynamic TP first
    if(InpUseDynamicTP)
    {
        tp = CalculateDynamicTP(POSITION_TYPE_BUY, ask);
        if(tp > 0 && tp > ask)
        {
            Print("Using dynamic TP @ ", tp, " (from S/R level)");
        }
    }
    
    // Fallback to ATR-based TP
    if(tp <= 0)
    {
        double tp_distance = atr[0] * InpTP_Multiplier;
        tp = ask + tp_distance;
    }
    
    // Check minimum stop level
    double min_stop = SymbolInfoInteger(g_active_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    if(MathAbs(ask - sl) < min_stop) sl = ask - min_stop - point;
    if(MathAbs(tp - ask) < min_stop) tp = ask + min_stop + point;
    
    double lots = CalculateLotSize(sl_distance / point);
    if(lots <= 0) return false;
    
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints((int)PipsToPoints(InpMaxSlippage));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Buy(lots, g_active_symbol, ask, sl, tp, "EURUSDm Long"))
    {
        Print("LONG entry: ", lots, " lots @ ", ask, " SL=", sl, " TP=", tp);
        LogTrade("LONG", ask, sl, tp, lots, "EMA crossover + RSI");
        return true;
    }
    else
    {
        Print("LONG entry failed: ", g_trade.ResultRetcode());
        return false;
    }
}

bool TryEnterShort()
{
    if(CountOpenTrades() >= InpMaxOpenTrades) return false;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    ArrayResize(atr, 1);
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return false;
    
    double bid = SymbolInfoDouble(g_active_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    double sl_distance = atr[0] * InpSL_Multiplier;
    
    double sl = bid + sl_distance;
    double tp = 0.0;
    
    // Try dynamic TP first
    if(InpUseDynamicTP)
    {
        tp = CalculateDynamicTP(POSITION_TYPE_SELL, bid);
        if(tp > 0 && tp < bid)
        {
            Print("Using dynamic TP @ ", tp, " (from S/R level)");
        }
    }
    
    // Fallback to ATR-based TP
    if(tp <= 0)
    {
        double tp_distance = atr[0] * InpTP_Multiplier;
        tp = bid - tp_distance;
    }
    
    // Check minimum stop level
    double min_stop = SymbolInfoInteger(g_active_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    if(MathAbs(sl - bid) < min_stop) sl = bid + min_stop + point;
    if(MathAbs(bid - tp) < min_stop) tp = bid - min_stop - point;
    
    double lots = CalculateLotSize(sl_distance / point);
    if(lots <= 0) return false;
    
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints((int)PipsToPoints(InpMaxSlippage));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Sell(lots, g_active_symbol, bid, sl, tp, "EURUSDm Short"))
    {
        Print("SHORT entry: ", lots, " lots @ ", bid, " SL=", sl, " TP=", tp);
        LogTrade("SHORT", bid, sl, tp, lots, "EMA crossover + RSI");
        return true;
    }
    else
    {
        Print("SHORT entry failed: ", g_trade.ResultRetcode());
        return false;
    }
}

//=========================== MAIN LOGIC ============================
void OnTick()
{
    // Process only on new bar
    datetime current_bar[];
    ArraySetAsSeries(current_bar, true);
    ArrayResize(current_bar, 1);
    if(CopyTime(g_active_symbol, InpTimeframe, 0, 1, current_bar) <= 0) return;
    
    if(current_bar[0] == g_last_bar_time) 
    {
        ManageExits(); // Manage exits every tick
        return;
    }
    g_last_bar_time = current_bar[0];
    
    // Safety checks
    if(!InpEnableTrading) return;
    if(!IsTradingHours()) return;
    if(!IsValidSpread()) return;
    if(IsNewsWindow()) return;
    if(!CheckDailyLossLimit()) 
    {
        Print("Daily loss limit reached!");
        return;
    }
    
    // Weekday check
    if(!InpAllowWeekend)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        if(dt.day_of_week == 0 || dt.day_of_week == 6) return;
    }
    
    // Manage existing positions
    ManageExits();
    
    // Standby mode check (wait after reversal close)
    if(TimeCurrent() < g_standby_until)
    {
        int remaining_sec = (int)(g_standby_until - TimeCurrent());
        if((remaining_sec % 60) == 0) // Print every minute
            Print("Standby mode: ", remaining_sec/60, " minutes remaining");
        return; // Don't open new trades during standby
    }
    
    // Check for new entries with signal confirmation
    bool long_signal = CheckLongEntry();
    bool short_signal = CheckShortEntry();
    
    // Track consecutive signal bars
    if(long_signal)
    {
        g_long_signal_count++;
        g_short_signal_count = 0; // Reset opposite signal
    }
    else if(short_signal)
    {
        g_short_signal_count++;
        g_long_signal_count = 0; // Reset opposite signal
    }
    else
    {
        // No signal - reset both counters
        g_long_signal_count = 0;
        g_short_signal_count = 0;
    }
    
    // Enter only after confirmation across N bars
    if(g_long_signal_count >= InpSignalConfirmation && long_signal)
    {
        if(TryEnterLong())
        {
            g_long_signal_count = 0; // Reset after entry
        }
    }
    else if(g_short_signal_count >= InpSignalConfirmation && short_signal)
    {
        if(TryEnterShort())
        {
            g_short_signal_count = 0; // Reset after entry
        }
    }
}

//=========================== INITIALIZATION ========================
int OnInit()
{
    // Symbol detection
    if(InpSymbol == "" || InpSymbol == "EURUSDm")
    {
        g_active_symbol = DetectEURUSDSymbol();
    }
    else
    {
        g_active_symbol = InpSymbol;
        if(!SymbolSelect(g_active_symbol, true))
        {
            Print("ERROR: Symbol not found: ", g_active_symbol);
            return INIT_FAILED;
        }
    }
    
    Print("========================================");
    Print("EURUSDm Robot Initialized - M1 Optimized");
    Print("Symbol: ", g_active_symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Magic Number: ", InpMagicNumber);
    Print("Signal Confirmation: ", InpSignalConfirmation, " bars");
    Print("Risk per Trade: ", InpRiskPercent, "%");
    Print("Max Spread: ", InpMaxSpread, " pips");
    Print("========================================");
    
    // Initialize indicators
    if(!CreateIndicators())
    {
        Print("ERROR: Failed to initialize indicators");
        return INIT_FAILED;
    }
    
    // Initialize session tracking
    g_session_start = TimeCurrent();
    g_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_daily_balance_start = g_start_balance;
    
    // Initialize logging
    InitializeLogging();
    
    // Set timer for daily balance tracking (every 1 hour)
    EventSetTimer(3600);
    
    Print("Robot ready. Waiting for signals...");
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    EventKillTimer();
    Print("EURUSDm Robot deinitialized. Reason: ", reason);
}

void OnTimer() // Called periodically - update daily balance reset
{
    static int last_day = -1;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(last_day != dt.day)
    {
        g_daily_balance_start = AccountInfoDouble(ACCOUNT_BALANCE);
        last_day = dt.day;
        Print("Daily balance reset. New starting balance: ", g_daily_balance_start);
    }
}
