//+------------------------------------------------------------------+
//|                                                  ScalingInEA.mq5 |
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

input group "=== Scaling In Settings ==="
input int MaxScalingSteps = 3;           // Maximum scaling steps
input int ScalingMethod = 0;             // Scaling method: 0=Pyramid, 1=Equal, 2=Aggressive
input double StepDistance = 100;         // Distance between steps (points)
input bool MoveSLAfterStep = true;       // Move SL after each step
input bool CloseOnOppositeSignal = true; // Close on opposite signal

input group "=== Trade Settings ==="
input int InitialStopLoss = 100;         // Initial Stop Loss (points)
input int TakeProfit = 300;              // Take Profit (points)
input int MagicNumber = 12346;           // Magic Number
input string TradeComment = "ScalingIn"; // Trade Comment
input int MaxSlippage = 10;              // Maximum slippage (points)

input group "=== Keyboard Shortcuts ==="
input bool EnableKeyboard = true;        // Enable keyboard shortcuts
input string BuyKey = "B";               // Buy key (case sensitive)
input string SellKey = "S";              // Sell key (case sensitive)
input string CloseKey = "C";             // Close all key (case sensitive)

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
datetime LastKeyPressTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Scaling In EA initialized - Professional Version");
   CurrentStep = 0;
   TotalRisk = 0;
   MainTicket = 0;
   TradeActive = false;
   CurrentDirection = -1;
   WaitingForTrade = false;
   LastKeyPressTime = 0;
   
   // Validate inputs
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
      
   Print("EA Ready - Keyboard shortcuts enabled:");
   Print("BUY: Press '", BuyKey, "' | SELL: Press '", SellKey, "' | CLOSE ALL: Press '", CloseKey, "'");
   
   // Enable keyboard events
   if(EnableKeyboard)
   {
      ChartSetInteger(0, CHART_KEYBOARD_CONTROL, true);
      Print("Keyboard events enabled");
   }
   
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
   
   if(MaxScalingSteps <= 0 || MaxScalingSteps > 10)
   {
      Alert("Max scaling steps must be between 1 and 10");
      return false;
   }
   
   if(StepDistance <= 10)
   {
      Alert("Step distance must be at least 10 points");
      return false;
   }
   
   if(ScalingMethod < 0 || ScalingMethod > 2)
   {
      Alert("Scaling method must be 0, 1, or 2");
      return false;
   }
   
   if(StringLen(BuyKey) != 1 || StringLen(SellKey) != 1 || StringLen(CloseKey) != 1)
   {
      Alert("Keyboard keys must be single characters");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Scaling In EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Monitor existing trades for scaling opportunities
   if(TradeActive)
   {
      MonitorForScaling();
      CheckForExit();
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle keyboard events
   if(id == CHARTEVENT_KEYDOWN && EnableKeyboard)
   {
      HandleKeyboard(lparam);
   }
}

//+------------------------------------------------------------------+
//| Handle keyboard input                                            |
//+------------------------------------------------------------------+
void HandleKeyboard(long keycode)
{
   // Prevent too frequent key presses (200ms minimum)
   if(GetTickCount() - LastKeyPressTime < 200)
      return;
      
   LastKeyPressTime = GetTickCount();
   
   // Convert keycode to character
   string key = CharToString((uchar)keycode);
   
   // Check for buy key
   if(key == BuyKey)
   {
      Print("Buy key pressed - Opening BUY trade");
      if(!TradeActive || CurrentDirection != POSITION_TYPE_BUY)
      {
         if(CloseOnOppositeSignal && TradeActive)
         {
            CloseAllTrades();
            // Wait a moment for close to complete
            Sleep(500);
         }
         OpenTrade(POSITION_TYPE_BUY, 0);
      }
      else
      {
         Print("BUY trade already active");
      }
   }
   // Check for sell key
   else if(key == SellKey)
   {
      Print("Sell key pressed - Opening SELL trade");
      if(!TradeActive || CurrentDirection != POSITION_TYPE_SELL)
      {
         if(CloseOnOppositeSignal && TradeActive)
         {
            CloseAllTrades();
            // Wait a moment for close to complete
            Sleep(500);
         }
         OpenTrade(POSITION_TYPE_SELL, 0);
      }
      else
      {
         Print("SELL trade already active");
      }
   }
   // Check for close key
   else if(key == CloseKey)
   {
      Print("Close key pressed - Closing all trades");
      if(TradeActive)
      {
         CloseAllTrades();
      }
      else
      {
         Print("No active trades to close");
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(int stepNumber = 0)
{
   if(UseFixedLot)
      return FixedLotSize;
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue == 0 || pointValue == 0 || tickSize == 0)
   {
      Print("Error: Cannot calculate market info");
      return 0.01;
   }
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   // Calculate position size based on stop loss
   double slPrice = InitialStopLoss * pointValue;
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
         // Decreasing lots: 1.0, 0.5, 0.3, 0.2
         if(step == 0) return baseVolume;
         return baseVolume * (1.0 / (step + 1));
         
      case SCALING_EQUAL:
         // Equal lots for all steps
         return baseVolume;
         
      case SCALING_AGGRESSIVE:
         // Increasing lots: 1.0, 1.2, 1.5
         if(step == 0) return baseVolume;
         return baseVolume * (1.0 + step * 0.2);
   }
   
   return baseVolume;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker requirements                        |
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
   if(WaitingForTrade) return;
   
   WaitingForTrade = true;
   
   // Refresh rates
   MqlTick last_tick;
   SymbolInfoTick(_Symbol, last_tick);
   
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
      Alert("Maximum total risk limit reached!");
      WaitingForTrade = false;
      return;
   }
   
   // Calculate price, SL, TP with proper validation
   double price, sl, tp;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(direction == POSITION_TYPE_BUY)
   {
      price = NormalizeDouble(ask, _Digits);
      sl = NormalizeDouble(price - InitialStopLoss * point, _Digits);
      tp = NormalizeDouble(price + TakeProfit * point, _Digits);
      
      // Validate prices
      if(sl >= price || tp <= price)
      {
         Print("Invalid BUY levels - SL: ", sl, " TP: ", tp, " Price: ", price);
         WaitingForTrade = false;
         return;
      }
   }
   else
   {
      price = NormalizeDouble(bid, _Digits);
      sl = NormalizeDouble(price + InitialStopLoss * point, _Digits);
      tp = NormalizeDouble(price - TakeProfit * point, _Digits);
      
      // Validate prices
      if(sl <= price || tp >= price)
      {
         Print("Invalid SELL levels - SL: ", sl, " TP: ", tp, " Price: ", price);
         WaitingForTrade = false;
         return;
      }
   }
   
   // For scaling steps, adjust SL for breakeven or better
   if(step > 0 && MoveSLAfterStep)
   {
      double newSL = CalculateNewStopLoss(direction);
      if(newSL > 0) sl = newSL;
   }
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = (direction == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = (step == 0) ? sl : 0; // Only set SL on first entry
   request.tp = (step == 0) ? tp : 0; // Only set TP on first entry
   request.deviation = MaxSlippage;
   request.magic = MagicNumber;
   request.comment = StringFormat("%s_Step%d", TradeComment, step+1);
   
   // Send order with retry logic
   bool success = false;
   int attempts = 0;
   int maxAttempts = 3;
   
   while(attempts < maxAttempts && !success)
   {
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Trade opened: ", EnumToString(direction), " Step ", step+1, 
                  " Lot: ", lotSize, " Price: ", price);
            
            if(step == 0)
            {
               MainTicket = result.order;
               CurrentDirection = (int)direction;
               TradeActive = true;
               CurrentStep = 0;
            }
            else
            {
               CurrentStep = step;
            }
            
            // Update SL for all positions if this is a scaling step
            if(step > 0 && MoveSLAfterStep && sl > 0)
            {
               UpdateStopLossForAll(sl);
            }
            
            TotalRisk += CalculatePotentialRisk(lotSize);
            success = true;
         }
         else
         {
            Print("Trade failed. Attempt: ", attempts+1, " Retcode: ", result.retcode, 
                  " Error: ", GetLastError());
            attempts++;
            Sleep(1000); // Wait 1 second before retry
         }
      }
      else
      {
         Print("OrderSend failed. Attempt: ", attempts+1, " Error: ", GetLastError());
         attempts++;
         Sleep(1000); // Wait 1 second before retry
      }
   }
   
   if(!success)
   {
      Alert("Failed to open trade after ", maxAttempts, " attempts");
   }
   
   WaitingForTrade = false;
}

//+------------------------------------------------------------------+
//| Calculate new stop loss for scaling steps                        |
//+------------------------------------------------------------------+
double CalculateNewStopLoss(ENUM_POSITION_TYPE direction)
{
   double breakevenPrice = CalculateBreakevenPrice();
   
   if(breakevenPrice == 0) return 0;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(direction == POSITION_TYPE_BUY)
   {
      // Move SL to breakeven or better
      return NormalizeDouble(breakevenPrice - (InitialStopLoss * 0.5 * point), _Digits);
   }
   else
   {
      // Move SL to breakeven or better
      return NormalizeDouble(breakevenPrice + (InitialStopLoss * 0.5 * point), _Digits);
   }
}

//+------------------------------------------------------------------+
//| Calculate breakeven price for all positions                      |
//+------------------------------------------------------------------+
double CalculateBreakevenPrice()
{
   double totalVolume = 0;
   double totalCost = 0;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == CurrentDirection)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         totalVolume += volume;
         totalCost += volume * openPrice;
      }
   }
   
   if(totalVolume > 0)
      return NormalizeDouble(totalCost / totalVolume, _Digits);
   
   return 0;
}

//+------------------------------------------------------------------+
//| Update stop loss for all positions                               |
//+------------------------------------------------------------------+
void UpdateStopLossForAll(double newSL)
{
   if(newSL == 0) return;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && 
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == CurrentDirection)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol = _Symbol;
         request.sl = newSL;
         request.magic = MagicNumber;
         
         if(OrderSend(request, result))
         {
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("Failed to update SL for ticket: ", ticket, " Retcode: ", result.retcode);
            }
         }
         else
         {
            Print("OrderSend failed for SL update. Error: ", GetLastError());
         }
      }
   }
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
   
   double distance = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(CurrentDirection == POSITION_TYPE_BUY)
   {
      distance = (currentPrice - firstEntry) / point;
   }
   else
   {
      distance = (firstEntry - currentPrice) / point;
   }
   
   // Check if price has moved in our favor by the step distance
   bool distanceCondition = (distance >= (StepDistance * (CurrentStep + 1)));
   
   // Additional condition: Check if we're in profit
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
//| Get total profit for current trade                               |
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
//| Check for exit conditions                                        |
//+------------------------------------------------------------------+
void CheckForExit()
{
   // Check if take profit or stop loss hit (handled automatically by broker)
}

//+------------------------------------------------------------------+
//| Check total risk                                                 |
//+------------------------------------------------------------------+
bool CheckTotalRisk(double newLotSize)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double newRisk = CalculatePotentialRisk(newLotSize);
   double totalRisk = TotalRisk + newRisk;
   
   return ((totalRisk / accountBalance * 100) <= MaxTotalRiskPercent);
}

//+------------------------------------------------------------------+
//| Calculate potential risk                                         |
//+------------------------------------------------------------------+
double CalculatePotentialRisk(double lotSize)
{
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickValue == 0 || pointValue == 0) 
      return 0;
   
   return lotSize * (InitialStopLoss * pointValue / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * tickValue);
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
//| Close all trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   WaitingForTrade = true;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         request.volume = PositionGetDouble(POSITION_VOLUME);
         request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         request.deviation = MaxSlippage;
         request.magic = MagicNumber;
         request.comment = "Close All";
         
         if(OrderSend(request, result))
         {
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("Failed to close trade: ", ticket, " Retcode: ", result.retcode);
            }
         }
         else
         {
            Print("OrderSend failed for close. Error: ", GetLastError());
         }
         
         Sleep(100); // Small delay between close operations
      }
   }
   
   ResetEA();
   WaitingForTrade = false;
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
   Print("EA state reset");
}