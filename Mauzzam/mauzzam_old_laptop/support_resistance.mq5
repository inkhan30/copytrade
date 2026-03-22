//+------------------------------------------------------------------+
//|                                                   SR_EA_v1.mq5   |
//|                                     Copyright 2024, Expert Trader |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Expert Trader"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Include Trade Classes
#include <Trade/Trade.mqh>
CTrade Trade;

//--- Input Parameters
input group "=== Trading Settings ==="
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M5;       // Working Timeframe (M5 or M15)
input bool UseCurrentChartTF = false;              // Use Current Chart Timeframe
input double LotSize = 0.1;                        // Fixed Lot Size
input int SL_Pips = 50;                            // Stop Loss in Pips
input int TP_Pips = 100;                           // Take Profit in Pips
input int Slippage = 3;                            // Slippage in Points

input group "=== Support/Resistance Settings ==="
input int SR_LookbackBars = 50;                    // Bars to analyze for SR
input int SR_ZoneWidthPips = 10;                   // SR Zone Width in Pips
input int MinTouchPoints = 2;                      // Minimum touches for valid SR

input group "=== Risk Management ==="
input bool EnableMaxDailyLoss = false;             // Enable Max Daily Loss
input double MaxDailyLossPercent = 5.0;            // Max Daily Loss (% of Balance)
input bool EnableMaxDailyTrades = false;           // Enable Max Daily Trades
input int MaxDailyTrades = 5;                      // Maximum Trades Per Day

input group "=== Display Settings ==="
input color BuySignalColor = clrLime;              // Buy Signal Color
input color SellSignalColor = clrRed;              // Sell Signal Color
input int SignalFontSize = 14;                     // Signal Font Size

//--- Global Variables
datetime LastTradeTime = 0;
double DailyProfitLoss = 0;
int DailyTradeCount = 0;
datetime LastDailyReset = 0;

//--- Support/Resistance Arrays
double SupportLevels[];
double ResistanceLevels[];
double CurrentPrice = 0;

//--- Display Objects
string SignalTextObj = "SR_Signal_Text";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Log initialization
   Print("=== SR Expert Advisor Initialization ===");
   Print("EA Version: 1.00");
   Print("Initialized on Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(TimeFrame));
   Print("Lot Size: ", LotSize);
   Print("SL: ", SL_Pips, " pips | TP: ", TP_Pips, " pips");
   
   //--- Set trade settings
   Trade.SetDeviationInPoints(Slippage);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);
   Trade.SetAsyncMode(false);
   
   //--- Hide grid lines
   HideGridLines();
   
   //--- Create display objects
   CreateDisplayObjects();
   
   //--- Reset daily counters if new day
   ResetDailyCounters();
   
   //--- Log successful initialization
   Print("EA initialized successfully at: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Remove display objects
   ObjectDelete(0, SignalTextObj);
   
   //--- Log deinitialization
   Print("EA deinitialized. Reason: ", GetUninitReasonText(reason));
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily counters at new day
   if(TimeCurrent() >= LastDailyReset + 86400)
   {
      ResetDailyCounters();
   }
   
   //--- Get working timeframe
   ENUM_TIMEFRAMES workingTF = UseCurrentChartTF ? _Period : TimeFrame;
   
   //--- Check for new bar (prevents multiple entries on same bar)
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, workingTF, 0);
   if(lastBarTime == currentBarTime)
      return;
   lastBarTime = currentBarTime;
   
   //--- Log new bar
   Print("New bar detected on ", EnumToString(workingTF), 
         " | Time: ", TimeToString(currentBarTime, TIME_MINUTES));
   
   //--- Update current price
   CurrentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Calculate Support and Resistance levels
   CalculateSupportResistance(workingTF);
   
   //--- Check trading conditions
   CheckTradingConditions(workingTF);
   
   //--- Update display
   UpdateSignalDisplay();
   
   //--- Log market state periodically
   static datetime lastLogTime = 0;
   if(TimeCurrent() >= lastLogTime + 300) // Log every 5 minutes
   {
      Print("Market Update | Bid: ", CurrentPrice, 
            " | Supports: ", ArraySize(SupportLevels), 
            " | Resistances: ", ArraySize(ResistanceLevels),
            " | Daily P/L: ", DailyProfitLoss,
            " | Daily Trades: ", DailyTradeCount);
      lastLogTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Calculate Support and Resistance levels                          |
//+------------------------------------------------------------------+
void CalculateSupportResistance(ENUM_TIMEFRAMES tf)
{
   //--- Clear arrays
   ArrayFree(SupportLevels);
   ArrayFree(ResistanceLevels);
   
   //--- Get rates
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, SR_LookbackBars, rates);
   
   if(copied <= 0)
   {
      Print("Failed to copy rates for SR calculation. Error: ", GetLastError());
      return;
   }
   
   //--- Temporary arrays for potential levels
   double tempSupports[100];
   double tempResistances[100];
   int supCount = 0;
   int resCount = 0;
   
   //--- Find potential swing highs and lows
   for(int i = 3; i < copied - 3; i++)
   {
      // Check for swing low (potential support)
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
      {
         // Check if this level is not too close to existing support
         bool isNewLevel = true;
         for(int j = 0; j < supCount; j++)
         {
            if(MathAbs(rates[i].low - tempSupports[j]) < SR_ZoneWidthPips * _Point * 10)
            {
               isNewLevel = false;
               break;
            }
         }
         if(isNewLevel && supCount < 100)
         {
            tempSupports[supCount++] = rates[i].low;
         }
      }
      
      // Check for swing high (potential resistance)
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
      {
         // Check if this level is not too close to existing resistance
         bool isNewLevel = true;
         for(int j = 0; j < resCount; j++)
         {
            if(MathAbs(rates[i].high - tempResistances[j]) < SR_ZoneWidthPips * _Point * 10)
            {
               isNewLevel = false;
               break;
            }
         }
         if(isNewLevel && resCount < 100)
         {
            tempResistances[resCount++] = rates[i].high;
         }
      }
   }
   
   //--- Copy to main arrays
   ArrayResize(SupportLevels, supCount);
   ArrayResize(ResistanceLevels, resCount);
   
   for(int i = 0; i < supCount; i++)
      SupportLevels[i] = tempSupports[i];
   
   for(int i = 0; i < resCount; i++)
      ResistanceLevels[i] = tempResistances[i];
   
   //--- Sort arrays
   ArraySort(SupportLevels);
   ArraySort(ResistanceLevels);
   
   //--- Log calculated levels
   Print("SR Calculation Complete. Found ", supCount, " supports and ", resCount, " resistances");
   if(supCount > 0)
      Print("Nearest Support: ", SupportLevels[supCount-1]);
   if(resCount > 0)
      Print("Nearest Resistance: ", ResistanceLevels[0]);
}

//+------------------------------------------------------------------+
//| Check trading conditions                                         |
//+------------------------------------------------------------------+
void CheckTradingConditions(ENUM_TIMEFRAMES tf)
{
   //--- Check if we already have a position
   if(PositionSelect(_Symbol))
   {
      Print("Position already exists. Skipping new signal check.");
      return;
   }
   
   //--- Check risk management
   if(!CheckRiskManagement())
   {
      Print("Risk management check failed. Skipping trade.");
      return;
   }
   
   //--- Check for buy signal (price at support)
   for(int i = 0; i < ArraySize(SupportLevels); i++)
   {
      double supportLevel = SupportLevels[i];
      double zoneTop = supportLevel + (SR_ZoneWidthPips * _Point * 10);
      
      if(CurrentPrice >= supportLevel && CurrentPrice <= zoneTop)
      {
         // Additional confirmation
         if(CheckBuyConfirmation(tf))
         {
            ExecuteBuyOrder();
            return;
         }
      }
   }
   
   //--- Check for sell signal (price at resistance)
   for(int i = 0; i < ArraySize(ResistanceLevels); i++)
   {
      double resistanceLevel = ResistanceLevels[i];
      double zoneBottom = resistanceLevel - (SR_ZoneWidthPips * _Point * 10);
      
      if(CurrentPrice <= resistanceLevel && CurrentPrice >= zoneBottom)
      {
         // Additional confirmation
         if(CheckSellConfirmation(tf))
         {
            ExecuteSellOrder();
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check buy confirmation                                           |
//+------------------------------------------------------------------+
bool CheckBuyConfirmation(ENUM_TIMEFRAMES tf)
{
   //--- Check for bullish reversal pattern
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, tf, 0, 3, rates);
   
   // Simple bullish engulfing pattern
   if(rates[1].close < rates[1].open && rates[0].close > rates[0].open)
   {
      if(rates[0].close > rates[1].open && rates[0].open < rates[1].close)
      {
         Print("Buy confirmation: Bullish engulfing pattern detected");
         return true;
      }
   }
   
   // Price above previous close
   if(rates[0].close > rates[1].close)
   {
      Print("Buy confirmation: Price closed above previous bar");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check sell confirmation                                          |
//+------------------------------------------------------------------+
bool CheckSellConfirmation(ENUM_TIMEFRAMES tf)
{
   //--- Check for bearish reversal pattern
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, tf, 0, 3, rates);
   
   // Simple bearish engulfing pattern
   if(rates[1].close > rates[1].open && rates[0].close < rates[0].open)
   {
      if(rates[0].close < rates[1].open && rates[0].open > rates[1].close)
      {
         Print("Sell confirmation: Bearish engulfing pattern detected");
         return true;
      }
   }
   
   // Price below previous close
   if(rates[0].close < rates[1].close)
   {
      Print("Sell confirmation: Price closed below previous bar");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Execute buy order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   //--- Calculate SL and TP
   double sl = CurrentPrice - (SL_Pips * _Point * 10);
   double tp = CurrentPrice + (TP_Pips * _Point * 10);
   
   //--- Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = 123456;
   request.comment = "SR_EA_Buy";
   
   //--- Execute trade
   if(OrderSend(request, result))
   {
      Print("BUY Order Executed Successfully!");
      Print("Price: ", result.price, " | SL: ", sl, " | TP: ", tp);
      Print("Ticket: ", result.order);
      
      //--- Update counters
      LastTradeTime = TimeCurrent();
      DailyTradeCount++;
   }
   else
   {
      Print("BUY Order Failed! Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Execute sell order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder()
{
   //--- Calculate SL and TP
   double sl = CurrentPrice + (SL_Pips * _Point * 10);
   double tp = CurrentPrice - (TP_Pips * _Point * 10);
   
   //--- Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = 123456;
   request.comment = "SR_EA_Sell";
   
   //--- Execute trade
   if(OrderSend(request, result))
   {
      Print("SELL Order Executed Successfully!");
      Print("Price: ", result.price, " | SL: ", sl, " | TP: ", tp);
      Print("Ticket: ", result.order);
      
      //--- Update counters
      LastTradeTime = TimeCurrent();
      DailyTradeCount++;
   }
   else
   {
      Print("SELL Order Failed! Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check risk management                                            |
//+------------------------------------------------------------------+
bool CheckRiskManagement()
{
   //--- Check maximum daily loss
   if(EnableMaxDailyLoss)
   {
      double maxLoss = AccountInfoDouble(ACCOUNT_BALANCE) * (MaxDailyLossPercent / 100.0);
      if(DailyProfitLoss <= -maxLoss)
      {
         Print("Daily loss limit reached. P/L: ", DailyProfitLoss, " | Limit: ", -maxLoss);
         return false;
      }
   }
   
   //--- Check maximum daily trades
   if(EnableMaxDailyTrades && DailyTradeCount >= MaxDailyTrades)
   {
      Print("Maximum daily trades reached: ", DailyTradeCount);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   DailyProfitLoss = 0;
   DailyTradeCount = 0;
   LastDailyReset = TimeCurrent();
   
   Print("Daily counters reset at: ", TimeToString(LastDailyReset, TIME_DATE));
}

//+------------------------------------------------------------------+
//| Hide grid lines                                                  |
//+------------------------------------------------------------------+
void HideGridLines()
{
   ChartSetInteger(0, CHART_SHOW_GRID, 0);
   Print("Grid lines hidden on chart");
}

//+------------------------------------------------------------------+
//| Create display objects                                           |
//+------------------------------------------------------------------+
void CreateDisplayObjects()
{
   //--- Create signal text object
   ObjectCreate(0, SignalTextObj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, SignalTextObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, SignalTextObj, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, SignalTextObj, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, SignalTextObj, OBJPROP_FONTSIZE, SignalFontSize);
   ObjectSetString(0, SignalTextObj, OBJPROP_TEXT, "SR EA v1.0");
   ObjectSetInteger(0, SignalTextObj, OBJPROP_COLOR, clrWhite);
   
   Print("Display objects created");
}

//+------------------------------------------------------------------+
//| Update signal display                                            |
//+------------------------------------------------------------------+
void UpdateSignalDisplay()
{
   string signalText = "SR EA v1.0 | " + _Symbol + "\n";
   signalText += "Timeframe: " + EnumToString(TimeFrame) + "\n";
   signalText += "Bid: " + DoubleToString(CurrentPrice, _Digits) + "\n";
   signalText += "Supports: " + IntegerToString(ArraySize(SupportLevels)) + "\n";
   signalText += "Resistances: " + IntegerToString(ArraySize(ResistanceLevels)) + "\n";
   signalText += "Daily Trades: " + IntegerToString(DailyTradeCount) + "\n";
   signalText += "Daily P/L: " + DoubleToString(DailyProfitLoss, 2) + "\n";
   
   //--- Check for signals
   bool buySignal = false;
   bool sellSignal = false;
   
   for(int i = 0; i < ArraySize(SupportLevels); i++)
   {
      double zoneTop = SupportLevels[i] + (SR_ZoneWidthPips * _Point * 10);
      if(CurrentPrice >= SupportLevels[i] && CurrentPrice <= zoneTop)
      {
         buySignal = true;
         break;
      }
   }
   
   for(int i = 0; i < ArraySize(ResistanceLevels); i++)
   {
      double zoneBottom = ResistanceLevels[i] - (SR_ZoneWidthPips * _Point * 10);
      if(CurrentPrice <= ResistanceLevels[i] && CurrentPrice >= zoneBottom)
      {
         sellSignal = true;
         break;
      }
   }
   
   if(buySignal)
      signalText += "\n>>> BUY SIGNAL <<<";
   else if(sellSignal)
      signalText += "\n>>> SELL SIGNAL <<<";
   else
      signalText += "\n>>> NO SIGNAL <<<";
   
   //--- Update object
   ObjectSetString(0, SignalTextObj, OBJPROP_TEXT, signalText);
   
   //--- Change color based on signal
   if(buySignal)
      ObjectSetInteger(0, SignalTextObj, OBJPROP_COLOR, BuySignalColor);
   else if(sellSignal)
      ObjectSetInteger(0, SignalTextObj, OBJPROP_COLOR, SellSignalColor);
   else
      ObjectSetInteger(0, SignalTextObj, OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
//| Get uninitialization reason text                                 |
//+------------------------------------------------------------------+
string GetUninitReasonText(int reasonCode)
{
   switch(reasonCode)
   {
      case REASON_ACCOUNT:    return "Account changed";
      case REASON_CHARTCHANGE:return "Chart changed";
      case REASON_CHARTCLOSE: return "Chart closed";
      case REASON_CLOSE:      return "Terminal closed";
      case REASON_INITFAILED: return "Initialization failed";
      case REASON_PARAMETERS: return "Parameters changed";
      case REASON_RECOMPILE:  return "Code recompiled";
      case REASON_REMOVE:     return "EA removed";
      case REASON_TEMPLATE:   return "Template changed";
      default:                return "Unknown reason";
   }
}

//+------------------------------------------------------------------+
//| OnTrade function - track profit/loss                            |
//+------------------------------------------------------------------+
void OnTrade()
{
   //--- Calculate daily profit/loss
   double totalProfit = 0;
   int totalPositions = PositionsTotal();
   
   for(int i = 0; i < totalPositions; i++)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   
   DailyProfitLoss = totalProfit;
   
   //--- Log trade event
   Print("Trade event. Total positions: ", totalPositions, " | Daily P/L: ", DailyProfitLoss);
}
//+------------------------------------------------------------------+