//+------------------------------------------------------------------+
//|                                                   SimpleHedging.mq5 |
//|                                      Loss Stop - Auto Restart with New Balance |
//+------------------------------------------------------------------+
#property strict
#property description "Opens a hedge pair every N minutes and scales in on the trending side."
#property description "Closes all when price reaches final target OR current drawdown exceeds $20."
#property description "After loss trigger, resets peak to new balance and continues trading."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input ulong    MagicNumber           = 12345;           // Unique EA identifier
input double   InitialLot            = 0.01;            // Lot size for the first pair
input int      TradeIntervalMinutes  = 15;              // Minutes between new cycles
input int      StepPoints            = 500;             // Distance (points) to add new position
input double   LotIncrement          = 0.01;            // Additional lot per level
input int      FinalStepPoints       = 100;             // Distance to close all (1$)
input bool     UseLossStop           = true;            // Enable $20 loss stop
input double   LossLimitDollars      = 20.0;            // Close all if current loss exceeds this from peak

//--- Global objects
CTrade         Trade;
CPositionInfo  PositionInfo;

//--- State variables
datetime       lastTradeTime = 0;
bool           isActive = false;
double         peakBalance = 0.0;                       // Track the highest balance ever seen
int            lossStopCount = 0;                        // Counter for how many times loss stop triggered

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set initial peak balance
   peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("========== EA STARTED ==========");
   Print("Initial peak balance: $", peakBalance);
   Print("Loss limit: $", LossLimitDollars);
   Print("Will trigger when current loss from peak >= $", LossLimitDollars);
   Print("=================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Update peak balance (whenever we reach a new high) ---
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(currentBalance > peakBalance)
   {
      peakBalance = currentBalance;
      Print("💰 New peak balance: $", peakBalance, " (New high!)");
   }
   
   // --- CRITICAL: Loss stop check on EVERY tick ---
   if(UseLossStop)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      // Calculate loss from peak balance
      double currentDrawdown = peakBalance - currentEquity;
      
      // Print occasionally for debugging (every 100 ticks)
      static int tickCount = 0;
      tickCount++;
      if(tickCount % 100 == 0)
         Print("Peak: $", peakBalance, " | Equity: $", currentEquity, 
               " | Drawdown: $", currentDrawdown, " | Limit: $", LossLimitDollars);
      
      // CHECK IF DRAWDOWN LIMIT REACHED
      if(currentDrawdown >= LossLimitDollars)
      {
         lossStopCount++;
         Print("🚨🚨🚨 DRAWDOWN LIMIT REACHED! (Trigger #", lossStopCount, ")");
         Print("Peak was: $", peakBalance, " Current equity: $", currentEquity);
         Print("Drawdown: $", currentDrawdown, " >= Limit: $", LossLimitDollars);
         
         // Close ALL positions immediately
         CloseAllPositions("Drawdown limit reached");
         
         // RESET with new balance
         double newBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         peakBalance = newBalance;
         Print("🔄 RESET: New peak balance set to $", peakBalance);
         Print("Ready to trade again in ", TradeIntervalMinutes, " minutes.");
         
         return; // Exit tick processing, next tick will continue normally
      }
   }
   
   // --- Normal trading logic ---
   if(isActive)
      ManageCycle();
   else
   {
      if(TimeCurrent() - lastTradeTime >= TradeIntervalMinutes * 60)
         StartNewCycle();
   }
}

//+------------------------------------------------------------------+
//| Start a new hedging cycle                                        |
//+------------------------------------------------------------------+
void StartNewCycle()
{
   // Double-check we're not in a loss stop situation
   if(UseLossStop)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double currentDrawdown = peakBalance - currentEquity;
      if(currentDrawdown >= LossLimitDollars)
      {
         Print("⚠️ Attempted to start cycle while in drawdown! Waiting...");
         return;
      }
   }
   
   double priceAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double priceBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   Print("Starting new cycle at balance: $", AccountInfoDouble(ACCOUNT_BALANCE), 
         " | Peak: $", peakBalance);
   
   // Open buy
   Trade.SetExpertMagicNumber(MagicNumber);
   if(!Trade.Buy(InitialLot, _Symbol, priceAsk, 0, 0, "Hedge B1"))
   {
      Print("Failed to open buy");
      return;
   }

   // Open sell
   if(!Trade.Sell(InitialLot, _Symbol, priceBid, 0, 0, "Hedge S1"))
   {
      Print("Failed to open sell");
      CloseAllPositions("Sell open failed");
      return;
   }

   isActive = true;
   lastTradeTime = TimeCurrent();
   Print("✅ New cycle started successfully");
}

//+------------------------------------------------------------------+
//| Manage active cycle                                              |
//+------------------------------------------------------------------+
void ManageCycle()
{
   // Count positions
   int buyCount = 0, sellCount = 0;
   double highestBuy = 0, lowestSell = DBL_MAX;
   double firstBuyPrice = 0, firstSellPrice = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionInfo.SelectByIndex(i))
      {
         if(PositionInfo.Magic() == MagicNumber && PositionInfo.Symbol() == _Symbol)
         {
            if(PositionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               buyCount++;
               if(PositionInfo.PriceOpen() > highestBuy)
                  highestBuy = PositionInfo.PriceOpen();
               if(firstBuyPrice == 0 || PositionInfo.PriceOpen() < firstBuyPrice)
                  firstBuyPrice = PositionInfo.PriceOpen();
            }
            else
            {
               sellCount++;
               if(PositionInfo.PriceOpen() < lowestSell)
                  lowestSell = PositionInfo.PriceOpen();
               if(firstSellPrice == 0 || PositionInfo.PriceOpen() > firstSellPrice)
                  firstSellPrice = PositionInfo.PriceOpen();
            }
         }
      }
   }

   if(buyCount + sellCount == 0)
   {
      isActive = false;
      return;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Determine trend
   int trend = 0;
   double refPrice = 0;

   if(buyCount > sellCount)
   {
      trend = 1;
      refPrice = highestBuy;
   }
   else if(sellCount > buyCount)
   {
      trend = -1;
      refPrice = lowestSell;
   }
   else
   {
      // No trend yet
      if(bid <= firstSellPrice - StepPoints * point)
      {
         trend = -1;
         refPrice = firstSellPrice;
      }
      else if(ask >= firstBuyPrice + StepPoints * point)
      {
         trend = 1;
         refPrice = firstBuyPrice;
      }
      else
         return;
   }

   // Add positions
   if(trend == -1 && bid <= refPrice - StepPoints * point)
   {
      double lot = InitialLot + sellCount * LotIncrement;
      if(Trade.Sell(lot, _Symbol, bid, 0, 0, "Hedge S" + IntegerToString(sellCount + 1)))
      {
         lowestSell = bid;
         sellCount++;
         Print("Added sell #", sellCount, " at ", bid);
      }
   }
   else if(trend == 1 && ask >= refPrice + StepPoints * point)
   {
      double lot = InitialLot + buyCount * LotIncrement;
      if(Trade.Buy(lot, _Symbol, ask, 0, 0, "Hedge B" + IntegerToString(buyCount + 1)))
      {
         highestBuy = ask;
         buyCount++;
         Print("Added buy #", buyCount, " at ", ask);
      }
   }

   // Check close condition
   if(trend == -1 && bid <= lowestSell - FinalStepPoints * point)
   {
      CloseAllPositions("Final target down");
   }
   else if(trend == 1 && ask >= highestBuy + FinalStepPoints * point)
   {
      CloseAllPositions("Final target up");
   }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("Closing all positions: ", reason);
   
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionInfo.SelectByIndex(i))
      {
         if(PositionInfo.Magic() == MagicNumber && PositionInfo.Symbol() == _Symbol)
         {
            if(Trade.PositionClose(PositionInfo.Ticket()))
               closed++;
         }
      }
   }
   
   Print("Closed ", closed, " positions");
   isActive = false;
   lastTradeTime = TimeCurrent();
}
//+------------------------------------------------------------------+