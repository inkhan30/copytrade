//+------------------------------------------------------------------+
//|                                                   EMA200_EA.mq5 |
//|                        Copyright 2023, Deepseek & MetaQuotes Ltd. |
//|                                             https://www.metaquotes.net/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Deepseek & MetaQuotes Ltd."
#property link      "https://www.metaquotes.net/"
#property version   "1.03"  // Added dynamic visual improvements

// Input parameters
input double   LotSize = 0.1;           // Lot size
input int      EmaPeriod = 200;         // EMA period
input int      DistanceFromEma = 10;    // Distance from EMA to open trade (in points)
input int      TakeProfit = 10;         // Take Profit (in points)
input int      StopLoss = 10;           // Initial Stop Loss (in points)
input double   MaxRiskPercent = 2.0;    // Maximum risk percentage of capital
input bool     UseCapitalProtection = true; // Enable capital protection
input bool     ShowEntryZones = true;   // Show visual entry zones on chart
input int      VisualAlertDistance = 15; // Distance (points) when visuals become more prominent

// Global variables
int            emaHandle;
double         pointValue;
double         initialBalance;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate point value for the current symbol
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Get the initial account balance for risk management
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Create EMA indicator handle
   emaHandle = iMA(_Symbol, PERIOD_H1, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle");
      return(INIT_FAILED);
   }
   
   // Create or update visual objects
   UpdateVisualObjects();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
      
   // Remove visual objects
   if(ShowEntryZones)
   {
      ObjectDelete(0, "EMA_BaseLine");
      ObjectDelete(0, "EMA_UpperZone");
      ObjectDelete(0, "EMA_LowerZone");
      ObjectDelete(0, "EMA_UpperText");
      ObjectDelete(0, "EMA_LowerText");
   }
}
//+------------------------------------------------------------------+
//| Update visual objects on chart                                   |
//+------------------------------------------------------------------+
void UpdateVisualObjects()
{
   if(!ShowEntryZones) return;
   
   // Get current EMA value
   double emaValue[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaValue) != 1)
   {
      Print("Failed to copy EMA buffer for visual objects");
      return;
   }
   
   // Get current prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Calculate distances from EMA
   double distanceUpper = (ask - emaValue[0]) / pointValue;
   double distanceLower = (emaValue[0] - bid) / pointValue;
   
   // Determine if we should use prominent visuals
   bool prominentVisuals = (distanceUpper >= VisualAlertDistance) || (distanceLower >= VisualAlertDistance);
   
   // Calculate entry zone levels
   double upperZone = emaValue[0] + DistanceFromEma * pointValue;
   double lowerZone = emaValue[0] - DistanceFromEma * pointValue;
   
   // Create or update EMA baseline
   if(!ObjectCreate(0, "EMA_BaseLine", OBJ_HLINE, 0, 0, emaValue[0]))
   {
      ObjectMove(0, "EMA_BaseLine", 0, 0, emaValue[0]);
   }
   ObjectSetInteger(0, "EMA_BaseLine", OBJPROP_COLOR, clrRoyalBlue);
   ObjectSetInteger(0, "EMA_BaseLine", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, "EMA_BaseLine", OBJPROP_WIDTH, prominentVisuals ? 3 : 2);
   ObjectSetString(0, "EMA_BaseLine", OBJPROP_TEXT, "200 EMA");
   
   // Create or update upper entry zone
   if(!ObjectCreate(0, "EMA_UpperZone", OBJ_HLINE, 0, 0, upperZone))
   {
      ObjectMove(0, "EMA_UpperZone", 0, 0, upperZone);
   }
   ObjectSetInteger(0, "EMA_UpperZone", OBJPROP_COLOR, prominentVisuals ? clrLime : clrGreen);
   ObjectSetInteger(0, "EMA_UpperZone", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "EMA_UpperZone", OBJPROP_WIDTH, prominentVisuals ? 2 : 1);
   
   // Create or update lower entry zone
   if(!ObjectCreate(0, "EMA_LowerZone", OBJ_HLINE, 0, 0, lowerZone))
   {
      ObjectMove(0, "EMA_LowerZone", 0, 0, lowerZone);
   }
   ObjectSetInteger(0, "EMA_LowerZone", OBJPROP_COLOR, prominentVisuals ? clrOrangeRed : clrRed);
   ObjectSetInteger(0, "EMA_LowerZone", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "EMA_LowerZone", OBJPROP_WIDTH, prominentVisuals ? 2 : 1);
   
   // Create or update text labels
   if(!ObjectCreate(0, "EMA_UpperText", OBJ_TEXT, 0, TimeCurrent(), upperZone))
   {
      ObjectMove(0, "EMA_UpperText", 0, TimeCurrent(), upperZone);
   }
   ObjectSetString(0, "EMA_UpperText", OBJPROP_TEXT, "Long Entry (+" + IntegerToString(DistanceFromEma) + "pts)");
   ObjectSetInteger(0, "EMA_UpperText", OBJPROP_COLOR, prominentVisuals ? clrLime : clrGreen);
   ObjectSetInteger(0, "EMA_UpperText", OBJPROP_FONTSIZE, prominentVisuals ? 10 : 8);
   ObjectSetInteger(0, "EMA_UpperText", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   
   if(!ObjectCreate(0, "EMA_LowerText", OBJ_TEXT, 0, TimeCurrent(), lowerZone))
   {
      ObjectMove(0, "EMA_LowerText", 0, TimeCurrent(), lowerZone);
   }
   ObjectSetString(0, "EMA_LowerText", OBJPROP_TEXT, "Short Entry (-" + IntegerToString(DistanceFromEma) + "pts)");
   ObjectSetInteger(0, "EMA_LowerText", OBJPROP_COLOR, prominentVisuals ? clrOrangeRed : clrRed);
   ObjectSetInteger(0, "EMA_LowerText", OBJPROP_FONTSIZE, prominentVisuals ? 10 : 8);
   ObjectSetInteger(0, "EMA_LowerText", OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   
   // Bring all objects to the foreground
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update visual objects on each tick
   if(ShowEntryZones)
      UpdateVisualObjects();
   
   // Check for open positions
   bool hasPosition = false;
   if(PositionSelect(_Symbol))
      hasPosition = true;
   
   // Get current EMA value
   double emaValue[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaValue) != 1)
   {
      Print("Failed to copy EMA buffer");
      return;
   }
   
   // Get current bid/ask prices
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Calculate distance from EMA in points
   double distanceFromEmaLong = (ask - emaValue[0]) / pointValue;
   double distanceFromEmaShort = (emaValue[0] - bid) / pointValue;
   
   // Check if we should open a new position
   if(!hasPosition)
   {
      // Check capital protection
      if(UseCapitalProtection)
      {
         double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(currentBalance < initialBalance * (1 - MaxRiskPercent/100))
         {
            Print("Capital protection activated - not opening new trades");
            return;
         }
      }
      
      // Check for long entry condition
      if(distanceFromEmaLong >= DistanceFromEma)
      {
         // Use dynamic SL - minimum 10 points but larger if further from EMA
         double dynamicSL = MathMax(StopLoss, distanceFromEmaLong * 0.5); // SL is 50% of distance from EMA
         double sl = emaValue[0] - dynamicSL * pointValue;
         double tp = ask + TakeProfit * pointValue;
         
         // Calculate position size based on risk
         double positionSize = CalculatePositionSize(sl);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         request.volume = positionSize;
         request.type = ORDER_TYPE_BUY;
         request.price = ask;
         request.sl = sl;
         request.tp = tp;
         request.deviation = 10;
         request.type_filling = ORDER_FILLING_FOK;
         
         if(!OrderSend(request, result))
         {
            Print("Buy OrderSend failed, error code: ", GetLastError());
            return;
         }
         
         if(result.retcode != TRADE_RETCODE_DONE)
         {
            Print("Buy order failed, retcode: ", result.retcode, ", deal: ", result.deal, ", order: ", result.order);
            return;
         }
      }
      // Check for short entry condition
      else if(distanceFromEmaShort >= DistanceFromEma)
      {
         // Use dynamic SL - minimum 10 points but larger if further from EMA
         double dynamicSL = MathMax(StopLoss, distanceFromEmaShort * 0.5); // SL is 50% of distance from EMA
         double sl = emaValue[0] + dynamicSL * pointValue;
         double tp = bid - TakeProfit * pointValue;
         
         // Calculate position size based on risk
         double positionSize = CalculatePositionSize(sl);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         request.volume = positionSize;
         request.type = ORDER_TYPE_SELL;
         request.price = bid;
         request.sl = sl;
         request.tp = tp;
         request.deviation = 10;
         request.type_filling = ORDER_FILLING_FOK;
         
         if(!OrderSend(request, result))
         {
            Print("Sell OrderSend failed, error code: ", GetLastError());
            return;
         }
         
         if(result.retcode != TRADE_RETCODE_DONE)
         {
            Print("Sell order failed, retcode: ", result.retcode, ", deal: ", result.deal, ", order: ", result.order);
            return;
         }
      }
   }
   else
   {
      // Manage open position
      ManageOpenPosition(emaValue[0]);
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stopLossPrice)
{
   if(!UseCapitalProtection)
      return LotSize;
   
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (MaxRiskPercent / 100);
   
   double price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double pointsRisk = MathAbs(price - stopLossPrice) / pointValue;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   // Calculate position size that would risk the specified percentage
   double positionSize = (riskAmount / (pointsRisk * tickValue)) * LotSize;
   
   // Ensure position size is within broker limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   positionSize = MathMax(minLot, MathMin(maxLot, positionSize));
   
   return positionSize;
}

//+------------------------------------------------------------------+
//| Manage open position                                             |
//+------------------------------------------------------------------+
void ManageOpenPosition(double currentEma)
{
   if(!PositionSelect(_Symbol))
      return;
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check if we're 1 point away from TP
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(currentPrice >= (currentTP - 1 * pointValue) && currentPrice < currentTP)
      {
         // Move SL to 2 points below TP
         double newSL = currentTP - 2 * pointValue;
         
         // Only move SL if it's higher than current SL (never move it back)
         if(newSL > currentSL)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP + 5 * pointValue; // Extend TP by 5 points
            
            if(!OrderSend(request, result))
            {
               Print("Failed to modify SL/TP (buy), error code: ", GetLastError());
               return;
            }
            
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("SL/TP modification failed (buy), retcode: ", result.retcode);
               return;
            }
         }
      }
      else
      {
         // Trail SL along EMA (only if it would improve our position)
         double newSL = currentEma - StopLoss * pointValue;
         if(newSL > currentSL)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP;
            
            if(!OrderSend(request, result))
            {
               Print("Failed to trail SL (buy), error code: ", GetLastError());
               return;
            }
            
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("SL trailing failed (buy), retcode: ", result.retcode);
               return;
            }
         }
      }
   }
   else // POSITION_TYPE_SELL
   {
      if(currentPrice <= (currentTP + 1 * pointValue) && currentPrice > currentTP)
      {
         // Move SL to 2 points above TP
         double newSL = currentTP + 2 * pointValue;
         
         // Only move SL if it's lower than current SL (never move it back)
         if(newSL < currentSL)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP - 5 * pointValue; // Extend TP by 5 points
            
            if(!OrderSend(request, result))
            {
               Print("Failed to modify SL/TP (sell), error code: ", GetLastError());
               return;
            }
            
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("SL/TP modification failed (sell), retcode: ", result.retcode);
               return;
            }
         }
      }
      else
      {
         // Trail SL along EMA (only if it would improve our position)
         double newSL = currentEma + StopLoss * pointValue;
         if(newSL < currentSL)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currentTP;
            
            if(!OrderSend(request, result))
            {
               Print("Failed to trail SL (sell), error code: ", GetLastError());
               return;
            }
            
            if(result.retcode != TRADE_RETCODE_DONE)
            {
               Print("SL trailing failed (sell), retcode: ", result.retcode);
               return;
            }
         }
      }
   }
}
//+------------------------------------------------------------------+