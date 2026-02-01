//+------------------------------------------------------------------+
//|                                          EnhancedMACDCrossoverEA |
//|                                                       Copyright 2024 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
//--- Risk Management
input double RiskPercentage = 2.0;           // Risk percentage per trade (1-3%)
input bool UseFixedLot = false;              // Use fixed lot size?
input double FixedLotSize = 0.1;             // Fixed lot size if enabled
input double MaxLotSize = 5.0;               // Maximum lot size
input double MinLotSize = 0.01;              // Minimum lot size

//--- Stop Loss & Take Profit
input bool UseFixedSLTP = false;             // Use fixed SL/TP in points?
input int FixedStopLossPoints = 150;         // Fixed Stop Loss in points
input int FixedTakeProfitPoints = 300;       // Fixed Take Profit in points
input double RiskRewardRatio = 2.0;          // Risk/Reward ratio (1.5-3.0)
input int TrailingStopPoints = 100;          // Trailing stop in points (0=disabled)
input int BreakEvenPoints = 50;              // Break-even activation in points

//--- MACD Parameters
input int FastEMA = 12;                      // MACD Fast EMA period
input int SlowEMA = 26;                      // MACD Slow EMA period
input int SignalSMA = 9;                     // MACD Signal SMA period
input ENUM_APPLIED_PRICE MACDPrice = PRICE_CLOSE; // MACD applied price

//--- Trend Filter Parameters
input bool UseTrendFilter = true;            // Enable trend filtering
input int TrendMAPeriod = 200;               // Trend MA period
input ENUM_MA_METHOD TrendMAMethod = MODE_EMA; // Trend MA method
input ENUM_APPLIED_PRICE TrendMAPrice = PRICE_CLOSE; // Trend MA applied price

//--- Volume Filter
input bool UseVolumeFilter = true;           // Enable volume filtering
input double MinVolumeRatio = 1.2;           // Minimum volume ratio vs average

//--- Time Filter
input bool UseTimeFilter = true;             // Enable time filtering
input string TradeStartTime = "08:00";       // Trading start time (Broker time)
input string TradeEndTime = "20:00";         // Trading end time (Broker time)

//--- Trade Management
input int MaxTradesPerDay = 3;               // Maximum trades per day
input int MinBarsBetweenTrades = 2;          // Minimum bars between trades
input bool CloseOnOppositeSignal = true;     // Close on opposite signal

//--- Advanced
input int Slippage = 3;                      // Slippage in points
input int MagicNumber = 2024;                // Magic number
input string TradeComment = "EnhancedMACD";  // Trade comment

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int macdHandle, trendMAHandle, adxHandle;
double macdMain[], macdSignal[], trendMA[], adxValues[];
datetime lastTradeTime = 0;
int tradesToday = 0;
datetime lastTradeDate = 0;
string eaName = "Enhanced_MACD_Crossover_EA";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize MACD indicator
    macdHandle = iMACD(_Symbol, PERIOD_H1, FastEMA, SlowEMA, SignalSMA, MACDPrice);
    if(macdHandle == INVALID_HANDLE)
    {
        Print("Error creating MACD indicator handle");
        return(INIT_FAILED);
    }
    
    // Initialize trend filter MA
    if(UseTrendFilter)
    {
        trendMAHandle = iMA(_Symbol, PERIOD_H1, TrendMAPeriod, 0, TrendMAMethod, TrendMAPrice);
        if(trendMAHandle == INVALID_HANDLE)
        {
            Print("Error creating Trend MA indicator handle");
            return(INIT_FAILED);
        }
    }
    
    // Initialize ADX for trend strength
    adxHandle = iADX(_Symbol, PERIOD_H1, 14);
    if(adxHandle == INVALID_HANDLE)
    {
        Print("Error creating ADX indicator handle");
        return(INIT_FAILED);
    }
    
    // Set arrays as series
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    ArraySetAsSeries(trendMA, true);
    ArraySetAsSeries(adxValues, true);
    
    Print(eaName + " initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(macdHandle != INVALID_HANDLE)
        IndicatorRelease(macdHandle);
    if(trendMAHandle != INVALID_HANDLE)
        IndicatorRelease(trendMAHandle);
    if(adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
    
    Print(eaName + " deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check trading conditions
    if(!IsTradingAllowed()) return;
    if(!IsNewBar(PERIOD_H1)) return;
    
    // Update daily trade count
    UpdateDailyTradeCount();
    
    // Check if we've reached daily trade limit
    if(tradesToday >= MaxTradesPerDay)
    {
        Print("Daily trade limit reached: ", tradesToday, "/", MaxTradesPerDay);
        return;
    }
    
    // Get indicator values
    if(!GetIndicatorValues()) return;
    
    // Check for trading signals
    CheckForTradingSignals();
    
    // Manage open positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    // Check if expert is allowed to trade
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("Trading not allowed. Check AutoTrading setting.");
        return false;
    }
    
    // Check if connected to trade server
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        Print("Not connected to trade server");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, timeframe, 0);
    
    if(lastBarTime != currentBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update daily trade count                                         |
//+------------------------------------------------------------------+
void UpdateDailyTradeCount()
{
    MqlDateTime currentTime;
    TimeCurrent(currentTime);
    
    if(lastTradeDate != currentTime.day)
    {
        tradesToday = 0;
        lastTradeDate = currentTime.day;
        Print("New trading day - reset trade count");
    }
}

//+------------------------------------------------------------------+
//| Get indicator values                                             |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
    // Get MACD values
    if(CopyBuffer(macdHandle, MAIN_LINE, 0, 5, macdMain) < 5 ||
       CopyBuffer(macdHandle, SIGNAL_LINE, 0, 5, macdSignal) < 5)
    {
        Print("Error copying MACD buffers");
        return false;
    }
    
    // Get trend MA values if enabled
    if(UseTrendFilter)
    {
        if(CopyBuffer(trendMAHandle, 0, 0, 3, trendMA) < 3)
        {
            Print("Error copying Trend MA buffer");
            return false;
        }
    }
    
    // Get ADX values for trend strength
    if(CopyBuffer(adxHandle, 0, 0, 3, adxValues) < 3)
    {
        Print("Error copying ADX buffer");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckForTradingSignals()
{
    // Check basic trading conditions
    if(!CheckTradingConditions()) return;
    
    // Detect MACD crossover
    bool bullishCrossover = (macdMain[2] < macdSignal[2] && macdMain[1] > macdSignal[1]);
    bool bearishCrossover = (macdMain[2] > macdSignal[2] && macdMain[1] < macdSignal[1]);
    
    if(!bullishCrossover && !bearishCrossover) return;
    
    // Additional confirmation checks
    if(bullishCrossover && IsBullishSignalConfirmed())
    {
        OpenTrade(ORDER_TYPE_BUY);
    }
    else if(bearishCrossover && IsBearishSignalConfirmed())
    {
        OpenTrade(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Check bullish signal confirmation                                |
//+------------------------------------------------------------------+
bool IsBullishSignalConfirmed()
{
    // Price above crossover point
    double crossoverPrice = iLow(_Symbol, PERIOD_H1, 1);
    double currentClose = iClose(_Symbol, PERIOD_H1, 0);
    if(currentClose <= crossoverPrice) 
    {
        Print("Bullish signal rejected: Price not above crossover point");
        return false;
    }
    
    // Trend filter
    if(UseTrendFilter)
    {
        double currentPrice = iClose(_Symbol, PERIOD_H1, 0);
        if(currentPrice <= trendMA[0]) 
        {
            Print("Bullish signal rejected: Price below trend MA");
            return false;
        }
    }
    
    // Volume filter
    if(UseVolumeFilter && !IsVolumeAboveAverage()) 
    {
        Print("Bullish signal rejected: Volume below average");
        return false;
    }
    
    // MACD momentum confirmation
    if(macdMain[0] < 0) 
    {
        Print("Bullish signal rejected: MACD below zero");
        return false;
    }
    
    Print("Bullish signal confirmed");
    return true;
}

//+------------------------------------------------------------------+
//| Check bearish signal confirmation                                |
//+------------------------------------------------------------------+
bool IsBearishSignalConfirmed()
{
    // Price below crossover point
    double crossoverPrice = iHigh(_Symbol, PERIOD_H1, 1);
    double currentClose = iClose(_Symbol, PERIOD_H1, 0);
    if(currentClose >= crossoverPrice) 
    {
        Print("Bearish signal rejected: Price not below crossover point");
        return false;
    }
    
    // Trend filter
    if(UseTrendFilter)
    {
        double currentPrice = iClose(_Symbol, PERIOD_H1, 0);
        if(currentPrice >= trendMA[0]) 
        {
            Print("Bearish signal rejected: Price above trend MA");
            return false;
        }
    }
    
    // Volume filter
    if(UseVolumeFilter && !IsVolumeAboveAverage()) 
    {
        Print("Bearish signal rejected: Volume below average");
        return false;
    }
    
    // MACD momentum confirmation
    if(macdMain[0] > 0) 
    {
        Print("Bearish signal rejected: MACD above zero");
        return false;
    }
    
    Print("Bearish signal confirmed");
    return true;
}

//+------------------------------------------------------------------+
//| Check volume conditions                                          |
//+------------------------------------------------------------------+
bool IsVolumeAboveAverage()
{
    double currentVolume = iRealVolume(_Symbol, PERIOD_H1, 0);
    
    // Calculate 20-period average volume
    double avgVolume = 0;
    for(int i = 1; i <= 20; i++)
    {
        avgVolume += iRealVolume(_Symbol, PERIOD_H1, i);
    }
    avgVolume /= 20.0;
    
    if(avgVolume == 0) return true; // Avoid division by zero
    
    return (currentVolume >= avgVolume * MinVolumeRatio);
}

//+------------------------------------------------------------------+
//| Get real volume                                                  |
//+------------------------------------------------------------------+
long iRealVolume(string symbol, ENUM_TIMEFRAMES timeframe, int shift)
{
    long volume_array[];
    ArraySetAsSeries(volume_array, true);
    CopyTickVolume(symbol, timeframe, 0, shift+1, volume_array);
    return volume_array[shift];
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
    // Time filter
    if(UseTimeFilter && !IsWithinTradingHours()) 
    {
        Print("Trading condition failed: Outside trading hours");
        return false;
    }
    
    // Check minimum bars between trades
    if(GetBarsSinceLastTrade() < MinBarsBetweenTrades) 
    {
        Print("Trading condition failed: Minimum bars between trades not met");
        return false;
    }
    
    // Check if market is trending
    if(IsMarketFlat()) 
    {
        Print("Trading condition failed: Market is flat");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime currentTimeStruct;
    TimeCurrent(currentTimeStruct);
    
    int currentHour = currentTimeStruct.hour;
    int currentMin = currentTimeStruct.min;
    
    int startHour = (int)StringSubstr(TradeStartTime, 0, 2);
    int startMin = (int)StringSubstr(TradeStartTime, 3, 2);
    int endHour = (int)StringSubstr(TradeEndTime, 0, 2);
    int endMin = (int)StringSubstr(TradeEndTime, 3, 2);
    
    int currentTotalMins = currentHour * 60 + currentMin;
    int startTotalMins = startHour * 60 + startMin;
    int endTotalMins = endHour * 60 + endMin;
    
    return (currentTotalMins >= startTotalMins && currentTotalMins <= endTotalMins);
}

//+------------------------------------------------------------------+
//| Check if market is flat                                          |
//+------------------------------------------------------------------+
bool IsMarketFlat()
{
    // Market is flat if ADX < 25 (weak trend)
    return (adxValues[0] < 25);
}

//+------------------------------------------------------------------+
//| Get bars since last trade                                        |
//+------------------------------------------------------------------+
int GetBarsSinceLastTrade()
{
    if(lastTradeTime == 0) return 1000; // No previous trades
    
    return Bars(_Symbol, PERIOD_H1, lastTradeTime, TimeCurrent());
}

//+------------------------------------------------------------------+
//| Open trade                                                       |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
    // Calculate position size based on risk
    double lotSize = CalculatePositionSize();
    if(lotSize <= 0) 
    {
        Print("Error: Invalid lot size calculation");
        return;
    }
    
    // Calculate SL and TP
    double entryPrice = (orderType == ORDER_TYPE_BUY) ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double sl = CalculateStopLoss(orderType, entryPrice);
    double tp = CalculateTakeProfit(orderType, entryPrice, sl);
    
    // Prepare trade request
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = orderType;
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = Slippage;
    request.magic = MagicNumber;
    request.comment = TradeComment;
    
    // Send trade
    if(OrderSend(request, result))
    {
        if(result.retcode == 10009) // TRADE_RETCODE_DONE
        {
            lastTradeTime = TimeCurrent();
            tradesToday++;
            Print("Trade opened successfully: ", EnumToString(orderType), 
                  " Lot: ", lotSize, 
                  " Price: ", result.price,
                  " SL: ", sl, 
                  " TP: ", tp);
        }
        else
        {
            Print("Trade opening failed: ", GetRetcodeDescription(result.retcode));
        }
    }
    else
    {
        Print("OrderSend failed: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculatePositionSize()
{
    if(UseFixedLot) return FixedLotSize;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * (RiskPercentage / 100.0);
    
    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * 
                       (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
    
    double stopLossPoints = FixedStopLossPoints;
    if(stopLossPoints == 0) stopLossPoints = 100; // Default
    
    double riskPoints = stopLossPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double lotSize = riskAmount / (riskPoints * pointValue);
    
    lotSize = NormalizeDouble(lotSize, 2);
    lotSize = MathMin(MathMax(lotSize, MinLotSize), MaxLotSize);
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
    if(!UseFixedSLTP) 
    {
        // Use recent support/resistance levels
        if(orderType == ORDER_TYPE_BUY)
            return iLow(_Symbol, PERIOD_H1, iLowest(_Symbol, PERIOD_H1, MODE_LOW, 10, 1));
        else
            return iHigh(_Symbol, PERIOD_H1, iHighest(_Symbol, PERIOD_H1, MODE_HIGH, 10, 1));
    }
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(orderType == ORDER_TYPE_BUY)
        return entryPrice - (FixedStopLossPoints * point);
    else
        return entryPrice + (FixedStopLossPoints * point);
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss)
{
    if(!UseFixedSLTP)
    {
        double risk = MathAbs(entryPrice - stopLoss);
        double reward = risk * RiskRewardRatio;
        
        if(orderType == ORDER_TYPE_BUY)
            return entryPrice + reward;
        else
            return entryPrice - reward;
    }
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(orderType == ORDER_TYPE_BUY)
        return entryPrice + (FixedTakeProfitPoints * point);
    else
        return entryPrice - (FixedTakeProfitPoints * point);
}

//+------------------------------------------------------------------+
//| Manage positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            double currentProfit = PositionGetDouble(POSITION_PROFIT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            
            // Trailing stop
            if(TrailingStopPoints > 0)
                ApplyTrailingStop(ticket, openPrice, currentPrice);
            
            // Break-even
            if(BreakEvenPoints > 0)
                ApplyBreakEven(ticket, openPrice, currentPrice, currentProfit);
            
            // Close on opposite signal
            if(CloseOnOppositeSignal)
                CheckForEarlyExit(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop(ulong ticket, double openPrice, double currentPrice)
{
    double currentSL = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int positionType = PositionGetInteger(POSITION_TYPE);
    
    if(positionType == POSITION_TYPE_BUY)
    {
        double newSL = currentPrice - (TrailingStopPoints * point);
        if(newSL > currentSL && newSL > openPrice)
        {
            ModifyStopLoss(ticket, newSL);
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double newSL = currentPrice + (TrailingStopPoints * point);
        if(newSL < currentSL && newSL < openPrice)
        {
            ModifyStopLoss(ticket, newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| Apply break-even                                                 |
//+------------------------------------------------------------------+
void ApplyBreakEven(ulong ticket, double openPrice, double currentPrice, double currentProfit)
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int positionType = PositionGetInteger(POSITION_TYPE);
    double currentSL = PositionGetDouble(POSITION_SL);
    
    if(positionType == POSITION_TYPE_BUY)
    {
        double profitPoints = (currentPrice - openPrice) / point;
        if(profitPoints >= BreakEvenPoints && currentSL < openPrice)
        {
            ModifyStopLoss(ticket, openPrice + (10 * point)); // Move to break-even + small buffer
        }
    }
    else if(positionType == POSITION_TYPE_SELL)
    {
        double profitPoints = (openPrice - currentPrice) / point;
        if(profitPoints >= BreakEvenPoints && currentSL > openPrice)
        {
            ModifyStopLoss(ticket, openPrice - (10 * point)); // Move to break-even - small buffer
        }
    }
}

//+------------------------------------------------------------------+
//| Modify stop loss                                                 |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket, double newSL)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.magic = MagicNumber;
    
    if(OrderSend(request, result))
    {
        if(result.retcode == 10009)
            Print("Stop loss modified successfully for ticket: ", ticket);
        else
            Print("Stop loss modification failed: ", GetRetcodeDescription(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Check for early exit                                             |
//+------------------------------------------------------------------+
void CheckForEarlyExit(ulong ticket)
{
    int positionType = PositionGetInteger(POSITION_TYPE);
    
    // Check for opposite MACD signal
    if((positionType == POSITION_TYPE_BUY && macdMain[0] < macdSignal[0]) ||
       (positionType == POSITION_TYPE_SELL && macdMain[0] > macdSignal[0]))
    {
        ClosePosition(ticket, "Early exit - opposite signal");
    }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                   ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (request.type == ORDER_TYPE_BUY) ? 
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.deviation = Slippage;
    request.magic = MagicNumber;
    request.comment = reason;
    
    if(OrderSend(request, result))
    {
        if(result.retcode == 10009)
            Print("Position closed: ", reason);
        else
            Print("Position close failed: ", GetRetcodeDescription(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Get description for return codes                                 |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
    switch(retcode)
    {
        case 10004: return "Requote";
        case 10006: return "Request rejected";
        case 10014: return "Not enough money";
        case 10015: return "Invalid price";
        case 10016: return "Invalid stops";
        case 10018: return "Price changed";
        case 10010: return "Timeout";
        case 10009: return "Order sent successfully";
        case 10008: return "Request canceled";
        case 10013: return "Invalid volume";
        case 10019: return "Broker busy";
        case 10020: return "Invalid request";
        case 10021: return "Not enough rights";
        case 10023: return "Market closed";
        case 10024: return "Hedging prohibited";
        case 10025: return "Prohibited by FIFO rules";
        case 10027: return "Connection to broker lost";
        case 10047: return "Not enough margins";
        case 10046: return "Autotrading disabled";
        default: return "Unknown error code: " + IntegerToString(retcode);
    }
}
//+------------------------------------------------------------------+