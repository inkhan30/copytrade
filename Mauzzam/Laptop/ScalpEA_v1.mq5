//+------------------------------------------------------------------+
//|                      ScalpEA.mq5                                |
//|                 Copyright 2023, ForexScalping EA                |
//|                       https://www.example.com                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, ForexScalping EA"
#property link      "https://www.example.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Indicators/Indicators.mqh>

//--- Input Parameters
input int      EMA_Fast_Period = 9;          // Fast EMA Period
input int      EMA_Slow_Period = 21;         // Slow EMA Period
input double   RiskPercent = 1.0;            // Risk Percentage per Trade
input int      TakeProfitPips = 15;          // Take Profit (Pips)
input int      StopLossPips = 10;            // Stop Loss (Pips)
input double   FixedLotSize = 0.0;           // Fixed Lot Size (0=auto)
input int      MaxSpread = 3;                // Max Allowed Spread (Pips)
input int      Slippage = 3;                 // Allowed Slippage (Pips)
input int      MagicNumber = 12345;          // EA Magic Number
input bool     EnableTrailingStop = true;    // Enable Trailing Stop
input int      TrailingStopPips = 5;         // Trailing Stop Distance
input int      MinBarsForSR = 20;            // Min Bars for S/R Detection
input string   TradeComment = "ScalpEA v1.0";// Trade Comment
input bool     TradeOnNewBar = true;         // Only Trade on New Bar

//--- Global Variables
CTrade         trade;
int            barsTotal;
datetime       lastTradeTime;
double         emaFast[], emaSlow[];
int            emaFastHandle, emaSlowHandle;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize indicators
   emaFastHandle = iMA(_Symbol, _Period, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, _Period, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE)
     {
      Print("Error creating indicators");
      return(INIT_FAILED);
     }
   
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   
//--- Set trade parameters
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
//--- Check trading permission
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Alert("Check if automated trading is allowed in the terminal settings!");
   
   barsTotal = iBars(_Symbol, _Period);
   lastTradeTime = 0;
   
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicators
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check for new bar if required
   if(TradeOnNewBar)
     {
      int currentBars = iBars(_Symbol, _Period);
      if(currentBars == barsTotal)
         return;
      barsTotal = currentBars;
     }
   
//--- Check minimum bars
   if(Bars(_Symbol, _Period) < 100)
      return;
   
//--- Check trading hours (optional)
   if(!IsTradingTime())
      return;
   
//--- Get current spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   if(spread > MaxSpread * _Point)
     {
      Comment("Spread too high: ", DoubleToString(spread / _Point, 1), " pips");
      return;
     }
   
//--- Get indicator values
   if(CopyBuffer(emaFastHandle, 0, 0, 3, emaFast) < 3 || 
      CopyBuffer(emaSlowHandle, 0, 0, 3, emaSlow) < 3)
     {
      Print("Error copying indicator buffers");
      return;
     }
   
//--- Get current price
   MqlTick last_tick;
   if(!SymbolInfoTick(_Symbol, last_tick))
     {
      Print("Error getting tick data");
      return;
     }
   
//--- Check existing positions
   if(PositionsTotal() > 0)
     {
      if(EnableTrailingStop)
         TrailingStop();
      return;
     }
   
//--- Calculate lot size
   double lotSize = CalculateLotSize();
   if(lotSize <= 0)
      return;
   
//--- Check for buy signal (EMA crossover near support)
   if(emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2] && IsNearSupport(last_tick.bid))
     {
      double sl = last_tick.bid - StopLossPips * _Point;
      double tp = last_tick.bid + TakeProfitPips * _Point;
      
      if(trade.Buy(lotSize, _Symbol, last_tick.ask, sl, tp, TradeComment))
         lastTradeTime = TimeCurrent();
     }
   
//--- Check for sell signal (EMA crossunder near resistance)
   if(emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2] && IsNearResistance(last_tick.ask))
     {
      double sl = last_tick.ask + StopLossPips * _Point;
      double tp = last_tick.ask - TakeProfitPips * _Point;
      
      if(trade.Sell(lotSize, _Symbol, last_tick.bid, sl, tp, TradeComment))
         lastTradeTime = TimeCurrent();
     }
  }
//+------------------------------------------------------------------+
//| Calculate proper lot size based on risk                           |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   if(FixedLotSize > 0)
      return FixedLotSize;
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(tickSize == 0 || tickValue == 0 || lotStep == 0)
     {
      Print("Error getting symbol info");
      return 0;
     }
   
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
   double moneyRiskPerLot = (StopLossPips * _Point / tickSize) * tickValue;
   
   if(moneyRiskPerLot <= 0)
      return 0;
   
   double lots = NormalizeDouble(riskAmount / moneyRiskPerLot, 2);
   
//--- Adjust to broker's lot step
   lots = floor(lots / lotStep) * lotStep;
   
//--- Check min/max lots
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   
   return lots;
  }
//+------------------------------------------------------------------+
//| Check if price is near support                                   |
//+------------------------------------------------------------------+
bool IsNearSupport(double price)
  {
   double lowest = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, MinBarsForSR, 1));
   return (price - lowest) < (10 * _Point);
  }
//+------------------------------------------------------------------+
//| Check if price is near resistance                                |
//+------------------------------------------------------------------+
bool IsNearResistance(double price)
  {
   double highest = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, MinBarsForSR, 1));
   return (highest - price) < (10 * _Point);
  }
//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
//+------------------------------------------------------------------+
void TrailingStop()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || 
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      
      double currentStop = PositionGetDouble(POSITION_SL);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double newStop = 0;
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         newStop = currentPrice - TrailingStopPips * _Point;
         if(newStop > currentStop && newStop > openPrice)
            trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
        }
      else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
         newStop = currentPrice + TrailingStopPips * _Point;
         if((newStop < currentStop || currentStop == 0) && newStop < openPrice)
            trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
        }
     }
  }
//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {
//--- Example: Trade only between 8 AM and 5 PM server time
   MqlDateTime time;
   TimeCurrent(time);
   
   if(time.hour >= 8 && time.hour < 17)
      return true;
      
   return false;
  }
//+------------------------------------------------------------------+