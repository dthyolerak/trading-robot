//+------------------------------------------------------------------+
//|                                                SimpleRobot.mq5 |
//|                        Copyright 2024, Forex Trading Robot |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Forex Trading Robot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Simple Forex Robot - No Indicators Required"

//--- Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group "=== GENERAL SETTINGS ==="
input bool     InpEnableTrading = true;           // Enable trading
input bool     InpDemoMode = true;                // Demo mode
input string   InpAccountCurrency = "USD";        // Account currency
input double   InpMinBalance = 10.0;              // Minimum balance

input group "=== RISK MANAGEMENT ==="
input double   InpRiskPerTrade = 0.1;             // Risk per trade (%)
input double   InpDailyLossLimit = 3.0;           // Daily loss limit (%)
input int      InpStopLossPips = 20;              // Stop loss (pips)
input int      InpTakeProfitPips = 30;            // Take profit (pips)

input group "=== SIMPLE STRATEGY ==="
input string   InpSymbol = "EURUSDm";              // Trading symbol
input int      InpMagicNumber = 12345;            // Magic number

//--- Global variables
CTrade trade;
CPositionInfo position;
double g_daily_pnl = 0.0;
double g_initial_balance = 0.0;
datetime g_last_trade_time = 0;
int g_consecutive_losses = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Simple Forex Robot starting...");
    
    //--- Check if trading is allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Print("Error: Trading not allowed in terminal");
        return INIT_FAILED;
    }
    
    //--- Check if auto trading is enabled
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("Error: Auto trading not allowed");
        return INIT_FAILED;
    }
    
    //--- Get initial balance
    g_initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    Print("Account Balance: $", g_initial_balance);
    
    //--- Initialize trade object
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    
    //--- Check symbol
    if(!SymbolSelect(InpSymbol, true))
    {
        Print("Error: Symbol ", InpSymbol, " not available");
        return INIT_FAILED;
    }
    
    Print("Simple Forex Robot initialized successfully");
    Print("Trading Symbol: ", InpSymbol);
    Print("Demo Mode: ", InpDemoMode);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Simple Forex Robot deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if trading is enabled
    if(!InpEnableTrading)
        return;
    
    //--- Check minimum balance
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(current_balance < InpMinBalance)
    {
        Print("Balance below minimum: $", current_balance);
        return;
    }
    
    //--- Check daily loss limit
    if(g_daily_pnl < -InpDailyLossLimit * g_initial_balance / 100.0)
    {
        Print("Daily loss limit reached: $", g_daily_pnl);
        return;
    }
    
    //--- Simple strategy: Buy every hour
    datetime current_time = TimeCurrent();
    if(current_time - g_last_trade_time >= 3600) // 1 hour = 3600 seconds
    {
        //--- Close existing positions
        CloseAllPositions();
        
        //--- Open new position
        if(CountPositions() == 0)
        {
            OpenBuyPosition();
            g_last_trade_time = current_time;
        }
    }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
    double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    
    if(ask <= 0 || bid <= 0)
    {
        Print("Error: Invalid prices");
        return;
    }
    
    //--- Calculate position size
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount = balance * InpRiskPerTrade / 100.0;
    double pip_value = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
    double lot_size = risk_amount / (InpStopLossPips * pip_value);
    
    //--- Normalize lot size
    double min_lot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    //--- Calculate stop loss and take profit
    double stop_loss = ask - InpStopLossPips * SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    double take_profit = ask + InpTakeProfitPips * SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    
    //--- Open position
    if(trade.Buy(lot_size, InpSymbol, ask, stop_loss, take_profit, "Simple Robot"))
    {
        Print("Buy order opened: ", lot_size, " lots at ", ask);
        g_consecutive_losses = 0;
    }
    else
    {
        Print("Error opening buy order: ", trade.ResultRetcode());
        g_consecutive_losses++;
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == InpSymbol && position.Magic() == InpMagicNumber)
            {
                trade.PositionClose(position.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count positions                                                  |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == InpSymbol && position.Magic() == InpMagicNumber)
                count++;
        }
    }
    return count;
}
