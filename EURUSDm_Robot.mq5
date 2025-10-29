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
input double   InpRSI_LongMin      = 50.0;          // RSI minimum for long entry (base value)
input double   InpRSI_ShortMax     = 50.0;           // RSI maximum for short entry (base value)
input bool     InpAdaptiveRSI      = true;           // Adjust RSI thresholds based on volatility
input double   InpRSI_VolatilityAdjust = 5.0;        // RSI adjustment per ATR deviation
input int      InpSignalConfirmation = 2;           // Require N consecutive bars with signal
input bool     InpUseADXFilter     = true;           // Use ADX to filter choppy markets
input int      InpADX_Period       = 14;            // ADX period
input double   InpADX_MinLevel     = 20.0;          // Minimum ADX for trade (trend strength)
input bool     InpVolumeConfirm    = true;           // Require volume/volatility confirmation
input int      InpVolumeLookback   = 5;              // Bars to check for volume confirmation

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
input bool     InpMTF_ReversalConf = true;          // Multi-timeframe reversal confirmation
input ENUM_TIMEFRAMES InpMTF_Period = PERIOD_M5;    // Higher TF for reversal confirmation
input bool     InpUsePartialTP     = true;          // Enable partial profit taking
input double   InpPartialTP_ATR   = 1.0;            // Close 50% at this ATR multiple
input bool     InpDynamicTP_Update = true;           // Recalculate TP during trade (every N bars)
input int      InpTP_UpdateBars    = 3;              // Bars between TP recalculation

input group "=== RISK MANAGEMENT ===";
input double   InpRiskPercent      = 0.5;          // Risk % per trade (lower for M1)
input double   InpFixedLotSize     = 0.0;           // Fixed lot size (0=use risk%)
input double   InpFixedRiskDollars  = 0.0;           // Fixed risk in dollars (0=use %)
input bool     InpVolatilityBasedLot = true;        // Reduce lot size when ATR is high
input double   InpVolatilityLotAdjust = 0.8;         // Lot multiplier for high volatility (0.8 = 80%)
input double   InpHighVolATR_Mult   = 1.5;          // ATR multiplier threshold for "high volatility"
input int      InpMaxOpenTrades    = 1;             // Maximum concurrent trades
input double   InpDailyLossLimit   = 5.0;           // Daily loss limit (% of closed balance)
input double   InpEquityDrawdownLimit = 10.0;        // Max equity drawdown % (live protection)
input double   InpMaxSpread        = 1.5;           // Maximum spread (pips - tighter for M1)
input double   InpMaxSlippage      = 2.0;           // Maximum slippage (pips - tighter for M1)
input bool     InpAdaptiveSlippage = true;          // Increase slippage tolerance during volatility
input bool     InpWeekendGapProtection = true;      // Close/tighten stops before weekend

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
int            h_adx      = INVALID_HANDLE;  // For trend strength filter
int            h_bb       = INVALID_HANDLE;  // Bollinger Bands for reversal confirmation

// Session tracking
datetime       g_session_start = 0;
double         g_start_balance = 0.0;
double         g_daily_balance_start = 0.0;
double         g_max_equity = 0.0;            // Track max equity for drawdown calculation
datetime       g_last_bar_time = 0;
bool           g_broker_checked = false;      // Broker compatibility check flag
bool           g_broker_compatible = false;   // Broker compatibility result

// Symbol detection
string         g_active_symbol = "";

// Logging
string         g_log_file = "";

// Signal confirmation tracking
int            g_long_signal_count = 0;
int            g_short_signal_count = 0;

// Standby mode (after reversal close)
datetime       g_standby_until = 0;

// Partial TP and dynamic TP tracking (ticket -> state)
struct TradeState
{
    ulong ticket;
    bool partial_taken;
    datetime last_tp_update_bar;
};
TradeState g_trade_states[];

//=========================== BROKER VALIDATION =====================
bool CheckBrokerCompatibility()
{
    if(g_broker_checked) return g_broker_compatible;
    
    g_broker_checked = true;
    string issues = "";
    
    // Check hedging mode (needed for multiple positions)
    ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && InpMaxOpenTrades > 1)
    {
        issues += "Hedging mode not enabled (needed for multiple positions); ";
    }
    
    // Check minimum lot size
    double min_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MIN);
    if(min_lot > 0.01)
    {
        issues += StringFormat("Min lot %.2f may be too large for micro accounts; ", min_lot);
    }
    
    // Check stop level
    int stop_level = (int)SymbolInfoInteger(g_active_symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stop_level > 50) // More than 5 pips for 5-digit broker
    {
        issues += StringFormat("Stop level %d points may be too restrictive; ", stop_level);
    }
    
    // Check contract size (micro should be 1000, standard 100000)
    double contract_size = SymbolInfoDouble(g_active_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    if(contract_size == 0)
    {
        issues += "Contract size is zero (symbol may not be available); ";
    }
    
    if(issues == "")
    {
        g_broker_compatible = true;
        Print("OK: Broker compatibility check passed");
        return true;
    }
    else
    {
        Print("WARNING: Broker compatibility issues detected: ", issues);
        g_broker_compatible = false;
        return false;
    }
}

//=========================== EQUITY DRAWDOWN CHECK =================
bool CheckEquityDrawdown()
{
    if(InpEquityDrawdownLimit <= 0) return true; // Disabled
    
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Track max equity
    if(current_equity > g_max_equity || g_max_equity == 0)
        g_max_equity = current_equity;
    
    // Calculate drawdown from max equity
    if(g_max_equity > 0)
    {
        double drawdown_pct = ((g_max_equity - current_equity) / g_max_equity) * 100.0;
        
        if(drawdown_pct >= InpEquityDrawdownLimit)
        {
            Print("STOP: Equity drawdown limit reached: ", drawdown_pct, "% (limit: ", InpEquityDrawdownLimit, "%)");
            return false; // Stop trading
        }
    }
    
    return true; // OK to trade
}

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
    
    if(InpUseADXFilter)
    {
        h_adx = iADX(g_active_symbol, InpTimeframe, InpADX_Period);
        if(h_adx == INVALID_HANDLE)
        {
            Print("ERROR: Failed to create ADX indicator. Error: ", GetLastError());
            return false;
        }
    }
    
    // Bollinger Bands for reversal confirmation
    h_bb = iBands(g_active_symbol, InpTimeframe, 20, 0, 2, PRICE_CLOSE);
    if(h_bb == INVALID_HANDLE)
    {
        Print("WARNING: Failed to create Bollinger Bands. Reversal detection may be less accurate.");
        // Don't fail initialization for optional indicator
    }
    
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

//=========================== SLIPPAGE MANAGEMENT ==================
double GetAdaptiveSlippagePips()
{
    double base_slippage = InpMaxSlippage;
    
    if(!InpAdaptiveSlippage) return base_slippage;
    
    // Measure recent average spread and ATR volatility
    double atr_current[], atr_avg[];
    ArraySetAsSeries(atr_current, true);
    ArraySetAsSeries(atr_avg, true);
    ArrayResize(atr_current, 1);
    ArrayResize(atr_avg, 10);
    
    if(CopyBuffer(h_atr, 0, 0, 1, atr_current) >= 1 && 
       CopyBuffer(h_atr, 0, 0, 10, atr_avg) >= 10)
    {
        double atr_sum = 0;
        for(int i = 0; i < 10; i++) atr_sum += atr_avg[i];
        double atr_mean = atr_sum / 10.0;
        
        // If current ATR is significantly above average, increase slippage tolerance
        if(atr_current[0] >= atr_mean * 1.3) // 30% above average
        {
            base_slippage *= 1.5; // Increase by 50%
        }
        else if(atr_current[0] >= atr_mean * 1.1) // 10% above average
        {
            base_slippage *= 1.2; // Increase by 20%
        }
    }
    
    // Also check current spread
    double spread = (SymbolInfoDouble(g_active_symbol, SYMBOL_ASK) - 
                     SymbolInfoDouble(g_active_symbol, SYMBOL_BID)) / GetPipValue();
    if(spread > InpMaxSpread * 1.5)
    {
        base_slippage *= 1.3; // Increase slippage during wide spreads
    }
    
    return MathMin(base_slippage, InpMaxSlippage * 2.0); // Cap at 2x base
}

//=========================== POSITION SIZING =======================
double CalculateLotSize(double sl_distance_points)
{
    if(InpFixedLotSize > 0) return InpFixedLotSize;
    
    double risk_amount = 0.0;
    
    // Fixed dollar risk OR percentage-based
    if(InpFixedRiskDollars > 0)
    {
        risk_amount = InpFixedRiskDollars;
    }
    else
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        risk_amount = balance * InpRiskPercent / 100.0;
    }
    
    double tick_value = SymbolInfoDouble(g_active_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(g_active_symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    
    if(tick_value <= 0 || tick_size <= 0) return 0.0;
    
    double ticks = sl_distance_points * point / tick_size;
    double lots = risk_amount / (ticks * tick_value);
    
    // VOLATILITY-BASED ADJUSTMENT: Reduce lot size when ATR is high
    if(InpVolatilityBasedLot)
    {
        double atr_current[], atr_avg[];
        ArraySetAsSeries(atr_current, true);
        ArraySetAsSeries(atr_avg, true);
        ArrayResize(atr_current, 1);
        ArrayResize(atr_avg, 20);
        
        if(CopyBuffer(h_atr, 0, 0, 1, atr_current) >= 1 && 
           CopyBuffer(h_atr, 0, 0, 20, atr_avg) >= 20)
        {
            double atr_sum = 0;
            for(int i = 0; i < 20; i++) atr_sum += atr_avg[i];
            double atr_mean = atr_sum / 20.0;
            
            // If current ATR is above threshold, reduce lot size
            if(atr_current[0] >= atr_mean * InpHighVolATR_Mult)
            {
                lots *= InpVolatilityLotAdjust; // e.g., 0.8 = reduce by 20%
            }
        }
    }
    
    // Normalize to broker constraints
    double min_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_STEP);
    
    lots = MathFloor(lots / lot_step) * lot_step;
    lots = MathMax(min_lot, MathMin(max_lot, lots));
    
    return lots;
}

//=========================== FILTER FUNCTIONS =======================
void GetAdaptiveRSIThresholds(double &long_min, double &short_max)
{
    long_min = InpRSI_LongMin;
    short_max = InpRSI_ShortMax;
    
    if(!InpAdaptiveRSI) return;
    
    // Get current ATR and historical ATR average
    double atr_current[], atr_avg[];
    ArraySetAsSeries(atr_current, true);
    ArraySetAsSeries(atr_avg, true);
    ArrayResize(atr_current, 1);
    ArrayResize(atr_avg, 20);
    
    if(CopyBuffer(h_atr, 0, 0, 1, atr_current) < 1) return;
    if(CopyBuffer(h_atr, 0, 0, 20, atr_avg) < 20) return;
    
    // Calculate average ATR
    double atr_sum = 0;
    for(int i = 0; i < 20; i++) atr_sum += atr_avg[i];
    double atr_mean = atr_sum / 20.0;
    
    // Calculate deviation (higher volatility = relax RSI thresholds)
    double deviation = (atr_current[0] - atr_mean) / atr_mean; // -1 to +1 typically
    double adjustment = deviation * InpRSI_VolatilityAdjust;
    
    // Adjust thresholds (high volatility = lower long_min, higher short_max)
    long_min = MathMax(30.0, MathMin(70.0, InpRSI_LongMin - adjustment));
    short_max = MathMin(70.0, MathMax(30.0, InpRSI_ShortMax + adjustment));
}

bool CheckADXFilter()
{
    if(!InpUseADXFilter) return true;
    if(h_adx == INVALID_HANDLE) return false;
    
    double adx[];
    ArraySetAsSeries(adx, true);
    ArrayResize(adx, 1);
    if(CopyBuffer(h_adx, 0, 0, 1, adx) < 1) return false;
    
    return (adx[0] >= InpADX_MinLevel);
}

bool CheckVolumeConfirmation()
{
    if(!InpVolumeConfirm) return true;
    
    // Use tick volume or ATR slope as proxy for momentum
    long tick_volume[];
    ArraySetAsSeries(tick_volume, true);
    ArrayResize(tick_volume, InpVolumeLookback + 5);
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(g_active_symbol, InpTimeframe, 0, InpVolumeLookback + 5, rates) < InpVolumeLookback + 5)
        return false;
    
    // Option 1: Check increasing volume (if tick volume available)
    // Option 2: Check ATR slope (volatility expansion = real move)
    double atr_values[];
    ArraySetAsSeries(atr_values, true);
    ArrayResize(atr_values, InpVolumeLookback);
    if(CopyBuffer(h_atr, 0, 0, InpVolumeLookback, atr_values) < InpVolumeLookback)
        return false;
    
    // ATR increasing = volatility/momentum expanding = real directional move
    // Compare recent ATR to average
    double atr_sum = 0;
    for(int i = 0; i < InpVolumeLookback; i++)
        atr_sum += atr_values[i];
    double atr_avg = atr_sum / InpVolumeLookback;
    
    // Recent ATR should be above average (momentum confirmation)
    return (atr_values[0] >= atr_avg * 0.95); // At least 95% of average
}

bool CheckMTFReversal(ENUM_POSITION_TYPE trade_type)
{
    if(!InpMTF_ReversalConf) return true; // If disabled, don't block
    
    // Check higher timeframe for reversal confirmation
    int h_rsi_mtf = iRSI(g_active_symbol, InpMTF_Period, InpRSI_Period, PRICE_CLOSE);
    int h_ema_f_mtf = iMA(g_active_symbol, InpMTF_Period, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    int h_ema_s_mtf = iMA(g_active_symbol, InpMTF_Period, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
    
    if(h_rsi_mtf == INVALID_HANDLE || h_ema_f_mtf == INVALID_HANDLE || h_ema_s_mtf == INVALID_HANDLE)
        return true; // If indicators fail, don't block
    
    double rsi_mtf[], ema_f_mtf[], ema_s_mtf[];
    ArraySetAsSeries(rsi_mtf, true);
    ArraySetAsSeries(ema_f_mtf, true);
    ArraySetAsSeries(ema_s_mtf, true);
    ArrayResize(rsi_mtf, 2);
    ArrayResize(ema_f_mtf, 2);
    ArrayResize(ema_s_mtf, 2);
    
    if(CopyBuffer(h_rsi_mtf, 0, 0, 2, rsi_mtf) < 2) return true;
    if(CopyBuffer(h_ema_f_mtf, 0, 0, 2, ema_f_mtf) < 2) return true;
    if(CopyBuffer(h_ema_s_mtf, 0, 0, 2, ema_s_mtf) < 2) return true;
    
    IndicatorRelease(h_rsi_mtf);
    IndicatorRelease(h_ema_f_mtf);
    IndicatorRelease(h_ema_s_mtf);
    
    if(trade_type == POSITION_TYPE_BUY)
    {
        // Bearish reversal on higher TF: RSI overbought or EMA cross down
        bool rsi_bearish = (rsi_mtf[0] > 70 && rsi_mtf[0] < rsi_mtf[1]);
        bool ema_bearish = (ema_f_mtf[0] < ema_s_mtf[0] && ema_f_mtf[1] >= ema_s_mtf[1]);
        return !(rsi_bearish || ema_bearish); // Return true if NO reversal
    }
    else
    {
        // Bullish reversal on higher TF: RSI oversold or EMA cross up
        bool rsi_bullish = (rsi_mtf[0] < 30 && rsi_mtf[0] > rsi_mtf[1]);
        bool ema_bullish = (ema_f_mtf[0] > ema_s_mtf[0] && ema_f_mtf[1] <= ema_s_mtf[1]);
        return !(rsi_bullish || ema_bullish); // Return true if NO reversal
    }
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
    
    // Adaptive RSI filter
    double rsi_long_min, rsi_short_max;
    GetAdaptiveRSIThresholds(rsi_long_min, rsi_short_max);
    bool rsi_ok = (rsi[0] > rsi_long_min && rsi[0] < 70); // Avoid overbought
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    // ADX trend strength filter
    bool adx_ok = CheckADXFilter();
    
    // Volume/volatility confirmation
    bool volume_ok = CheckVolumeConfirmation();
    
    // Require both EMA alignment AND price confirmation for better accuracy
    bool ema_aligned = (ema_f[0] > ema_s[0]);
    bool strong_signal = crossover || (price_above && ema_aligned && ema_f[0] > ema_f[1]); // EMA rising
    
    return strong_signal && rsi_ok && vol_ok && adx_ok && volume_ok;
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
    
    // Adaptive RSI filter
    double rsi_long_min, rsi_short_max;
    GetAdaptiveRSIThresholds(rsi_long_min, rsi_short_max);
    bool rsi_ok = (rsi[0] < rsi_short_max && rsi[0] > 30); // Avoid oversold
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    // ADX trend strength filter
    bool adx_ok = CheckADXFilter();
    
    // Volume/volatility confirmation
    bool volume_ok = CheckVolumeConfirmation();
    
    // Require both EMA alignment AND price confirmation for better accuracy
    bool ema_aligned = (ema_f[0] < ema_s[0]);
    bool strong_signal = crossover || (price_below && ema_aligned && ema_f[0] < ema_f[1]); // EMA falling
    
    return strong_signal && rsi_ok && vol_ok && adx_ok && volume_ok;
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
    
    // Get candle patterns and price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(g_active_symbol, InpTimeframe, 0, 5, rates) < 5) return rev; // Need more for price action
    
    // Get Bollinger Bands (if available)
    double bb_upper[], bb_lower[], bb_middle[];
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_lower, true);
    ArraySetAsSeries(bb_middle, true);
    ArrayResize(bb_upper, 2);
    ArrayResize(bb_lower, 2);
    ArrayResize(bb_middle, 2);
    bool bb_available = false;
    if(h_bb != INVALID_HANDLE && CopyBuffer(h_bb, 1, 0, 2, bb_upper) >= 2 &&
       CopyBuffer(h_bb, 2, 0, 2, bb_lower) >= 2 && CopyBuffer(h_bb, 0, 0, 2, bb_middle) >= 2)
        bb_available = true;
    
    // Price action: Check for higher-high/lower-low structures
    bool price_action_reversal = false;
    if(trade_type == POSITION_TYPE_BUY)
    {
        // Bearish: Check for lower high structure (reversal pattern)
        if(rates[0].high < rates[2].high && rates[1].high < rates[3].high)
            price_action_reversal = true;
    }
    else
    {
        // Bullish: Check for higher low structure (reversal pattern)
        if(rates[0].low > rates[2].low && rates[1].low > rates[3].low)
            price_action_reversal = true;
    }
    
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
        
        // 6. Bollinger Band bounce from upper band (bearish reversal)
        if(bb_available && rates[0].high >= bb_upper[0] * 0.999) // Within 0.1% of upper band
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "BB_bounce_upper";
        }
        
        // 7. Price action: Lower high structure (bearish reversal pattern)
        if(price_action_reversal)
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "PA_lower_high";
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
        
        // 6. Bollinger Band bounce from lower band (bullish reversal)
        if(bb_available && rates[0].low <= bb_lower[0] * 1.001) // Within 0.1% of lower band
        {
            score += 0.20;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "BB_bounce_lower";
        }
        
        // 7. Price action: Higher low structure (bullish reversal pattern)
        if(price_action_reversal)
        {
            score += 0.25;
            if(reason_count > 0) reason_parts += "+";
            reason_count++;
            reason_parts += "PA_higher_low";
        }
    }
    
    // Normalize score to 0-1 and apply sensitivity
    score = MathMin(1.0, score);
    double threshold = 0.3 + (InpReversalSensitivity * 0.07); // 0.3 to 1.0 scale
    
    // ADAPTIVE SENSITIVITY: Adjust based on ATR volatility
    // Higher volatility → lower sensitivity (prevent premature exits in volatile trends)
    double atr_current[], atr_avg[];
    ArraySetAsSeries(atr_current, true);
    ArraySetAsSeries(atr_avg, true);
    ArrayResize(atr_current, 1);
    ArrayResize(atr_avg, 10);
    
    if(CopyBuffer(h_atr, 0, 0, 1, atr_current) >= 1 && 
       CopyBuffer(h_atr, 0, 0, 10, atr_avg) >= 10)
    {
        double atr_sum = 0;
        for(int i = 0; i < 10; i++) atr_sum += atr_avg[i];
        double atr_mean = atr_sum / 10.0;
        
        // If volatility is high, increase threshold (lower sensitivity = need stronger reversal)
        if(atr_current[0] >= atr_mean * 1.3)
            threshold *= 1.15; // 15% higher threshold = less sensitive
        else if(atr_current[0] >= atr_mean * 1.1)
            threshold *= 1.08; // 8% higher threshold
    }
    
    threshold = MathMin(0.9, threshold); // Cap at 0.9
    
    if(score >= threshold)
    {
        // Multi-timeframe confirmation: Only exit if higher TF also shows reversal
        if(InpMTF_ReversalConf)
        {
            bool mtf_confirms = !CheckMTFReversal(trade_type); // CheckMTFReversal returns true if NO reversal
            if(!mtf_confirms)
            {
                // Higher TF doesn't confirm reversal - reduce score but don't exit
                score *= 0.7; // Reduce strength by 30%
                if(score < threshold * 1.2) // Only exit if score is still very high
                {
                    return rev; // Don't exit
                }
            }
        }
        
        rev.detected = true;
        rev.strength = score;
        rev.reason = reason_parts;
    }
    
    return rev;
}

//=========================== TRADE STATE MANAGEMENT ===============
int GetTradeStateIndex(ulong ticket)
{
    for(int i = 0; i < ArraySize(g_trade_states); i++)
    {
        if(g_trade_states[i].ticket == ticket)
            return i;
    }
    return -1; // Not found
}

void AddTradeState(ulong ticket)
{
    // Check if already exists
    if(GetTradeStateIndex(ticket) >= 0) return;
    
    int size = ArraySize(g_trade_states);
    ArrayResize(g_trade_states, size + 1);
    g_trade_states[size].ticket = ticket;
    g_trade_states[size].partial_taken = false;
    g_trade_states[size].last_tp_update_bar = 0;
}

void RemoveTradeState(ulong ticket)
{
    int idx = GetTradeStateIndex(ticket);
    if(idx < 0) return; // Not found
    
    // Remove by swapping with last element
    int last = ArraySize(g_trade_states) - 1;
    if(idx < last)
    {
        g_trade_states[idx] = g_trade_states[last];
    }
    ArrayResize(g_trade_states, last);
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
    
    // WEEKEND GAP PROTECTION: Close or tighten stops before weekend
    if(InpWeekendGapProtection)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        
        // Friday after market hours or Sunday (adjust for your broker timezone)
        // Typical: Friday 20:00+ or Saturday/Sunday
        if((dt.day_of_week == 5 && dt.hour >= 20) || dt.day_of_week == 0 || dt.day_of_week == 6)
        {
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
                if(!g_pos.SelectByIndex(j)) continue;
                if(g_pos.Symbol() != g_active_symbol || g_pos.Magic() != InpMagicNumber) continue;
                
                ulong w_ticket = g_pos.Ticket();
                double w_current = (g_pos.PositionType() == POSITION_TYPE_BUY) ?
                                  SymbolInfoDouble(g_active_symbol, SYMBOL_BID) :
                                  SymbolInfoDouble(g_active_symbol, SYMBOL_ASK);
                double w_sl = g_pos.StopLoss();
                double w_entry = g_pos.PriceOpen();
                
                // Tighten stop to breakeven + small buffer or close if profitable
                double w_profit = g_pos.Profit();
                if(w_profit > 0)
                {
                    // Close profitable trades before weekend
                    g_trade.PositionClose(w_ticket);
                    Print("Weekend protection: Closed profitable position ", w_ticket);
                    RemoveTradeState(w_ticket);
                }
                else if(w_sl == 0 || (g_pos.PositionType() == POSITION_TYPE_BUY && w_sl < w_entry) ||
                        (g_pos.PositionType() == POSITION_TYPE_SELL && w_sl > w_entry))
                {
                    // Move to breakeven + small buffer
                    double w_point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
                    double w_new_sl = w_entry;
                    if(g_pos.PositionType() == POSITION_TYPE_BUY)
                        w_new_sl = w_entry - (w_point * 5); // 5 points below entry
                    else
                        w_new_sl = w_entry + (w_point * 5); // 5 points above entry
                    
                    g_trade.PositionModify(w_ticket, w_new_sl, g_pos.TakeProfit());
                    Print("Weekend protection: Moved stop to breakeven for position ", w_ticket);
                }
            }
            return; // Exit after weekend protection
        }
    }
    
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
            RemoveTradeState(ticket);
            continue; // Move to next position
        }
        
        // Get or create trade state
        int state_idx = GetTradeStateIndex(ticket);
        if(state_idx < 0)
        {
            AddTradeState(ticket);
            state_idx = GetTradeStateIndex(ticket);
        }
        
        // PARTIAL PROFIT TAKING - Close 50% at TP1
        if(InpUsePartialTP && !g_trade_states[state_idx].partial_taken)
        {
            double profit_points = 0;
            if(type == POSITION_TYPE_BUY)
                profit_points = (current_price - open_price) / point;
            else
                profit_points = (open_price - current_price) / point;
            
            double tp1_atr_points = atr_points * InpPartialTP_ATR;
            if(profit_points >= tp1_atr_points)
            {
                double current_volume = g_pos.Volume();
                double partial_volume = NormalizeDouble(current_volume / 2.0, 2);
                
                // Ensure partial volume is valid
                double min_lot = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_MIN);
                double lot_step = SymbolInfoDouble(g_active_symbol, SYMBOL_VOLUME_STEP);
                partial_volume = MathFloor(partial_volume / lot_step) * lot_step;
                partial_volume = MathMax(min_lot, partial_volume);
                
                if(partial_volume < current_volume && current_volume - partial_volume >= min_lot)
                {
                    if(g_trade.PositionClosePartial(ticket, partial_volume))
                    {
                        g_trade_states[state_idx].partial_taken = true;
                        Print("Partial TP taken: Closed ", partial_volume, " lots at TP1 (", InpPartialTP_ATR, "x ATR)");
                        LogTrade("PARTIAL_TP", current_price, sl, tp, partial_volume, 
                                StringFormat("TP1 @ %.1fx ATR", InpPartialTP_ATR));
                    }
                }
            }
        }
        
        // DYNAMIC TP UPDATE - Recalculate S/R-based TP during trade
        if(InpDynamicTP_Update && InpUseDynamicTP)
        {
            datetime current_bar_time = 0;
            datetime bar_times[];
            ArraySetAsSeries(bar_times, true);
            ArrayResize(bar_times, 1);
            if(CopyTime(g_active_symbol, InpTimeframe, 0, 1, bar_times) > 0)
                current_bar_time = bar_times[0];
            
            bool should_update = false;
            if(g_trade_states[state_idx].last_tp_update_bar == 0)
                should_update = true; // First update
            else if(current_bar_time > 0 && g_trade_states[state_idx].last_tp_update_bar > 0)
            {
                // Check if N bars have passed
                int bars_passed = iBars(g_active_symbol, InpTimeframe) - 
                                 iBarShift(g_active_symbol, InpTimeframe, g_trade_states[state_idx].last_tp_update_bar);
                if(bars_passed >= InpTP_UpdateBars)
                    should_update = true;
            }
            
            if(should_update)
            {
                double new_tp = CalculateDynamicTP(type, open_price);
                if(new_tp > 0)
                {
                    // Validate new TP is better than current
                    bool tp_improved = false;
                    if(type == POSITION_TYPE_BUY)
                    {
                        // New TP should be higher and reasonable
                        if(new_tp > tp && new_tp > current_price + (point * 10) && 
                           new_tp < current_price + (point * 500))
                            tp_improved = true;
                    }
                    else
                    {
                        // New TP should be lower and reasonable
                        if((tp == 0 || new_tp < tp) && new_tp < current_price - (point * 10) &&
                           new_tp > current_price - (point * 500))
                            tp_improved = true;
                    }
                    
                    if(tp_improved && g_trade.PositionModify(ticket, sl, new_tp))
                    {
                        g_trade_states[state_idx].last_tp_update_bar = current_bar_time;
                        Print("Dynamic TP updated: ", ticket, " new TP=", new_tp);
                    }
                }
                else if(current_bar_time > 0)
                {
                    g_trade_states[state_idx].last_tp_update_bar = current_bar_time; // Update timestamp even if no new TP
                }
            }
        }
        
        // Time-based exit
        if(InpMaxTradeLifeMin > 0)
        {
            long time_diff = (long)(TimeCurrent() - open_time);
            int minutes_open = (int)(time_diff / 60);
            if(minutes_open >= InpMaxTradeLifeMin)
            {
                g_trade.PositionClose(ticket);
                RemoveTradeState(ticket);
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
    g_trade.SetDeviationInPoints((int)PipsToPoints(GetAdaptiveSlippagePips()));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Buy(lots, g_active_symbol, ask, sl, tp, "EURUSDm Long"))
    {
        ulong ticket = g_trade.ResultOrder();
        if(ticket > 0)
        {
            // Find the position ticket (deal creates position)
            Sleep(100); // Brief delay for position to be created
            if(g_pos.SelectByTicket(ticket) || g_pos.SelectByIndex(PositionsTotal() - 1))
            {
                AddTradeState(g_pos.Ticket());
            }
        }
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
    g_trade.SetDeviationInPoints((int)PipsToPoints(GetAdaptiveSlippagePips()));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Sell(lots, g_active_symbol, bid, sl, tp, "EURUSDm Short"))
    {
        ulong ticket = g_trade.ResultOrder();
        if(ticket > 0)
        {
            // Find the position ticket (deal creates position)
            Sleep(100); // Brief delay for position to be created
            if(g_pos.SelectByTicket(ticket) || g_pos.SelectByIndex(PositionsTotal() - 1))
            {
                AddTradeState(g_pos.Ticket());
            }
        }
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
    
    // EQUITY DRAWDOWN CHECK (live protection)
    if(!CheckEquityDrawdown())
    {
        Print("Trading stopped: Equity drawdown limit reached!");
        return;
    }
    
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
    
    // BROKER COMPATIBILITY CHECK
    if(!CheckBrokerCompatibility())
    {
        Print("WARNING: Broker compatibility issues detected. Continuing with caution...");
    }
    
    // Initialize equity tracking
    g_max_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_daily_balance_start = g_start_balance;
    
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
