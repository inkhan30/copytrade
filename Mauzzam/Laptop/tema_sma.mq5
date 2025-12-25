//+------------------------------------------------------------------+
//|                                                    TEMA_SMA_EA.mq5 |
//|                                  Copyright 2024, Your Name Here   |
//|                                              https://www.yoursite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name Here"
#property link      "https://www.yoursite.com"
#property version   "1.00"

// Include Trade class for easier position management
#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>

// Input parameters
input group "Moving Average Settings"
input int                FastMAPeriod = 5;          // Fast MA (TEMA) Period
input int                SlowMAPeriod = 9;          // Slow MA (SMA) Period

input group "Risk Management"
input double             StopLossPips = 150.0;      // Stop Loss in pips
input bool               UseTrailingStop = true;    // Enable Trailing Stop
input double             TakeProfitPips = 300.0;    // Take Profit in pips
input bool               UseTakeProfit = true;      // Enable Take Profit

input group "Trade Settings"
input double             LotSize = 0.01;            // Lot Size
input int                MagicNumber = 2024;        // Magic Number
input int                Slippage = 30;             // Slippage in points
input string             TradeComment = "TEMA_SMA_XAU"; // Trade Comment

input group "XAUUSD Settings"
input bool               ExtendedHoursFilter = true;  // Filter low liquidity periods
input double             MinSpread = 0.10;            // Minimum spread to avoid (in USD)
input int                MaxDailyTrades = 5;          // Maximum trades per day
input bool               AvoidNewsEvents = true;      // Avoid trading during news (NFP, FOMC, etc.)


input group "Visual Settings"
input color              BuySignalColor = clrLime;  // Buy signal color
input color              SellSignalColor = clrRed;  // Sell signal color
input color              WaitSignalColor = clrGray; // Waiting signal color
input string             FontFace = "Arial";        // Font for display
input int                FontSize = 14;             // Font size
input ENUM_BASE_CORNER   Corner = CORNER_LEFT_UPPER; // Display corner
input int                X_Offset = 10;             // X offset from corner
input int                Y_Offset = 20;             // Y offset from corner
// Global variables for XAUUSD
datetime lastTradeTime;
int tradesToday;

// Global variables
CTrade          trade;
CSymbolInfo     symbolInfo;
CPositionInfo   positionInfo;
CHistoryOrderInfo historyInfo;

// Indicator handles
int             temaHandle;
int             smaHandle;

// For crossover detection
double          temaCurrent, temaPrevious;
double          smaCurrent, smaPrevious;
datetime        lastBarTime;

// For signal tracking
enum ENUM_SIGNAL_TYPE 
{
   SIGNAL_NONE,
   SIGNAL_BUY,
   SIGNAL_SELL
};

ENUM_SIGNAL_TYPE currentSignal = SIGNAL_NONE;
ENUM_SIGNAL_TYPE previousSignal = SIGNAL_NONE;
datetime signalTime;

// Object names for chart display
string          objPrefix = "TEMA_SMA_Signal_";
string          objSignalName = objPrefix + "Signal";
string          objTimeName = objPrefix + "Time";
string          objStatusName = objPrefix + "Status";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
      return INIT_FAILED;
   
   // Set magic number for trade object
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Create indicator handles
   temaHandle = iTEMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, PRICE_CLOSE);
   smaHandle = iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   
   if(temaHandle == INVALID_HANDLE || smaHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }
   
   // Initialize last bar time
   lastBarTime = 0;
   
   // Initialize signal display
   CreateSignalDisplay();
   UpdateSignalDisplay("Waiting for opportunity...", WaitSignalColor);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(temaHandle != INVALID_HANDLE)
      IndicatorRelease(temaHandle);
   if(smaHandle != INVALID_HANDLE)
      IndicatorRelease(smaHandle);
   
   // Remove chart objects
   ObjectsDeleteAll(0, objPrefix);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(!IsNewBar())
      return;
   
   // XAUUSD: Check spread
   double currentSpread = symbolInfo.Ask() - symbolInfo.Bid();
   if(currentSpread > MinSpread * 10) // Convert to points
   {
      Print("Spread too high: ", currentSpread);
      return;
   }
   
   // XAUUSD: Check trading hours (avoid low liquidity)
   if(ExtendedHoursFilter && !IsOptimalTradingTime())
      return;
   
   // XAUUSD: Limit daily trades
   if(tradesToday >= MaxDailyTrades)
      return;
   
   // Continue with normal logic...
   if(!symbolInfo.RefreshRates())
      return;
   
   // Get current prices
   if(!symbolInfo.RefreshRates())
      return;
   
   // Get indicator values
   if(!GetIndicatorValues())
      return;
   
   // Store previous signal
   previousSignal = currentSignal;
   
   // Check for signals
   CheckForSignals();
   
   // Update display based on signal
   UpdateDisplay();
   
   // Manage trailing stop if enabled
   if(UseTrailingStop)
      ManageTrailingStop();
}

// XAUUSD optimal trading hours (London-New York overlap)
bool IsOptimalTradingTime()
{
   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   
   // Optimal hours: 8:00-17:00 GMT (London-NY overlap)
   if(time.hour >= 8 && time.hour <= 17)
      return true;
   
   // Avoid weekends
   if(time.day_of_week == 0 || time.day_of_week == 6)
      return false;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
// Get indicator values                                              |
//+------------------------------------------------------------------+
bool GetIndicatorValues()
{
   // Arrays to store indicator values
   double temaValues[2];
   double smaValues[2];
   
   // Copy TEMA values (current and previous)
   if(CopyBuffer(temaHandle, 0, 0, 2, temaValues) != 2)
   {
      Print("Error copying TEMA values");
      return false;
   }
   
   // Copy SMA values (current and previous)
   if(CopyBuffer(smaHandle, 0, 0, 2, smaValues) != 2)
   {
      Print("Error copying SMA values");
      return false;
   }
   
   // Store values for crossover detection
   temaPrevious = temaValues[1];
   temaCurrent = temaValues[0];
   smaPrevious = smaValues[1];
   smaCurrent = smaValues[0];
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for crossover signals                                      |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   // Check for buy signal (TEMA crosses above SMA)
   if(temaPrevious <= smaPrevious && temaCurrent > smaCurrent)
   {
      currentSignal = SIGNAL_BUY;
      signalTime = TimeCurrent();
      Print("BUY signal detected at ", signalTime);
      
      // Close any existing sell positions
      ClosePositions(POSITION_TYPE_SELL);
      
      // Execute buy trade
      ExecuteBuy();
   }
   // Check for sell signal (TEMA crosses below SMA)
   else if(temaPrevious >= smaPrevious && temaCurrent < smaCurrent)
   {
      currentSignal = SIGNAL_SELL;
      signalTime = TimeCurrent();
      Print("SELL signal detected at ", signalTime);
      
      // Close any existing buy positions
      ClosePositions(POSITION_TYPE_BUY);
      
      // Execute sell trade
      ExecuteSell();
   }
   else
   {
      // No crossover detected
      currentSignal = SIGNAL_NONE;
   }
}

//+------------------------------------------------------------------+
//| Update display based on current signal                           |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   string signalText = "";
   color signalColor = WaitSignalColor;
   
   switch(currentSignal)
   {
      case SIGNAL_BUY:
         signalText = "BUY SIGNAL DETECTED";
         signalColor = BuySignalColor;
         break;
         
      case SIGNAL_SELL:
         signalText = "SELL SIGNAL DETECTED";
         signalColor = SellSignalColor;
         break;
         
      case SIGNAL_NONE:
      default:
         signalText = "Waiting for opportunity...";
         signalColor = WaitSignalColor;
         break;
   }
   
   UpdateSignalDisplay(signalText, signalColor);
}

//+------------------------------------------------------------------+
//| Create chart objects for signal display                          |
//+------------------------------------------------------------------+
void CreateSignalDisplay()
{
   // Create main signal label
   ObjectCreate(0, objSignalName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objSignalName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, objSignalName, OBJPROP_XDISTANCE, X_Offset);
   ObjectSetInteger(0, objSignalName, OBJPROP_YDISTANCE, Y_Offset);
   ObjectSetInteger(0, objSignalName, OBJPROP_COLOR, WaitSignalColor);
   ObjectSetInteger(0, objSignalName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, objSignalName, OBJPROP_FONT, FontFace);
   ObjectSetInteger(0, objSignalName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, objSignalName, OBJPROP_TEXT, "TEMA/SMA EA");
   ObjectSetInteger(0, objSignalName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objSignalName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, objSignalName, OBJPROP_ZORDER, 0);
   
   // Create signal status text
   ObjectCreate(0, objStatusName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objStatusName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, objStatusName, OBJPROP_XDISTANCE, X_Offset);
   ObjectSetInteger(0, objStatusName, OBJPROP_YDISTANCE, Y_Offset + 25);
   ObjectSetInteger(0, objStatusName, OBJPROP_COLOR, WaitSignalColor);
   ObjectSetInteger(0, objStatusName, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, objStatusName, OBJPROP_FONT, FontFace);
   ObjectSetInteger(0, objStatusName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, objStatusName, OBJPROP_TEXT, "Waiting for opportunity...");
   ObjectSetInteger(0, objStatusName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objStatusName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, objStatusName, OBJPROP_ZORDER, 0);
   
   // Create signal time display
   ObjectCreate(0, objTimeName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objTimeName, OBJPROP_CORNER, Corner);
   ObjectSetInteger(0, objTimeName, OBJPROP_XDISTANCE, X_Offset);
   ObjectSetInteger(0, objTimeName, OBJPROP_YDISTANCE, Y_Offset + 50);
   ObjectSetInteger(0, objTimeName, OBJPROP_COLOR, clrSilver);
   ObjectSetInteger(0, objTimeName, OBJPROP_FONTSIZE, FontSize - 2);
   ObjectSetString(0, objTimeName, OBJPROP_FONT, FontFace);
   ObjectSetInteger(0, objTimeName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, objTimeName, OBJPROP_TEXT, "");
   ObjectSetInteger(0, objTimeName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objTimeName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, objTimeName, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
//| Update signal display on chart                                   |
//+------------------------------------------------------------------+
void UpdateSignalDisplay(string text, color clr)
{
   // Update status text
   ObjectSetString(0, objStatusName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objStatusName, OBJPROP_COLOR, clr);
   
   // Update signal time if we have an active signal
   if(currentSignal == SIGNAL_BUY || currentSignal == SIGNAL_SELL)
   {
      string timeText = "Signal Time: " + TimeToString(signalTime, TIME_DATE|TIME_SECONDS);
      ObjectSetString(0, objTimeName, OBJPROP_TEXT, timeText);
      
      // Make bold for active signals
      if(clr == BuySignalColor || clr == SellSignalColor)
      {
         ObjectSetInteger(0, objStatusName, OBJPROP_FONTSIZE, FontSize + 2); // Larger = bolder
         //ObjectSetInteger(0, objStatusName, OBJPROP_BOLD, true);
      }
   }
   else
   {
      // Clear time display for waiting state
      ObjectSetString(0, objTimeName, OBJPROP_TEXT, "");
      
      // Normal font for waiting state
      ObjectSetInteger(0, objStatusName, OBJPROP_FONTSIZE, FontSize);
      //ObjectSetInteger(0, objStatusName, OBJPROP_BOLD, false);
   }
   
   // Make all objects visible
   ObjectSetInteger(0, objSignalName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objStatusName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objTimeName, OBJPROP_HIDDEN, false);
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   // Calculate stop loss price in pips
   double slPrice = 0;
   double tpPrice = 0;
   
   if(StopLossPips > 0)
   {
      // For buy orders: SL = Ask - (StopLossPips * Point)
      slPrice = symbolInfo.Ask() - (StopLossPips * symbolInfo.Point());
      slPrice = NormalizeDouble(slPrice, symbolInfo.Digits());
   }
   
   if(UseTakeProfit && TakeProfitPips > 0)
   {
      tpPrice = symbolInfo.Ask() + (TakeProfitPips * symbolInfo.Point());
      tpPrice = NormalizeDouble(tpPrice, symbolInfo.Digits());
   }
   
   // Execute buy order
   trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, LotSize, 
                     symbolInfo.Ask(), slPrice, tpPrice, TradeComment);
   
   if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
      Print("Buy order failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Execute sell trade                                               |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   // Calculate stop loss price in pips
   double slPrice = 0;
   double tpPrice = 0;
   
   if(StopLossPips > 0)
   {
      // For sell orders: SL = Bid + (StopLossPips * Point)
      slPrice = symbolInfo.Bid() + (StopLossPips * symbolInfo.Point());
      slPrice = NormalizeDouble(slPrice, symbolInfo.Digits());
   }
   
   if(UseTakeProfit && TakeProfitPips > 0)
   {
      tpPrice = symbolInfo.Bid() - (TakeProfitPips * symbolInfo.Point());
      tpPrice = NormalizeDouble(tpPrice, symbolInfo.Digits());
   }
   
   // Execute sell order
   trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, LotSize, 
                     symbolInfo.Bid(), slPrice, tpPrice, TradeComment);
   
   if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
      Print("Sell order failed: ", trade.ResultRetcodeDescription());
}


//+------------------------------------------------------------------+
//| Close positions of specified type                                |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE positionType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType)
         {
            trade.PositionClose(ticket);
            Print("Position closed:->",positionType);
            if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
               Print("Failed to close position ", ticket, ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop (also updated for pips)                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Calculate trailing stop distance in pips
   double trailingDistancePips = StopLossPips;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionCurrentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
               // For buy positions: newSL = currentPrice - trailingDistancePips
               double newSL = positionCurrentPrice - (trailingDistancePips * symbolInfo.Point());
               newSL = NormalizeDouble(newSL, symbolInfo.Digits());
               Print("buy SL modified");
               // Only move SL if it's higher than current SL and above breakeven
               if(newSL > currentSL && newSL > positionOpenPrice)
               {
                  if(!trade.PositionModify(ticket, newSL, currentTP))
                     Print("Failed to modify trailing stop for buy position: ", trade.ResultRetcodeDescription());
               }
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
               // For sell positions: newSL = currentPrice + trailingDistancePips
               double newSL = positionCurrentPrice + (trailingDistancePips * symbolInfo.Point());
               newSL = NormalizeDouble(newSL, symbolInfo.Digits());
               Print("sell SL modified");
               // Only move SL if it's lower than current SL and below breakeven
               if((currentSL == 0 || newSL < currentSL) && newSL < positionOpenPrice)
               {
                  if(!trade.PositionModify(ticket, newSL, currentTP))
                     Print("Failed to modify trailing stop for sell position: ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom TEMA indicator calculation (if needed)                    |
//+------------------------------------------------------------------+
int iTEMA(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period, 
          const int shift, const ENUM_APPLIED_PRICE applied_price)
{
   // MQL5 has built-in iTEMA indicator
   int handle = iCustom(symbol, timeframe, "Examples\\TEMA", period, applied_price);
   return handle;
}

//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Additional helper function to convert pips to dollars            |
//+------------------------------------------------------------------+
double PipsToDollars(double pips, double lotSize)
{
   // Calculate the dollar value of pips
   // For most brokers: 1 pip = 0.0001 for most pairs, but for Gold it's 0.01
   double pipValue = 0;
   
   if(_Symbol == "XAUUSD" || StringFind(_Symbol, "XAU") != -1)
   {
      // For Gold: 1 pip = 0.01 (most brokers)
      pipValue = (lotSize * 100) * pips * 0.01;
   }
   else
   {
      // For Forex pairs: 1 pip = 0.0001
      pipValue = (lotSize * 100000) * pips * 0.0001;
   }
   
   return pipValue;
}

//+------------------------------------------------------------------+
//| Additional display for current indicator values                  |
//+------------------------------------------------------------------+
void DisplayIndicatorValues()
{
   string valuesText = StringFormat("TEMA: %.5f | SMA: %.5f", temaCurrent, smaCurrent);
   
   // Create or update indicator values display
   string objValuesName = objPrefix + "Values";
   
   if(ObjectFind(0, objValuesName) < 0)
   {
      ObjectCreate(0, objValuesName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objValuesName, OBJPROP_CORNER, Corner);
      ObjectSetInteger(0, objValuesName, OBJPROP_XDISTANCE, X_Offset);
      ObjectSetInteger(0, objValuesName, OBJPROP_YDISTANCE, Y_Offset + 75);
      ObjectSetInteger(0, objValuesName, OBJPROP_COLOR, clrSilver);
      ObjectSetInteger(0, objValuesName, OBJPROP_FONTSIZE, FontSize - 2);
      ObjectSetString(0, objValuesName, OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, objValuesName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, objValuesName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objValuesName, OBJPROP_HIDDEN, false);
   }
   
   ObjectSetString(0, objValuesName, OBJPROP_TEXT, valuesText);
}