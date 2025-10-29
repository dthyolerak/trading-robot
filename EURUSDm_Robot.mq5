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
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;    // Primary timeframe

input group "=== EMA CROSSOVER STRATEGY ===";
input int      InpEMA_Fast         = 9;             // Fast EMA period
input int      InpEMA_Slow         = 21;            // Slow EMA period
input int      InpRSI_Period       = 14;            // RSI period
input double   InpRSI_LongMin      = 45.0;          // RSI minimum for long entry
input double   InpRSI_ShortMax     = 55.0;          // RSI maximum for short entry

input group "=== ATR-BASED EXIT RULES ===";
input int      InpATR_Period       = 14;            // ATR period
input double   InpSL_Multiplier    = 2.0;           // SL = ATR * multiplier
input double   InpTP_Multiplier    = 3.0;           // TP = ATR * multiplier
input bool     InpUseTrailing      = true;          // Enable trailing stop
input double   InpTrailStart       = 2.0;           // Start trailing after (ATR multiples)
input double   InpTrailStep        = 10.0;          // Trailing stop step (pips)
input bool     InpUseBreakEven     = true;          // Move to breakeven after trigger
input double   InpBE_TriggerATR    = 1.5;           // BE trigger (ATR multiples)
input int      InpMaxTradeLifeMin  = 0;             // Max trade duration (0=unlimited)

input group "=== RISK MANAGEMENT ===";
input double   InpRiskPercent      = 1.0;           // Risk % per trade
input double   InpFixedLotSize     = 0.0;           // Fixed lot size (0=use risk%)
input int      InpMaxOpenTrades    = 1;             // Maximum concurrent trades
input double   InpDailyLossLimit   = 5.0;           // Daily loss limit (%)
input double   InpMaxSpread        = 2.5;           // Maximum spread (pips)
input double   InpMaxSlippage      = 3.0;           // Maximum slippage (pips)

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

// Session tracking
datetime       g_session_start = 0;
double         g_start_balance = 0.0;
double         g_daily_balance_start = 0.0;
double         g_last_bar_time = 0;

// Symbol detection
string         g_active_symbol = "";

// Logging
string         g_log_file = "";

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
    
    double ema_f[1], ema_s[1], rsi[1], atr[1];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    
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
    
    if(h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE ||
       h_rsi == INVALID_HANDLE || h_atr == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators. Error: ", GetLastError());
        return false;
    }
    
    // Wait for indicators to calculate
    Sleep(1000);
    return true;
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
    double ema_f[2], ema_s[2], rsi[1], atr[1];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    
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
    
    // RSI filter
    bool rsi_ok = (rsi[0] > InpRSI_LongMin);
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    return (crossover || (price_above && ema_f[0] > ema_s[0])) && rsi_ok && vol_ok;
}

bool CheckShortEntry()
{
    double ema_f[2], ema_s[2], rsi[1], atr[1];
    ArraySetAsSeries(ema_f, true);
    ArraySetAsSeries(ema_s, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(atr, true);
    
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
    
    // RSI filter
    bool rsi_ok = (rsi[0] < InpRSI_ShortMax);
    
    // Volatility filter
    bool vol_ok = true;
    if(InpVolatilityFilter)
    {
        vol_ok = (atr[0] >= InpATR_MinThreshold && atr[0] <= InpATR_MaxThreshold);
    }
    
    return (crossover || (price_below && ema_f[0] < ema_s[0])) && rsi_ok && vol_ok;
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

//=========================== EXIT LOGIC ============================
void ManageExits()
{
    double atr[1];
    ArraySetAsSeries(atr, true);
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
        
        // Time-based exit
        if(InpMaxTradeLifeMin > 0)
        {
            int minutes_open = (int)((TimeCurrent() - open_time) / 60);
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
void TryEnterLong()
{
    if(CountOpenTrades() >= InpMaxOpenTrades) return;
    
    double atr[1];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return;
    
    double ask = SymbolInfoDouble(g_active_symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    double sl_distance = atr[0] * InpSL_Multiplier;
    double tp_distance = atr[0] * InpTP_Multiplier;
    
    double sl = ask - sl_distance;
    double tp = ask + tp_distance;
    
    // Check minimum stop level
    double min_stop = SymbolInfoInteger(g_active_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    if(MathAbs(ask - sl) < min_stop) sl = ask - min_stop - point;
    if(MathAbs(tp - ask) < min_stop) tp = ask + min_stop + point;
    
    double lots = CalculateLotSize(sl_distance / point);
    if(lots <= 0) return;
    
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints((int)PipsToPoints(InpMaxSlippage));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Buy(lots, g_active_symbol, ask, sl, tp, "EURUSDm Long"))
    {
        Print("LONG entry: ", lots, " lots @ ", ask, " SL=", sl, " TP=", tp);
        LogTrade("LONG", ask, sl, tp, lots, "EMA crossover + RSI");
    }
    else
    {
        Print("LONG entry failed: ", g_trade.ResultRetcode());
    }
}

void TryEnterShort()
{
    if(CountOpenTrades() >= InpMaxOpenTrades) return;
    
    double atr[1];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(h_atr, 0, 0, 1, atr) < 1) return;
    
    double bid = SymbolInfoDouble(g_active_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(g_active_symbol, SYMBOL_POINT);
    double sl_distance = atr[0] * InpSL_Multiplier;
    double tp_distance = atr[0] * InpTP_Multiplier;
    
    double sl = bid + sl_distance;
    double tp = bid - tp_distance;
    
    // Check minimum stop level
    double min_stop = SymbolInfoInteger(g_active_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
    if(MathAbs(sl - bid) < min_stop) sl = bid + min_stop + point;
    if(MathAbs(bid - tp) < min_stop) tp = bid - min_stop - point;
    
    double lots = CalculateLotSize(sl_distance / point);
    if(lots <= 0) return;
    
    g_trade.SetExpertMagicNumber(InpMagicNumber);
    g_trade.SetDeviationInPoints((int)PipsToPoints(InpMaxSlippage));
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    if(g_trade.Sell(lots, g_active_symbol, bid, sl, tp, "EURUSDm Short"))
    {
        Print("SHORT entry: ", lots, " lots @ ", bid, " SL=", sl, " TP=", tp);
        LogTrade("SHORT", bid, sl, tp, lots, "EMA crossover + RSI");
    }
    else
    {
        Print("SHORT entry failed: ", g_trade.ResultRetcode());
    }
}

//=========================== MAIN LOGIC ============================
void OnTick()
{
    // Process only on new bar
    datetime current_bar[];
    ArraySetAsSeries(current_bar, true);
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
    
    // Check for new entries
    if(CheckLongEntry())
    {
        TryEnterLong();
    }
    else if(CheckShortEntry())
    {
        TryEnterShort();
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
    Print("EURUSDm Robot Initialized");
    Print("Symbol: ", g_active_symbol);
    Print("Timeframe: ", EnumToString(InpTimeframe));
    Print("Magic Number: ", InpMagicNumber);
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
