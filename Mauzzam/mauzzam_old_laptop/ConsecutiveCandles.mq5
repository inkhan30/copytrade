//+------------------------------------------------------------------+
//|                                         ConsecutiveCandlesEA.mq5 |
//|                        Copyright 2023, MetaQuotes Ltd.           |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Include MQL5 standard libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "EA Identification"
input long   EAMagicNumber      = 123456;    // EA Magic Number

input group "Trading Settings"
input int    ConsecutiveCandles = 2;         // Number of consecutive candles (2 or 3)
input double LotSize            = 0.01;      // Fixed lot size
input bool   EnableBuyTrades    = true;      // Enable buy trades
input bool   EnableSellTrades   = true;      // Enable sell trades
input bool   CloseOnCandleClose = true;      // Close on next candle close

input group "Risk Management"
input bool   UseStopLoss        = false;     // Enable Stop Loss
input double StopLossPoints     = 50;        // Stop Loss in points
input bool   UseTakeProfit      = false;     // Enable Take Profit
input double TakeProfitPoints   = 100;       // Take Profit in points

input group "Symbol Settings"
input bool   TradeOnNewBar      = true;      // Trade only on new bar

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
ulong lastBarTime = 0;
bool positionOpenedThisBar = false;
ulong openedPositionBarTime = 0;
MqlTick currentTick;
MqlRates rates[];

// Create CTrade and CPositionInfo objects
CTrade Trade;
CPositionInfo PositionInfo;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate input parameters
   //if(ConsecutiveCandles < 2 || ConsecutiveCandles > 3)
   //{
      //Print("Error: ConsecutiveCandles must be 2 or 3");
      //return INIT_PARAMETERS_INCORRECT;
   //}
   
   if(LotSize <= 0)
   {
      Print("Error: LotSize must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(!EnableBuyTrades && !EnableSellTrades)
   {
      Print("Error: At least one trade direction must be enabled");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(EAMagicNumber <= 0)
   {
      Print("Error: EA Magic Number must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Configure CTrade object
   Trade.SetExpertMagicNumber(EAMagicNumber);
   Trade.SetDeviationInPoints(10);
   Trade.SetAsyncMode(false);  // Synchronous mode for simplicity
   
   // Initialize arrays
   ArraySetAsSeries(rates, true);
   
   Print("Consecutive Candles EA initialized successfully");
   Print("EA Magic Number: ", EAMagicNumber);
   Print("Trading Parameters:");
   Print("  Consecutive Candles: ", ConsecutiveCandles);
   Print("  Lot Size: ", LotSize);
   Print("  Buy Trades: ", EnableBuyTrades ? "Enabled" : "Disabled");
   Print("  Sell Trades: ", EnableSellTrades ? "Enabled" : "Disabled");
   Print("  Close on Next Candle Close: ", CloseOnCandleClose ? "Yes" : "No");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   bool newBar = IsNewBar();
   
   // Reset position opened flag on new bar
   if(newBar)
   {
      positionOpenedThisBar = false;
      
      // Close positions on next candle close if enabled
      if(CloseOnCandleClose && HasPositionOpenedByEA())
      {
         // Check if position was opened on a previous bar
         if(openedPositionBarTime != 0 && openedPositionBarTime != lastBarTime)
         {
            CloseAllPositions();
            openedPositionBarTime = 0; // Reset after closing
         }
      }
   }
   
   // Check for consecutive candles conditions
   // Only if no position exists and not opened this bar, and (not TradeOnNewBar OR new bar)
   if(!HasPositionOpenedByEA() && !positionOpenedThisBar && (!TradeOnNewBar || newBar))
   {
      CheckConsecutiveCandles();
   }
}

//+------------------------------------------------------------------+
//| Check for consecutive bullish/bearish candles                    |
//+------------------------------------------------------------------+
void CheckConsecutiveCandles()
{
   // Get recent candles data
   if(CopyRates(_Symbol, _Period, 1, ConsecutiveCandles + 1, rates) < ConsecutiveCandles + 1)
   {
      Print("Failed to copy rates data");
      return;
   }
   
   // Check for consecutive bullish candles for buy signal
   if(EnableBuyTrades && CheckConsecutiveBullishCandles())
   {
      OpenBuyPosition();
   }
   
   // Check for consecutive bearish candles for sell signal
   if(EnableSellTrades && CheckConsecutiveBearishCandles())
   {
      OpenSellPosition();
   }
}

//+------------------------------------------------------------------+
//| Check for consecutive bullish candles                            |
//+------------------------------------------------------------------+
bool CheckConsecutiveBullishCandles()
{
   bool allBullish = true;
   
   // Check the last N candles (excluding current candle)
   for(int i = 1; i <= ConsecutiveCandles; i++)
   {
      if(rates[i].close <= rates[i].open) // Not bullish
      {
         allBullish = false;
         break;
      }
   }
   
   return allBullish;
}

//+------------------------------------------------------------------+
//| Check for consecutive bearish candles                            |
//+------------------------------------------------------------------+
bool CheckConsecutiveBearishCandles()
{
   bool allBearish = true;
   
   // Check the last N candles (excluding current candle)
   for(int i = 1; i <= ConsecutiveCandles; i++)
   {
      if(rates[i].close >= rates[i].open) // Not bearish
      {
         allBearish = false;
         break;
      }
   }
   
   return allBearish;
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   // Get current symbol information
   if(!SymbolInfoTick(_Symbol, currentTick))
   {
      Print("Failed to get tick data");
      return;
   }
   
   double stopLossPrice = 0;
   double takeProfitPrice = 0;
   
   // Calculate SL/TP if enabled
   if(UseStopLoss)
   {
      stopLossPrice = NormalizeDouble(currentTick.ask - StopLossPoints * _Point, _Digits);
   }
   
   if(UseTakeProfit)
   {
      takeProfitPrice = NormalizeDouble(currentTick.ask + TakeProfitPoints * _Point, _Digits);
   }
   
   // Open buy position using CTrade
   if(Trade.Buy(LotSize, _Symbol, currentTick.ask, stopLossPrice, takeProfitPrice, 
                "Consecutive Bullish Candles Buy"))
   {
      Print("Buy order placed successfully");
      positionOpenedThisBar = true;
      openedPositionBarTime = iTime(_Symbol, _Period, 0); // Record the bar time
   }
   else
   {
      Print("Buy order failed. Error: ", Trade.ResultRetcode(), ", Description: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   // Get current symbol information
   if(!SymbolInfoTick(_Symbol, currentTick))
   {
      Print("Failed to get tick data");
      return;
   }
   
   double stopLossPrice = 0;
   double takeProfitPrice = 0;
   
   // Calculate SL/TP if enabled
   if(UseStopLoss)
   {
      stopLossPrice = NormalizeDouble(currentTick.bid + StopLossPoints * _Point, _Digits);
   }
   
   if(UseTakeProfit)
   {
      takeProfitPrice = NormalizeDouble(currentTick.bid - TakeProfitPoints * _Point, _Digits);
   }
   
   // Open sell position using CTrade
   if(Trade.Sell(LotSize, _Symbol, currentTick.bid, stopLossPrice, takeProfitPrice, 
                 "Consecutive Bearish Candles Sell"))
   {
      Print("Sell order placed successfully");
      positionOpenedThisBar = true;
      openedPositionBarTime = iTime(_Symbol, _Period, 0); // Record the bar time
   }
   else
   {
      Print("Sell order failed. Error: ", Trade.ResultRetcode(), ", Description: ", Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Close all positions opened by this EA                            |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   // Loop through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionInfo.SelectByIndex(i))
      {
         // Check if position belongs to this EA
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EAMagicNumber)
         {
            ENUM_POSITION_TYPE positionType = PositionInfo.PositionType();
            
            if(positionType == POSITION_TYPE_BUY)
            {
               if(Trade.PositionClose(_Symbol))
               {
                  Print("Buy position closed successfully on next candle close");
               }
               else
               {
                  Print("Failed to close buy position. Error: ", Trade.ResultRetcode(), 
                        ", Description: ", Trade.ResultRetcodeDescription());
               }
            }
            else if(positionType == POSITION_TYPE_SELL)
            {
               if(Trade.PositionClose(_Symbol))
               {
                  Print("Sell position closed successfully on next candle close");
               }
               else
               {
                  Print("Failed to close sell position. Error: ", Trade.ResultRetcode(), 
                        ", Description: ", Trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if position was opened by this EA                          |
//+------------------------------------------------------------------+
bool HasPositionOpenedByEA()
{
   // Loop through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionInfo.SelectByIndex(i))
      {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EAMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Trade function for handling trade events                         |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Optional: Add trade event handling here
}

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
   // Optional: Add transaction handling here
   // You can add logging or other actions on trade events
}