//+------------------------------------------------------------------+
//|                                                  FiveMinuteEA.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   LotSize = 0.1;                // Trade lot size
input int      EMA_Period = 55;              // EMA period
input int      SMA_Period = 200;             // SMA period (H1)
input double   VolumeSpikeRatio = 1.5;       // Volume spike ratio (150%)
input int      VolumeLookback = 20;          // Volume lookback period
input int      StopLossPips = 15;            // Stop loss in pips
input double   RiskRewardRatio = 1.5;        // Risk reward ratio
input int      PartialClosePercent = 70;     // Partial close percentage
input bool     UseTrailingStop = true;       // Use trailing stop to BE
input int      MagicNumber = 12345;          // Magic number for trades

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int ema_high_handle, ema_low_handle, sma_handle;
double heikin_ashi_open[3], heikin_ashi_high[3], heikin_ashi_low[3], heikin_ashi_close[3];
datetime last_trade_time = 0;
string trade_comment = "5MinStrategy";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Create indicator handles
    ema_high_handle = iMA(_Symbol, PERIOD_M5, EMA_Period, 0, MODE_EMA, PRICE_HIGH);
    ema_low_handle = iMA(_Symbol, PERIOD_M5, EMA_Period, 0, MODE_EMA, PRICE_LOW);
    sma_handle = iMA(_Symbol, PERIOD_H1, SMA_Period, 0, MODE_SMA, PRICE_CLOSE);
    
    if(ema_high_handle == INVALID_HANDLE || ema_low_handle == INVALID_HANDLE || sma_handle == INVALID_HANDLE)
    {
        Print("Error creating indicator handles");
        return(INIT_FAILED);
    }
    
    // Initialize Heikin Ashi arrays as series
    ArraySetAsSeries(heikin_ashi_open, true);
    ArraySetAsSeries(heikin_ashi_high, true);
    ArraySetAsSeries(heikin_ashi_low, true);
    ArraySetAsSeries(heikin_ashi_close, true);
    
    Print("EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ema_high_handle != INVALID_HANDLE) IndicatorRelease(ema_high_handle);
    if(ema_low_handle != INVALID_HANDLE) IndicatorRelease(ema_low_handle);
    if(sma_handle != INVALID_HANDLE) IndicatorRelease(sma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    if(!IsNewBar())
        return;
        
    // Check if we can trade
    if(!CheckTradeConditions())
        return;
    
    // Get indicator values
    double ema_high = GetEMAHigh();
    double ema_low = GetEMALow();
    double sma_value = GetSMA();
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate Heikin Ashi values
    CalculateHeikinAshi();
    
    // Check volume spike
    bool volume_spike = CheckVolumeSpike();
    
    // Check trading signals
    CheckForSignals(current_price, ema_high, ema_low, sma_value, volume_spike);
    
    // Manage existing trades
    ManageTrades();
}

//+------------------------------------------------------------------+
//| Check if new bar has formed                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, PERIOD_M5, 0);
    
    if(current_bar_time != last_bar_time)
    {
        last_bar_time = current_bar_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check basic trade conditions                                     |
//+------------------------------------------------------------------+
bool CheckTradeConditions()
{
    // Check if market is open
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL)
        return false;
        
    // Check margin requirements
    double margin_required;
    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, LotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin_required))
        return false;
        
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    if(free_margin < margin_required)
        return false;
        
    return true;
}

//+------------------------------------------------------------------+
//| Get EMA High value                                               |
//+------------------------------------------------------------------+
double GetEMAHigh()
{
    double ema[1];
    if(CopyBuffer(ema_high_handle, 0, 0, 1, ema) < 1)
        return 0;
    return ema[0];
}

//+------------------------------------------------------------------+
//| Get EMA Low value                                                |
//+------------------------------------------------------------------+
double GetEMALow()
{
    double ema[1];
    if(CopyBuffer(ema_low_handle, 0, 0, 1, ema) < 1)
        return 0;
    return ema[0];
}

//+------------------------------------------------------------------+
//| Get SMA value                                                    |
//+------------------------------------------------------------------+
double GetSMA()
{
    double sma[1];
    if(CopyBuffer(sma_handle, 0, 0, 1, sma) < 1)
        return 0;
    return sma[0];
}

//+------------------------------------------------------------------+
//| Calculate Heikin Ashi values                                     |
//+------------------------------------------------------------------+
void CalculateHeikinAshi()
{
    double open[3], high[3], low[3], close[3];
    
    // Copy price data for last 3 candles
    if(CopyOpen(_Symbol, PERIOD_M5, 0, 3, open) < 3) return;
    if(CopyHigh(_Symbol, PERIOD_M5, 0, 3, high) < 3) return;
    if(CopyLow(_Symbol, PERIOD_M5, 0, 3, low) < 3) return;
    if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close) < 3) return;
    
    // Set arrays as series for easier indexing
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    // Calculate Heikin Ashi for current candle (index 0)
    heikin_ashi_open[0] = (heikin_ashi_open[1] + heikin_ashi_close[1]) / 2;
    heikin_ashi_close[0] = (open[0] + high[0] + low[0] + close[0]) / 4;
    heikin_ashi_high[0] = MathMax(high[0], MathMax(heikin_ashi_open[0], heikin_ashi_close[0]));
    heikin_ashi_low[0] = MathMin(low[0], MathMin(heikin_ashi_open[0], heikin_ashi_close[0]));
}

//+------------------------------------------------------------------+
//| Check for volume spike                                           |
//+------------------------------------------------------------------+
bool CheckVolumeSpike()
{
    long volume[];
    ArraySetAsSeries(volume, true);
    
    if(CopyTickVolume(_Symbol, PERIOD_M5, 0, VolumeLookback + 1, volume) < VolumeLookback + 1)
        return false;
    
    // Calculate average volume of last 20 candles (excluding current)
    long sum_volume = 0;
    for(int i = 1; i <= VolumeLookback; i++)
    {
        if(i < ArraySize(volume))
            sum_volume += volume[i];
    }
    
    if(VolumeLookback == 0) return false;
    
    double avg_volume = (double)sum_volume / VolumeLookback;
    double current_volume = (volume[0] > 0) ? (double)volume[0] : 1.0;
    
    return (current_volume >= avg_volume * VolumeSpikeRatio);
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckForSignals(double current_price, double ema_high, double ema_low, double sma_value, bool volume_spike)
{
    if(ema_high == 0 || ema_low == 0 || sma_value == 0) return;
    
    // Check Heikin Ashi color change (comparing current and previous candle)
    bool ha_bullish = heikin_ashi_close[0] > heikin_ashi_open[0];
    bool ha_previous_bullish = heikin_ashi_close[1] > heikin_ashi_open[1];
    bool ha_color_changed = (ha_bullish != ha_previous_bullish);
    
    if(!ha_color_changed || !volume_spike)
        return;
    
    // Check LONG conditions
    if(ha_bullish && current_price > sma_value && current_price > ema_high)
    {
        if(CountPositions(ORDER_TYPE_BUY) == 0)
            OpenLongPosition();
    }
    // Check SHORT conditions
    else if(!ha_bullish && current_price < sma_value && current_price < ema_low)
    {
        if(CountPositions(ORDER_TYPE_SELL) == 0)
            OpenShortPosition();
    }
}

//+------------------------------------------------------------------+
//| Open long position                                               |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    double stop_loss = iLow(_Symbol, PERIOD_M5, 1); // Previous candle's low
    double take_profit = ask + (ask - stop_loss) * RiskRewardRatio;
    
    // Adjust for 5-digit brokers
    if(digits == 5 || digits == 3)
    {
        stop_loss = NormalizeDouble(stop_loss, digits);
        take_profit = NormalizeDouble(take_profit, digits);
    }
    
    MqlTradeRequest request = {0};
    MqlTradeResult result = {0};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = stop_loss;
    request.tp = take_profit;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = trade_comment;
    
    if(OrderSend(request, result))
    {
        Print("Long position opened. Ticket: ", result.order);
    }
    else
    {
        Print("Error opening long position: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Open short position                                              |
//+------------------------------------------------------------------+
void OpenShortPosition()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    double stop_loss = iHigh(_Symbol, PERIOD_M5, 1); // Previous candle's high
    double take_profit = bid - (stop_loss - bid) * RiskRewardRatio;
    
    // Adjust for 5-digit brokers
    if(digits == 5 || digits == 3)
    {
        stop_loss = NormalizeDouble(stop_loss, digits);
        take_profit = NormalizeDouble(take_profit, digits);
    }
    
    MqlTradeRequest request = {0};
    MqlTradeResult result = {0};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = bid;
    request.sl = stop_loss;
    request.tp = take_profit;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = trade_comment;
    
    if(OrderSend(request, result))
    {
        Print("Short position opened. Ticket: ", result.order);
    }
    else
    {
        Print("Error opening short position: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Count positions by type                                          |
//+------------------------------------------------------------------+
int CountPositions(ENUM_ORDER_TYPE type)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage existing trades                                           |
//+------------------------------------------------------------------+
void ManageTrades()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                ManagePosition(PositionGetInteger(POSITION_TICKET));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage individual position                                       |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    double current_sl = PositionGetDouble(POSITION_SL);
    double current_tp = PositionGetDouble(POSITION_TP);
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    double volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate risk (distance from open to initial SL)
    double risk = 0;
    if(type == POSITION_TYPE_BUY)
        risk = open_price - current_sl;
    else if(type == POSITION_TYPE_SELL)
        risk = current_sl - open_price;
    
    if(risk <= 0) return;
    
    // Calculate target 1 level
    double target1 = 0;
    if(type == POSITION_TYPE_BUY)
        target1 = open_price + risk * RiskRewardRatio;
    else if(type == POSITION_TYPE_SELL)
        target1 = open_price - risk * RiskRewardRatio;
    
    // Check if we should close 70% at target 1
    if((type == POSITION_TYPE_BUY && current_price >= target1 && current_sl < open_price) ||
       (type == POSITION_TYPE_SELL && current_price <= target1 && current_sl > open_price))
    {
        // Close 70% of position
        double close_volume = NormalizeDouble(volume * PartialClosePercent / 100.0, 2);
        
        MqlTradeRequest request = {0};
        MqlTradeResult result = {0};
        
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.volume = close_volume;
        request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.deviation = 10;
        request.magic = MagicNumber;
        request.comment = "Partial close 70%";
        
        if(OrderSend(request, result))
        {
            Print("Partial close executed. Volume: ", close_volume);
            
            // Move stop to breakeven for remaining position
            if(UseTrailingStop)
            {
                MqlTradeRequest modify_request = {0};
                MqlTradeResult modify_result = {0};
                
                modify_request.action = TRADE_ACTION_SLTP;
                modify_request.position = ticket;
                modify_request.symbol = _Symbol;
                modify_request.sl = open_price;
                modify_request.tp = 0; // Remove TP to let it run
                modify_request.magic = MagicNumber;
                
                if(!OrderSend(modify_request, modify_result))
                {
                    Print("Error moving SL to breakeven: ", GetLastError());
                }
            }
        }
    }
    
    // Check for Heikin Ashi reversal for remaining 30%
    if(current_sl == open_price) // Only check if we're in BE mode
    {
        bool ha_bullish = heikin_ashi_close[0] > heikin_ashi_open[0];
        bool ha_previous_bullish = heikin_ashi_close[1] > heikin_ashi_open[1];
        bool ha_reversal = (ha_bullish != ha_previous_bullish);
        
        // Check if reversal contradicts our position direction
        if(ha_reversal)
        {
            if((type == POSITION_TYPE_BUY && !ha_bullish) ||
               (type == POSITION_TYPE_SELL && ha_bullish))
            {
                // Close remaining position
                MqlTradeRequest request = {0};
                MqlTradeResult result = {0};
                
                request.action = TRADE_ACTION_DEAL;
                request.position = ticket;
                request.symbol = _Symbol;
                request.volume = volume;
                request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                request.price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                request.deviation = 10;
                request.magic = MagicNumber;
                request.comment = "HA reversal close";
                
                if(OrderSend(request, result))
                {
                    Print("Position closed due to Heikin Ashi reversal");
                }
            }
        }
    }
}
//+------------------------------------------------------------------+