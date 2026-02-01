//+------------------------------------------------------------------+
//| AutoSLTP.mq5                                                     |
//| Deepseek AI Assistant                                            |
//|                                                                  |
//+------------------------------------------------------------------+

#property copyright "Deepseek AI Assistant"
#property version   "1.00"
#property description "Automatically add SL/TP to manual trades and trail them"

#include <Trade/Trade.mql5>
#include <Trade/PositionInfo.mql5>

// Input parameters
input group "=== Risk Management ==="
input double   StopLossPips = 50.0;        // Stop Loss in pips (larger for XAUUSD)
input double   TakeProfitPips = 100.0;     // Take Profit in pips  
input group "=== Trailing Settings ==="
input double   TrailStartPips = 30.0;      // Start trailing when profit reaches (pips)
input double   TrailStepPips = 20.0;       // Trailing step in pips
input bool     EnableTrailing = true;      // Enable trailing stop
input group "=== Trade Management ==="
input bool     ManageAllPositions = true;  // Manage ALL positions regardless of Magic Number

// Global variables
double pointMultiplier;
CTrade trade;
CPositionInfo position;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Calculate point multiplier for XAUUSD (Gold)
    pointMultiplier = Point();
    
    // For XAUUSD, usually 2 decimal places, so normal point is sufficient
    // But we'll handle the pip calculation correctly
    Print("XAUUSD Auto SL/TP EA started");
    Print("Stop Loss: ", StopLossPips, " pips, Take Profit: ", TakeProfitPips, " pips");
    Print("Symbol: ", _Symbol, ", Digits: ", Digits());
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Auto SL/TP EA removed from chart");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    ProcessAllPositions();
}

//+------------------------------------------------------------------+
//| Process all positions                                            |
//+------------------------------------------------------------------+
void ProcessAllPositions()
{
    int total = PositionsTotal();
    
    for(int i = total - 1; i >= 0; i--)
    {
        if(position.SelectByIndex(i))
        {
            // Process ALL positions for current symbol (ignore magic number)
            if(position.Symbol() == _Symbol)
            {
                ProcessPosition();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Process individual position                                      |
//+------------------------------------------------------------------+
void ProcessPosition()
{
    ulong ticket = position.Ticket();
    ENUM_POSITION_TYPE type = position.PositionType();
    double openPrice = position.PriceOpen();
    double currentSL = position.StopLoss();
    double currentTP = position.TakeProfit();
    double volume = position.Volume();
    
    // Calculate pip value for XAUUSD
    double pipSize = CalculatePipSize();
    double slDistance = StopLossPips * pipSize;
    double tpDistance = TakeProfitPips * pipSize;
    double trailStart = TrailStartPips * pipSize;
    double trailStep = TrailStepPips * pipSize;
    
    // Debug information
    Print("Processing position #", ticket, " Type: ", EnumToString(type), 
          " Open: ", openPrice, " SL: ", currentSL, " TP: ", currentTP);
    
    // Set initial SL/TP if they are zero
    if(currentSL == 0 && currentTP == 0)
    {
        SetInitialSLTP(ticket, type, openPrice, slDistance, tpDistance, volume);
    }
    // Or trail if enabled and SL is set
    else if(EnableTrailing && currentSL != 0)
    {
        TrailStopLoss(ticket, type, openPrice, currentSL, trailStart, trailStep, pipSize, volume);
    }
}

//+------------------------------------------------------------------+
//| Calculate pip size for XAUUSD                                    |
//+------------------------------------------------------------------+
double CalculatePipSize()
{
    // For XAUUSD (Gold), 1 pip is typically 0.01 (2 decimal places)
    // But some brokers might use 3 decimal places
    if(Digits() == 3 || Digits() == 5)
        return Point() * 10;
    else
        return Point();
}

//+------------------------------------------------------------------+
//| Set initial SL and TP for positions                              |
//+------------------------------------------------------------------+
void SetInitialSLTP(ulong ticket, ENUM_POSITION_TYPE type, double openPrice, 
                   double slDistance, double tpDistance, double volume)
{
    double newSL = 0, newTP = 0;
    
    if(type == POSITION_TYPE_BUY)
    {
        newSL = openPrice - slDistance;
        newTP = openPrice + tpDistance;
    }
    else if(type == POSITION_TYPE_SELL)
    {
        newSL = openPrice + slDistance;
        newTP = openPrice - tpDistance;
    }
    
    // Normalize prices
    newSL = NormalizeDouble(newSL, Digits());
    newTP = NormalizeDouble(newTP, Digits());
    
    // Validate levels
    if(ValidateLevels(type, openPrice, newSL, newTP))
    {
        // Use CTrade to modify the position
        CTrade tradeModify;
        
        if(tradeModify.PositionModify(ticket, newSL, newTP))
        {
            Print("SUCCESS: Initial SL/TP set for position #", ticket);
            Print("  Type: ", EnumToString(type), " Open: ", openPrice);
            Print("  SL: ", newSL, " TP: ", newTP);
        }
        else
        {
            int error = GetLastError();
            Print("ERROR: Failed to set SL/TP for position #", ticket, " Error: ", error, " - ", GetErrorDescription(error));
        }
    }
    else
    {
        Print("WARNING: Invalid levels for position #", ticket, " SL: ", newSL, " TP: ", newTP);
    }
}

//+------------------------------------------------------------------+
//| Trail stop loss                                                  |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket, ENUM_POSITION_TYPE type, double openPrice, double currentSL, 
                   double trailStart, double trailStep, double pipSize, double volume)
{
    double currentPrice = 0;
    double newSL = currentSL;
    bool modifyNeeded = false;
    
    if(type == POSITION_TYPE_BUY)
    {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double profit = currentPrice - openPrice;
        
        if(profit >= trailStart)
        {
            double potentialSL = currentPrice - trailStart;
            potentialSL = NormalizeDouble(potentialSL, Digits());
            
            if(potentialSL > currentSL && potentialSL > openPrice)
            {
                if(currentPrice - currentSL >= trailStep)
                {
                    newSL = potentialSL;
                    modifyNeeded = true;
                }
            }
        }
    }
    else if(type == POSITION_TYPE_SELL)
    {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double profit = openPrice - currentPrice;
        
        if(profit >= trailStart)
        {
            double potentialSL = currentPrice + trailStart;
            potentialSL = NormalizeDouble(potentialSL, Digits());
            
            if(potentialSL < currentSL && potentialSL < openPrice)
            {
                if(currentSL - currentPrice >= trailStep)
                {
                    newSL = potentialSL;
                    modifyNeeded = true;
                }
            }
        }
    }
    
    if(modifyNeeded)
    {
        CTrade tradeModify;
        if(tradeModify.PositionModify(ticket, newSL, position.TakeProfit()))
        {
            Print("SUCCESS: Trailed SL for position #", ticket, " New SL: ", newSL);
        }
        else
        {
            int error = GetLastError();
            Print("ERROR: Failed to trail SL for position #", ticket, " Error: ", error);
        }
    }
}

//+------------------------------------------------------------------+
//| Validate price levels                                            |
//+------------------------------------------------------------------+
bool ValidateLevels(ENUM_POSITION_TYPE type, double openPrice, double sl, double tp)
{
    if(sl == 0 && tp == 0) return false;
    
    // Check minimum distance from current price
    double currentPrice = 0;
    if(type == POSITION_TYPE_BUY)
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    else
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * Point();
    
    if(type == POSITION_TYPE_BUY)
    {
        if(sl >= currentPrice - minDist) return false;
        if(tp <= currentPrice + minDist) return false;
        if(sl >= openPrice) return false;
        if(tp <= openPrice) return false;
    }
    else if(type == POSITION_TYPE_SELL)
    {
        if(sl <= currentPrice + minDist) return false;
        if(tp >= currentPrice - minDist) return false;
        if(sl <= openPrice) return false;
        if(tp >= openPrice) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string GetErrorDescription(int error)
{
    switch(error)
    {
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10007: return "Request canceled by trader";
        case 10008: return "Order placed too long ago";
        case 10009: return "Invalid order";
        case 10010: return "Trade session is not active";
        case 10011: return "Market is closed";
        case 10012: return "Insufficient funds";
        case 10013: return "Invalid stop/take profit levels";
        case 10014: return "Invalid volume";
        case 10015: return "Position not found";
        case 10016: return "Trade disabled";
        case 10017: return "Too many requests";
        default: return "Unknown error";
    }
}