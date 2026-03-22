//+------------------------------------------------------------------+
//|                                                      RSI_EA.mq5  |
//|                                    Copyright 2025, Deepseek EA   |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Deepseek EA"
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                |
//+------------------------------------------------------------------+
input int      RSI_Period = 14;           // RSI Period
input ENUM_APPLIED_PRICE RSI_Applied_Price = PRICE_CLOSE; // RSI Applied Price
input double   RSI_Buy_Level = 60.0;      // RSI Buy Level (RSI > this value for BUY)
input double   RSI_Sell_Level = 35.0;     // RSI Sell Level (RSI < this value for SELL)
input int      Consecutive_Candles = 2;   // Consecutive candles required
input double   StopLoss = 50.0;           // Stop Loss (pips)
input double   TakeProfit = 100.0;        // Take Profit (pips)
input double   LotSize = 0.1;             // Trade volume
input int      MagicNumber = 123456;      // Expert Magic Number
input int      WaitAfterClose = 5;        // Wait minutes after trade close
input int      Slippage = 10;             // Slippage in points

//+------------------------------------------------------------------+
//| Global variables                                                |
//+------------------------------------------------------------------+
datetime lastTradeCloseTime = 0;          // Time of last trade close
datetime lastTradeOpenTime = 0;           // Time of last trade open
int rsiHandle;                            // RSI indicator handle
bool isInitialized = false;               // Initialization flag
bool waitingPeriodActive = false;         // Waiting period flag
int lastPositionsCount = 0;               // Track previous positions count

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize RSI indicator
   rsiHandle = iRSI(Symbol(), Period(), RSI_Period, RSI_Applied_Price);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return INIT_FAILED;
   }
   
   // Log initialization
   Print("=== RSI EA Initialization ===");
   Print("Symbol: ", Symbol());
   Print("Timeframe: ", PeriodToString(Period()));
   Print("RSI Period: ", RSI_Period);
   Print("RSI Buy Level (RSI >): ", RSI_Buy_Level);
   Print("RSI Sell Level (RSI <): ", RSI_Sell_Level);
   Print("Consecutive Candles: ", Consecutive_Candles);
   Print("Stop Loss: ", StopLoss, " pips");
   Print("Take Profit: ", TakeProfit, " pips");
   Print("Lot Size: ", LotSize);
   Print("Wait After Close: ", WaitAfterClose, " minutes");
   Print("Magic Number: ", MagicNumber);
   Print("=============================");
   
   // Initialize last trade time from closed positions history
   InitializeLastTradeTime();
   
   // Get initial positions count
   lastPositionsCount = PositionsTotal();
   
   isInitialized = true;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Initialize last trade time from history                          |
//+------------------------------------------------------------------+
void InitializeLastTradeTime()
{
   // Get trade history for the last day
   datetime from = TimeCurrent() - 86400;
   datetime to = TimeCurrent();
   HistorySelect(from, to);
   
   int total = HistoryDealsTotal();
   Print("Checking ", total, " recent deals in history");
   
   // Find the last closed position with our magic number
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
         
         // Check if it's our EA's deal
         if(magic == MagicNumber)
         {
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT)  // Position close
            {
               lastTradeCloseTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
               Print("Found last trade CLOSE time from history: ", TimeToString(lastTradeCloseTime));
               
               // Also find the corresponding open time
               for(int j = i - 1; j >= 0; j--)
               {
                  ulong openTicket = HistoryDealGetTicket(j);
                  if(openTicket > 0)
                  {
                     long openMagic = HistoryDealGetInteger(openTicket, DEAL_MAGIC);
                     long openEntry = HistoryDealGetInteger(openTicket, DEAL_ENTRY);
                     if(openMagic == MagicNumber && openEntry == DEAL_ENTRY_IN)
                     {
                        lastTradeOpenTime = (datetime)HistoryDealGetInteger(openTicket, DEAL_TIME);
                        Print("Found last trade OPEN time from history: ", TimeToString(lastTradeOpenTime));
                        break;
                     }
                  }
               }
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA Deinitialized. Reason: ", DeinitReasonToString(reason));
   
   // Release indicator handle
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if initialization was successful
   if(!isInitialized)
   {
      Print("Error: EA not properly initialized");
      return;
   }
   
   // Check if we have enough bars
   if(Bars(Symbol(), Period()) < RSI_Period + Consecutive_Candles + 10)
   {
      Print("Not enough bars available");
      return;
   }
   
   // Check for closed positions and update waiting period
   CheckClosedPositions();
   
   // Check if we should wait after closing a trade
   if(ShouldWait())
   {
      if(!waitingPeriodActive)
      {
         waitingPeriodActive = true;
         int minutesLeft = WaitAfterClose - (int)((TimeCurrent() - lastTradeCloseTime) / 60);
         Print("Waiting period active. Next check in: ", minutesLeft, " minutes");
      }
      return;
   }
   else if(waitingPeriodActive)
   {
      waitingPeriodActive = false;
      Print("Waiting period ended. Resuming signal checks.");
   }
   
   // Check if we already have an open position
   if(HasOpenPosition())
   {
      // Log position status but don't open new ones
      static int lastLogTime = 0;
      if(TimeCurrent() - lastLogTime >= 60)  // Log once per minute
      {
         lastLogTime = TimeCurrent();
         Print("Position already open. Waiting for it to close.");
      }
      return;
   }
   
   // Check for trading signals
   CheckForSignals();
}

//+------------------------------------------------------------------+
//| Check if waiting period is active                                |
//+------------------------------------------------------------------+
bool ShouldWait()
{
   if(lastTradeCloseTime == 0)
      return false;
      
   datetime currentTime = TimeCurrent();
   int minutesPassed = (int)((currentTime - lastTradeCloseTime) / 60);
   
   return minutesPassed < WaitAfterClose;
}

//+------------------------------------------------------------------+
//| Check if there's an open position                                |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol() &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   // Check for Buy signal (RSI > 60 and consecutive bullish candles)
   if(CheckBuySignal())
   {
      Print("BUY signal detected at ", TimeToString(TimeCurrent()));
      Print("Conditions: RSI > ", RSI_Buy_Level, " and ", Consecutive_Candles, " consecutive bullish candles");
      OpenBuyPosition();
   }
   // Check for Sell signal (RSI < 35 and consecutive bearish candles)
   else if(CheckSellSignal())
   {
      Print("SELL signal detected at ", TimeToString(TimeCurrent()));
      Print("Conditions: RSI < ", RSI_Sell_Level, " and ", Consecutive_Candles, " consecutive bearish candles");
      OpenSellPosition();
   }
}

//+------------------------------------------------------------------+
//| Check for Buy signal conditions                                  |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   // Get RSI values (need extra candle for confirmation)
   double rsi[];
   if(CopyBuffer(rsiHandle, 0, 0, Consecutive_Candles + 2, rsi) < Consecutive_Candles + 2)
   {
      Print("Error copying RSI data for Buy signal");
      return false;
   }
   
   // Check RSI condition for BUY: RSI must be GREATER than Buy Level
   // Using index 1 for previous complete candle
   if(rsi[1] <= RSI_Buy_Level)
   {
      return false;
   }
   
   // Check for consecutive bullish candles
   MqlRates rates[];
   if(CopyRates(Symbol(), Period(), 1, Consecutive_Candles, rates) < Consecutive_Candles)
   {
      Print("Error copying price data for Buy signal");
      return false;
   }
   
   // Check if all required candles are bullish (close > open)
   for(int i = 0; i < Consecutive_Candles; i++)
   {
      if(rates[i].close <= rates[i].open)
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for Sell signal conditions                                 |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   // Get RSI values (need extra candle for confirmation)
   double rsi[];
   if(CopyBuffer(rsiHandle, 0, 0, Consecutive_Candles + 2, rsi) < Consecutive_Candles + 2)
   {
      Print("Error copying RSI data for Sell signal");
      return false;
   }
   
   // Check RSI condition for SELL: RSI must be LESS than Sell Level
   // Using index 1 for previous complete candle
   if(rsi[1] >= RSI_Sell_Level)
   {
      return false;
   }
   
   // Check for consecutive bearish candles
   MqlRates rates[];
   if(CopyRates(Symbol(), Period(), 1, Consecutive_Candles, rates) < Consecutive_Candles)
   {
      Print("Error copying price data for Sell signal");
      return false;
   }
   
   // Check if all required candles are bearish (close < open)
   for(int i = 0; i < Consecutive_Candles; i++)
   {
      if(rates[i].close >= rates[i].open)
      {
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double sl = CalculateSL(price, StopLoss, false);
   double tp = CalculateTP(price, TakeProfit, false);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "RSI EA Buy - RSI > " + DoubleToString(RSI_Buy_Level, 1);
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         lastTradeOpenTime = TimeCurrent();
         Print("BUY order opened successfully at ", TimeToString(lastTradeOpenTime));
         Print("Ticket: ", result.order, 
               ", Price: ", price, 
               ", SL: ", sl, 
               ", TP: ", tp,
               ", Volume: ", LotSize);
      }
      else
      {
         Print("BUY order failed. Error: ", GetRetcodeDescription(result.retcode));
      }
   }
   else
   {
      Print("OrderSend failed for BUY order");
   }
}

//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double sl = CalculateSL(price, StopLoss, true);
   double tp = CalculateTP(price, TakeProfit, true);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "RSI EA Sell - RSI < " + DoubleToString(RSI_Sell_Level, 1);
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         lastTradeOpenTime = TimeCurrent();
         Print("SELL order opened successfully at ", TimeToString(lastTradeOpenTime));
         Print("Ticket: ", result.order, 
               ", Price: ", price, 
               ", SL: ", sl, 
               ", TP: ", tp,
               ", Volume: ", LotSize);
      }
      else
      {
         Print("SELL order failed. Error: ", GetRetcodeDescription(result.retcode));
      }
   }
   else
   {
      Print("OrderSend failed for SELL order");
   }
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss price                                        |
//+------------------------------------------------------------------+
double CalculateSL(double price, double slPips, bool isSell)
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double pipValue = point * 10;  // Standard pip for most pairs
   
   // For 5-digit brokers, pip is 10 points
   // For 3-digit brokers (JPY pairs), pip is 100 points
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   if(digits == 3 || digits == 2)  // JPY pairs
      pipValue = point * 100;
   
   if(isSell)
      return price + (slPips * pipValue);
   else
      return price - (slPips * pipValue);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit price                                      |
//+------------------------------------------------------------------+
double CalculateTP(double price, double tpPips, bool isSell)
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   double pipValue = point * 10;  // Standard pip for most pairs
   
   // For 5-digit brokers, pip is 10 points
   // For 3-digit brokers (JPY pairs), pip is 100 points
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   if(digits == 3 || digits == 2)  // JPY pairs
      pipValue = point * 100;
   
   if(isSell)
      return price - (tpPips * pipValue);
   else
      return price + (tpPips * pipValue);
}

//+------------------------------------------------------------------+
//| Check for closed positions                                       |
//+------------------------------------------------------------------+
void CheckClosedPositions()
{
   int currentPositionsCount = PositionsTotal();
   
   // If positions count decreased, a position was closed
   if(currentPositionsCount < lastPositionsCount)
   {
      // Check history for the closed position
      datetime from = TimeCurrent() - 300; // Last 5 minutes
      datetime to = TimeCurrent();
      HistorySelect(from, to);
      
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            
            // Check if it's our EA's position that was just closed
            if(magic == MagicNumber && entry == DEAL_ENTRY_OUT)
            {
               lastTradeCloseTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               
               Print("=========================================");
               Print("Position CLOSED at ", TimeToString(lastTradeCloseTime));
               Print("Closed by: ", (type == DEAL_TYPE_BUY ? "TP/SL on BUY" : "TP/SL on SELL"));
               Print("Profit/Loss: $", profit);
               Print("Waiting ", WaitAfterClose, " minutes before next trade");
               Print("Next trade allowed after: ", TimeToString(lastTradeCloseTime + WaitAfterClose * 60));
               Print("=========================================");
               
               break;
            }
         }
      }
   }
   
   lastPositionsCount = currentPositionsCount;
}

//+------------------------------------------------------------------+
//| Convert period to string                                         |
//+------------------------------------------------------------------+
string PeriodToString(ENUM_TIMEFRAMES period)
{
   switch(period)
   {
      case PERIOD_M1: return "M1";
      case PERIOD_M5: return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      case PERIOD_W1: return "W1";
      case PERIOD_MN1: return "MN1";
      default: return IntegerToString(period) + " min";
   }
}

//+------------------------------------------------------------------+
//| Convert deinit reason to string                                  |
//+------------------------------------------------------------------+
string DeinitReasonToString(int reason)
{
   switch(reason)
   {
      case REASON_ACCOUNT: return "Account changed";
      case REASON_CHARTCHANGE: return "Chart changed";
      case REASON_CHARTCLOSE: return "Chart closed";
      case REASON_CLOSE: return "Terminal closed";
      case REASON_INITFAILED: return "Init failed";
      case REASON_PARAMETERS: return "Parameters changed";
      case REASON_RECOMPILE: return "Recompiled";
      case REASON_REMOVE: return "EA removed";
      case REASON_TEMPLATE: return "Template changed";
      default: return "Unknown reason: " + IntegerToString(reason);
   }
}

//+------------------------------------------------------------------+
//| Get retcode description                                          |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE: return "Requote";
      case TRADE_RETCODE_REJECT: return "Request rejected";
      case TRADE_RETCODE_CANCEL: return "Request canceled";
      case TRADE_RETCODE_PLACED: return "Order placed";
      case TRADE_RETCODE_DONE: return "Request completed";
      case TRADE_RETCODE_DONE_PARTIAL: return "Only part of request completed";
      case TRADE_RETCODE_ERROR: return "Request processing error";
      case TRADE_RETCODE_TIMEOUT: return "Request timeout";
      case TRADE_RETCODE_INVALID: return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE: return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS: return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED: return "Market closed";
      case TRADE_RETCODE_NO_MONEY: return "Not enough money";
      case TRADE_RETCODE_PRICE_CHANGED: return "Price changed";
      case TRADE_RETCODE_PRICE_OFF: return "No quotes";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration";
      case TRADE_RETCODE_ORDER_CHANGED: return "Order changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests";
      case TRADE_RETCODE_NO_CHANGES: return "No changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Auto trading disabled";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Auto trading disabled by client";
      case TRADE_RETCODE_LOCKED: return "Order locked";
      case TRADE_RETCODE_FROZEN: return "Order frozen";
      case TRADE_RETCODE_INVALID_FILL: return "Invalid fill";
      case TRADE_RETCODE_CONNECTION: return "No connection";
      case TRADE_RETCODE_ONLY_REAL: return "Only real trading allowed";
      case TRADE_RETCODE_LIMIT_ORDERS: return "Limit orders exceeded";
      case TRADE_RETCODE_LIMIT_VOLUME: return "Volume exceeded";
      default: return "Unknown error: " + IntegerToString(retcode);
   }
}
//+------------------------------------------------------------------+