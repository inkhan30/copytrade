//+------------------------------------------------------------------+
//|                                                  ICT_EA_v1.mq5   |
//|                        Based on ICT Trading Concepts             |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ICT Concept EA"
#property version   "1.00"
#property description "Expert Advisor based on ICT trading concepts"

//--- Input parameters
input group "Risk Management"
input double LotSize = 0.1;          // Default lot size
input double RiskPercent = 2.0;      // Risk percentage per trade
input int StopLossPips = 50;         // Stop Loss in pips
input int TakeProfitPips = 100;      // Take Profit in pips

input group "ICT Strategy Parameters"
input int OrderBlockLookback = 20;   // Candles to look back for Order Blocks
input int FVGLookback = 10;          // Candles to look back for FVGs
input bool UseNewYorkSession = true; // Focus on NY Session (8AM-12PM EST)
input bool UseLondonSession = true;  // Use London Session (2AM-5AM EST)

//--- Global variables
int handleMA;
double maBuffer[];
MqlDateTime sessionStart, sessionEnd;
int newYorkStart, newYorkEnd;
int londonStart, londonEnd;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create indicator handles
   handleMA = iMA(_Symbol, _Period, 50, 0, MODE_SMA, PRICE_CLOSE);
   if(handleMA == INVALID_HANDLE)
   {
      Print("Error creating MA indicator");
      return(INIT_FAILED);
   }
   
   //--- Set session times (converted to broker time)
   SetSessionTimes();
   
   //--- Set indicator buffers
   ArraySetAsSeries(maBuffer, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(handleMA != INVALID_HANDLE)
      IndicatorRelease(handleMA);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for minimum bars and new bar
   if(Bars(_Symbol, _Period) < 100 || !IsNewBar())
      return;
   
   //--- Check trading session
   if(!IsTradingSession())
      return;
   
   //--- Update indicators
   if(CopyBuffer(handleMA, 0, 0, 50, maBuffer) < 0)
   {
      Print("Error copying MA buffer");
      return;
   }
   
   //--- Check for trading signals
   CheckForSignals();
}

//+------------------------------------------------------------------+
//| Check for ICT-based signals                                      |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   //--- Check for existing positions
   if(PositionsTotal() > 0)
      return;
   
   //--- Look for Order Block setups
   CheckOrderBlockSetups();
   
   //--- Look for FVG setups
   CheckFVGSetups();
   
   //--- Look for liquidity grab setups
   CheckLiquiditySetups();
}

//+------------------------------------------------------------------+
//| Check for Order Block setups                                     |
//+------------------------------------------------------------------+
void CheckOrderBlockSetups()
{
   // Bullish Order Block: Strong bear candle followed by bullish reversal
   if(IsBullishOrderBlock(1))
   {
      // Price has retraced back to the order block area
      if(IsRetraceToOB(1, true))
      {
         // Look for bullish reversal pattern
         if(IsBullishReversal(0))
         {
            OpenTrade(ORDER_TYPE_BUY, "Bullish OB");
         }
      }
   }
   
   // Bearish Order Block: Strong bull candle followed by bearish reversal
   if(IsBearishOrderBlock(1))
   {
      // Price has retraced back to the order block area
      if(IsRetraceToOB(1, false))
      {
         // Look for bearish reversal pattern
         if(IsBearishReversal(0))
         {
            OpenTrade(ORDER_TYPE_SELL, "Bearish OB");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for Fair Value Gap setups                                  |
//+------------------------------------------------------------------+
void CheckFVGSetups()
{
   // Check for bullish FVG (price above FVG, looking to buy on retrace)
   if(IsBullishFVG(2))
   {
      // Price is retracing back to fill the FVG
      if(IsRetraceToFVG(2, true))
      {
         // Bullish rejection at FVG
         if(IsBullishRejection(0))
         {
            OpenTrade(ORDER_TYPE_BUY, "Bullish FVG");
         }
      }
   }
   
   // Check for bearish FVG (price below FVG, looking to sell on retrace)
   if(IsBearishFVG(2))
   {
      // Price is retracing back to fill the FVG
      if(IsRetraceToFVG(2, false))
      {
         // Bearish rejection at FVG
         if(IsBearishRejection(0))
         {
            OpenTrade(ORDER_TYPE_SELL, "Bearish FVG");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for liquidity run setups                                   |
//+------------------------------------------------------------------+
void CheckLiquiditySetups()
{
   // Check for liquidity sweep above a high
   if(IsLiquiditySweep(true))
   {
      // Then look for reversal pattern
      if(IsBearishReversal(0))
      {
         OpenTrade(ORDER_TYPE_SELL, "Liquidity Sweep Sell");
      }
   }
   
   // Check for liquidity sweep below a low
   if(IsLiquiditySweep(false))
   {
      // Then look for reversal pattern
      if(IsBullishReversal(0))
      {
         OpenTrade(ORDER_TYPE_BUY, "Liquidity Sweep Buy");
      }
   }
}

//+------------------------------------------------------------------+
//| Open a trade based on signal                                     |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, string comment)
{
   double sl = 0, tp = 0;
   double price = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick))
      return;
   
   if(type == ORDER_TYPE_BUY)
   {
      price = last_tick.ask;
      sl = price - StopLossPips * point * 10;
      tp = price + TakeProfitPips * point * 10;
   }
   else
   {
      price = last_tick.bid;
      sl = price + StopLossPips * point * 10;
      tp = price - TakeProfitPips * point * 10;
   }
   
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   
   MqlTradeRequest request = {0};
   MqlTradeResult result = {0};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = CalculateLotSize();
   request.type = type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = 12345;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;
   
   if(!OrderSend(request, result))
   {
      Print("Error opening trade: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickSize == 0 || point == 0 || tickValue == 0)
      return LotSize;
   
   double riskLots = (riskAmount / (StopLossPips * 10 * point)) * (tickSize / tickValue);
   riskLots = NormalizeDouble(riskLots, 2);
   
   return MathMin(riskLots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
}

//+------------------------------------------------------------------+
//| Check if it's a new bar                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last_time = 0;
   datetime current_time = iTime(_Symbol, _Period, 0);
   
   if(last_time != current_time)
   {
      last_time = current_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if we're in a trading session                              |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime current_time;
   TimeCurrent(current_time);
   
   int current_minute = current_time.hour * 60 + current_time.min;
   
   // Check New York session (8AM-12PM EST = 1PM-5PM GMT)
   if(UseNewYorkSession && current_minute >= newYorkStart && current_minute < newYorkEnd)
      return true;
   
   // Check London session (2AM-5AM EST = 7AM-10AM GMT)
   if(UseLondonSession && current_minute >= londonStart && current_minute < londonEnd)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Set session times based on broker time                           |
//+------------------------------------------------------------------+
void SetSessionTimes()
{
   // Assuming broker is GMT+2 (adjust based on your broker)
   // New York session: 8AM-12PM EST = 1PM-5PM GMT
   newYorkStart = 13 * 60;  // 1:00 PM
   newYorkEnd = 17 * 60;    // 5:00 PM
   
   // London session: 2AM-5AM EST = 7AM-10AM GMT
   londonStart = 7 * 60;    // 7:00 AM
   londonEnd = 10 * 60;     // 10:00 AM
}

//+------------------------------------------------------------------+
//| Detection functions for ICT patterns (simplified)                |
//+------------------------------------------------------------------+
bool IsBullishOrderBlock(int shift)
{
   // Simplified logic: Look for a strong bear candle followed by a bullish candle
   double open = iOpen(_Symbol, _Period, shift+1);
   double close = iClose(_Symbol, _Period, shift+1);
   double bodySize = MathAbs(open - close);
   double range = iHigh(_Symbol, _Period, shift+1) - iLow(_Symbol, _Period, shift+1);
   
   // Strong bear candle (body is at least 70% of range)
   if(close < open && bodySize/range >= 0.7)
   {
      // Followed by a bullish candle
      if(iClose(_Symbol, _Period, shift) > iOpen(_Symbol, _Period, shift))
      {
         return true;
      }
   }
   return false;
}

bool IsBearishOrderBlock(int shift)
{
   // Simplified logic: Look for a strong bull candle followed by a bearish candle
   double open = iOpen(_Symbol, _Period, shift+1);
   double close = iClose(_Symbol, _Period, shift+1);
   double bodySize = MathAbs(open - close);
   double range = iHigh(_Symbol, _Period, shift+1) - iLow(_Symbol, _Period, shift+1);
   
   // Strong bull candle (body is at least 70% of range)
   if(close > open && bodySize/range >= 0.7)
   {
      // Followed by a bearish candle
      if(iClose(_Symbol, _Period, shift) < iOpen(_Symbol, _Period, shift))
      {
         return true;
      }
   }
   return false;
}

bool IsBullishFVG(int shift)
{
   // Simplified FVG detection
   // A Fair Value Gap is a three-candle pattern where there's a gap between the wicks
   double thirdCandleLow = iLow(_Symbol, _Period, shift);
   double firstCandleHigh = iHigh(_Symbol, _Period, shift+2);
   
   if(thirdCandleLow > firstCandleHigh)
   {
      return true;
   }
   return false;
}

bool IsLiquiditySweep(bool isHigh)
{
   // Check for liquidity sweep (false breakout)
   if(isHigh)
   {
      // Price made a new high but closed back below the previous high
      double currentHigh = iHigh(_Symbol, _Period, 0);
      double prevHigh = iHigh(_Symbol, _Period, 1);
      double close = iClose(_Symbol, _Period, 0);
      
      if(currentHigh > prevHigh && close < prevHigh)
      {
         return true;
      }
   }
   else
   {
      // Price made a new low but closed back above the previous low
      double currentLow = iLow(_Symbol, _Period, 0);
      double prevLow = iLow(_Symbol, _Period, 1);
      double close = iClose(_Symbol, _Period, 0);
      
      if(currentLow < prevLow && close > prevLow)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Additional pattern detection functions would be implemented here |
//+------------------------------------------------------------------+
bool IsRetraceToOB(int shift, bool isBullish) { return true; }
bool IsRetraceToFVG(int shift, bool isBullish) { return true; }
bool IsBullishRejection(int shift) { return true; }
bool IsBearishRejection(int shift) { return true; }
bool IsBullishReversal(int shift) { return true; }
bool IsBearishReversal(int shift) { return true; }
//+------------------------------------------------------------------+