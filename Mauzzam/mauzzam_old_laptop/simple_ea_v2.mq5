//+------------------------------------------------------------------+
//|                                          EnhancedScalpingBot.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "2.00"

// Input parameters
input double LotSize = 0.01;               // Lot size for trading (0 = auto calculate)
input double RiskPercent = 1.0;            // Risk percentage per trade (if LotSize=0)
input int LookbackBars = 20;               // Number of bars to look back for swing points
input int SwingValidationBars = 3;         // Bars on each side to validate swing point
input int MinBreakoutBars = 5;             // Minimum bars for breakout confirmation
input double RiskReward = 2.0;             // Risk to reward ratio
input int my_sl = 5;                        // My Stop Loss (5$)
input int my_tp = 5;                         //My Take Profit (5$)
input int mybreakeven_points = 150;          // My BreakEven Points (150 points)
input int MaxSpread = 15;                  // Maximum allowed spread in points
input int MagicNumber = 123457;            // Magic number for trade identification
input bool EnableBuy = true;               // Enable buy trades
input bool EnableSell = true;              // Enable sell trades
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M15; // Trading time frame

// Trailing Stop Parameters
input bool EnableTrailingStop = true;      // Enable trailing stop loss
input int TrailStartPips = 20;             // Pips profit to start trailing (0=immediately)
input int TrailStepPips = 10;              // Pips to move stop loss when trailing
input bool MoveToBreakeven = true;         // Move SL to breakeven at specified profit
input int BreakevenTriggerPips = 10;       // Pips profit to trigger breakeven
input bool PartialCloseAtRR = true;        // Close partial at risk reward targets
input double PartialClosePercent = 50.0;   // Percentage to close at first target

// Risk Management
input int MaxPositions = 1;                // Maximum simultaneous positions
input double DailyLossLimit = 5.0;         // Max daily loss percentage
input double DailyProfitTarget = 10.0;     // Daily profit target percentage
input bool UseSessionFilter = true;        // Filter by trading sessions
input string SessionStart = "08:00";       // Trading session start (broker time)
input string SessionEnd = "17:00";         // Trading session end (broker time)

// Global variables
double dailyProfitLoss = 0.0;
double dailyStartingBalance = 0.0;
datetime lastDailyReset = 0;
int swingPointsArraySize = 0;
double swingHighs[], swingLows[];
MqlTick currentTick;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Check input parameters
    if(LotSize < 0)
    {
        Print("Error: LotSize must be greater than or equal to 0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(LookbackBars <= SwingValidationBars * 2)
    {
        Print("Error: LookbackBars must be greater than 2 * SwingValidationBars");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(RiskReward <= 0)
    {
        Print("Error: RiskReward must be greater than 0");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    if(RiskPercent <= 0 || RiskPercent > 10)
    {
        Print("Error: RiskPercent must be between 0.1 and 10");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    // Initialize swing point arrays
    swingPointsArraySize = LookbackBars + 10;
    ArrayResize(swingHighs, swingPointsArraySize);
    ArrayResize(swingLows, swingPointsArraySize);
    ArrayInitialize(swingHighs, 0);
    ArrayInitialize(swingLows, 0);
    
    // Initialize daily tracking
    InitializeDailyTracking();
    
    Print("Enhanced Scalping Bot v2.0 initialized successfully");
    Print("Strategy: Swing Breakout with Advanced Trailing");
    Print("Session Time: ", SessionStart, " - ", SessionEnd);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Enhanced Scalping Bot deinitialized");
    Print("Final Daily P/L: $", dailyProfitLoss);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update daily tracking
    UpdateDailyTracking();
    
    // Check daily limits
    if(CheckDailyLimits()) return;
    
    // Get current tick information
    if(!SymbolInfoTick(_Symbol, currentTick))
    {
        Print("Error getting tick information");
        return;
    }
    
    // Check spread
    int currentSpread = (int)((currentTick.ask - currentTick.bid) / _Point);
    if(currentSpread > MaxSpread)
    {
        Comment("Spread too high: ", currentSpread, " points (Max: ", MaxSpread, ")");
        return;
    }
    
    // Check session time
    if(UseSessionFilter && !IsTradingSession())
    {
        Comment("Outside trading session");
        return;
    }
    
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, TimeFrame, 0);
    if(currentBarTime == lastBarTime)
    {
        // On every tick, check trailing stops
        if(EnableTrailingStop) ManageTrailingStops();
        return;
    }
    
    lastBarTime = currentBarTime;
    
    // Update swing points on new bar
    UpdateSwingPoints();
    
    // Display information
    DisplayInfo(currentSpread);
    
    // Check for trading opportunities
    if(CountPositions() < MaxPositions)
    {
        CheckForBuySignal();
        CheckForSellSignal();
    }
    
    // Manage trailing stops
    if(EnableTrailingStop) ManageTrailingStops();
}

//+------------------------------------------------------------------+
//| Initialize daily tracking                                        |
//+------------------------------------------------------------------+
void InitializeDailyTracking()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    lastDailyReset = StructToTime(dt);
    
    dailyStartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dailyProfitLoss = 0.0;
}

//+------------------------------------------------------------------+
//| Update daily tracking                                            |
//+------------------------------------------------------------------+
void UpdateDailyTracking()
{
    datetime currentTime = TimeCurrent();
    if(currentTime >= lastDailyReset + 86400) // New day
    {
        dailyStartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dailyProfitLoss = 0.0;
        lastDailyReset = currentTime;
        Print("Daily tracking reset. New starting balance: $", dailyStartingBalance);
    }
    
    // Calculate today's P/L
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dailyProfitLoss = currentBalance - dailyStartingBalance;
}

//+------------------------------------------------------------------+
//| Check daily limits                                               |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPLPercent = (dailyProfitLoss / dailyStartingBalance) * 100;
    
    // Check daily loss limit
    if(dailyPLPercent <= -DailyLossLimit)
    {
        CloseAllPositions();
        Comment("Daily loss limit reached: ", DoubleToString(dailyPLPercent, 2), "%");
        return true;
    }
    
    // Check daily profit target
    if(dailyPLPercent >= DailyProfitTarget)
    {
        Comment("Daily profit target reached: ", DoubleToString(dailyPLPercent, 2), "%");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    string currentTimeStr = StringFormat("%02d:%02d", dt.hour, dt.min);
    
    return (currentTimeStr >= SessionStart && currentTimeStr <= SessionEnd);
}

//+------------------------------------------------------------------+
//| Update swing points                                              |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
    // Clear arrays
    ArrayInitialize(swingHighs, 0);
    ArrayInitialize(swingLows, 0);
    
    // Get price data
    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    
    int barsToCopy = LookbackBars + SwingValidationBars * 2 + 10;
    
    if(CopyHigh(_Symbol, TimeFrame, 0, barsToCopy, highs) < barsToCopy ||
       CopyLow(_Symbol, TimeFrame, 0, barsToCopy, lows) < barsToCopy)
    {
        Print("Error copying price data for swing points");
        return;
    }
    
    // Find swing highs
    for(int i = SwingValidationBars; i < LookbackBars + SwingValidationBars; i++)
    {
        bool isSwingHigh = true;
        
        // Check left side
        for(int j = 1; j <= SwingValidationBars; j++)
        {
            if(highs[i] <= highs[i - j])
            {
                isSwingHigh = false;
                break;
            }
        }
        
        // Check right side
        if(isSwingHigh)
        {
            for(int j = 1; j <= SwingValidationBars; j++)
            {
                if(highs[i] <= highs[i + j])
                {
                    isSwingHigh = false;
                    break;
                }
            }
        }
        
        if(isSwingHigh)
        {
            swingHighs[i - SwingValidationBars] = highs[i];
        }
    }
    
    // Find swing lows
    for(int i = SwingValidationBars; i < LookbackBars + SwingValidationBars; i++)
    {
        bool isSwingLow = true;
        
        // Check left side
        for(int j = 1; j <= SwingValidationBars; j++)
        {
            if(lows[i] >= lows[i - j])
            {
                isSwingLow = false;
                break;
            }
        }
        
        // Check right side
        if(isSwingLow)
        {
            for(int j = 1; j <= SwingValidationBars; j++)
            {
                if(lows[i] >= lows[i + j])
                {
                    isSwingLow = false;
                    break;
                }
            }
        }
        
        if(isSwingLow)
        {
            swingLows[i - SwingValidationBars] = lows[i];
        }
    }
}

//+------------------------------------------------------------------+
//| Find latest valid swing high                                     |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
    for(int i = 0; i < LookbackBars; i++)
    {
        if(swingHighs[i] > 0)
        {
            return swingHighs[i];
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Find latest valid swing low                                      |
//+------------------------------------------------------------------+
double FindSwingLow()
{
    for(int i = 0; i < LookbackBars; i++)
    {
        if(swingLows[i] > 0)
        {
            return swingLows[i];
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Count current positions                                          |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count positions by type                                          |
//+------------------------------------------------------------------+
int CountPositionsByType(int positionType)
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && 
           PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
           PositionGetInteger(POSITION_TYPE) == positionType)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check for buy signal                                             |
//+------------------------------------------------------------------+
void CheckForBuySignal()
{
    if(!EnableBuy || CountPositionsByType(POSITION_TYPE_BUY) >= MaxPositions) return;
    
    // Get current and previous prices
    double currentHigh = iHigh(_Symbol, TimeFrame, 0);
    double previousHigh = iHigh(_Symbol, TimeFrame, MinBreakoutBars);
    double swingHigh = FindSwingHigh();
    
    // Additional confirmation: check if we're in an uptrend
    double maFast = iMA(_Symbol, TimeFrame, 10, 0, MODE_SMA, PRICE_CLOSE);
    double maSlow = iMA(_Symbol, TimeFrame, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    if(swingHigh > 0 && currentHigh > swingHigh && currentHigh > previousHigh && maFast > maSlow)
    {
        double entryPrice = currentTick.ask;
        double stopLoss = FindSwingLow();
        double takeProfit = entryPrice + (entryPrice - stopLoss) * RiskReward;
        
        // Validate stop loss and take profit
        if(stopLoss >= entryPrice - 10 * _Point) // Minimum 10 pips distance
        {
            Print("Invalid stop loss for buy trade: ", stopLoss, " >= ", entryPrice);
            return;
        }
        
        // Calculate position size
        double positionSize = CalculatePositionSize(entryPrice, stopLoss);
        
        if(positionSize > 0)
        {
            stopLoss = entryPrice - my_sl;
            takeProfit = entryPrice + my_tp;
            ExecuteBuyOrder(entryPrice, stopLoss, takeProfit, positionSize);
            
            ExecuteSellOrder(entryPrice,takeProfit,stopLoss,positionSize);//hedge position
        }
    }
}

//+------------------------------------------------------------------+
//| Check for sell signal                                            |
//+------------------------------------------------------------------+
void CheckForSellSignal()
{
    if(!EnableSell || CountPositionsByType(POSITION_TYPE_SELL) >= MaxPositions) return;
    
    // Get current and previous prices
    double currentLow = iLow(_Symbol, TimeFrame, 0);
    double previousLow = iLow(_Symbol, TimeFrame, MinBreakoutBars);
    double swingLow = FindSwingLow();
    
    // Additional confirmation: check if we're in a downtrend
    double maFast = iMA(_Symbol, TimeFrame, 10, 0, MODE_SMA, PRICE_CLOSE);
    double maSlow = iMA(_Symbol, TimeFrame, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    if(swingLow > 0 && currentLow < swingLow && currentLow < previousLow && maFast < maSlow)
    {
        double entryPrice = currentTick.bid;
        double stopLoss = FindSwingHigh();
        double takeProfit = entryPrice - (stopLoss - entryPrice) * RiskReward;
        
        // Validate stop loss and take profit
        if(stopLoss <= entryPrice + 10 * _Point) // Minimum 10 pips distance
        {
            Print("Invalid stop loss for sell trade: ", stopLoss, " <= ", entryPrice);
            return;
        }
        
        // Calculate position size
        double positionSize = CalculatePositionSize(entryPrice, stopLoss);
        
        if(positionSize > 0)
        {
            //ExecuteSellOrder(entryPrice, stopLoss, takeProfit, positionSize);
            stopLoss = entryPrice + my_sl;
            takeProfit = entryPrice - my_tp;
            ExecuteSellOrder(entryPrice, stopLoss, takeProfit, positionSize);
            
            ExecuteBuyOrder(entryPrice,takeProfit,stopLoss,positionSize);//extra hedge
        }
    }
}

//+------------------------------------------------------------------+
//| Execute buy order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double entryPrice, double stopLoss, double takeProfit, double lotSize)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.magic = MagicNumber;
    request.comment = "SwingBreakout Buy";
    request.type_filling = ORDER_FILLING_IOC;
    
    if(OrderSend(request, result))
    {
        Print("Buy order executed. Ticket: ", result.order, 
              " SL: ", stopLoss, " TP: ", takeProfit,
              " Risk: $", (entryPrice - stopLoss) / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * lotSize);
    }
    else
    {
        Print("Error executing buy order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Execute sell order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double entryPrice, double stopLoss, double takeProfit, double lotSize)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = entryPrice;
    request.sl = stopLoss;
    request.tp = takeProfit;
    request.magic = MagicNumber;
    request.comment = "SwingBreakout Sell";
    request.type_filling = ORDER_FILLING_IOC;
    
    if(OrderSend(request, result))
    {
        Print("Sell order executed. Ticket: ", result.order,
              " SL: ", stopLoss, " TP: ", takeProfit,
              " Risk: $", (stopLoss - entryPrice) / _Point * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * lotSize);
    }
    else
    {
        Print("Error executing sell order: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLossPrice)
{
    // If LotSize > 0, use fixed lot size
    if(LotSize > 0) return LotSize;
    
    // Otherwise calculate based on risk percentage
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
    double riskPoints = MathAbs(entryPrice - stopLossPrice) / _Point;
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(riskPoints <= 0 || tickValue <= 0)
    {
        Print("Error calculating position size");
        return 0.01; // Default minimum
    }
    
    double positionSize = riskAmount / (riskPoints * tickValue);
    
    // Normalize to allowed lot step
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    positionSize = MathFloor(positionSize / lotStep) * lotStep;
    
    // Check minimum and maximum limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    positionSize = MathMax(positionSize, minLot);
    positionSize = MathMin(positionSize, maxLot);
    
    return positionSize;
}

//+------------------------------------------------------------------+
//| Manage trailing stops                                            |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            long type = PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            double currentPrice = (type == POSITION_TYPE_BUY) ? currentTick.bid : currentTick.ask;
            double profitInPoints = (type == POSITION_TYPE_BUY) ? 
                                   (currentPrice - openPrice) / _Point :
                                   (openPrice - currentPrice) / _Point;
            
            // Convert pips to points (assuming 1 pip = 10 points for 5 digit brokers)
            int trailStartPoints = TrailStartPips * 10;
            int breakevenTriggerPoints = BreakevenTriggerPips * 10;
            int trailStepPoints = TrailStepPips * 10;
            
            // Check if we should move to breakeven
            if(MoveToBreakeven && profitInPoints >= breakevenTriggerPoints)
            {
                
                double breakevenPrice = openPrice + (type == POSITION_TYPE_BUY ? mybreakeven_points * _Point : -mybreakeven_points * _Point);
                
                // For buy positions, SL should be below entry; for sell, above entry
                if((type == POSITION_TYPE_BUY && (currentSL < breakevenPrice || currentSL == 0)) ||
                   (type == POSITION_TYPE_SELL && (currentSL > breakevenPrice || currentSL == 0)))
                {
                    if(ModifyPositionSL(ticket, breakevenPrice))
                    {
                        Print("Moved to breakeven. Ticket: ", ticket, " New SL: ", breakevenPrice);
                    }
                }
            }
            
            // Check if we should start trailing
            if(profitInPoints >= trailStartPoints)
            {
                double newStopLoss = 0;
                
                if(type == POSITION_TYPE_BUY)
                {
                    // For buy positions, trail below current price
                    double proposedSL = currentPrice - trailStepPoints * _Point;
                    if(proposedSL > currentSL && proposedSL > openPrice)
                    {
                        newStopLoss = proposedSL;
                    }
                }
                else // POSITION_TYPE_SELL
                {
                    // For sell positions, trail above current price
                    double proposedSL = currentPrice + trailStepPoints * _Point;
                    if(proposedSL < currentSL && proposedSL < openPrice)
                    {
                        newStopLoss = proposedSL;
                    }
                }
                
                if(newStopLoss != 0)
                {
                    if(ModifyPositionSL(ticket, newStopLoss))
                    {
                        Print("Trailing stop updated. Ticket: ", ticket, 
                              " New SL: ", newStopLoss, " Profit: ", profitInPoints, " points");
                    }
                }
            }
            
            // Check for partial close at 50% profit target
            if(PartialCloseAtRR)
            {
                double initialRisk = MathAbs(openPrice - PositionGetDouble(POSITION_PRICE_OPEN));
                double firstTargetDistance = initialRisk * (RiskReward * 0.5); // 50% of full target
                double firstTargetPrice = (type == POSITION_TYPE_BUY) ? 
                                         openPrice + firstTargetDistance :
                                         openPrice - firstTargetDistance;
                
                if((type == POSITION_TYPE_BUY && currentPrice >= firstTargetPrice && currentPrice < currentTP) ||
                   (type == POSITION_TYPE_SELL && currentPrice <= firstTargetPrice && currentPrice > currentTP))
                {
                    ClosePartialPosition(ticket, PartialClosePercent);
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
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    if(!PositionSelectByTicket(ticket)) return false;
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.magic = MagicNumber;
    
    return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Close partial position                                           |
//+------------------------------------------------------------------+
void ClosePartialPosition(ulong ticket, double percent)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    double currentVolume = PositionGetDouble(POSITION_VOLUME);
    double closeVolume = currentVolume * (percent / 100.0);
    
    // Normalize volume to lot step
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
    
    if(closeVolume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    long type = PositionGetInteger(POSITION_TYPE);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = closeVolume;
    request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (type == POSITION_TYPE_BUY) ? currentTick.bid : currentTick.ask;
    request.position = ticket;
    request.magic = MagicNumber;
    request.comment = "Partial Close";
    
    if(OrderSend(request, result))
    {
        Print("Partial close executed. Ticket: ", ticket, 
              " Volume: ", closeVolume, " (", percent, "%)");
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            long type = PositionGetInteger(POSITION_TYPE);
            
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (type == POSITION_TYPE_BUY) ? currentTick.bid : currentTick.ask;
            request.position = ticket;
            request.magic = MagicNumber;
            request.comment = "Daily Limit Close";
            
            OrderSend(request, result);
        }
    }
}

//+------------------------------------------------------------------+
//| Display information                                              |
//+------------------------------------------------------------------+
void DisplayInfo(int spread)
{
    string comment = "Enhanced Scalping Bot v2.0\n";
    comment += "===========================\n";
    comment += "Spread: " + IntegerToString(spread) + " points\n";
    comment += "Daily P/L: $" + DoubleToString(dailyProfitLoss, 2) + 
               " (" + DoubleToString((dailyProfitLoss/dailyStartingBalance)*100, 2) + "%)\n";
    comment += "Positions: " + IntegerToString(CountPositions()) + "/" + IntegerToString(MaxPositions) + "\n";
    comment += "Swing High: " + DoubleToString(FindSwingHigh(), _Digits) + "\n";
    comment += "Swing Low: " + DoubleToString(FindSwingLow(), _Digits) + "\n";
    
    if(UseSessionFilter)
    {
        comment += "Session: " + (IsTradingSession() ? "ACTIVE" : "CLOSED") + "\n";
    }
    
    Comment(comment);
}