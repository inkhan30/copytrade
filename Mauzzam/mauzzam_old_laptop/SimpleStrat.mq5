//+------------------------------------------------------------------+
//|                                           SimpleStrat_1Min_EA.mq5 |
//|                                    Generated from your strategy  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Your Strategy EA"
#property version   "1.00"
#property description "EA based on 50/200 EMA and Stochastic strategy"
#property description "Trades only on 1-minute chart"

//--- Include MQL5 libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayDouble.mqh>

//--- Global trading objects
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;
CArrayInt triggerPips;
CArrayDouble customLotsArray;
CArrayInt profitTargetsArray;

//--- Define enum for exit strategy
enum EXIT_STRATEGY
{
   FIXED_RR = 0,        // Option A: Fixed 1.5 RR
   STOCHASTIC_EXIT = 1  // Option B: Stochastic exit
};

//--- Input parameters
input group "=== TRADE SETTINGS ==="
input double     LotSize        = 0.01;        // Fixed lot size
input int        Slippage       = 30;          // Slippage in points
input int        MagicNumber    = 2024001;     // Magic number for orders

input group "=== EXIT STRATEGY ==="
input EXIT_STRATEGY ExitStrategy = FIXED_RR;    // Exit strategy

input group "=== RISK MANAGEMENT ==="
input int        RiskRewardRatio = 15;         // Risk:Reward ratio (1:1.5 means 15 for 10 pip stop)
input int        StopLossBuffer  = 2;          // Buffer from swing high/low (1-2 pips)

input group "=== INDICATOR SETTINGS ==="
input int        EMAPeriod1     = 50;          // First EMA period
input int        EMAPeriod2     = 200;         // Second EMA period
input int        StochasticK    = 5;            // Stochastic %K period
input int        StochasticD    = 3;            // Stochastic %D period
input int        StochasticSlowing = 3;         // Stochastic slowing
input int        StochasticPrice = 0;           // Stochastic price (0=Low/High, 1=Close/Close)

input group "=== SWING DETECTION ==="
input int        SwingLookback  = 20;           // Bars to look back for swing points

//--- Global variables
int ema1Handle, ema2Handle, stochHandle;
double ema1[], ema2[], stochK[], stochD[];
datetime lastBarTime;
bool isBullish, isBearish;
double pointValue;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trading objects
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Failed to set symbol name");
      return INIT_FAILED;
   }
   symbolInfo.RefreshRates();
   pointValue = symbolInfo.Point();
   
   // Set arrays as series
   ArraySetAsSeries(ema1, true);
   ArraySetAsSeries(ema2, true);
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   
   // Create EMA handles
   ema1Handle = iMA(_Symbol, _Period, EMAPeriod1, 0, MODE_EMA, PRICE_CLOSE);
   ema2Handle = iMA(_Symbol, _Period, EMAPeriod2, 0, MODE_EMA, PRICE_CLOSE);
   
   // Create Stochastic handle
   ENUM_STO_PRICE stochPriceEnum;
   if(StochasticPrice == 0)
      stochPriceEnum = STO_LOWHIGH;
   else
      stochPriceEnum = STO_CLOSECLOSE;
   
   stochHandle = iStochastic(_Symbol, _Period, StochasticK, StochasticD, StochasticSlowing, MODE_SMA, stochPriceEnum);
   
   // Check if handles created successfully
   if(ema1Handle == INVALID_HANDLE || ema2Handle == INVALID_HANDLE || stochHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   lastBarTime = 0;
   
   // Initialize arrays (example usage)
   triggerPips.Add(10);  // Example: store trigger pips values
   profitTargetsArray.Add(RiskRewardRatio); // Store profit targets
   
   Print("EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(ema1Handle != INVALID_HANDLE) IndicatorRelease(ema1Handle);
   if(ema2Handle != INVALID_HANDLE) IndicatorRelease(ema2Handle);
   if(stochHandle != INVALID_HANDLE) IndicatorRelease(stochHandle);
   
   // Clear arrays
   triggerPips.Clear();
   customLotsArray.Clear();
   profitTargetsArray.Clear();
   
   Print("EA deinitialized");
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Copy EMA values
   if(CopyBuffer(ema1Handle, 0, 0, 3, ema1) < 3) return false;
   if(CopyBuffer(ema2Handle, 0, 0, 3, ema2) < 3) return false;
   
   // Copy Stochastic values
   if(CopyBuffer(stochHandle, 0, 0, 3, stochK) < 3) return false;
   if(CopyBuffer(stochHandle, 1, 0, 3, stochD) < 3) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Find nearest swing low                                           |
//+------------------------------------------------------------------+
double FindSwingLow()
{
   double lowest = DBL_MAX;
   
   for(int i = 1; i <= SwingLookback; i++)
   {
      double low = iLow(_Symbol, _Period, i);
      if(low < lowest)
         lowest = low;
   }
   
   return lowest;
}

//+------------------------------------------------------------------+
//| Find nearest swing high                                          |
//+------------------------------------------------------------------+
double FindSwingHigh()
{
   double highest = 0;
   
   for(int i = 1; i <= SwingLookback; i++)
   {
      double high = iHigh(_Symbol, _Period, i);
      if(high > highest)
         highest = high;
   }
   
   return highest;
}

//+------------------------------------------------------------------+
//| Check if position exists                                         |
//+------------------------------------------------------------------+
bool PositionExists()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get position ticket if exists                                    |
//+------------------------------------------------------------------+
ulong GetPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == MagicNumber)
         {
            return positionInfo.Ticket();
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Open Order                                                       |
//+------------------------------------------------------------------+
bool OpenOrder(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   symbolInfo.RefreshRates();
   
   bool result = false;
   
   if(type == ORDER_TYPE_BUY)
   {
      result = trade.Buy(LotSize, _Symbol, symbolInfo.Ask(), sl, tp, "EMA_Stoch_Buy");
   }
   else if(type == ORDER_TYPE_SELL)
   {
      result = trade.Sell(LotSize, _Symbol, symbolInfo.Bid(), sl, tp, "EMA_Stoch_Sell");
   }
   
   if(result)
   {
      Print("Order opened successfully. Ticket: ", trade.ResultOrder());
      return true;
   }
   else
   {
      Print("Order failed. Code: ", trade.ResultRetcode());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   if(trade.PositionClose(ticket))
   {
      Print("Position closed successfully: ", ticket);
      return true;
   }
   else
   {
      Print("Failed to close position: ", ticket, " Code: ", trade.ResultRetcode());
      return false;
   }
}

//+------------------------------------------------------------------+
//| Check Buy Signal                                                 |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
   if(!isBullish)
      return;
   
   // Check for Stochastic cross above 20
   bool stochCrossAbove20 = (stochK[1] <= 20.0 && stochD[1] <= 20.0 && 
                             stochK[0] > 20.0 && stochD[0] > 20.0);
   
   if(stochCrossAbove20)
   {
      symbolInfo.RefreshRates();
      double askPrice = symbolInfo.Ask();
      
      // Find nearest swing low for stop loss
      double swingLow = FindSwingLow();
      double stopLoss = swingLow - StopLossBuffer * 10 * pointValue; // Convert pips to price
      
      // Ensure stop loss is below entry
      if(stopLoss >= askPrice)
      {
         Print("Invalid stop loss for buy, skipping trade");
         return;
      }
      
      // Calculate take profit based on exit strategy
      double takeProfit = 0;
      
      if(ExitStrategy == FIXED_RR)
      {
         double stopDistance = askPrice - stopLoss;
         double riskRewardPoints = (RiskRewardRatio / 10.0); // Convert to ratio
         takeProfit = askPrice + (stopDistance * riskRewardPoints);
      }
      else // STOCHASTIC_EXIT
      {
         takeProfit = 0; // No TP, will close based on stochastic
      }
      
      // Open buy order
      OpenOrder(ORDER_TYPE_BUY, askPrice, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Check Sell Signal                                                |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
   if(!isBearish)
      return;
   
   // Check for Stochastic cross above 80 (for sell)
   bool stochCrossAbove80 = (stochK[1] >= 80.0 && stochD[1] >= 80.0 && 
                             stochK[0] < 80.0 && stochD[0] < 80.0);
   
   if(stochCrossAbove80)
   {
      symbolInfo.RefreshRates();
      double bidPrice = symbolInfo.Bid();
      
      // Find nearest swing high for stop loss
      double swingHigh = FindSwingHigh();
      double stopLoss = swingHigh + StopLossBuffer * 10 * pointValue; // Convert pips to price
      
      // Ensure stop loss is above entry
      if(stopLoss <= bidPrice)
      {
         Print("Invalid stop loss for sell, skipping trade");
         return;
      }
      
      // Calculate take profit based on exit strategy
      double takeProfit = 0;
      
      if(ExitStrategy == FIXED_RR)
      {
         double stopDistance = stopLoss - bidPrice;
         double riskRewardPoints = (RiskRewardRatio / 10.0); // Convert to ratio
         takeProfit = bidPrice - (stopDistance * riskRewardPoints);
      }
      else // STOCHASTIC_EXIT
      {
         takeProfit = 0; // No TP, will close based on stochastic
      }
      
      // Open sell order
      OpenOrder(ORDER_TYPE_SELL, bidPrice, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Manage exit based on stochastic                                  |
//+------------------------------------------------------------------+
void ManageStochasticExit()
{
   ulong ticket = GetPositionTicket();
   if(ticket == 0) return;
   
   if(!positionInfo.SelectByTicket(ticket))
      return;
   
   ENUM_POSITION_TYPE type = positionInfo.PositionType();
   
   // Update indicators for current bar
   if(!UpdateIndicators())
      return;
   
   bool shouldClose = false;
   
   if(type == POSITION_TYPE_BUY)
   {
      // Close buy when Stochastic enters overbought (>80)
      if(stochK[0] >= 80.0 && stochD[0] >= 80.0)
         shouldClose = true;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      // Close sell when Stochastic enters oversold (<20)
      if(stochK[0] <= 20.0 && stochD[0] <= 20.0)
         shouldClose = true;
   }
   
   if(shouldClose)
   {
      ClosePosition(ticket);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar only (1-minute chart)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   // Update indicator values
   if(!UpdateIndicators())
      return;
   
   // Refresh symbol rates
   symbolInfo.RefreshRates();
   
   // Check for existing positions
   if(PositionExists())
   {
      // If position exists and using stochastic exit, manage it
      if(ExitStrategy == STOCHASTIC_EXIT)
      {
         ManageStochasticExit();
      }
      return;
   }
   
   // Identify trend based on EMA positions
   double currentPrice = symbolInfo.Bid();
   
   isBullish = (currentPrice > ema1[0] && currentPrice > ema2[0]);
   isBearish = (currentPrice < ema1[0] && currentPrice < ema2[0]);
   
   // Check if price is between EMAs - do nothing
   if(!isBullish && !isBearish)
      return;
   
   // Check for entry signals
   CheckBuySignal();
   CheckSellSignal();
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Handle trade transactions if needed
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      // Can add custom logic for tracking trades
   }
}
//+------------------------------------------------------------------+