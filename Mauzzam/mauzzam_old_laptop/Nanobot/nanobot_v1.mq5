//+------------------------------------------------------------------+
//|                                                   Nanobot_v1.mq5 |
//|                        Copyright 2023, DeepSeek                  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, DeepSeek"
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                |
//+------------------------------------------------------------------+
input int      FastEMA = 10;               // Fast EMA Period
input int      SlowEMA = 21;              // Slow EMA Period
input bool     CapitalProtection = true;  // Enable Capital Protection
input color    FastEMAColor = clrGreen;   // Fast EMA Color
input color    SlowEMAColor = clrRed;     // Slow EMA Color
input ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT; // Chart Timeframe
input double   RiskPercentage = 1.0;      // Risk Percentage per Trade
input bool     UseFixedLotSize = false;   // Use Fixed Lot Size
input double   FixedLotSize = 0.1;        // Fixed Lot Size
input int      StopLossPoints = 50;       // Stop Loss in Points
input int      TakeProfitPoints = 250;    // Take Profit in Points (1:5 ratio)
input bool     EnableTrailingStop = true; // Enable Trailing Stop
input int      TrailingStopPoints = 50;   // Trailing Stop Distance in Points
input int      TrailingStepPoints = 10;   // Trailing Step in Points

//+------------------------------------------------------------------+
//| Global variables                                                |
//+------------------------------------------------------------------+
int fastEMAHandle, slowEMAHandle;
double fastEMA[], slowEMA[];
double lastFastEMA = 0, lastSlowEMA = 0;
bool crossUp = false, crossDown = false;
int crossBar = 0;
ulong lastTicket = 0;
double balance, equity, margin, freeMargin;
double currentSL = 0, currentTP = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicators
   fastEMAHandle = iMA(NULL, TimeFrame, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   slowEMAHandle = iMA(NULL, TimeFrame, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   
   if(fastEMAHandle == INVALID_HANDLE || slowEMAHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   // Set up timer to update display every second
   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove EMA lines from chart
   ObjectDelete(0, "FastEMA");
   ObjectDelete(0, "SlowEMA");
   // Release indicator handles
   if(fastEMAHandle != INVALID_HANDLE) IndicatorRelease(fastEMAHandle);
   if(slowEMAHandle != INVALID_HANDLE) IndicatorRelease(slowEMAHandle);
   
   // Remove timer
   EventKillTimer();
   
   // Delete all graphical objects
   ObjectsDeleteAll(0, "Nanobot_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastUpdate = 0;
   if(TimeCurrent() - lastUpdate >= 1) // Update every second
   {
      UpdateEMALines();
      lastUpdate = TimeCurrent();
   }
   
   // Get account information
   balance = AccountInfoDouble(ACCOUNT_BALANCE);
   equity = AccountInfoDouble(ACCOUNT_EQUITY);
   margin = AccountInfoDouble(ACCOUNT_MARGIN);
   freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Get EMA values
   CopyBuffer(fastEMAHandle, 0, 0, 3, fastEMA);
   CopyBuffer(slowEMAHandle, 0, 0, 3, slowEMA);
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   
   // Check for EMA crossover
   if(fastEMA[1] > slowEMA[1] && lastFastEMA <= lastSlowEMA)
   {
      crossUp = true;
      crossDown = false;
      crossBar = iBars(NULL, TimeFrame);
   }
   else if(fastEMA[1] < slowEMA[1] && lastFastEMA >= lastSlowEMA)
   {
      crossDown = true;
      crossUp = false;
      crossBar = iBars(NULL, TimeFrame);
   }
   
   lastFastEMA = fastEMA[1];
   lastSlowEMA = slowEMA[1];
   
   // Check for trade entry conditions
   if(crossUp && (iBars(NULL, TimeFrame) - crossBar) >= 2)
   {
      // Check if second candle after cross closes higher than previous candle
      double candle1Close = iClose(NULL, TimeFrame, 1);
      double candle2Close = iClose(NULL, TimeFrame, 0);
      double candle1Open = iOpen(NULL, TimeFrame, 1);
      
      if(candle2Close > candle1Open)
      {
         OpenBuyPosition();
         crossUp = false;
      }
   }
   else if(crossDown && (iBars(NULL, TimeFrame) - crossBar) >= 2)
   {
      // Check if second candle after cross closes lower than previous candle
      double candle1Close = iClose(NULL, TimeFrame, 1);
      double candle2Close = iClose(NULL, TimeFrame, 0);
      double candle1Open = iOpen(NULL, TimeFrame, 1);
      
      if(candle2Close < candle1Open)
      {
         OpenSellPosition();
         crossDown = false;
      }
   }
   
   // Check for trailing stop
   if(EnableTrailingStop && lastTicket > 0)
   {
      TrailingStop();
   }
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE) // Chart modified (scrolled, zoomed etc)
   {
      UpdateEMALines();
   }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Update display
   DisplayInfo();
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   // Calculate lot size
   double lotSize = CalculateLotSize();
   if(lotSize <= 0) return;
   
   // Get current price
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;
   
   // Calculate SL and TP
   double slPrice = slowEMA[0] - StopLossPoints * _Point;
   double tpPrice = 0;
   if(TakeProfitPoints > 0)
   {
      tpPrice = last_tick.ask + TakeProfitPoints * _Point;
   }
   
   // Open buy position
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = last_tick.ask;
   request.sl = slPrice;
   request.tp = tpPrice;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      Print("Buy order failed. Error code: ", GetLastError());
      return;
   }
   
   lastTicket = result.order;
   currentSL = slPrice;
   currentTP = tpPrice;
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   // Calculate lot size
   double lotSize = CalculateLotSize();
   if(lotSize <= 0) return;
   
   // Get current price
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;
   
   // Calculate SL and TP
   double slPrice = slowEMA[0] + StopLossPoints * _Point;
   double tpPrice = 0;
   if(TakeProfitPoints > 0)
   {
      tpPrice = last_tick.bid - TakeProfitPoints * _Point;
   }
   
   // Open sell position
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = last_tick.bid;
   request.sl = slPrice;
   request.tp = tpPrice;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      Print("Sell order failed. Error code: ", GetLastError());
      return;
   }
   
   lastTicket = result.order;
   currentSL = slPrice;
   currentTP = tpPrice;
}

//+------------------------------------------------------------------+
//| Calculate lot size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(UseFixedLotSize) return FixedLotSize;
   
   if(CapitalProtection && RiskPercentage <= 0) return 0;
   
   double riskAmount = balance * (RiskPercentage / 100);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = tickValue / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double lotSize = riskAmount / (StopLossPoints * pointValue);
   
   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Trailing stop function                                           |
//+------------------------------------------------------------------+
void TrailingStop()
{
   if(!PositionSelectByTicket(lastTicket)) return;
   
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;
   
   double currentPrice = 0;
   double newSL = 0;
   double currentPositionSL = PositionGetDouble(POSITION_SL);
   double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      currentPrice = last_tick.bid;
      // Only trail if price is above break-even (open price + spread)
      if(currentPrice > positionOpenPrice)
      {
         newSL = currentPrice - TrailingStopPoints * _Point;
         
         // Ensure new SL is above the original SL and previous SL
         if(newSL > currentPositionSL && newSL > (positionOpenPrice - StopLossPoints * _Point))
         {
            MqlTradeRequest request;
            ZeroMemory(request);
            MqlTradeResult result;
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_SLTP;
            request.position = lastTicket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP;
            
            if(!OrderSend(request, result))
            {
               Print("Trailing stop failed. Error code: ", GetLastError());
               return;
            }
            
            currentSL = newSL;
         }
      }
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      currentPrice = last_tick.ask;
      // Only trail if price is below break-even (open price - spread)
      if(currentPrice < positionOpenPrice)
      {
         newSL = currentPrice + TrailingStopPoints * _Point;
         
         // Ensure new SL is below the original SL and previous SL
         if(newSL < currentPositionSL && newSL < (positionOpenPrice + StopLossPoints * _Point))
         {
            MqlTradeRequest request;
            ZeroMemory(request);
            MqlTradeResult result;
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_SLTP;
            request.position = lastTicket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP;
            
            if(!OrderSend(request, result))
            {
               Print("Trailing stop failed. Error code: ", GetLastError());
               return;
            }
            
            currentSL = newSL;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Display information on chart                                     |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   // Create or update display objects
   string prefix = "Nanobot_";
   
   // Total Balance
   CreateLabel(prefix + "Balance", StringFormat("Balance: %.2f", balance), 10, 20, clrWhite, 10, "Arial Bold");
   
   // Equity
   CreateLabel(prefix + "Equity", StringFormat("Equity: %.2f", equity), 10, 50, clrWhite, 10, "Arial Bold");
   
   // Free Margin
   CreateLabel(prefix + "FreeMargin", StringFormat("Free Margin: %.2f", freeMargin), 10, 80, clrWhite, 10, "Arial Bold");
   
   // Current SL
   if(lastTicket > 0)
   {
      CreateLabel(prefix + "SL", StringFormat("Stop Loss: %.5f", currentSL), 10, 110, clrRed, 10, "Arial Bold");
      CreateLabel(prefix + "TP", StringFormat("Take Profit: %.5f", currentTP), 10, 140, clrGreen, 10, "Arial Bold");
   }
   else
   {
      CreateLabel(prefix + "SL", "Stop Loss: -", 10, 110, clrRed, 10, "Arial Bold");
      CreateLabel(prefix + "TP", "Take Profit: -", 10, 140, clrGreen, 10, "Arial Bold");
   }
}

//+------------------------------------------------------------------+
//| Create or update label                                           |
//+------------------------------------------------------------------+
void CreateLabel(const string name, const string text, const int x, const int y, const color clr, const int fontSize, const string font)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   }
   
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Create EMA objects on chart                                      |
//+------------------------------------------------------------------+
void CreateEMAObjects()
{
   // Fast EMA line
   ObjectCreate(0, "FastEMA", OBJ_TREND, 0, 0, 0);
   ObjectSetInteger(0, "FastEMA", OBJPROP_COLOR, FastEMAColor);
   ObjectSetInteger(0, "FastEMA", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "FastEMA", OBJPROP_RAY, false);
   ObjectSetString(0, "FastEMA", OBJPROP_TEXT, "EMA "+IntegerToString(FastEMA));
   
   // Slow EMA line
   ObjectCreate(0, "SlowEMA", OBJ_TREND, 0, 0, 0);
   ObjectSetInteger(0, "SlowEMA", OBJPROP_COLOR, SlowEMAColor);
   ObjectSetInteger(0, "SlowEMA", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "SlowEMA", OBJPROP_RAY, false);
   ObjectSetString(0, "SlowEMA", OBJPROP_TEXT, "EMA "+IntegerToString(SlowEMA));
   
   // Update EMA lines
   UpdateEMALines();
}
//+------------------------------------------------------------------+
//| Update EMA lines on chart                                        |
//+------------------------------------------------------------------+
void UpdateEMALines()
{
   // Get visible bars count
   int bars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int totalBars = iBars(_Symbol, TimeFrame);
   if(bars <= 0) bars = 100; // Default if can't get visible bars
   if(bars > totalBars) bars = totalBars;
   
   // Get EMA values
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   CopyBuffer(fastEMAHandle, 0, 0, bars, fast);
   CopyBuffer(slowEMAHandle, 0, 0, bars, slow);
   
   // Create/update Fast EMA line
   if(ObjectFind(0, "FastEMA") < 0)
   {
      ObjectCreate(0, "FastEMA", OBJ_TREND, 0, 0, 0);
      ObjectSetInteger(0, "FastEMA", OBJPROP_COLOR, FastEMAColor);
      ObjectSetInteger(0, "FastEMA", OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, "FastEMA", OBJPROP_RAY_RIGHT, true);
      ObjectSetString(0, "FastEMA", OBJPROP_TEXT, "EMA "+IntegerToString(FastEMA));
      ObjectSetInteger(0, "FastEMA", OBJPROP_SELECTABLE, false);
   }
   
   // Create/update Slow EMA line
   if(ObjectFind(0, "SlowEMA") < 0)
   {
      ObjectCreate(0, "SlowEMA", OBJ_TREND, 0, 0, 0);
      ObjectSetInteger(0, "SlowEMA", OBJPROP_COLOR, SlowEMAColor);
      ObjectSetInteger(0, "SlowEMA", OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, "SlowEMA", OBJPROP_RAY_RIGHT, true);
      ObjectSetString(0, "SlowEMA", OBJPROP_TEXT, "EMA "+IntegerToString(SlowEMA));
      ObjectSetInteger(0, "SlowEMA", OBJPROP_SELECTABLE, false);
   }
   
   // Update points for both EMAs
   for(int i=0; i<bars; i++)
   {
      datetime time = iTime(_Symbol, TimeFrame, i);
      ObjectMove(0, "FastEMA", i, time, fast[i]);
      ObjectMove(0, "SlowEMA", i, time, slow[i]);
   }
   
   // Extend lines to current bar
   datetime currentTime = iTime(_Symbol, TimeFrame, 0);
   ObjectMove(0, "FastEMA", bars, currentTime, fast[0]);
   ObjectMove(0, "SlowEMA", bars, currentTime, slow[0]);
}