//+------------------------------------------------------------------+
//|                                                  ScalingInEA.mq5 |
//|                                                      Code Wizard |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Code Wizard"
#property version   "1.00"
#property description "Professional Scaling-In Strategy EA"

//--- Input parameters
input group "=== Trading Settings ==="
input int      MagicNumber = 12345;           // Magic Number
input double   StepPoints = 100;              // Step between entries (points)
input double   StopLossPoints = 100;          // Initial Stop Loss (points)
input double   TrailPoints = 50;              // Trailing Stop (points)
input bool     UseBreakeven = true;           // Use breakeven trailing

input group "=== Position Size Settings ==="
input int      LotSizeMethod = 1;             // Lot size method: 0=Pyramid, 1=Equal, 2=Aggressive
input double   InitialLotSize = 0.01;         // Initial lot size
input bool     UseMoneyManagement = false;    // Use money management
input double   RiskPercent = 1.0;             // Risk percentage per trade
input double   LotMultiplier = 2.0;           // Lot multiplier for aggressive

input group "=== Risk Management ==="
input int      MaxPositions = 5;              // Maximum positions
input bool     CloseAllOnProfit = true;       // Close all on final target
input double   CloseAllProfitPoints = 300;    // Points to close all positions

input group "=== Additional Settings ==="
input int      Slippage = 3;                  // Slippage in points
input bool     UseTrailingStop = true;        // Enable trailing stop

//--- Global variables
double point;
double step;
double stopLoss;
double trailStop;
double closeAllProfit;
int positionsOpened = 0;
bool manualDirection = false; // false = no direction, true = long, false = short
ENUM_POSITION_TYPE currentDirection;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Calculate point value
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    if(digits == 3 || digits == 5)
        point *= 10;
    
    //--- Calculate step values
    step = StepPoints * point;
    stopLoss = StopLossPoints * point;
    trailStop = TrailPoints * point;
    closeAllProfit = CloseAllProfitPoints * point;
    
    //--- Reset counter
    positionsOpened = 0;
    manualDirection = false;
    
    Print("ScalingIn EA initialized successfully");
    Print("Point value: ", point, ", Step: ", step, ", StopLoss: ", stopLoss);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("ScalingIn EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check for new bar
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(lastBar == currentBar)
        return;
    lastBar = currentBar;
    
    //--- Manage existing positions
    ManagePositions();
    
    //--- Check for new entry signals
    CheckForEntry();
}

//+------------------------------------------------------------------+
//| Calculate position size based on method                          |
//+------------------------------------------------------------------+
double CalculateLotSize(int positionNumber)
{
    double lotSize = InitialLotSize;
    
    switch(LotSizeMethod)
    {
        case 0: // Pyramid (decreasing lots)
            lotSize = InitialLotSize / positionNumber;
            break;
            
        case 1: // Equal (same lots)
            lotSize = InitialLotSize;
            break;
            
        case 2: // Aggressive (increasing lots)
            lotSize = InitialLotSize * positionNumber;
            break;
    }
    
    //--- Apply money management if enabled
    if(UseMoneyManagement)
    {
        double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double stopLossPoints = StopLossPoints * (_Point / point);
        
        if(tickValue > 0 && stopLossPoints > 0)
        {
            double calculatedLots = riskMoney / (stopLossPoints * tickValue);
            lotSize = NormalizeDouble(calculatedLots, 2);
        }
    }
    
    //--- Ensure minimum and maximum lot sizes
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    
    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Check for entry conditions                                       |
//+------------------------------------------------------------------+
void CheckForEntry()
{
    //--- Get current positions
    int totalPositions = CountPositions();
    
    //--- If no positions and manual direction not set, wait
    if(totalPositions == 0 && !manualDirection)
        return;
    
    //--- Determine direction from first position or manual setting
    if(totalPositions == 0 && manualDirection)
    {
        // First entry based on manual direction
        OpenPosition(currentDirection);
        positionsOpened = 1;
    }
    else if(totalPositions > 0 && totalPositions < MaxPositions)
    {
        //--- Get current price and check for next entry
        double currentPrice = GetCurrentPrice();
        double lastEntryPrice = GetLastEntryPrice();
        
        if(IsLongPosition())
        {
            if(currentPrice >= lastEntryPrice + step)
            {
                OpenPosition(POSITION_TYPE_BUY);
                positionsOpened++;
            }
        }
        else if(IsShortPosition())
        {
            if(currentPrice <= lastEntryPrice - step)
            {
                OpenPosition(POSITION_TYPE_SELL);
                positionsOpened++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open new position                                                |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_POSITION_TYPE type)
{
    double lotSize = CalculateLotSize(positionsOpened + 1);
    double currentPrice = GetCurrentPrice();
    double sl = 0, tp = 0;
    
    //--- Calculate stop loss
    if(type == POSITION_TYPE_BUY)
    {
        sl = currentPrice - stopLoss;
        if(positionsOpened + 1 == MaxPositions && CloseAllOnProfit)
            tp = currentPrice + closeAllProfit;
    }
    else
    {
        sl = currentPrice + stopLoss;
        if(positionsOpened + 1 == MaxPositions && CloseAllOnProfit)
            tp = currentPrice - closeAllProfit;
    }
    
    //--- Prepare trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = currentPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = Slippage;
    request.magic = MagicNumber;
    request.comment = StringFormat("ScalePos%d", positionsOpened + 1);
    
    //--- Send order
    if(OrderSend(request, result))
    {
        Print("Position opened: ", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", 
              " Lot: ", lotSize, " Price: ", currentPrice);
        return true;
    }
    else
    {
        Print("Error opening position: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    int totalPositions = CountPositions();
    if(totalPositions == 0) return;
    
    //--- Check if we should close all positions
    if(ShouldCloseAll())
    {
        CloseAllPositions();
        return;
    }
    
    //--- Apply trailing stops
    if(UseTrailingStop)
        ApplyTrailingStops();
}

//+------------------------------------------------------------------+
//| Apply trailing stops to all positions                            |
//+------------------------------------------------------------------+
void ApplyTrailingStops()
{
    double currentPrice = GetCurrentPrice();
    double newSL = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            
            if(type == POSITION_TYPE_BUY)
            {
                newSL = currentPrice - trailStop;
                
                //--- Only move SL if it's beneficial
                if(newSL > currentSL && newSL > openPrice)
                {
                    ModifyPositionSL(ticket, newSL);
                }
                else if(UseBreakeven && currentPrice >= openPrice + trailStop && 
                       (currentSL < openPrice || currentSL == 0))
                {
                    // Move to breakeven
                    ModifyPositionSL(ticket, openPrice + (point * 10)); // Small buffer
                }
            }
            else if(type == POSITION_TYPE_SELL)
            {
                newSL = currentPrice + trailStop;
                
                //--- Only move SL if it's beneficial
                if((newSL < currentSL || currentSL == 0) && newSL < openPrice)
                {
                    ModifyPositionSL(ticket, newSL);
                }
                else if(UseBreakeven && currentPrice <= openPrice - trailStop && 
                       (currentSL > openPrice || currentSL == 0))
                {
                    // Move to breakeven
                    ModifyPositionSL(ticket, openPrice - (point * 10)); // Small buffer
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify position stop loss                                        |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double newSL)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    if(!PositionSelectByTicket(ticket))
        return false;
    
    double currentTP = PositionGetDouble(POSITION_TP);
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = currentTP;
    request.magic = MagicNumber;
    
    if(OrderSend(request, result))
    {
        Print("SL modified for ticket ", ticket, " New SL: ", newSL);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if all positions should be closed                         |
//+------------------------------------------------------------------+
bool ShouldCloseAll()
{
    if(!CloseAllOnProfit || positionsOpened < MaxPositions)
        return false;
    
    double currentPrice = GetCurrentPrice();
    double firstEntryPrice = GetFirstEntryPrice();
    
    if(IsLongPosition())
        return (currentPrice >= firstEntryPrice + closeAllProfit);
    else
        return (currentPrice <= firstEntryPrice - closeAllProfit);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ClosePosition(ticket);
        }
    }
    
    positionsOpened = 0;
    manualDirection = false;
    Print("All positions closed");
}

//+------------------------------------------------------------------+
//| Close single position                                            |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    if(!PositionSelectByTicket(ticket))
        return false;
    
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = volume;
    request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = GetCurrentPrice();
    request.deviation = Slippage;
    request.magic = MagicNumber;
    
    return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            count++;
        }
    }
    return count;
}

bool IsLongPosition()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            return (type == POSITION_TYPE_BUY);
        }
    }
    return false;
}

bool IsShortPosition()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            return (type == POSITION_TYPE_SELL);
        }
    }
    return false;
}

double GetCurrentPrice()
{
    MqlTick lastTick;
    SymbolInfoTick(_Symbol, lastTick);
    
    if(IsLongPosition() || (manualDirection && currentDirection == POSITION_TYPE_BUY))
        return lastTick.ask;
    else
        return lastTick.bid;
}

double GetLastEntryPrice()
{
    double lastPrice = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(price > lastPrice)
                lastPrice = price;
        }
    }
    return lastPrice;
}

double GetFirstEntryPrice()
{
    double firstPrice = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
           PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(firstPrice == 0 || price < firstPrice)
                firstPrice = price;
        }
    }
    return firstPrice;
}

//+------------------------------------------------------------------+
//| Manual control functions                                         |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN)
    {
        //--- B key for Buy start
        if(lparam == 66) // 'B' key
        {
            manualDirection = true;
            currentDirection = POSITION_TYPE_BUY;
            Print("Manual BUY direction set");
        }
        //--- S key for Sell start
        else if(lparam == 83) // 'S' key
        {
            manualDirection = true;
            currentDirection = POSITION_TYPE_SELL;
            Print("Manual SELL direction set");
        }
        //--- C key to close all
        else if(lparam == 67) // 'C' key
        {
            CloseAllPositions();
        }
    }
}
//+------------------------------------------------------------------+