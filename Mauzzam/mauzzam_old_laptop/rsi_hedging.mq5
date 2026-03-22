//+------------------------------------------------------------------+
//|                                                     HedgeRSI.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input group "RSI Settings"
input int RSI_Period = 14;           // RSI Period
input ENUM_APPLIED_PRICE RSI_Price = PRICE_CLOSE; // RSI Applied Price
input double Overbought_Level = 70;  // Overbought Level
input double Oversold_Level = 30;    // Oversold Level

input group "Trade Settings"
input double Lot_Size = 0.01;        // Lot Size
input double StopLoss_Dollars = 10;  // Stop Loss in Dollars
input double TakeProfit_Dollars = 10;// Take Profit in Dollars
input int Magic_Number = 123456;     // Magic Number
input string Trade_Comment = "HedgeRSI"; // Trade Comment

input group "Trailing Stop Settings"
input int Trail_Start = 10;          // Trail Start (points)
input int Trail_Step = 10;           // Trail Step (points)
input bool Enable_Trailing = true;   // Enable Trailing Stop

// Global variables
int rsi_handle;
double current_sl_buy = 0, current_sl_sell = 0;
double entry_price = 0;
bool positions_open = false;
datetime last_trade_time = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize RSI indicator
    rsi_handle = iRSI(_Symbol, _Period, RSI_Period, RSI_Price);
    if(rsi_handle == INVALID_HANDLE)
    {
        Print("Failed to create RSI indicator handle");
        return INIT_FAILED;
    }
    
    // Check if symbol is correct
    if(_Symbol != "XAUUSD")
        Print("Warning: This EA was designed for XAUUSD. Other symbols may have different pip values.");
    
    // Log initialization
    Print("Hedge RSI EA initialized successfully");
    Print("RSI Period: ", RSI_Period);
    Print("Lot Size: ", Lot_Size);
    Print("Stop Loss: $", StopLoss_Dollars);
    Print("Take Profit: $", TakeProfit_Dollars);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handle
    if(rsi_handle != INVALID_HANDLE)
        IndicatorRelease(rsi_handle);
        
    Print("EA deinitialized, reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    
    if(current_bar_time != last_bar_time)
    {
        last_bar_time = current_bar_time;
        CheckForEntrySignal();
    }
    
    // Manage open positions
    if(positions_open)
    {
        ManageOpenPositions();
        CheckForTrailingStop();
    }
}

//+------------------------------------------------------------------+
//| Check for RSI entry signal                                       |
//+------------------------------------------------------------------+
void CheckForEntrySignal()
{
    // Don't open new positions if we already have them
    if(positions_open || PositionsTotal() > 0)
        return;
    
    // Get RSI value
    double rsi_values[1];
    if(CopyBuffer(rsi_handle, 0, 0, 1, rsi_values) != 1)
    {
        Print("Failed to get RSI value");
        return;
    }
    
    double rsi_current = rsi_values[0];
    
    // Check for overbought/oversold conditions
    if(rsi_current >= Overbought_Level || rsi_current <= Oversold_Level)
    {
        // Calculate SL and TP in points based on dollar value
        double point_value = GetPointValue();
        double sl_points = NormalizeDouble(StopLoss_Dollars / (Lot_Size * point_value), 0);
        double tp_points = NormalizeDouble(TakeProfit_Dollars / (Lot_Size * point_value), 0);
        
        // Get current price
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        entry_price = current_price;
        
        // Open buy position
        MqlTradeRequest buy_request = {};
        MqlTradeResult buy_result = {};
        
        buy_request.action = TRADE_ACTION_DEAL;
        buy_request.symbol = _Symbol;
        buy_request.volume = Lot_Size;
        buy_request.type = ORDER_TYPE_BUY;
        buy_request.price = current_price;
        buy_request.sl = current_price - sl_points * _Point;
        buy_request.tp = current_price + tp_points * _Point;
        buy_request.deviation = 10;
        buy_request.magic = Magic_Number;
        buy_request.comment = Trade_Comment + "_BUY";
        buy_request.type_filling = ORDER_FILLING_FOK;
        
        // Open sell position
        MqlTradeRequest sell_request = {};
        MqlTradeResult sell_result = {};
        
        sell_request.action = TRADE_ACTION_DEAL;
        sell_request.symbol = _Symbol;
        sell_request.volume = Lot_Size;
        sell_request.type = ORDER_TYPE_SELL;
        sell_request.price = current_price;
        sell_request.sl = current_price + sl_points * _Point;
        sell_request.tp = current_price - tp_points * _Point;
        sell_request.deviation = 10;
        sell_request.magic = Magic_Number;
        sell_request.comment = Trade_Comment + "_SELL";
        sell_request.type_filling = ORDER_FILLING_FOK;
        
        // Send buy order
        if(OrderSend(buy_request, buy_result))
        {
            Print("Buy order opened: Ticket #", buy_result.order);
            Print("Buy - Price: ", buy_request.price, " SL: ", buy_request.sl, " TP: ", buy_request.tp);
            
            // Send sell order
            if(OrderSend(sell_request, sell_result))
            {
                Print("Sell order opened: Ticket #", sell_result.order);
                Print("Sell - Price: ", sell_request.price, " SL: ", sell_request.sl, " TP: ", sell_request.tp);
                
                // Set initial trailing stop levels
                current_sl_buy = buy_request.sl;
                current_sl_sell = sell_request.sl;
                positions_open = true;
                last_trade_time = TimeCurrent();
                
                Print("Hedge positions opened at price: ", current_price);
                Print("RSI Value: ", rsi_current);
            }
            else
            {
                Print("Failed to open sell order: ", sell_result.comment);
                // Close buy order if sell failed
                CloseAllPositions();
            }
        }
        else
        {
            Print("Failed to open buy order: ", buy_result.comment);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    int buy_positions = 0;
    int sell_positions = 0;
    
    // Count open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    buy_positions++;
                else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    sell_positions++;
            }
        }
    }
    
    // If one position is closed, close the other
    if(buy_positions == 0 || sell_positions == 0)
    {
        CloseAllPositions();
        positions_open = false;
        current_sl_buy = 0;
        current_sl_sell = 0;
        Print("One position closed. Closing all remaining positions.");
    }
}

//+------------------------------------------------------------------+
//| Check and update trailing stops                                  |
//+------------------------------------------------------------------+
void CheckForTrailingStop()
{
    if(!Enable_Trailing || !positions_open)
        return;
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double distance_from_entry = (current_price - entry_price) / _Point;
    
    // Only start trailing after price moves Trail_Start points
    if(MathAbs(distance_from_entry) >= Trail_Start)
    {
        // Update buy position trailing stop
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket))
            {
                if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                   PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    double current_sl = PositionGetDouble(POSITION_SL);
                    double new_sl = current_price - Trail_Step * _Point;
                    
                    // Only move SL up (for buy position)
                    if(new_sl > current_sl && new_sl > entry_price)
                    {
                        MqlTradeRequest request = {};
                        MqlTradeResult result = {};
                        
                        request.action = TRADE_ACTION_SLTP;
                        request.position = ticket;
                        request.symbol = _Symbol;
                        request.sl = new_sl;
                        request.magic = Magic_Number;
                        
                        if(OrderSend(request, result))
                        {
                            current_sl_buy = new_sl;
                            Print("Buy trailing SL updated to: ", new_sl);
                        }
                    }
                }
                
                // Update sell position trailing stop
                if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
                   PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                {
                    double current_sl = PositionGetDouble(POSITION_SL);
                    double new_sl = current_price + Trail_Step * _Point;
                    
                    // Only move SL down (for sell position)
                    if(new_sl < current_sl && new_sl < entry_price)
                    {
                        MqlTradeRequest request = {};
                        MqlTradeResult result = {};
                        
                        request.action = TRADE_ACTION_SLTP;
                        request.position = ticket;
                        request.symbol = _Symbol;
                        request.sl = new_sl;
                        request.magic = Magic_Number;
                        
                        if(OrderSend(request, result))
                        {
                            current_sl_sell = new_sl;
                            Print("Sell trailing SL updated to: ", new_sl);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic_Number)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                
                request.action = TRADE_ACTION_DEAL;
                request.position = ticket;
                request.symbol = _Symbol;
                request.volume = PositionGetDouble(POSITION_VOLUME);
                request.deviation = 10;
                request.magic = Magic_Number;
                request.comment = "Close hedge";
                
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    request.type = ORDER_TYPE_SELL;
                    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                }
                else
                {
                    request.type = ORDER_TYPE_BUY;
                    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                }
                
                if(OrderSend(request, result))
                {
                    Print("Position closed: Ticket #", ticket, " Profit: $", PositionGetDouble(POSITION_PROFIT));
                }
                else
                {
                    Print("Failed to close position: ", result.comment);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate point value for dollar conversion                      |
//+------------------------------------------------------------------+
double GetPointValue()
{
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tick_size > 0)
        return tick_value / tick_size * _Point;
    
    return 0;
}

//+------------------------------------------------------------------+
//| Display info on chart                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_CHART_CHANGE)
    {
        Comment("Hedge RSI EA\n",
                "Positions Open: ", positions_open ? "Yes" : "No", "\n",
                "Lot Size: ", Lot_Size, "\n",
                "RSI Levels: ", Oversold_Level, "/", Overbought_Level, "\n",
                "Trailing: ", Enable_Trailing ? "On" : "Off", "\n",
                "Time: ", TimeToString(TimeCurrent()));
    }
}