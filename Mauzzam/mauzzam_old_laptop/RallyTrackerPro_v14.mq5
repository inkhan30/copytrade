//+------------------------------------------------------------------+
//| Expert Advisor: Bidirectional Dynamic Hedging                    |
//|                Custom Trigger Distances and Lot Sizes Version    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

input bool     EnableStrategy      = true;        // Initial enable state
input bool     EnableEquityStop    = false;       // Enable/disable equity stop protection
input double   MaxEquityDrawdownPercent = 20.0;   // Max allowed equity drawdown percentage (if enabled)
input bool     RestartAfterDrawdown = true;       // Restart strategy after drawdown (if false, stops completely)
input double   InitialLotSize      = 0.01;
input string   CustomLots          = "0.01,0.02,0.03"; // Comma-separated lot sizes for hedge positions
input int      InitialTPPips       = 0;           // Take-profit in pips (0 for no TP)
input string   TriggerPipsArray    = "700,1400,2100"; // Comma-separated trigger distances
input int      ProfitTargetPips    = 1000;       // Total profit target in pips
input int      MagicNumber         = 123456;
input int      EMA_Period          = 200;        // EMA period for trend filter
input int      LastPositionSLPips  = 200;        // Stop-loss in pips for the last hedge position

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
bool equityStopTriggered = false;
datetime lastHedgeTime = 0;
double highestEquity = 0;
int emaHandle = INVALID_HANDLE; // Handle for EMA indicator

// Track long and short positions separately
struct PositionGroup {
   double entryPrice;
   int positionCount;
   int direction; // 1 for long, -1 for short
};
PositionGroup longGroup = {0, 0, 1};
PositionGroup shortGroup = {0, 0, -1};

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
   
   // Create EMA indicator handle
   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator!");
      return(INIT_FAILED);
   }
   
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityStopTriggered = false; // Reset on init
   
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
         return false;
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
         return false;
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
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release EMA indicator handle
   if(emaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(emaHandle);
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
   
   // Capital label
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
   startY += verticalSpacing + 5;
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
   startY += verticalSpacing + 5;
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
   startY += verticalSpacing + 5;
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
   
   // Status label
   startY += verticalSpacing + 10;
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
   // Update capital and margin information
   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   ObjectSetString(0, capitalValue, OBJPROP_TEXT, DoubleToString(capital, 2));
   ObjectSetString(0, marginValue, OBJPROP_TEXT, DoubleToString(margin, 2));
   
   // Update profit target
   ObjectSetString(0, profitTargetValue, OBJPROP_TEXT, DoubleToString(ProfitTargetPips, 0) + " pips");
   
   int totalPositions = CountOpenTrades();
   
   if(totalPositions == 0)
   {
      ObjectSetString(0, tpValue, OBJPROP_TEXT, "N/A");
      ObjectSetString(0, beValue, OBJPROP_TEXT, "N/A");
      return;
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
   
   ObjectSetString(0, tpValue, OBJPROP_TEXT, "Bidirectional");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!strategyEnabled) return;

   UpdateHighestEquity();
   
   // Check equity stop if enabled and not already triggered
   if(EnableEquityStop && !equityStopTriggered && CheckEquityStop())
   {
      equityStopTriggered = true;
      CloseAllTrades();
      
      if(RestartAfterDrawdown)
      {
         // Reset strategy state but keep monitoring equity
         longGroup.positionCount = 0;
         longGroup.entryPrice = 0;
         shortGroup.positionCount = 0;
         shortGroup.entryPrice = 0;
         highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         Alert("Drawdown limit hit! Strategy reset and waiting for new signal.");
         UpdateStatusLabel("Drawdown - Reset");
      }
      else
      {
         // Completely stop the strategy
         strategyEnabled = false;
         Alert("Drawdown limit hit! Strategy stopped completely.");
         UpdateStatusLabel("Stopped (Drawdown)");
         return;
      }
   }
   
   // If equity stop was triggered but we're restarting, check if we can resume
   if(equityStopTriggered && RestartAfterDrawdown)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      double recoveryLevel = highestEquity * (1 - MaxEquityDrawdownPercent/200);
      
      if(currentEquity >= recoveryLevel)
      {
         equityStopTriggered = false;
         Alert("Equity recovered - strategy resuming");
         UpdateStatusLabel("Running");
      }
      else
      {
         return;
      }
   }
   
   // Get current EMA and price values
   double emaValue = GetEMAValue();
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Check if we should open initial long positions
   if(currentPrice > emaValue && longGroup.positionCount == 0)
   {
      OpenInitialPosition(1); // Open long position
   }
   
   // Check if we should open initial short positions
   if(currentPrice < emaValue && shortGroup.positionCount == 0)
   {
      OpenInitialPosition(-1); // Open short position
   }
   
   // Manage hedging for both directions
   if(longGroup.positionCount > 0)
   {
      ManageHedging(longGroup);
   }
   
   if(shortGroup.positionCount > 0)
   {
      ManageHedging(shortGroup);
   }

   // Check profit target
   double totalProfit = GetTotalUnrealizedProfit();
   if(totalProfit >= ProfitTargetPips * PIP * _Point)
   {
      CloseAllTrades();
      longGroup.positionCount = 0;
      longGroup.entryPrice = 0;
      shortGroup.positionCount = 0;
      shortGroup.entryPrice = 0;
   }
   
   UpdateChartInfo();
}

//+------------------------------------------------------------------+
//| Open initial position in specified direction                     |
//+------------------------------------------------------------------+
void OpenInitialPosition(int dir)
{
   double entryPrice = SymbolInfoDouble(_Symbol, dir == 1 ? SYMBOL_ASK : SYMBOL_BID);
   double tpPrice = 0;
   
   if(InitialTPPips > 0)
   {
      tpPrice = entryPrice + (dir == 1 ? InitialTPPips : -InitialTPPips) * PIP * _Point;
   }
   
   trade.SetExpertMagicNumber(MagicNumber);
   bool result = trade.PositionOpen(_Symbol, dir == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                     InitialLotSize, entryPrice, 0, tpPrice);
   
   if(result)
   {
      if(dir == 1)
      {
         longGroup.entryPrice = entryPrice;
         longGroup.positionCount = 1;
         Print("Initial long position opened at ", entryPrice);
      }
      else
      {
         shortGroup.entryPrice = entryPrice;
         shortGroup.positionCount = 1;
         Print("Initial short position opened at ", entryPrice);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage hedging for a position group                              |
//+------------------------------------------------------------------+
void ManageHedging(PositionGroup &group)
{
   if(group.entryPrice == 0) return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, group.direction == 1 ? SYMBOL_BID : SYMBOL_ASK);
   
   if(group.positionCount > triggerPips.Total()) return;
   
   // Calculate trigger price based on the custom array
   double triggerPrice = CalculateHedgeTriggerPrice(group);
   if(triggerPrice == 0) return;
   
   bool conditionMet = false;
   if(group.direction == 1 && currentPrice <= triggerPrice)
   {
      conditionMet = true;
   }
   else if(group.direction == -1 && currentPrice >= triggerPrice)
   {
      conditionMet = true;
   }
   
   if(conditionMet)
   {
      double lot = GetLotSize(group.positionCount);
      double entryPrice = SymbolInfoDouble(_Symbol, group.direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
      trade.SetExpertMagicNumber(MagicNumber);
      
      // Check if this is the last position
      bool isLastPosition = (group.positionCount == triggerPips.Total());
      
      if(isLastPosition && LastPositionSLPips > 0)
      {
         // For last position, set SL
         double slPrice = entryPrice + (group.direction == 1 ? -LastPositionSLPips : LastPositionSLPips) * PIP * _Point;
         trade.PositionOpen(_Symbol, group.direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, slPrice, 0);
         Print("Last hedge position #", group.positionCount, " opened with SL at ", slPrice);
      }
      else
      {
         // For other positions, no SL
         trade.PositionOpen(_Symbol, group.direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           lot, entryPrice, 0, 0);
      }
      
      group.positionCount++;
      Print("Hedge #", group.positionCount, " opened at ", entryPrice, 
            " (Trigger: ", triggerPrice, 
            " Pips from initial: ", GetTotalTriggerPips(group.positionCount), ")");
      
      // Remove TP from initial position if this is first hedge
      if(group.positionCount == 2)
      {
         RemoveInitialPositionTP(group.direction);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate hedge trigger price for a position group               |
//+------------------------------------------------------------------+
double CalculateHedgeTriggerPrice(PositionGroup &group)
{
   if(group.positionCount == 0 || group.positionCount > triggerPips.Total()) 
      return 0;
   
   // Calculate cumulative pips from initial entry for this hedge level
   int totalPips = 0;
   for(int i = 0; i < group.positionCount; i++)
   {
      totalPips += triggerPips.At(i);
   }
   
   if(group.direction == 1)
   {
      // For buy direction, hedges go down in price
      return group.entryPrice - totalPips * PIP * _Point;
   }
   else
   {
      // For sell direction, hedges go up in price
      return group.entryPrice + totalPips * PIP * _Point;
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

//+------------------------------------------------------------------+
//| Remove TP from initial position in specified direction           |
//+------------------------------------------------------------------+
void RemoveInitialPositionTP(int dir)
{
   ulong initialTicket = 0;
   datetime earliestTime = D'3000.01.01';
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE) != (dir == 1 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL)) continue;
      
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
      Print("Removed TP from initial ", dir == 1 ? "long" : "short", " position #", initialTicket);
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
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get total unrealized profit                                      |
//+------------------------------------------------------------------+
double GetTotalUnrealizedProfit()
{
   double profit = 0;
   for(int i = PositionsTotal()-1; i >=0; i--)
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
   for(int i = PositionsTotal()-1; i >=0; i--)
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
   if(currentEquity > highestEquity)
   {
      highestEquity = currentEquity;
   }
}