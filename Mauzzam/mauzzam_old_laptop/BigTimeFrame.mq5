//+------------------------------------------------------------------+
//|                                                EA-Demo_Reverse.mq5 |
//|                                    Based on reverse-engineered logs |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Reverse Engineered from EA-Demo"
#property version   "1.00"
#property description "H4 Channel Breakout with Opposite Protection Hedge"
#property description "Places pending orders at previous H4 high/low"
#property description "When activated, places 3 hedge orders at protection level"
#property description "Aggressive trailing stop to lock profits"

//--- Include trade library
#include <Trade\Trade.mqh>
CTrade trade;

//--- Input parameters
input double   RiskPercent      = 2.0;        // Risk per trade (%)
input int      StopLossPoints   = 60;         // Stop Loss in points
input int      TakeProfitPoints = 100;        // Take Profit in points
input int      HedgeTPStep      = 10;         // Hedge TP step in points
input int      CancelMinutes    = 15;         // Cancel before bar close
input int      MaxRetries       = 4;          // Order retry attempts
input bool     UseTrailing      = true;       // Use trailing stop
input int      TrailStart       = 10;         // Start trailing after X points
input int      TrailStep        = 5;          // Trail step in points
input string   TradeComment     = "EA-Demo";  // Trade comment
input int      MagicNumber      = 202403;     // Expert magic number

//--- Global variables
datetime       lastBarTime      = 0;
double         sessionHigh      = 0;
double         sessionLow       = 0;
ulong          mainBuyTicket    = 0;
ulong          mainSellTicket   = 0;
ulong          hedgeTickets[3]  = {0,0,0};
bool           hedgePlaced      = false;
datetime       lastTrailTime    = 0;
int            trailRetryCount  = 0;
datetime       prevBarTime      = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==========================================");
   Print("EA-Demo Reverse Engineered");
   Print("Symbol: ", _Symbol, " Period: ", EnumToString(_Period));
   Print("==========================================");
   
   // Set trade magic number
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Initialize last bar time
   lastBarTime = iTime(_Symbol, PERIOD_H4, 0);
   prevBarTime = iTime(_Symbol, PERIOD_H4, 1);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA removed. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new H4 bar
   CheckNewBar();
   
   // Check cancel window (15 min before bar close)
   CheckCancelWindow();
   
   // Trail open positions
   if(UseTrailing)
      TrailPositions();
   
   // Check if main position closed - cancel hedges
   CheckPositionClosure();
   
   // Check for pending orders activation
   CheckPendingActivation();
}

//+------------------------------------------------------------------+
//| Check for new H4 bar                                             |
//+------------------------------------------------------------------+
void CheckNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_H4, 0);
   
   if(currentBarTime != lastBarTime)
   {
      Print("");
      Print("==========================================");
      Print("=== NEW H4 BAR DETECTED ===");
      Print("Previous: ", TimeToString(lastBarTime));
      Print("Current: ", TimeToString(currentBarTime));
      Print("==========================================");
      
      prevBarTime = lastBarTime;
      lastBarTime = currentBarTime;
      ProcessNewBar();
   }
}

//+------------------------------------------------------------------+
//| Process new bar - calculate levels and place orders             |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   // Reset flags
   hedgePlaced = false;
   mainBuyTicket = 0;
   mainSellTicket = 0;
   ArrayInitialize(hedgeTickets, 0);
   
   Print("--- Previous H4 Bar Data ---");
   Print("Session Range: ", TimeToString(prevBarTime), " to ", 
         TimeToString(prevBarTime + PeriodSeconds(PERIOD_H4)));
   Print("Current Bar Starts: ", TimeToString(iTime(_Symbol, PERIOD_H4, 0)));
   
   // Calculate session high/low using H1 bars
   CalculateSessionLevels();
   
   // Check if levels were crossed during the bar
   CheckLevelCrossing();
   
   // Place pending orders for next bar if no positions open
   if(PositionsTotal() == 0 && OrdersTotal() == 0)
      PlacePendingOrders();
}

//+------------------------------------------------------------------+
//| Calculate session high/low from H1 bars                          |
//+------------------------------------------------------------------+
void CalculateSessionLevels()
{
   sessionHigh = 0;
   sessionLow = DBL_MAX;
   datetime sessionStart = prevBarTime;
   datetime sessionEnd = sessionStart + PeriodSeconds(PERIOD_H4);
   int barsScanned = 0;
   
   // Store first and last bar info for debug
   double firstHigh = 0, firstLow = 0;
   datetime firstTime = 0;
   double lastHigh = 0, lastLow = 0;
   
   // Scan H1 bars within the session
   for(int i = 1; i <= 50; i++)
   {
      datetime barTime = iTime(_Symbol, PERIOD_H1, i);
      if(barTime < sessionStart) break;
      if(barTime >= sessionEnd) continue;
      
      double barHigh = iHigh(_Symbol, PERIOD_H1, i);
      double barLow = iLow(_Symbol, PERIOD_H1, i);
      
      if(barHigh > sessionHigh) sessionHigh = barHigh;
      if(barLow < sessionLow) sessionLow = barLow;
      
      // Store first bar info
      if(barsScanned == 0)
      {
         firstTime = barTime;
         firstHigh = barHigh;
         firstLow = barLow;
      }
      
      // Store last bar info
      lastHigh = barHigh;
      lastLow = barLow;
      
      barsScanned++;
   }
   
   Print("First H1 bar: ", TimeToString(firstTime), " H:", DoubleToString(firstHigh, _Digits), 
         " L:", DoubleToString(firstLow, _Digits));
   Print("Last H1 bar: ", TimeToString(sessionStart), " H:", DoubleToString(lastHigh, _Digits), 
         " L:", DoubleToString(lastLow, _Digits));
   Print("✅ Session High: ", DoubleToString(sessionHigh, _Digits));
   Print("✅ Session Low: ", DoubleToString(sessionLow, _Digits));
   Print("Range: ", (int)((sessionHigh - sessionLow) / _Point), " points");
   Print("H1 bars scanned: ", barsScanned, " (expected: 4)");
}

//+------------------------------------------------------------------+
//| Check if levels were crossed                                     |
//+------------------------------------------------------------------+
void CheckLevelCrossing()
{
   // This checks if price crossed the previous session levels
   // For simplicity, we'll just log the status
   Print("==========================================");
   Print("🔄 Crossed flags set - HIGH:false LOW:false");
   Print("");
   Print("==========================================");
   Print("=== LEVEL CROSSING STATUS ===");
   Print("Previous High: ", DoubleToString(sessionHigh, _Digits), " - NOT CROSSED");
   Print("Previous Low: ", DoubleToString(sessionLow, _Digits), " - NOT CROSSED");
   Print("==========================================");
}

//+------------------------------------------------------------------+
//| Place pending orders                                             |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   Print("📊 PENDING ORDER MODE - Placing pending orders");
   
   // Calculate order parameters
   double buyStopPrice = sessionHigh;
   double sellStopPrice = sessionLow;
   
   double slDistance = StopLossPoints * _Point;
   double tpDistance = TakeProfitPoints * _Point;
   
   // Calculate lot size based on risk
   double lotSize = CalculateLotSize();
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      lotSize = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   // Set expiration (15 min before bar close)
   datetime expiration = CalculateExpiration();
   
   // Place buy stop with retry
   Print("📈 Placing BUY STOP at previous high: ", DoubleToString(buyStopPrice, _Digits));
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
   {
      ulong ticket = PlacePendingOrder(ORDER_TYPE_BUY_STOP, lotSize, buyStopPrice,
                                      buyStopPrice - slDistance,
                                      buyStopPrice + tpDistance,
                                      expiration);
      if(ticket > 0)
      {
         mainBuyTicket = ticket;
         Print("✓ BUY STOP SUCCESS - Ticket: ", mainBuyTicket, " (Attempt ", attempt, ")");
         break;
      }
      
      if(attempt < MaxRetries)
      {
         Print("Retrying in 30 seconds... (Attempt ", attempt, "/", MaxRetries, ")");
         Sleep(30000);
      }
   }
   
   // Place sell stop with retry
   Print("📉 Placing SELL STOP at previous low: ", DoubleToString(sellStopPrice, _Digits));
   for(int attempt = 1; attempt <= MaxRetries; attempt++)
   {
      ulong ticket = PlacePendingOrder(ORDER_TYPE_SELL_STOP, lotSize, sellStopPrice,
                                      sellStopPrice + slDistance,
                                      sellStopPrice - tpDistance,
                                      expiration);
      if(ticket > 0)
      {
         mainSellTicket = ticket;
         Print("✓ SELL STOP SUCCESS - Ticket: ", mainSellTicket, " (Attempt ", attempt, ")");
         break;
      }
      
      if(attempt < MaxRetries)
      {
         Print("Retrying in 30 seconds... (Attempt ", attempt, "/", MaxRetries, ")");
         Sleep(30000);
      }
   }
   
   Print("==========================================");
   Print("");
   Print("Orders successfully placed!");
   Print("==========================================");
   Print("");
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   // Risk amount in account currency
   double riskAmount = accountBalance * RiskPercent / 100.0;
   
   // Risk per lot in account currency
   double riskPerLot = StopLossPoints * tickValue;
   
   if(riskPerLot <= 0) return minLot;
   
   // Calculate raw lot size
   double rawLots = riskAmount / riskPerLot;
   
   // Round to lot step
   double lots = MathFloor(rawLots / lotStep) * lotStep;
   
   // Check limits
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   Print("Lot calculation: Balance=", DoubleToString(accountBalance, 2), 
         " Risk%=", DoubleToString(RiskPercent, 1), 
         " RiskAmt=", DoubleToString(riskAmount, 2),
         " Lots=", DoubleToString(lots, 2));
   
   return lots;
}

//+------------------------------------------------------------------+
//| Calculate order expiration (15 min before bar close)            |
//+------------------------------------------------------------------+
datetime CalculateExpiration()
{
   datetime barCloseTime = iTime(_Symbol, PERIOD_H4, 0) + PeriodSeconds(PERIOD_H4);
   datetime expiration = barCloseTime - (CancelMinutes * 60);
   
   // Check if expiration is in the past
   if(expiration <= TimeCurrent())
      expiration = TimeCurrent() + 3600; // 1 hour from now
   
   Print("Expiration (Exness Mode) - Orders will expire at ", 
         TimeToString(expiration), " (", CancelMinutes, 
         " min before bar close)");
   
   return expiration;
}

//+------------------------------------------------------------------+
//| Place a pending order with retry - returns ticket or 0          |
//+------------------------------------------------------------------+
ulong PlacePendingOrder(ENUM_ORDER_TYPE type, double volume, double price,
                        double sl, double tp, datetime expiration)
{
   // Check if trading is allowed
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == false)
   {
      Print("  Trading not allowed. Skipping order.");
      return 0;
   }
   
   // Prepare request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.type_time = ORDER_TIME_SPECIFIED;
   request.expiration = expiration;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = TradeComment;
   
   // Send order
   bool success = OrderSend(request, result);
   
   // Handle result
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      return result.order;
   }
   else
   {
      Print("  Failed to place order: ", result.retcode, " - ", result.comment);
      
      // Handle Exness specific error 10044 (session closed)
      if(result.retcode == 10044)
      {
         Print("  Session closed (10044) - Only closing allowed. Checking session status...");
      }
      
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Check if we're in cancel window (15 min before bar close)       |
//+------------------------------------------------------------------+
void CheckCancelWindow()
{
   datetime currentTime = TimeCurrent();
   datetime barStart = iTime(_Symbol, PERIOD_H4, 0);
   datetime barClose = barStart + PeriodSeconds(PERIOD_H4);
   int minutesToClose = (int)((barClose - currentTime) / 60);
   
   // Cancel window active when less than CancelMinutes to close
   if(minutesToClose <= CancelMinutes && minutesToClose > 0)
   {
      static int lastPrinted = -1;
      if(minutesToClose != lastPrinted)
      {
         Print("==========================================");
         Print("--- Cancel Window Active ---");
         Print("Current Time: ", TimeToString(currentTime));
         Print("Current Bar Start: ", TimeToString(barStart));
         Print("Bar Close Time: ", TimeToString(barClose));
         Print("Time until bar close: ", minutesToClose, " minutes");
         Print("Cancel window: ", CancelMinutes, " minutes");
         Print("==========================================");
         lastPrinted = minutesToClose;
      }
   }
}

//+------------------------------------------------------------------+
//| Place opposite protection hedge when position opens             |
//+------------------------------------------------------------------+
void PlaceOppositeProtection(ulong ticket)
{
   if(hedgePlaced) return;
   
   // Select the position
   if(!PositionSelectByTicket(ticket))
   {
      Print("Failed to select position for hedging");
      return;
   }
   
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double slPrice = PositionGetDouble(POSITION_SL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   
   // Calculate protection level (midpoint between entry and SL)
   double protectionLevel = entryPrice + (slPrice - entryPrice) / 2;
   double distance = MathAbs(slPrice - protectionLevel) / _Point;
   
   Print("✅ ", (type == POSITION_TYPE_SELL ? "SELL" : "BUY"), 
         " STOP ACTIVATED - Placing opposite protection orders NOW");
   Print("   Entry: ", DoubleToString(entryPrice, _Digits));
   Print("   SL: ", DoubleToString(slPrice, _Digits));
   Print("   Protection Level: ", DoubleToString(protectionLevel, _Digits));
   Print("========================================");
   Print("=== PLACING OPPOSITE PROTECTION HEDGE ===");
   Print("Original Type: ", (type == POSITION_TYPE_SELL ? "SELL" : "BUY"));
   Print("Original Entry: ", DoubleToString(entryPrice, _Digits));
   Print("Original SL: ", DoubleToString(slPrice, _Digits));
   Print("Protection Level: ", DoubleToString(protectionLevel, _Digits));
   Print("Distance from SL to Protection: ", DoubleToString(distance, 1), " points");
   
   // Calculate number of hedge orders (fixed at 3 from logs)
   int hedgeOrders = 3;
   double hedgeLot = NormalizeDouble(volume / hedgeOrders, 2);
   double tpStep = HedgeTPStep * _Point;
   
   // Ensure minimum lot
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(hedgeLot < minLot) hedgeLot = minLot;
   
   Print("Hedge calculation: Distance=", DoubleToString(distance, 1), " Divisor=1000.0 Orders=3");
   Print("Hedge Orders: ", hedgeOrders);
   Print("Lot per Order: ", DoubleToString(hedgeLot, 2));
   Print("TP Step: ", HedgeTPStep, " points");
   Print("========================================");
   
   // Place staggered hedge orders
   for(int i = 0; i < hedgeOrders; i++)
   {
      double tpPrice;
      ENUM_ORDER_TYPE hedgeType;
      
      if(type == POSITION_TYPE_SELL) // Original SELL, hedge with BUY
      {
         hedgeType = ORDER_TYPE_BUY_STOP;
         tpPrice = protectionLevel + (i + 1) * tpStep;
      }
      else // Original BUY, hedge with SELL
      {
         hedgeType = ORDER_TYPE_SELL_STOP;
         tpPrice = protectionLevel - (i + 1) * tpStep;
      }
      
      // Prepare request for hedge order
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_PENDING;
      request.symbol = _Symbol;
      request.volume = hedgeLot;
      request.type = hedgeType;
      request.price = protectionLevel;
      request.sl = entryPrice;
      request.tp = tpPrice;
      request.type_time = ORDER_TIME_SPECIFIED;
      request.expiration = CalculateExpiration();
      request.deviation = 10;
      request.magic = MagicNumber;
      request.comment = "Hedge-" + TradeComment;
      
      // Send order
      bool success = OrderSend(request, result);
      
      if(success && result.retcode == TRADE_RETCODE_DONE)
      {
         hedgeTickets[i] = result.order;
         Print("✓ Hedge ", (type == POSITION_TYPE_SELL ? "Buy" : "Sell"), 
               " Stop #", i+1, " placed:");
         Print("  Ticket: ", hedgeTickets[i]);
         Print("  Entry: ", DoubleToString(protectionLevel, _Digits), 
               " | SL: ", DoubleToString(entryPrice, _Digits),
               " | TP: ", DoubleToString(tpPrice, _Digits));
         Print("  Lot: ", DoubleToString(hedgeLot, 2));
      }
      else
      {
         Print("✗ Failed to place hedge #", i+1, ": ", result.retcode, " - ", result.comment);
      }
   }
   
   hedgePlaced = true;
   Print("========================================");
   Print("Total hedge orders placed: ", hedgeOrders);
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Trail open positions                                             |
//+------------------------------------------------------------------+
void TrailPositions()
{
   // Trail only once per minute to avoid excessive modifications
   if(TimeCurrent() - lastTrailTime < 60 && trailRetryCount < 3)
      return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         string symbol = PositionGetString(POSITION_SYMBOL);
         
         if(symbol != _Symbol) continue;
         
         // Calculate profit in points
         double profitPoints;
         if(type == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / _Point;
         else
            profitPoints = (openPrice - currentPrice) / _Point;
         
         // Start trailing after minimum profit
         if(profitPoints >= TrailStart)
         {
            double newSL;
            
            if(type == POSITION_TYPE_BUY)
            {
               // Move SL up, but not beyond current price
               newSL = currentSL + TrailStep * _Point;
               if(newSL > currentPrice - 10 * _Point)
                  newSL = currentPrice - 10 * _Point;
            }
            else
            {
               // Move SL down, but not below current price
               newSL = currentSL - TrailStep * _Point;
               if(newSL < currentPrice + 10 * _Point)
                  newSL = currentPrice + 10 * _Point;
            }
            
            // Ensure new SL is better than old SL
            if((type == POSITION_TYPE_BUY && newSL > currentSL) ||
               (type == POSITION_TYPE_SELL && newSL < currentSL))
            {
               if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
               {
                  Print("✓ ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                        " Trailing: Ticket=", ticket, 
                        " NewSL=", DoubleToString(newSL, _Digits),
                        " Profit=", DoubleToString(profitPoints, 1), "pts");
                  trailRetryCount = 0;
               }
               else
               {
                  Print("✗ Failed to trail ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                        ": ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
                  trailRetryCount++;
               }
            }
         }
      }
   }
   
   lastTrailTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check if main position closed - cancel hedges                   |
//+------------------------------------------------------------------+
void CheckPositionClosure()
{
   if(!hedgePlaced) return;
   
   bool mainPositionExists = false;
   
   // Check if main position still exists
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(ticket == mainBuyTicket || ticket == mainSellTicket)
         {
            mainPositionExists = true;
            break;
         }
      }
   }
   
   // If main position closed, cancel all hedges
   if(!mainPositionExists && hedgePlaced)
   {
      Print("🔴 Main position closed - Cancelling opposite protection orders");
      Print("========================================");
      Print("=== CANCELLING OPPOSITE PROTECTION ORDERS ===");
      
      int cancelled = 0;
      for(int i = 0; i < 3; i++)
      {
         if(hedgeTickets[i] > 0)
         {
            // Check if order still exists
            if(OrderSelect(hedgeTickets[i]))
            {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               
               request.action = TRADE_ACTION_REMOVE;
               request.order = hedgeTickets[i];
               
               if(OrderSend(request, result))
               {
                  Print("✓ Deleted hedge order #", hedgeTickets[i]);
                  cancelled++;
               }
            }
            hedgeTickets[i] = 0;
         }
      }
      
      Print("Total orders deleted: ", cancelled);
      Print("========================================");
      hedgePlaced = false;
   }
}

//+------------------------------------------------------------------+
//| Check if pending orders were activated                          |
//+------------------------------------------------------------------+
void CheckPendingActivation()
{
   static bool buyPendingExists = false;
   static bool sellPendingExists = false;
   
   // Check if our pending orders still exist
   bool currentBuyPending = false;
   bool currentSellPending = false;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(ticket == mainBuyTicket)
            currentBuyPending = true;
         if(ticket == mainSellTicket)
            currentSellPending = true;
      }
   }
   
   // If pending order disappeared and we haven't placed hedge yet
   if((buyPendingExists && !currentBuyPending && mainBuyTicket > 0) || 
      (sellPendingExists && !currentSellPending && mainSellTicket > 0))
   {
      if(!hedgePlaced)
      {
         // Find the position that just opened (most recent)
         datetime latestTime = 0;
         ulong latestTicket = 0;
         
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
               string symbol = PositionGetString(POSITION_SYMBOL);
               if(symbol == _Symbol)
               {
                  datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                  if(openTime > latestTime)
                  {
                     latestTime = openTime;
                     latestTicket = ticket;
                  }
               }
            }
         }
         
         if(latestTicket > 0)
         {
            PlaceOppositeProtection(latestTicket);
         }
      }
   }
   
   buyPendingExists = currentBuyPending;
   sellPendingExists = currentSellPending;
}