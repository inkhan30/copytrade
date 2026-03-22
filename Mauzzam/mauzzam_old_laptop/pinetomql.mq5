//+------------------------------------------------------------------+
//|                                              S_R_Breaks_EA.mq5   |
//|                        Converted from Pine Script by LuxAlgo     |
//|                                       Support/Resistance with Breaks |
//+------------------------------------------------------------------+
#property copyright "Converted from LuxAlgo Pine Script"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property description "Support and Resistance Levels with Breaks"
#property description "Trading EA based on support/resistance breaks"
#property description "with volume confirmation"

//--- Input Parameters
input int      LeftBars = 15;          // Left Bars for pivot detection
input int      RightBars = 15;         // Right Bars for pivot detection
input bool     ShowBreaks = true;      // Show Break Signals
input double   VolumeThresh = 20.0;    // Volume Threshold %
input bool     EnableTrading = true;   // Enable Trading
input double   LotSize = 0.1;          // Lot Size
input int      StopLoss = 200;         // Stop Loss (points)
input int      TakeProfit = 400;       // Take Profit (points)
input int      MagicNumber = 123456;   // Magic Number
input int      Slippage = 3;           // Slippage (points)

//--- Global Variables
double         ResistanceLevel = 0.0;
double         SupportLevel = 0.0;
double         LastResistance = 0.0;
double         LastSupport = 0.0;
datetime       LastSignalTime = 0;
int            VolumeShortHandle;
int            VolumeLongHandle;

//--- Indicator Buffers for plotting
double         ResistanceBuffer[];
double         SupportBuffer[];
double         BuySignalBuffer[];
double         SellSignalBuffer[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set up indicator buffers for chart drawing
   SetIndexBuffer(0, ResistanceBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SupportBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, SellSignalBuffer, INDICATOR_DATA);
   
   //--- Set drawing styles
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_ARROW);
   
   //--- Set colors
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrBlue);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 10);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, clrGreen);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, clrRed);
   
   //--- Set line widths
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);
   
   //--- Set names for DataWindow
   PlotIndexSetString(0, PLOT_LABEL, "Resistance");
   PlotIndexSetString(1, PLOT_LABEL, "Support");
   
   //--- Create handles for volume EMAs
   VolumeShortHandle = iMA(_Symbol, _Period, 5, 0, MODE_EMA, PRICE_VOLUME);
   VolumeLongHandle = iMA(_Symbol, _Period, 10, 0, MODE_EMA, PRICE_VOLUME);
   
   if(VolumeShortHandle == INVALID_HANDLE || VolumeLongHandle == INVALID_HANDLE)
   {
      Print("Error creating volume indicators");
      return(INIT_FAILED);
   }
   
   //--- Initialize arrays with EMPTY_VALUE
   ArrayInitialize(ResistanceBuffer, EMPTY_VALUE);
   ArrayInitialize(SupportBuffer, EMPTY_VALUE);
   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(VolumeShortHandle != INVALID_HANDLE) IndicatorRelease(VolumeShortHandle);
   if(VolumeLongHandle != INVALID_HANDLE) IndicatorRelease(VolumeLongHandle);
}

//+------------------------------------------------------------------+
//| Calculate pivot high                                             |
//+------------------------------------------------------------------+
double CalculatePivotHigh(int left, int right, int shift)
{
   if(shift + right + left >= Bars(_Symbol, _Period)) return 0.0;
   
   double high = iHigh(_Symbol, _Period, shift + right);
   
   // Check right side
   for(int i = shift + right + 1; i <= shift + right + left; i++)
   {
      if(iHigh(_Symbol, _Period, i) > high) return 0.0;
   }
   
   // Check left side
   for(int i = shift + right - 1; i >= shift - left; i--)
   {
      if(i < 0) break;
      if(iHigh(_Symbol, _Period, i) > high) return 0.0;
   }
   
   return high;
}

//+------------------------------------------------------------------+
//| Calculate pivot low                                              |
//+------------------------------------------------------------------+
double CalculatePivotLow(int left, int right, int shift)
{
   if(shift + right + left >= Bars(_Symbol, _Period)) return EMPTY_VALUE;
   
   double low = iLow(_Symbol, _Period, shift + right);
   
   // Check right side
   for(int i = shift + right + 1; i <= shift + right + left; i++)
   {
      if(iLow(_Symbol, _Period, i) < low) return EMPTY_VALUE;
   }
   
   // Check left side
   for(int i = shift + right - 1; i >= shift - left; i--)
   {
      if(i < 0) break;
      if(iLow(_Symbol, _Period, i) < low) return EMPTY_VALUE;
   }
   
   return low;
}

//+------------------------------------------------------------------+
//| Calculate volume oscillator                                      |
//+------------------------------------------------------------------+
double CalculateVolumeOscillator()
{
   double volumeShort[5], volumeLong[5];
   
   // Copy more bars to ensure we have valid data
   if(CopyBuffer(VolumeShortHandle, 0, 0, 5, volumeShort) <= 0) 
   {
      Print("Error copying short volume buffer: ", GetLastError());
      return 0.0;
   }
   
   if(CopyBuffer(VolumeLongHandle, 0, 0, 5, volumeLong) <= 0) 
   {
      Print("Error copying long volume buffer: ", GetLastError());
      return 0.0;
   }
   
   if(volumeLong[0] == 0.0) return 0.0;
   
   return 100.0 * (volumeShort[0] - volumeLong[0]) / volumeLong[0];
}

//+------------------------------------------------------------------+
//| Check for trading conditions                                     |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   if(!EnableTrading) return;
   
   // Count open positions with our magic number
   int positions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         positions++;
      }
   }
   if(positions > 0) return; // Only one position at a time
   
   // Avoid multiple signals in same bar
   if(TimeCurrent() - LastSignalTime < PeriodSeconds(_Period)) return;
   
   double close = iClose(_Symbol, _Period, 0);
   double open = iOpen(_Symbol, _Period, 0);
   double high = iHigh(_Symbol, _Period, 0);
   double low = iLow(_Symbol, _Period, 0);
   double volumeOsc = CalculateVolumeOscillator();
   
   //--- Check for resistance break (BUY signal)
   if(ResistanceLevel > 0 && close > ResistanceLevel && volumeOsc > VolumeThresh)
   {
      bool isBullWick = (open - low) > (close - open);
      
      if(!isBullWick) // Regular break
      {
         if(ShowBreaks)
         {
            BuySignalBuffer[0] = low - 100 * _Point;
            ObjectCreate(0, "BuySignal_" + IntegerToString(TimeCurrent()), OBJ_ARROW_BUY, 0, TimeCurrent(), low - 100 * _Point);
            ObjectSetInteger(0, "BuySignal_" + IntegerToString(TimeCurrent()), OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, "BuySignal_" + IntegerToString(TimeCurrent()), OBJPROP_WIDTH, 2);
         }
         
         //--- Place BUY order
         double sl = NormalizeDouble(close - StopLoss * _Point, _Digits);
         double tp = NormalizeDouble(close + TakeProfit * _Point, _Digits);
         PlaceOrder(ORDER_TYPE_BUY, sl, tp);
         LastSignalTime = TimeCurrent();
         Print("BUY Signal - Resistance Broken at: ", ResistanceLevel, 
               " | Close: ", close, " | Volume Osc: ", volumeOsc);
      }
   }
   
   //--- Check for support break (SELL signal)
   if(SupportLevel > 0 && close < SupportLevel && volumeOsc > VolumeThresh)
   {
      bool isBearWick = (open - close) < (high - open);
      
      if(!isBearWick) // Regular break
      {
         if(ShowBreaks)
         {
            SellSignalBuffer[0] = high + 100 * _Point;
            ObjectCreate(0, "SellSignal_" + IntegerToString(TimeCurrent()), OBJ_ARROW_SELL, 0, TimeCurrent(), high + 100 * _Point);
            ObjectSetInteger(0, "SellSignal_" + IntegerToString(TimeCurrent()), OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, "SellSignal_" + IntegerToString(TimeCurrent()), OBJPROP_WIDTH, 2);
         }
         
         //--- Place SELL order
         double sl = NormalizeDouble(close + StopLoss * _Point, _Digits);
         double tp = NormalizeDouble(close - TakeProfit * _Point, _Digits);
         PlaceOrder(ORDER_TYPE_SELL, sl, tp);
         LastSignalTime = TimeCurrent();
         Print("SELL Signal - Support Broken at: ", SupportLevel, 
               " | Close: ", close, " | Volume Osc: ", volumeOsc);
      }
   }
}

//+------------------------------------------------------------------+
//| Place order function                                             |
//+------------------------------------------------------------------+
void PlaceOrder(ENUM_ORDER_TYPE orderType, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = LotSize;
   request.type = orderType;
   request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = sl;
   request.tp = tp;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "S/R Break";
   
   //--- Send order
   if(!OrderSend(request, result))
   {
      Print("OrderSend failed: ", GetLastError(), 
            " | Retcode: ", result.retcode, 
            " | Bid: ", SymbolInfoDouble(_Symbol, SYMBOL_BID),
            " | Ask: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   }
   else
   {
      Print("Order placed successfully: Ticket #", result.order,
            " | Price: ", result.price,
            " | SL: ", sl,
            " | TP: ", tp);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Don't process on tick if we're not at a new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   
   if(currentBarTime == lastBarTime && !IsTesting())
   {
      return; // Same bar, don't recalculate
   }
   lastBarTime = currentBarTime;
   
   //--- Calculate pivot points
   int bars = Bars(_Symbol, _Period);
   if(bars < RightBars + LeftBars + 10) 
   {
      Print("Not enough bars to calculate pivots");
      return;
   }
   
   // Calculate resistance (pivot high)
   double pivotHigh = CalculatePivotHigh(LeftBars, RightBars, 0);
   if(pivotHigh > 0)
   {
      ResistanceLevel = pivotHigh;
      LastResistance = ResistanceLevel;
   }
   
   // Calculate support (pivot low)
   double pivotLow = CalculatePivotLow(LeftBars, RightBars, 0);
   if(pivotLow != EMPTY_VALUE && pivotLow > 0)
   {
      SupportLevel = pivotLow;
      LastSupport = SupportLevel;
   }
   
   //--- Update buffers for plotting
   for(int i = 0; i < bars; i++)
   {
      ResistanceBuffer[i] = EMPTY_VALUE;
      SupportBuffer[i] = EMPTY_VALUE;
      
      // Plot recent resistance
      if(i <= RightBars && ResistanceLevel > 0)
      {
         ResistanceBuffer[i] = ResistanceLevel;
      }
      
      // Plot recent support
      if(i <= RightBars && SupportLevel > 0)
      {
         SupportBuffer[i] = SupportLevel;
      }
   }
   
   //--- Clear signal buffers
   BuySignalBuffer[0] = EMPTY_VALUE;
   SellSignalBuffer[0] = EMPTY_VALUE;
   
   //--- Check trading conditions
   CheckTradingConditions();
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Handle chart events if needed
}