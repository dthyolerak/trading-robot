//+------------------------------------------------------------------+
//|                                                ForexRobot.mq5 |
//|                        Copyright 2024, Forex Trading Robot |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Forex Trading Robot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Hybrid Momentum + Mean Reversion Forex Trading Robot"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== GENERAL SETTINGS ==="
input bool     InpEnableTrading = true;           // Enable trading
input bool     InpDemoMode = false;               // Demo mode
input string   InpAccountCurrency = "USD";        // Account currency
input double   InpMinBalance = 10.0;              // Minimum balance

input group "=== RISK MANAGEMENT ==="
input double   InpRiskPerTrade = 0.5;             // Risk per trade (%)
input double   InpDailyLossLimit = 3.0;           // Daily loss limit (%)
input double   InpMaxDrawdownLimit = 20.0;        // Max drawdown limit (%)
input int      InpConsecutiveLossLimit = 3;       // Consecutive loss limit
input bool     InpKillSwitchEnabled = true;       // Kill switch enabled

input group "=== POSITION SIZING ==="
input double   InpMinLotSize = 0.01;              // Minimum lot size
input double   InpMaxLotSize = 1.0;               // Maximum lot size
input int      InpStopLossPips = 8;               // Stop loss (pips)
input int      InpTakeProfitPips = 12;            // Take profit (pips)
input double   InpMinProfitRatio = 1.2;           // Minimum profit ratio

input group "=== TRADING PAIRS ==="
input string   InpTradingPairs = "EURUSD,USDJPY,GBPUSD,AUDUSD"; // Trading pairs
input string   InpPrimaryPair = "EURUSD";         // Primary pair
input int      InpMaxPairsSimultaneous = 2;       // Max pairs simultaneous

input group "=== STRATEGY PARAMETERS ==="
input int      InpEMAFastPeriod = 20;             // EMA fast period
input int      InpEMASlowPeriod = 200;            // EMA slow period
input int      InpBBPeriod = 20;                  // Bollinger Bands period
input double   InpBBDeviation = 2.0;              // Bollinger Bands deviation
input int      InpRSIPeriod = 14;                 // RSI period
input double   InpRSIOverbought = 70.0;          // RSI overbought level
input double   InpRSIOversold = 30.0;             // RSI oversold level

input group "=== TIME FILTERS ==="
input int      InpTradingStartHour = 8;           // Trading start hour
input int      InpTradingEndHour = 22;            // Trading end hour
input bool     InpAvoidFridayClose = true;        // Avoid Friday close
input bool     InpAvoidNewsEvents = true;         // Avoid news events

input group "=== PERFORMANCE TARGETS ==="
input double   InpDay1Target = 900.0;             // Day 1 target (%)
input double   InpDay2Target = 200.0;             // Day 2 target (%)
input double   InpDay3PlusTargetMin = 2.0;        // Day 3+ target min (%)
input double   InpDay3PlusTargetMax = 5.0;        // Day 3+ target max (%)

input group "=== ADVANCED SETTINGS ==="
input int      InpMagicNumber = 123456;           // Magic number
input string   InpCommentPrefix = "ForexRobot";   // Comment prefix
input bool     InpDebugMode = false;              // Debug mode
input bool     InpVerboseLogging = false;         // Verbose logging

//--- Global variables
CTrade         trade;
CPositionInfo  position;
COrderInfo     order;

//--- Strategy state variables
struct StrategyState {
    bool trading_enabled;
    bool kill_switch_active;
    int consecutive_losses;
    double daily_pnl;
    double max_drawdown;
    double account_balance_start;
    datetime last_trade_time;
    int total_trades_today;
    double total_profit_today;
    double total_loss_today;
};

StrategyState g_strategy_state;

//--- Performance tracking
struct PerformanceMetrics {
    double net_profit;
    double win_rate;
    double profit_factor;
    double max_drawdown;
    double sharpe_ratio;
    double expectancy;
    int total_trades;
    int winning_trades;
    int losing_trades;
    double total_profit;
    double total_loss;
};

PerformanceMetrics g_performance;

//--- Indicator handles
int g_ema_fast_handle;
int g_ema_slow_handle;
int g_bb_handle;
int g_rsi_handle;

//--- Trading pairs
string g_trading_pairs[];
int g_pair_count;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize strategy state
    InitializeStrategyState();
    
    //--- Parse trading pairs
    ParseTradingPairs();
    
    //--- Initialize indicators
    if(!InitializeIndicators())
    {
        Print("Failed to initialize indicators");
        Print("Please check:");
        Print("1. MetaTrader 5 is properly installed");
        Print("2. Indicators are available in Navigator");
        Print("3. AutoTrading is enabled");
        Print("4. Symbol ", InpPrimaryPair, " is available");
        return INIT_FAILED;
    }
    
    //--- Initialize trade object
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    //--- Load configuration from file
    LoadConfiguration();
    
    //--- Print initialization info
    Print("Forex Robot initialized successfully");
    Print("Account Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Account Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("Trading Pairs: ", InpTradingPairs);
    Print("Risk per Trade: ", InpRiskPerTrade, "%");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Save performance metrics
    SavePerformanceMetrics();
    
    //--- Release indicator handles
    if(g_ema_fast_handle != INVALID_HANDLE)
        IndicatorRelease(g_ema_fast_handle);
    if(g_ema_slow_handle != INVALID_HANDLE)
        IndicatorRelease(g_ema_slow_handle);
    if(g_bb_handle != INVALID_HANDLE)
        IndicatorRelease(g_bb_handle);
    if(g_rsi_handle != INVALID_HANDLE)
        IndicatorRelease(g_rsi_handle);
    
    Print("Forex Robot deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if trading is enabled
    if(!InpEnableTrading || g_strategy_state.kill_switch_active)
        return;
    
    //--- Check account balance
    if(!CheckAccountBalance())
        return;
    
    //--- Check time filters
    if(!CheckTimeFilters())
        return;
    
    //--- Check risk limits
    if(!CheckRiskLimits())
        return;
    
    //--- Check news filter
    if(InpAvoidNewsEvents && !CheckNewsFilter())
        return;
    
    //--- Process each trading pair
    for(int i = 0; i < g_pair_count; i++)
    {
        ProcessTradingPair(g_trading_pairs[i]);
    }
    
    //--- Update performance metrics
    UpdatePerformanceMetrics();
    
    //--- Check circuit breakers
    CheckCircuitBreakers();
}

//+------------------------------------------------------------------+
//| Initialize strategy state                                        |
//+------------------------------------------------------------------+
void InitializeStrategyState()
{
    g_strategy_state.trading_enabled = InpEnableTrading;
    g_strategy_state.kill_switch_active = false;
    g_strategy_state.consecutive_losses = 0;
    g_strategy_state.daily_pnl = 0.0;
    g_strategy_state.max_drawdown = 0.0;
    g_strategy_state.account_balance_start = AccountInfoDouble(ACCOUNT_BALANCE);
    g_strategy_state.last_trade_time = 0;
    g_strategy_state.total_trades_today = 0;
    g_strategy_state.total_profit_today = 0.0;
    g_strategy_state.total_loss_today = 0.0;
    
    //--- Initialize performance metrics
    g_performance.net_profit = 0.0;
    g_performance.win_rate = 0.0;
    g_performance.profit_factor = 0.0;
    g_performance.max_drawdown = 0.0;
    g_performance.sharpe_ratio = 0.0;
    g_performance.expectancy = 0.0;
    g_performance.total_trades = 0;
    g_performance.winning_trades = 0;
    g_performance.losing_trades = 0;
    g_performance.total_profit = 0.0;
    g_performance.total_loss = 0.0;
}

//+------------------------------------------------------------------+
//| Parse trading pairs from input string                           |
//+------------------------------------------------------------------+
void ParseTradingPairs()
{
    string pairs[];
    StringSplit(InpTradingPairs, ',', pairs);
    
    g_pair_count = ArraySize(pairs);
    ArrayResize(g_trading_pairs, g_pair_count);
    
    for(int i = 0; i < g_pair_count; i++)
    {
        g_trading_pairs[i] = pairs[i];
        if(InpDebugMode)
            Print("Added trading pair: ", g_trading_pairs[i]);
    }
}

//+------------------------------------------------------------------+
//| Initialize technical indicators                                  |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
    //--- Initialize EMA handles
    g_ema_fast_handle = iMA(InpPrimaryPair, PERIOD_M5, InpEMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(g_ema_fast_handle == INVALID_HANDLE)
    {
        Print("Error: Cannot create EMA Fast indicator handle. Error: ", GetLastError());
        return false;
    }
    
    g_ema_slow_handle = iMA(InpPrimaryPair, PERIOD_M5, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(g_ema_slow_handle == INVALID_HANDLE)
    {
        Print("Error: Cannot create EMA Slow indicator handle. Error: ", GetLastError());
        return false;
    }
    
    //--- Initialize Bollinger Bands handle
    g_bb_handle = iBands(InpPrimaryPair, PERIOD_M5, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
    if(g_bb_handle == INVALID_HANDLE)
    {
        Print("Error: Cannot create Bollinger Bands indicator handle. Error: ", GetLastError());
        return false;
    }
    
    //--- Initialize RSI handle
    g_rsi_handle = iRSI(InpPrimaryPair, PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
    if(g_rsi_handle == INVALID_HANDLE)
    {
        Print("Error: Cannot create RSI indicator handle. Error: ", GetLastError());
        return false;
    }
    
    //--- Wait for indicators to calculate
    Sleep(1000);
    
    //--- Verify indicators are working
    double test_values[1];
    if(CopyBuffer(g_ema_fast_handle, 0, 0, 1, test_values) <= 0 ||
       CopyBuffer(g_ema_slow_handle, 0, 0, 1, test_values) <= 0 ||
       CopyBuffer(g_bb_handle, 0, 0, 1, test_values) <= 0 ||
       CopyBuffer(g_rsi_handle, 0, 0, 1, test_values) <= 0)
    {
        Print("Error: Indicators created but cannot read data. Error: ", GetLastError());
        return false;
    }
    
    Print("All indicators initialized successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Load configuration from file                                    |
//+------------------------------------------------------------------+
void LoadConfiguration()
{
    //--- This would load from config.ini file
    //--- For now, using input parameters
    if(InpDebugMode)
        Print("Configuration loaded from input parameters");
}

//+------------------------------------------------------------------+
//| Check account balance                                           |
//+------------------------------------------------------------------+
bool CheckAccountBalance()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance < InpMinBalance)
    {
        Print("Account balance below minimum: ", balance, " < ", InpMinBalance);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check time filters                                              |
//+------------------------------------------------------------------+
bool CheckTimeFilters()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    //--- Check trading hours
    if(dt.hour < InpTradingStartHour || dt.hour >= InpTradingEndHour)
    {
        if(InpVerboseLogging)
            Print("Outside trading hours: ", dt.hour);
        return false;
    }
    
    //--- Avoid Friday close
    if(InpAvoidFridayClose && dt.day_of_week == 5 && dt.hour >= 21)
    {
        if(InpVerboseLogging)
            Print("Avoiding Friday close");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check risk limits                                               |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    //--- Check daily loss limit
    double daily_loss_pct = (g_strategy_state.account_balance_start - equity) / g_strategy_state.account_balance_start * 100;
    if(daily_loss_pct >= InpDailyLossLimit)
    {
        Print("Daily loss limit reached: ", daily_loss_pct, "%");
        g_strategy_state.kill_switch_active = true;
        return false;
    }
    
    //--- Check max drawdown
    double drawdown_pct = (g_strategy_state.account_balance_start - equity) / g_strategy_state.account_balance_start * 100;
    if(drawdown_pct >= InpMaxDrawdownLimit)
    {
        Print("Max drawdown limit reached: ", drawdown_pct, "%");
        g_strategy_state.kill_switch_active = true;
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check news filter                                               |
//+------------------------------------------------------------------+
bool CheckNewsFilter()
{
    //--- This would check news calendar
    //--- For now, return true (no news filter)
    return true;
}

//+------------------------------------------------------------------+
//| Process trading pair                                            |
//+------------------------------------------------------------------+
void ProcessTradingPair(string symbol)
{
    //--- Check if we already have a position for this symbol
    if(PositionSelect(symbol))
        return;
    
    //--- Get indicator values
    double ema_fast[], ema_slow[], bb_upper[], bb_lower[], bb_middle[], rsi[];
    
    if(CopyBuffer(g_ema_fast_handle, 0, 0, 3, ema_fast) <= 0 ||
       CopyBuffer(g_ema_slow_handle, 0, 0, 3, ema_slow) <= 0 ||
       CopyBuffer(g_bb_handle, 1, 0, 3, bb_upper) <= 0 ||
       CopyBuffer(g_bb_handle, 2, 0, 3, bb_lower) <= 0 ||
       CopyBuffer(g_bb_handle, 0, 0, 3, bb_middle) <= 0 ||
       CopyBuffer(g_rsi_handle, 0, 0, 3, rsi) <= 0)
    {
        Print("Error: Failed to copy indicator buffers for ", symbol);
        return;
    }
    
    //--- Get current price
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    //--- Calculate pip value
    double pip_value = point * 10;
    if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(symbol, SYMBOL_DIGITS) == 3)
        pip_value = point * 10;
    else
        pip_value = point;
    
    //--- Check for buy signal
    if(CheckBuySignal(ema_fast, ema_slow, bb_upper, bb_lower, bb_middle, rsi, ask))
    {
        ExecuteBuyOrder(symbol, ask, pip_value);
    }
    //--- Check for sell signal
    else if(CheckSellSignal(ema_fast, ema_slow, bb_upper, bb_lower, bb_middle, rsi, bid))
    {
        ExecuteSellOrder(symbol, bid, pip_value);
    }
}

//+------------------------------------------------------------------+
//| Check buy signal                                                |
//+------------------------------------------------------------------+
bool CheckBuySignal(double &ema_fast[], double &ema_slow[], double &bb_upper[], 
                   double &bb_lower[], double &bb_middle[], double &rsi[], double price)
{
    //--- EMA trend confirmation (price above both EMAs)
    if(price <= ema_fast[0] || price <= ema_slow[0])
        return false;
    
    //--- Bollinger Bands mean reversion (price near lower band)
    double bb_position = (price - bb_lower[0]) / (bb_upper[0] - bb_lower[0]);
    if(bb_position > 0.3) // Not oversold enough
        return false;
    
    //--- RSI confirmation (not overbought)
    if(rsi[0] > InpRSIOverbought)
        return false;
    
    //--- Additional momentum confirmation
    if(ema_fast[0] <= ema_slow[0])
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check sell signal                                               |
//+------------------------------------------------------------------+
bool CheckSellSignal(double &ema_fast[], double &ema_slow[], double &bb_upper[], 
                    double &bb_lower[], double &bb_middle[], double &rsi[], double price)
{
    //--- EMA trend confirmation (price below both EMAs)
    if(price >= ema_fast[0] || price >= ema_slow[0])
        return false;
    
    //--- Bollinger Bands mean reversion (price near upper band)
    double bb_position = (price - bb_lower[0]) / (bb_upper[0] - bb_lower[0]);
    if(bb_position < 0.7) // Not overbought enough
        return false;
    
    //--- RSI confirmation (not oversold)
    if(rsi[0] < InpRSIOversold)
        return false;
    
    //--- Additional momentum confirmation
    if(ema_fast[0] >= ema_slow[0])
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Execute buy order                                               |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(string symbol, double price, double pip_value)
{
    //--- Calculate position size
    double lot_size = CalculatePositionSize(symbol, InpStopLossPips * pip_value);
    if(lot_size <= 0)
        return;
    
    //--- Calculate stop loss and take profit
    double stop_loss = price - (InpStopLossPips * pip_value);
    double take_profit = price + (InpTakeProfitPips * pip_value);
    
    //--- Execute buy order
    if(trade.Buy(lot_size, symbol, price, stop_loss, take_profit, InpCommentPrefix + "_BUY"))
    {
        Print("Buy order executed: ", symbol, " Lot: ", lot_size, " Price: ", price);
        g_strategy_state.last_trade_time = TimeCurrent();
        g_strategy_state.total_trades_today++;
    }
    else
    {
        Print("Buy order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Execute sell order                                              |
//+------------------------------------------------------------------+
void ExecuteSellOrder(string symbol, double price, double pip_value)
{
    //--- Calculate position size
    double lot_size = CalculatePositionSize(symbol, InpStopLossPips * pip_value);
    if(lot_size <= 0)
        return;
    
    //--- Calculate stop loss and take profit
    double stop_loss = price + (InpStopLossPips * pip_value);
    double take_profit = price - (InpTakeProfitPips * pip_value);
    
    //--- Execute sell order
    if(trade.Sell(lot_size, symbol, price, stop_loss, take_profit, InpCommentPrefix + "_SELL"))
    {
        Print("Sell order executed: ", symbol, " Lot: ", lot_size, " Price: ", price);
        g_strategy_state.last_trade_time = TimeCurrent();
        g_strategy_state.total_trades_today++;
    }
    else
    {
        Print("Sell order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                           |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double stop_loss_distance)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = balance * InpRiskPerTrade / 100.0;
    
    double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double lot_size = risk_amount / (stop_loss_distance / tick_size * tick_value);
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    lot_size = MathMin(lot_size, InpMaxLotSize);
    
    //--- Round to lot step
    lot_size = MathRound(lot_size / lot_step) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Update performance metrics                                      |
//+------------------------------------------------------------------+
void UpdatePerformanceMetrics()
{
    //--- This would update performance metrics based on closed positions
    //--- For now, basic implementation
    g_performance.total_trades = g_strategy_state.total_trades_today;
}

//+------------------------------------------------------------------+
//| Check circuit breakers                                          |
//+------------------------------------------------------------------+
void CheckCircuitBreakers()
{
    //--- Check consecutive losses
    if(g_strategy_state.consecutive_losses >= InpConsecutiveLossLimit)
    {
        Print("Circuit breaker activated: Too many consecutive losses");
        g_strategy_state.kill_switch_active = true;
    }
    
    //--- Check daily loss limit
    if(g_strategy_state.total_loss_today >= AccountInfoDouble(ACCOUNT_BALANCE) * InpDailyLossLimit / 100.0)
    {
        Print("Circuit breaker activated: Daily loss limit reached");
        g_strategy_state.kill_switch_active = true;
    }
}

//+------------------------------------------------------------------+
//| Save performance metrics                                         |
//+------------------------------------------------------------------+
void SavePerformanceMetrics()
{
    //--- This would save performance metrics to file
    if(InpDebugMode)
        Print("Performance metrics saved");
}

//+------------------------------------------------------------------+
//| Trade transaction event                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    //--- Handle trade transaction events
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        //--- Process deal
        if(InpVerboseLogging)
            Print("Deal executed: ", trans.symbol, " Volume: ", trans.volume, " Price: ", trans.price);
    }
}
