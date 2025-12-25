//+------------------------------------------------------------------+
//|                                              SmartScalingEA.mq5  |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input group "=== Risk Management ==="
input double RiskPercent = 1.0;          // Risk per trade (%)
input double MaxTotalRiskPercent = 5.0;  // Maximum total risk (%)
input bool UseFixedLot = false;          // Use fixed lot size
input double FixedLotSize = 0.01;        // Fixed lot size if enabled

input group "=== Trading Hours & Limits ==="
input int MaxTradesPerDay = 3;           // Maximum trades per day
input string TradingStart = "08:00";     // Trading session start (Broker Time)
input string TradingEnd = "20:00";       // Trading session end (Broker Time)
input bool AvoidNews = true;             // Avoid high impact news
input int MinHoursBetweenTrades = 2;     // Minimum hours between trades

input group "=== Strategy Parameters ==="
input int SwingPeriod = 20;              // Swing high/low period
input int MAPeriod = 50;                 // Moving Average period
input ENUM_MA_METHOD MAMethod = MODE_EMA;// MA Method
input int ATRPeriod = 14;                // ATR Period for volatility
input double ATRMultiplier = 2.0;        // ATR Multiplier for SL/TP
input bool UseRSI = true;                // Use RSI filter
input int RSIPeriod = 14;                // RSI Period
input double RSIOverbought = 70;         // RSI Overbought level
input double RSIOversold = 30;           // RSI Oversold level

input group "=== Scaling In Settings ==="
input int MaxScalingSteps = 3;           // Maximum scaling steps
input int ScalingMethod = 0;             // Scaling method: 0=Pyramid, 1=Equal, 2=Aggressive
input double StepDistance = 100;         // Distance between steps (points)
input bool MoveSLAfterStep = true;       // Move SL after each step

input group "=== Trade Settings ==="
input int MagicNumber = 12347;           // Magic Number
input string TradeComment = "SmartScale";// Trade Comment
input int MaxSlippage = 10;              // Maximum slippage (points)

//--- Constants for scaling methods
#define SCALING_PYRAMID    0
#define SCALING_EQUAL      1
#define SCALING_AGGRESSIVE 2

//--- Global variables
double InitialLotSize;
int CurrentStep;
double TotalRisk;
ulong MainTicket;
int CurrentDirection;
bool TradeActive;
bool WaitingForTrade;
int DailyTradeCount;
datetime LastTradeTime;
int MAHandle, ATRHandle, RSIHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Smart Scaling EA initialized - Auto Entry Version");
   CurrentStep = 0;
   TotalRisk = 0;
   MainTicket = 0;
   TradeActive = false;
   CurrentDirection = -1;
   WaitingForTrade = false;
   DailyTradeCount = 0;
   LastTradeTime = 0;
   
   // Create indicator handles
   MAHandle = iMA(_Symbol, _Period, MAPeriod, 0, MAMethod, PRICE_CLOSE);
   ATRHandle = iATR(_Symbol, _Period, ATRPeriod);
   if(UseRSI) 
      RSIHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   
   if(MAHandle == INVALID_HANDLE || ATRHandle == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return INIT_FAILED;
   }
   
   // Validate inputs
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   
   // Load today's trade count
   LoadDailyTradeCount();
   
   Print("Smart EA Ready - Auto entries based on multi-factor analysis");
   Print("Max Trades Today: ", MaxTradesPerDay - DailyTradeCount);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Input validation                                                 |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(RiskPercent <= 0 || RiskPercent > 10)
   {
      Alert("Risk percentage must be between 0.1 and 10");
      return false;
   }
   
   if(MaxTradesPerDay <= 0 || MaxTradesPerDay > 20)
   {
      Alert("Max trades per day must be between 1 and 20");
      return false;
   }
   
   if(MaxScalingSteps <= 0 || MaxScalingSteps > 10)
   {
      Alert("Max scaling steps must be between 1 and 10");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(MAHandle != INVALID_HANDLE) IndicatorRelease(MAHandle);
   if(ATRHandle != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(UseRSI && RSIHandle != INVALID_HANDLE) IndicatorRelease(RSIHandle);
   
   Print("Smart Scaling EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new day reset
   CheckDailyReset();
   
   // Check if we can trade
   if(!CanTradeNow())
      return;
   
   // Monitor existing trades for scaling opportunities
   if(TradeActive)
   {
      MonitorForScaling();
      CheckForExit();
   }
   else
   {
      // Look for new entry opportunities
      CheckForAutoEntry();
   }
}

//+------------------------------------------------------------------+
//| Check for exit conditions                                        |
//+------------------------------------------------------------------+
void CheckForExit()
{
   // Check if take profit or stop loss hit (handled automatically by broker)
}

//+------------------------------------------------------------------+
//| Check for daily reset                                            |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime today;
   TimeCurrent(today);
   today.hour = 0;
   today.min = 0;
   today.sec = 0;
   datetime todayStart = StructToTime(today);
   
   if(LastTradeTime < todayStart)
   {
      DailyTradeCount = 0;
      Print("New day started - Trade counter reset");
   }
}

//+------------------------------------------------------------------+
//| Load daily trade count from previous trades                      |
//+------------------------------------------------------------------+
void LoadDailyTradeCount()
{
   DailyTradeCount = 0;
   MqlDateTime today;
   TimeCurrent(today);
   today.hour = 0;
   today.min = 0;
   today.sec = 0;
   datetime todayStart = StructToTime(today);
   
   HistorySelect(todayStart, TimeCurrent() + 86400);
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            if(dealTime >= todayStart)
            {
               DailyTradeCount++;
               if(dealTime > LastTradeTime) LastTradeTime = dealTime;
            }
         }
      }
   }
   
   Print("Loaded ", DailyTradeCount, " trades for today");
}

//+------------------------------------------------------------------+
//| Check if we can trade now                                        |
//+------------------------------------------------------------------+
bool CanTradeNow()
{
   // Check daily trade limit
   if(DailyTradeCount >= MaxTradesPerDay)
   {
      Comment("Daily trade limit reached: ", DailyTradeCount, "/", MaxTradesPerDay);
      return false;
   }
   
   // Check time between trades
   if(LastTradeTime > 0 && (TimeCurrent() - LastTradeTime) < (MinHoursBetweenTrades * 3600))
   {
      int minutesLeft = (int)((MinHoursBetweenTrades * 3600 - (TimeCurrent() - LastTradeTime)) / 60);
      Comment("Wait ", minutesLeft, " minutes before next trade");
      return false;
   }
   
   // Check trading hours
   if(!IsTradingHours())
   {
      Comment("Outside trading hours");
      return false;
   }
   
   // Check news (simplified - in real EA, integrate with news API)
   if(AvoidNews && IsHighImpactNews())
   {
      Comment("Avoiding high impact news");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsTradingHours()
{
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   
   // Convert time strings to minutes
   int startHour, startMinute, endHour, endMinute;
   StringToTime(TradingStart, startHour, startMinute);
   StringToTime(TradingEnd, endHour, endMinute);
   
   int startMinutes = startHour * 60 + startMinute;
   int endMinutes = endHour * 60 + endMinute;
   
   return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

//+------------------------------------------------------------------+
//| Convert time string to hours and minutes                         |
//+------------------------------------------------------------------+
void StringToTime(string timeStr, int &hour, int &minute)
{
   string parts[];
   StringSplit(timeStr, ':', parts);
   if(ArraySize(parts) >= 2)
   {
      hour = (int)StringToInteger(parts[0]);
      minute = (int)StringToInteger(parts[1]);
   }
   else
   {
      hour = 8;
      minute = 0;
   }
}

//+------------------------------------------------------------------+
//| Check for high impact news (simplified)                          |
//+------------------------------------------------------------------+
bool IsHighImpactNews()
{
   // This is a simplified version. In real implementation, integrate with:
   // - Forex Factory API
   // - Economic Calendar
   // - News feeds
   
   // For now, avoid trading during major session overlaps
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   int currentHour = currentTime.hour;
   
   // Avoid London-New York overlap (13:00-16:00 GMT)
   if(currentHour >= 13 && currentHour <= 16)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for automatic entry opportunities                          |
//+------------------------------------------------------------------+
void CheckForAutoEntry()
{
   if(WaitingForTrade || TradeActive)
      return;
   
   // Get indicator values
   double maValue = GetMAValue();
   double atrValue = GetATRValue();
   double rsiValue = GetRSIValue();
   double swingHigh = GetSwingHigh();
   double swingLow = GetSwingLow();
   
   if(maValue == 0 || atrValue == 0)
      return;
   
   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2;
   
   // Multi-factor analysis for BUY signal
   if(CheckBuySignal(currentPrice, maValue, atrValue, rsiValue, swingHigh, swingLow))
   {
      Print("BUY Signal Detected - Multi-factor confirmation");
      OpenTrade(POSITION_TYPE_BUY, 0);
   }
   // Multi-factor analysis for SELL signal
   else if(CheckSellSignal(currentPrice, maValue, atrValue, rsiValue, swingHigh, swingLow))
   {
      Print("SELL Signal Detected - Multi-factor confirmation");
      OpenTrade(POSITION_TYPE_SELL, 0);
   }
}

//+------------------------------------------------------------------+
//| Check for BUY signal with multiple confirmations                 |
//+------------------------------------------------------------------+
bool CheckBuySignal(double price, double ma, double atr, double rsi, double swingHigh, double swingLow)
{
   int confirmations = 0;
   
   // 1. Price above MA (trend)
   if(price > ma)
      confirmations++;
   
   // 2. RSI not overbought
   if(!UseRSI || (rsi < RSIOverbought && rsi > RSIOversold))
      confirmations++;
   else if(rsi < RSIOversold) // Oversold bounce
      confirmations += 2;
   
   // 3. Swing low breakout
   if(swingLow > 0 && price > swingLow)
      confirmations++;
   
   // 4. Volatility check (adequate movement)
   if(atr > (10 * _Point))
      confirmations++;
   
   // 5. Recent price action (simplified)
   if(IsUptrend())
      confirmations++;
   
   // Require at least 3 confirmations
   return (confirmations >= 3);
}

//+------------------------------------------------------------------+
//| Check for SELL signal with multiple confirmations                |
//+------------------------------------------------------------------+
bool CheckSellSignal(double price, double ma, double atr, double rsi, double swingHigh, double swingLow)
{
   int confirmations = 0;
   
   // 1. Price below MA (trend)
   if(price < ma)
      confirmations++;
   
   // 2. RSI not oversold
   if(!UseRSI || (rsi < RSIOverbought && rsi > RSIOversold))
      confirmations++;
   else if(rsi > RSIOverbought) // Overbought rejection
      confirmations += 2;
   
   // 3. Swing high breakdown
   if(swingHigh > 0 && price < swingHigh)
      confirmations++;
   
   // 4. Volatility check (adequate movement)
   if(atr > (10 * _Point))
      confirmations++;
   
   // 5. Recent price action (simplified)
   if(IsDowntrend())
      confirmations++;
   
   // Require at least 3 confirmations
   return (confirmations >= 3);
}

//+------------------------------------------------------------------+
//| Check if market is in uptrend                                    |
//+------------------------------------------------------------------+
bool IsUptrend()
{
   double ma1 = GetMAValue(1);  // Current
   double ma2 = GetMAValue(10); // 10 bars ago
   
   return (ma1 > ma2);
}

//+------------------------------------------------------------------+
//| Check if market is in downtrend                                  |
//+------------------------------------------------------------------+
bool IsDowntrend()
{
   double ma1 = GetMAValue(1);  // Current
   double ma2 = GetMAValue(10); // 10 bars ago
   
   return (ma1 < ma2);
}

//+------------------------------------------------------------------+
//| Get MA value                                                     |
//+------------------------------------------------------------------+
double GetMAValue(int shift = 0)
{
   double ma[1];
   if(CopyBuffer(MAHandle, 0, shift, 1, ma) > 0)
      return ma[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double GetATRValue(int shift = 0)
{
   double atr[1];
   if(CopyBuffer(ATRHandle, 0, shift, 1, atr) > 0)
      return atr[0];
   return 0;
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSIValue(int shift = 0)
{
   if(!UseRSI) return 50;
   
   double rsi[1];
   if(CopyBuffer(RSIHandle, 0, shift, 1, rsi) > 0)
      return rsi[0];
   return 50;
}

//+------------------------------------------------------------------+
//| Get swing high                                                   |
//+------------------------------------------------------------------+
double GetSwingHigh()
{
   double high[];
   if(CopyHigh(_Symbol, _Period, 0, SwingPeriod + 1, high) > 0)
   {
      double highest = high[0];
      for(int i = 1; i < SwingPeriod; i++)
      {
         if(high[i] > highest)
            highest = high[i];
      }
      return highest;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Get swing low                                                    |
//+------------------------------------------------------------------+
double GetSwingLow()
{
   double low[];
   if(CopyLow(_Symbol, _Period, 0, SwingPeriod + 1, low) > 0)
   {
      double lowest = low[0];
      for(int i = 1; i < SwingPeriod; i++)
      {
         if(low[i] < lowest)
            lowest = low[i];
      }
      return lowest;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(int stepNumber = 0)
{
   if(UseFixedLot)
      return FixedLotSize;
   
   double atr = GetATRValue();
   double stopLossPoints = atr * ATRMultiplier / _Point;
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue == 0 || pointValue == 0 || tickSize == 0)
      return 0.01;
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   double slPrice = stopLossPoints * pointValue;
   double volume = riskAmount / (slPrice / tickSize * tickValue);
   
   // Apply scaling method
   volume = ApplyScalingMethod(volume, stepNumber);
   
   // Normalize lot size
   return NormalizeLotSize(volume);
}

//+------------------------------------------------------------------+
//| Apply scaling method to lot size                                 |
//+------------------------------------------------------------------+
double ApplyScalingMethod(double baseVolume, int step)
{
   switch(ScalingMethod)
   {
      case SCALING_PYRAMID:
         if(step == 0) return baseVolume;
         return baseVolume * (1.0 / (step + 1));
         
      case SCALING_EQUAL:
         return baseVolume;
         
      case SCALING_AGGRESSIVE:
         if(step == 0) return baseVolume;
         return baseVolume * (1.0 + step * 0.2);
   }
   return baseVolume;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormalizeLotSize(double volume)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(stepLot == 0) return minLot;
   
   volume = MathRound(volume / stepLot) * stepLot;
   volume = MathMax(minLot, MathMin(volume, maxLot));
   
   return volume;
}

//+------------------------------------------------------------------+
//| Open a new trade                                                 |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_POSITION_TYPE direction, int step)
{
   WaitingForTrade = true;
   
   // Calculate lot size
   double lotSize = CalculateLotSize(step);
   if(lotSize <= 0)
   {
      Print("Error: Invalid lot size calculated");
      WaitingForTrade = false;
      return;
   }
   
   // Check total risk
   if(!CheckTotalRisk(lotSize))
   {
      Print("Maximum total risk limit reached!");
      WaitingForTrade = false;
      return;
   }
   
   // Calculate dynamic SL/TP based on ATR
   double atr = GetATRValue();
   double atrSl = atr * ATRMultiplier;
   double atrTp = atrSl * 1.5; // 1.5:1 risk reward
   
   double price, sl, tp;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(direction == POSITION_TYPE_BUY)
   {
      price = NormalizeDouble(ask, _Digits);
      sl = NormalizeDouble(price - atrSl, _Digits);
      tp = NormalizeDouble(price + atrTp, _Digits);
   }
   else
   {
      price = NormalizeDouble(bid, _Digits);
      sl = NormalizeDouble(price + atrSl, _Digits);
      tp = NormalizeDouble(price - atrTp, _Digits);
   }
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = (direction == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = MaxSlippage;
   request.magic = MagicNumber;
   request.comment = StringFormat("%s_Step%d", TradeComment, step+1);
   
   // Send order
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Trade opened: ", EnumToString(direction), " Step ", step+1, 
               " Lot: ", lotSize, " SL: ", sl, " TP: ", tp);
         
         if(step == 0)
         {
            MainTicket = result.order;
            CurrentDirection = direction;
            TradeActive = true;
            CurrentStep = 0;
            DailyTradeCount++;
            LastTradeTime = TimeCurrent();
            
            Print("Daily trades: ", DailyTradeCount, "/", MaxTradesPerDay);
         }
         else
         {
            CurrentStep = step;
         }
         
         TotalRisk += CalculatePotentialRisk(lotSize, atrSl);
      }
   }
   
   WaitingForTrade = false;
}

//+------------------------------------------------------------------+
//| Monitor for scaling opportunities                                |
//+------------------------------------------------------------------+
void MonitorForScaling()
{
   if(CurrentStep >= MaxScalingSteps || WaitingForTrade)
      return;
   
   if(CheckScalingCondition())
   {
      OpenTrade((ENUM_POSITION_TYPE)CurrentDirection, CurrentStep + 1);
   }
}

//+------------------------------------------------------------------+
//| Check if conditions are met for scaling                          |
//+------------------------------------------------------------------+
bool CheckScalingCondition()
{
   double firstEntry = GetFirstEntryPrice();
   double currentPrice = (CurrentDirection == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(firstEntry == 0) return false;
   
   double atr = GetATRValue();
   double stepDistancePoints = atr * 0.5; // Use 0.5 ATR for step distance
   
   double distance = 0;
   
   if(CurrentDirection == POSITION_TYPE_BUY)
   {
      distance = (currentPrice - firstEntry) / _Point;
   }
   else
   {
      distance = (firstEntry - currentPrice) / _Point;
   }
   
   bool distanceCondition = (distance >= stepDistancePoints / _Point);
   bool profitCondition = (GetTotalProfit() > 0);
   
   return (distanceCondition && profitCondition);
}

//+------------------------------------------------------------------+
//| Get first entry price                                            |
//+------------------------------------------------------------------+
double GetFirstEntryPrice()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == CurrentDirection)
      {
         return PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Get total profit                                                 |
//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double totalProfit = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Check total risk                                                 |
//+------------------------------------------------------------------+
bool CheckTotalRisk(double newLotSize)
{
   double atr = GetATRValue();
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double newRisk = CalculatePotentialRisk(newLotSize, atr * ATRMultiplier);
   double totalRisk = TotalRisk + newRisk;
   
   return ((totalRisk / accountBalance * 100) <= MaxTotalRiskPercent);
}

//+------------------------------------------------------------------+
//| Calculate potential risk                                         |
//+------------------------------------------------------------------+
double CalculatePotentialRisk(double lotSize, double atrSl)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue == 0 || pointValue == 0) 
      return 0;
   
   return lotSize * (atrSl / pointValue / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * tickValue);
}

//+------------------------------------------------------------------+
//| Count open trades                                                |
//+------------------------------------------------------------------+
int CountTrades()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Reset EA state                                                   |
//+------------------------------------------------------------------+
void ResetEA()
{
   CurrentStep = 0;
   TotalRisk = 0;
   MainTicket = 0;
   TradeActive = false;
   CurrentDirection = -1;
}