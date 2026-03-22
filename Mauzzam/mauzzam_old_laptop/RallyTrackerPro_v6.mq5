//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic Hedging Martingale                       |
//|                Reverse Trigger Distances Version                |
//+------------------------------------------------------------------+
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!EnableStrategy) return;

   int totalTrades = CountOpenTrades();
   if(totalTrades == 0)
   {
      if(CheckStrictConsecutiveCandles(direction))
      {
         initialTradeOpened = true;
         initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
         trade.SetExpertMagicNumber(MagicNumber);
         Print("First Trade at price: ", initialEntryPrice);
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           InitialLotSize, initialEntryPrice,
                           0,
                           initialEntryPrice + (direction == 1 ? InitialTPPips : -InitialTPPips) * PIP * _Point);
      }
   }
   else if(totalTrades < TotalLotCounts)
   {
      ManageHedging();
   }

   double totalProfit = GetTotalUnrealizedProfit();
   if(totalProfit >= ProfitTargetPips * PIP * _Point)
   {
      CloseAllTrades();
      initialTradeOpened = false;
      initialEntryPrice = 0;
   }
}

//+------------------------------------------------------------------+
//| Strict consecutive candles check                                 |
//| Only returns true if ALL candles meet condition                  |
//+------------------------------------------------------------------+
bool CheckStrictConsecutiveCandles(int &dir)
{
   double openArray[], closeArray[];
   
   if(CopyOpen(_Symbol, _Period, 1, ConsecutiveCandles, openArray) != ConsecutiveCandles ||
      CopyClose(_Symbol, _Period, 1, ConsecutiveCandles, closeArray) != ConsecutiveCandles)
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
      datetime posTime = PositionGetInteger(POSITION_TIME);
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