//+------------------------------------------------------------------+
//| Expert Advisor: Reverse Martingale Strategy                      |
//|                Multi-Entry Condition Version                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "DeepSeek AI"
#property version   "1.00"
#property description "Reverse Martingale Strategy with Multiple Entry Conditions"

input group "=== Strategy Configuration ==="
input bool     EnableStrategy      = true;        // Enable/disable trading
input double   InitialLotSize      = 0.01;        // Initial lot size
input string   CustomLots          = "0.02,0.03,0.04"; // Comma-separated lot sizes for profit positions
input string   TriggerPipsArray    = "700,1400,2100"; // Comma-separated trigger distances in pips
input string   ProfitTargetPips    = "1000,2000,3000"; // Comma-separated profit targets in pips
input string   TotalProfitInPoints = "500,1500,2500"; // Comma-separated total profit targets in points
input int      InitialSLPips       = 1000;        // Initial Stop Loss in pips
input int      MagicNumber         = 202402;      // Magic number for trades
input int      Slippage            = 10;          // Slippage in points

input group "=== Entry Conditions ==="
input bool     UseConsecutiveCandles = true;      // Use consecutive candles for entry
input int      ConsecutiveCandles  = 2;           // Number of consecutive candles
input bool     UseEMA              = false;       // Use EMA for trend direction
input int      EMA_Period          = 200;         // EMA period
input bool     UseRSI              = false;       // Use RSI for entry confirmation
input int      RSI_Period          = 14;          // RSI period
input double   RSI_UpperLevel      = 70.0;        // RSI upper level
input double   RSI_LowerLevel      = 30.0;        // RSI lower level
input bool     UseSwingPoints      = false;       // Use swing high/low for entry
input int      SwingLookback       = 5;           // Bars to look back for swing points

input group "=== Risk Management ==="
input bool     UseEquityProtection = true;        // Enable equity protection
input double   MaxEquityDrawdown   = 20.0;        // Maximum equity drawdown percentage
input bool     UseTrailingStop     = true;        // Enable trailing stop after all positions
input int      TrailingStartPips   = 500;         // Pips profit to start trailing
input int      TrailingStepPips    = 100;         // Trailing step in pips

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Arrays/ArrayInt.mqh>
#include <Arrays/ArrayDouble.mqh>

CTrade trade;
CPositionInfo positionInfo;
CArrayInt triggerPips;        // Array to store trigger pip values
CArrayDouble customLotsArray; // Array to store custom lot sizes
CArrayInt profitTargets;      // Array to store profit targets
CArrayInt totalProfitPoints;  // Array to store total profit targets in points

// Global variables
bool strategyEnabled;
int direction = 0;            // 1 for Buy, -1 for Sell
bool initialTradeOpened = false;
double initialEntryPrice = 0;
double highestEquity = 0;
int totalPositionsOpened = 0;
int emaHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;

#define PIP 10 // For 5-digit brokers, adjust if needed

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    strategyEnabled = EnableStrategy;
    
    // Parse input arrays
    if(!ParseTriggerPipsArray())
    {
        Print("Error parsing TriggerPipsArray!");
        return INIT_FAILED;
    }
    
    if(!ParseCustomLotsArray())
    {
        Print("Error parsing CustomLots!");
        return INIT_FAILED;
    }
    
    if(!ParseProfitTargetsArray())
    {
        Print("Error parsing ProfitTargetPips!");
        return INIT_FAILED;
    }
    
    if(!ParseTotalProfitPointsArray())
    {
        Print("Error parsing TotalProfitInPoints!");
        return INIT_FAILED;
    }
    
    // Verify arrays have same size
    if(triggerPips.Total() != customLotsArray.Total() || 
       triggerPips.Total() != profitTargets.Total() ||
       triggerPips.Total() != totalProfitPoints.Total())
    {
        Print("Error: TriggerPipsArray, CustomLots, ProfitTargetPips, and TotalProfitInPoints must have the same number of elements!");
        return INIT_FAILED;
    }
    
    // Create indicator handles if needed
    if(UseEMA)
    {
        emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
        if(emaHandle == INVALID_HANDLE)
        {
            Print("Failed to create EMA indicator!");
            return INIT_FAILED;
        }
    }
    
    if(UseRSI)
    {
        rsiHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            Print("Failed to create RSI indicator!");
            return INIT_FAILED;
        }
    }
    
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    
    highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    Print("Reverse Martingale EA initialized successfully");
    Print("Total levels configured: ", triggerPips.Total());
    Print("TotalProfitInPoints: ", TotalProfitInPoints);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Parse TriggerPipsArray string                                    |
//+------------------------------------------------------------------+
bool ParseTriggerPipsArray()
{
    string values[];
    int count = StringSplit(TriggerPipsArray, ',', values);
    
    if(count <= 0) return false;
    
    triggerPips.Clear();
    for(int i = 0; i < count; i++)
    {
        string temp = values[i];
        StringTrimLeft(temp);
        StringTrimRight(temp);
        int pipValue = (int)StringToInteger(temp);
        if(pipValue > 0)
        {
            triggerPips.Add(pipValue);
        }
    }
    
    return triggerPips.Total() > 0;
}

//+------------------------------------------------------------------+
//| Parse CustomLots string                                          |
//+------------------------------------------------------------------+
bool ParseCustomLotsArray()
{
    string values[];
    int count = StringSplit(CustomLots, ',', values);
    
    if(count <= 0) return false;
    
    customLotsArray.Clear();
    for(int i = 0; i < count; i++)
    {
        string temp = values[i];
        StringTrimLeft(temp);
        StringTrimRight(temp);
        double lotValue = StringToDouble(temp);
        if(lotValue > 0)
        {
            customLotsArray.Add(lotValue);
        }
    }
    
    return customLotsArray.Total() > 0;
}

//+------------------------------------------------------------------+
//| Parse ProfitTargets string                                       |
//+------------------------------------------------------------------+
bool ParseProfitTargetsArray()
{
    string values[];
    int count = StringSplit(ProfitTargetPips, ',', values);
    
    if(count <= 0) return false;
    
    profitTargets.Clear();
    for(int i = 0; i < count; i++)
    {
        string temp = values[i];
        StringTrimLeft(temp);
        StringTrimRight(temp);
        int pipValue = (int)StringToInteger(temp);
        if(pipValue > 0)
        {
            profitTargets.Add(pipValue);
        }
    }
    
    return profitTargets.Total() > 0;
}

//+------------------------------------------------------------------+
//| Parse TotalProfitInPoints string                                 |
//+------------------------------------------------------------------+
bool ParseTotalProfitPointsArray()
{
    string values[];
    int count = StringSplit(TotalProfitInPoints, ',', values);
    
    if(count <= 0) return false;
    
    totalProfitPoints.Clear();
    for(int i = 0; i < count; i++)
    {
        string temp = values[i];
        StringTrimLeft(temp);
        StringTrimRight(temp);
        int pointsValue = (int)StringToInteger(temp);
        if(pointsValue > 0)
        {
            totalProfitPoints.Add(pointsValue);
        }
    }
    
    return totalProfitPoints.Total() > 0;
}

//+------------------------------------------------------------------+
//| Get current EMA value                                            |
//+------------------------------------------------------------------+
double GetEMAValue()
{
    if(emaHandle == INVALID_HANDLE) return 0;
    
    double emaValue[1];
    if(CopyBuffer(emaHandle, 0, 0, 1, emaValue) != 1)
    {
        Print("Failed to copy EMA buffer!");
        return 0;
    }
    
    return emaValue[0];
}

//+------------------------------------------------------------------+
//| Get current RSI value                                            |
//+------------------------------------------------------------------+
double GetRSIValue()
{
    if(rsiHandle == INVALID_HANDLE) return 0;
    
    double rsiValue[1];
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsiValue) != 1)
    {
        Print("Failed to copy RSI buffer!");
        return 0;
    }
    
    return rsiValue[0];
}

//+------------------------------------------------------------------+
//| Check EMA filter condition                                       |
//+------------------------------------------------------------------+
bool CheckEMAFilter(int &dir)
{
    if(!UseEMA) return true;
    
    double emaValue = GetEMAValue();
    if(emaValue == 0) return false;
    
    double currentClose = iClose(_Symbol, _Period, 1);
    
    if(currentClose > emaValue)
    {
        dir = 1; // Only allow buy trades
        return true;
    }
    else if(currentClose < emaValue)
    {
        dir = -1; // Only allow sell trades
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check RSI filter condition                                       |
//+------------------------------------------------------------------+
bool CheckRSIFilter()
{
    if(!UseRSI) return true;
    
    double rsiValue = GetRSIValue();
    if(rsiValue == 0) return false;
    
    return (rsiValue >= RSI_LowerLevel && rsiValue <= RSI_UpperLevel);
}

//+------------------------------------------------------------------+
//| Check Swing Points condition                                     |
//+------------------------------------------------------------------+
bool CheckSwingPoints(int &dir)
{
    if(!UseSwingPoints) return false;
    
    double highArray[], lowArray[];
    ArraySetAsSeries(highArray, true);
    ArraySetAsSeries(lowArray, true);
    
    if(CopyHigh(_Symbol, _Period, 0, SwingLookback + 1, highArray) != SwingLookback + 1 ||
       CopyLow(_Symbol, _Period, 0, SwingLookback + 1, lowArray) != SwingLookback + 1)
    {
        return false;
    }
    
    // Check for swing high
    bool isSwingHigh = true;
    for(int i = 1; i <= SwingLookback; i++)
    {
        if(highArray[0] < highArray[i])
        {
            isSwingHigh = false;
            break;
        }
    }
    
    // Check for swing low
    bool isSwingLow = true;
    for(int i = 1; i <= SwingLookback; i++)
    {
        if(lowArray[0] > lowArray[i])
        {
            isSwingLow = false;
            break;
        }
    }
    
    if(isSwingHigh)
    {
        dir = -1; // Sell direction
        return true;
    }
    else if(isSwingLow)
    {
        dir = 1; // Buy direction
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Consecutive Candles condition                              |
//+------------------------------------------------------------------+
bool CheckConsecutiveCandles(int &dir)
{
    if(!UseConsecutiveCandles) return false;
    
    bool bullish = true;
    bool bearish = true;
    
    for(int i = 1; i <= ConsecutiveCandles; i++)
    {
        double open = iOpen(_Symbol, _Period, i);
        double close = iClose(_Symbol, _Period, i);
        
        if(close <= open) bullish = false;
        if(close >= open) bearish = false;
    }
    
    if(bullish)
    {
        dir = 1;
        return true;
    }
    else if(bearish)
    {
        dir = -1;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check entry conditions                                           |
//+------------------------------------------------------------------+
bool CheckEntryConditions(int &dir)
{
    bool entrySignal = false;
    
    // Check multiple entry conditions
    if(UseConsecutiveCandles && CheckConsecutiveCandles(dir))
    {
        entrySignal = true;
    }
    
    if(!entrySignal && UseSwingPoints && CheckSwingPoints(dir))
    {
        entrySignal = true;
    }
    
    // Apply filters
    if(entrySignal && UseEMA)
    {
        int emaDir = 0;
        if(!CheckEMAFilter(emaDir) || dir != emaDir)
        {
            entrySignal = false;
        }
    }
    
    if(entrySignal && UseRSI)
    {
        if(!CheckRSIFilter())
        {
            entrySignal = false;
        }
    }
    
    return entrySignal;
}

//+------------------------------------------------------------------+
//| Calculate stop loss price                                        |
//+------------------------------------------------------------------+
double CalculateStopLoss(double entryPrice, int dir, bool isInitial = true)
{
    if(isInitial && InitialSLPips <= 0) return 0;
    
    if(dir == 1) // Buy
    {
        if(isInitial)
            return entryPrice - (InitialSLPips * PIP * _Point);
        else
            return entryPrice - (InitialSLPips * PIP * _Point);
    }
    else // Sell
    {
        if(isInitial)
            return entryPrice + (InitialSLPips * PIP * _Point);
        else
            return entryPrice + (InitialSLPips * PIP * _Point);
    }
}

//+------------------------------------------------------------------+
//| Calculate trigger price for next position                        |
//+------------------------------------------------------------------+
double CalculateTriggerPrice(int positionCount)
{
    if(positionCount == 0 || positionCount > triggerPips.Total()) return 0;
    
    int totalPips = 0;
    for(int i = 0; i < positionCount; i++)
    {
        totalPips += triggerPips.At(i);
    }
    
    if(direction == 1) // Buy
    {
        return initialEntryPrice + (totalPips * PIP * _Point);
    }
    else // Sell
    {
        return initialEntryPrice - (totalPips * PIP * _Point);
    }
}

//+------------------------------------------------------------------+
//| Get lot size for position                                        |
//+------------------------------------------------------------------+
double GetLotSize(int positionIndex)
{
    if(positionIndex == 0) return InitialLotSize;
    
    int lotIndex = positionIndex - 1;
    if(lotIndex < customLotsArray.Total())
    {
        return customLotsArray.At(lotIndex);
    }
    
    return customLotsArray.At(customLotsArray.Total() - 1); // Return last lot if out of bounds
}

//+------------------------------------------------------------------+
//| Get profit target for current level                              |
//+------------------------------------------------------------------+
double GetProfitTarget(int positionCount)
{
    if(positionCount <= 0 || positionCount > profitTargets.Total()) return 0;
    
    int targetPips = profitTargets.At(positionCount - 1);
    return targetPips * PIP * _Point;
}

//+------------------------------------------------------------------+
//| Get total profit target in points for current level              |
//+------------------------------------------------------------------+
double GetTotalProfitTargetPoints(int positionCount)
{
    if(positionCount <= 0 || positionCount > totalProfitPoints.Total()) return 0;
    
    int targetPoints = totalProfitPoints.At(positionCount - 1);
    return targetPoints * _Point; // Convert points to price
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get total unrealized profit                                      |
//+------------------------------------------------------------------+
double GetTotalProfit()
{
    double profit = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Get total profit in points from initial entry                    |
//+------------------------------------------------------------------+
double GetTotalProfitInPoints()
{
    if(!initialTradeOpened || initialEntryPrice == 0) return 0;
    
    double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(direction == 1) // Buy positions
    {
        return (currentPrice - initialEntryPrice) / _Point;
    }
    else // Sell positions
    {
        return (initialEntryPrice - currentPrice) / _Point;
    }
}

//+------------------------------------------------------------------+
//| Check equity protection                                          |
//+------------------------------------------------------------------+
bool CheckEquityProtection()
{
    if(!UseEquityProtection) return false;
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Update highest equity
    if(currentEquity > highestEquity)
    {
        highestEquity = currentEquity;
    }
    
    // Calculate drawdown
    double drawdownPercent = ((highestEquity - currentEquity) / highestEquity) * 100;
    
    if(drawdownPercent >= MaxEquityDrawdown)
    {
        Print("Equity protection triggered! Drawdown: ", drawdownPercent, "%");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
    if(!UseTrailingStop || CountOpenPositions() == 0) return;
    
    double totalProfit = GetTotalProfit();
    if(totalProfit < (TrailingStartPips * PIP * _Point)) return;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            double newSL = currentSL;
            
            if(posType == POSITION_TYPE_BUY)
            {
                newSL = currentPrice - (TrailingStepPips * PIP * _Point);
                if(newSL > currentSL || currentSL == 0)
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                newSL = currentPrice + (TrailingStepPips * PIP * _Point);
                if(newSL < currentSL || currentSL == 0)
                {
                    trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            trade.PositionClose(ticket);
        }
    }
    
    // Reset state
    initialTradeOpened = false;
    initialEntryPrice = 0;
    direction = 0;
    totalPositionsOpened = 0;
}

//+------------------------------------------------------------------+
//| Adjust stop losses to previous trigger level                     |
//+------------------------------------------------------------------+
void AdjustStopLossesToLevel(int level)
{
    double newSL = CalculateTriggerPrice(level - 1);
    if(newSL == 0) return;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // For buy positions, SL should be below current price
            if(posType == POSITION_TYPE_BUY && newSL < PositionGetDouble(POSITION_PRICE_CURRENT))
            {
                trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
            // For sell positions, SL should be above current price
            else if(posType == POSITION_TYPE_SELL && newSL > PositionGetDouble(POSITION_PRICE_CURRENT))
            {
                trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!strategyEnabled) return;
    
    // Check equity protection
    if(CheckEquityProtection())
    {
        CloseAllPositions();
        strategyEnabled = false;
        return;
    }
    
    int currentPositions = CountOpenPositions();
    
    if(currentPositions == 0)
    {
        // Look for new entry
        int dir = 0;
        if(CheckEntryConditions(dir))
        {
            OpenInitialPosition(dir);
        }
    }
    else
    {
        // Manage existing positions
        ManagePositions();
    }
    
    // Apply trailing stop if all positions are open
    if(currentPositions >= triggerPips.Total() + 1)
    {
        ApplyTrailingStop();
    }
}

//+------------------------------------------------------------------+
//| Open initial position                                            |
//+------------------------------------------------------------------+
void OpenInitialPosition(int dir)
{
    double entryPrice = (dir == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = CalculateStopLoss(entryPrice, dir, true);
    
    ENUM_ORDER_TYPE orderType = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if(trade.PositionOpen(_Symbol, orderType, InitialLotSize, entryPrice, sl, 0))
    {
        initialTradeOpened = true;
        initialEntryPrice = entryPrice;
        direction = dir;
        totalPositionsOpened = 1;
        
        Print("Initial position opened: ", EnumToString(orderType), 
              " Lot: ", InitialLotSize, " Price: ", entryPrice, " SL: ", sl);
    }
    else
    {
        Print("Failed to open initial position. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    if(!initialTradeOpened || initialEntryPrice == 0) return;
    
    int currentPositions = CountOpenPositions();
    
    // Check if we need to open next position
    if(currentPositions <= triggerPips.Total())
    {
        double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double triggerPrice = CalculateTriggerPrice(currentPositions);
        
        bool conditionMet = false;
        if(direction == 1 && currentPrice >= triggerPrice)
        {
            conditionMet = true;
        }
        else if(direction == -1 && currentPrice <= triggerPrice)
        {
            conditionMet = true;
        }
        
        if(conditionMet)
        {
            OpenAdditionalPosition(currentPositions);
        }
    }
    
    // Check profit targets
    CheckProfitTargets(currentPositions);
}

//+------------------------------------------------------------------+
//| Check profit targets                                             |
//+------------------------------------------------------------------+
void CheckProfitTargets(int currentPositions)
{
    // Check monetary profit target
    double totalProfit = GetTotalProfit();
    double currentMonetaryTarget = GetProfitTarget(currentPositions);
    
    if(currentMonetaryTarget > 0 && totalProfit >= currentMonetaryTarget)
    {
        Print("Monetary profit target reached! Closing all positions. Profit: ", totalProfit);
        CloseAllPositions();
        return;
    }
    
    // Check points profit target
    double totalPointsProfit = GetTotalProfitInPoints();
    double currentPointsTarget = GetTotalProfitTargetPoints(currentPositions);
    
    if(currentPointsTarget > 0 && totalPointsProfit >= currentPointsTarget)
    {
        Print("Points profit target reached! Closing all positions. Points Profit: ", totalPointsProfit);
        CloseAllPositions();
        return;
    }
}

//+------------------------------------------------------------------+
//| Open additional position                                         |
//+------------------------------------------------------------------+
void OpenAdditionalPosition(int positionCount)
{
    double lotSize = GetLotSize(positionCount);
    double entryPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = CalculateStopLoss(entryPrice, direction, false);
    
    ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    
    if(trade.PositionOpen(_Symbol, orderType, lotSize, entryPrice, sl, 0))
    {
        totalPositionsOpened++;
        
        // Adjust previous positions' SL to current trigger level
        AdjustStopLossesToLevel(positionCount);
        
        Print("Additional position #", positionCount, " opened. Lot: ", lotSize, 
              " Price: ", entryPrice, " Total positions: ", totalPositionsOpened);
              
        // Check profit targets immediately after opening new position
        CheckProfitTargets(positionCount + 1);
    }
    else
    {
        Print("Failed to open additional position #", positionCount, ". Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(emaHandle != INVALID_HANDLE)
        IndicatorRelease(emaHandle);
    if(rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
    
    Print("Reverse Martingale EA deinitialized. Reason: ", reason);
}