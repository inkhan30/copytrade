//+------------------------------------------------------------------+
//|                                                  Nanobot_v2.mq5 |
//|                        Copyright 2023, DeepSeek                  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, DeepSeek"
#property link      "https://www.mql5.com"
#property version   "2.00"

//+------------------------------------------------------------------+
//| Input parameters                                                |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT; // Chart Timeframe
input double   LotSize = 0.01;           // Fixed Lot Size
input double   MaxRiskPercentage = 10.0; // Max Risk % of Equity (Capital Protection)
input int      TakeProfitPoints = 200;    // Take Profit in Points
input int      StopLossBuffer = 5;       // Stop Loss Buffer Points from 21 EMA
input bool     EnableTrailingStop = true; // Enable Trailing Stop
input int      TrailingStepPoints = 1;   // Trailing Step in Points

//+------------------------------------------------------------------+
//| Global variables                                                |
//+------------------------------------------------------------------+
int ema9Handle, ema21Handle, ema200Handle;
double ema9[], ema21[], ema200[];
bool tradingEnabled = true;
ulong lastTicket = 0;
double currentSL = 0;
double balance, equity;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize EMA indicators
   ema9Handle = iMA(NULL, TimeFrame, 9, 0, MODE_EMA, PRICE_CLOSE);
   ema21Handle = iMA(NULL, TimeFrame, 21, 0, MODE_EMA, PRICE_CLOSE);
   ema200Handle = iMA(NULL, TimeFrame, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   if(ema9Handle == INVALID_HANDLE || ema21Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   // Set up timer to update every second
   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(ema9Handle != INVALID_HANDLE) IndicatorRelease(ema9Handle);
   if(ema21Handle != INVALID_HANDLE) IndicatorRelease(ema21Handle);
   if(ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);
   
   // Remove timer
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check capital protection
   CheckCapitalProtection();
   
   if(!tradingEnabled) return;
   
   // Get current prices
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick)) return;
   
   // Get account information
   balance = AccountInfoDouble(ACCOUNT_BALANCE);
   equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Get EMA values
   CopyBuffer(ema9Handle, 0, 0, 3, ema9);
   CopyBuffer(ema21Handle, 0, 0, 3, ema21);
   CopyBuffer(ema200Handle, 0, 0, 3, ema200);
   ArraySetAsSeries(ema9, true);
   ArraySetAsSeries(ema21, true);
   ArraySetAsSeries(ema200, true);
   
   // Check if we have an open position
   if(lastTicket > 0 && PositionSelectByTicket(lastTicket))
   {
      // Handle trailing stop if enabled
      if(EnableTrailingStop)
         TrailingStop();
      return;
   }
   
   // Check for buy condition (price above all EMAs)
   if(last_tick.ask > ema9[0] && last_tick.ask > ema21[0] && last_tick.ask > ema200[0])
   {
      OpenBuyPosition(last_tick.ask);
   }
   // Check for sell condition (price below all EMAs)
   else if(last_tick.bid < ema9[0] && last_tick.bid < ema21[0] && last_tick.bid < ema200[0])
   {
      OpenSellPosition(last_tick.bid);
   }
}

//+------------------------------------------------------------------+
//| Check capital protection                                         |
//+------------------------------------------------------------------+
void CheckCapitalProtection()
{
   if(MaxRiskPercentage <= 0) return;
   
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   double riskThreshold = initialBalance * (MaxRiskPercentage / 100);
   
   if(currentEquity <= (initialBalance - riskThreshold))
   {
      tradingEnabled = false;
      
      // Close all positions
      if(PositionSelectByTicket(lastTicket))
      {
         MqlTradeRequest request;
         ZeroMemory(request);
         MqlTradeResult result;
         ZeroMemory(result);
         
         request.action = TRADE_ACTION_DEAL;
         request.position = lastTicket;
         request.symbol = _Symbol;
         request.volume = LotSize;
         request.deviation = 10;
         request.type_filling = ORDER_FILLING_FOK;
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            request.type = ORDER_TYPE_SELL;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         }
         else
         {
            request.type = ORDER_TYPE_BUY;
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         }
         
         OrderSend(request, result);
      }
      
      Print("Capital protection activated. Trading disabled.");
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition(double entryPrice)
{
   // Calculate SL (21 EMA - buffer)
   double slPrice = ema21[0] - StopLossBuffer * _Point;
   
   // Calculate TP
   double tpPrice = entryPrice + TakeProfitPoints * _Point;
   
   // Open buy position
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = entryPrice;
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
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition(double entryPrice)
{
   // Calculate SL (21 EMA + buffer)
   double slPrice = ema21[0] + StopLossBuffer * _Point;
   
   // Calculate TP
   double tpPrice = entryPrice - TakeProfitPoints * _Point;
   
   // Open sell position
   MqlTradeRequest request;
   ZeroMemory(request);
   MqlTradeResult result;
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = entryPrice;
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
      // Calculate new SL based on 21 EMA
      newSL = ema21[0] - StopLossBuffer * _Point;
      
      // Only move SL up, not down
      if(newSL > currentPositionSL && newSL > positionOpenPrice)
      {
         MqlTradeRequest request;
         ZeroMemory(request);
         MqlTradeResult result;
         ZeroMemory(result);
         
         request.action = TRADE_ACTION_SLTP;
         request.position = lastTicket;
         request.symbol = _Symbol;
         request.sl = newSL;
         
         if(!OrderSend(request, result))
         {
            Print("Trailing stop failed. Error code: ", GetLastError());
            return;
         }
         
         currentSL = newSL;
      }
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      currentPrice = last_tick.ask;
      // Calculate new SL based on 21 EMA
      newSL = ema21[0] + StopLossBuffer * _Point;
      
      // Only move SL down, not up
      if(newSL < currentPositionSL && newSL < positionOpenPrice)
      {
         MqlTradeRequest request;
         ZeroMemory(request);
         MqlTradeResult result;
         ZeroMemory(result);
         
         request.action = TRADE_ACTION_SLTP;
         request.position = lastTicket;
         request.symbol = _Symbol;
         request.sl = newSL;
         
         if(!OrderSend(request, result))
         {
            Print("Trailing stop failed. Error code: ", GetLastError());
            return;
         }
         
         currentSL = newSL;
      }
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
//| Display information on chart                                     |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   string prefix = "NanobotV2_";
   
   // Account Information
   CreateLabel(prefix+"Balance", StringFormat("Balance: %.2f", balance), 10, 20, clrWhite, 10, "Arial Bold");
   CreateLabel(prefix+"Equity", StringFormat("Equity: %.2f", equity), 10, 50, clrWhite, 10, "Arial Bold");
   
   // Trading Status
   string statusText = tradingEnabled ? "Trading: ENABLED" : "Trading: DISABLED (Capital Protection)";
   color statusColor = tradingEnabled ? clrGreen : clrRed;
   CreateLabel(prefix+"Status", statusText, 10, 80, statusColor, 10, "Arial Bold");
   
   // Current Position
   if(lastTicket > 0 && PositionSelectByTicket(lastTicket))
   {
      string type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL";
      double profit = PositionGetDouble(POSITION_PROFIT);
      CreateLabel(prefix+"Position", StringFormat("Position: %s (%.2f)", type, profit), 10, 110, clrGold, 10, "Arial Bold");
      CreateLabel(prefix+"SL", StringFormat("Stop Loss: %.5f", currentSL), 10, 140, clrRed, 10, "Arial Bold");
   }
   else
   {
      CreateLabel(prefix+"Position", "Position: NONE", 10, 110, clrSilver, 10, "Arial Bold");
      CreateLabel(prefix+"SL", "Stop Loss: -", 10, 140, clrSilver, 10, "Arial Bold");
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