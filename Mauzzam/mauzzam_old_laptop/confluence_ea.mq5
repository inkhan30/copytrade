//+------------------------------------------------------------------+
//|                                              XAUUSD_ConfluenceEA |
//|                                     Copyright 2024, Expert Advisor|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Expert Advisor"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property description "XAUUSD Confluence Trading EA"
#property description "Uses S/R, RSI, MACD, Volume, Price Action & Trend Filters"
#property strict

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- Trading Settings
input int    MagicNumber = 12345;           // Magic Number
input bool   EnableBuyOrders = true;        // Enable Buy Orders
input bool   EnableSellOrders = true;       // Enable Sell Orders
input int    MaxOpenPositions = 3;          // Maximum Open Positions
input int    OrderRetryCount = 3;           // Order Retry Count
input int    OrderRetryDelay = 300;         // Order Retry Delay (ms)

//--- Position Sizing
enum ENUM_LOT_TYPE {
   LOT_FIXED,      // Fixed Lot Size
   LOT_RISK_BASED  // Risk-Based Lot Size
};
input ENUM_LOT_TYPE LotType = LOT_RISK_BASED; // Position Sizing Method
input double FixedLotSize = 0.01;             // Fixed Lot Size
input double RiskPercentage = 1.0;            // Risk Percentage per Trade
input double MinLotSize = 0.01;               // Minimum Lot Size
input double MaxLotSize = 1.00;               // Maximum Lot Size

//--- Risk Management
input int    StopLossPips = 200;             // Stop Loss (Pips)
input int    TakeProfitPips = 400;           // Take Profit (Pips)
input bool   UseATRForSLTP = true;          // Use ATR for SL/TP
input double ATRMultiplierSL = 2.0;          // ATR Multiplier for SL
input double ATRMultiplierTP = 4.0;          // ATR Multiplier for TP
input bool   UseTrailingStop = false;        // Enable Trailing Stop
input int    TrailingStopPips = 100;         // Trailing Stop Distance (Pips)
input int    BreakevenPips = 50;             // Breakeven Trigger (Pips)

//--- Indicator Settings
input int    RSIPeriod = 14;                 // RSI Period
input double RSIOverbought = 70.0;           // RSI Overbought Level
input double RSIOversold = 30.0;             // RSI Oversold Level
input bool   UseRSIDivergence = true;        // Enable RSI Divergence

input int    FastEMA = 12;                   // MACD Fast EMA
input int    SlowEMA = 26;                   // MACD Slow EMA
input int    SignalSMA = 9;                  // MACD Signal SMA
input bool   UseMACDDivergence = true;       // Enable MACD Divergence

input int    ATRPeriod = 14;                 // ATR Period

//--- Trend Filter Settings
input bool   EnableTrendFilter = true;       // Enable Trend Filter
input ENUM_MA_METHOD MATrendMethod = MODE_EMA; // MA Method for Trend
input int    MATrendFastPeriod = 20;         // Fast MA for Trend
input int    MATrendSlowPeriod = 50;         // Slow MA for Trend
input int    ADXPeriod = 14;                 // ADX Period for Trend Strength
input double ADXThreshold = 25.0;            // Minimum ADX for Trend
input bool   UsePriceActionTrend = true;     // Use Price Action for Trend
input int    TrendLookbackBars = 50;         // Bars to analyze for trend
input double MinTrendAngle = 15.0;           // Minimum angle for trend (degrees)
input bool   UseHigherTimeframeTrend = true; // Use higher timeframe trend
input ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H4; // Higher timeframe for trend

//--- Support/Resistance Settings
input int    SRLookback = 100;               // S/R Lookback Period
input double SRZonePips = 50.0;              // S/R Zone Width (Pips)
input int    PivotPointsPeriod = 1;          // Pivot Points Period (Days)
input bool   UseDynamicSR = true;            // Use Dynamic S/R Levels

//--- Volume Settings
input int    VolumeLookback = 20;            // Volume Lookback Period
input double VolumeSpikeMultiplier = 2.0;    // Volume Spike Threshold

//--- Time Settings
input bool   TradeSessionOnly = true;        // Trade Only During Session
input int    SessionStartHour = 1;           // Session Start Hour (GMT)
input int    SessionEndHour = 23;            // Session End Hour (GMT)

//--- Entry Conditions
input int    RequiredConfirmations = 3;      // Minimum Confirmations Required
input bool   RequireTrendConfirmation = true; // Require trend for entry

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
double pipValue;
int totalConfirmations = 0;
datetime lastTradeTime = 0;
ulong orderTicket = 0;
bool newBarFlag = false;

//--- Indicator handles
int rsiHandle;
int macdHandle;
int atrHandle;
int maHandle50;
int maFastHandle;
int maSlowHandle;
int adxHandle;

//--- Higher timeframe indicator handles
int rsiHTFHandle;
int maFastHTFHandle;
int maSlowHTFHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate pip value for XAUUSD (Gold)
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   pipValue = (tickValue / tickSize) * 10.0; // For XAUUSD, 1 pip = 10 points
   
   // Create indicator handles for current timeframe
   rsiHandle = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   macdHandle = iMACD(_Symbol, _Period, FastEMA, SlowEMA, SignalSMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, ATRPeriod);
   maHandle50 = iMA(_Symbol, _Period, 50, 0, MODE_SMA, PRICE_CLOSE);
   maFastHandle = iMA(_Symbol, _Period, MATrendFastPeriod, 0, MATrendMethod, PRICE_CLOSE);
   maSlowHandle = iMA(_Symbol, _Period, MATrendSlowPeriod, 0, MATrendMethod, PRICE_CLOSE);
   adxHandle = iADX(_Symbol, _Period, ADXPeriod);
   
   // Create higher timeframe indicators if needed
   if(UseHigherTimeframeTrend)
   {
      rsiHTFHandle = iRSI(_Symbol, HigherTimeframe, RSIPeriod, PRICE_CLOSE);
      maFastHTFHandle = iMA(_Symbol, HigherTimeframe, MATrendFastPeriod, 0, MATrendMethod, PRICE_CLOSE);
      maSlowHTFHandle = iMA(_Symbol, HigherTimeframe, MATrendSlowPeriod, 0, MATrendMethod, PRICE_CLOSE);
   }
   
   // Check if handles are valid
   if(rsiHandle == INVALID_HANDLE || macdHandle == INVALID_HANDLE || 
      atrHandle == INVALID_HANDLE || maHandle50 == INVALID_HANDLE ||
      maFastHandle == INVALID_HANDLE || maSlowHandle == INVALID_HANDLE ||
      adxHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }
   
   if(UseHigherTimeframeTrend && 
      (rsiHTFHandle == INVALID_HANDLE || maFastHTFHandle == INVALID_HANDLE || maSlowHTFHandle == INVALID_HANDLE))
   {
      Print("Error creating higher timeframe indicator handles");
      return INIT_FAILED;
   }
   
   // Check if terminal is connected to trade server
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("Trading is not allowed. Check terminal settings.");
      return INIT_FAILED;
   }
   
   // Check for enough bars
   int minBars = MathMax(SRLookback, MathMax(RSIPeriod, ATRPeriod)) * 2;
   minBars = MathMax(minBars, TrendLookbackBars);
   if(Bars(_Symbol, _Period) < minBars)
   {
      Alert("Not enough historical data. Need at least ", minBars, " bars.");
      return INIT_FAILED;
   }
   
   Print("EA initialized successfully for ", _Symbol);
   Print("Account Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("Account Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("Pip Value: ", pipValue);
   Print("Trend Filter: ", EnableTrendFilter ? "Enabled" : "Disabled");
   if(EnableTrendFilter) Print("ADX Threshold: ", ADXThreshold);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(macdHandle != INVALID_HANDLE) IndicatorRelease(macdHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(maHandle50 != INVALID_HANDLE) IndicatorRelease(maHandle50);
   if(maFastHandle != INVALID_HANDLE) IndicatorRelease(maFastHandle);
   if(maSlowHandle != INVALID_HANDLE) IndicatorRelease(maSlowHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   
   if(UseHigherTimeframeTrend)
   {
      if(rsiHTFHandle != INVALID_HANDLE) IndicatorRelease(rsiHTFHandle);
      if(maFastHTFHandle != INVALID_HANDLE) IndicatorRelease(maFastHTFHandle);
      if(maSlowHTFHandle != INVALID_HANDLE) IndicatorRelease(maSlowHTFHandle);
   }
   
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(!IsNewBar())
      return;
   
   // Check trading session
   if(TradeSessionOnly && !IsTradingSession())
      return;
   
   // Check max positions
   if(CountOpenPositions() >= MaxOpenPositions)
      return;
   
   // Reset confirmations counter
   totalConfirmations = 0;
   
   // Check market trend first (if enabled)
   bool marketIsTrending = true;
   if(EnableTrendFilter)
   {
      marketIsTrending = CheckMarketTrend();
      if(!marketIsTrending && RequireTrendConfirmation)
      {
         Print("Market is not trending. No trades allowed.");
         return;
      }
   }
   
   // Check entry conditions for both directions
   bool buySignal = false;
   bool sellSignal = false;
   
   if(EnableBuyOrders)
      buySignal = CheckBuyConditions();
   
   if(EnableSellOrders)
      sellSignal = CheckSellConditions();
   
   // Execute trades if conditions met and market is trending (if required)
   if(buySignal && totalConfirmations >= RequiredConfirmations)
   {
      // Additional trend direction check for buys
      if(!RequireTrendConfirmation || (marketIsTrending && IsUptrend()))
      {
         ExecuteBuyOrder();
         lastTradeTime = TimeCurrent();
      }
   }
   else if(sellSignal && totalConfirmations >= RequiredConfirmations)
   {
      // Additional trend direction check for sells
      if(!RequireTrendConfirmation || (marketIsTrending && IsDowntrend()))
      {
         ExecuteSellOrder();
         lastTradeTime = TimeCurrent();
      }
   }
   
   // Manage open positions
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
//| Trend Detection Functions                                        |
//+------------------------------------------------------------------+
bool CheckMarketTrend()
{
   int trendConfirmations = 0;
   int requiredTrendConfirmations = 2; // Require at least 2 trend confirmations
   
   // 1. ADX Trend Strength Filter
   if(CheckADXTrendStrength())
   {
      trendConfirmations++;
      Print("Trend Confirmation 1: ADX shows trending market");
   }
   
   // 2. Moving Average Trend Filter
   if(CheckMATrend())
   {
      trendConfirmations++;
      Print("Trend Confirmation 2: Moving Averages show trend");
   }
   
   // 3. Price Action Trend Filter
   if(UsePriceActionTrend && CheckPriceActionTrend())
   {
      trendConfirmations++;
      Print("Trend Confirmation 3: Price action confirms trend");
   }
   
   // 4. Higher Timeframe Trend Filter
   if(UseHigherTimeframeTrend && CheckHigherTimeframeTrend())
   {
      trendConfirmations++;
      Print("Trend Confirmation 4: Higher timeframe confirms trend");
   }
   
   // 5. Trend Line Angle Filter
   if(CalculateTrendAngle() >= MinTrendAngle)
   {
      trendConfirmations++;
      Print("Trend Confirmation 5: Trend angle meets minimum requirement");
   }
   
   return (trendConfirmations >= requiredTrendConfirmations);
}

bool CheckADXTrendStrength()
{
   double adxBuffer[];
   double plusDIbuffer[];
   double minusDIbuffer[];
   ArraySetAsSeries(adxBuffer, true);
   ArraySetAsSeries(plusDIbuffer, true);
   ArraySetAsSeries(minusDIbuffer, true);
   
   if(CopyBuffer(adxHandle, 0, 0, 3, adxBuffer) < 3) return false; // ADX line
   if(CopyBuffer(adxHandle, 1, 0, 3, plusDIbuffer) < 3) return false; // +DI line
   if(CopyBuffer(adxHandle, 2, 0, 3, minusDIbuffer) < 3) return false; // -DI line
   
   double adxCurrent = adxBuffer[0];
   double plusDICurrent = plusDIbuffer[0];
   double minusDICurrent = minusDIbuffer[0];
   
   // Check if ADX is above threshold (strong trend)
   if(adxCurrent < ADXThreshold) return false;
   
   // Check if there's a clear trend direction
   if(MathAbs(plusDICurrent - minusDICurrent) < 5.0) return false; // Too close, no clear trend
   
   // Check if ADX is rising (increasing trend strength)
   if(adxBuffer[0] < adxBuffer[1]) return false;
   
   return true;
}

bool CheckMATrend()
{
   double maFastBuffer[], maSlowBuffer[];
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   
   if(CopyBuffer(maFastHandle, 0, 0, 2, maFastBuffer) < 2) return false;
   if(CopyBuffer(maSlowHandle, 0, 0, 2, maSlowBuffer) < 2) return false;
   
   double maFastCurrent = maFastBuffer[0];
   double maSlowCurrent = maSlowBuffer[0];
   
   // Get current price
   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2.0;
   
   // Check if price is above/below both MAs (strong trend)
   if(IsUptrend())
   {
      return (currentPrice > maFastCurrent && maFastCurrent > maSlowCurrent);
   }
   else if(IsDowntrend())
   {
      return (currentPrice < maFastCurrent && maFastCurrent < maSlowCurrent);
   }
   
   return false;
}

bool CheckPriceActionTrend()
{
   // Analyze last N bars for trend using price action
   double highs[], lows[];
   ArrayResize(highs, TrendLookbackBars);
   ArrayResize(lows, TrendLookbackBars);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   
   // Copy high and low prices
   for(int i = 0; i < TrendLookbackBars; i++)
   {
      highs[i] = iHigh(_Symbol, _Period, i);
      lows[i] = iLow(_Symbol, _Period, i);
   }
   
   // Calculate higher highs and higher lows for uptrend
   int higherHighs = 0;
   int higherLows = 0;
   int lowerHighs = 0;
   int lowerLows = 0;
   
   for(int i = 1; i < TrendLookbackBars - 1; i++)
   {
      // Check for higher highs
      if(highs[i] > highs[i+1]) higherHighs++;
      else if(highs[i] < highs[i+1]) lowerHighs++;
      
      // Check for higher lows
      if(lows[i] > lows[i+1]) higherLows++;
      else if(lows[i] < lows[i+1]) lowerLows++;
   }
   
   // Determine trend based on price action
   double trendScore = 0;
   if(higherHighs > lowerHighs * 1.5 && higherLows > lowerLows * 1.5)
   {
      trendScore = (double)(higherHighs + higherLows) / (TrendLookbackBars * 2.0);
   }
   else if(lowerHighs > higherHighs * 1.5 && lowerLows > higherLows * 1.5)
   {
      trendScore = (double)(lowerHighs + lowerLows) / (TrendLookbackBars * 2.0);
   }
   
   return (trendScore > 0.6); // At least 60% consistency in trend
}

bool CheckHigherTimeframeTrend()
{
   double maFastHTFBuffer[], maSlowHTFBuffer[];
   ArraySetAsSeries(maFastHTFBuffer, true);
   ArraySetAsSeries(maSlowHTFBuffer, true);
   
   if(CopyBuffer(maFastHTFHandle, 0, 0, 2, maFastHTFBuffer) < 2) return false;
   if(CopyBuffer(maSlowHTFHandle, 0, 0, 2, maSlowHTFBuffer) < 2) return false;
   
   double maFastHTFCurrent = maFastHTFBuffer[0];
   double maSlowHTFCurrent = maSlowHTFBuffer[0];
   
   // Check if higher timeframe shows trend
   if(maFastHTFCurrent > maSlowHTFCurrent && maFastHTFBuffer[0] > maFastHTFBuffer[1])
   {
      // Uptrend on higher timeframe
      return true;
   }
   else if(maFastHTFCurrent < maSlowHTFCurrent && maFastHTFBuffer[0] < maFastHTFBuffer[1])
   {
      // Downtrend on higher timeframe
      return true;
   }
   
   return false;
}

double CalculateTrendAngle()
{
   // Calculate trend angle using linear regression
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
   int n = TrendLookbackBars;
   
   for(int i = 0; i < n; i++)
   {
      double price = iClose(_Symbol, _Period, i);
      sumX += i;
      sumY += price;
      sumXY += i * price;
      sumX2 += i * i;
   }
   
   double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
   
   // Convert slope to angle in degrees
   double angle = MathArctan(slope) * 180.0 / M_PI;
   
   return MathAbs(angle);
}

bool IsUptrend()
{
   double maFastBuffer[], maSlowBuffer[];
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   
   if(CopyBuffer(maFastHandle, 0, 0, 2, maFastBuffer) < 2) return false;
   if(CopyBuffer(maSlowHandle, 0, 0, 2, maSlowBuffer) < 2) return false;
   
   // Check if fast MA is above slow MA and both are rising
   bool maAlignment = (maFastBuffer[0] > maSlowBuffer[0]);
   bool maDirection = (maFastBuffer[0] > maFastBuffer[1] && maSlowBuffer[0] > maSlowBuffer[1]);
   
   // Check ADX +DI vs -DI
   double plusDIbuffer[], minusDIbuffer[];
   ArraySetAsSeries(plusDIbuffer, true);
   ArraySetAsSeries(minusDIbuffer, true);
   
   if(CopyBuffer(adxHandle, 1, 0, 1, plusDIbuffer) < 1) return false;
   if(CopyBuffer(adxHandle, 2, 0, 1, minusDIbuffer) < 1) return false;
   
   bool diAlignment = (plusDIbuffer[0] > minusDIbuffer[0]);
   
   return (maAlignment && maDirection && diAlignment);
}

bool IsDowntrend()
{
   double maFastBuffer[], maSlowBuffer[];
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   
   if(CopyBuffer(maFastHandle, 0, 0, 2, maFastBuffer) < 2) return false;
   if(CopyBuffer(maSlowHandle, 0, 0, 2, maSlowBuffer) < 2) return false;
   
   // Check if fast MA is below slow MA and both are falling
   bool maAlignment = (maFastBuffer[0] < maSlowBuffer[0]);
   bool maDirection = (maFastBuffer[0] < maFastBuffer[1] && maSlowBuffer[0] < maSlowBuffer[1]);
   
   // Check ADX +DI vs -DI
   double plusDIbuffer[], minusDIbuffer[];
   ArraySetAsSeries(plusDIbuffer, true);
   ArraySetAsSeries(minusDIbuffer, true);
   
   if(CopyBuffer(adxHandle, 1, 0, 1, plusDIbuffer) < 1) return false;
   if(CopyBuffer(adxHandle, 2, 0, 1, minusDIbuffer) < 1) return false;
   
   bool diAlignment = (plusDIbuffer[0] < minusDIbuffer[0]);
   
   return (maAlignment && maDirection && diAlignment);
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      newBarFlag = true;
      return true;
   }
   newBarFlag = false;
   return false;
}

//+------------------------------------------------------------------+
//| Check if within trading session                                  |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime timeNow;
   TimeToStruct(TimeCurrent(), timeNow);
   
   int currentHour = timeNow.hour;
   
   return (currentHour >= SessionStartHour && currentHour <= SessionEndHour);
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         
         if(symbol == _Symbol && magic == MagicNumber)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Check buy conditions (Enhanced with trend direction)            |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
{
   int confirmations = 0;
   
   // Check trend direction first if required
   if(RequireTrendConfirmation && !IsUptrend())
   {
      Print("Buy Condition: Market is not in uptrend. Skipping buy.");
      return false;
   }
   
   // 1. Support/Resistance Check
   if(CheckSupportLevel())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 1: Price at Support Level");
   }
   
   // 2. RSI Check (only oversold in uptrend)
   if(CheckRSIBuy())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 2: RSI Oversold/Bullish Divergence");
   }
   
   // 3. MACD Check (only bullish signals in uptrend)
   if(CheckMACDBuy())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 3: MACD Bullish Signal");
   }
   
   // 4. Volume Check
   if(CheckVolumeBuy())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 4: Volume Confirmation");
   }
   
   // 5. Price Action Check
   if(CheckPriceActionBuy())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 5: Bullish Price Action Pattern");
   }
   
   // 6. Trend Pullback Check (for buy in uptrend)
   if(CheckTrendPullbackBuy())
   {
      confirmations++;
      totalConfirmations++;
      Print("Buy Confirmation 6: Trend Pullback Opportunity");
   }
   
   return (confirmations >= RequiredConfirmations);
}

//+------------------------------------------------------------------+
//| Check sell conditions (Enhanced with trend direction)           |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
   int confirmations = 0;
   
   // Check trend direction first if required
   if(RequireTrendConfirmation && !IsDowntrend())
   {
      Print("Sell Condition: Market is not in downtrend. Skipping sell.");
      return false;
   }
   
   // 1. Support/Resistance Check
   if(CheckResistanceLevel())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 1: Price at Resistance Level");
   }
   
   // 2. RSI Check (only overbought in downtrend)
   if(CheckRSISell())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 2: RSI Overbought/Bearish Divergence");
   }
   
   // 3. MACD Check (only bearish signals in downtrend)
   if(CheckMACDSell())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 3: MACD Bearish Signal");
   }
   
   // 4. Volume Check
   if(CheckVolumeSell())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 4: Volume Confirmation");
   }
   
   // 5. Price Action Check
   if(CheckPriceActionSell())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 5: Bearish Price Action Pattern");
   }
   
   // 6. Trend Pullback Check (for sell in downtrend)
   if(CheckTrendPullbackSell())
   {
      confirmations++;
      totalConfirmations++;
      Print("Sell Confirmation 6: Trend Pullback Opportunity");
   }
   
   return (confirmations >= RequiredConfirmations);
}

//+------------------------------------------------------------------+
//| Trend Pullback Functions                                        |
//+------------------------------------------------------------------+
bool CheckTrendPullbackBuy()
{
   // Check if price is pulling back to support in an uptrend
   double maFastBuffer[], maSlowBuffer[];
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   
   if(CopyBuffer(maFastHandle, 0, 0, 5, maFastBuffer) < 5) return false;
   if(CopyBuffer(maSlowHandle, 0, 0, 5, maSlowBuffer) < 5) return false;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double maFastCurrent = maFastBuffer[0];
   
   // Check if price has pulled back to fast MA (support in uptrend)
   if(currentPrice <= maFastCurrent * 1.01 && currentPrice >= maFastCurrent * 0.99)
   {
      // Check if MA is still rising (uptrend intact)
      if(maFastBuffer[0] > maFastBuffer[2] && maSlowBuffer[0] > maSlowBuffer[2])
      {
         return true;
      }
   }
   
   return false;
}

bool CheckTrendPullbackSell()
{
   // Check if price is pulling back to resistance in a downtrend
   double maFastBuffer[], maSlowBuffer[];
   ArraySetAsSeries(maFastBuffer, true);
   ArraySetAsSeries(maSlowBuffer, true);
   
   if(CopyBuffer(maFastHandle, 0, 0, 5, maFastBuffer) < 5) return false;
   if(CopyBuffer(maSlowHandle, 0, 0, 5, maSlowBuffer) < 5) return false;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double maFastCurrent = maFastBuffer[0];
   
   // Check if price has pulled back to fast MA (resistance in downtrend)
   if(currentPrice >= maFastCurrent * 0.99 && currentPrice <= maFastCurrent * 1.01)
   {
      // Check if MA is still falling (downtrend intact)
      if(maFastBuffer[0] < maFastBuffer[2] && maSlowBuffer[0] < maSlowBuffer[2])
      {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Support/Resistance Functions                                     |
//+------------------------------------------------------------------+
bool CheckSupportLevel()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double supportLevel = IdentifySupportLevel();
   double zoneWidth = SRZonePips * _Point * 10; // Convert pips to price
   
   if(supportLevel <= 0) return false;
   
   return (currentPrice <= supportLevel + zoneWidth && 
           currentPrice >= supportLevel - zoneWidth);
}

bool CheckResistanceLevel()
{
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double resistanceLevel = IdentifyResistanceLevel();
   double zoneWidth = SRZonePips * _Point * 10; // Convert pips to price
   
   if(resistanceLevel <= 0) return false;
   
   return (currentPrice <= resistanceLevel + zoneWidth && 
           currentPrice >= resistanceLevel - zoneWidth);
}

double IdentifySupportLevel()
{
   double support = 0;
   
   // Find lowest low in lookback period
   int lowestBar = iLowest(_Symbol, _Period, MODE_LOW, SRLookback, 1);
   
   if(lowestBar >= 0)
   {
      support = iLow(_Symbol, _Period, lowestBar);
   }
   
   // Additional logic for dynamic support levels
   if(UseDynamicSR)
   {
      // Get moving average value
      double maBuffer[];
      ArraySetAsSeries(maBuffer, true);
      if(CopyBuffer(maHandle50, 0, 0, 2, maBuffer) == 2)
      {
         double maValue = maBuffer[0];
         double pivot = CalculatePivotPoints();
         
         if(support > 0)
            support = MathMin(support, MathMin(pivot, maValue));
         else
            support = MathMin(pivot, maValue);
      }
   }
   
   return support;
}

double IdentifyResistanceLevel()
{
   double resistance = 0;
   
   // Find highest high in lookback period
   int highestBar = iHighest(_Symbol, _Period, MODE_HIGH, SRLookback, 1);
   
   if(highestBar >= 0)
   {
      resistance = iHigh(_Symbol, _Period, highestBar);
   }
   
   // Additional logic for dynamic resistance levels
   if(UseDynamicSR)
   {
      // Get moving average value
      double maBuffer[];
      ArraySetAsSeries(maBuffer, true);
      if(CopyBuffer(maHandle50, 0, 0, 2, maBuffer) == 2)
      {
         double maValue = maBuffer[0];
         double pivot = CalculatePivotPoints();
         
         if(resistance > 0)
            resistance = MathMax(resistance, MathMax(pivot, maValue));
         else
            resistance = MathMax(pivot, maValue);
      }
   }
   
   return resistance;
}

double CalculatePivotPoints()
{
   // Calculate daily pivot points
   double high = iHigh(_Symbol, PERIOD_D1, 1);
   double low = iLow(_Symbol, PERIOD_D1, 1);
   double close = iClose(_Symbol, PERIOD_D1, 1);
   
   if(high == 0 || low == 0 || close == 0) return 0;
   
   return (high + low + close) / 3.0;
}

//+------------------------------------------------------------------+
//| RSI Functions                                                    |
//+------------------------------------------------------------------+
bool CheckRSIBuy()
{
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3)
      return false;
   
   double rsiCurrent = rsiBuffer[0];
   
   // Oversold condition
   if(rsiCurrent < RSIOversold)
      return true;
   
   // Bullish divergence
   if(UseRSIDivergence && CheckRSIBullishDivergence())
      return true;
   
   return false;
}

bool CheckRSISell()
{
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3)
      return false;
   
   double rsiCurrent = rsiBuffer[0];
   
   // Overbought condition
   if(rsiCurrent > RSIOverbought)
      return true;
   
   // Bearish divergence
   if(UseRSIDivergence && CheckRSIBearishDivergence())
      return true;
   
   return false;
}

bool CheckRSIBullishDivergence()
{
   // Get price data
   double priceBuffer[];
   ArraySetAsSeries(priceBuffer, true);
   if(CopyClose(_Symbol, _Period, 0, 5, priceBuffer) < 5) return false;
   
   // Get RSI data
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(rsiHandle, 0, 0, 5, rsiBuffer) < 5) return false;
   
   // Simple divergence detection
   if(priceBuffer[0] < priceBuffer[2] && rsiBuffer[0] > rsiBuffer[2])
      return true;
   
   return false;
}

bool CheckRSIBearishDivergence()
{
   // Get price data
   double priceBuffer[];
   ArraySetAsSeries(priceBuffer, true);
   if(CopyClose(_Symbol, _Period, 0, 5, priceBuffer) < 5) return false;
   
   // Get RSI data
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(rsiHandle, 0, 0, 5, rsiBuffer) < 5) return false;
   
   // Simple divergence detection
   if(priceBuffer[0] > priceBuffer[2] && rsiBuffer[0] < rsiBuffer[2])
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| MACD Functions                                                   |
//+------------------------------------------------------------------+
bool CheckMACDBuy()
{
   double macdMainBuffer[], macdSignalBuffer[];
   ArraySetAsSeries(macdMainBuffer, true);
   ArraySetAsSeries(macdSignalBuffer, true);
   
   if(CopyBuffer(macdHandle, MAIN_LINE, 0, 3, macdMainBuffer) < 3) return false;
   if(CopyBuffer(macdHandle, SIGNAL_LINE, 0, 3, macdSignalBuffer) < 3) return false;
   
   double macdCurrent = macdMainBuffer[0];
   double macdPrev = macdMainBuffer[1];
   double signalCurrent = macdSignalBuffer[0];
   double signalPrev = macdSignalBuffer[1];
   
   // MACD cross above signal line
   if(macdPrev < signalPrev && macdCurrent > signalCurrent)
      return true;
   
   // MACD above zero
   if(macdCurrent > 0)
      return true;
   
   // Bullish divergence
   if(UseMACDDivergence && CheckMACDBullishDivergence())
      return true;
   
   return false;
}

bool CheckMACDSell()
{
   double macdMainBuffer[], macdSignalBuffer[];
   ArraySetAsSeries(macdMainBuffer, true);
   ArraySetAsSeries(macdSignalBuffer, true);
   
   if(CopyBuffer(macdHandle, MAIN_LINE, 0, 3, macdMainBuffer) < 3) return false;
   if(CopyBuffer(macdHandle, SIGNAL_LINE, 0, 3, macdSignalBuffer) < 3) return false;
   
   double macdCurrent = macdMainBuffer[0];
   double macdPrev = macdMainBuffer[1];
   double signalCurrent = macdSignalBuffer[0];
   double signalPrev = macdSignalBuffer[1];
   
   // MACD cross below signal line
   if(macdPrev > signalPrev && macdCurrent < signalCurrent)
      return true;
   
   // MACD below zero
   if(macdCurrent < 0)
      return true;
   
   // Bearish divergence
   if(UseMACDDivergence && CheckMACDBearishDivergence())
      return true;
   
   return false;
}

bool CheckMACDBullishDivergence()
{
   // Simplified divergence detection
   double priceBuffer[], macdBuffer[];
   ArraySetAsSeries(priceBuffer, true);
   ArraySetAsSeries(macdBuffer, true);
   
   if(CopyClose(_Symbol, _Period, 0, 5, priceBuffer) < 5) return false;
   if(CopyBuffer(macdHandle, MAIN_LINE, 0, 5, macdBuffer) < 5) return false;
   
   if(priceBuffer[0] < priceBuffer[2] && macdBuffer[0] > macdBuffer[2])
      return true;
   
   return false;
}

bool CheckMACDBearishDivergence()
{
   double priceBuffer[], macdBuffer[];
   ArraySetAsSeries(priceBuffer, true);
   ArraySetAsSeries(macdBuffer, true);
   
   if(CopyClose(_Symbol, _Period, 0, 5, priceBuffer) < 5) return false;
   if(CopyBuffer(macdHandle, MAIN_LINE, 0, 5, macdBuffer) < 5) return false;
   
   if(priceBuffer[0] > priceBuffer[2] && macdBuffer[0] < macdBuffer[2])
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Volume Functions                                                 |
//+------------------------------------------------------------------+
bool CheckVolumeBuy()
{
   long volumeBuffer[];
   ArraySetAsSeries(volumeBuffer, true);
   
   if(CopyTickVolume(_Symbol, _Period, 0, VolumeLookback + 1, volumeBuffer) < VolumeLookback + 1)
      return false;
   
   long currentVolume = volumeBuffer[0];
   
   // Calculate average volume
   long totalVolume = 0;
   for(int i = 1; i <= VolumeLookback; i++)
   {
      totalVolume += volumeBuffer[i];
   }
   long avgVolume = totalVolume / VolumeLookback;
   
   // Volume spike on down move
   if(currentVolume > avgVolume * VolumeSpikeMultiplier)
   {
      double open = iOpen(_Symbol, _Period, 0);
      double close = iClose(_Symbol, _Period, 0);
      
      if(close < open) // Down candle with high volume
         return true;
   }
   
   // Decreasing volume on pullback
   if(CheckVolumeDecreasing())
      return true;
   
   return false;
}

bool CheckVolumeSell()
{
   long volumeBuffer[];
   ArraySetAsSeries(volumeBuffer, true);
   
   if(CopyTickVolume(_Symbol, _Period, 0, VolumeLookback + 1, volumeBuffer) < VolumeLookback + 1)
      return false;
   
   long currentVolume = volumeBuffer[0];
   
   // Calculate average volume
   long totalVolume = 0;
   for(int i = 1; i <= VolumeLookback; i++)
   {
      totalVolume += volumeBuffer[i];
   }
   long avgVolume = totalVolume / VolumeLookback;
   
   // Volume spike on up move
   if(currentVolume > avgVolume * VolumeSpikeMultiplier)
   {
      double open = iOpen(_Symbol, _Period, 0);
      double close = iClose(_Symbol, _Period, 0);
      
      if(close > open) // Up candle with high volume
         return true;
   }
   
   return false;
}

bool CheckVolumeDecreasing()
{
   long volumeBuffer[];
   ArraySetAsSeries(volumeBuffer, true);
   
   if(CopyTickVolume(_Symbol, _Period, 0, 4, volumeBuffer) < 4)
      return false;
   
   return (volumeBuffer[0] < volumeBuffer[1] && 
           volumeBuffer[1] < volumeBuffer[2] && 
           volumeBuffer[2] < volumeBuffer[3]);
}

//+------------------------------------------------------------------+
//| Price Action Functions                                           |
//+------------------------------------------------------------------+
bool CheckPriceActionBuy()
{
   // Check for bullish candlestick patterns
   if(DetectBullishEngulfing())
      return true;
   
   if(DetectHammer())
      return true;
   
   // Check for chart patterns
   if(DetectDoubleBottom())
      return true;
   
   return false;
}

bool CheckPriceActionSell()
{
   // Check for bearish candlestick patterns
   if(DetectBearishEngulfing())
      return true;
   
   if(DetectShootingStar())
      return true;
   
   // Check for chart patterns
   if(DetectDoubleTop())
      return true;
   
   return false;
}

bool DetectBullishEngulfing()
{
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open0 = iOpen(_Symbol, _Period, 0);
   double close0 = iClose(_Symbol, _Period, 0);
   
   if(open1 == 0 || close1 == 0 || open0 == 0 || close0 == 0)
      return false;
   
   return (close1 < open1 &&           // Previous candle bearish
           close0 > open0 &&           // Current candle bullish
           open0 <= close1 &&          // Current opens below or at previous close
           close0 >= open1);           // Current closes above or at previous open
}

bool DetectBearishEngulfing()
{
   double open1 = iOpen(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double open0 = iOpen(_Symbol, _Period, 0);
   double close0 = iClose(_Symbol, _Period, 0);
   
   if(open1 == 0 || close1 == 0 || open0 == 0 || close0 == 0)
      return false;
   
   return (close1 > open1 &&           // Previous candle bullish
           close0 < open0 &&           // Current candle bearish
           open0 >= close1 &&          // Current opens above or at previous close
           close0 <= open1);           // Current closes below or at previous open
}

bool DetectHammer()
{
   double open = iOpen(_Symbol, _Period, 0);
   double high = iHigh(_Symbol, _Period, 0);
   double low = iLow(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   
   if(open == 0 || high == 0 || low == 0 || close == 0)
      return false;
   
   double body = MathAbs(close - open);
   double lowerShadow = MathMin(open, close) - low;
   double upperShadow = high - MathMax(open, close);
   
   return (lowerShadow > body * 2.0 &&  // Long lower shadow
           upperShadow < body * 0.3 &&  // Small upper shadow
           close > open);               // Bullish candle
}

bool DetectShootingStar()
{
   double open = iOpen(_Symbol, _Period, 0);
   double high = iHigh(_Symbol, _Period, 0);
   double low = iLow(_Symbol, _Period, 0);
   double close = iClose(_Symbol, _Period, 0);
   
   if(open == 0 || high == 0 || low == 0 || close == 0)
      return false;
   
   double body = MathAbs(close - open);
   double lowerShadow = MathMin(open, close) - low;
   double upperShadow = high - MathMax(open, close);
   
   return (upperShadow > body * 2.0 &&  // Long upper shadow
           lowerShadow < body * 0.3 &&  // Small lower shadow
           close < open);               // Bearish candle
}

bool DetectDoubleBottom()
{
   // Simplified double bottom detection
   // Look for two consecutive lows with similar prices and higher low between
   double low1 = iLow(_Symbol, _Period, 1);
   double low2 = iLow(_Symbol, _Period, 3);
   
   if(low1 == 0 || low2 == 0) return false;
   
   double difference = MathAbs(low1 - low2);
   double avgPrice = (low1 + low2) / 2.0;
   
   // Check if lows are within 0.5% of each other
   if(difference / avgPrice < 0.005)
   {
      double middleLow = iLow(_Symbol, _Period, 2);
      if(middleLow > low1 && middleLow > low2)
         return true;
   }
   
   return false;
}

bool DetectDoubleTop()
{
   // Simplified double top detection
   double high1 = iHigh(_Symbol, _Period, 1);
   double high2 = iHigh(_Symbol, _Period, 3);
   
   if(high1 == 0 || high2 == 0) return false;
   
   double difference = MathAbs(high1 - high2);
   double avgPrice = (high1 + high2) / 2.0;
   
   // Check if highs are within 0.5% of each other
   if(difference / avgPrice < 0.005)
   {
      double middleHigh = iHigh(_Symbol, _Period, 2);
      if(middleHigh < high1 && middleHigh < high2)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Position Sizing Functions                                        |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPoints)
{
   double lotSize = FixedLotSize;
   
   if(LotType == LOT_RISK_BASED)
   {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = accountBalance * (RiskPercentage / 100.0);
      
      if(stopLossPoints > 0)
      {
         // Calculate lot size based on risk
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double pointValue = tickValue / tickSize;
         
         lotSize = riskAmount / (stopLossPoints * pointValue * _Point);
         
         // Adjust for minimum and maximum lot sizes
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         
         lotSize = MathMax(lotSize, MinLotSize);
         lotSize = MathMin(lotSize, MaxLotSize);
         
         // Normalize to lot step
         lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
         
         // Ensure within broker limits
         lotSize = MathMax(lotSize, minLot);
         lotSize = MathMin(lotSize, maxLot);
      }
   }
   
   return NormalizeDouble(lotSize, 2);
}

double CalculateStopLossPoints()
{
   if(UseATRForSLTP)
   {
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      
      if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) >= 1)
      {
         return (atrBuffer[0] * ATRMultiplierSL) / _Point;
      }
   }
   
   return StopLossPips * 10.0; // Convert pips to points for XAUUSD
}

double CalculateTakeProfitPoints()
{
   if(UseATRForSLTP)
   {
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      
      if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) >= 1)
      {
         return (atrBuffer[0] * ATRMultiplierTP) / _Point;
      }
   }
   
   return TakeProfitPips * 10.0; // Convert pips to points for XAUUSD
}

//+------------------------------------------------------------------+
//| Order Execution Functions                                        |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   double stopLossPoints = CalculateStopLossPoints();
   double takeProfitPoints = CalculateTakeProfitPoints();
   double lotSize = CalculateLotSize(stopLossPoints);
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = entryPrice - (stopLossPoints * _Point);
   double takeProfit = entryPrice + (takeProfitPoints * _Point);
   
   // Validate prices
   if(!ValidatePrices(entryPrice, stopLoss, takeProfit, ORDER_TYPE_BUY))
      return;
   
   // Prepare trade request
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "XAUUSD Buy - Confluence EA (Trend Following)";
   
   // Send order with retry logic
   for(int i = 0; i < OrderRetryCount; i++)
   {
      bool sent = OrderSend(request, result);
      if(sent)
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Buy order executed. Ticket: ", result.order, 
                  " Volume: ", lotSize, 
                  " Price: ", entryPrice,
                  " SL: ", stopLoss,
                  " TP: ", takeProfit);
            orderTicket = result.order;
            break;
         }
         else
         {
            Print("Order send failed. Retry ", i + 1, "/", OrderRetryCount, 
                  ". Error: ", GetTradeErrorDescription(result.retcode));
            Sleep(OrderRetryDelay);
         }
      }
      else
      {
         Print("OrderSend failed. Error: ", GetLastError());
         Sleep(OrderRetryDelay);
      }
   }
}

void ExecuteSellOrder()
{
   double stopLossPoints = CalculateStopLossPoints();
   double takeProfitPoints = CalculateTakeProfitPoints();
   double lotSize = CalculateLotSize(stopLossPoints);
   
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = entryPrice + (stopLossPoints * _Point);
   double takeProfit = entryPrice - (takeProfitPoints * _Point);
   
   // Validate prices
   if(!ValidatePrices(entryPrice, stopLoss, takeProfit, ORDER_TYPE_SELL))
      return;
   
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = entryPrice;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 10;
   request.magic = MagicNumber;
   request.comment = "XAUUSD Sell - Confluence EA (Trend Following)";
   
   // Send order with retry logic
   for(int i = 0; i < OrderRetryCount; i++)
   {
      bool sent = OrderSend(request, result);
      if(sent)
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Sell order executed. Ticket: ", result.order, 
                  " Volume: ", lotSize, 
                  " Price: ", entryPrice,
                  " SL: ", stopLoss,
                  " TP: ", takeProfit);
            orderTicket = result.order;
            break;
         }
         else
         {
            Print("Order send failed. Retry ", i + 1, "/", OrderRetryCount, 
                  ". Error: ", GetTradeErrorDescription(result.retcode));
            Sleep(OrderRetryDelay);
         }
      }
      else
      {
         Print("OrderSend failed. Error: ", GetLastError());
         Sleep(OrderRetryDelay);
      }
   }
}

bool ValidatePrices(double entry, double sl, double tp, ENUM_ORDER_TYPE type)
{
   // Check if prices are valid
   if(entry <= 0 || entry == EMPTY_VALUE || 
      sl <= 0 || sl == EMPTY_VALUE || 
      tp <= 0 || tp == EMPTY_VALUE)
   {
      Print("Invalid price values. Entry: ", entry, " SL: ", sl, " TP: ", tp);
      return false;
   }
   
   // Check stop loss distance
   double minSLDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(minSLDistance == 0) minSLDistance = 10 * _Point; // Default minimum
   
   double slDistance = MathAbs(entry - sl);
   
   if(slDistance < minSLDistance)
   {
      Print("Stop loss too close. Minimum: ", minSLDistance, " Current: ", slDistance);
      return false;
   }
   
   // Check if SL/TP are too close to current price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;
   
   if(type == ORDER_TYPE_BUY)
   {
      if(sl >= entry - spread)
      {
         Print("Stop loss too close to entry for buy order");
         return false;
      }
   }
   else if(type == ORDER_TYPE_SELL)
   {
      if(sl <= entry + spread)
      {
         Print("Stop loss too close to entry for sell order");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Trade Management Functions                                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      
      if(ticket > 0)
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         
         if(symbol == _Symbol && magic == MagicNumber)
         {
            // Apply trailing stop
            if(UseTrailingStop)
               ApplyTrailingStop(ticket);
            
            // Move to breakeven
            if(BreakevenPips > 0)
               MoveToBreakeven(ticket);
         }
      }
   }
}

void ApplyTrailingStop(ulong ticket)
{
   if(PositionSelectByTicket(ticket))
   {
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentPrice = (type == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double trailingDistance = TrailingStopPips * 10 * _Point;
      
      MqlTradeRequest request;
      MqlTradeResult result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = _Symbol;
      request.magic = MagicNumber;
      
      if(type == POSITION_TYPE_BUY)
      {
         double newSL = currentPrice - trailingDistance;
         if(newSL > currentSL && newSL > entryPrice)
         {
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(!OrderSend(request, result))
               Print("Failed to update trailing stop. Error: ", GetLastError());
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double newSL = currentPrice + trailingDistance;
         if((currentSL == 0 || newSL < currentSL) && newSL < entryPrice)
         {
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(!OrderSend(request, result))
               Print("Failed to update trailing stop. Error: ", GetLastError());
         }
      }
   }
}

void MoveToBreakeven(ulong ticket)
{
   if(PositionSelectByTicket(ticket))
   {
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = (type == POSITION_TYPE_BUY) ? 
                           SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                           SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double breakevenDistance = BreakevenPips * 10 * _Point;
      
      // Check if we should move to breakeven
      if(type == POSITION_TYPE_BUY)
      {
         double profitDistance = currentPrice - entryPrice;
         if(profitDistance >= breakevenDistance && currentSL < entryPrice)
         {
            ModifyStopLoss(ticket, entryPrice);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitDistance = entryPrice - currentPrice;
         if(profitDistance >= breakevenDistance && (currentSL > entryPrice || currentSL == 0))
         {
            ModifyStopLoss(ticket, entryPrice);
         }
      }
   }
}

void ModifyStopLoss(ulong ticket, double newSL)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = newSL;
   request.tp = PositionGetDouble(POSITION_TP);
   request.magic = MagicNumber;
   
   if(!OrderSend(request, result))
      Print("Failed to modify stop loss. Error: ", GetLastError());
   else
      Print("Stop loss moved to breakeven for ticket: ", ticket);
}

//+------------------------------------------------------------------+
//| Utility Functions                                                |
//+------------------------------------------------------------------+
string GetTradeErrorDescription(int errorCode)
{
   switch(errorCode)
   {
      case 10004: return "Requote";
      case 10006: return "Request rejected";
      case 10007: return "Request canceled by trader";
      case 10008: return "Order placed";
      case 10009: return "Request completed";
      case 10010: return "Only part of the request completed";
      case 10011: return "Request processing error";
      case 10012: return "Request timeout";
      case 10013: return "Invalid request";
      case 10014: return "Invalid volume";
      case 10015: return "Invalid price";
      case 10016: return "Invalid stops";
      case 10017: return "Trading disabled";
      case 10018: return "Market closed";
      case 10019: return "Not enough money";
      case 10020: return "Price changed";
      case 10021: return "Off quotes";
      case 10022: return "Invalid expiration";
      case 10023: return "Order changed";
      case 10024: return "Too many requests";
      case 10025: return "No changes";
      case 10026: return "Autotrading disabled";
      case 10027: return "Autotrading disabled by client";
      case 10028: return "Order locked";
      case 10029: return "Order frozen";
      case 10030: return "Invalid fill type";
      case 10031: return "No connection";
      case 10032: return "Only real trading";
      case 10033: return "Limit orders exceeded";
      case 10034: return "Volume exceeds limit";
      default:    return "Unknown error: " + IntegerToString(errorCode);
   }
}

//+------------------------------------------------------------------+