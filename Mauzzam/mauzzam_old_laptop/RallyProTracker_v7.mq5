//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic Hedging Martingale (with Safety Features)|
//|                Reverse Trigger Distances Version                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.10"
#property description "Dynamic Hedging Martingale with reverse triggers and safety features"

input bool     EnableStrategy      = true;
input int      ConsecutiveCandles  = 3;          // Number of consecutive candles required
input double   InitialLotSize      = 0.01;
input int      InitialTPPips       = 100;        // Take-profit in pips
input int      TotalLotCounts      = 30;         // Total number of hedge positions
input double   MinLotSize          = 0.02;       // Minimum lot size for hedging
input double   MaxLotSize          = 2.0;        // Maximum lot size for hedging
input double   TriggerPips         = 1000;       // Base trigger pips (will auto-generate array)
input int      ProfitTargetPips    = 1000;       // Total profit target in pips
input int      MagicNumber         = 123456;

// Safety parameters
input double   EmergencyMarginLevel = 500.0;    // Trigger emergency when Free Margin <= this value
input int      EmergencySLPips      = 50;       // Stop-loss for emergency positions
input bool     EnableSafetyFeatures = true;      // Enable/disable safety features
input int      EmergencyProfitThresholdPips = 500;  // Profit threshold (in pips) to move SL to breakeven+1

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo positionInfo;

int direction = 0; // 1 for Buy, -1 for Sell
bool initialTradeOpened = false;
double lotSequence[];
double triggerPips[];
datetime lastHedgeTime = 0;
double initialEntryPrice = 0;
bool emergencyTriggered = false; // Emergency state flag
// Add these new global variables
double emergencyEntryPrice = 0;
bool emergencyActive = false;
datetime emergencyTriggerTime = 0; // Added this missing declaration
#define PIP 10

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Generate dynamic lot sizes and trigger pips
   GenerateLotSequence();
   GenerateTriggerPipsArray();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function (COMPLETE VERSION)                         |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EnableStrategy) return;
   
   // Check Free Margin instead of Equity
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   
   // Emergency margin check
   if(EnableSafetyFeatures && !emergencyTriggered && freeMargin <= EmergencyMarginLevel)
   {
      emergencyTriggered = true;
      emergencyTriggerTime = TimeCurrent();
      Print("EMERGENCY TRIGGERED! Free Margin: ", freeMargin, " <= ", EmergencyMarginLevel);
      TriggerEmergencyHedge();
      return;
   }
   
   // Check if any emergency positions were closed by SL
   if(emergencyActive)
   {
      bool emergencyPositionsExist = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
            PositionGetInteger(POSITION_TIME) >= emergencyTriggerTime)
         {
            emergencyPositionsExist = true;
            break;
         }
      }
      
      if(!emergencyPositionsExist)
      {
         emergencyActive = false;
         // Check if price returned to emergency entry level
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(MathAbs(currentPrice - emergencyEntryPrice) < (10 * _Point))
         {
            TriggerEmergencyHedge();
         }
      }
   }
   
   

   int totalTrades = CountOpenTrades();
   if(totalTrades == 0)
   {
      emergencyTriggered = false;
      int dir = 0;
      if(CheckStrictConsecutiveCandles(dir))
      {
         direction = dir;
         initialTradeOpened = true;
         initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
         trade.SetExpertMagicNumber(MagicNumber);
         Print("First Trade at price: ", initialEntryPrice);
         
         double tpPrice = initialEntryPrice + (direction == 1 ? InitialTPPips : -InitialTPPips) * _Point * PIP;
         
         if(!trade.PositionOpen(_Symbol, 
                              direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                              InitialLotSize, 
                              initialEntryPrice,
                              0, // SL
                              tpPrice))
         {
            Print("Failed to open initial trade! Error: ", GetLastError());
         }
      }
   }
   else if(totalTrades < TotalLotCounts)
   {
      ManageHedging();
   }

   double totalProfit = GetTotalUnrealizedProfit();
   if(totalProfit >= ProfitTargetPips * _Point * PIP)
   {
      CloseAllTrades();
      initialTradeOpened = false;
      initialEntryPrice = 0;
   }
   
   // Modified profit check
   if(emergencyActive && AllEmergencyPositionsProfitable())
   {
      MoveEmergencySLToBreakevenPlus1();
   }
}
//+------------------------------------------------------------------+
//| Generate dynamic lot size sequence                               |
//+------------------------------------------------------------------+
void GenerateLotSequence()
{
   ArrayResize(lotSequence, TotalLotCounts);
   
   // Exponential growth from MinLotSize to MaxLotSize
   double growthFactor = pow(MaxLotSize/MinLotSize, 1.0/(TotalLotCounts-1));
   
   for(int i = 0; i < TotalLotCounts; i++)
   {
      lotSequence[i] = MinLotSize * pow(growthFactor, i);
      lotSequence[i] = NormalizeDouble(lotSequence[i], 2);
   }
   
   // Print generated lots for verification
   string lotStr = "Generated Lot Sequence: ";
   for(int i = 0; i < ArraySize(lotSequence); i++)
   {
      lotStr += DoubleToString(lotSequence[i], 2);
      if(i < ArraySize(lotSequence)-1) lotStr += ",";
   }
   Print(lotStr);
}

//+------------------------------------------------------------------+
//| Generate trigger pips array in REVERSE order                     |
//+------------------------------------------------------------------+
void GenerateTriggerPipsArray()
{
   ArrayResize(triggerPips, TotalLotCounts);
   
   // REVERSED trigger pips (increasing triggers)
   for(int i = 0; i < TotalLotCounts; i++)
   {
      triggerPips[i] = TriggerPips * pow(0.97, (TotalLotCounts - 1 - i));
      triggerPips[i] = NormalizeDouble(triggerPips[i], 2);
   }
   
   // Print generated triggers for verification
   string triggerStr = "REVERSED Trigger Pips: ";
   for(int i = 0; i < ArraySize(triggerPips); i++)
   {
      triggerStr += DoubleToString(triggerPips[i], 2);
      if(i < ArraySize(triggerPips)-1) triggerStr += ",";
   }
   Print(triggerStr);
}

//+------------------------------------------------------------------+
//| Count open trades                                                |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Strict consecutive candles check                                 |
//| Only returns true if ALL candles meet condition                  |
//+------------------------------------------------------------------+
bool CheckStrictConsecutiveCandles(int &dir)
{
   double openArray[], closeArray[];
   
   if(CopyOpen(_Symbol, _Period, 1, ConsecutiveCandles, openArray) < ConsecutiveCandles ||
      CopyClose(_Symbol, _Period, 1, ConsecutiveCandles, closeArray) < ConsecutiveCandles)
      return false;

   bool allBullish = true;
   bool allBearish = true;
   
   for(int i = 0; i < ConsecutiveCandles; i++)
   {
      if(closeArray[i] <= openArray[i]) allBullish = false;
      if(closeArray[i] >= openArray[i]) allBearish = false;
   }

   if(allBullish) { dir = 1; return true; }
   if(allBearish) { dir = -1; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Remove TP from initial position                                  |
//+------------------------------------------------------------------+
void RemoveInitialPositionTP()
{
   ulong initialTicket = 0;
   datetime earliestTime = D'3000.01.01';
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(posTime < earliestTime)
      {
         earliestTime = posTime;
         initialTicket = ticket;
      }
   }
   
   if(initialTicket == 0) return;
   
   if(positionInfo.SelectByTicket(initialTicket))
   {
      trade.PositionModify(initialTicket, positionInfo.StopLoss(), 0);
      Print("Removed TP from initial position #", initialTicket);
   }
}

//+------------------------------------------------------------------+
//| Get total unrealized profit                                      |
//+------------------------------------------------------------------+
double GetTotalUnrealizedProfit()
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Close all trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         trade.PositionClose(symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage hedging with reversed triggers                            |
//+------------------------------------------------------------------+
void ManageHedging()
{
   if(initialEntryPrice == 0) return;
    
   double currentPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_BID : SYMBOL_ASK);
   int openCount = CountOpenTrades();
   
   if(openCount >= TotalLotCounts) return;
   
   double cumulativeTrigger = 0;
   for(int i = 0; i < openCount; i++)
   {
      cumulativeTrigger += triggerPips[i];
   }
   
   double triggerPrice = initialEntryPrice;
   if(direction == 1)
   {
      triggerPrice -= cumulativeTrigger * PIP * _Point;
   }
   else
   {
      triggerPrice += cumulativeTrigger * PIP * _Point;
   }
   
   bool conditionMet = false;
   if(direction == 1 && currentPrice <= triggerPrice)
   {
      conditionMet = true;
   }
   else if(direction == -1 && currentPrice >= triggerPrice)
   {
      conditionMet = true;
   }
   
   if(conditionMet)
   {
      double lot = lotSequence[openCount];
      double entryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                         lot, entryPrice, 0, 0);
      
      if(openCount == 1)
      {
         RemoveInitialPositionTP();
      }
   }
}

//+------------------------------------------------------------------+
//| Modified Emergency hedge function                                |
//+------------------------------------------------------------------+
void TriggerEmergencyHedge()
{
   if(emergencyActive && emergencyEntryPrice != 0) 
   {
      // Check if price returned to emergency entry level
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(MathAbs(currentPrice - emergencyEntryPrice) < (10 * _Point)) // Small buffer
      {
         ExecuteEmergencyHedge();
         return;
      }
   }
   else
   {
      ExecuteEmergencyHedge();
   }
}

//+------------------------------------------------------------------+
//| Execute the actual emergency hedge                               |
//+------------------------------------------------------------------+
void ExecuteEmergencyHedge()
{
   Print("EMERGENCY HEDGE ACTIVATED! Free Margin: ", AccountInfoDouble(ACCOUNT_MARGIN_FREE));
   
   emergencyEntryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   emergencyActive = true;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      // Get position details
      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Determine reverse direction
      ENUM_ORDER_TYPE newDirection;
      if(posType == POSITION_TYPE_BUY) 
         newDirection = ORDER_TYPE_SELL;
      else 
         newDirection = ORDER_TYPE_BUY;
      
      // Calculate entry price
      double price = (newDirection == ORDER_TYPE_BUY) ? 
                     SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                     SymbolInfoDouble(symbol, SYMBOL_BID);
      
      // Calculate emergency SL (500 pips for Gold)
      double slDistance = EmergencySLPips * PIP * _Point;
      double slPrice = (newDirection == ORDER_TYPE_BUY) ? 
                       price - slDistance : 
                       price + slDistance;
      
      // Open reverse position with SL
      trade.SetExpertMagicNumber(MagicNumber);
      if(trade.PositionOpen(symbol, newDirection, volume, price, slPrice, 0))
      {
         Print("Emergency hedge opened at ", price, 
               " | Type: ", EnumToString(newDirection),
               " | Lots: ", volume,
               " | SL: ", slPrice);
      }
      else
      {
         Print("Failed to open emergency hedge! Error: ", GetLastError());
      }
   }
}

// Add this new function to check if all emergency positions are profitable
bool AllEmergencyPositionsProfitable()
{
   double profitThreshold = EmergencyProfitThresholdPips * _Point * PIP;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetInteger(POSITION_TIME) >= emergencyTriggerTime)
      {
         double positionProfit = PositionGetDouble(POSITION_PROFIT);
         double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         
         // For long positions
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            if((currentPrice - positionPrice) < profitThreshold)
               return false;
         }
         // For short positions
         else
         {
            if((positionPrice - currentPrice) < profitThreshold)
               return false;
         }
      }
   }
   return true;
}

// Add this function to modify SL for all emergency positions
void MoveEmergencySLToBreakevenPlus1()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && 
         PositionGetInteger(POSITION_TIME) >= emergencyTriggerTime)
      {
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double newSl;
         
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            newSl = entryPrice - (1 * _Point); // 1 pip below entry for buys
         else
            newSl = entryPrice + (1 * _Point); // 1 pip above entry for sells
         
         if(!trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP)))
            Print("Failed to modify SL for position #", ticket, " Error: ", GetLastError());
         else
            Print("Moved SL to breakeven+1 for position #", ticket, " New SL: ", newSl);
      }
   }
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up if needed
}