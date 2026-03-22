//+------------------------------------------------------------------+
//|                                                      RSITrailEA.mq5 |
//|                        Copyright 2025, Mauzzam Shaikh            |
//|                                              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Mauzzam"
#property link      "https://google.com/"
#property version   "0.2"

//+------------------------------------------------------------------+
//| Input parameters                                                |
//+------------------------------------------------------------------+
input int      RSIPeriod = 14;               // RSI Period
input int      EMAPeriod = 50;               // EMA Period
input double   TakeProfitPips = 50;          // Take Profit in Pips
input double   LotSize = 0.1;                // Lot Size
input bool     UseCapitalProtection = true;  // Enable Capital Protection
input double   MaxRiskPercent = 2.0;         // Max Risk % of Capital
input bool     AllowManualUpdate = true;     // Allow Manual Updates
input double   NoTradeZonePips = 10.0;       // Avoid trading this close to EMA
input int      TrailingStopCandles = 3;      // Number of candles to look back for trailing SL

//+------------------------------------------------------------------+
//| Global variables                                                |
//+------------------------------------------------------------------+
double emaBuffer[];                          // EMA buffer
double rsiBuffer[];                          // RSI buffer
double closePrices[];                        // Close prices array
double lowPrices[];                          // Low prices array
double highPrices[];                         // High prices array
int emaHandle;                               // EMA indicator handle
int rsiHandle;                               // RSI indicator handle
double currentCapital;                       // Current account balance
double lastStopLossBuy = 0;                  // Last Buy SL value
double lastStopLossSell = 0;                 // Last Sell SL value

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicators
   emaHandle = iMA(_Symbol, _Period, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   
   // Set buffers
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(rsiBuffer, true);
   ArraySetAsSeries(closePrices, true);
   ArraySetAsSeries(lowPrices, true);
   ArraySetAsSeries(highPrices, true);
   
   // Get current capital
   currentCapital = AccountInfoDouble(ACCOUNT_BALANCE);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaHandle);
   IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update capital if capital protection is enabled
   if(UseCapitalProtection)
   {
      currentCapital = AccountInfoDouble(ACCOUNT_BALANCE);
   }
   
   // Get price data - we need more periods for trailing stop
   int candlesNeeded = TrailingStopCandles + 3; // Extra candles for signal confirmation
   if(CopyClose(_Symbol, _Period, 0, candlesNeeded, closePrices) < candlesNeeded ||
      CopyLow(_Symbol, _Period, 0, candlesNeeded, lowPrices) < candlesNeeded ||
      CopyHigh(_Symbol, _Period, 0, candlesNeeded, highPrices) < candlesNeeded ||
      CopyBuffer(emaHandle, 0, 0, 3, emaBuffer) < 3 || 
      CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3)
   {
      Print("Failed to copy indicator buffers");
      return;
   }
   
   // Check for open positions
   CheckOpenPositions();
   
   // Check for new trading signals
   CheckForSignals();
}

//+------------------------------------------------------------------+
//| Check for new trading signals                                    |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   // Get current price and indicator values
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentEMA = emaBuffer[0];
   double currentRSI = rsiBuffer[0];
   double prevRSI = rsiBuffer[1];
   
   // Calculate distance from EMA in pips
   double distanceFromEMA = MathAbs(currentPrice - currentEMA) / _Point / 10;
   
   // Avoid trading when RSI is between 30-70 or price is too close to EMA
   if((currentRSI > 30 && currentRSI < 70) || distanceFromEMA < NoTradeZonePips)
   {
      return;
   }
   
   // Check for buy signal with 2 candle confirmation
   if(currentRSI >= 70 && prevRSI >= 70 && 
      currentPrice > currentEMA && 
      closePrices[0] > closePrices[1]) // Current close > previous close
   {
      // Additional confirmation: previous candle was also above EMA
      if(closePrices[1] > emaBuffer[1])
      {
         // Calculate lot size with capital protection if enabled
         double lotSize = CalculateLotSize();
         
         // Calculate stop loss (previous candle low)
         double stopLoss = lowPrices[1];
         
         // Calculate take profit
         double takeProfit = currentPrice + TakeProfitPips * _Point * 10;
         
         // Open buy position
         OpenPosition(ORDER_TYPE_BUY, lotSize, stopLoss, takeProfit);
      }
   }
   
   // Check for sell signal with 2 candle confirmation
   if(currentRSI <= 30 && prevRSI <= 30 && 
      currentPrice < currentEMA && 
      closePrices[0] < closePrices[1]) // Current close < previous close
   {
      // Additional confirmation: previous candle was also below EMA
      if(closePrices[1] < emaBuffer[1])
      {
         // Calculate lot size with capital protection if enabled
         double lotSize = CalculateLotSize();
         
         // Calculate stop loss (previous candle high)
         double stopLoss = highPrices[1];
         
         // Calculate take profit
         double takeProfit = currentPrice - TakeProfitPips * _Point * 10;
         
         // Open sell position
         OpenPosition(ORDER_TYPE_SELL, lotSize, stopLoss, takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size with capital protection                       |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double calculatedLotSize = LotSize;
   
   if(UseCapitalProtection)
   {
      // Calculate risk amount in account currency
      double riskAmount = currentCapital * (MaxRiskPercent / 100);
      
      // Get symbol information for lot calculation
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      if(tickSize > 0 && tickValue > 0)
      {
         // Calculate maximum allowed lot size based on risk
         calculatedLotSize = (riskAmount / (TakeProfitPips * _Point * 10)) * (tickSize / tickValue);
         
         // Normalize to lot step
         calculatedLotSize = MathFloor(calculatedLotSize / lotStep) * lotStep;
         
         // Ensure minimum and maximum lot sizes are respected
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         calculatedLotSize = MathMax(minLot, MathMin(maxLot, calculatedLotSize));
      }
   }
   
   return calculatedLotSize;
}

//+------------------------------------------------------------------+
//| Open a new position                                              |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double lotSize, double stopLoss, double takeProfit)
{
   // Check if there are no open positions for this symbol
   if(PositionSelect(_Symbol))
   {
      return; // Position already exists
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.type_filling = ORDER_FILLING_FOK;
   
   // Send order
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed: ", GetLastError());
   }
   else
   {
      // Update last stop loss values
      if(orderType == ORDER_TYPE_BUY)
      {
         lastStopLossBuy = stopLoss;
      }
      else
      {
         lastStopLossSell = stopLoss;
      }
   }
}

//+------------------------------------------------------------------+
//| Check and manage open positions                                  |
//+------------------------------------------------------------------+
void CheckOpenPositions()
{
   if(PositionSelect(_Symbol))
   {
      // Get position details
      double currentStopLoss = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // For buy positions
      if(positionType == POSITION_TYPE_BUY)
      {
         // Find the lowest low in the last TrailingStopCandles candles
         double lowestLow = lowPrices[1];
         for(int i = 2; i <= TrailingStopCandles; i++)
         {
            if(lowPrices[i] < lowestLow)
               lowestLow = lowPrices[i];
         }
         
         // Calculate new stop loss (lowest low or higher than previous)
         double newStopLoss = MathMax(lowestLow, lastStopLossBuy);
         
         // Update if SL needs to be moved up
         if(newStopLoss > currentStopLoss)
         {
            ModifyStopLoss(newStopLoss);
            lastStopLossBuy = newStopLoss;
         }
      }
      // For sell positions
      else if(positionType == POSITION_TYPE_SELL)
      {
         // Find the highest high in the last TrailingStopCandles candles
         double highestHigh = highPrices[1];
         for(int i = 2; i <= TrailingStopCandles; i++)
         {
            if(highPrices[i] > highestHigh)
               highestHigh = highPrices[i];
         }
         
         // Calculate new stop loss (highest high or lower than previous)
         double newStopLoss = MathMin(highestHigh, lastStopLossSell);
         
         // Update if SL needs to be moved down
         if(newStopLoss < currentStopLoss || currentStopLoss == 0)
         {
            ModifyStopLoss(newStopLoss);
            lastStopLossSell = newStopLoss;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify stop loss for open position                               |
//+------------------------------------------------------------------+
void ModifyStopLoss(double newStopLoss)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.symbol = _Symbol;
   request.sl = newStopLoss;
   request.position = PositionGetInteger(POSITION_TICKET);
   
   // Keep existing take profit
   request.tp = PositionGetDouble(POSITION_TP);
   
   // Send modification request
   if(!OrderSend(request, result))
   {
      Print("Failed to modify stop loss: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Manual update function                                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle manual update if enabled
   if(AllowManualUpdate && id == CHARTEVENT_KEYDOWN && lparam == 'U')
   {
      Print("Manual update triggered");
      currentCapital = AccountInfoDouble(ACCOUNT_BALANCE);
      lastStopLossBuy = 0;
      lastStopLossSell = 0;
   }
}
//+------------------------------------------------------------------+