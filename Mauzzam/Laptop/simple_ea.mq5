//+------------------------------------------------------------------+
//|                                                  ScalpingBot.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input double LotSize = 0.01;               // Lot size for trading
input int LookbackBars = 20;               // Number of bars to look back for swing points
input int MinBreakoutBars = 5;             // Minimum bars for breakout confirmation
input double RiskReward = 2.0;             // Risk to reward ratio
input int MaxSpread = 5000;                // Maximum allowed spread in points
input int MagicNumber = 123456;            // Magic number for trade identification
input bool EnableBuy = true;               // Enable buy trades
input bool EnableSell = true;              // Enable sell trades
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M15; // Trading time frame

// Global variables
int handleSwingHighs, handleSwingLows;
double swingHighBuffer[], swingLowBuffer[];
MqlTick currentTick;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Check input parameters
    if(LotSize <= 0)
    {
        Print("Error: LotSize must be greater than 0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(LookbackBars <= 0)
    {
        Print("Error: LookbackBars must be greater than 0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(RiskReward <= 0)
    {
        Print("Error: RiskReward must be greater than 0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    // Set up buffers for swing points
    ArraySetAsSeries(swingHighBuffer, true);
    ArraySetAsSeries(swingLowBuffer, true);
    
    Print("Scalping Bot initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Scalping Bot deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Get current tick information
    if(!SymbolInfoTick(_Symbol, currentTick))
    {
        Print("Error getting tick information");
        return;
    }
    
    // Check spread
    if((currentTick.ask - currentTick.bid) > MaxSpread * _Point)
    {
        Print("Spread too high: ", (currentTick.ask - currentTick.bid) / _Point, " points");
        return;
    }
    
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, TimeFrame, 0);
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    // Check for trading opportunities
    CheckForBuySignal();
    CheckForSellSignal();
    
    // Check for exit conditions
    CheckForExit();
}

//+------------------------------------------------------------------+
//| Find swing high                                                  |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
    double highArray[];
    ArraySetAsSeries(highArray, true);
    
    // Copy high prices
    if(CopyHigh(_Symbol, TimeFrame, 0, LookbackBars + 1, highArray) < LookbackBars + 1)
    {
        Print("Error copying high prices");
        return 0;
    }
    
    // Find the highest high in the lookback period
    int highestBar = ArrayMaximum(highArray, 1, LookbackBars);
    return highArray[highestBar];
}

//+------------------------------------------------------------------+
//| Find swing low                                                   |
//+------------------------------------------------------------------+
double FindSwingLow()
{
    double lowArray[];
    ArraySetAsSeries(lowArray, true);
    
    // Copy low prices
    if(CopyLow(_Symbol, TimeFrame, 0, LookbackBars + 1, lowArray) < LookbackBars + 1)
    {
        Print("Error copying low prices");
        return 0;
    }
    
    // Find the lowest low in the lookback period
    int lowestBar = ArrayMinimum(lowArray, 1, LookbackBars);
    return lowArray[lowestBar];
}

//+------------------------------------------------------------------+
//| Check for buy signal                                             |
//+------------------------------------------------------------------+
void CheckForBuySignal()
{
    if(!EnableBuy) return;
    
    // Check if we already have a buy position
    if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        return;
    
    // Get current and previous prices
    double currentHigh = iHigh(_Symbol, TimeFrame, 0);
    double previousHigh = iHigh(_Symbol, TimeFrame, MinBreakoutBars);
    double swingHigh = FindSwingHigh();
    
    // Buy condition: current high breaks above swing high with confirmation
    if(currentHigh > swingHigh && currentHigh > previousHigh)
    {
        double entryPrice = currentTick.ask;
        double stopLoss = FindSwingLow();
        double takeProfit = entryPrice + (entryPrice - stopLoss) * RiskReward;
        
        // Validate stop loss and take profit
        if(stopLoss >= entryPrice)
        {
            Print("Invalid stop loss for buy trade");
            return;
        }
        
        ExecuteBuyOrder(entryPrice, stopLoss, takeProfit);
    }
}

//+------------------------------------------------------------------+
//| Check for sell signal                                            |
//+------------------------------------------------------------------+
void CheckForSellSignal()
{
    if(!EnableSell) return;
    
    // Check if we already have a sell position
    if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        return;
    
    // Get current and previous prices
    double currentLow = iLow(_Symbol, TimeFrame, 0);
    double previousLow = iLow(_Symbol, TimeFrame, MinBreakoutBars);
    double swingLow = FindSwingLow();
    
    // Sell condition: current low breaks below swing low with confirmation
    if(currentLow < swingLow && currentLow < previousLow)
    {
        double entryPrice = currentTick.bid;
        double stopLoss = FindSwingHigh();
        double takeProfit = entryPrice - (stopLoss - entryPrice) * RiskReward;
        
        // Validate stop loss and take profit
        if(stopLoss <= entryPrice)
        {
            Print("Invalid stop loss for sell trade");
            return;
        }
        
        ExecuteSellOrder(entryPrice, stopLoss, takeProfit);
    }
}

//+------------------------------------------------------------------+
//| Execute buy order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double entryPrice, double stopLoss, double takeProfit)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.magic = MagicNumber;
    request.comment = "Scalping Bot Buy";
    
    if(OrderSend(request, result))
    {
        Print("Buy order executed. Ticket: ", result.order);
    }
    else
    {
        Print("Error executing buy order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Execute sell order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double entryPrice, double stopLoss, double takeProfit)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.magic = MagicNumber;
    request.comment = "Scalping Bot Sell";
    
    if(OrderSend(request, result))
    {
        Print("Sell order executed. Ticket: ", result.order);
    }
    else
    {
        Print("Error executing sell order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Check for exit conditions                                        |
//+------------------------------------------------------------------+
void CheckForExit()
{
    // Check if we have any positions
    if(!PositionSelect(_Symbol)) return;
    
    // You can add additional exit conditions here if needed
    // For example, time-based exits or trailing stops
    
    // Currently, we rely on the initial stop loss and take profit
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLossPrice)
{
    // For fixed lot size, we just return the configured lot size
    return LotSize;
    
    // Alternative: risk-based position sizing (commented out)
    /*
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * 0.01; // 1% risk
    double riskPoints = MathAbs(entryPrice - stopLossPrice) / _Point;
    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOT);
    
    return riskAmount / (riskPoints * pointValue);
    */
}