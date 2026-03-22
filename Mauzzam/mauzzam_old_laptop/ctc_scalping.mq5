//+------------------------------------------------------------------+
//|                      QuickScalper EA.mq5                        |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "QuickScalper EA"
#property version   "1.00"
#property description "Scalping EA with tight risk management"

//--- Input Parameters
input double   LotSize         = 0.1;       // Lot size for trading
input int      MAPeriod        = 20;        // MA Period for trend
input int      MaxTradeDuration= 10;        // Max bars to hold trade
input double   TP_Pips         = 5.0;       // Take Profit in Pips
input double   SL_Pips         = 8.0;       // Stop Loss in Pips
input double   DeviationPips   = 3.0;       // Deviation from MA to trigger
input int      MagicNumber     = 20245;     // Unique EA ID
input bool     EnableTrailing  = true;      // Enable trailing stop
input double   TrailingStart   = 3.0;       // Pips profit to start trailing
input double   TrailingStep    = 2.0;       // Trailing step in pips
input int      MaxTradesPerDay = 50;        // Maximum trades per day

//--- Global variables
int maHandle;
double PointMultiplier;
int DailyTradeCount = 0;
datetime LastTradeDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing QuickScalper EA...");
   
   //--- Calculate point multiplier
   PointMultiplier = 1;
   if(_Digits == 3 || _Digits == 5) PointMultiplier = 10;
   
   //--- Create indicator handles
   maHandle = iMA(_Symbol, _Period, MAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
   {
      Print("Error creating MA indicator");
      return(INIT_FAILED);
   }

   Print("QuickScalper EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily trade count if new day
   CheckDailyReset();
   
   //--- Manage existing positions first
   ManagePositions();
   
   //--- Check for new entry only if no positions exist for this magic number
   if(CountPositions() == 0 && IsNewBar() && CheckTradingConditions())
   {
      CheckForEntry();
   }
}

//+------------------------------------------------------------------+
//| Count positions for this EA                                      |
//+------------------------------------------------------------------+
int CountPositions()
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
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, _Period, 0);
   
   if(currentBar != lastBar)
   {
      lastBar = currentBar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
   //--- Check daily trade limit
   if(DailyTradeCount >= MaxTradesPerDay)
   {
      Comment("Daily trade limit reached: ", DailyTradeCount);
      return false;
   }
   
   //--- Check spread (avoid high spread periods)
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > 25) // Max 2.5 pips spread (25 points)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for entry conditions                                       |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   double maValue[3];
   
   //--- Get MA values
   if(CopyBuffer(maHandle, 0, 0, 3, maValue) < 3) return;
   
   double currentMA = maValue[0];
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Calculate trade levels
   double deviationPoints = DeviationPips * PointMultiplier;
   double tpPoints = TP_Pips * PointMultiplier;
   double slPoints = SL_Pips * PointMultiplier;
   
   //--- Convert to price levels
   double deviationPrice = deviationPoints * _Point;
   double tpPrice = tpPoints * _Point;
   double slPrice = slPoints * _Point;
   
   bool buySignal = false;
   bool sellSignal = false;
   
   //--- Buy when price dips below MA
   if(bid < (currentMA - deviationPrice))
   {
      buySignal = true;
   }
   //--- Sell when price rallies above MA
   else if(ask > (currentMA + deviationPrice))
   {
      sellSignal = true;
   }
   
   //--- Execute trades
   if(buySignal)
   {
      double sl = NormalizeDouble(bid - slPrice, _Digits);
      double tp = NormalizeDouble(bid + tpPrice, _Digits);
      
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = LotSize;
      request.type = ORDER_TYPE_BUY;
      request.price = NormalizeDouble(ask, _Digits);
      request.sl = sl;
      request.tp = tp;
      request.magic = MagicNumber;
      request.comment = "QuickScalper Buy";
      request.deviation = 10;
      
      if(OrderSend(request, result))
      {
         DailyTradeCount++;
         Print("Buy order executed. Ticket: ", result.order, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Buy order failed. Error: ", GetLastError());
      }
   }
   else if(sellSignal)
   {
      double sl = NormalizeDouble(ask + slPrice, _Digits);
      double tp = NormalizeDouble(ask - tpPrice, _Digits);
      
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = LotSize;
      request.type = ORDER_TYPE_SELL;
      request.price = NormalizeDouble(bid, _Digits);
      request.sl = sl;
      request.tp = tp;
      request.magic = MagicNumber;
      request.comment = "QuickScalper Sell";
      request.deviation = 10;
      
      if(OrderSend(request, result))
      {
         DailyTradeCount++;
         Print("Sell order executed. Ticket: ", result.order, " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Sell order failed. Error: ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         ulong ticket = PositionGetTicket(i);
         long type = PositionGetInteger(POSITION_TYPE);
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         
         //--- Check time-based exit
         if(CheckTimeExit(ticket, openTime, type))
         {
            continue;
         }
         
         //--- Check trailing stop
         if(EnableTrailing)
         {
            CheckTrailingStop(ticket, type);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check time-based exit                                            |
//+------------------------------------------------------------------+
bool CheckTimeExit(ulong ticket, datetime openTime, long type)
{
   datetime currentTime = TimeCurrent();
   int secondsSinceOpen = (int)(currentTime - openTime);
   int maxSeconds = MaxTradeDuration * PeriodSeconds(_Period);
   
   if(secondsSinceOpen >= maxSeconds)
   {
      double profit = PositionGetDouble(POSITION_PROFIT);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      
      Print("Time exit triggered for ticket: ", ticket, 
            " Profit: ", NormalizeDouble(profit, 2), 
            " Pips: ", NormalizeDouble(MathAbs(currentPrice - openPrice) / (_Point * PointMultiplier), 1));
      
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.magic = MagicNumber;
      request.comment = "Time Exit";
      request.deviation = 10;
      
      if(type == POSITION_TYPE_BUY)
      {
         request.type = ORDER_TYPE_SELL;
         request.price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      }
      else
      {
         request.type = ORDER_TYPE_BUY;
         request.price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      }
      
      if(OrderSend(request, result))
      {
         Print("Time-based exit executed for ticket: ", ticket);
         return true;
      }
      else
      {
         Print("Time exit failed. Error: ", GetLastError());
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check trailing stop                                              |
//+------------------------------------------------------------------+
void CheckTrailingStop(ulong ticket, long type)
{
   double currentPrice, openPrice, currentSL;
   
   if(type == POSITION_TYPE_BUY)
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   }
   else
   {
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }
   
   openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   currentSL = PositionGetDouble(POSITION_SL);
   
   double trailingStart = TrailingStart * PointMultiplier * _Point;
   double trailingStep = TrailingStep * PointMultiplier * _Point;
   
   if(type == POSITION_TYPE_BUY)
   {
      double profit = currentPrice - openPrice;
      if(profit >= trailingStart)
      {
         double newSL = currentPrice - trailingStep;
         if(newSL > currentSL || currentSL == 0)
         {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.sl = NormalizeDouble(newSL, _Digits);
            request.tp = PositionGetDouble(POSITION_TP);
            request.position = ticket;
            request.magic = MagicNumber;
            
            if(OrderSend(request, result))
            {
               Print("Trailing SL updated to: ", newSL);
            }
            else
            {
               Print("Trailing SL update failed. Error: ", GetLastError());
            }
         }
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double profit = openPrice - currentPrice;
      if(profit >= trailingStart)
      {
         double newSL = currentPrice + trailingStep;
         if(newSL < currentSL || currentSL == 0)
         {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);
            
            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.sl = NormalizeDouble(newSL, _Digits);
            request.tp = PositionGetDouble(POSITION_TP);
            request.position = ticket;
            request.magic = MagicNumber;
            
            if(OrderSend(request, result))
            {
               Print("Trailing SL updated to: ", newSL);
            }
            else
            {
               Print("Trailing SL update failed. Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check daily reset                                                |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime today;
   TimeCurrent(today);
   today.hour = 0;
   today.min = 0;
   today.sec = 0;
   
   datetime todayStart = StructToTime(today);
   
   if(todayStart > LastTradeDate)
   {
      DailyTradeCount = 0;
      LastTradeDate = todayStart;
      Print("Daily trade counter reset");
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("QuickScalper EA deinitialized. Reason: ", reason);
   
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}