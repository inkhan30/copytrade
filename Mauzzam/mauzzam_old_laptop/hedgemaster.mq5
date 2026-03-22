//+------------------------------------------------------------------+
//|                                                  HedgeMasterEA.mq5 |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Entry Settings ==="
enum ENTRY_MODE
{
   ENTRY_RSI,           // RSI Based
   ENTRY_CONSECUTIVE,   // Consecutive Candles
   ENTRY_MANUAL         // Manual Entry
};

input ENTRY_MODE          EntryMode = ENTRY_MANUAL;    // Entry Mode
input bool                EnableTrading = true;        // Enable Trading

// RSI Settings
input int                 RSIPeriod = 14;              // RSI Period
input double              RSIOverbought = 70;          // RSI Overbought Level
input double              RSIOversold = 30;            // RSI Oversold Level

// Consecutive Candles Settings
input int                 ConsecutiveBars = 3;         // Consecutive Bars Count
input bool                ConsecutiveUp = true;        // Consecutive Up Bars

// Trading Settings
input group "=== Trading Settings ==="
input double              LotSize = 0.01;              // Lot Size
input int                 StopLossPips = 100;          // Stop Loss (Pips)
input int                 TakeProfitPips = 100;        // Take Profit (Pips)
input int                 TrailPips = 50;              // Trail SL (Pips)
input int                 MaxTradesPerDay = 0;         // Max Trades Per Day (0=Unlimited)
input double              MaxDrawdownPercent = 0;      // Max Drawdown % (0=Disabled)
input int                 CoolingPeriod = 0;           // Cooling Period (Minutes)

// Display Settings
input color               BuyTextColor = clrLime;      // Buy Text Color
input color               SellTextColor = clrRed;      // Sell Text Color
input color               InfoTextColor = clrWhite;    // Info Text Color

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
datetime lastTradeTime;
int tradesToday = 0;
datetime lastTradeDate = 0;
double initialBalance = 0;
bool coolingActive = false;
datetime coolingEndTime = 0;

// Position tracking
long buyTicket = -1;
long sellTicket = -1;
bool positionsOpen = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("HedgeMaster EA initialized successfully");
   
   // Get initial balance
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Reset daily trades counter if date changed
   if(TimeCurrent() > lastTradeDate + 86400)
   {
      tradesToday = 0;
      lastTradeDate = TimeCurrent();
   }
   
   // Create chart objects for display
   CreateChartObjects();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("HedgeMaster EA deinitialized. Reason: ", reason);
   DeleteChartObjects();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update display
   UpdateDisplay();
   
   // Check if trading is enabled
   if(!EnableTrading)
      return;
   
   // Check drawdown limit
   if(!CheckDrawdown())
      return;
   
   // Check cooling period
   if(!CheckCoolingPeriod())
      return;
   
   // Check daily trade limit
   if(!CheckDailyTradeLimit())
      return;
   
   // Manage existing positions
   ManagePositions();
   
   // Check for new entry if no positions open
   if(!positionsOpen)
   {
      if(CheckEntrySignal())
      {
         OpenHedgePositions();
      }
   }
}

//+------------------------------------------------------------------+
//| Check entry signal based on selected mode                        |
//+------------------------------------------------------------------+
bool CheckEntrySignal()
{
   switch(EntryMode)
   {
      case ENTRY_RSI:
         return CheckRSISignal();
      
      case ENTRY_CONSECUTIVE:
         return CheckConsecutiveSignal();
      
      case ENTRY_MANUAL:
         return CheckManualSignal();
   }
   return false;
}

//+------------------------------------------------------------------+
//| RSI based entry signal                                           |
//+------------------------------------------------------------------+
bool CheckRSISignal()
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   int handle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   
   if(CopyBuffer(handle, 0, 0, 3, rsi) < 3)
      return false;
   
   // Check for overbought/oversold conditions
   if(rsi[1] > RSIOverbought || rsi[1] < RSIOversold)
   {
      Print("RSI Signal detected. RSI: ", rsi[1]);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Consecutive candles entry signal                                 |
//+------------------------------------------------------------------+
bool CheckConsecutiveSignal()
{
   double open[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(_Symbol, _Period, 0, ConsecutiveBars + 1, open) < ConsecutiveBars + 1)
      return false;
   
   if(CopyClose(_Symbol, _Period, 0, ConsecutiveBars + 1, close) < ConsecutiveBars + 1)
      return false;
   
   bool consecutiveUp = true;
   bool consecutiveDown = true;
   
   for(int i = 1; i <= ConsecutiveBars; i++)
   {
      if(close[i] <= open[i]) consecutiveUp = false;
      if(close[i] >= open[i]) consecutiveDown = false;
   }
   
   if((ConsecutiveUp && consecutiveUp) || (!ConsecutiveUp && consecutiveDown))
   {
      Print("Consecutive bars signal detected");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manual entry signal                                              |
//+------------------------------------------------------------------+
bool CheckManualSignal()
{
   // For manual mode, we need external trigger
   // This could be modified to use chart events or other triggers
   static bool manualTrigger = false;
   
   // Reset manual trigger if positions were closed
   if(!positionsOpen)
      manualTrigger = false;
   
   return manualTrigger;
}

//+------------------------------------------------------------------+
//| Open hedge positions (both buy and sell)                         |
//+------------------------------------------------------------------+
void OpenHedgePositions()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = StopLossPips * point * 10;
   double tp = TakeProfitPips * point * 10;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Open buy position
   MqlTradeRequest buyRequest = {};
   MqlTradeResult buyResult = {};
   
   buyRequest.action = TRADE_ACTION_DEAL;
   buyRequest.symbol = _Symbol;
   buyRequest.volume = LotSize;
   buyRequest.type = ORDER_TYPE_BUY;
   buyRequest.price = price;
   buyRequest.sl = price - sl;
   buyRequest.tp = price + tp;
   buyRequest.deviation = 10;
   buyRequest.magic = 12345;
   buyRequest.comment = "HedgeMaster Buy";
   
   if(OrderSend(buyRequest, buyResult))
   {
      buyTicket = buyResult.order;
      Print("Buy position opened. Ticket: ", buyTicket);
   }
   else
   {
      Print("Failed to open buy position. Error: ", GetLastError());
      return;
   }
   
   // Open sell position
   price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   MqlTradeRequest sellRequest = {};
   MqlTradeResult sellResult = {};
   
   sellRequest.action = TRADE_ACTION_DEAL;
   sellRequest.symbol = _Symbol;
   sellRequest.volume = LotSize;
   sellRequest.type = ORDER_TYPE_SELL;
   sellRequest.price = price;
   sellRequest.sl = price + sl;
   sellRequest.tp = price - tp;
   sellRequest.deviation = 10;
   sellRequest.magic = 12345;
   sellRequest.comment = "HedgeMaster Sell";
   
   if(OrderSend(sellRequest, sellResult))
   {
      sellTicket = sellResult.order;
      Print("Sell position opened. Ticket: ", sellTicket);
      positionsOpen = true;
      tradesToday++;
      lastTradeTime = TimeCurrent();
   }
   else
   {
      Print("Failed to open sell position. Error: ", GetLastError());
      // Close the buy position if sell failed
      ClosePosition(buyTicket);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!positionsOpen)
      return;
   
   // Check if positions still exist
   bool buyExists = PositionSelectByTicket(buyTicket);
   bool sellExists = PositionSelectByTicket(sellTicket);
   
   if(!buyExists || !sellExists)
   {
      // One or both positions closed
      positionsOpen = false;
      
      // Close remaining position
      if(buyExists) ClosePosition(buyTicket);
      if(sellExists) ClosePosition(sellTicket);
      
      // Start cooling period
      if(CoolingPeriod > 0)
      {
         coolingActive = true;
         coolingEndTime = TimeCurrent() + (CoolingPeriod * 60);
         Print("Cooling period started. Ends at: ", TimeToString(coolingEndTime));
      }
      
      Print("Hedge positions closed");
      return;
   }
   
   // Trail stop loss for profitable positions
   TrailStopLoss();
}

//+------------------------------------------------------------------+
//| Close specified position                                         |
//+------------------------------------------------------------------+
void ClosePosition(long ticket)
{
   if(PositionSelectByTicket(ticket))
   {
      ulong posTicket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      string symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = symbol;
      request.volume = volume;
      request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price = (type == POSITION_TYPE_BUY) ? 
                     SymbolInfoDouble(symbol, SYMBOL_BID) : 
                     SymbolInfoDouble(symbol, SYMBOL_ASK);
      request.deviation = 10;
      request.magic = 12345;
      request.comment = "HedgeMaster Close";
      request.position = posTicket;
      
      if(OrderSend(request, result))
      {
         Print("Position closed. Ticket: ", ticket);
      }
      else
      {
         Print("Failed to close position. Ticket: ", ticket, " Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Trail stop loss for profitable positions                         |
//+------------------------------------------------------------------+
void TrailStopLoss()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double trailDistance = TrailPips * point * 10;
   
   // Trail buy position
   if(PositionSelectByTicket(buyTicket))
   {
      double currentSL = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL = currentPrice - trailDistance;
      
      if(newSL > currentSL && newSL > openPrice)
      {
         ModifyStopLoss(buyTicket, newSL);
      }
   }
   
   // Trail sell position
   if(PositionSelectByTicket(sellTicket))
   {
      double currentSL = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = currentPrice + trailDistance;
      
      if(newSL < currentSL && newSL < openPrice)
      {
         ModifyStopLoss(sellTicket, newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Modify stop loss for position                                    |
//+------------------------------------------------------------------+
void ModifyStopLoss(long ticket, double newSL)
{
   if(PositionSelectByTicket(ticket))
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;
      request.sl = newSL;
      request.position = PositionGetInteger(POSITION_TICKET);
      
      if(OrderSend(request, result))
      {
         Print("Stop loss modified for ticket: ", ticket, " New SL: ", newSL);
      }
   }
}

//+------------------------------------------------------------------+
//| Check daily trade limit                                          |
//+------------------------------------------------------------------+
bool CheckDailyTradeLimit()
{
   if(MaxTradesPerDay == 0)
      return true;
   
   // Reset counter if new day
   if(TimeCurrent() > lastTradeDate + 86400)
   {
      tradesToday = 0;
      lastTradeDate = TimeCurrent();
   }
   
   return (tradesToday < MaxTradesPerDay);
}

//+------------------------------------------------------------------+
//| Check capital drawdown                                           |
//+------------------------------------------------------------------+
bool CheckDrawdown()
{
   if(MaxDrawdownPercent == 0)
      return true;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = ((initialBalance - currentBalance) / initialBalance) * 100;
   
   if(drawdown >= MaxDrawdownPercent)
   {
      Print("Maximum drawdown limit reached: ", drawdown, "%");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check cooling period                                             |
//+------------------------------------------------------------------+
bool CheckCoolingPeriod()
{
   if(!coolingActive)
      return true;
   
   if(TimeCurrent() >= coolingEndTime)
   {
      coolingActive = false;
      Print("Cooling period ended");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Create chart objects for display                                 |
//+------------------------------------------------------------------+
void CreateChartObjects()
{
   // Buy orders text
   ObjectCreate(0, "BuyText", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "BuyText", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "BuyText", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "BuyText", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, "BuyText", OBJPROP_COLOR, BuyTextColor);
   ObjectSetInteger(0, "BuyText", OBJPROP_FONTSIZE, 10);
   
   // Sell orders text
   ObjectCreate(0, "SellText", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "SellText", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "SellText", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "SellText", OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, "SellText", OBJPROP_COLOR, SellTextColor);
   ObjectSetInteger(0, "SellText", OBJPROP_FONTSIZE, 10);
   
   // Info text
   ObjectCreate(0, "InfoText", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "InfoText", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "InfoText", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "InfoText", OBJPROP_YDISTANCE, 60);
   ObjectSetInteger(0, "InfoText", OBJPROP_COLOR, InfoTextColor);
   ObjectSetInteger(0, "InfoText", OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Update chart display                                             |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   int totalBuy = 0, totalSell = 0;
   
   // Count open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i))
      {
         if(PositionGetInteger(POSITION_MAGIC) == 12345)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               totalBuy++;
            else
               totalSell++;
         }
      }
   }
   
   // Update display objects - FIXED: Use proper ObjectSetString syntax
   ObjectSetString(0, "BuyText", OBJPROP_TEXT, "Buy Orders: " + IntegerToString(totalBuy));
   ObjectSetString(0, "SellText", OBJPROP_TEXT, "Sell Orders: " + IntegerToString(totalSell));
   
   string info = "Trades Today: " + IntegerToString(tradesToday);
   if(coolingActive)
      info += " | Cooling: " + IntegerToString((int)(coolingEndTime - TimeCurrent()) / 60) + "m";
   
   ObjectSetString(0, "InfoText", OBJPROP_TEXT, info);
}

//+------------------------------------------------------------------+
//| Delete chart objects                                             |
//+------------------------------------------------------------------+
void DeleteChartObjects()
{
   ObjectDelete(0, "BuyText");
   ObjectDelete(0, "SellText");
   ObjectDelete(0, "InfoText");
}

//+------------------------------------------------------------------+
//| Manual trigger function (can be called from outside)             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 69) // Press 'E' key for manual entry (69 is 'E' key code)
   {
      if(EntryMode == ENTRY_MANUAL && !positionsOpen && EnableTrading)
      {
         Print("Manual entry triggered by key press");
         OpenHedgePositions();
      }
   }
}

//+------------------------------------------------------------------+
//| Function to manually trigger trading from outside                |
//+------------------------------------------------------------------+
void TriggerManualTrade()
{
   if(EntryMode == ENTRY_MANUAL && !positionsOpen && EnableTrading)
   {
      Print("Manual trade triggered externally");
      OpenHedgePositions();
   }
}