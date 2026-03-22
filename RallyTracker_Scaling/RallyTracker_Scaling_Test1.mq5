//+------------------------------------------------------------------+
//|                                                  RallyTracker.mq5|
//|                                    Copyright 2025, YourNameHere |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- input parameters
input int      MagicNumber      = 123456;          // Unique EA identifier
input int      RSI_Period       = 14;               // RSI period
input int      RSI_Oversold     = 30;               // Level for long entry
input int      RSI_Overbought   = 70;               // Level for short entry
input double   InitialLot        = 0.01;             // Lot size of first position
input double   LotIncrement      = 0.01;             // Additional lot per new level
input int      MaxLevels         = 10;               // Maximum number of scaling levels
input double   StepPips          = 3.0;              // Price step between levels (in pips)
input double   InitialStopPips    = 20.0;             // Initial stop loss for first position (pips)
input double   TrailingStopPips   = 15.0;             // Trailing stop after all levels opened (pips)
input double   PipSize            = 0;                 // 0 for auto-detect, else custom pip size

//--- global variables
CTrade         trade;
CPositionInfo  posInfo;

double   pipMultiplier;          // conversion pips -> price
bool     inTrade = false;        // true when we have open positions
int      direction = 0;          // 1 = long, -1 = short
int      currentLevel = 0;       // number of positions currently open
double   lastEntryPrice = 0.0;   // price of the most recent position
double   stopLossPrice = 0.0;    // current common stop loss for all positions
double   peakPrice = 0.0;        // highest price reached (for long trailing)
double   troughPrice = 0.0;      // lowest price reached (for short trailing)
bool     trailingActive = false; // true after all levels opened

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- determine pip size
   if(PipSize == 0)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(digits == 3 || digits == 5)
         pipMultiplier = 10 * _Point;      // 5‑digit broker: 1 pip = 10 points
      else
         pipMultiplier = _Point;            // 4‑digit broker: 1 pip = 1 point
   }
   else
      pipMultiplier = PipSize * _Point;

   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if we already have positions
   if(!HasOurPositions())
   {
      // No positions → look for entry signal
      if(inTrade) inTrade = false;   // clean up flag
      CheckEntry();
   }
   else
   {
      // Positions exist → manage them
      if(!inTrade) InitializeTradeState();   // reconstruct state on first tick
      ManageTrade();
   }
}

//+------------------------------------------------------------------+
//| Check for entry signal using RSI                                 |
//+------------------------------------------------------------------+
void CheckEntry()
{
   double rsi = GetRSI();
   if(rsi == 0) return;

   if(rsi < RSI_Oversold)
   {
      // Long entry
      OpenFirstPosition(ORDER_TYPE_BUY);
   }
   else if(rsi > RSI_Overbought)
   {
      // Short entry
      OpenFirstPosition(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Open the first position with initial stop loss                   |
//+------------------------------------------------------------------+
void OpenFirstPosition(ENUM_ORDER_TYPE type)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = 0;
   if(InitialStopPips > 0)
   {
      if(type == ORDER_TYPE_BUY)
         sl = price - InitialStopPips * pipMultiplier;
      else
         sl = price + InitialStopPips * pipMultiplier;
      sl = NormalizePrice(sl);
   }

   trade.PositionOpen(_Symbol, type, InitialLot, price, sl, 0, "RallyTracker first");

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      inTrade = true;
      direction = (type == ORDER_TYPE_BUY) ? 1 : -1;
      currentLevel = 1;
      lastEntryPrice = price;
      stopLossPrice = sl;   // initial stop

      // Initialize peak/trough for trailing
      if(type == ORDER_TYPE_BUY)
         peakPrice = price;
      else
         troughPrice = price;
   }
   else
      Print("First position open failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Reconstruct trade state from existing positions                  |
//+------------------------------------------------------------------+
void InitializeTradeState()
{
   double entries[];
   double lots[];
   ENUM_POSITION_TYPE firstType = -1;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber)
      {
         if(firstType == -1)
            firstType = posInfo.PositionType();
         else if(posInfo.PositionType() != firstType)
         {
            Print("Error: mixed directions in positions. Closing all.");
            CloseAllPositions();
            return;
         }
         int idx = ArraySize(entries);
         ArrayResize(entries, idx + 1);
         ArrayResize(lots, idx + 1);
         entries[idx] = posInfo.PriceOpen();
         lots[idx]   = posInfo.Volume();
      }
   }
   if(firstType == -1) return;

   //--- sort entries in trade order (ascending for buys, descending for sells)
   if(firstType == POSITION_TYPE_BUY)
   {
      // ascending sort
      for(int i = 0; i < ArraySize(entries) - 1; i++)
         for(int j = i + 1; j < ArraySize(entries); j++)
            if(entries[i] > entries[j])
            {
               double temp = entries[i]; entries[i] = entries[j]; entries[j] = temp;
               temp = lots[i]; lots[i] = lots[j]; lots[j] = temp;
            }
      direction = 1;
   }
   else
   {
      // descending sort (highest first for shorts)
      for(int i = 0; i < ArraySize(entries) - 1; i++)
         for(int j = i + 1; j < ArraySize(entries); j++)
            if(entries[i] < entries[j])
            {
               double temp = entries[i]; entries[i] = entries[j]; entries[j] = temp;
               temp = lots[i]; lots[i] = lots[j]; lots[j] = temp;
            }
      direction = -1;
   }

   currentLevel = ArraySize(entries);
   lastEntryPrice = entries[ArraySize(entries) - 1];   // last added position

   //--- recover stop loss from any position (all should have same SL)
   stopLossPrice = 0;
   for(int i = 0; i < total; i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber)
      {
         stopLossPrice = posInfo.StopLoss();
         break;
      }

   //--- set peak/trough based on direction and current price
   if(direction == 1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      peakPrice = MathMax(bid, entries[ArraySize(entries) - 1]);
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      troughPrice = MathMin(ask, entries[ArraySize(entries) - 1]);
   }

   //--- trailing active only if we already have all levels
   trailingActive = (currentLevel >= MaxLevels);
   inTrade = true;
}

//+------------------------------------------------------------------+
//| Manage the open trade: scale in, update stop, check exit        |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!HasOurPositions())   // safety check
   {
      inTrade = false;
      return;
   }

   //--- update peak/trough for trailing
   if(direction == 1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > peakPrice) peakPrice = bid;
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask < troughPrice) troughPrice = ask;
   }

   //--- check if we can add a new level
   if(!trailingActive && currentLevel < MaxLevels)
   {
      double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double step = StepPips * pipMultiplier;
      bool trigger = false;

      if(direction == 1 && currentPrice >= lastEntryPrice + step)
         trigger = true;
      else if(direction == -1 && currentPrice <= lastEntryPrice - step)
         trigger = true;

      if(trigger)
      {
         //--- calculate next lot size
         double nextLot = InitialLot + (currentLevel * LotIncrement);   // currentLevel is number of existing positions (1-based)
         //--- normalize lot to broker limits
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         nextLot = MathMax(minLot, MathMin(maxLot, MathRound(nextLot / stepLot) * stepLot));

         double entryPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         trade.PositionOpen(_Symbol, (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                            nextLot, entryPrice, 0, 0, "RallyTracker scale");

         if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            currentLevel++;
            lastEntryPrice = entryPrice;
            stopLossPrice = entryPrice;   // new common stop

            //--- move all positions' stop loss to the new entry price
            SetGlobalStopLoss(stopLossPrice);

            //--- if we just reached max levels, activate trailing
            if(currentLevel >= MaxLevels)
            {
               trailingActive = true;
               // initialize peak/trough for trailing from current price
               if(direction == 1)
                  peakPrice = MathMax(peakPrice, entryPrice);
               else
                  troughPrice = MathMin(troughPrice, entryPrice);
            }
         }
         else
            Print("Scale‑in failed: ", trade.ResultRetcodeDescription());
      }
   }

   //--- check stop loss hit (if not trailing or before trailing)
   if(!trailingActive)
   {
      bool stopHit = false;
      if(direction == 1)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid <= stopLossPrice) stopHit = true;
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask >= stopLossPrice) stopHit = true;
      }
      if(stopHit)
      {
         CloseAllPositions();
         return;
      }
   }

   //--- trailing stop check (after all levels opened)
   if(trailingActive)
   {
      bool trailExit = false;
      double trailDist = TrailingStopPips * pipMultiplier;

      if(direction == 1)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid <= peakPrice - trailDist)
            trailExit = true;
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask >= troughPrice + trailDist)
            trailExit = true;
      }

      if(trailExit)
         CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Check if any position with our magic exists                      |
//+------------------------------------------------------------------+
bool HasOurPositions()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Set the same stop loss for all open positions                    |
//+------------------------------------------------------------------+
void SetGlobalStopLoss(double slPrice)
{
   slPrice = NormalizePrice(slPrice);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber)
      {
         ulong ticket = posInfo.Ticket();
         double currentSL = posInfo.StopLoss();
         // only modify if new SL is different and valid
         if(MathAbs(slPrice - currentSL) > _Point)
         {
            trade.PositionModify(ticket, slPrice, posInfo.TakeProfit());
            if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
               Print("Failed to modify SL for ticket ", ticket, ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions with our magic number                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == MagicNumber)
      {
         trade.PositionClose(posInfo.Ticket());
         if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
            Print("Failed to close position ", posInfo.Ticket(), ": ", trade.ResultRetcodeDescription());
      }
   }
   inTrade = false;
   trailingActive = false;
}

//+------------------------------------------------------------------+
//| Get current RSI value                                            |
//+------------------------------------------------------------------+
double GetRSI()
{
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   int handle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
   {
      Print("Failed to create RSI handle");
      return 0;
   }
   if(CopyBuffer(handle, 0, 0, 1, rsiBuffer) < 1)
   {
      Print("Failed to copy RSI buffer");
      IndicatorRelease(handle);
      return 0;
   }
   IndicatorRelease(handle);
   return rsiBuffer[0];
}

//+------------------------------------------------------------------+
//| Normalise price to the symbol's tick size                        |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, _Digits);
}
//+------------------------------------------------------------------+