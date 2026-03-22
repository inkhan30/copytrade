//+------------------------------------------------------------------+
//|                                     Swing_Breakout_Scalper.mq5 |
//|                                  Copyright 2023, Your Name |
//|                                             https://www.example.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name"
#property link      "https://www.example.com"
#property version   "1.00"
#property description "A scalping bot that trades breakouts of swing highs and lows."

#include <Trade\Trade.mqh>

//--- Input Parameters
input double LotSize           = 0.01;      // Fixed lot size for trades
input int    LookbackBars      = 20;        // Number of bars to look back for swing points
input int    MinBreakoutBars   = 5;         // Minimum bars since swing point for a valid breakout
input double RiskReward        = 2.0;       // Risk to Reward Ratio (e.g., 2.0 means TP is 2x SL)
input int    MaxSpread         = 50;        // Maximum allowed spread in points (e.g. 50 points = 5 pips)
input ulong  MagicNumber       = 123456;    // Magic number to identify trades from this EA
input bool   EnableBuy         = true;      // Allow the EA to open buy trades
input bool   EnableSell        = true;      // Allow the EA to open sell trades

//--- Global Objects
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize the CTrade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   
   //--- Print parameters to the Experts log for review
   Print("Swing Breakout Scalper Initialized");
   Print("Lot Size: ", LotSize);
   Print("Lookback Bars: ", LookbackBars);
   Print("Min Breakout Bars: ", MinBreakoutBars);
   Print("Risk/Reward Ratio: ", RiskReward);
   Print("Max Spread (Points): ", MaxSpread);
   Print("Magic Number: ", MagicNumber);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //---
   Print("Swing Breakout Scalper Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function (main logic)                                |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Ensure we have enough bars to work with
   if(Bars(_Symbol, _Period) < LookbackBars + 5)
   {
      // Not enough history yet
      return;
   }
   
   //--- Check if a new bar has formed to avoid trading multiple times on the same bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if(lastBarTime == currentBarTime)
   {
      return; // Not a new bar, do nothing
   }
   lastBarTime = currentBarTime;

   //--- Check if there are already open positions managed by this EA
   if(PositionsTotal() > 0 && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
   {
      return; // A trade is already open
   }
   
   //--- Check the spread before trading
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread)
   {
      //Print("Spread is too high: ", spread, " > ", MaxSpread);
      return; // Spread is too wide, skip this tick
   }

   //--- Get current market prices
   MqlTick latest_tick;
   SymbolInfoTick(_Symbol, latest_tick);
   double ask = latest_tick.ask;
   double bid = latest_tick.bid;

   //--- Find the highest and lowest points in the lookback period (excluding the current bar)
   int high_index = iHighest(_Symbol, _Period, MODE_HIGH, LookbackBars, 1);
   int low_index = iLowest(_Symbol, _Period, MODE_LOW, LookbackBars, 1);

   //--- Get the actual high and low price values from those bars
   double swing_high = iHigh(_Symbol, _Period, high_index);
   double swing_low = iLow(_Symbol, _Period, low_index);

   //--- BUY LOGIC ---
   if(EnableBuy)
   {
      // Condition 1: Current ask price breaks above the swing high
      // Condition 2: The swing high must not be too recent (respects MinBreakoutBars)
      if(ask > swing_high && high_index >= MinBreakoutBars)
      {
         // Calculate Stop Loss: Place it at the swing low
         double sl_price = swing_low;
         
         // Calculate the size of the stop loss in points
         double sl_distance = ask - sl_price;
         
         // Ensure SL is not zero or negative
         if(sl_distance > 0)
         {
            // Calculate Take Profit based on the Risk/Reward ratio
            double tp_price = ask + (sl_distance * RiskReward);
            
            // Normalize prices to the correct number of digits for the symbol
            sl_price = NormalizeDouble(sl_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            tp_price = NormalizeDouble(tp_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            
            //--- Send the buy order
            Print("BUY Signal: Breakout above ", swing_high, ". SL: ", sl_price, " TP: ", tp_price);
            trade.Buy(LotSize, _Symbol, ask, sl_price, tp_price, "Buy triggered by Swing Breakout Scalper");
         }
      }
   }

   //--- SELL LOGIC ---
   if(EnableSell)
   {
      // Condition 1: Current bid price breaks below the swing low
      // Condition 2: The swing low must not be too recent (respects MinBreakoutBars)
      if(bid < swing_low && low_index >= MinBreakoutBars)
      {
         // Calculate Stop Loss: Place it at the swing high
         double sl_price = swing_high;
         
         // Calculate the size of the stop loss in points
         double sl_distance = sl_price - bid;

         // Ensure SL is not zero or negative
         if(sl_distance > 0)
         {
            // Calculate Take Profit based on the Risk/Reward ratio
            double tp_price = bid - (sl_distance * RiskReward);
            
            // Normalize prices to the correct number of digits for the symbol
            sl_price = NormalizeDouble(sl_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
            tp_price = NormalizeDouble(tp_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

            //--- Send the sell order
            Print("SELL Signal: Breakout below ", swing_low, ". SL: ", sl_price, " TP: ", tp_price);
            trade.Sell(LotSize, _Symbol, bid, sl_price, tp_price, "Sell triggered by Swing Breakout Scalper");
         }
      }
   }
}
//+------------------------------------------------------------------+
