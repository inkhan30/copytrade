//+------------------------------------------------------------------+
//|                                          CorrelatedPairsEA.mq5   |
//|                                Copyright 2024, Your Name Here    |
//|                                             https://www.your.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name Here"
#property link      "https://www.your.com"
#property version   "1.00"
#property description "Correlated Pairs Trading - Both positions in same direction"

// Include Trade and Logging classes
#include <Trade/Trade.mqh>
#include <Trade/AccountInfo.mqh>

// Input parameters
input double   InpLotSize = 0.1;           // Lot Size for each position
input int      InpRSIPeriod = 14;          // RSI Period
input double   InpRSIOverSold = 30.0;      // RSI Oversold Level
input double   InpTargetProfit = 2.0;      // Target Profit in $ (e.g., 1$ or 2$)
input double   InpMaxSpread = 20.0;        // Maximum allowed spread in points
input int      InpMagicNumber = 12345;     // Magic Number for trades
input bool     InpUseStopLoss = true;      // Use Stop Loss
input double   InpStopLossPips = 100;      // Stop Loss in pips
input bool     InpUseTakeProfit = false;   // Use Take Profit
input double   InpTakeProfitPips = 200;    // Take Profit in pips
input bool     InpIncludeSwapInProfit = true; // Include swap in profit calculation

// Global variables
CTrade trade;
CAccountInfo accountInfo;
double targetProfit;                       // Target profit in dollars
bool positionOpenedByRSI = false;          // Flag for RSI-based positions
int eurusdTicket = -1;                     // EURUSD position ticket
int usdchfTicket = -1;                     // USDCHF position ticket

// Logging levels
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_ERROR = 0,
   LOG_LEVEL_WARNING = 1,
   LOG_LEVEL_INFO = 2,
   LOG_LEVEL_DEBUG = 3
};

input ENUM_LOG_LEVEL InpLogLevel = LOG_LEVEL_INFO;  // Logging level

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade object with magic number
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Set target profit directly from input
   targetProfit = InpTargetProfit;
   
   // Log initialization
   LogMessage(LOG_LEVEL_INFO, "EA Initialized",
      StringFormat("Correlated Pairs Trading - BOTH POSITIONS IN SAME DIRECTION\n" +
                  "Lot Size: %.2f, Target Profit: $%.2f, RSI Period: %d, RSI Level: %.1f\n" +
                  "Stop Loss: %.0f pips, Take Profit: %.0f pips\n" +
                  "Include Swap in Profit: %s", 
                  InpLotSize, targetProfit, InpRSIPeriod, InpRSIOverSold,
                  InpStopLossPips, InpTakeProfitPips,
                  InpIncludeSwapInProfit ? "Yes" : "No"));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   LogMessage(LOG_LEVEL_INFO, "EA Deinitialized", 
      StringFormat("Reason: %d", reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for open positions
   CheckExistingPositions();
   
   // Manage open positions
   if (ArePositionsOpen())
   {
      ManageOpenPositions();
   }
   else
   {
      // Check for new trading opportunities
      CheckForNewTrades();
   }
}

//+------------------------------------------------------------------+
//| Check and update existing positions                              |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
   eurusdTicket = -1;
   usdchfTicket = -1;
   
   // Get positions with our magic number
   int positionsTotal = PositionsTotal();
   
   for(int i = positionsTotal - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         
         if(symbol == "EURUSD")
            eurusdTicket = (int)ticket;
         else if(symbol == "USDCHF")
            usdchfTicket = (int)ticket;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if both positions are open                                 |
//+------------------------------------------------------------------+
bool ArePositionsOpen()
{
   return (eurusdTicket != -1 && usdchfTicket != -1);
}

//+------------------------------------------------------------------+
//| Check for new trading opportunities                              |
//+------------------------------------------------------------------+
void CheckForNewTrades()
{
   // Check if positions are already open
   if(ArePositionsOpen())
      return;
   
   // Check RSI condition for EURUSD
   double rsi = GetRSI("EURUSD", InpRSIPeriod, PRICE_CLOSE, 1); // Previous candle
   bool isGreenCandle = IsGreenCandle("EURUSD", 1); // Previous candle
   
   LogMessage(LOG_LEVEL_DEBUG, "RSI Check", 
      StringFormat("RSI: %.2f, Green Candle: %s", rsi, isGreenCandle ? "Yes" : "No"));
   
   // Check if conditions are met
   if(rsi < InpRSIOverSold && isGreenCandle)
   {
      // Check spread
      if(GetSpread("EURUSD") <= InpMaxSpread && GetSpread("USDCHF") <= InpMaxSpread)
      {
         OpenCorrelatedPositions();
         positionOpenedByRSI = true;
      }
      else
      {
         LogMessage(LOG_LEVEL_WARNING, "Spread Check Failed",
            StringFormat("Spread too high. EURUSD: %.1f, USDCHF: %.1f", 
            GetSpread("EURUSD"), GetSpread("USDCHF")));
      }
   }
}

//+------------------------------------------------------------------+
//| Open correlated positions - BOTH IN SAME DIRECTION              |
//+------------------------------------------------------------------+
void OpenCorrelatedPositions()
{
   // Get current prices
   double eurusdAsk = SymbolInfoDouble("EURUSD", SYMBOL_ASK);
   double usdchfAsk = SymbolInfoDouble("USDCHF", SYMBOL_ASK);
   
   // Calculate stop loss and take profit levels
   double eurusdSl = 0, eurusdTp = 0;
   double usdchfSl = 0, usdchfTp = 0;
   
   if(InpUseStopLoss)
   {
      // For BUY positions, SL is below entry
      eurusdSl = eurusdAsk - InpStopLossPips * Point("EURUSD");
      usdchfSl = usdchfAsk - InpStopLossPips * Point("USDCHF");
   }
   
   if(InpUseTakeProfit)
   {
      eurusdTp = eurusdAsk + InpTakeProfitPips * Point("EURUSD");
      usdchfTp = usdchfAsk + InpTakeProfitPips * Point("USDCHF");
   }
   
   // Open EURUSD BUY position
   bool eurusdResult = trade.Buy(InpLotSize, "EURUSD", eurusdAsk, eurusdSl, eurusdTp, 
                                 "Correlated Pairs - BUY");
   
   if(eurusdResult)
   {
      LogMessage(LOG_LEVEL_INFO, "EURUSD BUY Position Opened",
         StringFormat("Lot: %.2f, Price: %.5f, SL: %.5f, TP: %.5f", 
         InpLotSize, eurusdAsk, eurusdSl, eurusdTp));
   }
   else
   {
      LogMessage(LOG_LEVEL_ERROR, "Failed to open EURUSD BUY position",
         StringFormat("Error: %d", GetLastError()));
      return;
   }
   
   // Give a small delay to ensure first order is processed
   Sleep(100);
   
   // Open USDCHF BUY position - SAME DIRECTION
   bool usdchfResult = trade.Buy(InpLotSize, "USDCHF", usdchfAsk, usdchfSl, usdchfTp, 
                                 "Correlated Pairs - BUY");
   
   if(usdchfResult)
   {
      LogMessage(LOG_LEVEL_INFO, "USDCHF BUY Position Opened",
         StringFormat("Lot: %.2f, Price: %.5f, SL: %.5f, TP: %.5f", 
         InpLotSize, usdchfAsk, usdchfSl, usdchfTp));
   }
   else
   {
      LogMessage(LOG_LEVEL_ERROR, "Failed to open USDCHF BUY position",
         StringFormat("Error: %d", GetLastError()));
      // Try to close the EURUSD position if USDCHF failed
      trade.PositionClose("EURUSD");
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double totalProfit = GetTotalProfit();
   double totalSwap = GetTotalSwap();
   double netProfit = InpIncludeSwapInProfit ? (totalProfit + totalSwap) : totalProfit;
   
   LogMessage(LOG_LEVEL_DEBUG, "Position Management",
      StringFormat("Total Profit: $%.2f, Swap: $%.2f, Net: $%.2f, Target: $%.2f", 
      totalProfit, totalSwap, netProfit, targetProfit));
   
   // Check if target profit is reached
   if(netProfit >= targetProfit)
   {
      LogMessage(LOG_LEVEL_INFO, "Profit Target Reached",
         StringFormat("Closing all positions. Current profit: $%.2f, Target: $%.2f", 
         netProfit, targetProfit));
      
      CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Get total profit from both positions                            |
//+------------------------------------------------------------------+
double GetTotalProfit()
{
   double totalProfit = 0;
   
   if(eurusdTicket != -1)
   {
      if(PositionSelectByTicket(eurusdTicket))
         totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   if(usdchfTicket != -1)
   {
      if(PositionSelectByTicket(usdchfTicket))
         totalProfit += PositionGetDouble(POSITION_PROFIT);
   }
   
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Get total swap from both positions                              |
//+------------------------------------------------------------------+
double GetTotalSwap()
{
   double totalSwap = 0;
   
   if(eurusdTicket != -1)
   {
      if(PositionSelectByTicket(eurusdTicket))
         totalSwap += PositionGetDouble(POSITION_SWAP);
   }
   
   if(usdchfTicket != -1)
   {
      if(PositionSelectByTicket(usdchfTicket))
         totalSwap += PositionGetDouble(POSITION_SWAP);
   }
   
   return totalSwap;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   double totalProfit = GetTotalProfit();
   double totalSwap = GetTotalSwap();
   double netProfit = InpIncludeSwapInProfit ? (totalProfit + totalSwap) : totalProfit;
   
   LogMessage(LOG_LEVEL_INFO, "Closing All Positions",
      StringFormat("Profit Target Reached!\n" +
                  "Profit: $%.2f, Swap: $%.2f, Net: $%.2f, Target: $%.2f", 
                  totalProfit, totalSwap, netProfit, targetProfit));
   
   bool allClosedSuccessfully = true;
   
   // Close EURUSD position
   if(eurusdTicket != -1)
   {
      if(PositionSelectByTicket(eurusdTicket))
      {
         double eurusdProfit = PositionGetDouble(POSITION_PROFIT);
         double eurusdSwap = PositionGetDouble(POSITION_SWAP);
         
         if(trade.PositionClose(eurusdTicket))
         {
            LogMessage(LOG_LEVEL_INFO, "EURUSD Position Closed",
               StringFormat("Ticket: %d, Profit: $%.2f, Swap: $%.2f, Total: $%.2f", 
               eurusdTicket, eurusdProfit, eurusdSwap, eurusdProfit + eurusdSwap));
         }
         else
         {
            LogMessage(LOG_LEVEL_ERROR, "Failed to close EURUSD position",
               StringFormat("Error: %d", GetLastError()));
            allClosedSuccessfully = false;
         }
      }
   }
   
   // Close USDCHF position
   if(usdchfTicket != -1)
   {
      if(PositionSelectByTicket(usdchfTicket))
      {
         double usdchfProfit = PositionGetDouble(POSITION_PROFIT);
         double usdchfSwap = PositionGetDouble(POSITION_SWAP);
         
         if(trade.PositionClose(usdchfTicket))
         {
            LogMessage(LOG_LEVEL_INFO, "USDCHF Position Closed",
               StringFormat("Ticket: %d, Profit: $%.2f, Swap: $%.2f, Total: $%.2f", 
               usdchfTicket, usdchfProfit, usdchfSwap, usdchfProfit + usdchfSwap));
         }
         else
         {
            LogMessage(LOG_LEVEL_ERROR, "Failed to close USDCHF position",
               StringFormat("Error: %d", GetLastError()));
            allClosedSuccessfully = false;
         }
      }
   }
   
   if(allClosedSuccessfully)
   {
      LogMessage(LOG_LEVEL_INFO, "All Positions Closed Successfully",
         StringFormat("Total Net Profit: $%.2f", netProfit));
   }
   
   // Reset flags
   positionOpenedByRSI = false;
   eurusdTicket = -1;
   usdchfTicket = -1;
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSI(string symbol, int period, ENUM_APPLIED_PRICE price, int shift)
{
   double rsiArray[];
   ArraySetAsSeries(rsiArray, true);
   
   int handle = iRSI(symbol, PERIOD_CURRENT, period, price);
   if(handle == INVALID_HANDLE)
   {
      LogMessage(LOG_LEVEL_ERROR, "RSI Indicator Error",
         StringFormat("Failed to get RSI handle for %s", symbol));
      return 100; // Return invalid value
   }
   
   if(CopyBuffer(handle, 0, shift, 1, rsiArray) < 1)
   {
      LogMessage(LOG_LEVEL_ERROR, "RSI Data Error",
         "Failed to copy RSI buffer");
      IndicatorRelease(handle);
      return 100;
   }
   
   IndicatorRelease(handle);
   return rsiArray[0];
}

//+------------------------------------------------------------------+
//| Check if candle is green                                         |
//+------------------------------------------------------------------+
bool IsGreenCandle(string symbol, int shift)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(symbol, PERIOD_CURRENT, shift, 1, rates) < 1)
   {
      LogMessage(LOG_LEVEL_ERROR, "Candle Data Error",
         "Failed to copy rates");
      return false;
   }
   
   return rates[0].close > rates[0].open;
}

//+------------------------------------------------------------------+
//| Get current spread in points                                     |
//+------------------------------------------------------------------+
double GetSpread(string symbol)
{
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return spread;
}

//+------------------------------------------------------------------+
//| Get point value for a symbol                                     |
//+------------------------------------------------------------------+
double Point(string symbol)
{
   return SymbolInfoDouble(symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Log message function                                             |
//+------------------------------------------------------------------+
void LogMessage(ENUM_LOG_LEVEL level, string function, string message)
{
   // Only log messages at or below the configured level
   if(level > InpLogLevel) return;
   
   string levelStr;
   switch(level)
   {
      case LOG_LEVEL_ERROR:   levelStr = "ERROR"; break;
      case LOG_LEVEL_WARNING: levelStr = "WARNING"; break;
      case LOG_LEVEL_INFO:    levelStr = "INFO"; break;
      case LOG_LEVEL_DEBUG:   levelStr = "DEBUG"; break;
      default:                levelStr = "UNKNOWN"; break;
   }
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string logEntry = StringFormat("%s [%s] %s: %s", timestamp, levelStr, function, message);
   
   // Print to Experts tab
   Print(logEntry);
}