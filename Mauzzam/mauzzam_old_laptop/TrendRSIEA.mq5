//+------------------------------------------------------------------+
//|                                                    TrendRSIEA.mq5|
//|                        Copyright 2024, MetaQuotes Ltd.           |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "Trading Parameters"
input double   InpLotSize = 0.1;          // Lot Size
input int      InpStopLoss = 100;         // Stop Loss (points)
input int      InpTakeProfit = 200;       // Take Profit (points)
input int      InpMagicNumber = 12345;    // Magic Number
input bool     InpAllowHedging = false;   // Allow Multiple Positions

input group "Indicator Parameters"
input int      InpEmaPeriod = 21;         // EMA Period
input int      InpRsiPeriod = 14;         // RSI Period
input int      InpAdxPeriod = 14;         // ADX Period
input int      InpAtrPeriod = 14;         // ATR Period
input int      InpVwapPeriod = 20;        // VWAP Period

input group "Strategy Parameters"
input int      InpBuyRsiMin = 40;         // Buy RSI Minimum
input int      InpBuyRsiMax = 70;         // Buy RSI Maximum
input int      InpSellRsiMin = 30;        // Sell RSI Minimum
input int      InpSellRsiMax = 60;        // Sell RSI Maximum
input int      InpAdxThreshold = 20;      // ADX Minimum Threshold
input int      InpAtrLookback = 5;        // ATR Lookback Period for Rising Check

input group "Other Parameters"
input int      InpSlippage = 10;          // Slippage (points)
input string   InpTradeComment = "TrendRSI"; // Trade Comment

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int emaHandle, rsiHandle, adxHandle, atrHandle;
datetime lastBarTime;
MqlTick lastTick;
ulong buyTicket = 0;
ulong sellTicket = 0;

// VWAP Calculation arrays
double vwapBuffer[];
datetime sessionStartTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicator handles
   emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   adxHandle = iADX(_Symbol, _Period, InpAdxPeriod);
   atrHandle = iATR(_Symbol, _Period, InpAtrPeriod);
   
   if(emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE ||
      adxHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }
   
   // Initialize VWAP buffer
   ArraySetAsSeries(vwapBuffer, true);
   ArrayResize(vwapBuffer, InpVwapPeriod * 3);
   
   lastBarTime = 0;
   sessionStartTime = iTime(_Symbol, PERIOD_D1, 0); // Start of current day
   
   Print("EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   
   ArrayFree(vwapBuffer);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime && !IsTradeAllowed())
      return;
   
   // Update last bar time
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      UpdateVWAP();
   }
   
   // Get current tick
   if(!SymbolInfoTick(_Symbol, lastTick))
      return;
   
   // Check for existing positions
   if(!InpAllowHedging)
      CheckExistingPositions();
   
   // Check for trading signals if no position exists (or hedging is allowed)
   if(buyTicket == 0 || InpAllowHedging)
      CheckBuySignal();
   
   if(sellTicket == 0 || InpAllowHedging)
      CheckSellSignal();
}

//+------------------------------------------------------------------+
//| Check for existing positions                                     |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
   // Reset tickets
   buyTicket = 0;
   sellTicket = 0;
   
   // Check all positions
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               buyTicket = ticket;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               sellTicket = ticket;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate VWAP value                                             |
//+------------------------------------------------------------------+
double CalculateVWAP()
{
   double totalPV = 0;
   double totalVolume = 0;
   int barsToCalculate = MathMin(InpVwapPeriod, Bars(_Symbol, _Period));
   
   // Calculate VWAP for specified period
   for(int i = 0; i < barsToCalculate; i++)
   {
      MqlRates rates[];
      if(CopyRates(_Symbol, _Period, i, 1, rates) < 1)
         continue;
      
      // Typical price = (High + Low + Close) / 3
      double typicalPrice = (rates[0].high + rates[0].low + rates[0].close) / 3.0;
      double volume = rates[0].tick_volume;
      
      totalPV += typicalPrice * volume;
      totalVolume += volume;
   }
   
   if(totalVolume > 0)
      return totalPV / totalVolume;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Update VWAP buffer                                               |
//+------------------------------------------------------------------+
void UpdateVWAP()
{
   // Check if new day started
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if(currentDay > sessionStartTime)
   {
      sessionStartTime = currentDay;
      ArrayFill(vwapBuffer, 0, ArraySize(vwapBuffer), 0);
   }
   
   // Shift buffer
   for(int i = ArraySize(vwapBuffer) - 1; i > 0; i--)
   {
      vwapBuffer[i] = vwapBuffer[i-1];
   }
   
   // Calculate new VWAP value
   vwapBuffer[0] = CalculateVWAP();
}

//+------------------------------------------------------------------+
//| Get current VWAP value                                           |
//+------------------------------------------------------------------+
double GetVWAPValue()
{
   if(ArraySize(vwapBuffer) > 0 && vwapBuffer[0] != 0)
      return vwapBuffer[0];
   
   return CalculateVWAP(); // Fallback calculation
}

//+------------------------------------------------------------------+
//| Check buy conditions                                             |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
   // Get indicator values
   double ema[], rsi[], adxMain[], atr[];
   
   // Copy indicator data
   if(CopyBuffer(emaHandle, 0, 0, 2, ema) < 2) return;
   if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) < 2) return;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxMain) < 2) return;
   if(CopyBuffer(atrHandle, 0, 0, InpAtrLookback+1, atr) < InpAtrLookback+1) return;
   
   // Get VWAP value
   double vwap = GetVWAPValue();
   
   // Condition 1: Price > EMA 21
   bool condition1 = lastTick.ask > ema[0];
   
   // Condition 2: RSI > 40 but < 70
   bool condition2 = (rsi[0] > InpBuyRsiMin && rsi[0] < InpBuyRsiMax);
   
   // Condition 3: ADX > 20 (trend strong)
   bool condition3 = adxMain[0] > InpAdxThreshold;
   
   // Condition 4: ATR rising
   bool condition4 = IsATRRising(atr);
   
   // Debug output
   if(condition1 && condition2 && condition3 && condition4)
   {
      Print("Buy Signal Conditions Met:");
      PrintFormat("  Price: %.5f, EMA: %.5f", lastTick.ask, ema[0]);
      PrintFormat("  RSI: %.2f (Min: %d, Max: %d)", rsi[0], InpBuyRsiMin, InpBuyRsiMax);
      PrintFormat("  ADX: %.2f (Threshold: %d)", adxMain[0], InpAdxThreshold);
      PrintFormat("  ATR Rising: %s", condition4 ? "Yes" : "No");
      PrintFormat("  VWAP: %.5f (not used for buy)", vwap);
      
      OpenBuyPosition();
   }
}

//+------------------------------------------------------------------+
//| Check sell conditions                                            |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
   // Get indicator values
   double ema[], rsi[], adxMain[], atr[];
   
   // Copy indicator data
   if(CopyBuffer(emaHandle, 0, 0, 2, ema) < 2) return;
   if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) < 2) return;
   if(CopyBuffer(adxHandle, 0, 0, 2, adxMain) < 2) return;
   if(CopyBuffer(atrHandle, 0, 0, InpAtrLookback+1, atr) < InpAtrLookback+1) return;
   
   // Get VWAP value
   double vwap = GetVWAPValue();
   
   // Condition 1: Price < EMA 21
   bool condition1 = lastTick.bid < ema[0];
   
   // Condition 2: RSI < 60 but > 30
   bool condition2 = (rsi[0] > InpSellRsiMin && rsi[0] < InpSellRsiMax);
   
   // Condition 3: ADX > 20
   bool condition3 = adxMain[0] > InpAdxThreshold;
   
   // Condition 4: Price < VWAP
   bool condition4 = lastTick.bid < vwap;
   
   // Condition 5: ATR rising
   bool condition5 = IsATRRising(atr);
   
   // Debug output
   if(condition1 && condition2 && condition3 && condition4 && condition5)
   {
      Print("Sell Signal Conditions Met:");
      PrintFormat("  Price: %.5f, EMA: %.5f", lastTick.bid, ema[0]);
      PrintFormat("  RSI: %.2f (Min: %d, Max: %d)", rsi[0], InpSellRsiMin, InpSellRsiMax);
      PrintFormat("  ADX: %.2f (Threshold: %d)", adxMain[0], InpAdxThreshold);
      PrintFormat("  VWAP: %.5f, Price < VWAP: %s", vwap, condition4 ? "Yes" : "No");
      PrintFormat("  ATR Rising: %s", condition5 ? "Yes" : "No");
      
      OpenSellPosition();
   }
}

//+------------------------------------------------------------------+
//| Check if ATR is rising                                           |
//+------------------------------------------------------------------+
bool IsATRRising(double &atrArray[])
{
   // Check if current ATR is higher than previous ATRs
   if(ArraySize(atrArray) < InpAtrLookback + 1) return false;
   
   double currentATR = atrArray[0];
   double sumPrevious = 0;
   
   // Calculate average of previous ATR values
   for(int i = 1; i <= InpAtrLookback; i++)
   {
      sumPrevious += atrArray[i];
   }
   double avgPrevious = sumPrevious / InpAtrLookback;
   
   // Current ATR should be higher than average of previous ATRs
   return currentATR > avgPrevious;
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   if(!IsTradeAllowed())
   {
      Print("Trading not allowed");
      return;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Calculate SL and TP
   double sl = InpStopLoss > 0 ? lastTick.ask - InpStopLoss * _Point : 0;
   double tp = InpTakeProfit > 0 ? lastTick.ask + InpTakeProfit * _Point : 0;
   
   // Fill trade request
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(InpLotSize, 2);
   request.type = ORDER_TYPE_BUY;
   request.price = NormalizeDouble(lastTick.ask, _Digits);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = InpSlippage;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   
   // Send order
   if(!OrderSend(request, result))
   {
      Print("Buy order failed: Error ", GetLastError(), " - ", GetLastErrorText());
   }
   else if(result.retcode == TRADE_RETCODE_DONE)
   {
      PrintFormat("Buy order opened successfully: Ticket #%I64u, Price: %.5f", 
                  result.order, result.price);
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   if(!IsTradeAllowed())
   {
      Print("Trading not allowed");
      return;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Calculate SL and TP
   double sl = InpStopLoss > 0 ? lastTick.bid + InpStopLoss * _Point : 0;
   double tp = InpTakeProfit > 0 ? lastTick.bid - InpTakeProfit * _Point : 0;
   
   // Fill trade request
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = NormalizeDouble(InpLotSize, 2);
   request.type = ORDER_TYPE_SELL;
   request.price = NormalizeDouble(lastTick.bid, _Digits);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.deviation = InpSlippage;
   request.magic = InpMagicNumber;
   request.comment = InpTradeComment;
   
   // Send order
   if(!OrderSend(request, result))
   {
      Print("Sell order failed: Error ", GetLastError(), " - ", GetLastErrorText());
   }
   else if(result.retcode == TRADE_RETCODE_DONE)
   {
      PrintFormat("Sell order opened successfully: Ticket #%I64u, Price: %.5f", 
                  result.order, result.price);
   }
}

//+------------------------------------------------------------------+
//| Get error text                                                   |
//+------------------------------------------------------------------+
string GetLastErrorText()
{
   uint error = GetLastError();
   switch(error)
   {
      case 0: return "No error";
      case 1: return "No error returned";
      case 2: return "Common error";
      case 3: return "Invalid trade parameters";
      case 4: return "Trade server is busy";
      case 5: return "Old version of the client terminal";
      case 6: return "No connection with trade server";
      case 7: return "Not enough rights";
      case 8: return "Too frequent requests";
      case 9: return "Malfunctional trade operation";
      case 64: return "Account disabled";
      case 65: return "Invalid account";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 132: return "Market is closed";
      case 133: return "Trade is disabled";
      case 134: return "Not enough money";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker is busy";
      case 138: return "Requote";
      case 139: return "Order is locked";
      case 140: return "Long positions only allowed";
      case 141: return "Too many requests";
      case 145: return "Modification denied because order too close to market";
      case 146: return "Trade context is busy";
      case 147: return "Expirations are denied by broker";
      case 148: return "Too many pending orders";
      case 149: return "Hedging is prohibited";
      case 150: return "Prohibited by FIFO rules";
      default: return "Unknown error " + IntegerToString(error);
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   // Check if Expert Advisor is allowed to trade
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Terminal trading is not allowed");
      return false;
   }
   
   // Check if auto trading is allowed
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("Auto trading is not allowed in the program settings");
      return false;
   }
   
   // Check if symbol is synced
   if(!SymbolInfoInteger(_Symbol, SYMBOL_SYNCHRONIZED))
   {
      Print("Symbol data is not synchronized");
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+