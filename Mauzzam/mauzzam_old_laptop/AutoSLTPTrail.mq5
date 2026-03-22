//+------------------------------------------------------------------+
//|                                  SimpleAutoSLTPTrailing.mq5      |
//+------------------------------------------------------------------+
#property copyright "Professional Trader"
#property version   "1.00"

input int      SL_Points      = 2000;      // Default SL in points
input int      TP_Points      = 5000;      // Default TP in points
input double   TrailTrigger   = 2.0;       // Trail trigger ($ profit)
input double   TrailLock      = 1.0;       // Lock profit at ($)
input int      Magic          = 2024;      // Magic number
#include <Trade\Trade.mqh>
double point, tickValue;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckAndModifyPositions();
}

//+------------------------------------------------------------------+
//| Check and modify positions                                       |
//+------------------------------------------------------------------+
void CheckAndModifyPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            //--- Get position details
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            double profit = PositionGetDouble(POSITION_PROFIT);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            //--- Case 1: No SL/TP set
            if(currentSL == 0 && currentTP == 0)
            {
               double newSL = 0, newTP = 0;
               
               if(type == POSITION_TYPE_BUY)
               {
                  newSL = openPrice - (SL_Points * point);
                  newTP = openPrice + (TP_Points * point);
               }
               else // SELL
               {
                  newSL = openPrice + (SL_Points * point);
                  newTP = openPrice - (TP_Points * point);
               }
               
               trade.PositionModify(ticket, newSL, newTP);
               Print("SL/TP added to position #", ticket);
            }
            //--- Case 2: Apply trailing stop
            else if(MathAbs(profit) >= TrailTrigger)
            {
               double newSL = currentSL;
               double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
               
               if(type == POSITION_TYPE_BUY && currentPrice > openPrice)
               {
                  //--- Calculate $1 profit level
                  double lockPrice = openPrice + (TrailLock / tickValue * point);
                  if(lockPrice > currentSL)
                     newSL = lockPrice;
               }
               else if(type == POSITION_TYPE_SELL && currentPrice < openPrice)
               {
                  //--- Calculate $1 profit level
                  double lockPrice = openPrice - (TrailLock / tickValue * point);
                  if(lockPrice < currentSL)
                     newSL = lockPrice;
               }
               
               //--- Modify if SL changed
               if(newSL != currentSL)
               {
                  trade.PositionModify(ticket, newSL, currentTP);
                  Print("Trailed SL to: ", newSL, " on position #", ticket);
               }
            }
         }
      }
   }
}