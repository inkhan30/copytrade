//+------------------------------------------------------------------+
//|                                                  SMC_EA.mq5      |
//|                        Smart Money Concept EA with Liquidity Zones |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Smart Money Concept EA"
#property version   "1.00"
#property description "EA using SMC, Liquidity Zones, and Trend Following"

//--- Input parameters
input double   LotSize = 0.1;           // Lot size
input int      StopLoss = 200;          // Stop Loss in points
input int      TakeProfit = 400;        // Take Profit in points
input int      RSI_Period = 14;         // RSI Period
input double   RSI_Overbought = 70;     // RSI Overbought level
input double   RSI_Oversold = 30;       // RSI Oversold level
input int      Liquidity_Lookback = 100; // Bars to analyze for liquidity
input int      ATR_Period = 14;         // ATR Period for volatility
input double   Trend_Strength = 0.5;    // Minimum trend strength (0-1)

//--- Global variables
int handleRSI, handleATR;
double previousHigh[], previousLow[];
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Create indicator handles
    handleRSI = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);
    handleATR = iATR(_Symbol, _Period, ATR_Period);
    
    //--- Check if handles are created successfully
    if(handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
    {
        Print("Error creating indicator handles");
        return(INIT_FAILED);
    }
    
    //--- Initialize arrays
    ArraySetAsSeries(previousHigh, true);
    ArraySetAsSeries(previousLow, true);
    
    Print("Smart Money Concept EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
    if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if we can trade (only one position at a time)
    if(PositionsTotal() > 0) return;
    
    //--- Prevent too frequent trading
    if(TimeCurrent() - lastTradeTime < 60) return; // 1 minute cooldown
    
    //--- Get current market data
    double currentRSI = GetRSIValue(0);
    double atrValue = GetATRValue(0);
    double trendDirection = GetTrendDirection();
    
    //--- Find liquidity zones
    double liquidityHigh = FindLiquidityZoneHigh();
    double liquidityLow = FindLiquidityZoneLow();
    
    //--- Get current price levels
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    CopyRates(_Symbol, _Period, 0, 3, rates);
    
    if(ArraySize(rates) < 3) return;
    
    double currentPrice = rates[0].close;
    double previousPrice = rates[1].close;
    
    //--- Trading logic
    if(MathAbs(trendDirection) >= Trend_Strength)
    {
        //--- Bullish setup
        if(trendDirection > 0 && currentPrice > liquidityHigh)
        {
            if(IsBullishRSI(currentRSI) && IsPriceAboveTrendLine())
            {
                if(OpenBuyPosition(currentPrice, atrValue))
                    lastTradeTime = TimeCurrent();
            }
        }
        //--- Bearish setup
        else if(trendDirection < 0 && currentPrice < liquidityLow)
        {
            if(IsBearishRSI(currentRSI) && IsPriceBelowTrendLine())
            {
                if(OpenSellPosition(currentPrice, atrValue))
                    lastTradeTime = TimeCurrent();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get RSI value                                                    |
//+------------------------------------------------------------------+
double GetRSIValue(int shift)
{
    double rsi[1];
    ArraySetAsSeries(rsi, true);
    if(CopyBuffer(handleRSI, 0, shift, 1, rsi) < 1)
        return 50;
    return rsi[0];
}

//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double GetATRValue(int shift)
{
    double atr[1];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handleATR, 0, shift, 1, atr) < 1)
        return 0;
    return atr[0];
}

//+------------------------------------------------------------------+
//| Find liquidity zone - High                                       |
//+------------------------------------------------------------------+
double FindLiquidityZoneHigh()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, Liquidity_Lookback, rates) < Liquidity_Lookback)
        return 0;
    
    double highPrices[];
    ArrayResize(highPrices, Liquidity_Lookback);
    
    for(int i = 0; i < Liquidity_Lookback; i++)
        highPrices[i] = rates[i].high;
    
    ArraySort(highPrices);
    
    //--- Return the median high price as liquidity zone
    return highPrices[Liquidity_Lookback / 2];
}

//+------------------------------------------------------------------+
//| Find liquidity zone - Low                                        |
//+------------------------------------------------------------------+
double FindLiquidityZoneLow()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, Liquidity_Lookback, rates) < Liquidity_Lookback)
        return 0;
    
    double lowPrices[];
    ArrayResize(lowPrices, Liquidity_Lookback);
    
    for(int i = 0; i < Liquidity_Lookback; i++)
        lowPrices[i] = rates[i].low;
    
    ArraySort(lowPrices);
    
    //--- Return the median low price as liquidity zone
    return lowPrices[Liquidity_Lookback / 2];
}

//+------------------------------------------------------------------+
//| Get trend direction using linear regression                      |
//+------------------------------------------------------------------+
double GetTrendDirection()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 50, rates) < 50)
        return 0;

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    int n = MathMin(50, ArraySize(rates));
    
    for(int i = 0; i < n; i++)
    {
        sumX += i;
        sumY += rates[i].close;
        sumXY += i * rates[i].close;
        sumX2 += i * i;
    }
    
    double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    
    // Normalize slope to -1 to 1 range
    return MathTanh(slope * 1000);
}

//+------------------------------------------------------------------+
//| Check if price is above trend line (simplified)                  |
//+------------------------------------------------------------------+
bool IsPriceAboveTrendLine()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(_Symbol, _Period, 0, 3, rates) < 3)
        return false;
    
    double trendDirection = GetTrendDirection();
    
    // Simple trend line check - if bullish, current price should be above previous
    if(trendDirection > 0)
        return rates[0].close > rates[1].close;
    else
        return rates[0].close < rates[1].close;
}

//+------------------------------------------------------------------+
//| Check if price is below trend line (simplified)                  |
//+------------------------------------------------------------------+
bool IsPriceBelowTrendLine()
{
    return !IsPriceAboveTrendLine();
}

//+------------------------------------------------------------------+
//| Check RSI for bullish condition                                  |
//+------------------------------------------------------------------+
bool IsBullishRSI(double rsi)
{
    return (rsi > RSI_Oversold && rsi < RSI_Overbought);
}

//+------------------------------------------------------------------+
//| Check RSI for bearish condition                                  |
//+------------------------------------------------------------------+
bool IsBearishRSI(double rsi)
{
    return (rsi < RSI_Overbought && rsi > RSI_Oversold);
}

//+------------------------------------------------------------------+
//| Open buy position                                                |
//+------------------------------------------------------------------+
bool OpenBuyPosition(double entryPrice, double atrValue)
{
    double sl = entryPrice - StopLoss * _Point;
    double tp = entryPrice + TakeProfit * _Point;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = NormalizeDouble(entryPrice, _Digits);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "SMC Buy";
    
    return SendOrder(request, result);
}

//+------------------------------------------------------------------+
//| Open sell position                                               |
//+------------------------------------------------------------------+
bool OpenSellPosition(double entryPrice, double atrValue)
{
    double sl = entryPrice + StopLoss * _Point;
    double tp = entryPrice - TakeProfit * _Point;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = NormalizeDouble(entryPrice, _Digits);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "SMC Sell";
    
    return SendOrder(request, result);
}

//+------------------------------------------------------------------+
//| Custom OrderSend function to avoid naming conflict               |
//+------------------------------------------------------------------+
bool SendOrder(MqlTradeRequest &request, MqlTradeResult &result)
{
    bool success = OrderSend(request, result);
    
    if(!success)
    {
        Print("OrderSend error: ", GetLastError());
        Print("Retcode: ", result.retcode, ", Deal: ", result.deal, ", Order: ", result.order);
    }
    else
    {
        Print("Order opened successfully: ", request.comment);
        Print("Price: ", request.price, ", SL: ", request.sl, ", TP: ", request.tp);
    }
    
    return success;
}