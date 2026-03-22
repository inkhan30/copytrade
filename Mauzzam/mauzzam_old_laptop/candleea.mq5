//+------------------------------------------------------------------+
//|                                                  TwoCandleEA.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input int      ConsecutiveCandles = 2;           // Number of consecutive candles
input double   LotSize = 0.01;                   // Trade lot size
input double   RiskRewardRatio = 1.5;            // TP ratio (1:1.5)
input int      CoolingPeriod = 15;               // Cooling period in minutes
input bool     UseLowForSL = true;               // Use Low for SL (false = Use Close)
input int      MagicNumber = 12345;              // Magic number for trades
input int      Slippage = 3;                     // Slippage in points
input bool     EnableTrailingStop = true;        // Enable trailing stop feature

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
datetime lastTradeTime = 0;                      // Time of last trade
bool isCooling = false;                          // Cooling period flag
double point;                                    // Point value
double tickSize;                                 // Tick size

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== Two Candle EA Initialization ===");
   
   // Get symbol information
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   PrintFormat("Symbol: %s, Point: %.5f, Tick Size: %.5f", _Symbol, point, tickSize);
   PrintFormat("Consecutive Candles: %d, Lot Size: %.2f", ConsecutiveCandles, LotSize);
   PrintFormat("Risk Reward Ratio: %.1f, Cooling Period: %d minutes", RiskRewardRatio, CoolingPeriod);
   PrintFormat("Use Low for SL: %s, Magic Number: %d", UseLowForSL ? "Yes" : "No", MagicNumber);
   PrintFormat("Trailing Stop Enabled: %s", EnableTrailingStop ? "Yes" : "No");
   
   // Validate inputs
   if(ConsecutiveCandles < 2)
   {
      Print("ERROR: ConsecutiveCandles must be at least 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(LotSize <= 0)
   {
      Print("ERROR: LotSize must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(RiskRewardRatio <= 0)
   {
      Print("ERROR: RiskRewardRatio must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   Print("EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("EA deinitialized with reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we're in cooling period
   CheckCoolingPeriod();
   
   // Manage trailing stops for open positions
   if(EnableTrailingStop && PositionsTotal() > 0)
   {
      ManageTrailingStops();
   }
   
   // Only check for new trades if not in cooling period and it's a new bar
   if(!isCooling && IsNewBar())
   {
      CheckForTradeSignal();
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops for open positions                         |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double currentSL = PositionGetDouble(POSITION_SL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         // Get position type properly
         long positionType = PositionGetInteger(POSITION_TYPE);
         
         // Determine current price based on position type
         double currentPrice;
         if(positionType == POSITION_TYPE_BUY)
         {
            currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         }
         else // POSITION_TYPE_SELL
         {
            currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         }
         
         double tp = PositionGetDouble(POSITION_TP);
         
         // Convert position type to direction (1 for BUY, -1 for SELL)
         int direction = (positionType == POSITION_TYPE_BUY) ? 1 : -1;
         
         // Calculate profit progression
         double profitProgression = CalculateProfitProgression(direction, openPrice, currentPrice, tp);
         
         // Calculate new stop loss based on profit progression
         double newSL = CalculateNewStopLoss(direction, openPrice, currentPrice, tp, currentSL, profitProgression);
         
         // Update stop loss if needed
         if(newSL > 0 && ShouldUpdateSL(direction, currentSL, newSL))
         {
            UpdateStopLoss(ticket, newSL);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate profit progression (0 to 1.0)                         |
//+------------------------------------------------------------------+
double CalculateProfitProgression(int direction, double openPrice, double currentPrice, double tp)
{
   double totalDistance = MathAbs(tp - openPrice);
   double currentDistance;
   
   if(direction > 0) // BUY position
   {
      currentDistance = currentPrice - openPrice;
   }
   else // SELL position
   {
      currentDistance = openPrice - currentPrice;
   }
   
   if(totalDistance == 0) return 0;
   
   double progression = currentDistance / totalDistance;
   
   PrintFormat("Profit Progression: %.2f%% (Distance: %.5f/%.5f)", progression * 100, currentDistance, totalDistance);
   return progression;
}

//+------------------------------------------------------------------+
//| Calculate new stop loss based on profit progression              |
//+------------------------------------------------------------------+
double CalculateNewStopLoss(int direction, double openPrice, double currentPrice, double tp, double currentSL, double progression)
{
   double newSL = currentSL;
   double totalDistance = MathAbs(tp - openPrice);
   
   if(direction > 0) // BUY position
   {
      if(progression >= 0.25 && progression < 0.50)
      {
         // 25% progression - move SL to break even
         newSL = openPrice;
         Print("25% profit reached - Moving SL to break even");
      }
      else if(progression >= 0.50 && progression < 0.75)
      {
         // 50% progression - move SL to lock in 25% profit
         newSL = openPrice + (totalDistance * 0.25);
         Print("50% profit reached - Moving SL to lock 25% profit");
      }
      else if(progression >= 0.75)
      {
         // 75% progression - move SL to lock in 50% profit
         newSL = openPrice + (totalDistance * 0.50);
         Print("75% profit reached - Moving SL to lock 50% profit");
      }
   }
   else // SELL position
   {
      if(progression >= 0.25 && progression < 0.50)
      {
         // 25% progression - move SL to break even
         newSL = openPrice;
         Print("25% profit reached - Moving SL to break even");
      }
      else if(progression >= 0.50 && progression < 0.75)
      {
         // 50% progression - move SL to lock in 25% profit
         newSL = openPrice - (totalDistance * 0.25);
         Print("50% profit reached - Moving SL to lock 25% profit");
      }
      else if(progression >= 0.75)
      {
         // 75% progression - move SL to lock in 50% profit
         newSL = openPrice - (totalDistance * 0.50);
         Print("75% profit reached - Moving SL to lock 50% profit");
      }
   }
   
   // Validate new SL is better than current SL
   if(direction > 0)
   {
      if(newSL <= currentSL) newSL = currentSL; // Only move SL up, not down
   }
   else
   {
      if(newSL >= currentSL) newSL = currentSL; // Only move SL down, not up
   }
   
   return newSL;
}

//+------------------------------------------------------------------+
//| Check if we should update stop loss                              |
//+------------------------------------------------------------------+
bool ShouldUpdateSL(int direction, double currentSL, double newSL)
{
   if(direction > 0) // BUY
   {
      return (newSL > currentSL && MathAbs(newSL - currentSL) > point * 10); // Minimum 10 points difference
   }
   else // SELL
   {
      return (newSL < currentSL && MathAbs(newSL - currentSL) > point * 10); // Minimum 10 points difference
   }
}

//+------------------------------------------------------------------+
//| Update stop loss for a position                                  |
//+------------------------------------------------------------------+
void UpdateStopLoss(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = newSL;
   // Keep the original TP
   request.tp = PositionGetDouble(POSITION_TP);
   request.magic = MagicNumber;
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         PrintFormat("Stop loss updated successfully. Ticket: %d, New SL: %.5f", ticket, newSL);
      }
      else
      {
         PrintFormat("Stop loss update failed. Error code: %d", result.retcode);
      }
   }
   else
   {
      Print("OrderSend for SL update failed. Last error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check if we're in cooling period                                 |
//+------------------------------------------------------------------+
void CheckCoolingPeriod()
{
   if(lastTradeTime > 0)
   {
      datetime currentTime = TimeCurrent();
      datetime coolingEndTime = lastTradeTime + (CoolingPeriod * 60);
      
      if(currentTime < coolingEndTime)
      {
         if(!isCooling)
         {
            isCooling = true;
            PrintFormat("Cooling period activated until %s", TimeToString(coolingEndTime));
         }
      }
      else
      {
         if(isCooling)
         {
            isCooling = false;
            Print("Cooling period ended");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if it's a new bar                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for trade signals                                          |
//+------------------------------------------------------------------+
void CheckForTradeSignal()
{
   Print("Checking for trade signals...");
   
   // Check if we already have an open position
   if(HasOpenPosition())
   {
      Print("Position already open. Waiting for it to close.");
      return;
   }
   
   // Check for bullish pattern
   if(CheckBullishPattern())
   {
      Print("Bullish pattern detected - Opening BUY trade");
      OpenBuyTrade();
      return;
   }
   
   // Check for bearish pattern
   if(CheckBearishPattern())
   {
      Print("Bearish pattern detected - Opening SELL trade");
      OpenSellTrade();
      return;
   }
   
   Print("No trade signal detected");
}

//+------------------------------------------------------------------+
//| Check for consecutive bullish candles                            |
//+------------------------------------------------------------------+
bool CheckBullishPattern()
{
   // We need ConsecutiveCandles bullish candles
   for(int i = 1; i <= ConsecutiveCandles; i++)
   {
      double open = iOpen(_Symbol, _Period, i);
      double close = iClose(_Symbol, _Period, i);
      
      // Check if candle is bullish (close > open)
      if(close <= open)
      {
         PrintFormat("Candle %d is not bullish (Open: %.5f, Close: %.5f)", i, open, close);
         return false;
      }
   }
   
   PrintFormat("Found %d consecutive bullish candles", ConsecutiveCandles);
   return true;
}

//+------------------------------------------------------------------+
//| Check for consecutive bearish candles                            |
//+------------------------------------------------------------------+
bool CheckBearishPattern()
{
   // We need ConsecutiveCandles bearish candles
   for(int i = 1; i <= ConsecutiveCandles; i++)
   {
      double open = iOpen(_Symbol, _Period, i);
      double close = iClose(_Symbol, _Period, i);
      
      // Check if candle is bearish (close < open)
      if(close >= open)
      {
         PrintFormat("Candle %d is not bearish (Open: %.5f, Close: %.5f)", i, open, close);
         return false;
      }
   }
   
   PrintFormat("Found %d consecutive bearish candles", ConsecutiveCandles);
   return true;
}

//+------------------------------------------------------------------+
//| Open buy trade                                                   |
//+------------------------------------------------------------------+
void OpenBuyTrade()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = CalculateBuySL();
   double tp = CalculateBuyTP(ask, sl);
   
   if(sl >= ask)
   {
      Print("ERROR: Stop loss is above or equal to current price. Trade rejected.");
      return;
   }
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "TwoCandleEA Buy";
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         PrintFormat("BUY trade opened successfully. Ticket: %d, Price: %.5f, SL: %.5f, TP: %.5f", 
                    result.order, result.price, sl, tp);
         lastTradeTime = TimeCurrent();
         isCooling = true;
      }
      else
      {
         PrintFormat("BUY trade failed. Error code: %d", result.retcode);
      }
   }
   else
   {
      Print("OrderSend failed. Last error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open sell trade                                                  |
//+------------------------------------------------------------------+
void OpenSellTrade()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = CalculateSellSL();
   double tp = CalculateSellTP(bid, sl);
   
   if(sl <= bid)
   {
      Print("ERROR: Stop loss is below or equal to current price. Trade rejected.");
      return;
   }
   
   MqlTradeRequest request;
   MqlTradeResult result;
   
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "TwoCandleEA Sell";
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         PrintFormat("SELL trade opened successfully. Ticket: %d, Price: %.5f, SL: %.5f, TP: %.5f", 
                    result.order, result.price, sl, tp);
         lastTradeTime = TimeCurrent();
         isCooling = true;
      }
      else
      {
         PrintFormat("SELL trade failed. Error code: %d", result.retcode);
      }
   }
   else
   {
      Print("OrderSend failed. Last error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate buy stop loss                                          |
//+------------------------------------------------------------------+
double CalculateBuySL()
{
   if(UseLowForSL)
   {
      // Use the low of the previous candle
      return iLow(_Symbol, _Period, 1);
   }
   else
   {
      // Use the close of the previous candle
      return iClose(_Symbol, _Period, 1);
   }
}

//+------------------------------------------------------------------+
//| Calculate sell stop loss                                         |
//+------------------------------------------------------------------+
double CalculateSellSL()
{
   if(UseLowForSL)
   {
      // Use the high of the previous candle
      return iHigh(_Symbol, _Period, 1);
   }
   else
   {
      // Use the close of the previous candle
      return iClose(_Symbol, _Period, 1);
   }
}

//+------------------------------------------------------------------+
//| Calculate buy take profit                                        |
//+------------------------------------------------------------------+
double CalculateBuyTP(double entryPrice, double slPrice)
{
   double risk = entryPrice - slPrice;
   double reward = risk * RiskRewardRatio;
   return entryPrice + reward;
}

//+------------------------------------------------------------------+
//| Calculate sell take profit                                       |
//+------------------------------------------------------------------+
double CalculateSellTP(double entryPrice, double slPrice)
{
   double risk = slPrice - entryPrice;
   double reward = risk * RiskRewardRatio;
   return entryPrice - reward;
}

//+------------------------------------------------------------------+
//| Check for open positions                                         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check position close event                                       |
//+------------------------------------------------------------------+
void OnTrade()
{
   // This function is called when any trade activity occurs
   static int lastPositions = 0;
   int currentPositions = PositionsTotal();
   
   if(currentPositions < lastPositions)
   {
      Print("Position closed. Cooling period will be activated after next trade.");
   }
   
   lastPositions = currentPositions;
}