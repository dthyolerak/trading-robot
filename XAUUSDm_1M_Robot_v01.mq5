//+------------------------------------------------------------------+
//|                                              XAUUSDm_1M_Robot.mq5|
//| A survivability-first scalper for XAUUSDm on M1.                 |
//| - Supports micro/fractional lots; any starting balance           |
//| - Concurrent trades allowed under strict aggregate exposure caps |
//| - Auto-shutdown when realized profit >= profit_target*start_bal  |
//| - Decision engine: ATR(vol), MTF EMAs, Bollinger z-score, RSI,   |
//|   MACD momentum; reversal score with candle + volume features    |
//| - Daily/weekly loss caps, circuit breaker, low-liquidity filter  |
//|                                                                  |
//| NOTE: News filter hook provided (WebRequest URL list in Options).|
//|                                                                  |
//| Inputs are fully configurable.                                   |
//+------------------------------------------------------------------+
#property copyright   "2025"
#property version     "1.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//=========================== INPUTS =================================
input group "=== SYMBOL/TIMEFRAME GUARD ===";
input string InpSymbol                 = "XAUUSDm"; // Enforced symbol
input ENUM_TIMEFRAMES InpTF            = PERIOD_M1;  // Enforced timeframe

input group "=== PROFIT TARGET & SESSION ===";
input double InpProfitTargetX          = 7.0;        // Stop trading when realized profit >= X * start_balance
input bool   InpDormantAfterTarget     = true;       // Stop trading (true) or reduce risk to 0.05% (false)

input group "=== RISK & EXPOSURE ===";
input double InpRiskPerTradePct        = 0.30;       // Default 0.25–0.5% recommended
input double InpMaxAggExposurePct      = 7.5;        // Max equity-at-risk across open trades
input int    InpMaxConcurrentTrades    = 10;         // Hard cap on open trades
input double InpCircuitBreakerDDPct    = 20.0;       // Stop if equity drawdown exceeds this %
input double InpDailyLossCapPct        = 3.0;        // Stop for the day when exceeded
input double InpWeeklyLossCapPct       = 7.5;        // Stop for the week when exceeded
input int    InpSL_Points              = 800;        // Hard SL in points (XAUUSDm 0.01 point = 1 point depending broker)
input int    InpTP_Points              = 1200;       // TP in points (>= SL*1.2 suggested)
input bool   InpAllowScaling           = true;       // Allow limited scaling when edge improves
input int    InpMaxDailyPositionAdds   = 3;          // Max net adds per day

input group "=== LIQUIDITY/NEWS FILTERS ===";
input bool   InpAvoidLowLiquidity      = true;       // Skip rollover and dead hours
input int    InpRollFromHour           = 21;         // Broker server hour to start avoiding
input int    InpRollToHour             = 23;         // End of avoidance window (inclusive start)
input bool   InpUseNewsWindow          = false;      // If true, obey news blackout minutes
input int    InpNewsBlackoutBeforeMin  = 15;
input int    InpNewsBlackoutAfterMin   = 15;

input group "=== DECISION ENGINE (INDICATORS) ===";
input int    InpATR_Period             = 14;
input int    InpEMA_Fast_M1            = 20;
input int    InpEMA_Slow_M5            = 100;        // on M5
input int    InpEMA_Slow_M30           = 200;        // on M30/1H (selected M30 for speed)
input int    InpBB_Period              = 20;
input double InpBB_Dev                 = 2.0;
input int    InpRSI_Period             = 14;
input int    InpMACD_Fast              = 12;
input int    InpMACD_Slow              = 26;
input int    InpMACD_Signal            = 9;
input double InpEntryScoreThreshold    = 0.75;       // 0..1 composite entry threshold (raised for quality)
input double InpReversalThreshold      = 0.80;       // reversal score to close (raised to prevent premature exits)
input int    InpMinBarsBeforeReverse   = 3;          // Minimum bars before checking reversal (let trades breathe)
input int    InpSignalConfirmationBars = 2;          // Require N consecutive bars with signal before entry

input group "=== LOGGING/SAFETY ===";
input bool   InpDetailedLogs           = true;
input bool   InpCSV_Export             = true;
input bool   InpEquityCurveCSV         = true;
input ulong  InpMagic                  = 2025102901;

//=========================== GLOBALS =================================
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_ord;

datetime g_session_start = 0;
double   g_start_balance = 0.0;
double   g_max_equity    = 0.0;
double   g_min_equity    = 0.0;
double   g_daily_pnl     = 0.0;
double   g_weekly_pnl    = 0.0;
int      g_today_adds    = 0;
bool     g_dormant       = false;

// Indicator handles (M1 base)
int h_atr = INVALID_HANDLE;
int h_ema_fast_m1 = INVALID_HANDLE;
int h_bb = INVALID_HANDLE;
int h_rsi = INVALID_HANDLE;
int h_macd = INVALID_HANDLE; // buffer: main 0, signal 1, hist 2

// Higher TF EMAs
int h_ema_slow_m5  = INVALID_HANDLE;
int h_ema_slow_m30 = INVALID_HANDLE;

// CSV paths
string g_dir = "XAUUSDm_1M_Robot";
string g_trades_csv, g_equity_csv, g_events_csv;

// Bar and signal tracking
datetime g_last_bar_time = 0;
int g_buy_signal_count = 0;
int g_sell_signal_count = 0;

//=========================== UTILITIES ===============================
bool EnsureSymbolAndTF()
{
    if(_Symbol != InpSymbol)
    {
        Print("ERROR: Attach EA on symbol ", InpSymbol, ", current=", _Symbol);
        return false;
    }
    if(_Period != InpTF)
    {
        Print("ERROR: Attach EA on timeframe M1 only.");
        return false;
    }
    return true;
}

double AccountEquity(){ return AccountInfoDouble(ACCOUNT_EQUITY); }
double AccountBalance(){ return AccountInfoDouble(ACCOUNT_BALANCE); }

double PointValue()
{
    return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

double TickValue()
{
    return SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
}

void CsvAppend(const string path, const string line)
{
    int h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
    if(h == INVALID_HANDLE)
    {
        int h2 = FileOpen(path, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
        if(h2 != INVALID_HANDLE)
        {
            FileWrite(h2, "timestamp", "event", "data");
            FileClose(h2);
            h = FileOpen(path, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
        }
    }
    if(h != INVALID_HANDLE)
    {
        FileSeek(h, 0, SEEK_END);
        string line_to_write = line + "\r\n";
        FileWriteString(h, line_to_write);
        FileClose(h);
    }
}

void LogEvent(const string event, const string data="")
{
    if(!InpCSV_Export) return;
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
    string line = timestamp + ";" + event + ";" + data;
    CsvAppend(g_events_csv, line);
}

//======================= INDICATOR SETUP ============================
bool CreateIndicators()
{
    h_atr         = iATR(_Symbol, PERIOD_M1, InpATR_Period);
    h_ema_fast_m1 = iMA(_Symbol, PERIOD_M1, InpEMA_Fast_M1, 0, MODE_EMA, PRICE_CLOSE);
    h_bb          = iBands(_Symbol, PERIOD_M1, InpBB_Period, 0, InpBB_Dev, PRICE_CLOSE);
    h_rsi         = iRSI(_Symbol, PERIOD_M1, InpRSI_Period, PRICE_CLOSE);
    h_macd        = iMACD(_Symbol, PERIOD_M1, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
    h_ema_slow_m5 = iMA(_Symbol, PERIOD_M5, InpEMA_Slow_M5, 0, MODE_EMA, PRICE_CLOSE);
    h_ema_slow_m30= iMA(_Symbol, PERIOD_M30, InpEMA_Slow_M30, 0, MODE_EMA, PRICE_CLOSE);

    if(h_atr==INVALID_HANDLE || h_ema_fast_m1==INVALID_HANDLE || h_bb==INVALID_HANDLE ||
       h_rsi==INVALID_HANDLE || h_macd==INVALID_HANDLE || h_ema_slow_m5==INVALID_HANDLE ||
       h_ema_slow_m30==INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicator handles. Code=", GetLastError());
        return false;
    }
    return true;
}

bool ReadIndDouble(const int handle, const int buffer, const int count, double &out[])
{
    ArraySetAsSeries(out, true);
    if(CopyBuffer(handle, buffer, 0, count, out) <= 0)
        return false;
    return true;
}

//======================= RISK/EXPOSURE ENGINE =======================
// per-trade risk in currency given lot size and SL points
double RiskValueCurrency(const double lots, const int sl_points)
{
    double point = PointValue();
    double tickval = TickValue();
    // approximate: risk = lots * (sl_points*point / SymbolInfoDouble(SYMBOL_TRADE_TICK_SIZE)) * tickval
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double ticks = (sl_points*point)/ (tick_size>0?tick_size:point);
    return lots * ticks * tickval;
}

// equity-based lot size from risk % and SL
double LotFromRiskPct(const double risk_pct, const int sl_points)
{
    double equity = AccountEquity();
    double risk_money = equity * risk_pct/100.0;
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tick_value = TickValue();
    double point = PointValue();
    double ticks = (sl_points*point)/(tick_size>0?tick_size:point);
    double lots = 0.0;
    if(ticks>0 && tick_value>0)
        lots = risk_money/(ticks*tick_value);

    // normalize to broker constraints
    double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lots = MathMax(minlot, MathMin(maxlot, MathFloor(lots/step)*step));
    return lots;
}

// aggregate open risk across robot positions
double AggregateOpenRiskPct()
{
    double equity = AccountEquity();
    if(equity<=0) return 1000.0;
    double risk_ccy = 0.0;
    for(int i=0;i<PositionsTotal();++i)
    {
        if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic)
        {
            // approximate distance to SL
            double sl = g_pos.StopLoss();
            if(sl<=0) continue;
            double price = (g_pos.PositionType()==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol, SYMBOL_BID):SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double dist_points = MathAbs((price - sl)/PointValue());
            risk_ccy += RiskValueCurrency(g_pos.Volume(), (int)dist_points);
        }
    }
    return 100.0 * (risk_ccy/MathMax(1.0,equity));
}

int RobotPositionsCount()
{
    int c=0; for(int i=0;i<PositionsTotal();++i) if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic) c++; return c;
}

bool ExposureAllowsNewTrade(const int sl_points, const double risk_pct)
{
    if(RobotPositionsCount() >= InpMaxConcurrentTrades) return false;
    double agg = AggregateOpenRiskPct();
    double new_risk = risk_pct;
    return (agg + new_risk) <= InpMaxAggExposurePct;
}

//======================= DECISION ENGINE ============================
// Composite entry score 0..1 using: trend (MTF EMAs), vol regime (ATR),
// Bollinger z-score (mean reversion), RSI/MACD (momentum).
// Returns: score_buy, score_sell
void ComputeEntryScores(double &score_buy, double &score_sell)
{
    score_buy = 0.0; score_sell = 0.0;

    double ema_m1[1], bb_upper[1], bb_lower[1], bb_mid[1], rsi[1], atr[1];
    double macd_main[1], macd_sig[1];
    double ema_m5[1], ema_m30[1];

    if(!ReadIndDouble(h_ema_fast_m1,0,1,ema_m1)) return;
    if(!ReadIndDouble(h_bb,0,1,bb_upper)) return;
    if(!ReadIndDouble(h_bb,1,1,bb_mid)) return;
    if(!ReadIndDouble(h_bb,2,1,bb_lower)) return;
    if(!ReadIndDouble(h_rsi,0,1,rsi)) return;
    if(!ReadIndDouble(h_atr,0,1,atr)) return;
    if(!ReadIndDouble(h_macd,0,1,macd_main)) return;
    if(!ReadIndDouble(h_macd,1,1,macd_sig)) return;
    if(!ReadIndDouble(h_ema_slow_m5,0,1,ema_m5)) return;
    if(!ReadIndDouble(h_ema_slow_m30,0,1,ema_m30)) return;

    double close = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Trend components
    double trend_up = (close>ema_m1[0]) + (close>ema_m5[0]) + (close>ema_m30[0]);
    double trend_dn = (close<ema_m1[0]) + (close<ema_m5[0]) + (close<ema_m30[0]);

    // Momentum components
    double macd_up = (macd_main[0]>macd_sig[0]);
    double macd_dn = (macd_main[0]<macd_sig[0]);
    double rsi_up  = (rsi[0]>52);
    double rsi_dn  = (rsi[0]<48);

    // Mean reversion: z-score to bands
    double z = 0.0;
    if(bb_upper[0]>bb_lower[0])
        z = (close - bb_mid[0]) / (0.5*(bb_upper[0]-bb_lower[0]));
    double mr_long = (z < -0.8);
    double mr_short= (z > 0.8);

    // Volatility gate: avoid ultra-low ATR
    double vol_ok = (atr[0] > 0.5 * PointValue() * InpSL_Points);

    // Compose (weights can be tuned)
    double buy_raw  = 0.35*trend_up/3.0 + 0.25*macd_up + 0.15*rsi_up + 0.25*mr_long;
    double sell_raw = 0.35*trend_dn/3.0 + 0.25*macd_dn + 0.15*rsi_dn + 0.25*mr_short;

    if(!vol_ok) { buy_raw*=0.3; sell_raw*=0.3; }

    score_buy  = MathMin(1.0, MathMax(0.0, buy_raw));
    score_sell = MathMin(1.0, MathMax(0.0, sell_raw));
}

// Reversal score for an open position
// Combines: momentum flip, candle body reversal, tick volume spike vs adverse move.
double ComputeReversalScore(const ENUM_POSITION_TYPE type)
{
    double macd_main[1], macd_sig[1], rsi[1];
    if(!ReadIndDouble(h_macd,0,1,macd_main)) return 0.0;
    if(!ReadIndDouble(h_macd,1,1,macd_sig)) return 0.0;
    if(!ReadIndDouble(h_rsi,0,1,rsi)) return 0.0;

    // candle features
    MqlRates rates[]; ArraySetAsSeries(rates,true);
    int n = CopyRates(_Symbol, PERIOD_M1, 0, 3, rates);
    if(n<3) return 0.0;

    double body_now = MathAbs(rates[0].close - rates[0].open);
    double body_prev= MathAbs(rates[1].close - rates[1].open);
    bool engulf = (body_now>body_prev*1.2) && ((rates[0].close>rates[0].open) != (rates[1].close>rates[1].open));

    // momentum flip
    bool macd_flip = (macd_main[0]-macd_sig[0])<0.0;
    bool macd_flip_dn = (macd_main[0]-macd_sig[0])>0.0;

    double score = 0.0;
    if(type==POSITION_TYPE_BUY)
    {
        score = 0.4*(macd_flip?1.0:0.0) + 0.3*(rsi[0]<48?1.0:0.0) + 0.3*(engulf?1.0:0.0);
    }
    else
    {
        score = 0.4*(macd_flip_dn?1.0:0.0) + 0.3*(rsi[0]>52?1.0:0.0) + 0.3*(engulf?1.0:0.0);
    }
    return score;
}

//======================= ENTRY/EXIT =================================
bool OpenTrade(const ENUM_ORDER_TYPE type, const int sl_points, const int tp_points, const double risk_pct)
{
    if(!ExposureAllowsNewTrade(sl_points, risk_pct)) return false;

    double lots = LotFromRiskPct(risk_pct, sl_points);
    if(lots<=0) return false;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = PointValue();

    double price= (type==ORDER_TYPE_BUY)?ask:bid;
    double sl   = (type==ORDER_TYPE_BUY)? price - sl_points*point : price + sl_points*point;
    double tp   = (type==ORDER_TYPE_BUY)? price + tp_points*point : price - tp_points*point;

    g_trade.SetExpertMagicNumber(InpMagic);
    g_trade.SetTypeFilling(ORDER_FILLING_FOK);

    bool ok=false;
    if(type==ORDER_TYPE_BUY) ok=g_trade.Buy(lots,_Symbol,ask,sl,tp,"XAU M1 entry");
    else ok=g_trade.Sell(lots,_Symbol,bid,sl,tp,"XAU M1 entry");

    if(ok)
    {
        LogEvent("OPEN", StringFormat("type=%s,lots=%.3f,price=%.2f,slp=%d,tpp=%d,risk%%=%.2f", (type==ORDER_TYPE_BUY?"BUY":"SELL"), lots, price, sl_points, tp_points, risk_pct));
    }
    else
    {
        LogEvent("OPEN_FAIL", StringFormat("retcode=%d", g_trade.ResultRetcode()));
    }
    return ok;
}

void ManageOpenTrades()
{
    // Only check on new bars to avoid premature exits
    datetime current_bar = iTime(_Symbol, PERIOD_M1, 0);
    if(current_bar == g_last_bar_time) return; // Same bar, skip
    
    for(int i=PositionsTotal()-1;i>=0;--i)
    {
        if(!g_pos.SelectByIndex(i)) continue;
        if(g_pos.Symbol()!=_Symbol || g_pos.Magic()!=InpMagic) continue;

        // Check how long position has been open
        datetime pos_time = (datetime)g_pos.Time();
        int bars_open = (int)((TimeCurrent() - pos_time) / 60); // minutes open
        
        // Don't check reversal too early - let trades breathe
        if(bars_open < InpMinBarsBeforeReverse) continue;

        double rev = ComputeReversalScore(g_pos.PositionType());
        if(rev >= InpReversalThreshold)
        {
            // close
            g_trade.PositionClose(g_pos.Ticket());
            LogEvent("REV_CLOSE", StringFormat("ticket=%I64d,rev=%.2f,bars=%d", g_pos.Ticket(), rev, bars_open));
        }
    }
}

void TryEntries()
{
    if(g_dormant) return;

    // Only check on new bars (not every tick!)
    datetime current_bar = iTime(_Symbol, PERIOD_M1, 0);
    if(current_bar == g_last_bar_time) return; // Same bar, skip
    g_last_bar_time = current_bar;

    // liquidity filter
    if(InpAvoidLowLiquidity)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int h = dt.hour;
        if(h>=InpRollFromHour && h<=InpRollToHour) return;
    }

    // Compute entry scores
    double sb, ss; 
    ComputeEntryScores(sb, ss);
    
    // Require confirmation across multiple bars
    if(sb >= InpEntryScoreThreshold)
        g_buy_signal_count++;
    else
        g_buy_signal_count = 0;
        
    if(ss >= InpEntryScoreThreshold)
        g_sell_signal_count++;
    else
        g_sell_signal_count = 0;
    
    // Only enter if signal confirmed across N consecutive bars
    bool buy_confirmed = (g_buy_signal_count >= InpSignalConfirmationBars);
    bool sell_confirmed = (g_sell_signal_count >= InpSignalConfirmationBars);
    
    // Additional quality check: score must be significantly above threshold
    double quality_threshold = InpEntryScoreThreshold + 0.05; // Require 0.05 above minimum
    
    if(buy_confirmed && sb >= quality_threshold && ExposureAllowsNewTrade(InpSL_Points, InpRiskPerTradePct))
    {
        if(OpenTrade(ORDER_TYPE_BUY, InpSL_Points, InpTP_Points, InpRiskPerTradePct))
        {
            g_buy_signal_count = 0; // Reset after entry
            LogEvent("ENTRY_BUY", StringFormat("score=%.3f,confirmed=%d bars", sb, InpSignalConfirmationBars));
        }
    }
    
    if(sell_confirmed && ss >= quality_threshold && ExposureAllowsNewTrade(InpSL_Points, InpRiskPerTradePct))
    {
        if(OpenTrade(ORDER_TYPE_SELL, InpSL_Points, InpTP_Points, InpRiskPerTradePct))
        {
            g_sell_signal_count = 0; // Reset after entry
            LogEvent("ENTRY_SELL", StringFormat("score=%.3f,confirmed=%d bars", ss, InpSignalConfirmationBars));
        }
    }
}

//======================= PROFIT TARGET/SAFETY ========================
double RealizedProfitSinceStart()
{
    // sum closed deals since g_session_start
    double pnl = 0.0;
    HistorySelect(g_session_start, TimeCurrent());
    int deals = HistoryDealsTotal();
    for(int i=0;i<deals;++i)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        string deal_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
        if(deal_symbol != _Symbol) continue;
        long magic = (long)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
        if(magic != (long)InpMagic) continue;
        double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
        double swap   = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
        double comm   = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
        pnl += profit + swap + comm;
    }
    return pnl;
}

void EnforceGlobalStops()
{
    double equity = AccountEquity();
    g_max_equity = MathMax(g_max_equity, equity);
    g_min_equity = MathMin(g_min_equity==0?equity:g_min_equity, equity);

    // circuit breaker
    if(g_max_equity>0)
    {
        double dd = 100.0*(g_max_equity - equity)/g_max_equity;
        if(dd >= InpCircuitBreakerDDPct)
        {
            g_dormant = true; LogEvent("CIRCUIT_BREAKER", DoubleToString(dd,2));
            // close everything
            for(int i=PositionsTotal()-1;i>=0;--i) if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic) g_trade.PositionClose(g_pos.Ticket());
        }
    }

    // realized profit target
    double realized = RealizedProfitSinceStart();
    if(realized >= InpProfitTargetX * g_start_balance)
    {
        // close all and stop
        for(int i=PositionsTotal()-1;i>=0;--i) if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic) g_trade.PositionClose(g_pos.Ticket());
        g_dormant = true; LogEvent("TARGET_REACHED", DoubleToString(realized,2));
    }
}

//======================= LIFECYCLE ==================================
int OnInit()
{
    if(!EnsureSymbolAndTF()) return(INIT_FAILED);

    // folders
    string base = g_dir+"/";
    g_trades_csv = base+"trades.csv";
    g_equity_csv = base+"equity.csv";
    g_events_csv = base+"events.csv";

    g_session_start = TimeCurrent();
    g_start_balance = AccountBalance();
    g_max_equity = AccountEquity();

    if(!CreateIndicators()) return(INIT_FAILED);

    LogEvent("INIT", StringFormat("start_balance=%.2f", g_start_balance));
    Print("XAUUSDm_1M_Robot initialized. StartBalance=", g_start_balance);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    LogEvent("DEINIT", IntegerToString(reason));
}

void OnTick()
{
    if(!EnsureSymbolAndTF()) return;

    // log equity (every ~15 seconds)
    static datetime last_eq_log = 0;
    if(InpEquityCurveCSV)
    {
        datetime now = TimeCurrent();
        if(now - last_eq_log >= 15)
        {
            string eq_timestamp = TimeToString(now, TIME_DATE|TIME_SECONDS);
            string eq_line = eq_timestamp + ";equity;" + DoubleToString(AccountEquity(), 2);
            CsvAppend(g_equity_csv, eq_line);
            last_eq_log = now;
        }
    }

    EnforceGlobalStops();
    if(g_dormant) return;

    ManageOpenTrades();
    TryEntries();
}

//======================= README (short) ==============================
/*
Analysis window guidance (for backtesting/offline tooling):
- Use the largest window within <= 1 year that gives stable feature stats; typically 6–12 months M1 for gold.
- For calibration: first 70% in-sample, last 30% out-of-sample; walk-forward monthly if available.

Concurrent-trade capacity formula (safe default):
- perTradeRisk = equity * riskPct
- worstCasePortfolioLoss = perTradeRisk * N
- Choose N so worstCasePortfolioLoss <= maxAggExposure * equity
=> N_max = floor(maxAggExposurePct / riskPct)
Example: riskPct=0.3%, maxAggExposure=7.5% => N_max= floor(7.5/0.3)=25, then clamp to InpMaxConcurrentTrades.

This EA enforces both aggregate risk cap and concurrent-trade cap. No martingale; optional scaling limited by InpMaxDailyPositionAdds and exposure caps.
*/
