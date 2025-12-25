//+------------------------------------------------------------------+
//| AutoCloseEA.mq5                                                  |
//| Copyright 2024, Your Name Here                                   |
//| https://www.mql5.com                                             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Name Here"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Automatically closes any trade immediately after opening"

input bool EnableAutoClose = true; // Enable/Disable Auto Close feature

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
ulong lastProcessedTicket = 0;
datetime lastCheckTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("Auto Close EA started successfully");
    Print("EA will automatically close any new trade immediately");
    
    if(!EnableAutoClose)
    {
        Print("WARNING: Auto Close feature is disabled!");
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("Auto Close EA stopped");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new trades once per second to avoid excessive processing
    if(TimeCurrent() - lastCheckTime < 1)
        return;
    
    lastCheckTime = TimeCurrent();
    
    if(!EnableAutoClose)
        return;
    
    CheckAndCloseNewTrades();
}

//+------------------------------------------------------------------+
//| Check for new trades and close them immediately                  |
//+------------------------------------------------------------------+
void CheckAndCloseNewTrades()
{
    // Get total number of open positions
    int totalPositions = PositionsTotal();
    
    if(totalPositions == 0)
    {
        lastProcessedTicket = 0;
        return;
    }
    
    // Iterate through all positions
    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        
        if(ticket > 0)
        {
            // Get position details
            if(PositionSelectByTicket(ticket))
            {
                // Check if this is a new trade we haven't processed yet
                if(ticket != lastProcessedTicket)
                {
                    // Close the position immediately
                    ClosePosition(ticket);
                    
                    // Update last processed ticket
                    lastProcessedTicket = ticket;
                    
                    Print("Auto-closed position with ticket: ", ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close a position by ticket                                       |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    // Get position details
    if(!PositionSelectByTicket(ticket))
    {
        Print("Error: Failed to select position with ticket ", ticket);
        return false;
    }
    
    // Get position information
    double volume = PositionGetDouble(POSITION_VOLUME);
    string symbol = PositionGetString(POSITION_SYMBOL);
    long position_type = PositionGetInteger(POSITION_TYPE);
    
    // Prepare trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = symbol;
    request.volume = volume;
    request.deviation = 10;
    
    // Set order type based on position type
    if(position_type == POSITION_TYPE_BUY)
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
    }
    else if(position_type == POSITION_TYPE_SELL)
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    }
    else
    {
        Print("Error: Unknown position type for ticket ", ticket);
        return false;
    }
    
    // Send close order
    if(!OrderSend(request, result))
    {
        Print("Error closing position ", ticket, ": ", GetLastError());
        return false;
    }
    
    if(result.retcode != TRADE_RETCODE_DONE)
    {
        Print("Trade close failed for ticket ", ticket, ". Return code: ", result.retcode);
        return false;
    }
    
    Print("Successfully closed position: ", ticket, " | Symbol: ", symbol, " | Volume: ", volume);
    return true;
}

//+------------------------------------------------------------------+
//| Trade function - handles trade events                            |
//+------------------------------------------------------------------+
void OnTrade()
{
    // This function is called when trade events occur
    // We can use it as an additional trigger
    if(EnableAutoClose)
    {
        // Small delay to ensure position is registered
        Sleep(100);
        CheckAndCloseNewTrades();
    }
}

//+------------------------------------------------------------------+
//| TradeTransaction function - handles transaction events           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
    // This function provides more granular control over trade events
    if(EnableAutoClose)
    {
        // Check for position open events
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD && 
           trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
        {
            // Small delay to ensure position is registered
            Sleep(100);
            CheckAndCloseNewTrades();
        }
    }
}