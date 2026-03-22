//+------------------------------------------------------------------+
//|                                                   EMA_RSI_EA.mq5 |
//|                                    Created by Deepseek Assistant |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Created by Deepseek Assistant"
#property version   "1.00"
#property description "EMA and RSI based trading strategy"

//--- Input parameters
input double   InpLotSize     = 0.01;       // Lot size
input int      InpStopLoss    = 100;        // Stop Loss (pips)
input int      InpTakeProfit  = 200;        // Take Profit (pips)
input int      InpMAPeriod    = 20;         // EMA Period
input int      InpRSIPeriod   = 14;         // RSI Period
input int      InpRSILevelBuy = 60;         // RSI Buy Level
input int      InpRSILevelSell= 40;         // RSI Sell Level
input int      InpWaitTime    = 5;          // Wait time after SL (minutes)

//--- Global variables
ulong          magic_number   = 123456;     // Magic number
bool           allow_trade    = true;       // Trading permission
datetime       sl_hit_time    = 0;          // Time when SL was hit

//--- Indicator handles
int            ema_handle;
int            rsi_handle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check input parameters
   if(InpLotSize <= 0)
   {
      Print("Error: Lot size must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if(InpStopLoss < 0 || InpTakeProfit < 0)
   {
      Print("Error: Stop Loss and Take Profit must be non-negative");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Create indicator handles
   ema_handle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(ema_handle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator");
      return INIT_FAILED;
   }
   
   rsi_handle = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator");
      IndicatorRelease(ema_handle);
      return INIT_FAILED;
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(ema_handle != INVALID_HANDLE)
   {
      IndicatorRelease(ema_handle);
      ema_handle = INVALID_HANDLE;
   }
   
   if(rsi_handle != INVALID_HANDLE)
   {
      IndicatorRelease(rsi_handle);
      rsi_handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we can trade
   if(!IsTradeAllowed())
   {
      Comment("Trading not allowed");
      return;
   }
   
   // Check for SL hit cooldown
   if(sl_hit_time > 0)
   {
      datetime current_time = TimeCurrent();
      if(current_time - sl_hit_time < InpWaitTime * 60)
      {
         Comment("Waiting after SL hit...");
         return;
      }
      else
      {
         sl_hit_time = 0; // Reset cooldown
      }
   }
   
   // Check if we already have an open position
   if(PositionSelect(_Symbol))
   {
      Comment("Position already open");
      return;
   }
   
   // Get indicator values
   double ema_buffer[];
   double rsi_buffer[];
   
   // Copy EMA values
   if(CopyBuffer(ema_handle, 0, 0, 1, ema_buffer) < 1)
   {
      Print("Failed to copy EMA data");
      return;
   }
   
   // Copy RSI values
   if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_buffer) < 1)
   {
      Print("Failed to copy RSI data");
      return;
   }
   
   double ema_value = ema_buffer[0];
   double rsi_value = rsi_buffer[0];
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Check for buy signal
   if(current_price > ema_value && rsi_value > InpRSILevelBuy)
   {
      OpenPosition(ORDER_TYPE_BUY);
   }
   // Check for sell signal
   else if(current_price < ema_value && rsi_value < InpRSILevelSell)
   {
      OpenPosition(ORDER_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Open position function                                           |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_ORDER_TYPE order_type)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Calculate stop loss and take profit
   double sl_price = 0, tp_price = 0;
   double current_price = (order_type == ORDER_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Adjust for 5-digit brokers (multiply by 10)
   double multiplier = (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 || 
                       SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3) ? 10 : 1;
   
   double stop_loss_pips = InpStopLoss * multiplier * point;
   double take_profit_pips = InpTakeProfit * multiplier * point;
   
   if(order_type == ORDER_TYPE_BUY)
   {
      sl_price = current_price - stop_loss_pips;
      tp_price = current_price + take_profit_pips;
   }
   else // ORDER_TYPE_SELL
   {
      sl_price = current_price + stop_loss_pips;
      tp_price = current_price - take_profit_pips;
   }
   
   // Normalize prices
   sl_price = NormalizeDouble(sl_price, _Digits);
   tp_price = NormalizeDouble(tp_price, _Digits);
   
   // Prepare trade request
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = InpLotSize;
   request.type = order_type;
   request.price = current_price;
   request.sl = (InpStopLoss > 0) ? sl_price : 0;
   request.tp = (InpTakeProfit > 0) ? tp_price : 0;
   request.deviation = 10;
   request.magic = magic_number;
   request.comment = "EMA_RSI_Strategy";
   
   // Check volume
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Normalize volume to step size
   request.volume = NormalizeDouble(request.volume, 2);
   
   if(request.volume < min_volume)
   {
      Print("Volume too small. Minimum: ", min_volume);
      return false;
   }
   if(request.volume > max_volume)
   {
      Print("Volume too large. Maximum: ", max_volume);
      return false;
   }
   
   // Send order
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Order opened successfully. Ticket: ", result.order);
         return true;
      }
      else
      {
         Print("Order failed. Error: ", GetRetcodeID(result.retcode));
         return false;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check for closed positions
   HistorySelect(TimeCurrent() - 3600, TimeCurrent());
   int total_orders = HistoryOrdersTotal();
   
   for(int i = total_orders - 1; i >= 0; i--)
   {
      ulong ticket = HistoryOrderGetTicket(i);
      if(HistoryOrderGetInteger(ticket, ORDER_MAGIC) == magic_number)
      {
         ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
         if(state == ORDER_STATE_FILLED)
         {
            // Check if position was closed
            ulong position_ticket = HistoryOrderGetInteger(ticket, ORDER_POSITION_ID);
            
            // Check deals to see if SL was hit
            int total_deals = HistoryDealsTotal();
            for(int j = 0; j < total_deals; j++)
            {
               ulong deal_ticket = HistoryDealGetTicket(j);
               if(HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID) == position_ticket)
               {
                  ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                  
                  // Check if this was an exit deal (DEAL_ENTRY_OUT)
                  if(entry == DEAL_ENTRY_OUT)
                  {
                     double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                     
                     // If profit is negative and we have a stop loss set, mark as SL hit
                     if(profit < 0 && InpStopLoss > 0)
                     {
                        sl_hit_time = TimeCurrent();
                        Print("Stop Loss hit at ", TimeToString(sl_hit_time), ". Waiting for ", InpWaitTime, " minutes.");
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get retcode description                                          |
//+------------------------------------------------------------------+
string GetRetcodeID(int retcode)
{
   switch(retcode)
   {
      case 10004: return("TRADE_RETCODE_REQUOTE");
      case 10006: return("TRADE_RETCODE_REJECT");
      case 10007: return("TRADE_RETCODE_CANCEL");
      case 10008: return("TRADE_RETCODE_PLACED");
      case 10009: return("TRADE_RETCODE_DONE");
      case 10010: return("TRADE_RETCODE_DONE_PARTIAL");
      case 10011: return("TRADE_RETCODE_ERROR");
      case 10012: return("TRADE_RETCODE_TIMEOUT");
      case 10013: return("TRADE_RETCODE_INVALID");
      case 10014: return("TRADE_RETCODE_INVALID_VOLUME");
      case 10015: return("TRADE_RETCODE_INVALID_PRICE");
      case 10016: return("TRADE_RETCODE_INVALID_STOPS");
      case 10017: return("TRADE_RETCODE_TRADE_DISABLED");
      case 10018: return("TRARE_RETCODE_MARKET_CLOSED");
      case 10019: return("TRADE_RETCODE_NO_MONEY");
      case 10020: return("TRADE_RETCODE_PRICE_CHANGED");
      case 10021: return("TRADE_RETCODE_PRICE_OFF");
      case 10022: return("TRADE_RETCODE_INVALID_EXPIRATION");
      case 10023: return("TRADE_RETCODE_ORDER_CHANGED");
      case 10024: return("TRADE_RETCODE_TOO_MANY_REQUESTS");
      case 10025: return("TRADE_RETCODE_NO_CHANGES");
      case 10026: return("TRADE_RETCODE_SERVER_DISABLES_AT");
      case 10027: return("TRADE_RETCODE_CLIENT_DISABLES_AT");
      case 10028: return("TRADE_RETCODE_LOCKED");
      case 10029: return("TRADE_RETCODE_FROZEN");
      case 10030: return("TRADE_RETCODE_INVALID_FILL");
      case 10031: return("TRADE_RETCODE_CONNECTION");
      case 10032: return("TRADE_RETCODE_ONLY_REAL");
      case 10033: return("TRADE_RETCODE_LIMIT_ORDERS");
      case 10034: return("TRADE_RETCODE_LIMIT_VOLUME");
      case 10035: return("TRADE_RETCODE_INVALID_ORDER");
      case 10036: return("TRADE_RETCODE_POSITION_CLOSED");
      case 10038: return("TRADE_RETCODE_INVALID_CLOSE_VOLUME");
      case 10039: return("TRADE_RETCODE_CLOSE_ORDER_EXIST");
      case 10040: return("TRADE_RETCODE_LIMIT_POSITIONS");
      case 10041: return("TRADE_RETCODE_REJECT_CANCEL");
      case 10042: return("TRADE_RETCODE_LONG_ONLY");
      case 10043: return("TRADE_RETCODE_SHORT_ONLY");
      case 10044: return("TRADE_RETCODE_CLOSE_ONLY");
      case 10045: return("TRADE_RETCODE_FIFO_CLOSE");
      default: return("UNKNOWN_RETCODE");
   }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   // Check if trade context is busy
   if(!MQL5InfoInteger(MQL5_TRADE_ALLOWED))
   {
      Comment("Trade context is busy");
      return false;
   }
   
   // Check if AutoTrading is enabled
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Comment("AutoTrading disabled in terminal");
      return false;
   }
   
   // Check if trading is allowed for the symbol
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      Comment("Trading disabled for ", _Symbol);
      return false;
   }
   
   return true;
}
//+------------------------------------------------------------------+