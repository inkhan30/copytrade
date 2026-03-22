//+------------------------------------------------------------------+
//|                                            TradeManagerEA.mq5    |
//|                                       Developed by MT5 Expert    |
//|                                                 Version 1.0      |
//+------------------------------------------------------------------+
#property copyright "MT5 Expert"
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input Parameters                                                |
//+------------------------------------------------------------------+
input group "Equity Stop Loss Settings"
input bool   EnableEquitySL = true;          // Enable Equity Stop Loss
input double EquityStopLoss = 100.0;         // Equity SL in dollars
input bool   CloseAllOnSL = true;            // Close all trades on SL

input group "Take Profit Management"
input bool   AutoAddTP = true;               // Auto-add TP to manual trades
input double TakeProfitDollars = 10.0;       // Take Profit in dollars
input bool   EnableTrailingTP = true;        // Enable Trailing Take Profit
input double TrailStepDollars = 10.0;        // Trail step in dollars

input group "Risk Management"
input double MaxSpread = 5.0;                // Maximum spread in points
input int    MagicNumber = 123456;           // Magic number for EA trades
input string TradeComment = "TradeManager";  // Trade comment

//+------------------------------------------------------------------+
//| Global Variables                                                |
//+------------------------------------------------------------------+
double equityPeak;
double equityLow;
bool equitySLTriggered = false;
datetime lastCheckTime = 0;
MqlTick currentTick;
double pointValue;
ulong manualTickets[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize logging
    Print("=== Trade Manager EA Initialized ===");
    Print("Symbol: ", _Symbol);
    Print("Account Balance: $", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Equity Stop Loss: $", EquityStopLoss);
    Print("Take Profit: $", TakeProfitDollars);
    
    // Calculate point value
    pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * 
                 SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(pointValue <= 0)
    {
        Print("Error: Cannot calculate point value!");
        return INIT_FAILED;
    }
    
    Print("Point Value: $", pointValue);
    
    // Initialize equity tracking
    equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
    equityLow = equityPeak;
    
    // Initialize array for manual trade tracking
    ArrayResize(manualTickets, 0);
    
    // Run initial check
    OnTick();
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== Trade Manager EA Deinitialized ===");
    Print("Reason: ", GetDeinitReasonText(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Get current tick
    if(!SymbolInfoTick(_Symbol, currentTick))
    {
        Print("Error: Cannot get current tick!");
        return;
    }
    
    // Check spread
    double spread = (currentTick.ask - currentTick.bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(spread > MaxSpread)
    {
        Print("Spread too high: ", spread, " points. Maximum allowed: ", MaxSpread);
        return;
    }
    
    // Update equity tracking
    UpdateEquityTracking();
    
    // Check equity stop loss
    CheckEquityStopLoss();
    
    // Manage manual trades
    ManageManualTrades();
    
    // Clean up ticket array
    CleanupTicketArray();
}

//+------------------------------------------------------------------+
//| Update equity tracking                                           |
//+------------------------------------------------------------------+
void UpdateEquityTracking()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(currentEquity > equityPeak)
        equityPeak = currentEquity;
    
    if(currentEquity < equityLow)
        equityLow = currentEquity;
    
    // Reset equity SL trigger if equity recovers
    if(equitySLTriggered && currentEquity > (equityLow + EquityStopLoss))
    {
        equitySLTriggered = false;
        Print("Equity recovered from low of $", equityLow, " to $", currentEquity);
    }
}

//+------------------------------------------------------------------+
//| Check equity stop loss                                           |
//+------------------------------------------------------------------+
void CheckEquityStopLoss()
{
    if(!EnableEquitySL || equitySLTriggered)
        return;
    
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = equityPeak - currentEquity;
    
    if(drawdown >= EquityStopLoss)
    {
        equitySLTriggered = true;
        Print("EQUITY STOP LOSS TRIGGERED!");
        Print("Equity Peak: $", equityPeak);
        Print("Current Equity: $", currentEquity);
        Print("Drawdown: $", drawdown);
        Print("Stop Loss Level: $", EquityStopLoss);
        
        if(CloseAllOnSL)
        {
            CloseAllTrades();
        }
    }
}

//+------------------------------------------------------------------+
//| Manage manual trades                                             |
//+------------------------------------------------------------------+
void ManageManualTrades()
{
    int totalPositions = PositionsTotal();
    
    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        long magic = PositionGetInteger(POSITION_MAGIC);
        string comment = PositionGetString(POSITION_COMMENT);
        
        // Skip EA's own trades
        if(magic == MagicNumber) continue;
        
        // Check if this is a manual trade
        if(IsManualTrade(magic, comment))
        {
            // Add to tracking array if not already tracked
            if(!IsTicketTracked(ticket))
            {
                ArrayResize(manualTickets, ArraySize(manualTickets) + 1);
                manualTickets[ArraySize(manualTickets) - 1] = ticket;
                Print("New manual trade detected: Ticket #", ticket);
            }
            
            // Manage this trade
            ManageTrade(ticket);
        }
    }
}

//+------------------------------------------------------------------+
//| Manage individual trade                                          |
//+------------------------------------------------------------------+
void ManageTrade(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentProfit = PositionGetDouble(POSITION_PROFIT);
    double currentTP = PositionGetDouble(POSITION_TP);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Calculate TP in price
    double tpPrice = CalculateTPPrice(openPrice, type);
    
    // If no TP set and auto-add is enabled
    if(currentTP == 0 && AutoAddTP)
    {
        if(SetTradeTP(ticket, tpPrice))
        {
            Print("TP added to manual trade #", ticket, 
                  " at price: ", tpPrice, 
                  " (Profit target: $", TakeProfitDollars, ")");
        }
    }
    
    // Handle trailing TP
    if(EnableTrailingTP && currentTP != 0)
    {
        TrailTakeProfit(ticket, openPrice, currentTP, type, currentProfit);
    }
}

//+------------------------------------------------------------------+
//| Calculate TP price based on dollar amount                        |
//+------------------------------------------------------------------+
double CalculateTPPrice(double openPrice, ENUM_POSITION_TYPE type)
{
    double lotSize = PositionGetDouble(POSITION_VOLUME);
    
    // Calculate required price movement for target profit
    double requiredPoints = TakeProfitDollars / (lotSize * pointValue);
    double tpDistance = requiredPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(type == POSITION_TYPE_BUY)
        return openPrice + tpDistance;
    else
        return openPrice - tpDistance;
}

//+------------------------------------------------------------------+
//| Set take profit for trade                                        |
//+------------------------------------------------------------------+
bool SetTradeTP(ulong ticket, double tpPrice)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    // Validate TP price
    if(type == POSITION_TYPE_BUY && tpPrice <= PositionGetDouble(POSITION_PRICE_CURRENT))
        return false;
    if(type == POSITION_TYPE_SELL && tpPrice >= PositionGetDouble(POSITION_PRICE_CURRENT))
        return false;
    
    // Prepare trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.magic = MagicNumber;
    
    // Preserve existing SL
    double currentSL = PositionGetDouble(POSITION_SL);
    request.sl = currentSL;
    request.tp = tpPrice;
    
    // Send modification request
    if(!OrderSend(request, result))
    {
        Print("Error setting TP for trade #", ticket, 
              ". Error code: ", result.retcode, 
              " - ", GetRetcodeDescription(result.retcode));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Trail take profit                                                |
//+------------------------------------------------------------------+
void TrailTakeProfit(ulong ticket, double openPrice, double currentTP, 
                     ENUM_POSITION_TYPE type, double currentProfit)
{
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double lotSize = PositionGetDouble(POSITION_VOLUME);
    
    // Calculate required profit for trail step
    double requiredProfitForTrail = TakeProfitDollars + TrailStepDollars;
    double currentProfitDollars = currentProfit;
    
    // Check if we should trail
    if(currentProfitDollars >= requiredProfitForTrail)
    {
        // Calculate new TP
        double trailStepPoints = TrailStepDollars / (lotSize * pointValue);
        double trailDistance = trailStepPoints * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        
        double newTP;
        if(type == POSITION_TYPE_BUY)
        {
            newTP = currentTP + trailDistance;
            // Only trail if price is moving in our favor
            if(newTP <= currentPrice)
                return;
        }
        else
        {
            newTP = currentTP - trailDistance;
            // Only trail if price is moving in our favor
            if(newTP >= currentPrice)
                return;
        }
        
        // Set new TP
        if(SetTradeTP(ticket, newTP))
        {
            Print("TP trailed for trade #", ticket, 
                  " from ", currentTP, " to ", newTP,
                  " (Current profit: $", NormalizeDouble(currentProfitDollars, 2), ")");
        }
    }
}

//+------------------------------------------------------------------+
//| Close all trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
    int totalPositions = PositionsTotal();
    Print("Closing all ", totalPositions, " trades...");
    
    for(int i = totalPositions - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(!PositionSelectByTicket(ticket)) continue;
        
        ClosePosition(ticket);
    }
}

//+------------------------------------------------------------------+
//| Close individual position                                        |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                   ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "Equity SL Close";
    
    if(!OrderSend(request, result))
    {
        Print("Error closing trade #", ticket, 
              ". Error code: ", result.retcode);
        return false;
    }
    
    Print("Trade #", ticket, " closed due to equity stop loss");
    return true;
}

//+------------------------------------------------------------------+
//| Check if trade is manual                                         |
//+------------------------------------------------------------------+
bool IsManualTrade(long magic, string comment)
{
    // Consider trade as manual if magic is 0 or doesn't match EA's magic
    // and comment doesn't contain EA's trade comment
    return (magic == 0 || magic != MagicNumber) && 
           StringFind(comment, TradeComment) == -1;
}

//+------------------------------------------------------------------+
//| Check if ticket is already tracked                               |
//+------------------------------------------------------------------+
bool IsTicketTracked(ulong ticket)
{
    for(int i = 0; i < ArraySize(manualTickets); i++)
    {
        if(manualTickets[i] == ticket)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Clean up ticket array                                            |
//+------------------------------------------------------------------+
void CleanupTicketArray()
{
    // Remove closed trades from tracking array
    int size = ArraySize(manualTickets);
    if(size == 0) return;
    
    ulong tempArray[];
    ArrayResize(tempArray, 0);
    
    for(int i = 0; i < size; i++)
    {
        if(PositionSelectByTicket(manualTickets[i]))
        {
            ArrayResize(tempArray, ArraySize(tempArray) + 1);
            tempArray[ArraySize(tempArray) - 1] = manualTickets[i];
        }
    }
    
    // Copy back to original array
    ArrayCopy(manualTickets, tempArray);
    ArrayResize(manualTickets, ArraySize(tempArray));
}

//+------------------------------------------------------------------+
//| Get deinit reason text                                           |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
    switch(reason)
    {
        case REASON_ACCOUNT:    return "Account changed";
        case REASON_CHARTCHANGE:return "Chart changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_CLOSE:      return "Terminal closed";
        case REASON_INITFAILED: return "Init failed";
        case REASON_PARAMETERS: return "Parameters changed";
        case REASON_RECOMPILE:  return "Recompile";
        case REASON_REMOVE:     return "EA removed";
        case REASON_TEMPLATE:   return "Template changed";
        default:                return "Unknown reason";
    }
}

//+------------------------------------------------------------------+
//| Get retcode description                                          |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
    switch(retcode)
    {
        case 10004: return "TRADE_RETCODE_REQUOTE";
        case 10006: return "TRADE_RETCODE_REJECT";
        case 10007: return "TRADE_RETCODE_CANCEL";
        case 10008: return "TRADE_RETCODE_PLACED";
        case 10009: return "TRADE_RETCODE_DONE";
        case 10010: return "TRADE_RETCODE_DONE_PARTIAL";
        case 10011: return "TRADE_RETCODE_ERROR";
        case 10012: return "TRADE_RETCODE_TIMEOUT";
        case 10013: return "TRADE_RETCODE_INVALID";
        case 10014: return "TRADE_RETCODE_INVALID_VOLUME";
        case 10015: return "TRADE_RETCODE_INVALID_PRICE";
        case 10016: return "TRADE_RETCODE_INVALID_STOPS";
        case 10017: return "TRADE_RETCODE_TRADE_DISABLED";
        case 10018: return "TRADE_RETCODE_MARKET_CLOSED";
        case 10019: return "TRADE_RETCODE_NO_MONEY";
        case 10020: return "TRADE_RETCODE_PRICE_CHANGED";
        case 10021: return "TRADE_RETCODE_PRICE_OFF";
        case 10022: return "TRADE_RETCODE_INVALID_EXPIRATION";
        case 10023: return "TRADE_RETCODE_ORDER_CHANGED";
        case 10024: return "TRADE_RETCODE_TOO_MANY_REQUESTS";
        case 10025: return "TRADE_RETCODE_NO_CHANGES";
        case 10026: return "TRADE_RETCODE_SERVER_DISABLES_AT";
        case 10027: return "TRADE_RETCODE_CLIENT_DISABLES_AT";
        case 10028: return "TRADE_RETCODE_LOCKED";
        case 10029: return "TRADE_RETCODE_FROZEN";
        case 10030: return "TRADE_RETCODE_INVALID_FILL";
        case 10031: return "TRADE_RETCODE_CONNECTION";
        case 10032: return "TRADE_RETCODE_ONLY_REAL";
        case 10033: return "TRADE_RETCODE_LIMIT_ORDERS";
        case 10034: return "TRADE_RETCODE_LIMIT_VOLUME";
        case 10035: return "TRADE_RETCODE_INVALID_ORDER";
        case 10036: return "TRADE_RETCODE_POSITION_CLOSED";
        case 10038: return "TRADE_RETCODE_INVALID_CLOSE_VOLUME";
        case 10039: return "TRADE_RETCODE_CLOSE_ORDER_EXIST";
        case 10040: return "TRADE_RETCODE_LIMIT_POSITIONS";
        case 10041: return "TRADE_RETCODE_REJECT_CANCEL";
        case 10042: return "TRADE_RETCODE_LONG_ONLY";
        case 10043: return "TRADE_RETCODE_SHORT_ONLY";
        case 10044: return "TRADE_RETCODE_CLOSE_ONLY";
        case 10045: return "TRADE_RETCODE_FIFO_CLOSE";
        default:    return "Unknown error: " + IntegerToString(retcode);
    }
}
//+------------------------------------------------------------------+