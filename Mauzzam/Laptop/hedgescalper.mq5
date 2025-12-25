//+------------------------------------------------------------------+
//|                                XAUHedgeScalperFixed.mq5 |
//|                                  Copyright 2024, DeepSeek AI     |
//+------------------------------------------------------------------+
#property copyright "DeepSeek AI"
#property version   "2.0"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== STRATEGY SETTINGS ==="
input int    MagicNumber = 202405;          // Magic Number
input bool   EnableHedging = true;          // Enable Hedging
input double RiskPercent = 0.5;             // Risk Per Trade (%)
input double DailyMaxLoss = 2.0;            // Daily Max Loss (%)

input group "=== ENTRY PARAMETERS ==="
input int    EmaPeriod = 21;                // EMA Period
input int    BbandsPeriod = 20;             // Bollinger Bands Period
input double BbandsDeviation = 2.0;         // BB Deviation
input int    RSIPeriod = 7;                 // RSI Period
input int    RSIOversold = 30;              // RSI Oversold Level
input int    RSIOverbought = 70;            // RSI Overbought Level

input group "=== TRADE PARAMETERS ==="
input double StopLoss = 2.0;                // Stop Loss ($)
input double TakeProfit = 2.5;              // Take Profit ($)
input double HedgeTrigger = 2.0;            // Hedge Trigger ($)
input double HedgeSizePercent = 30;         // Hedge Size (%)
input double PartialClosePercent = 50;      // Partial Close (%)

input group "=== TIME FILTERS ==="
input bool   UseTimeFilter = false;         // Use Time Filter
input string StartTime = "03:00";           // Start Time (Server)
input string EndTime = "11:00";             // End Time (Server)
input bool   TradeMonday = true;            // Trade Monday
input bool   TradeFriday = true;            // Trade Friday

input group "=== LOGGING ==="
input bool   EnableLogging = true;          // Enable Detailed Logging

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int emaHandle, bbHandle, rsiHandle;
double ema[], bbUpper[], bbLower[], rsi[];
datetime lastBarTime;
int lastSignal = 0;
double positionAvgPrice = 0;
double positionSize = 0;
bool positionOpen = false;
int positionDirection = 0; // 1=long, -1=short
double dailyProfit = 0;
double dailyLoss = 0;
datetime lastTradeTime = 0;
int totalTradesToday = 0;
double maxDailyTrades = 10;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   emaHandle = iMA(_Symbol, PERIOD_M5, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   bbHandle = iBands(_Symbol, PERIOD_M5, BbandsPeriod, 0, BbandsDeviation, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M5, RSIPeriod, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE || bbHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Error: Failed to create indicators");
      return INIT_FAILED;
   }
   
   // Initialize arrays
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(rsi, true);
   
   // Reset daily stats at midnight
   EventSetTimer(3600); // Check every hour
   
   Print("=== XAU Scalper EA Initialized ===");
   Print("Symbol: ", _Symbol, " | Timeframe: M5");
   Print("Risk per trade: ", RiskPercent, "%");
   Print("Stop Loss: $", StopLoss, " | Take Profit: $", TakeProfit);
   Print("=================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaHandle);
   IndicatorRelease(bbHandle);
   IndicatorRelease(rsiHandle);
   EventKillTimer();
   Print("EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Reset daily stats at midnight
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.hour == 0 && dt.min == 0)
   {
      totalTradesToday = 0;
      dailyProfit = 0;
      dailyLoss = 0;
      if(EnableLogging) Print("Daily stats reset at midnight");
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(!IsNewBar(PERIOD_M5))
      return;
   
   // Check trading conditions
   if(!CheckTradingConditions())
      return;
   
   // Update indicators
   if(!UpdateIndicators())
   {
      if(EnableLogging) Print("Failed to update indicators");
      return;
   }
   
   // Check for signals
   CheckSignals();
   
   // Manage existing position
   if(positionOpen)
      ManagePosition();
   
   // Update chart comment
   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES period)
{
   datetime currentBarTime = iTime(_Symbol, period, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update indicator buffers                                        |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Clear arrays
   ArrayFree(ema);
   ArrayFree(bbUpper);
   ArrayFree(bbLower);
   ArrayFree(rsi);
   
   // Resize arrays
   ArrayResize(ema, 3);
   ArrayResize(bbUpper, 3);
   ArrayResize(bbLower, 3);
   ArrayResize(rsi, 3);
   
   // Get EMA
   if(CopyBuffer(emaHandle, 0, 0, 3, ema) < 3)
   {
      if(EnableLogging) Print("Failed to copy EMA buffer");
      return false;
   }
   
   // Get Bollinger Bands
   if(CopyBuffer(bbHandle, 2, 0, 3, bbLower) < 3) // Lower band
   {
      if(EnableLogging) Print("Failed to copy BB Lower buffer");
      return false;
   }
   
   if(CopyBuffer(bbHandle, 0, 0, 3, bbUpper) < 3) // Upper band
   {
      if(EnableLogging) Print("Failed to copy BB Upper buffer");
      return false;
   }
   
   // Get RSI
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 3)
   {
      if(EnableLogging) Print("Failed to copy RSI buffer");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                        |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
   // Check day of week
   MqlDateTime dt;
   TimeCurrent(dt);
   
   // Reset daily stats if new day
   static int lastDay = -1;
   if(lastDay != dt.day)
   {
      totalTradesToday = 0;
      lastDay = dt.day;
   }
   
   if(dt.day_of_week == 0) // Sunday
   {
      if(EnableLogging) Print("No trading on Sunday");
      return false;
   }
   
   if(!TradeMonday && dt.day_of_week == 1) // Monday
   {
      if(EnableLogging) Print("Monday trading disabled");
      return false;
   }
   
   if(!TradeFriday && dt.day_of_week == 5) // Friday
   {
      if(EnableLogging) Print("Friday trading disabled");
      return false;
   }
   
   // Check time filter
   if(UseTimeFilter && !IsTradingTime())
   {
      if(EnableLogging) Print("Outside trading hours");
      return false;
   }
   
   // Check spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 50) // 5 pips for XAU
   {
      Comment("Spread too high: ", spread);
      return false;
   }
   
   // Check max daily trades
   if(totalTradesToday >= maxDailyTrades)
   {
      Comment("Max daily trades reached: ", totalTradesToday);
      return false;
   }
   
   // Check minimum time between trades
   if(TimeCurrent() - lastTradeTime < 300) // 5 minutes
   {
      Comment("Waiting between trades...");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading time                                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   datetime current = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current, dt);
   
   string currentTime = StringFormat("%02d:%02d", dt.hour, dt.min);
   string currentDate = TimeToString(current, TIME_DATE);
   
   datetime start = StringToTime(currentDate + " " + StartTime);
   datetime end = StringToTime(currentDate + " " + EndTime);
   
   return (current >= start && current <= end);
}

//+------------------------------------------------------------------+
//| Check for signals                                               |
//+------------------------------------------------------------------+
void CheckSignals()
{
   if(positionOpen)
   {
      if(EnableLogging) Print("Position already open, skipping signal check");
      return;
   }
   
   // Get prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   
   if(EnableLogging)
   {
      Print("Signal Check - Close: ", close, 
            " BB Lower: ", bbLower[1], 
            " BB Upper: ", bbUpper[1],
            " RSI: ", rsi[1],
            " EMA: ", ema[1]);
   }
   
   // Long signal: Price at lower BB, RSI oversold, price above EMA
   if(close <= bbLower[1] && rsi[1] <= RSIOversold && close > ema[1])
   {
      if(EnableLogging) Print("LONG SIGNAL DETECTED");
      if(OpenPosition(ORDER_TYPE_BUY))
      {
         Print("Long position opened at ", bid);
         totalTradesToday++;
      }
   }
   // Short signal: Price at upper BB, RSI overbought, price below EMA
   else if(close >= bbUpper[1] && rsi[1] >= RSIOverbought && close < ema[1])
   {
      if(EnableLogging) Print("SHORT SIGNAL DETECTED");
      if(OpenPosition(ORDER_TYPE_SELL))
      {
         Print("Short position opened at ", ask);
         totalTradesToday++;
      }
   }
}

//+------------------------------------------------------------------+
//| Open position                                                   |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE type)
{
   // Get price
   double price = (type == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Calculate SL and TP
   double sl = CalculateStopLoss(type, price);
   double tp = CalculateTakeProfit(type, price);
   double lots = CalculateLots(sl, price, type);
   
   if(lots <= 0)
   {
      Print("Error: Invalid lot size calculated: ", lots);
      return false;
   }
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 50; // Increased deviation for XAU
   request.magic = MagicNumber;
   request.comment = "XAU Scalp Entry";
   
   // Send order
   bool success = OrderSend(request, result);
   
   if(!success)
   {
      Print("OrderSend failed. Error: ", GetLastError(), 
            " | Retcode: ", result.retcode,
            " | Comment: ", result.comment);
      return false;
   }
   
   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Order rejected. Retcode: ", result.retcode,
            " | Comment: ", result.comment);
      return false;
   }
   
   // Update position tracking
   positionOpen = true;
   positionDirection = (type == ORDER_TYPE_BUY) ? 1 : -1;
   positionAvgPrice = result.price;
   positionSize = lots;
   lastTradeTime = TimeCurrent();
   
   if(EnableLogging)
   {
      Print("SUCCESS: Position opened");
      Print("  Type: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"));
      Print("  Price: ", result.price);
      Print("  Lots: ", lots);
      Print("  SL: ", sl);
      Print("  TP: ", tp);
      Print("  Ticket: ", result.order);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate stop loss - FIXED VERSION                             |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE type, double price)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize <= 0) tickSize = 0.01; // Default for XAU
   
   // Convert dollars to points
   double stopPoints = StopLoss / tickSize;
   
   if(type == ORDER_TYPE_BUY)
      return price - (stopPoints * point);
   else
      return price + (stopPoints * point);
}

//+------------------------------------------------------------------+
//| Calculate take profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE type, double price)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize <= 0) tickSize = 0.01;
   
   double tpPoints = TakeProfit / tickSize;
   
   if(type == ORDER_TYPE_BUY)
      return price + (tpPoints * point);
   else
      return price - (tpPoints * point);
}

//+------------------------------------------------------------------+
//| Calculate lots based on risk                                    |
//+------------------------------------------------------------------+
double CalculateLots(double sl, double price, ENUM_ORDER_TYPE type)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) balance = 1000; // Default if zero
   
   double riskAmount = balance * (RiskPercent / 100);
   
   // Calculate stop distance in price
   double stopDistance = MathAbs(price - sl);
   
   if(stopDistance <= 0)
   {
      Print("Error: Stop distance is zero or negative");
      return 0;
   }
   
   // For XAUUSD, tick value is usually $0.01 per 0.01 move
   double tickValue = 0.01; // Conservative estimate for XAU
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   
   if(contractSize > 0)
      tickValue = (stopDistance / SymbolInfoDouble(_Symbol, SYMBOL_POINT)) * tickValue;
   
   // Calculate lots
   double lots = riskAmount / (stopDistance / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * tickValue);
   
   // Normalize
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(minLot <= 0) minLot = 0.01;
   if(lotStep <= 0) lotStep = 0.01;
   
   lots = MathFloor(lots / lotStep) * lotStep;
   
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Manage existing position                                        |
//+------------------------------------------------------------------+
void ManagePosition()
{
   // Check if position still exists
   bool positionExists = false;
   ulong positionTicket = 0;
   ENUM_POSITION_TYPE posType = POSITION_TYPE_BUY; // Initialize with default
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            positionExists = true;
            positionTicket = PositionGetTicket(i);
            posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            break;
         }
      }
   }
   
   if(!positionExists)
   {
      positionOpen = false;
      if(EnableLogging) Print("Position no longer exists, resetting flag");
      return;
   }
   
   // Check for partial close
   CheckPartialClose(positionTicket, posType);
   
   // Check for hedging
   if(EnableHedging)
      CheckHedge(positionTicket, posType);
   
   // Check for breakeven
   CheckBreakeven(positionTicket, posType);
   
   // Check for daily limits
   CheckDailyLimits();
}

//+------------------------------------------------------------------+
//| Check for partial close                                         |
//+------------------------------------------------------------------+
void CheckPartialClose(ulong ticket, ENUM_POSITION_TYPE posType)
{
   if(PartialClosePercent <= 0 || ticket == 0)
      return;
   
   if(!PositionSelectByTicket(ticket))
      return;
   
   double currentProfit = PositionGetDouble(POSITION_PROFIT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double volume = PositionGetDouble(POSITION_VOLUME);
   
   // Calculate profit in dollars
   double profitPips = MathAbs(currentPrice - openPrice) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickValue = 0.01; // XAUUSD
   double profitDollars = profitPips * tickValue * volume;
   
   // If profit reaches 80% of TP, do partial close
   double targetProfit = TakeProfit * volume;
   
   if(profitDollars >= (targetProfit * 0.8))
   {
      double closeVolume = volume * (PartialClosePercent / 100);
      closeVolume = NormalizeDouble(closeVolume, 2);
      
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(minLot <= 0) minLot = 0.01;
      
      if(closeVolume < minLot)
         return;
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = closeVolume;
      request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.position = ticket;
      request.price = (request.type == ORDER_TYPE_BUY) ? 
                      SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                      SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.deviation = 50;
      request.magic = MagicNumber;
      request.comment = "Partial Close";
      
      bool success = OrderSend(request, result);
      
      if(success && result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Partial close executed. Volume: ", closeVolume, " | Profit: $", profitDollars);
         positionSize -= closeVolume;
      }
      else if(EnableLogging)
      {
         Print("Partial close failed. Error: ", GetLastError(), " | Retcode: ", result.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for hedge opportunity - FIXED VERSION                     |
//+------------------------------------------------------------------+
void CheckHedge(ulong ticket, ENUM_POSITION_TYPE posType)
{
   if(!positionOpen || ticket == 0)
      return;
   
   if(!PositionSelectByTicket(ticket))
      return;
   
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   
   // Calculate drawdown
   double drawdown = (posType == POSITION_TYPE_BUY) ? 
                     (openPrice - currentPrice) : 
                     (currentPrice - openPrice);
   
   // Convert to dollars
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = 0.01;
   
   double drawdownDollars = MathAbs(drawdown) / point * tickSize;
   
   if(EnableLogging) Print("Drawdown: $", drawdownDollars, " | Trigger: $", HedgeTrigger);
   
   // If drawdown exceeds hedge trigger
   if(drawdownDollars >= HedgeTrigger)
   {
      // Check if we already have a hedge position
      bool hasHedge = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(comment == "Hedge")
            {
               hasHedge = true;
               break;
            }
         }
      }
      
      if(!hasHedge)
      {
         AddHedgePosition(posType);
      }
   }
}

//+------------------------------------------------------------------+
//| Add hedge position                                              |
//+------------------------------------------------------------------+
void AddHedgePosition(ENUM_POSITION_TYPE originalType)
{
   // Calculate hedge lots
   double hedgeLots = positionSize * (HedgeSizePercent / 100);
   hedgeLots = NormalizeDouble(hedgeLots, 2);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minLot <= 0) minLot = 0.01;
   
   if(hedgeLots < minLot)
   {
      if(EnableLogging) Print("Hedge lot size too small: ", hedgeLots);
      return;
   }
   
   ENUM_ORDER_TYPE hedgeType = (originalType == POSITION_TYPE_BUY) ? 
                               ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   double price = (hedgeType == ORDER_TYPE_BUY) ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = hedgeLots;
   request.type = hedgeType;
   request.price = price;
   request.deviation = 50;
   request.magic = MagicNumber;
   request.comment = "Hedge";
   
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Hedge added. Lots: ", hedgeLots, " | Price: ", price);
      positionSize += hedgeLots;
      
      // Recalculate average price
      positionAvgPrice = (positionAvgPrice * (positionSize - hedgeLots) + 
                         price * hedgeLots) / positionSize;
   }
   else if(EnableLogging)
   {
      Print("Hedge order failed. Error: ", GetLastError(), " | Retcode: ", result.retcode);
   }
}

//+------------------------------------------------------------------+
//| Check for breakeven                                             |
//+------------------------------------------------------------------+
void CheckBreakeven(ulong ticket, ENUM_POSITION_TYPE posType)
{
   if(ticket == 0) return;
   
   if(!PositionSelectByTicket(ticket))
      return;
   
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   
   double breakevenDistance = 1.0; // $1 profit
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = 0.01;
   
   double distanceInPoints = breakevenDistance / tickSize;
   
   double newSL = currentSL;
   
   if(posType == POSITION_TYPE_BUY)
   {
      double breakevenLevel = openPrice + (distanceInPoints * point);
      if(currentPrice >= breakevenLevel && (currentSL < openPrice || currentSL == 0))
      {
         newSL = openPrice;
      }
   }
   else
   {
      double breakevenLevel = openPrice - (distanceInPoints * point);
      if(currentPrice <= breakevenLevel && (currentSL > openPrice || currentSL == 0))
      {
         newSL = openPrice;
      }
   }
   
   if(newSL != currentSL)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;
      request.position = ticket;
      request.sl = newSL;
      request.tp = PositionGetDouble(POSITION_TP);
      request.magic = MagicNumber;
      
      bool success = OrderSend(request, result);
      
      if(success && result.retcode == TRADE_RETCODE_DONE)
      {
         if(EnableLogging) Print("Stop loss moved to breakeven: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Check daily limits                                              |
//+------------------------------------------------------------------+
void CheckDailyLimits()
{
   double dailyPL = GetDailyProfit();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(balance <= 0) return;
   
   double lossPercent = MathAbs(dailyPL) / balance * 100;
   
   if(dailyPL < 0 && lossPercent >= DailyMaxLoss)
   {
      Print("Daily loss limit reached: ", lossPercent, "% | P/L: $", dailyPL);
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Get daily profit                                                |
//+------------------------------------------------------------------+
double GetDailyProfit()
{
   double profit = 0;
   MqlDateTime today;
   TimeCurrent(today);
   today.hour = 0;
   today.min = 0;
   today.sec = 0;
   datetime startOfDay = StructToTime(today);
   
   if(HistorySelect(startOfDay, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }
   }
   
   // Add open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         profit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| Close all positions - FIXED VERSION                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                           ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = ticket;
            request.price = (request.type == ORDER_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID);
            request.deviation = 50;
            request.magic = MagicNumber;
            request.comment = "Emergency Close";
            
            bool success = OrderSend(request, result);
            
            if(success && result.retcode == TRADE_RETCODE_DONE)
            {
               Print("Emergency close executed for ticket: ", ticket);
            }
            else if(EnableLogging)
            {
               Print("Emergency close failed. Error: ", GetLastError(), 
                     " | Retcode: ", result.retcode);
            }
         }
      }
   }
   
   positionOpen = false;
}

//+------------------------------------------------------------------+
//| Update chart comment                                            |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string comment = "\n=== XAU SCALPER EA ===\n";
   comment += "Status: " + (positionOpen ? "POSITION OPEN" : "WAITING") + "\n";
   comment += "Position: " + (positionDirection == 1 ? "LONG" : 
              positionDirection == -1 ? "SHORT" : "NONE") + "\n";
   comment += "Size: " + DoubleToString(positionSize, 2) + " lots\n";
   comment += "Trades Today: " + IntegerToString(totalTradesToday) + "\n";
   comment += "Daily P/L: $" + DoubleToString(GetDailyProfit(), 2) + "\n";
   comment += "Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   comment += "Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   comment += "======================";
   
   Comment(comment);
}