//+------------------------------------------------------------------+
//|                                                       ConsecutiveCandleBreakEA.mq5 |
//|                                       Created by Deepseek AI Assistant |
//|                                          https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Deepseek AI Assistant"
#property link      "https://www.mql5.com"
#property version   "1.0"

//+------------------------------------------------------------------+
//| Input Parameters                                                |
//+------------------------------------------------------------------+
input string   GeneralSettings   = "------ General Settings ------";  // ---
input int      MagicNumber       = 123456;                           // Magic Number
input bool     EnableLogging     = true;                             // Enable Detailed Logging
input string   LogFileName       = "ConsecutiveCandleBreak.log";     // Log File Name

input string   TimeFrameSettings = "------ Time Frame Settings ------"; // ---
input ENUM_TIMEFRAMES ChartTimeFrame = PERIOD_CURRENT;                // Working Time Frame

input string   TradeSettings     = "------ Trade Settings ------";   // ---
input int      ConsecutiveCandles = 2;                               // Consecutive Candles to Check
input double   LotSize           = 0.1;                              // Lot Size
input int      StopLossPips      = 50;                               // Stop Loss (Pips)
input int      TakeProfitPips    = 100;                              // Take Profit (Pips)
input int      BreakEvenAtPercent = 50;                              // Move to BE at (%) Profit
input bool     EnableTrailingStop = true;                            // Enable Trailing Stop
input int      TrailStepPips     = 20;                               // Trailing Step (Pips)

input string   RiskSettings      = "------ Risk Management ------";  // ---
input int      MaxSpreadPoints   = 20;                               // Maximum Spread (Points)
input int      SlippagePoints    = 10;                               // Slippage (Points)

input string   BreakSettings     = "------ Break Settings ------";   // ---
input int      BreakMinutes      = 5;                                // Break After Trade (Minutes)
input bool     ShowBreakOnChart  = true;                             // Display Break on Chart

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
bool           trade_allowed = true;
bool           in_break_period = false;
datetime       break_end_time = 0;
ulong          last_order_ticket = 0;
double         point_value;
double         pip_value;
int            spread_limit;
MqlTradeRequest request;
MqlTradeResult  result;
MqlDateTime     break_end_struct;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate point and pip values
   point_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   pip_value = point_value * (_Digits % 2 == 1 ? 10 : 1); // For 5-digit brokers
   
   // Calculate spread limit
   spread_limit = (int)(MaxSpreadPoints * point_value * 10);
   
   // Initialize trade request structure
   ZeroMemory(request);
   ZeroMemory(result);
   
   // Create log file if enabled
   if(EnableLogging)
   {
      string log_path = "Files\\" + LogFileName;
      int file_handle = FileOpen(log_path, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(file_handle != INVALID_HANDLE)
      {
         string init_msg = "EA Initialized: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + 
                          ", Symbol: " + _Symbol + 
                          ", TimeFrame: " + EnumToString(ChartTimeFrame) + 
                          ", Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
         FileWrite(file_handle, init_msg);
         FileClose(file_handle);
         
         Print(init_msg);
      }
   }
   
   // Set up chart objects if enabled
   if(ShowBreakOnChart)
   {
      ObjectCreate(0, "BreakLabel", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "BreakLabel", OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, "BreakLabel", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, "BreakLabel", OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, "BreakLabel", OBJPROP_COLOR, clrRed);
      ObjectSetString(0, "BreakLabel", OBJPROP_TEXT, "");
      ObjectSetInteger(0, "BreakLabel", OBJPROP_FONTSIZE, 10);
   }
   
   EventSetTimer(1); // Set timer for 1 second updates
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Remove chart objects
   if(ShowBreakOnChart)
   {
      ObjectDelete(0, "BreakLabel");
   }
   
   // Log deinitialization
   if(EnableLogging)
   {
      string log_path = "Files\\" + LogFileName;
      int file_handle = FileOpen(log_path, FILE_WRITE|FILE_TXT|FILE_READ|FILE_COMMON);
      if(file_handle != INVALID_HANDLE)
      {
         FileSeek(file_handle, 0, SEEK_END);
         FileWrite(file_handle, "EA Deinitialized: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + 
                  ", Reason: " + IntegerToString(reason));
         FileClose(file_handle);
      }
   }
   
   EventKillTimer(); // Kill timer
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we're in break period
   CheckBreakPeriod();
   
   // Check if trading is allowed
   if(!trade_allowed || in_break_period)
   {
      return;
   }
   
   // Check if we already have an open position
   if(PositionsTotal() > 0)
   {
      ManageOpenPositions();
      return;
   }
   
   // Check entry conditions
   CheckEntryConditions();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Update break display
   UpdateBreakDisplay();
}

//+------------------------------------------------------------------+
//| Check entry conditions                                           |
//+------------------------------------------------------------------+
void CheckEntryConditions()
{
   // Check spread
   int current_spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(current_spread > spread_limit)
   {
      LogMessage("Spread too high: " + IntegerToString(current_spread) + " > " + IntegerToString(spread_limit));
      return;
   }
   
   // Get candle data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, ChartTimeFrame, 0, ConsecutiveCandles + 2, rates);
   
   if(copied < ConsecutiveCandles + 2)
   {
      LogMessage("Failed to copy rates. Copied: " + IntegerToString(copied));
      return;
   }
   
   // Check if we have enough consecutive candles
   bool consecutive_bullish = true;
   bool consecutive_bearish = true;
   
   for(int i = ConsecutiveCandles; i > 0; i--)
   {
      if(rates[i].close <= rates[i].open)
         consecutive_bullish = false;
      if(rates[i].close >= rates[i].open)
         consecutive_bearish = false;
   }
   
   // Check current candle (candle 0) break conditions
   double current_high = rates[0].high;
   double current_low = rates[0].low;
   double second_candle_high = rates[ConsecutiveCandles].high;
   double second_candle_low = rates[ConsecutiveCandles].low;
   
   // Check for buy signal
   if(consecutive_bullish && current_high > second_candle_high)
   {
      OpenBuyPosition(rates);
      return;
   }
   
   // Check for sell signal
   if(consecutive_bearish && current_low < second_candle_low)
   {
      OpenSellPosition(rates);
      return;
   }
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
void OpenBuyPosition(MqlRates &rates[])
{
   // Calculate SL and TP
   double sl_price = rates[ConsecutiveCandles + 1].low; // Low of first candle
   double tp_price = rates[0].open + (TakeProfitPips * pip_value);
   
   // Adjust SL if it's too close
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value;
   
   if(MathAbs(current_price - sl_price) < min_stop_level)
   {
      sl_price = current_price - min_stop_level;
      LogMessage("SL adjusted to minimum stop level. New SL: " + DoubleToString(sl_price, _Digits));
   }
   
   // Prepare trade request
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = current_price;
   request.sl = NormalizeDouble(sl_price, _Digits);
   request.tp = NormalizeDouble(tp_price, _Digits);
   request.deviation = SlippagePoints;
   request.magic = MagicNumber;
   request.comment = "ConsecutiveCandleBreak-BUY";
   
   // Send order
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      last_order_ticket = result.order;
      LogMessage("Buy order opened. Ticket: " + IntegerToString(last_order_ticket) + 
                ", Price: " + DoubleToString(result.price, _Digits) +
                ", SL: " + DoubleToString(request.sl, _Digits) +
                ", TP: " + DoubleToString(request.tp, _Digits));
      
      // Start break period
      StartBreakPeriod();
   }
   else
   {
      LogMessage("Failed to open buy order. Error: " + IntegerToString(result.retcode) +
                ", Price: " + DoubleToString(current_price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
void OpenSellPosition(MqlRates &rates[])
{
   // Calculate SL and TP
   double sl_price = rates[ConsecutiveCandles + 1].high; // High of first candle
   double tp_price = rates[0].open - (TakeProfitPips * pip_value);
   
   // Adjust SL if it's too close
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point_value;
   
   if(MathAbs(sl_price - current_price) < min_stop_level)
   {
      sl_price = current_price + min_stop_level;
      LogMessage("SL adjusted to minimum stop level. New SL: " + DoubleToString(sl_price, _Digits));
   }
   
   // Prepare trade request
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = current_price;
   request.sl = NormalizeDouble(sl_price, _Digits);
   request.tp = NormalizeDouble(tp_price, _Digits);
   request.deviation = SlippagePoints;
   request.magic = MagicNumber;
   request.comment = "ConsecutiveCandleBreak-SELL";
   
   // Send order
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      last_order_ticket = result.order;
      LogMessage("Sell order opened. Ticket: " + IntegerToString(last_order_ticket) + 
                ", Price: " + DoubleToString(result.price, _Digits) +
                ", SL: " + DoubleToString(request.sl, _Digits) +
                ", TP: " + DoubleToString(request.tp, _Digits));
      
      // Start break period
      StartBreakPeriod();
   }
   else
   {
      LogMessage("Failed to open sell order. Error: " + IntegerToString(result.retcode) +
                ", Price: " + DoubleToString(current_price, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         double current_profit = PositionGetDouble(POSITION_PROFIT);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl_price = PositionGetDouble(POSITION_SL);
         double tp_price = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Calculate profit percentage
         double profit_points = 0;
         if(pos_type == POSITION_TYPE_BUY)
            profit_points = (current_price - open_price) / pip_value;
         else if(pos_type == POSITION_TYPE_SELL)
            profit_points = (open_price - current_price) / pip_value;
            
         double profit_percent = (profit_points / TakeProfitPips) * 100;
         
         // Log current position status
         LogMessage("Position " + IntegerToString(ticket) + 
                   ", Profit: " + DoubleToString(current_profit, 2) + 
                   " (" + DoubleToString(profit_percent, 1) + "%)" +
                   ", SL: " + DoubleToString(sl_price, _Digits));
         
         // Check for break-even
         if(profit_percent >= BreakEvenAtPercent && MathAbs(sl_price - open_price) > point_value)
         {
            MoveToBreakEven(ticket, pos_type, open_price);
         }
         
         // Check for trailing stop
         if(EnableTrailingStop && profit_percent > BreakEvenAtPercent)
         {
            TrailStopLoss(ticket, pos_type, current_price, profit_points);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Move to break-even                                               |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket, ENUM_POSITION_TYPE pos_type, double open_price)
{
   MqlTradeRequest modify_request;
   MqlTradeResult modify_result;
   ZeroMemory(modify_request);
   ZeroMemory(modify_result);
   
   modify_request.action = TRADE_ACTION_SLTP;
   modify_request.position = ticket;
   modify_request.symbol = _Symbol;
   modify_request.sl = NormalizeDouble(open_price, _Digits);
   modify_request.tp = PositionGetDouble(POSITION_TP);
   
   if(OrderSend(modify_request, modify_result) && modify_result.retcode == TRADE_RETCODE_DONE)
   {
      LogMessage("Moved to break-even for ticket: " + IntegerToString(ticket));
   }
   else
   {
      LogMessage("Failed to move to break-even. Error: " + IntegerToString(modify_result.retcode));
   }
}

//+------------------------------------------------------------------+
//| Trail stop loss                                                  |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket, ENUM_POSITION_TYPE pos_type, double current_price, double profit_points)
{
   double current_sl = PositionGetDouble(POSITION_SL);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double trail_distance = TrailStepPips * pip_value;
   double new_sl = 0;
   bool should_modify = false;
   
   if(pos_type == POSITION_TYPE_BUY)
   {
      new_sl = current_price - trail_distance;
      // Only trail if new SL is higher than current SL and higher than open price
      if(new_sl > current_sl && new_sl > open_price)
      {
         should_modify = true;
      }
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      new_sl = current_price + trail_distance;
      // Only trail if new SL is lower than current SL and lower than open price
      if(new_sl < current_sl && new_sl < open_price)
      {
         should_modify = true;
      }
   }
   
   if(should_modify)
   {
      ModifyStopLoss(ticket, new_sl);
   }
}

//+------------------------------------------------------------------+
//| Modify stop loss                                                 |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket, double new_sl)
{
   MqlTradeRequest modify_request;
   MqlTradeResult modify_result;
   ZeroMemory(modify_request);
   ZeroMemory(modify_result);
   
   modify_request.action = TRADE_ACTION_SLTP;
   modify_request.position = ticket;
   modify_request.symbol = _Symbol;
   modify_request.sl = NormalizeDouble(new_sl, _Digits);
   modify_request.tp = PositionGetDouble(POSITION_TP);
   
   if(OrderSend(modify_request, modify_result) && modify_result.retcode == TRADE_RETCODE_DONE)
   {
      LogMessage("Trailed SL for ticket: " + IntegerToString(ticket) + 
                " to " + DoubleToString(new_sl, _Digits));
   }
   else
   {
      LogMessage("Failed to trail SL. Error: " + IntegerToString(modify_result.retcode));
   }
}

//+------------------------------------------------------------------+
//| Start break period                                               |
//+------------------------------------------------------------------+
void StartBreakPeriod()
{
   break_end_time = TimeCurrent() + (BreakMinutes * 60);
   in_break_period = true;
   trade_allowed = false;
   
   LogMessage("Started break period. Ends at: " + TimeToString(break_end_time, TIME_SECONDS));
}

//+------------------------------------------------------------------+
//| Check break period                                               |
//+------------------------------------------------------------------+
void CheckBreakPeriod()
{
   if(in_break_period && TimeCurrent() >= break_end_time)
   {
      in_break_period = false;
      trade_allowed = true;
      LogMessage("Break period ended. Trading resumed.");
   }
}

//+------------------------------------------------------------------+
//| Update break display                                             |
//+------------------------------------------------------------------+
void UpdateBreakDisplay()
{
   if(ShowBreakOnChart && in_break_period)
   {
      datetime current_time = TimeCurrent();
      int seconds_left = (int)(break_end_time - current_time);
      
      if(seconds_left > 0)
      {
         int minutes = seconds_left / 60;
         int seconds = seconds_left % 60;
         
         string display_text = "Break: " + IntegerToString(minutes) + "m " + 
                              IntegerToString(seconds) + "s left";
         
         ObjectSetString(0, "BreakLabel", OBJPROP_TEXT, display_text);
         ObjectSetInteger(0, "BreakLabel", OBJPROP_COLOR, clrRed);
      }
      else
      {
         ObjectSetString(0, "BreakLabel", OBJPROP_TEXT, "Trading Active");
         ObjectSetInteger(0, "BreakLabel", OBJPROP_COLOR, clrGreen);
      }
   }
   else if(ShowBreakOnChart && !in_break_period)
   {
      ObjectSetString(0, "BreakLabel", OBJPROP_TEXT, "Trading Active");
      ObjectSetInteger(0, "BreakLabel", OBJPROP_COLOR, clrGreen);
   }
}

//+------------------------------------------------------------------+
//| Log message function                                             |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string full_message = timestamp + " - " + message;
   
   // Print to experts journal
   Print(full_message);
   
   // Write to log file if enabled
   if(EnableLogging)
   {
      string log_path = "Files\\" + LogFileName;
      int file_handle = FileOpen(log_path, FILE_WRITE|FILE_TXT|FILE_READ|FILE_COMMON);
      if(file_handle != INVALID_HANDLE)
      {
         FileSeek(file_handle, 0, SEEK_END);
         FileWrite(file_handle, full_message);
         FileClose(file_handle);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
   // This function is called when a trade event occurs
   LogMessage("Trade event occurred");
}

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Check if a position was closed
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      
      if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
      {
         ENUM_DEAL_ENTRY entry_type = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         
         if(entry_type == DEAL_ENTRY_OUT)
         {
            LogMessage("Position closed. Starting break period.");
            StartBreakPeriod();
         }
      }
   }
}