//+------------------------------------------------------------------+
//|                                                      RSIHedgePro.mq5 |
//|                        Copyright 2024, MetaQuotes Ltd.           |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"

// Includes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Arrays/ArrayObj.mqh>

// Input parameters
input double   InpLotSize       = 0.01;        // Base lot size
input double   InpLotMultiplier = 2.0;         // Lot multiplier for averaging
input int      InpRSIPeriod     = 14;          // RSI period
input double   InpRSIOversold   = 30.0;        // RSI oversold level (buy zone)
input double   InpRSIOverbought = 70.0;        // RSI overbought level (sell zone)
input int      InpMaxPositions  = 5;           // Maximum positions per direction
input double   InpLevelDistance = 10.0;        // Distance between averaging levels (in points)
input double   InpTakeProfit    = 20.0;        // Take profit in points
input int      InpMagicNumber   = 202411;      // Magic number
input string   InpComment       = "RSIHedge";  // Trade comment
input bool     InpUseTrailingSL = true;        // Use trailing stop loss
input double   InpTrailingStart = 10.0;        // Trailing start (points)
input double   InpTrailingStep  = 5.0;         // Trailing step (points)

// Global variables
CTrade trade;
CPositionInfo position;
CAccountInfo account;
int rsiHandle;

// Strategy flags
bool bFlag = false;      // Buy flag
bool sFlag = false;      // Sell flag
bool rsiFlag = true;     // RSI search flag

// Position tracking
struct PositionData
{
   long ticket;
   double volume;
   double price;
   datetime time;
};

CArrayObj buyPositions;
CArrayObj sellPositions;

double totalBuyVolume = 0.0;
double totalSellVolume = 0.0;
double avgBuyPrice = 0.0;
double avgSellPrice = 0.0;
double currentBuyPL = 0.0;
double currentSellPL = 0.0;

// Price levels
double entryPrice = 0.0;
double level90 = 0.0;
double level80 = 0.0;
double level70 = 0.0;
double level120 = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Initialize arrays
   buyPositions.FreeMode(true);
   sellPositions.FreeMode(true);
   
   // Create RSI indicator
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }
   
   // Initialize trade object
   trade.SetDeviationInPoints(10);
   trade.SetTypeFillingBySymbol(_Symbol);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handle
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
   
   // Clear arrays
   buyPositions.Clear();
   sellPositions.Clear();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;
   
   // Get current price
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   double currentPrice = tick.bid;
   
   // Get RSI value
   double rsiValue = GetRSIValue();
   
   // Update position tracking
   UpdatePositionData();
   
   // Calculate P&L
   CalculateProfitLoss();
   
   // Calculate price levels
   CalculatePriceLevels();
   
   // Strategy logic
   if(rsiFlag) // Looking for RSI signal
   {
      if(rsiValue < InpRSIOversold) // RSI oversold - BUY signal
      {
         StartBuyStrategy(currentPrice);
      }
      else if(rsiValue > InpRSIOverbought) // RSI overbought - SELL signal
      {
         StartSellStrategy(currentPrice);
      }
   }
   else // Already in a strategy
   {
      if(bFlag) // Buy strategy active
      {
         ManageBuyStrategy(currentPrice);
      }
      else if(sFlag) // Sell strategy active
      {
         ManageSellStrategy(currentPrice);
      }
   }
   
   // Check for exit conditions
   CheckExitConditions(currentPrice);
   
   // Apply trailing stop if enabled
   if(InpUseTrailingSL)
      ApplyTrailingStop();
}

//+------------------------------------------------------------------+
//| Start buy strategy                                               |
//+------------------------------------------------------------------+
void StartBuyStrategy(double price)
{
   Print("Starting BUY strategy at price: ", price);
   
   entryPrice = price;
   CalculateAllLevels(price);
   bFlag = true;
   rsiFlag = false;
   
   // Open initial hedge positions
   OpenPosition(ORDER_TYPE_BUY, InpLotSize, "Initial buy");
   OpenPosition(ORDER_TYPE_SELL, InpLotSize, "Initial hedge sell");
}

//+------------------------------------------------------------------+
//| Start sell strategy                                              |
//+------------------------------------------------------------------+
void StartSellStrategy(double price)
{
   Print("Starting SELL strategy at price: ", price);
   
   entryPrice = price;
   CalculateAllLevels(price);
   sFlag = true;
   rsiFlag = false;
   
   // Open initial hedge positions
   OpenPosition(ORDER_TYPE_SELL, InpLotSize, "Initial sell");
   OpenPosition(ORDER_TYPE_BUY, InpLotSize, "Initial hedge buy");
}

//+------------------------------------------------------------------+
//| Manage buy strategy                                              |
//+------------------------------------------------------------------+
void ManageBuyStrategy(double currentPrice)
{
   // Check price levels
   if(currentPrice <= level90 && buyPositions.Total() < InpMaxPositions)
   {
      // Price at 90 level - add to positions
      double newLotSize = InpLotSize * MathPow(InpLotMultiplier, buyPositions.Total());
      OpenPosition(ORDER_TYPE_BUY, newLotSize, "Averaging buy at 90");
      OpenPosition(ORDER_TYPE_SELL, newLotSize, "Hedge sell at 90");
      
      Print("Added positions at level 90: ", currentPrice);
   }
   
   if(currentPrice <= level80)
   {
      // Price at 80 level - close sell positions
      CloseAllSellPositions();
      Print("Closed all SELL positions at level 80: ", currentPrice);
   }
   
   if(currentPrice <= level70)
   {
      // Price at 70 level - close buy positions
      CloseAllBuyPositions();
      ResetStrategy();
      Print("Closed all BUY positions at level 70: ", currentPrice);
   }
   
   if(currentPrice >= level120)
   {
      // Price at 120 level - close buy positions in profit
      CloseAllBuyPositions();
      ResetStrategy();
      Print("Closed BUY positions in profit at level 120: ", currentPrice);
   }
}

//+------------------------------------------------------------------+
//| Manage sell strategy                                             |
//+------------------------------------------------------------------+
void ManageSellStrategy(double currentPrice)
{
   // Check price levels
   if(currentPrice >= level90 && sellPositions.Total() < InpMaxPositions)
   {
      // Price at 110 level (90 relative to entry) - add to positions
      double newLotSize = InpLotSize * MathPow(InpLotMultiplier, sellPositions.Total());
      OpenPosition(ORDER_TYPE_SELL, newLotSize, "Averaging sell at 110");
      OpenPosition(ORDER_TYPE_BUY, newLotSize, "Hedge buy at 110");
      
      Print("Added positions at level 110: ", currentPrice);
   }
   
   if(currentPrice >= level80)
   {
      // Price at 120 level - close buy positions
      CloseAllBuyPositions();
      Print("Closed all BUY positions at level 120: ", currentPrice);
   }
   
   if(currentPrice >= level70)
   {
      // Price at 130 level - close sell positions
      CloseAllSellPositions();
      ResetStrategy();
      Print("Closed all SELL positions at level 130: ", currentPrice);
   }
   
   if(currentPrice <= level120)
   {
      // Price at 80 level - close sell positions in profit
      CloseAllSellPositions();
      ResetStrategy();
      Print("Closed SELL positions in profit at level 80: ", currentPrice);
   }
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE type, double volume, string comment)
{
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = 0, tp = 0;
   
   // Calculate SL and TP based on position type
   if(type == ORDER_TYPE_BUY)
   {
      sl = price - InpLevelDistance * _Point * 10; // 10 point levels
      tp = price + InpTakeProfit * _Point;
   }
   else
   {
      sl = price + InpLevelDistance * _Point * 10; // 10 point levels
      tp = price - InpTakeProfit * _Point;
   }
   
   bool result = trade.PositionOpen(_Symbol, type, volume, price, sl, tp, 
                                   StringFormat("%s|%s", InpComment, comment));
   
   if(result)
   {
      // Add to tracking arrays
      PositionData* data = new PositionData();
      data.ticket = trade.ResultOrder();
      data.volume = volume;
      data.price = price;
      data.time = TimeCurrent();
      
      if(type == ORDER_TYPE_BUY)
         buyPositions.Add(data);
      else
         sellPositions.Add(data);
         
      Print("Opened position: ", EnumToString(type), " Volume: ", volume, " Price: ", price);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Close all buy positions                                          |
//+------------------------------------------------------------------+
void CloseAllBuyPositions()
{
   for(int i = buyPositions.Total() - 1; i >= 0; i--)
   {
      PositionData* data = buyPositions.At(i);
      if(data != NULL)
      {
         if(position.SelectByTicket(data.ticket))
         {
            trade.PositionClose(data.ticket);
            Print("Closed BUY position: ", data.ticket);
         }
         buyPositions.Delete(i);
      }
   }
   totalBuyVolume = 0.0;
   avgBuyPrice = 0.0;
}

//+------------------------------------------------------------------+
//| Close all sell positions                                         |
//+------------------------------------------------------------------+
void CloseAllSellPositions()
{
   for(int i = sellPositions.Total() - 1; i >= 0; i--)
   {
      PositionData* data = sellPositions.At(i);
      if(data != NULL)
      {
         if(position.SelectByTicket(data.ticket))
         {
            trade.PositionClose(data.ticket);
            Print("Closed SELL position: ", data.ticket);
         }
         sellPositions.Delete(i);
      }
   }
   totalSellVolume = 0.0;
   avgSellPrice = 0.0;
}

//+------------------------------------------------------------------+
//| Update position data                                             |
//+------------------------------------------------------------------+
void UpdatePositionData()
{
   totalBuyVolume = 0.0;
   totalSellVolume = 0.0;
   double buyPriceSum = 0.0;
   double sellPriceSum = 0.0;
   
   // Update buy positions
   for(int i = buyPositions.Total() - 1; i >= 0; i--)
   {
      PositionData* data = buyPositions.At(i);
      if(data != NULL)
      {
         if(position.SelectByTicket(data.ticket))
         {
            totalBuyVolume += data.volume;
            buyPriceSum += data.price * data.volume;
         }
         else // Position closed
         {
            buyPositions.Delete(i);
         }
      }
   }
   
   // Update sell positions
   for(int i = sellPositions.Total() - 1; i >= 0; i--)
   {
      PositionData* data = sellPositions.At(i);
      if(data != NULL)
      {
         if(position.SelectByTicket(data.ticket))
         {
            totalSellVolume += data.volume;
            sellPriceSum += data.price * data.volume;
         }
         else // Position closed
         {
            sellPositions.Delete(i);
         }
      }
   }
   
   // Calculate average prices
   if(totalBuyVolume > 0)
      avgBuyPrice = buyPriceSum / totalBuyVolume;
   if(totalSellVolume > 0)
      avgSellPrice = sellPriceSum / totalSellVolume;
}

//+------------------------------------------------------------------+
//| Calculate profit/loss                                            |
//+------------------------------------------------------------------+
void CalculateProfitLoss()
{
   currentBuyPL = 0.0;
   currentSellPL = 0.0;
   
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   
   // Calculate buy positions P&L
   for(int i = 0; i < buyPositions.Total(); i++)
   {
      PositionData* data = buyPositions.At(i);
      if(data != NULL)
      {
         currentBuyPL += (tick.bid - data.price) * data.volume * 
                        SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / _Point;
      }
   }
   
   // Calculate sell positions P&L
   for(int i = 0; i < sellPositions.Total(); i++)
   {
      PositionData* data = sellPositions.At(i);
      if(data != NULL)
      {
         currentSellPL += (data.price - tick.ask) * data.volume * 
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / _Point;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate price levels                                           |
//+------------------------------------------------------------------+
void CalculatePriceLevels()
{
   if(bFlag)
   {
      level90 = entryPrice - (10 * _Point * InpLevelDistance);
      level80 = entryPrice - (20 * _Point * InpLevelDistance);
      level70 = entryPrice - (30 * _Point * InpLevelDistance);
      level120 = entryPrice + (20 * _Point * InpLevelDistance);
   }
   else if(sFlag)
   {
      level90 = entryPrice + (10 * _Point * InpLevelDistance);
      level80 = entryPrice + (20 * _Point * InpLevelDistance);
      level70 = entryPrice + (30 * _Point * InpLevelDistance);
      level120 = entryPrice - (20 * _Point * InpLevelDistance);
   }
}

//+------------------------------------------------------------------+
//| Calculate all levels                                             |
//+------------------------------------------------------------------+
void CalculateAllLevels(double price)
{
   entryPrice = price;
   CalculatePriceLevels();
}

//+------------------------------------------------------------------+
//| Check exit conditions                                            |
//+------------------------------------------------------------------+
void CheckExitConditions(double currentPrice)
{
   // If all positions are closed, reset strategy
   if(buyPositions.Total() == 0 && sellPositions.Total() == 0)
   {
      ResetStrategy();
   }
   
   // Check for break-even on buy positions
   if(bFlag && buyPositions.Total() > 0 && currentPrice >= avgBuyPrice)
   {
      // Move SL to break-even for all buy positions
      for(int i = 0; i < buyPositions.Total(); i++)
      {
         PositionData* data = buyPositions.At(i);
         if(data != NULL && position.SelectByTicket(data.ticket))
         {
            trade.PositionModify(data.ticket, avgBuyPrice, position.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                              |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   
   // Trail buy positions
   for(int i = 0; i < buyPositions.Total(); i++)
   {
      PositionData* data = buyPositions.At(i);
      if(data != NULL && position.SelectByTicket(data.ticket))
      {
         double currentSL = position.StopLoss();
         double newSL = tick.bid - InpTrailingStart * _Point;
         
         if(newSL > currentSL + InpTrailingStep * _Point)
         {
            trade.PositionModify(data.ticket, newSL, position.TakeProfit());
         }
      }
   }
   
   // Trail sell positions
   for(int i = 0; i < sellPositions.Total(); i++)
   {
      PositionData* data = sellPositions.At(i);
      if(data != NULL && position.SelectByTicket(data.ticket))
      {
         double currentSL = position.StopLoss();
         double newSL = tick.ask + InpTrailingStart * _Point;
         
         if(newSL < currentSL - InpTrailingStep * _Point)
         {
            trade.PositionModify(data.ticket, newSL, position.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset strategy                                                   |
//+------------------------------------------------------------------+
void ResetStrategy()
{
   bFlag = false;
   sFlag = false;
   rsiFlag = true;
   
   entryPrice = 0.0;
   level90 = 0.0;
   level80 = 0.0;
   level70 = 0.0;
   level120 = 0.0;
   
   Print("Strategy reset - waiting for new RSI signal");
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSIValue()
{
   double rsi[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) == 1)
      return rsi[0];
   return 50.0;
}

//+------------------------------------------------------------------+
//| Display info on chart                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      Comment(StringFormat(
         "RSI Hedge EA\n" +
         "Strategy: %s\n" +
         "Buy Positions: %d (Vol: %.2f, Avg: %.5f)\n" +
         "Sell Positions: %d (Vol: %.2f, Avg: %.5f)\n" +
         "Buy P&L: $%.2f | Sell P&L: $%.2f\n" +
         "RSI Flag: %s | B Flag: %s | S Flag: %s\n" +
         "Entry Price: %.5f\n" +
         "Levels -> 90: %.5f | 80: %.5f | 70: %.5f | 120: %.5f",
         rsiFlag ? "Waiting for RSI" : (bFlag ? "Buy Active" : "Sell Active"),
         buyPositions.Total(), totalBuyVolume, avgBuyPrice,
         sellPositions.Total(), totalSellVolume, avgSellPrice,
         currentBuyPL, currentSellPL,
         rsiFlag ? "Yes" : "No",
         bFlag ? "Yes" : "No",
         sFlag ? "Yes" : "No",
         entryPrice,
         level90, level80, level70, level120
      ));
   }
}