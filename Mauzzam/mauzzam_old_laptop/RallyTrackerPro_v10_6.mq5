//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic Hedging Martingale with Recovery         |
//|                Custom Trigger Distances and Lot Sizes Version    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// Original inputs
input bool     EnableStrategy      = true;        // Initial enable state
input bool     EnableEquityStop    = false;       // Enable/disable equity stop protection
input double   MaxEquityDrawdownPercent = 20.0;   // Max allowed equity drawdown percentage (if enabled)
input bool     RestartAfterDrawdown = true;       // Restart strategy after drawdown (if false, stops completely)
input int      ConsecutiveCandles  = 2;
input double   InitialLotSize      = 0.01;
input string   CustomLots          = "0.01,0.02,0.03"; // Comma-separated lot sizes for hedge positions
input int      InitialTPPips       = 100;        // Take-profit in pips
input string   TriggerPipsArray    = "700,1400,2100"; // Comma-separated trigger distances
input int      ProfitTargetPips    = 1000;       // Total profit target in pips
input int      MagicNumber         = 123456;
input bool     UseEMAFilter        = true;       // Enable/disable 200 EMA filter
input int      EMA_Period          = 200;        // EMA period for trend filter
input int      LastPositionSLPips  = 200;        // Stop-loss in pips for the last hedge position

// RSI Filter Inputs
input bool     UseRSIFilter        = false;      // Enable/disable RSI filter
input int      RSI_Period          = 14;         // RSI period
input int      RSI_Applied_Price   = 0;          // RSI applied price (0=Close, 1=Open, 2=High, 3=Low, 4=Median, 5=Typical, 6=Weighted)
input double   RSI_UpperLevel      = 70.0;       // RSI upper level
input double   RSI_LowerLevel      = 30.0;       // RSI lower level
input bool     CloseTradesOnRSI    = true;       // Close open trades when RSI condition not met

// Recovery Strategy Inputs
input bool     EnableRecovery      = true;       // Enable recovery strategy
input double   RecoveryTriggerPercent = 10.0;    // Drawdown % to trigger recovery mode
input double   RecoveryLotMultiplier = 0.3;      // Lot size multiplier for recovery trades
input int      RecoveryGridPips    = 50;         // Grid distance for recovery trades
input int      RecoveryTakeProfitPips = 20;      // Take profit for recovery trades

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayDouble.mqh>
CTrade trade;
CPositionInfo positionInfo;
CArrayInt triggerPips; // Array to store trigger pip values
CArrayDouble customLotsArray; // Array to store custom lot sizes

// Global variables
bool strategyEnabled; // Track current strategy state (can be modified)
int direction = 0; // 1 for Buy, -1 for Sell
bool initialTradeOpened = false;
bool equityStopTriggered = false;
datetime lastHedgeTime = 0;
double highestEquity = 0;
double initialEntryPrice = 0;
int emaHandle = INVALID_HANDLE; // Handle for EMA indicator
int rsiHandle = INVALID_HANDLE; // Handle for RSI indicator

// Recovery mode variables
bool recoveryModeActive = false;
double recoveryHighestPrice = 0;
double recoveryLowestPrice = 0;
datetime lastRecoveryTradeTime = 0;
int recoveryTradeCount = 0;

#define PIP 10

// Objects for displaying information on chart
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
string rsiLabel = "RSILabel";
string rsiValue = "RSIValue";
string recoveryLabel = "RecoveryLabel";
string recoveryValue = "RecoveryValue";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   strategyEnabled = EnableStrategy; // Initialize with input value
   // Parse the TriggerPipsArray string into the triggerPips array
   if(!ParseTriggerPipsArray())
   {
      Print("Error parsing TriggerPipsArray! Using default values");
      return INIT_FAILED;
   }
   
   // Parse the CustomLots string into the customLotsArray
   if(!ParseCustomLotsArray())
   {
      Print("Error parsing CustomLots! Using default values");
      return INIT_FAILED;
   }
   
   // Verify that both arrays have the same size
   if(triggerPips.Total() != customLotsArray.Total())
   {
      Print("Error: TriggerPipsArray and CustomLots must have the same number of elements!");
      return INIT_FAILED;
   }
   
   // Create EMA indicator handle if filter is enabled
   if(UseEMAFilter)
   {
      emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE)
      {
         Print("Failed to create EMA indicator!");
         return(INIT_FAILED);
      }
   }
   
   // Create RSI indicator handle if filter is enabled
   if(UseRSIFilter)
   {
      rsiHandle = iRSI(_Symbol, _Period, RSI_Period, RSI_Applied_Price);
      if(rsiHandle == INVALID_HANDLE)
      {
         Print("Failed to create RSI indicator!");
         return(INIT_FAILED);
      }
   }
   
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityStopTriggered = false; // Reset on init
   recoveryModeActive = false; // Reset recovery mode
   
   // Create chart objects for display
   CreateInfoLabels();
   
   // Print the configured lot sizes
   PrintConfiguredLotSizes();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Parse the TriggerPipsArray string into an array                  |
//+------------------------------------------------------------------+
bool ParseTriggerPipsArray()
{
   string values[];
   int count = StringSplit(TriggerPipsArray, ',', values);
   
   if(count <= 0)
   {
      Print("No values found in TriggerPipsArray!");
      return false;
   }
   
   // Clear and initialize the array
   triggerPips.Clear();
   
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp);
      StringTrimRight(temp);
      int pipValue = (int)StringToInteger(temp);
      if(pipValue <= 0)
      {
         Print("Invalid pip value in TriggerPipsArray: ", temp);
      }
      triggerPips.Add(pipValue);
   }
   
   Print("Successfully parsed ", triggerPips.Total(), " trigger pip values");
   return true;
}

//+------------------------------------------------------------------+
//| Parse the CustomLots string into an array                        |
//+------------------------------------------------------------------+
bool ParseCustomLotsArray()
{
   string values[];
   int count = StringSplit(CustomLots, ',', values);
   
   if(count <= 0)
   {
      Print("No values found in CustomLots!");
      return false;
   }
   
   // Clear and initialize the array
   customLotsArray.Clear();
   
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp);
      StringTrimRight(temp);
      double lotValue = StringToDouble(temp);
      if(lotValue <= 0)
      {
         Print("Invalid lot value in CustomLots: ", temp);
      }
      customLotsArray.Add(lotValue);
   }
   
   Print("Successfully parsed ", customLotsArray.Total(), " custom lot values");
   return true;
}

//+------------------------------------------------------------------+
//| Get current EMA value                                            |
//+------------------------------------------------------------------+
double GetEMAValue()
{
   if(emaHandle == INVALID_HANDLE) return 0;
   
   double emaValue[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, emaValue) != 1)
   {
      Print("Failed to copy EMA buffer!");
      return 0;
   }
   
   return emaValue[0];
}

//+------------------------------------------------------------------+
//| Get current RSI value                                            |
//+------------------------------------------------------------------+
double GetRSIValue()
{
   if(rsiHandle == INVALID_HANDLE) return 0;
   
   double rsiValue[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsiValue) != 1)
   {
      Print("Failed to copy RSI buffer!");
      return 0;
   }
   
   return rsiValue[0];
}
//+------------------------------------------------------------------+
//| Check RSI filter condition                                       |
//+------------------------------------------------------------------+
bool CheckRSIFilter()
{
   if(!UseRSIFilter) return true; // If filter disabled, always return true
   
   double rsiValue = GetRSIValue();
   if(rsiValue == 0) return false; // Failed to get RSI value
   
   // Check if RSI is between the specified levels
   if(rsiValue >= RSI_LowerLevel && rsiValue <= RSI_UpperLevel){
      return true;
   }else{
      return false;
   }
}

//+------------------------------------------------------------------+
//| Print the configured lot sizes                                   |
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
   Print("Last position will have SL of ", LastPositionSLPips, " pips");
}

//+------------------------------------------------------------------+
//| Get lot size for the specified position index                    |
//+------------------------------------------------------------------+
double GetLotSize(int positionIndex)
{
   if(positionIndex == 0) return InitialLotSize;
   
   // For hedge positions (index > 0), use the custom lots array
   int hedgeIndex = positionIndex - 1; // First hedge is at index 1, which corresponds to array index 0
   
   if(hedgeIndex < customLotsArray.Total())
   {
      return NormalizeDouble(customLotsArray.At(hedgeIndex), 2);
   }
   
   // If we somehow get here, return the last custom lot size
   return NormalizeDouble(customLotsArray.At(customLotsArray.Total()-1), 2);
}

//+------------------------------------------------------------------+
//| Check EMA filter condition                                       |
//+------------------------------------------------------------------+
bool CheckEMAFilter(int &dir)
{
   if(!UseEMAFilter) return true; // If filter disabled, always return true
   
   double emaValue = GetEMAValue();
   if(emaValue == 0) return false; // Failed to get EMA value
   
   double currentClose = iClose(_Symbol, _Period, 1);
   
   if(currentClose > emaValue)
   {
      dir = 1; // Only allow buy trades
      return true;
   }
   else if(currentClose < emaValue)
   {
      dir = -1; // Only allow sell trades
      return true;
   }
   
   return false; // Price exactly at EMA - no trades
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(emaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(emaHandle);
   }
   
   if(rsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(rsiHandle);
   }
   
   // Remove chart objects when EA is removed
   ObjectDelete(0, capitalLabel);
   ObjectDelete(0, capitalValue);
   ObjectDelete(0, marginLabel);
   ObjectDelete(0, marginValue);
   ObjectDelete(0, tpLabel);
   ObjectDelete(0, tpValue);
   ObjectDelete(0, profitTargetLabel);
   ObjectDelete(0, profitTargetValue);
   ObjectDelete(0, beLabel);
   ObjectDelete(0, beValue);
   ObjectDelete(0, statusLabel);
   ObjectDelete(0, statusValue);
   ObjectDelete(0, rsiLabel);
   ObjectDelete(0, rsiValue);
   ObjectDelete(0, recoveryLabel);
   ObjectDelete(0, recoveryValue);
}

//+------------------------------------------------------------------+
//| Create information labels on chart                               |
//+------------------------------------------------------------------+
void CreateInfoLabels()
{
   int verticalSpacing = 25;
   int startY = 20;
   int labelX = 10;
   int valueX = 170;
   
   // RSI label
   ObjectCreate(0, rsiLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, rsiLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, rsiLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, rsiLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, rsiLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, rsiLabel, OBJPROP_TEXT, "RSI Status:");
   ObjectSetInteger(0, rsiLabel, OBJPROP_FONTSIZE, 10);
   
   // RSI value
   ObjectCreate(0, rsiValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, rsiValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, rsiValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, rsiValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, rsiValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, rsiValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, rsiValue, OBJPROP_FONTSIZE, 10);
   
   // Capital label
   startY += verticalSpacing;
   ObjectCreate(0, capitalLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, capitalLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, capitalLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, capitalLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, capitalLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, capitalLabel, OBJPROP_TEXT, "Capital:");
   ObjectSetInteger(0, capitalLabel, OBJPROP_FONTSIZE, 10);
   
   // Capital value
   ObjectCreate(0, capitalValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, capitalValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, capitalValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, capitalValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, capitalValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, capitalValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, capitalValue, OBJPROP_FONTSIZE, 10);
   
   // Margin label
   startY += verticalSpacing;
   ObjectCreate(0, marginLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, marginLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, marginLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, marginLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, marginLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, marginLabel, OBJPROP_TEXT, "Margin Used:");
   ObjectSetInteger(0, marginLabel, OBJPROP_FONTSIZE, 10);
   
   // Margin value
   ObjectCreate(0, marginValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, marginValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, marginValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, marginValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, marginValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, marginValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, marginValue, OBJPROP_FONTSIZE, 10);
   
   // TP price label
   startY += verticalSpacing;
   ObjectCreate(0, tpLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tpLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tpLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, tpLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, tpLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, tpLabel, OBJPROP_TEXT, "TP Price:");
   ObjectSetInteger(0, tpLabel, OBJPROP_FONTSIZE, 10);
   
   // TP price value
   ObjectCreate(0, tpValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, tpValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, tpValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, tpValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, tpValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, tpValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, tpValue, OBJPROP_FONTSIZE, 10);
   
   // Profit target label
   startY += verticalSpacing;
   ObjectCreate(0, profitTargetLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, profitTargetLabel, OBJPROP_TEXT, "Profit Target:");
   ObjectSetInteger(0, profitTargetLabel, OBJPROP_FONTSIZE, 10);
   
   // Profit target value
   ObjectCreate(0, profitTargetValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, profitTargetValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, profitTargetValue, OBJPROP_FONTSIZE, 10);
   
   // Break-even label
   startY += verticalSpacing;
   ObjectCreate(0, beLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, beLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, beLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, beLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, beLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, beLabel, OBJPROP_TEXT, "Break-even:");
   ObjectSetInteger(0, beLabel, OBJPROP_FONTSIZE, 10);
   
   // Break-even value
   ObjectCreate(0, beValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, beValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, beValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, beValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, beValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, beValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, beValue, OBJPROP_FONTSIZE, 10);
   
   // Recovery status label
   startY += verticalSpacing;
   ObjectCreate(0, recoveryLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, recoveryLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, recoveryLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, recoveryLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, recoveryLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, recoveryLabel, OBJPROP_TEXT, "Recovery:");
   ObjectSetInteger(0, recoveryLabel, OBJPROP_FONTSIZE, 10);
   
   // Recovery status value
   ObjectCreate(0, recoveryValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, recoveryValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, recoveryValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, recoveryValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, recoveryValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, recoveryValue, OBJPROP_TEXT, "Inactive");
   ObjectSetInteger(0, recoveryValue, OBJPROP_FONTSIZE, 10);
   
   // Status label
   startY += verticalSpacing;
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
   // Update RSI information
   if(UseRSIFilter)
   {
      double rsiVal = GetRSIValue();
      string rsiStatus = "N/A";
      color rsiColor = clrYellow;
      
      if(rsiVal > 0)
      {
         if(rsiVal >= RSI_LowerLevel && rsiVal <= RSI_UpperLevel)
         {
            rsiStatus = "In Range (" + DoubleToString(rsiVal, 1) + ")";
            rsiColor = clrLime;
         }
         else if(rsiVal < RSI_LowerLevel)
         {
            rsiStatus = "Below Range (" + DoubleToString(rsiVal, 1) + ")";
            rsiColor = clrRed;
         }
         else if(rsiVal > RSI_UpperLevel)
         {
            rsiStatus = "Above Range (" + DoubleToString(rsiVal, 1) + ")";
            rsiColor = clrRed;
         }
      }
      else
      {
         rsiStatus = "Error reading RSI";
         rsiColor = clrRed;
      }
      
      ObjectSetString(0, rsiValue, OBJPROP_TEXT, rsiStatus);
      ObjectSetInteger(0, rsiValue, OBJPROP_COLOR, rsiColor);
   }
   else
   {
      ObjectSetString(0, rsiValue, OBJPROP_TEXT, "Disabled");
      ObjectSetInteger(0, rsiValue, OBJPROP_COLOR, clrGray);
   }
   
   // Update capital and margin information
   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   ObjectSetString(0, capitalValue, OBJPROP_TEXT, DoubleToString(capital, 2));
   ObjectSetString(0, marginValue, OBJPROP_TEXT, DoubleToString(margin, 2));
   
   // Update profit target
   ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, DoubleToString(ProfitTargetPips, 0) + " pips");
   
   // Update recovery status
   if(recoveryModeActive)
   {
      ObjectSetString(0, recoveryValue, OBJPROP_TEXT, "Active (" + IntegerToString(recoveryTradeCount) + ")");
      ObjectSetInteger(0, recoveryValue, OBJPROP_COLOR, clrOrange);
   }
   else
   {
      ObjectSetString(0, recoveryValue, OBJPROP_TEXT, "Inactive");
      ObjectSetInteger(0, recoveryValue, OBJPROP_COLOR, clrGray);
   }
   
   int totalPositions = CountOpenTrades();
   
   if(totalPositions == 0)
   {
      ObjectSetString(0, tpValue, OBJPROP_TEXT, "N/A");
      ObjectSetString(0, beValue, OBJPROP_TEXT, "N/A");
      return;
   }
   
   // Check if initial position still has TP
   bool hasTP = false;
   double tpPrice = 0;
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double tp = PositionGetDouble(POSITION_TP);
      if(tp != 0)
      {
         hasTP = true;
         tpPrice = tp;
         break;
      }
   }
   
   if(hasTP)
   {
      ObjectSetString(0, tpValue, OBJPROP_TEXT, DoubleToString(tpPrice, _Digits));
   }
   else
   {
      ObjectSetString(0, tpValue, OBJPROP_TEXT, "No TP set");
   }
   
   // Calculate break-even price
   double totalLots = 0;
   double weightedPrice = 0;
   
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
   if(!strategyEnabled) return; // Use the modifiable variable

   UpdateHighestEquity();
   
   // Check RSI filter if enabled
   if(UseRSIFilter && !CheckRSIFilter())
   {
      // RSI condition not met
      if(CloseTradesOnRSI && CountOpenTrades() > 0)
      {
         // Close all open trades if option is enabled
         CloseAllTrades();
         initialTradeOpened = false;
         initialEntryPrice = 0;
         direction = 0;
         recoveryModeActive = false;
         Print("RSI condition not met - all positions closed");
         UpdateStatusLabel("RSI Condition Failed");
      }
      return; // Don't proceed with trading logic
   }
   
   // Check equity stop if enabled and not already triggered
   if(EnableEquityStop && !equityStopTriggered && CheckEquityStop())
   {
      equityStopTriggered = true;
      CloseAllTrades();
      recoveryModeActive = false;
      
      if(RestartAfterDrawdown)
      {
         // Reset strategy state but keep monitoring equity
         initialTradeOpened = false;
         initialEntryPrice = 0;
         direction = 0;
         highestEquity = AccountInfoDouble(ACCOUNT_EQUITY); // Reset highest equity
         Alert("Drawdown limit hit! Strategy reset and waiting for new signal.");
         UpdateStatusLabel("Drawdown - Reset");
      }
      else
      {
         // Completely stop the strategy
         strategyEnabled = false; // This is now allowed
         Alert("Drawdown limit hit! Strategy stopped completely.");
         UpdateStatusLabel("Stopped (Drawdown)");
         return;
      }
   }
   
   // If equity stop was triggered but we're restarting, check if we can resume
   if(equityStopTriggered && RestartAfterDrawdown)
   {
      // Check if equity has recovered enough (optional - you can remove this if you want immediate restart)
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double recoveryLevel = highestEquity * (1 - MaxEquityDrawdownPercent/200); // Allow half the drawdown for recovery
      
      if(currentEquity >= recoveryLevel)
      {
         equityStopTriggered = false;
         Alert("Equity recovered - strategy resuming");
         UpdateStatusLabel("Running");
      }
      else
      {
         return; // Wait for recovery
      }
   }
   
   // Check if we should activate recovery mode
   if(EnableRecovery && !recoveryModeActive && ShouldActivateRecovery())
   {
      ActivateRecoveryMode();
      return;
   }
   
   // Handle recovery mode if active
   if(recoveryModeActive)
   {
      HandleRecoveryMode();
      return;
   }
   
   // Normal trading logic
   int totalTrades = CountOpenTrades();
   if(totalTrades == 0)
   {
      // First check EMA filter if enabled
      int emaDirection = 0;
      if(UseEMAFilter && !CheckEMAFilter(emaDirection))
      {
         return; // EMA filter condition not met
      }
      
      // Then check consecutive candles
      if(CheckConsecutiveCandles(direction))
      {
         // If EMA filter is enabled, verify direction matches EMA
         if(UseEMAFilter && direction != emaDirection)
         {
            return; // Direction doesn't match EMA filter
         }
         
         initialTradeOpened = true;
         initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
         trade.SetExpertMagicNumber(MagicNumber);
         Print("First Trade at price: ", initialEntryPrice);
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           InitialLotSize, initialEntryPrice,
                           0,
                           initialEntryPrice + (direction == 1 ? InitialTPPips : -InitialTPPips) * PIP * _Point);
      }
   }
   else if(totalTrades <= triggerPips.Total()) // Changed to use triggerPips count
   {
      ManageHedging();
   }

   double totalProfit = GetTotalUnrealizedProfit();
   if(totalProfit >= ProfitTargetPips * PIP * _Point)
   {
      CloseAllTrades();
      initialTradeOpened = false;
      initialEntryPrice = 0;
      recoveryModeActive = false;
   }
   
   // Update chart information on every tick
   UpdateChartInfo();
}

//+------------------------------------------------------------------+
//| Check if recovery mode should be activated                       |
//+------------------------------------------------------------------+
bool ShouldActivateRecovery()
{
   int openTrades = CountOpenTrades();
   if(openTrades < 2) return false; // Need at least 2 trades for recovery
   
   double unrealizedLoss = GetTotalUnrealizedProfit();
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lossPercent = MathAbs(unrealizedLoss) / accountBalance * 100;
   
   // Also check if we have reached the maximum number of hedge positions
   bool maxHedgesReached = (openTrades >= triggerPips.Total());
   
   return (lossPercent >= RecoveryTriggerPercent) || maxHedgesReached;
}

//+------------------------------------------------------------------+
//| Activate recovery mode                                           |
//+------------------------------------------------------------------+
void ActivateRecoveryMode()
{
   Print("Activating Recovery Mode - Unwinding positions");
   recoveryModeActive = true;
   recoveryTradeCount = 0;
   
   // Calculate the price range of all open positions
   CalculateRecoveryRange();
   
   // Stop opening new martingale positions
   UpdateStatusLabel("Recovery Active");
}

//+------------------------------------------------------------------+
//| Calculate the highest and lowest prices of open positions        |
//+------------------------------------------------------------------+
void CalculateRecoveryRange()
{
   recoveryHighestPrice = 0;
   recoveryLowestPrice = 0;
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      
      if(recoveryHighestPrice == 0 || price > recoveryHighestPrice)
         recoveryHighestPrice = price;
         
      if(recoveryLowestPrice == 0 || price < recoveryLowestPrice)
         recoveryLowestPrice = price;
   }
   
   Print("Recovery Range: Low=", recoveryLowestPrice, " High=", recoveryHighestPrice);
}

//+------------------------------------------------------------------+
//| Handle recovery mode logic                                       |
//+------------------------------------------------------------------+
void HandleRecoveryMode()
{
   // Don't trade too frequently in recovery mode
   if(lastRecoveryTradeTime != 0 && (TimeCurrent() - lastRecoveryTradeTime) < 60)
      return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double recoveryLotSize = NormalizeDouble(InitialLotSize * RecoveryLotMultiplier, 2);
   
   // Calculate grid levels
   double gridStep = RecoveryGridPips * PIP * _Point;
   double upperGrid = recoveryHighestPrice - gridStep;
   double lowerGrid = recoveryLowestPrice + gridStep;
   
   // Check if price is within our recovery grid range
   if(currentPrice <= upperGrid && currentPrice >= lowerGrid)
   {
      // Determine if we should place a buy or sell order
      // Use a simple oscillator based on price position in the range
      double rangeMid = recoveryLowestPrice + (recoveryHighestPrice - recoveryLowestPrice) / 2;
      
      if(currentPrice < rangeMid)
      {
         // Price is in lower half of range - place a buy order
         double tpPrice = currentPrice + RecoveryTakeProfitPips * PIP * _Point;
         trade.Buy(recoveryLotSize, _Symbol, currentPrice, 0, tpPrice, "Recovery Buy");
         Print("Recovery BUY at ", currentPrice, " TP: ", tpPrice);
      }
      else
      {
         // Price is in upper half of range - place a sell order
         double tpPrice = currentPrice - RecoveryTakeProfitPips * PIP * _Point;
         trade.Sell(recoveryLotSize, _Symbol, currentPrice, 0, tpPrice, "Recovery Sell");
         Print("Recovery SELL at ", currentPrice, " TP: ", tpPrice);
      }
      
      recoveryTradeCount++;
      lastRecoveryTradeTime = TimeCurrent();
   }
   
   // Check if we've recovered enough to exit recovery mode
   if(GetTotalUnrealizedProfit() >= 0)
   {
      Print("Recovery complete - exiting recovery mode");
      recoveryModeActive = false;
      UpdateStatusLabel("Running");
      
      // Close all positions if we're at break-even or profit
      CloseAllTrades();
      initialTradeOpened = false;
      initialEntryPrice = 0;
   }
}

//+------------------------------------------------------------------+
//| Update status label on chart                                     |
//+------------------------------------------------------------------+
void UpdateStatusLabel(string text)
{
   if(ObjectFind(0, statusValue) < 0) return;
   ObjectSetString(0, statusValue, OBJPROP_TEXT, text);
   
   // Change color based on status
   color clr = clrYellow;
   if(StringFind(text, "Running") >= 0) clr = clrLime;
   else if(StringFind(text, "Drawdown") >= 0) clr = clrOrangeRed;
   else if(StringFind(text, "Stopped") >= 0) clr = clrRed;
   else if(StringFind(text, "RSI") >= 0) clr = clrOrange;
   else if(StringFind(text, "Recovery") >= 0) clr = clrOrange;
   
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
   {
      drawdownPercent = ((highestEquity - currentEquity) / highestEquity) * 100;
   }
   
   return drawdownPercent >= MaxEquityDrawdownPercent;
}

//+------------------------------------------------------------------+
//| Count open trades                                                |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if (PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check consecutive candles                                        |
//+------------------------------------------------------------------+
bool CheckConsecutiveCandles(int &dir)
{
   bool bullish = true;
   bool bearish = true;
   double openArray[1], closeArray[1];

   for (int i = 1; i <= ConsecutiveCandles; i++)
   {
      if (CopyOpen(_Symbol, _Period, i, 1, openArray) != 1 ||
          CopyClose(_Symbol, _Period, i, 1, closeArray) != 1)
         return false;

      if (closeArray[0] <= openArray[0]) bullish = false;
      if (closeArray[0] >= openArray[0]) bearish = false;
   }

   if (bullish) { dir = 1; return true; }
   if (bearish) { dir = -1; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Manage hedging with custom trigger distances                     |
//+------------------------------------------------------------------+
void ManageHedging()
{
   if(initialEntryPrice == 0) return;
    
   double currentPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_BID : SYMBOL_ASK);
   int openCount = CountOpenTrades();
   
   if(openCount > triggerPips.Total()) return; // Changed to use triggerPips count
   
   // Calculate trigger price based on the custom array
   double triggerPrice = CalculateHedgeTriggerPrice(openCount);
   if(triggerPrice == 0) return;
   
   bool conditionMet = false;
   if(direction == 1 && currentPrice <= triggerPrice)
   {
      conditionMet = true;
   }
   else if(direction == -1 && currentPrice >= triggerPrice)
   {
      conditionMet = true;
   }
   
   if(conditionMet)
   {
      double lot = GetLotSize(openCount);
      double entryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      
      // Check if this is the last position
      bool isLastPosition = (openCount == triggerPips.Total()); // Changed to use triggerPips count
      
      if(isLastPosition && LastPositionSLPips > 0)
      {
         // For last position, set SL
         double slPrice = entryPrice + (direction == 1 ? -LastPositionSLPips : LastPositionSLPips) * PIP * _Point;
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, slPrice, 0);
         Print("Last hedge position #", openCount, " opened with SL at ", slPrice);
      }
      else
      {
         // For other positions, no SL
         trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, 0, 0);
      }
      
      Print("Hedge #", openCount, " opened at ", entryPrice, 
            " (Trigger: ", triggerPrice, 
            " Pips from initial: ", GetTotalTriggerPips(openCount), ")");
      
      if(openCount == 1)
      {
         RemoveInitialPositionTP();
      }
   }
}

//+------------------------------------------------------------------+
//| Remove TP from initial position                                  |
//+------------------------------------------------------------------+
void RemoveInitialPositionTP()
{
   ulong initialTicket = 0;
   datetime earliestTime = D'3000.01.01';
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      datetime posTime = PositionGetInteger(POSITION_TIME);
      if(posTime < earliestTime)
      {
         earliestTime = posTime;
         initialTicket = ticket;
      }
   }
   
   if(initialTicket == 0) return;
   
   if(positionInfo.SelectByTicket(initialTicket))
   {
      trade.PositionModify(initialTicket, positionInfo.StopLoss(), 0);
      Print("Removed TP from initial position #", initialTicket);
   }
}

//+------------------------------------------------------------------+
//| Get total unrealized profit                                      |
//+------------------------------------------------------------------+
double GetTotalUnrealizedProfit()
{
   double profit = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if (PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Close all trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if (PositionGetInteger(POSITION_MAGIC) == MagicNumber)
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
   if(currentEquity > highestEquity)
   {
      highestEquity = currentEquity;
   }
}

//+------------------------------------------------------------------+
//| Calculate hedge trigger price based on position count            |
//+------------------------------------------------------------------+
double CalculateHedgeTriggerPrice(int positionCount)
{
   if(positionCount == 0 || positionCount > triggerPips.Total()) 
      return 0; // No trigger price for initial position or if beyond our array
   
   // Calculate cumulative pips from initial entry for this hedge level
   int totalPips = 0;
   for(int i = 0; i < positionCount; i++)
   {
      totalPips += triggerPips.At(i);
   }
   
   if(direction == 1)
   {
      // For buy direction, hedges go down in price
      return initialEntryPrice - totalPips * PIP * _Point;
   }
   else
   {
      // For sell direction, hedges go up in price
      return initialEntryPrice + totalPips * PIP * _Point;
   }
}

//+------------------------------------------------------------------+
//| Get total trigger pips for a given position count                |
//+------------------------------------------------------------------+
int GetTotalTriggerPips(int positionCount)
{
   int total = 0;
   for(int i = 0; i < positionCount && i < triggerPips.Total(); i++)
   {
      total += triggerPips.At(i);
   }
   return total;
}