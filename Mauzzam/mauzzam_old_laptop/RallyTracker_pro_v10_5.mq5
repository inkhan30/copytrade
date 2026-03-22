//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic Hedging RallyTrackerPro_v10_4           |
//| (Pyramiding on favorable moves + initial SL + breakeven stop)   |
//| (First position has no TP – scaling works)                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, RallyTrackerPro_v10_4"
#property link      "https://www.mql5.com"
#property version   "10.05"
#property strict
#property indicator_chart_window

// Hard-coded array of allowed account numbers
const long ALLOWED_ACCOUNT_NUMBERS[] = {206895936};

// --- EXPIRY DATE (MODIFY THIS LINE TO SET/UPDATE EXPIRY) ---
const datetime EXPIRY_DATE = D'2026.12.31';

input bool     EnableStrategy      = true;
input bool     EnableEquityStop    = false;
input double   MaxEquityDrawdownPercent = 20.0;
input bool     RestartAfterDrawdown = true;
input int      ConsecutiveCandles  = 2;
input double   InitialLotSize      = 0.01;
input string   CustomLots          = "0.01,0.02,0.03";
input int      InitialTPPips       = 100;          // NOT USED for first position (kept for compatibility)
input string   TriggerPipsArray    = "700,1400,2100";
input string   ProfitTargets       = "1000,2000,3000,4000";
input int      MagicNumber         = 123456;
input bool     UseEMAFilter        = true;
input int      EMA_Period          = 200;
input int      LastPositionSLPips  = 200;          // SL for the last scaling position

// RSI Filter Inputs
input bool     UseRSIFilter        = false;
input int      RSI_Period          = 14;
input int      RSI_Overbought      = 75;
input int      RSI_Oversold        = 35;
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE;
input int      RSIDirection        = 0;
input bool     ReverseRSI          = false;

// ATR Indicator Inputs
input bool     UseATRIndicator     = true;        // Show ATR on chart
input int      ATR_Period          = 14;          // ATR period
input bool     UseATRStop          = false;       // Enable/disable ATR stop
input double   ATRHighThreshold    = 2.0;         // ATR level (in points) above which trading stops
input bool     CloseOnHighATR      = true;        // true = close all positions, false = only block new entries

// --- INPUTS FOR PYRAMIDING & STOP LOSS ---
input int      InitialSLPips       = 200;         // Stop loss for the first position (pips)
input bool     UseBreakevenStop    = true;        // After first scale, move all stops to breakeven (+ buffer)
input int      BreakevenBufferPips = 0;           // Additional buffer above breakeven (positive for buys, negative for sells)

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayDouble.mqh>
CTrade trade;
CPositionInfo positionInfo;
CArrayInt triggerPips;
CArrayDouble customLotsArray;
CArrayInt profitTargetsArray;

// Global variables
bool strategyEnabled;
int direction = 0;               // 1 for Buy, -1 for Sell
bool initialTradeOpened = false;
bool equityStopTriggered = false;
datetime lastHedgeTime = 0;
double highestEquity = 0;
double initialEntryPrice = 0;    // Price of the first position
int emaHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;
#define PIP 10

// ATR stop flag
bool atrStopTriggered = false;

// Chart label names
string capitalLabel = "CapitalLabel";
string capitalValue = "CapitalValue";
string marginLabel = "MarginLabel";
string marginValue = "MarginValue";
string tpLabel = "TPLabel";
string tpValue = "TPValue";
string profitTargetLabel = "ProfitTargetLabel";
string profitTargetValue = "ProfitTargetValue";
string beLabel = "BreakEvenLabel";
string beValue = "BreakEvenValue";
string statusLabel = "StatusLabel";
string statusValue = "StatusValue";
string atrLabel = "ATRLabel";
string atrValue = "ATRValue";

//+------------------------------------------------------------------+
//| Check if current account is allowed                              |
//+------------------------------------------------------------------+
bool IsAccountAllowed()
{
   long currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);
   for(int i = 0; i < ArraySize(ALLOWED_ACCOUNT_NUMBERS); i++)
      if(currentAccount == ALLOWED_ACCOUNT_NUMBERS[i])
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Parse the ProfitTargets string                                   |
//+------------------------------------------------------------------+
bool ParseProfitTargetsArray()
{
   string values[];
   int count = StringSplit(ProfitTargets, ',', values);
   if(count <= 0) return false;
   profitTargetsArray.Clear();
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp); StringTrimRight(temp);
      int pipValue = (int)StringToInteger(temp);
      if(pipValue <= 0) return false;
      profitTargetsArray.Add(pipValue);
   }
   int expectedSize = triggerPips.Total() + 1;
   if(profitTargetsArray.Total() != expectedSize)
   {
      Print("Error: ProfitTargets must have exactly ", expectedSize, " values.");
      return false;
   }
   Print("Successfully parsed ", profitTargetsArray.Total(), " profit target values");
   return true;
}

//+------------------------------------------------------------------+
//| Parse the TriggerPipsArray string                                |
//+------------------------------------------------------------------+
bool ParseTriggerPipsArray()
{
   string values[];
   int count = StringSplit(TriggerPipsArray, ',', values);
   if(count <= 0) return false;
   triggerPips.Clear();
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp); StringTrimRight(temp);
      int pipValue = (int)StringToInteger(temp);
      if(pipValue <= 0) return false;
      triggerPips.Add(pipValue);
   }
   Print("Successfully parsed ", triggerPips.Total(), " trigger pip values");
   return true;
}

//+------------------------------------------------------------------+
//| Parse the CustomLots string                                      |
//+------------------------------------------------------------------+
bool ParseCustomLotsArray()
{
   string values[];
   int count = StringSplit(CustomLots, ',', values);
   if(count <= 0) return false;
   customLotsArray.Clear();
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp); StringTrimRight(temp);
      double lotValue = StringToDouble(temp);
      if(lotValue <= 0) return false;
      customLotsArray.Add(lotValue);
   }
   Print("Successfully parsed ", customLotsArray.Total(), " custom lot values");
   return true;
}

//+------------------------------------------------------------------+
//| Create ATR labels                                                |
//+------------------------------------------------------------------+
void CreateATRLabels()
{
   ObjectDelete(0, atrLabel); ObjectDelete(0, atrValue);
   int statusY = (int)ObjectGetInteger(0, statusValue, OBJPROP_YDISTANCE);
   int labelX = 10, valueX = 170, spacing = 25, atrY = statusY + spacing;
   ObjectCreate(0, atrLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, atrLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, atrLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, atrLabel, OBJPROP_YDISTANCE, atrY);
   ObjectSetInteger(0, atrLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, atrLabel, OBJPROP_TEXT, "ATR (" + IntegerToString(ATR_Period) + "):");
   ObjectSetInteger(0, atrLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, atrValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, atrValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, atrValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, atrValue, OBJPROP_YDISTANCE, atrY);
   ObjectSetInteger(0, atrValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, atrValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, atrValue, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Account check
   if(!IsAccountAllowed())
   {
      string allowedAccounts = "";
      for(int i = 0; i < ArraySize(ALLOWED_ACCOUNT_NUMBERS); i++)
      {
         if(i > 0) allowedAccounts += ", ";
         allowedAccounts += IntegerToString(ALLOWED_ACCOUNT_NUMBERS[i]);
      }
      Alert("EA not allowed on this account! Allowed accounts: ", allowedAccounts);
      strategyEnabled = false;
      UpdateStatusLabel("Wrong Account");
      return INIT_FAILED;
   }
   
   // Expiry check
   datetime now = TimeCurrent();
   if(now >= EXPIRY_DATE)
   {
      Print("EXPIRY DATE REACHED. EA will not start.");
      strategyEnabled = false;
      CreateInfoLabels();
      UpdateStatusLabel("Expired. Contact Developer for Renewal");
      return INIT_FAILED;
   }
   
   strategyEnabled = EnableStrategy;
   
   // Parse input arrays
   if(!ParseTriggerPipsArray()) return INIT_FAILED;
   if(!ParseCustomLotsArray()) return INIT_FAILED;
   if(triggerPips.Total() != customLotsArray.Total())
   {
      Print("Error: TriggerPipsArray and CustomLots must have same number of elements!");
      return INIT_FAILED;
   }
   if(!ParseProfitTargetsArray()) return INIT_FAILED;
   
   // Create indicators
   if(UseEMAFilter)
   {
      emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   if(UseRSIFilter)
   {
      rsiHandle = iRSI(_Symbol, _Period, RSI_Period, RSI_Price);
      if(rsiHandle == INVALID_HANDLE) return INIT_FAILED;
   }
   if(UseATRIndicator)
   {
      atrHandle = iATR(_Symbol, _Period, ATR_Period);
      if(atrHandle == INVALID_HANDLE) Print("Failed to create ATR indicator!");
   }
   
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityStopTriggered = false;
   atrStopTriggered = false;
   
   // Create chart objects
   CreateInfoLabels();
   CreateProfitTargetLine();
   if(UseATRIndicator && atrHandle != INVALID_HANDLE) CreateATRLabels();
   
   PrintConfiguredLotSizes();
   
   return INIT_SUCCEEDED;
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
//| Get current RSI value                                            |
//+------------------------------------------------------------------+
double GetRSIValue()
{
   if(rsiHandle == INVALID_HANDLE) return 50;
   double rsiValue[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsiValue) != 1) return 50;
   return rsiValue[0];
}

//+------------------------------------------------------------------+
//| Check RSI filter condition                                       |
//+------------------------------------------------------------------+
bool CheckRSIFilter(int &dir)
{
   if(!UseRSIFilter) return true;
   double rsiValue = GetRSIValue();
   if(rsiValue == 50) return false;
   int rawDir = 0;
   if(RSIDirection == 1)
   {
      if(rsiValue <= RSI_Oversold) rawDir = 1;
      else return false;
   }
   else if(RSIDirection == 2)
   {
      if(rsiValue >= RSI_Overbought) rawDir = -1;
      else return false;
   }
   else
   {
      if(rsiValue <= RSI_Oversold) rawDir = 1;
      else if(rsiValue >= RSI_Overbought) rawDir = -1;
      else return false;
   }
   if(ReverseRSI) dir = -rawDir;
   else dir = rawDir;
   return true;
}

//+------------------------------------------------------------------+
//| Print configuration                                              |
//+------------------------------------------------------------------+
void PrintConfiguredLotSizes()
{
   string lotSizesStr = "Configured Lot Sizes: [";
   for(int i = 0; i < customLotsArray.Total(); i++)
   {
      lotSizesStr += DoubleToString(customLotsArray.At(i), 2);
      if(i < customLotsArray.Total() - 1) lotSizesStr += ", ";
   }
   lotSizesStr += "]";
   Print(lotSizesStr);
   Print("Last position SL: ", LastPositionSLPips, " pips");
   
   string profitTargetsStr = "Profit Targets (pips) per position count: [";
   for(int i = 0; i < profitTargetsArray.Total(); i++)
   {
      profitTargetsStr += IntegerToString(profitTargetsArray.At(i));
      if(i < profitTargetsArray.Total() - 1) profitTargetsStr += ", ";
   }
   profitTargetsStr += "]";
   Print(profitTargetsStr);
   
   if(UseRSIFilter)
   {
      string rsiModeStr[] = {"Both sides", "Oversold only", "Overbought only"};
      Print("RSI Filter Mode: ", rsiModeStr[RSIDirection]);
      Print("RSI Reverse: ", ReverseRSI ? "Enabled" : "Disabled");
   }
   if(UseATRIndicator) Print("ATR enabled, Period: ", ATR_Period);
   if(UseATRStop) Print("ATR stop enabled, Threshold: ", ATRHighThreshold, ", CloseOnHighATR: ", CloseOnHighATR);
   Print("Initial SL: ", InitialSLPips, " pips (first position only)");
   Print("Breakeven stop: ", UseBreakevenStop ? "Enabled (buffer " + IntegerToString(BreakevenBufferPips) + " pips)" : "Disabled");
   Print("NOTE: First position has NO take profit – profit target based on basket.");
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
//| Check EMA filter condition                                       |
//+------------------------------------------------------------------+
bool CheckEMAFilter(int &dir)
{
   if(!UseEMAFilter) return true;
   double emaValue = GetEMAValue();
   if(emaValue == 0) return false;
   double currentClose = iClose(_Symbol, _Period, 1);
   if(currentClose > emaValue) { dir = 1; return true; }
   if(currentClose < emaValue) { dir = -1; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   
   ObjectDelete(0, capitalLabel); ObjectDelete(0, capitalValue);
   ObjectDelete(0, marginLabel); ObjectDelete(0, marginValue);
   ObjectDelete(0, tpLabel); ObjectDelete(0, tpValue);
   ObjectDelete(0, profitTargetLabel); ObjectDelete(0, profitTargetValue);
   ObjectDelete(0, beLabel); ObjectDelete(0, beValue);
   ObjectDelete(0, statusLabel); ObjectDelete(0, statusValue);
   ObjectDelete(0, "ProfitTargetLine");
   ObjectDelete(0, atrLabel); ObjectDelete(0, atrValue);
}

//+------------------------------------------------------------------+
//| Create profit target horizontal line                             |
//+------------------------------------------------------------------+
void CreateProfitTargetLine()
{
   ObjectCreate(0, "ProfitTargetLine", OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetString(0, "ProfitTargetLine", OBJPROP_TOOLTIP, "Profit Target Level");
}

//+------------------------------------------------------------------+
//| Update profit target line price                                  |
//+------------------------------------------------------------------+
void UpdateProfitTargetLine(int totalTrades)
{
   if(totalTrades == 0)
   {
      ObjectSetDouble(0, "ProfitTargetLine", OBJPROP_PRICE, 0);
      ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
      return;
   }
   int targetPips = profitTargetsArray.At(totalTrades - 1);
   double targetProfitCurrency = targetPips * PIP * _Point;
   double targetPrice = CalculateTargetPrice(totalTrades, targetProfitCurrency);
   if(targetPrice > 0)
   {
      ObjectSetDouble(0, "ProfitTargetLine", OBJPROP_PRICE, targetPrice);
      ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
      ObjectSetInteger(0, "ProfitTargetLine", OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
}

//+------------------------------------------------------------------+
//| Calculate price for target profit                                |
//+------------------------------------------------------------------+
double CalculateTargetPrice(int totalTrades, double targetProfitCurrency)
{
   double K = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(K <= 0) return 0;
   double A = 0, B = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      long type = PositionGetInteger(POSITION_TYPE);
      int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      A += lot * dir;
      B += lot * dir * entry;
   }
   if(A == 0) return 0;
   return (targetProfitCurrency / K + B) / A;
}

//+------------------------------------------------------------------+
//| Create information labels on chart                               |
//+------------------------------------------------------------------+
void CreateInfoLabels()
{
   int spacing = 25, startY = 20, labelX = 10, valueX = 170;
   // Capital
   ObjectCreate(0, capitalLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, capitalLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, capitalLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, capitalLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, capitalLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, capitalLabel, OBJPROP_TEXT, "Capital:");
   ObjectSetInteger(0, capitalLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, capitalValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, capitalValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, capitalValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, capitalValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, capitalValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, capitalValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, capitalValue, OBJPROP_FONTSIZE, 10);
   // Margin
   startY += spacing + 5;
   ObjectCreate(0, marginLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, marginLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, marginLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, marginLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, marginLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, marginLabel, OBJPROP_TEXT, "Margin Used:");
   ObjectSetInteger(0, marginLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, marginValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, marginValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, marginValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, marginValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, marginValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, marginValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, marginValue, OBJPROP_FONTSIZE, 10);
   // TP
   startY += spacing + 5;
   ObjectCreate(0, tpLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tpLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tpLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, tpLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, tpLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, tpLabel, OBJPROP_TEXT, "TP Price:");
   ObjectSetInteger(0, tpLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, tpValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tpValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tpValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, tpValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, tpValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, tpValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, tpValue, OBJPROP_FONTSIZE, 10);
   // Profit target
   startY += spacing;
   ObjectCreate(0, profitTargetLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, profitTargetLabel, OBJPROP_TEXT, "Profit Target:");
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, profitTargetValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, profitTargetValue, OBJPROP_FONTSIZE, 10);
   // Break-even
   startY += spacing + 5;
   ObjectCreate(0, beLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, beLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, beLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, beLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, beLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, beLabel, OBJPROP_TEXT, "Break-even:");
   ObjectSetInteger(0, beLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, beValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, beValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, beValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, beValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, beValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, beValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, beValue, OBJPROP_FONTSIZE, 10);
   // Status
   startY += spacing + 10;
   ObjectCreate(0, statusLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, statusLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, statusLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, statusLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, statusLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, statusLabel, OBJPROP_TEXT, "Status:");
   ObjectSetInteger(0, statusLabel, OBJPROP_FONTSIZE, 10);
   ObjectCreate(0, statusValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, statusValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, statusValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, statusValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, statusValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, statusValue, OBJPROP_TEXT, "Running");
   ObjectSetInteger(0, statusValue, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Update information on chart                                      |
//+------------------------------------------------------------------+
void UpdateChartInfo()
{
   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   ObjectSetString(0, capitalValue, OBJPROP_TEXT, DoubleToString(capital, 2));
   ObjectSetString(0, marginValue, OBJPROP_TEXT, DoubleToString(margin, 2));
   
   int totalTrades = CountOpenTrades();
   if(totalTrades > 0 && totalTrades <= profitTargetsArray.Total())
   {
      int currentTarget = profitTargetsArray.At(totalTrades - 1);
      ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, IntegerToString(currentTarget) + " pips");
   }
   else
      ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, "N/A");
   
   if(totalTrades == 0)
   {
      ObjectSetString(0, tpValue, OBJPROP_TEXT, "N/A");
      ObjectSetString(0, beValue, OBJPROP_TEXT, "N/A");
      return;
   }
   
   bool hasTP = false;
   double tpPrice = 0;
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      double tp = PositionGetDouble(POSITION_TP);
      if(tp != 0) { hasTP = true; tpPrice = tp; break; }
   }
   if(hasTP)
      ObjectSetString(0, tpValue, OBJPROP_TEXT, DoubleToString(tpPrice, _Digits));
   else
      ObjectSetString(0, tpValue, OBJPROP_TEXT, "No TP set");
   
   double totalLots = 0, weightedPrice = 0;
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      totalLots += lot;
      weightedPrice += lot * price;
   }
   if(totalLots > 0)
   {
      double breakEvenPrice = weightedPrice / totalLots;
      ObjectSetString(0, beValue, OBJPROP_TEXT, DoubleToString(breakEvenPrice, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Account and expiry checks
   if(!IsAccountAllowed())
   {
      if(strategyEnabled)
      {
         strategyEnabled = false;
         CloseAllTrades();
         UpdateStatusLabel("Wrong Account");
      }
      return;
   }
   
   datetime now = TimeCurrent();
   if(now >= EXPIRY_DATE)
   {
      if(strategyEnabled)
      {
         CloseAllTrades();
         strategyEnabled = false;
         UpdateStatusLabel("Expired. Contact Developer for Renewal");
      }
      return;
   }
   
   if(!strategyEnabled) return;
   
   // Update highest equity for equity stop
   UpdateHighestEquity();
   
   // Equity stop check
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
         UpdateStatusLabel("Drawdown - Reset");
      }
      else
      {
         strategyEnabled = false;
         UpdateStatusLabel("Stopped (Drawdown)");
         return;
      }
   }
   
   if(equityStopTriggered && RestartAfterDrawdown)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double recoveryLevel = highestEquity * (1 - MaxEquityDrawdownPercent/200);
      if(currentEquity >= recoveryLevel)
      {
         equityStopTriggered = false;
         UpdateStatusLabel("Running");
      }
      else return;
   }
   
   // ATR stop logic
   if(UseATRStop && atrHandle != INVALID_HANDLE)
   {
      double atr[1];
      if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1)
      {
         if(atr[0] > ATRHighThreshold && !atrStopTriggered)
         {
            atrStopTriggered = true;
            if(CloseOnHighATR)
               CloseAllTrades();
            UpdateStatusLabel("High ATR - Stopped");
         }
         else if(atr[0] <= ATRHighThreshold && atrStopTriggered)
         {
            atrStopTriggered = false;
            UpdateStatusLabel("Running");
         }
      }
   }
   
   if(atrStopTriggered)
   {
      UpdateChartInfo();
      if(UseATRIndicator && atrHandle != INVALID_HANDLE)
      {
         double atr[1];
         if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1)
            ObjectSetString(0, atrValue, OBJPROP_TEXT, DoubleToString(atr[0], _Digits));
      }
      return;
   }
   
   // --- Normal trading logic ---
   int totalTrades = CountOpenTrades();
   if(totalTrades == 0)
   {
      int rsiDirection = 0;
      bool rsiConditionMet = false;
      
      if(UseRSIFilter)
      {
         rsiConditionMet = CheckRSIFilter(rsiDirection);
         if(!rsiConditionMet) return;
      }
      
      if(!UseRSIFilter)
      {
         int emaDirection = 0;
         if(UseEMAFilter && !CheckEMAFilter(emaDirection)) return;
         if(!CheckConsecutiveCandles(direction)) return;
         if(UseEMAFilter && direction != emaDirection) return;
      }
      else
         direction = rsiDirection;
      
      initialTradeOpened = true;
      initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      
      // Calculate SL price for the first position
      double slPrice = 0;
      if(InitialSLPips > 0)
      {
         if(direction == 1)
            slPrice = initialEntryPrice - InitialSLPips * PIP * _Point;
         else
            slPrice = initialEntryPrice + InitialSLPips * PIP * _Point;
      }
      
      // Open first position with SL only (NO TP)
      trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                        InitialLotSize, initialEntryPrice, slPrice, 0);
   }
   else if(totalTrades <= triggerPips.Total())
   {
      ManagePyramiding();  // Add positions only in favorable direction
   }
   
   // Profit target check (close all when total profit reaches target)
   if(totalTrades > 0 && totalTrades <= profitTargetsArray.Total())
   {
      double currentTargetPips = profitTargetsArray.At(totalTrades - 1);
      double totalProfit = GetTotalUnrealizedProfit(); 
      if(totalProfit >= currentTargetPips * PIP * _Point)
      {
         CloseAllTrades();
         initialTradeOpened = false;
         initialEntryPrice = 0;
      }
   }
   
   // Update visual elements
   UpdateProfitTargetLine(totalTrades);
   UpdateChartInfo();
   
   if(UseATRIndicator && atrHandle != INVALID_HANDLE)
   {
      double atr[1];
      if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1)
         ObjectSetString(0, atrValue, OBJPROP_TEXT, DoubleToString(atr[0], _Digits));
   }
}

//+------------------------------------------------------------------+
//| Update status label                                              |
//+------------------------------------------------------------------+
void UpdateStatusLabel(string text)
{
   if(ObjectFind(0, statusValue) < 0) return;
   ObjectSetString(0, statusValue, OBJPROP_TEXT, text);
   color clr = clrYellow;
   if(StringFind(text, "Running") >= 0) clr = clrLime;
   else if(StringFind(text, "Drawdown") >= 0) clr = clrOrangeRed;
   else if(StringFind(text, "High ATR") >= 0) clr = clrOrange;
   else if(StringFind(text, "Stopped") >= 0) clr = clrRed;
   ObjectSetInteger(0, statusValue, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Check equity drawdown                                            |
//+------------------------------------------------------------------+
bool CheckEquityStop()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPercent = 0;
   if(highestEquity > 0)
      drawdownPercent = ((highestEquity - currentEquity) / highestEquity) * 100;
   return drawdownPercent >= MaxEquityDrawdownPercent;
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
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber) count++;
   }
   return count;
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
      if(CopyOpen(_Symbol, _Period, i, 1, openArray) != 1 ||
         CopyClose(_Symbol, _Period, i, 1, closeArray) != 1)
         return false;
      if(closeArray[0] <= openArray[0]) bullish = false;
      if(closeArray[0] >= openArray[0]) bearish = false;
   }
   if(bullish) { dir = 1; return true; }
   if(bearish) { dir = -1; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Manage pyramiding (add positions only in favorable direction)   |
//+------------------------------------------------------------------+
void ManagePyramiding()
{
   if(initialEntryPrice == 0) return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_BID : SYMBOL_ASK);
   int openCount = CountOpenTrades();
   if(openCount > triggerPips.Total()) return;
   
   // Calculate trigger price in the favorable direction
   double triggerPrice = CalculatePyramidTriggerPrice(openCount);
   if(triggerPrice == 0) return;
   
   bool conditionMet = false;
   if(direction == 1 && currentPrice >= triggerPrice)   // Buy: add when price rises
      conditionMet = true;
   else if(direction == -1 && currentPrice <= triggerPrice) // Sell: add when price falls
      conditionMet = true;
   
   if(conditionMet)
   {
      double lot = GetLotSize(openCount);
      double entryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      
      bool isLastPosition = (openCount == triggerPips.Total());
      
      if(isLastPosition && LastPositionSLPips > 0)
      {
         // Last position gets its own SL
         double slPrice = entryPrice + (direction == 1 ? -LastPositionSLPips : LastPositionSLPips) * PIP * _Point;
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, slPrice, 0);
      }
      else
      {
         // Intermediate positions: no SL initially
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, 0, 0);
      }
      
      // If breakeven stop is enabled and this is the first hedge (now total positions = openCount+1 after open)
      if(UseBreakevenStop && openCount == 1)  // first hedge added => now 2 positions total
      {
         SetBreakevenStop();
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate trigger price for pyramiding (favorable direction)    |
//+------------------------------------------------------------------+
double CalculatePyramidTriggerPrice(int positionCount)
{
   if(positionCount == 0 || positionCount > triggerPips.Total()) 
      return 0;
   
   // Cumulative pips from initial entry for this level
   int totalPips = 0;
   for(int i = 0; i < positionCount; i++)
      totalPips += triggerPips.At(i);
   
   if(direction == 1)
      // For buy, trigger is above entry (price rising)
      return initialEntryPrice + totalPips * PIP * _Point;
   else
      // For sell, trigger is below entry (price falling)
      return initialEntryPrice - totalPips * PIP * _Point;
}

//+------------------------------------------------------------------+
//| Set all positions' stop loss to weighted average + buffer       |
//+------------------------------------------------------------------+
void SetBreakevenStop()
{
   double totalLots = 0;
   double weightedPrice = 0;
   int totalPos = 0;
   
   // Calculate weighted average entry price of all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double lot = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      totalLots += lot;
      weightedPrice += lot * price;
      totalPos++;
   }
   
   if(totalLots == 0) return;
   
   double avgPrice = weightedPrice / totalLots;
   
   // Determine stop price with buffer
   double stopPrice;
   if(direction == 1)
      stopPrice = avgPrice + BreakevenBufferPips * PIP * _Point; // buffer above avg (more conservative)
   else
      stopPrice = avgPrice - BreakevenBufferPips * PIP * _Point; // buffer below avg
   
   // Modify all positions to this stop loss
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      if(positionInfo.SelectByTicket(ticket))
      {
         // Keep original TP if any, only modify SL
         trade.PositionModify(ticket, stopPrice, positionInfo.TakeProfit());
      }
   }
   
   Print("Breakeven stop set at ", DoubleToString(stopPrice, _Digits), " (avg entry ", DoubleToString(avgPrice, _Digits), ")");
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

//+------------------------------------------------------------------+
//| Update highest equity                                            |
//+------------------------------------------------------------------+
void UpdateHighestEquity()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(currentEquity > highestEquity) highestEquity = currentEquity;
}