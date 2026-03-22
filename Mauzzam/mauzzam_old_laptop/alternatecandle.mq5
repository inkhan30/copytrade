//+------------------------------------------------------------------+
//|                                             CandleOpenCloseEA.mq5|
//|                                      Created by Deepseek Trader  |
//|                                         https://www.deepseek.com |
//+------------------------------------------------------------------+
#property copyright "Deepseek Trader"
#property link      "https://www.deepseek.com"
#property version   "1.00"
#property description "Opens trade at candle open, closes at candle close"

//--- Input parameters
input double   LotSize=0.1;            // Fixed lot size
input int      SlippagePoints=10;      // Maximum slippage in points
input int      MagicNumber=98765;      // Unique EA identifier
input string   TradeComment="CandleOC"; // Trade comment
input bool     EnableTrading=true;     // Master trading switch
input int      MaxSpreadPoints=20;     // Maximum allowed spread
input bool     UseTightSpreadFilter=true; // Enable spread filter

//--- Global variables
datetime  current_bar_time=0;
bool      position_opened_this_bar=false;
ulong     current_position_ticket=0;
ENUM_POSITION_TYPE last_position_type=WRONG_VALUE;
double    entry_price=0.0;
MqlTick   last_tick;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Validate inputs
   if(LotSize<=0)
     {
      Print("Error: LotSize must be greater than 0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   
//--- Check trading permissions
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Error: Trading is not allowed on this terminal");
      return(INIT_FAILED);
     }
   
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("Error: Trading is not allowed in the program settings");
      return(INIT_FAILED);
     }
   
//--- Initialize variables
   current_bar_time=0;
   position_opened_this_bar=false;
   current_position_ticket=0;
   
//--- Print initialization message
   Print("Candle Open/Close EA Initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(_Period));
   Print("Lot Size: ", LotSize);
   Print("Max Spread: ", MaxSpreadPoints, " points");
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Close any open positions
   CloseAllPositions();
   Print("EA Deinitialized - Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check if trading is enabled
   if(!EnableTrading)
      return;
   
//--- Get current tick data
   if(!SymbolInfoTick(_Symbol,last_tick))
     {
      Print("Failed to get tick data");
      return;
     }
   
//--- Check for new candle
   datetime bar_time=iTime(_Symbol,_Period,0);
   
   if(current_bar_time!=bar_time)
     {
      //--- New candle detected
      OnNewCandle();
      current_bar_time=bar_time;
      position_opened_this_bar=false;
     }
   
//--- Manage trades on current candle
   ManageCurrentTrade();
  }

//+------------------------------------------------------------------+
//| Handle new candle formation                                      |
//+------------------------------------------------------------------+
void OnNewCandle()
  {
//--- Close any open position from previous candle
   CloseAllPositions();
   
//--- Reset tracking variables
   position_opened_this_bar=false;
   current_position_ticket=0;
   
//--- Get previous candle data (candle that just closed)
   double open[], close[];
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(close,true);
   
   if(CopyOpen(_Symbol,_Period,1,1,open)<1) return;
   if(CopyClose(_Symbol,_Period,1,1,close)<1) return;
   
//--- Check if we should open a new position
   if(!position_opened_this_bar)
     {
      //--- Determine candle direction
      bool is_bullish=(close[0]>open[0]);
      bool is_bearish=(close[0]<open[0]);
      
      if(is_bullish)
        {
         OpenBuyPosition();
        }
      else if(is_bearish)
        {
         OpenSellPosition();
        }
      // Do nothing for doji candles (open == close)
     }
  }

//+------------------------------------------------------------------+
//| Manage trade on current candle                                   |
//+------------------------------------------------------------------+
void ManageCurrentTrade()
  {
//--- Check if we have an open position
   if(current_position_ticket==0)
      return;
   
//--- Get current candle's open time
   datetime current_candle_open=iTime(_Symbol,_Period,0);
   
//--- Check if we're still in the same candle
   if(current_bar_time==current_candle_open)
     {
      // Position is still valid for this candle
      return;
     }
   else
     {
      // Candle has changed, close position
      CloseAllPositions();
     }
  }

//+------------------------------------------------------------------+
//| Open buy position at current candle open                         |
//+------------------------------------------------------------------+
void OpenBuyPosition()
  {
//--- Check spread if filter enabled
   if(UseTightSpreadFilter)
     {
      int spread=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spread>MaxSpreadPoints)
        {
         Print("Spread too high: ",spread," > ",MaxSpreadPoints," - Skipping buy");
         return;
        }
     }
   
//--- Get current candle open price
   double open_price=NormalizeDouble(iOpen(_Symbol,_Period,0),_Digits);
   
//--- Use current ask price for market execution
   double execution_price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   
//--- Check if price is near open (within 2 pips)
   double price_diff=MathAbs(execution_price-open_price)/_Point;
   if(price_diff>20) // More than 2 pips away
     {
      Print("Current price too far from candle open. Diff: ",price_diff," points");
      return;
     }
   
//--- Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=LotSize;
   request.type=ORDER_TYPE_BUY;
   request.price=execution_price;
   request.sl=0.0;  // No stop loss
   request.tp=0.0;  // No take profit
   request.deviation=SlippagePoints;
   request.magic=MagicNumber;
   request.comment=StringFormat("%s Buy C:%d",TradeComment,(int)current_bar_time);
   request.type_filling=ORDER_FILLING_FOK;
   request.type_time=ORDER_TIME_GTC;
   
//--- Send trade request
   if(!OrderSend(request,result))
     {
      Print("Buy order failed. Error: ",GetLastError()," | Retcode: ",result.retcode);
      return;
     }
   
//--- Update tracking variables
   if(result.retcode==TRADE_RETCODE_DONE)
     {
      current_position_ticket=result.order;
      position_opened_this_bar=true;
      entry_price=execution_price;
      last_position_type=POSITION_TYPE_BUY;
      
      Print("Buy order opened. Ticket: ",result.order,
            " | Price: ",execution_price,
            " | Time: ",TimeToString(TimeCurrent(),TIME_SECONDS));
     }
  }

//+------------------------------------------------------------------+
//| Open sell position at current candle open                        |
//+------------------------------------------------------------------+
void OpenSellPosition()
  {
//--- Check spread if filter enabled
   if(UseTightSpreadFilter)
     {
      int spread=(int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
      if(spread>MaxSpreadPoints)
        {
         Print("Spread too high: ",spread," > ",MaxSpreadPoints," - Skipping sell");
         return;
        }
     }
   
//--- Get current candle open price
   double open_price=NormalizeDouble(iOpen(_Symbol,_Period,0),_Digits);
   
//--- Use current bid price for market execution
   double execution_price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   
//--- Check if price is near open (within 2 pips)
   double price_diff=MathAbs(execution_price-open_price)/_Point;
   if(price_diff>20) // More than 2 pips away
     {
      Print("Current price too far from candle open. Diff: ",price_diff," points");
      return;
     }
   
//--- Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action=TRADE_ACTION_DEAL;
   request.symbol=_Symbol;
   request.volume=LotSize;
   request.type=ORDER_TYPE_SELL;
   request.price=execution_price;
   request.sl=0.0;  // No stop loss
   request.tp=0.0;  // No take profit
   request.deviation=SlippagePoints;
   request.magic=MagicNumber;
   request.comment=StringFormat("%s Sell C:%d",TradeComment,(int)current_bar_time);
   request.type_filling=ORDER_FILLING_FOK;
   request.type_time=ORDER_TIME_GTC;
   
//--- Send trade request
   if(!OrderSend(request,result))
     {
      Print("Sell order failed. Error: ",GetLastError()," | Retcode: ",result.retcode);
      return;
     }
   
//--- Update tracking variables
   if(result.retcode==TRADE_RETCODE_DONE)
     {
      current_position_ticket=result.order;
      position_opened_this_bar=true;
      entry_price=execution_price;
      last_position_type=POSITION_TYPE_SELL;
      
      Print("Sell order opened. Ticket: ",result.order,
            " | Price: ",execution_price,
            " | Time: ",TimeToString(TimeCurrent(),TIME_SECONDS));
     }
  }

//+------------------------------------------------------------------+
//| Close all positions opened by this EA                            |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
//--- Check if we have any positions to close
   if(PositionsTotal()==0)
      return;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0)
        {
         //--- Get position details
         string symbol=PositionGetString(POSITION_SYMBOL);
         ulong magic=PositionGetInteger(POSITION_MAGIC);
         
         //--- Close only positions opened by this EA
         if(symbol==_Symbol && magic==MagicNumber)
           {
            ClosePosition(ticket);
           }
        }
     }
   
//--- Reset tracking
   current_position_ticket=0;
  }

//+------------------------------------------------------------------+
//| Close a specific position                                        |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
  {
//--- Select the position
   if(!PositionSelectByTicket(ticket))
     {
      Print("Failed to select position with ticket: ",ticket);
      return;
     }
   
//--- Get position details
   double volume=PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   string symbol=PositionGetString(POSITION_SYMBOL);
   
//--- Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action=TRADE_ACTION_DEAL;
   request.symbol=symbol;
   request.volume=volume;
   request.position=ticket;
   request.deviation=SlippagePoints;
   request.magic=MagicNumber;
   request.comment=StringFormat("%s Close C:%d",TradeComment,(int)current_bar_time);
   request.type_filling=ORDER_FILLING_FOK;
   request.type_time=ORDER_TIME_GTC;
   
//--- Set order type based on position type
   if(type==POSITION_TYPE_BUY)
     {
      request.type=ORDER_TYPE_SELL;
      request.price=SymbolInfoDouble(symbol,SYMBOL_BID);
     }
   else if(type==POSITION_TYPE_SELL)
     {
      request.type=ORDER_TYPE_BUY;
      request.price=SymbolInfoDouble(symbol,SYMBOL_ASK);
     }
   else
     {
      return;
     }
   
//--- Send trade request
   if(!OrderSend(request,result))
     {
      Print("Failed to close position ",ticket,". Error: ",GetLastError());
      return;
     }
   
   // Calculate P&L
   double profit=PositionGetDouble(POSITION_PROFIT);
   Print("Position closed. Ticket: ",ticket,
         " | P&L: ",profit,
         " | Time: ",TimeToString(TimeCurrent(),TIME_SECONDS));
  }

//+------------------------------------------------------------------+
//| Trade function - handles trade events                            |
//+------------------------------------------------------------------+
void OnTrade()
  {
//--- Update position tracking when trades occur
   if(PositionsTotal()>0)
     {
      for(int i=0; i<PositionsTotal(); i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket>0 && PositionSelectByTicket(ticket))
           {
            ulong magic=PositionGetInteger(POSITION_MAGIC);
            if(magic==MagicNumber)
              {
               current_position_ticket=ticket;
               break;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| TradeTransaction function - detailed trade event handling        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
//--- Handle order placement events
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
     {
      // New deal added
      if(HistoryDealSelect(trans.deal))
        {
         ulong magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
         if(magic==MagicNumber)
           {
            ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_IN)
              {
               // Entry deal
               Print("Entry deal executed: ",HistoryDealGetString(trans.deal,DEAL_COMMENT));
              }
            else if(entry==DEAL_ENTRY_OUT)
              {
               // Exit deal
               Print("Exit deal executed: ",HistoryDealGetString(trans.deal,DEAL_COMMENT));
              }
           }
        }
     }
  }