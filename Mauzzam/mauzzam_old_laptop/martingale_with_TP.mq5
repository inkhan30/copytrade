// added 2 entry rsi entry
// Udate chart display fix
//+------------------------------------------------------------------+
//| Expert Advisor: Dynamic Hedging Martingale                       |
//|                Custom Trigger Distances and Lot Sizes Version    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023"
#property version   "1.00"
#property strict
#property indicator_chart_window

input bool     EnableStrategy      = true;        // Initial enable state
input bool     EnableEquityStop    = false;       // Enable/disable equity stop protection
input double   MaxEquityDrawdownPercent = 20.0;   // Max allowed equity drawdown percentage (if enabled)
input bool     RestartAfterDrawdown = true;       // Restart strategy after drawdown (if false, stops completely)

// Entry Logic Selection
input string   EntryLogicSettings  = "------ Entry Logic Settings ------";
input int      EntryLogic          = 1;           // 1=Consecutive Candles, 2=RSI Crossover, 3=Both
input int      ConsecutiveCandles  = 2;

// RSI Entry Logic Parameters
input int      RSI_Period_Entry    = 14;          // RSI period for entry signals
input int      RSI_Applied_Price_Entry = 0;       // RSI applied price for entry
input double   RSI_Overbought      = 75.0;        // RSI overbought level for sell signals
input double   RSI_Oversold        = 35.0;        // RSI oversold level for buy signals
input int      Trade_Mode          = 3;           // 0=No trading, 1=Buy only, 2=Sell only, 3=Both

input double   InitialLotSize      = 0.01;
input string   CustomLots          = "0.01,0.02,0.03"; // Comma-separated lot sizes for hedge positions
input int      InitialTPPips       = 100;        // Take-profit in pips
input string   TriggerPipsArray    = "700,1400,2100"; // Comma-separated trigger distances
input string   HedgeTPPipsArray    = "0,0,0";    // Comma-separated TP in pips for hedge positions (0=no TP)
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

// Manual Trade Incorporation
input bool     IncorporateManualTrades = true;   // Incorporate manual trades into EA management
input bool     CloseManualTradesWithEA = true;   // Close manual trades when EA closes positions

// New Inputs from Reliable v13
input string   ProfitTargetSettings= "------ Profit Target Settings ------";
input bool     EnableProfitTarget  = true;        // Enable profit target
input double   ProfitTargetFixed   = 100.0;       // Profit target in account currency
input int      ProfitTargetCooldownHours = 4;     // Cooldown after reaching target (hours)

input string   TimeExitSettings    = "------ Time Exit Settings ------";
input bool     EnableTimeExit      = true;        // Enable time-based exit for initial+hedge
input double   MaxTimeForInitialHedge = 2.0;      // Max hours for initial + first hedge
input double   BreakevenThreshold  = 5.0;         // USD threshold for breakeven condition

input string   TrailingSettings    = "------ Dynamic Trailing Settings ------";
input bool     EnableGroupTrailing = true;        // Enable group trailing SL
input double   TrailingActivationProfit = 20.0;   // Fixed profit amount to activate trailing (in USD)
input double   TrailingStepUSD     = 1.0;         // Profit increment to move SL
input double   MinTrailingDistanceUSD = 2.0;      // Minimum distance from current profit

input string   HaltSettings        = "------ Halt Period Settings ------";
input int      HaltPeriodSeconds   = 60;          // Wait time (seconds) after closing trades before new initial trade

// Trailing TP Settings
input string   TrailingTPSettings  = "------ Trailing TP Settings ------";
input bool     EnableTrailingTP    = true;        // Enable trailing take-profit for initial position
input int      TrailingTPDistance  = 20;          // Distance in pips to trail behind price
input int      TrailingTPActivation= 50;          // Profit in pips required to activate trailing

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayInt.mqh>
#include <Arrays\ArrayDouble.mqh>
#include <Indicators\Trend.mqh>
#include <Indicators\Oscilators.mqh>
CTrade trade;
CPositionInfo positionInfo;
CArrayInt triggerPips; // Array to store trigger pip values
CArrayDouble customLotsArray; // Array to store custom lot sizes
CArrayInt hedgeTPPips; // Array to store hedge TP pip values

// Global variables
bool strategyEnabled; // Track current strategy state (can be modified)
int direction = 0; // 1 for Buy, -1 for Sell
bool initialTradeOpened = false;
bool equityStopTriggered = false;
datetime lastHedgeTime = 0;
double highestEquity = 0;
double initialEntryPrice = 0;
CiMA emaIndicator; // EMA indicator object
CiRSI rsiIndicator; // RSI indicator object
CiRSI rsiEntryIndicator; // RSI indicator for entry signals
#define PIP 10

// New variables for added features
bool manualTradeDetected = false;
datetime initialTradeOpenTime = 0;
datetime firstHedgeOpenTime = 0;
bool timeExitTriggered = false;
double peakGroupProfit = 0;
bool trailingActive = false;
double activationLevel = 0;
double groupTrailingLevel = 0;
bool profitTargetReached = false;
datetime cooldownStartTime = 0;
double totalProfitSinceReset = 0;
bool inHaltPeriod = false;
datetime lastTradeCloseTime = 0;

// Trailing TP variables
double currentTrailingTP = 0;
bool trailingTPActive = false;

// RSI Entry variables
double rsiBuffer[]; // Array to store RSI values for entry logic
bool rsiBuySignal = false;
bool rsiSellSignal = false;

// Track previous state to detect manual closes
int previousTradeCount = 0;
bool wasInTrade = false;

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
string entryLogicLabel = "EntryLogicLabel";
string entryLogicValue = "EntryLogicValue";

//+------------------------------------------------------------------+
//| Reset EA state function                                          |
//+------------------------------------------------------------------+
void ResetEAState(bool isInitialization = false)
{
   initialTradeOpened = false;
   direction = 0;
   initialEntryPrice = 0;
   initialTradeOpenTime = 0;
   firstHedgeOpenTime = 0;
   timeExitTriggered = false;
   manualTradeDetected = false;
   trailingActive = false;
   groupTrailingLevel = 0;
   peakGroupProfit = 0;
   activationLevel = 0;
   totalProfitSinceReset = 0;
   profitTargetReached = false;
   cooldownStartTime = 0;
   
   // Reset trailing TP variables
   currentTrailingTP = 0;
   trailingTPActive = false;
   
   // Reset RSI signals
   rsiBuySignal = false;
   rsiSellSignal = false;
   
   // Only enter halt period if not initializing and HaltPeriodSeconds > 0
   inHaltPeriod = (!isInitialization && HaltPeriodSeconds > 0);
   lastTradeCloseTime = TimeCurrent();
   wasInTrade = false;
   
   if(isInitialization)
      Log("EA state initialized");
   else
      Log("EA state reset - waiting for halt period to expire");
}

//+------------------------------------------------------------------+
//| Log function for debugging                                       |
//+------------------------------------------------------------------+
void Log(string message)
{
   string logMessage = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + " - " + message;
   Print(logMessage);
}

//+------------------------------------------------------------------+
//| Send status notification                                         |
//+------------------------------------------------------------------+
void SendStatusNotification(string message)
{
   Print("Notification: " + message);
}

//+------------------------------------------------------------------+
//| Check manual trades and incorporate them                         |
//+------------------------------------------------------------------+
void CheckManualTrades()
{
   if(!IncorporateManualTrades) return;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber && 
         PositionGetString(POSITION_COMMENT) == "")
      {
         manualTradeDetected = true;
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         
         if(posType == POSITION_TYPE_BUY)
         {
            direction = 1;
            Log("Detected manual BUY trade");
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            direction = -1;
            Log("Detected manual SELL trade");
         }
         
         initialTradeOpened = true;
         initialEntryPrice = entryPrice;
         initialTradeOpenTime = TimeCurrent();
         wasInTrade = true;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate total profit since reset                               |
//+------------------------------------------------------------------+
double CalculateTotalProfitSinceReset()
{
   double profit = 0;
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }
   return profit + GetTotalUnrealizedProfit();
}

//+------------------------------------------------------------------+
//| Calculate total profit including manual trades                   |
//+------------------------------------------------------------------+
double CalculateTotalProfitIncludingManual()
{
   double profit = 0;
   
   // Add realized profit from history
   HistorySelect(0, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(IncorporateManualTrades || HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }
   
   // Add unrealized profit from open positions
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(IncorporateManualTrades || PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| Check profit target and cooldown                                 |
//+------------------------------------------------------------------+
void CheckProfitTarget()
{
   if(!EnableProfitTarget || ProfitTargetFixed <= 0) return;
   
   if(cooldownStartTime > 0)
   {
      double hoursInCooldown = (TimeCurrent() - cooldownStartTime) / 3600.0;
      if(hoursInCooldown >= ProfitTargetCooldownHours)
      {
         cooldownStartTime = 0;
         profitTargetReached = false;
         Log("Profit target cooldown period ended");
      }
      return;
   }
   
   if(!profitTargetReached)
   {
      double currentProfit = CalculateTotalProfitIncludingManual();
      if(currentProfit >= ProfitTargetFixed)
      {
         Log("Profit target reached: " + DoubleToString(currentProfit, 2));
         if(CloseAllTrades())
         {
            profitTargetReached = true;
            cooldownStartTime = TimeCurrent();
            SendStatusNotification("Profit target reached");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check time-based exit conditions                                 |
//+------------------------------------------------------------------+
void CheckTimeExit()
{
   if(!EnableTimeExit || timeExitTriggered) return;
   
   if(initialTradeOpened && firstHedgeOpenTime > 0)
   {
      double hoursElapsed = (TimeCurrent() - firstHedgeOpenTime) / 3600.0;
      if(hoursElapsed >= MaxTimeForInitialHedge)
      {
         double totalProfit = GetTotalUnrealizedProfit();
         if(MathAbs(totalProfit) <= BreakevenThreshold)
         {
            Log("Time exit triggered");
            timeExitTriggered = true;
            CloseAllTrades();
            SendStatusNotification("Time-based exit activated");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage dynamic trailing stops                                    |
//+------------------------------------------------------------------+
void ManageDynamicTrailing()
{
   if(!EnableGroupTrailing) return;
   
   double totalProfit = GetTotalUnrealizedProfitIncludingManual();
   
   if(totalProfit >= TrailingActivationProfit)
   {
      if(!trailingActive)
      {
         trailingActive = true;
         peakGroupProfit = totalProfit;
         groupTrailingLevel = peakGroupProfit - MinTrailingDistanceUSD;
         Log("Trailing SL activated at profit: " + DoubleToString(totalProfit, 2));
      }
      else
      {
         if(totalProfit > peakGroupProfit + TrailingStepUSD)
         {
            groupTrailingLevel = totalProfit - MinTrailingDistanceUSD;
            peakGroupProfit = totalProfit;
            Log("Trailing SL moved to: " + DoubleToString(groupTrailingLevel, 2));
         }
         
         if(totalProfit <= groupTrailingLevel)
         {
            CloseAllTrades();
            Log("Trailing SL triggered at profit: " + DoubleToString(totalProfit, 2));
            SendStatusNotification("Trailing stop triggered");
         }
      }
   }
   else if(trailingActive && totalProfit < TrailingActivationProfit)
   {
      // Reset trailing if profit falls below activation level
      trailingActive = false;
      Log("Trailing deactivated - profit below threshold");
   }
}

//+------------------------------------------------------------------+
//| Manage trailing take-profit for initial position                 |
//+------------------------------------------------------------------+
void ManageTrailingTP()
{
   if(!EnableTrailingTP || !initialTradeOpened) return;
   
   int totalTrades = CountOpenTrades();
   if(totalTrades > 1) return; // Only apply to initial position (before hedging)
   
   // Find the initial position
   ulong initialTicket = 0;
   double initialOpenPrice = 0;
   double currentTP = 0;
   
   for(int i = PositionsTotal()-1; i >=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      initialTicket = ticket;
      initialOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      currentTP = PositionGetDouble(POSITION_TP);
      break;
   }
   
   if(initialTicket == 0) return;
   
   double currentPrice = (direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentProfitPips = 0;
   
   if(direction == 1) // Buy position
   {
      currentProfitPips = (currentPrice - initialOpenPrice) / (_Point * PIP);
   }
   else // Sell position
   {
      currentProfitPips = (initialOpenPrice - currentPrice) / (_Point * PIP);
   }
   
   // Check if we should activate trailing TP
   if(!trailingTPActive && currentProfitPips >= TrailingTPActivation)
   {
      trailingTPActive = true;
      currentTrailingTP = currentTP;
      Log("Trailing TP activated at " + DoubleToString(currentTP, _Digits));
   }
   
   // Manage trailing TP if active
   if(trailingTPActive)
   {
      double newTP = 0;
      
      if(direction == 1) // Buy position
      {
         newTP = currentPrice - (TrailingTPDistance * PIP * _Point);
         if(newTP > currentTrailingTP && newTP > initialOpenPrice)
         {
            currentTrailingTP = newTP;
            if(trade.PositionModify(initialTicket, PositionGetDouble(POSITION_SL), newTP))
            {
               Log("Trailing TP moved to: " + DoubleToString(newTP, _Digits));
            }
         }
      }
      else // Sell position
      {
         newTP = currentPrice + (TrailingTPDistance * PIP * _Point);
         if((newTP < currentTrailingTP || currentTrailingTP == 0) && newTP < initialOpenPrice)
         {
            currentTrailingTP = newTP;
            if(trade.PositionModify(initialTicket, PositionGetDouble(POSITION_SL), newTP))
            {
               Log("Trailing TP moved to: " + DoubleToString(newTP, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check RSI crossover entry signals                                |
//+------------------------------------------------------------------+
bool CheckRSIEntrySignals()
{
   if(EntryLogic == 1) return false; // RSI entry disabled
   
   // Refresh RSI indicator data
   rsiEntryIndicator.Refresh();
   
   // Get RSI values
   double rsiCurrent = rsiEntryIndicator.Main(0);
   double rsiPrevious = rsiEntryIndicator.Main(1);
   
   if(rsiCurrent == 0 || rsiPrevious == 0) return false; // Invalid RSI values
   
   rsiBuySignal = false;
   rsiSellSignal = false;
   
   // Buy signal: RSI crosses above oversold level
   if((Trade_Mode == 1 || Trade_Mode == 3) && 
      rsiPrevious < RSI_Oversold && rsiCurrent >= RSI_Oversold)
   {
      rsiBuySignal = true;
      Log("RSI Buy Signal: RSI crossed above oversold (" + DoubleToString(RSI_Oversold, 1) + 
          ") - Previous: " + DoubleToString(rsiPrevious, 1) + ", Current: " + DoubleToString(rsiCurrent, 1));
   }
   
   // Sell signal: RSI crosses below overbought level  
   if((Trade_Mode == 2 || Trade_Mode == 3) && 
      rsiPrevious > RSI_Overbought && rsiCurrent <= RSI_Overbought)
   {
      rsiSellSignal = true;
      Log("RSI Sell Signal: RSI crossed below overbought (" + DoubleToString(RSI_Overbought, 1) + 
          ") - Previous: " + DoubleToString(rsiPrevious, 1) + ", Current: " + DoubleToString(rsiCurrent, 1));
   }
   
   return (rsiBuySignal || rsiSellSignal);
}

//+------------------------------------------------------------------+
//| Check if in halt period                                          |
//+------------------------------------------------------------------+
bool IsInHaltPeriod()
{
   if(HaltPeriodSeconds <= 0) return false;
   
   if(inHaltPeriod && (TimeCurrent() >= lastTradeCloseTime + HaltPeriodSeconds))
   {
      inHaltPeriod = false;
      Log("Halt period ended");
   }
   
   return inHaltPeriod;
}

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
   
   // Parse the HedgeTPPipsArray string into the hedgeTPPips array
   if(!ParseHedgeTPPipsArray())
   {
      Print("Error parsing HedgeTPPipsArray! Using default values");
      return INIT_FAILED;
   }
   
   // Verify that all arrays have the same size
   if(triggerPips.Total() != customLotsArray.Total() || 
      triggerPips.Total() != hedgeTPPips.Total())
   {
      Print("Error: TriggerPipsArray, CustomLots and HedgeTPPipsArray must have the same number of elements!");
      return INIT_FAILED;
   }
   
   // Initialize EMA indicator if filter is enabled
   if(UseEMAFilter)
   {
      if(!emaIndicator.Create(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE))
      {
         Print("Failed to create EMA indicator!");
         return(INIT_FAILED);
      }
   }
   
   // Initialize RSI indicator if filter is enabled
   if(UseRSIFilter)
   {
      if(!rsiIndicator.Create(_Symbol, _Period, RSI_Period, RSI_Applied_Price))
      {
         Print("Failed to create RSI indicator!");
         return(INIT_FAILED);
      }
   }
   
   // Initialize RSI indicator for entry signals if RSI entry is enabled
   if(EntryLogic == 2 || EntryLogic == 3)
   {
      if(!rsiEntryIndicator.Create(_Symbol, _Period, RSI_Period_Entry, RSI_Applied_Price_Entry))
      {
         Print("Failed to create RSI indicator for entry signals!");
         return(INIT_FAILED);
      }
      Log("RSI Entry logic initialized - Period: " + IntegerToString(RSI_Period_Entry) + 
          ", Overbought: " + DoubleToString(RSI_Overbought, 1) + 
          ", Oversold: " + DoubleToString(RSI_Oversold, 1) +
          ", Trade Mode: " + IntegerToString(Trade_Mode));
   }
   
   highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityStopTriggered = false; // Reset on init
   
   // Create chart objects for display
   CreateInfoLabels();
   
   // Print the configured lot sizes
   PrintConfiguredLotSizes();
   
   // Initialize new variables - don't enter halt period during initialization
   ResetEAState(true);
   
   // Initialize previous trade count
   previousTradeCount = CountOpenTrades();
   wasInTrade = (previousTradeCount > 0);
   
   // Print entry logic configuration
   string entryLogicStr = "";
   switch(EntryLogic)
   {
      case 1: entryLogicStr = "Consecutive Candles Only"; break;
      case 2: entryLogicStr = "RSI Crossover Only"; break;
      case 3: entryLogicStr = "Both Methods"; break;
      default: entryLogicStr = "Unknown"; break;
   }
   
   string tradeModeStr = "";
   switch(Trade_Mode)
   {
      case 0: tradeModeStr = "No Trading"; break;
      case 1: tradeModeStr = "Buy Only"; break;
      case 2: tradeModeStr = "Sell Only"; break;
      case 3: tradeModeStr = "Both Directions"; break;
      default: tradeModeStr = "Unknown"; break;
   }
   
   Log("EA initialized successfully - Entry Logic: " + entryLogicStr + ", Trade Mode: " + tradeModeStr);
   
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
//| Parse the HedgeTPPipsArray string into an array                  |
//+------------------------------------------------------------------+
bool ParseHedgeTPPipsArray()
{
   string values[];
   int count = StringSplit(HedgeTPPipsArray, ',', values);
   
   if(count <= 0)
   {
      Print("No values found in HedgeTPPipsArray!");
      return false;
   }
   
   // Clear and initialize the array
   hedgeTPPips.Clear();
   
   for(int i = 0; i < count; i++)
   {
      string temp = values[i];
      StringTrimLeft(temp);
      StringTrimRight(temp);
      int pipValue = (int)StringToInteger(temp);
      if(pipValue < 0)
      {
         Print("Invalid pip value in HedgeTPPipsArray: ", temp);
      }
      hedgeTPPips.Add(pipValue);
   }
   
   Print("Successfully parsed ", hedgeTPPips.Total(), " hedge TP pip values");
   return true;
}

//+------------------------------------------------------------------+
//| Get current EMA value                                            |
//+------------------------------------------------------------------+
double GetEMAValue()
{
   if(!UseEMAFilter) return 0;
   
   emaIndicator.Refresh();
   double emaValue = emaIndicator.Main(0);
   return emaValue;
}

//+------------------------------------------------------------------+
//| Get current RSI value                                            |
//+------------------------------------------------------------------+
double GetRSIValue()
{
   if(!UseRSIFilter) return 0;
   
   rsiIndicator.Refresh();
   double rsiValue = rsiIndicator.Main(0);
   return rsiValue;
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
   
   double currentClose = iClose(_Symbol, _Period, 0);
   
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
   ObjectDelete(0, entryLogicLabel);
   ObjectDelete(0, entryLogicValue);
   
   Log("EA deinitialized");
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
   
   // Entry Logic label
   ObjectCreate(0, entryLogicLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, entryLogicLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, entryLogicLabel, OBJPROP_XDISTANCE, labelX);
   ObjectSetInteger(0, entryLogicLabel, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, entryLogicLabel, OBJPROP_COLOR, clrLime);
   ObjectSetString(0, entryLogicLabel, OBJPROP_TEXT, "Entry Logic:");
   ObjectSetInteger(0, entryLogicLabel, OBJPROP_FONTSIZE, 10);
   
   // Entry Logic value
   ObjectCreate(0, entryLogicValue, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, entryLogicValue, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, entryLogicValue, OBJPROP_XDISTANCE, valueX);
   ObjectSetInteger(0, entryLogicValue, OBJPROP_YDISTANCE, startY);
   ObjectSetInteger(0, entryLogicValue, OBJPROP_COLOR, clrYellow);
   ObjectSetString(0, entryLogicValue, OBJPROP_TEXT, "N/A");
   ObjectSetInteger(0, entryLogicValue, OBJPROP_FONTSIZE, 10);
   
   // RSI label
   startY += verticalSpacing;
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
   
   // Status label (single status display - removed duplicate)
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
   // Update Entry Logic information
   string entryLogicStr = "";
   switch(EntryLogic)
   {
      case 1: entryLogicStr = "Candles Only"; break;
      case 2: entryLogicStr = "RSI Only"; break;
      case 3: entryLogicStr = "Both Methods"; break;
      default: entryLogicStr = "Unknown"; break;
   }
   
   string tradeModeStr = "";
   switch(Trade_Mode)
   {
      case 0: tradeModeStr = "No Trading"; break;
      case 1: tradeModeStr = "Buy Only"; break;
      case 2: tradeModeStr = "Sell Only"; break;
      case 3: tradeModeStr = "Both"; break;
      default: tradeModeStr = "Unknown"; break;
   }
   
   ObjectSetString(0, entryLogicValue, OBJPROP_TEXT, entryLogicStr + " (" + tradeModeStr + ")");
   
   // Update RSI information for entry
   if(EntryLogic == 2 || EntryLogic == 3)
   {
      rsiEntryIndicator.Refresh();
      double rsiVal = rsiEntryIndicator.Main(0);
      string rsiStatus = "N/A";
      color rsiColor = clrYellow;
      
      if(rsiVal > 0)
      {
         rsiStatus = DoubleToString(rsiVal, 1);
         
         if(rsiVal <= RSI_Oversold)
            rsiColor = clrLime;
         else if(rsiVal >= RSI_Overbought)
            rsiColor = clrRed;
         else
            rsiColor = clrYellow;
            
         if(rsiBuySignal)
            rsiStatus += " BUY SIGNAL";
         else if(rsiSellSignal)
            rsiStatus += " SELL SIGNAL";
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
   else if(StringFind(text, "Halt") >= 0) clr = clrGray;
   
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
//| Count all open trades including manual ones                      |
//+------------------------------------------------------------------+
int CountAllOpenTrades()
{
   int count = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check consecutive candles                                        |
//+------------------------------------------------------------------+
bool CheckConsecutiveCandles(int &dir)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1, ConsecutiveCandles, rates);
   if(copied < ConsecutiveCandles) return false;

   bool bullish = true;
   bool bearish = true;

   for(int i=0; i<ConsecutiveCandles; i++)
   {
      if(rates[i].close <= rates[i].open) bullish = false;
      if(rates[i].close >= rates[i].open) bearish = false;
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
   
   if(openCount > triggerPips.Total()) return;
   
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
      bool isLastPosition = (openCount == triggerPips.Total());
      
      // Calculate TP for this hedge position
      double tpPrice = 0;
      int tpPips = hedgeTPPips.At(openCount-1);
      if(tpPips > 0)
      {
         tpPrice = entryPrice + (direction == 1 ? tpPips : -tpPips) * PIP * _Point;
      }
      
      // Calculate SL for last position if needed
      double slPrice = 0;
      if(isLastPosition && LastPositionSLPips > 0)
      {
         slPrice = entryPrice + (direction == 1 ? -LastPositionSLPips : LastPositionSLPips) * PIP * _Point;
      }
      
      // Open the position with TP and/or SL
      if(trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                        lot, entryPrice, slPrice, tpPrice))
      {
         Log("Hedge #" + IntegerToString(openCount) + " opened at " + DoubleToString(entryPrice, _Digits) + 
               " (Trigger: " + DoubleToString(triggerPrice, _Digits) + 
               " Pips from initial: " + IntegerToString(GetTotalTriggerPips(openCount)) + 
               " TP: " + (tpPips > 0 ? DoubleToString(tpPrice, _Digits) : "None") +
               " SL: " + (isLastPosition && LastPositionSLPips > 0 ? DoubleToString(slPrice, _Digits) : "None") + ")");
         
         // Remove TP from initial position after first hedge opens and disable trailing TP
         if(openCount == 1)
         {
            RemoveInitialPositionTP();
            trailingTPActive = false;
         }
         
         // Record first hedge time
         if(openCount == 1 && firstHedgeOpenTime == 0)
            firstHedgeOpenTime = TimeCurrent();
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
      Log("Removed TP from initial position #" + IntegerToString(initialTicket));
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
//| Get total unrealized profit including manual trades              |
//+------------------------------------------------------------------+
double GetTotalUnrealizedProfitIncludingManual()
{
   double profit = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if (IncorporateManualTrades || PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         profit += PositionGetDouble(POSITION_PROFIT);
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Close all trades and return success status                       |
//+------------------------------------------------------------------+
bool CloseAllTrades()
{
   int closedCount = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if (CloseManualTradesWithEA || PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         if(trade.PositionClose(symbol)) {
            closedCount++;
         }
      }
   }
   
   if(closedCount > 0) {
      Log("Closed " + IntegerToString(closedCount) + " trades");
      ResetEAState(false);
      return true;
   }
   return false;
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
      return 0;
   
   int totalPips = 0;
   for(int i = 0; i < positionCount; i++)
   {
      totalPips += triggerPips.At(i);
   }
   
   if(direction == 1)
   {
      return initialEntryPrice - totalPips * PIP * _Point;
   }
   else
   {
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

//+------------------------------------------------------------------+
//| Check if trades were manually closed                            |
//+------------------------------------------------------------------+
void CheckForManualClose()
{
   int currentTradeCount = CountOpenTrades();
   
   if(wasInTrade && currentTradeCount == 0 && initialTradeOpened)
   {
      Log("Trades manually closed - resetting EA state");
      ResetEAState(false);
   }
   
   wasInTrade = (currentTradeCount > 0);
   previousTradeCount = currentTradeCount;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for manual closes first
   CheckForManualClose();
   
   if(!strategyEnabled || IsInHaltPeriod()) 
   {
      if(inHaltPeriod) 
         UpdateStatusLabel("In Halt Period");
      else
         UpdateStatusLabel("Strategy Disabled");
      UpdateChartInfo(); // Still update chart info even when disabled
      return;
   }

   CheckManualTrades();
   CheckProfitTarget();
   CheckTimeExit();
   ManageDynamicTrailing();
   ManageTrailingTP();
   
   UpdateHighestEquity();
   
   // Check if all trades are closed and reset if needed
   if(CountOpenTrades() == 0 && initialTradeOpened)
   {
      ResetEAState(false);
      highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      equityStopTriggered = false;
      Log("All trades closed - resetting EA state");
   }
   
   // Check RSI filter if enabled
   if(UseRSIFilter && !CheckRSIFilter())
   {
      if(CloseTradesOnRSI && CountOpenTrades() > 0)
      {
         CloseAllTrades();
         Log("RSI condition not met - all positions closed");
         UpdateStatusLabel("RSI Condition Failed");
      }
      UpdateChartInfo();
      return;
   }
   
   // Check equity stop if enabled and not already triggered
   if(EnableEquityStop && !equityStopTriggered && CheckEquityStop())
   {
      equityStopTriggered = true;
      CloseAllTrades();
      
      if(RestartAfterDrawdown)
      {
         ResetEAState(false);
         highestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         Log("Drawdown limit hit! Strategy reset and waiting for new signal.");
         UpdateStatusLabel("Drawdown - Reset");
      }
      else
      {
         strategyEnabled = false;
         Log("Drawdown limit hit! Strategy stopped completely.");
         UpdateStatusLabel("Stopped (Drawdown)");
         UpdateChartInfo();
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
         Log("Equity recovered - strategy resuming");
         UpdateStatusLabel("Running");
      }
      else
      {
         UpdateChartInfo();
         return;
      }
   }
   
   // Normal trading logic
   int totalTrades = CountOpenTrades();
   if(totalTrades == 0 && !inHaltPeriod)
   {
      // First check EMA filter if enabled
      int emaDirection = 0;
      if(UseEMAFilter && !CheckEMAFilter(emaDirection))
      {
         Log("EMA filter condition not met");
         UpdateChartInfo();
         return;
      }
      
      bool entrySignal = false;
      int newDirection = 0;
      
      // Check consecutive candles entry logic (if enabled)
      if(EntryLogic == 1 || EntryLogic == 3)
      {
         if(CheckConsecutiveCandles(newDirection))
         {
            if(!UseEMAFilter || newDirection == emaDirection)
            {
               entrySignal = true;
               direction = newDirection;
               Log("Consecutive candles entry signal detected");
            }
         }
      }
      
      // Check RSI crossover entry logic (if enabled and no signal from candles yet)
      if(!entrySignal && (EntryLogic == 2 || EntryLogic == 3))
      {
         if(CheckRSIEntrySignals())
         {
            if(rsiBuySignal && (Trade_Mode == 1 || Trade_Mode == 3))
            {
               if(!UseEMAFilter || emaDirection == 1)
               {
                  entrySignal = true;
                  direction = 1;
               }
            }
            else if(rsiSellSignal && (Trade_Mode == 2 || Trade_Mode == 3))
            {
               if(!UseEMAFilter || emaDirection == -1)
               {
                  entrySignal = true;
                  direction = -1;
               }
            }
         }
      }
      
      if(entrySignal)
      {
         initialTradeOpened = true;
         initialEntryPrice = SymbolInfoDouble(_Symbol, direction == 1 ? SYMBOL_ASK : SYMBOL_BID);
         trade.SetExpertMagicNumber(MagicNumber);
         Log("Entry signal detected - Direction: " + (direction == 1 ? "BUY" : "SELL") + " at price: " + DoubleToString(initialEntryPrice, _Digits));
         
         double tpPrice = initialEntryPrice + (direction == 1 ? InitialTPPips : -InitialTPPips) * PIP * _Point;
         
         if(trade.PositionOpen(_Symbol, direction == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                           InitialLotSize, initialEntryPrice, 0, tpPrice))
         {
            Log("Initial trade opened with TP: " + DoubleToString(tpPrice, _Digits));
            UpdateStatusLabel("Running");
         }
      }
   }
   else if(totalTrades <= triggerPips.Total())
   {
      ManageHedging();
   }
   
   // Update chart information on every tick
   UpdateChartInfo();
}
//+------------------------------------------------------------------+