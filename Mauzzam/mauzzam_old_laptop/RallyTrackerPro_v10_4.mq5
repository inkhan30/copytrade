//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic EMA-Based Hedging Strategy               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Dynamic hedging strategy that switches between long/short positions based on EMA"
#property description "Opens initial position based on consecutive candles, then hedges according to EMA position"
#property description "Exits when total profit target is reached"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayDouble.mqh>

//--- Input Parameters
input bool     EnableStrategy      = true;        // Enable/disable strategy
input bool     EnableEquityStop    = false;       // Enable equity stop protection
input double   MaxEquityDrawdownPercent = 20.0;   // Max equity drawdown percentage
input bool     RestartAfterDrawdown = true;       // Restart after drawdown
input int      ConsecutiveCandles  = 2;           // Consecutive candles for entry
input double   InitialLotSize      = 0.01;        // Initial position lot size
input string   CustomLots          = "0.01,0.02,0.03"; // Hedge position lot sizes
input int      InitialTPPips       = 100;         // Initial TP in pips
input string   TriggerPipsArray    = "700,1400,2100"; // Hedge trigger distances
input int      ProfitTargetPips    = 1000;        // Total profit target in pips
input int      MagicNumber         = 123456;      // Magic number
input bool     UseEMAFilter        = true;        // Use EMA filter
input int      EMA_Period          = 200;         // EMA period
input int      LastPositionSLPips  = 200;         // SL for last hedge position

//--- Global Variables
CTrade trade;
CPositionInfo positionInfo;
CArrayInt triggerPips;
CArrayDouble customLotsArray;

bool strategyEnabled;
int direction = 0;
bool initialTradeOpened = false;
bool equityStopTriggered = false;
double highestEquity = 0;
double initialEntryPrice = 0;
int emaHandle = INVALID_HANDLE;
#define PIP 10

//+------------------------------------------------------------------+
//| Custom string trim functions (renamed to avoid conflicts)        |
//+------------------------------------------------------------------+
string CustomStringTrimLeft(string str)
{
   while(StringGetCharacter(str, 0) == ' ')
      str = StringSubstr(str, 1);
   return str;
}

string CustomStringTrimRight(string str)
{
   while(StringGetCharacter(str, StringLen(str)-1) == ' ')
      str = StringSubstr(str, 0, StringLen(str)-1);
   return str;
}

string CustomStringTrim(string str)
{
   return CustomStringTrimRight(CustomStringTrimLeft(str));
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   strategyEnabled = EnableStrategy;
   
   if(!ParseTriggerPipsArray()) return INIT_FAILED;
   if(!ParseCustomLotsArray()) return INIT_FAILED;
   if(triggerPips.Total() != customLotsArray.Total()) return INIT_FAILED;
   
   if(UseEMAFilter)
   {
      emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityStopTriggered = false;
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Parse trigger pips array                                         |
//+------------------------------------------------------------------+
bool ParseTriggerPipsArray()
{
   string values[];
   int count = StringSplit(TriggerPipsArray, ',', values);
   if(count <= 0) return false;
   
   triggerPips.Clear();
   for(int i = 0; i < count; i++)
   {
      string temp = CustomStringTrim(values[i]);
      int pipValue = (int)StringToInteger(temp);
      if(pipValue <= 0) return false;
      triggerPips.Add(pipValue);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Parse custom lots array                                          |
//+------------------------------------------------------------------+
bool ParseCustomLotsArray()
{
   string values[];
   int count = StringSplit(CustomLots, ',', values);
   if(count <= 0) return false;
   
   customLotsArray.Clear();
   for(int i = 0; i < count; i++)
   {
      string temp = CustomStringTrim(values[i]);
      double lotValue = StringToDouble(temp);
      if(lotValue <= 0) return false;
      customLotsArray.Add(lotValue);
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get current EMA value                                            |
//+------------------------------------------------------------------+
double GetEMAValue()
{
   if(emaHandle == INVALID_HANDLE) return 0;
   
   double emaValue[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaValue) != 1) return 0;
   
   return emaValue[0];
}

//+------------------------------------------------------------------+
//| Get lot size for position index                                  |
//+------------------------------------------------------------------+
double GetLotSize(int positionIndex)
{
   if(positionIndex == 0) return InitialLotSize;
   
   int hedgeIndex = positionIndex - 1;
   if(hedgeIndex < customLotsArray.Total()) 
      return NormalizeDouble(customLotsArray.At(hedgeIndex), 2);
   
   return NormalizeDouble(customLotsArray.At(customLotsArray.Total()-1), 2);
}

//+------------------------------------------------------------------+
//| Check consecutive candles                                        |
//+------------------------------------------------------------------+
bool CheckConsecutiveCandles(int &dir)
{
   bool bullish = true, bearish = true;
   double openArray[1], closeArray[1];

   for(int i = 1; i <= ConsecutiveCandles; i++)
   {
      if(CopyOpen(_Symbol, _Period, i, 1, openArray) != 1 || CopyClose(_Symbol, _Period, i, 1, closeArray) != 1)
         return false;

      if(closeArray[0] <= openArray[0]) bullish = false;
      if(closeArray[0] >= openArray[0]) bearish = false;
   }

   if(bullish) { dir = 1; return true; }
   if(bearish) { dir = -1; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Manage dynamic hedging                                           |
//+------------------------------------------------------------------+
void ManageDynamicHedging()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double emaValue = GetEMAValue();
   int openCount = CountOpenTrades();
   
   if(openCount == 0) return;
   
   // Determine current direction based on EMA
   int currentDirection = (currentPrice > emaValue) ? 1 : -1;
   
   // Calculate distance from initial entry
   double distancePips = MathAbs(currentPrice - initialEntryPrice) / (_Point * PIP);
   
   // Check if we need to open a hedge position
   bool needHedge = false;
   int nextHedgeIndex = openCount;
   
   if(nextHedgeIndex < triggerPips.Total())
   {
      double triggerDistance = GetTotalTriggerPips(nextHedgeIndex);
      needHedge = distancePips >= triggerDistance;
   }
   
   if(needHedge)
   {
      double lot = GetLotSize(nextHedgeIndex);
      double entryPrice = SymbolInfoDouble(_Symbol, currentDirection == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      
      bool isLastPosition = (nextHedgeIndex == triggerPips.Total() - 1);
      
      if(isLastPosition && LastPositionSLPips > 0)
      {
         double slPrice = entryPrice + (currentDirection == 1 ? -LastPositionSLPips : LastPositionSLPips) * PIP * _Point;
         trade.PositionOpen(_Symbol, currentDirection == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, slPrice, 0);
      }
      else
      {
         trade.PositionOpen(_Symbol, currentDirection == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, 0, 0);
      }
      
      Print("Hedge #", nextHedgeIndex, " opened at ", entryPrice, 
            " (Direction: ", currentDirection == 1 ? "Buy" : "Sell", 
            ", Distance: ", distancePips, " pips)");
   }
   
   // Check profit target
   double totalProfit = GetTotalUnrealizedProfit();
   if(totalProfit >= ProfitTargetPips * PIP * _Point)
   {
      CloseAllTrades();
      initialTradeOpened = false;
      initialEntryPrice = 0;
   }
}

//+------------------------------------------------------------------+
//| Get total trigger pips                                           |
//+------------------------------------------------------------------+
int GetTotalTriggerPips(int positionCount)
{
   int total = 0;
   for(int i = 0; i < positionCount && i < triggerPips.Total(); i++)
      total += triggerPips.At(i);
   return total;
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
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Check equity stop                                                |
//+------------------------------------------------------------------+
bool CheckEquityStop()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(highestEquity > 0)
   {
      double drawdownPercent = ((highestEquity - currentEquity) / highestEquity) * 100;
      return drawdownPercent >= MaxEquityDrawdownPercent;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update highest equity                                            |
//+------------------------------------------------------------------+
void UpdateHighestEquity()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > highestEquity)
      highestEquity = currentEquity;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!strategyEnabled) return;

   UpdateHighestEquity();
   
   if(EnableEquityStop && !equityStopTriggered && CheckEquityStop())
   {
      equityStopTriggered = true;
      CloseAllTrades();
      
      if(RestartAfterDrawdown)
      {
         initialTradeOpened = false;
         initialEntryPrice = 0;
         direction = 0;
         highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
      else
      {
         strategyEnabled = false;
         return;
      }
   }
   
   if(equityStopTriggered && RestartAfterDrawdown)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double recoveryLevel = highestEquity * (1 - MaxEquityDrawdownPercent/200);
      if(currentEquity >= recoveryLevel)
         equityStopTriggered = false;
      else
         return;
   }
   
   int totalTrades = CountOpenTrades();
   if(totalTrades == 0)
   {
      if(CheckConsecutiveCandles(direction))
      {
         if(UseEMAFilter)
         {
            double emaValue = GetEMAValue();
            double currentClose = iClose(_Symbol, _Period, 1);
            if((direction == 1 && currentClose < emaValue) || (direction == -1 && currentClose > emaValue))
               return;
         }
         
         initialTradeOpened = true;
         initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
         trade.SetExpertMagicNumber(MagicNumber);
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           InitialLotSize, initialEntryPrice, 0,
                           initialEntryPrice + (direction == 1 ? InitialTPPips : -InitialTPPips) * PIP * _Point);
      }
   }
   else
   {
      ManageDynamicHedging();
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
}