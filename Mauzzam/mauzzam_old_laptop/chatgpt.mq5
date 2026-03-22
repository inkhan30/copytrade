//+------------------------------------------------------------------+
//| Expert Advisor: Consecutive Candle Break EA                     |
//| Description: Trades based on consecutive highs/lows & EMA filter |
//+------------------------------------------------------------------+
#property strict

//--- input parameters
input int    EMA_Period = 50;          // EMA period
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M15; // Timeframe
input int    CandleCount = 3;          // Number of consecutive candles
input double Lots = 0.10;              // Lot size
input int    StopLossPips = 20;        // Stop Loss in pips
input int    TakeProfitPips = 40;      // Take Profit in pips
input int    Slippage = 2;             // Slippage
input int    MagicNumber = 12345;      // Unique EA ID

//--- handles
int emaHandle;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   emaHandle = iMA(_Symbol, TimeFrame, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Error creating EMA handle!");
      return(INIT_FAILED);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;  // only act at new bar

   double ema[];
   if(CopyBuffer(emaHandle,0,0,2,ema) < 0) return;
   double EMAValue = ema[0];

   //--- Check highs in last X candles
   bool bullish = true;
   bool bearish = true;

   for(int i=1; i<=CandleCount; i++)
   {
      double highPrev = iHigh(_Symbol, TimeFrame, i+1);
      double highCurr = iHigh(_Symbol, TimeFrame, i);

      double lowPrev = iLow(_Symbol, TimeFrame, i+1);
      double lowCurr = iLow(_Symbol, TimeFrame, i);

      if(!(highCurr > highPrev)) bullish = false;
      if(!(lowCurr < lowPrev))   bearish = false;
   }

   double price = iClose(_Symbol, TimeFrame, 1); // last closed candle

   if(bullish && price > EMAValue)
      OpenTrade(ORDER_TYPE_BUY);

   if(bearish && price < EMAValue)
      OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| Open trade function                                              |
//+------------------------------------------------------------------+
void OpenTrade(int type)
{
   if(PositionSelect(_Symbol)) return; // only 1 trade per symbol

   double price, sl, tp;
   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      sl = price - StopLossPips * _Point * 10;    // adjust for 5-digit
      tp = price + TakeProfitPips * _Point * 10;
   }
   else
   {
      price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      sl = price + StopLossPips * _Point * 10;
      tp = price - TakeProfitPips * _Point * 10;
   }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = Lots;
   request.type     = type;
   request.price    = price;
   request.sl       = sl;
   request.tp       = tp;
   request.deviation= Slippage;
   request.magic    = MagicNumber;

   if(!OrderSend(request,result))
      Print("OrderSend failed: ",result.comment);
   else
      Print("Trade opened: ",type==ORDER_TYPE_BUY ? "BUY" : "SELL");
}

//+------------------------------------------------------------------+
//| Check if a new bar opened                                        |
//+------------------------------------------------------------------+
datetime lastTime=0;
bool IsNewBar()
{
   static datetime lastBar=0;
   datetime curBar=iTime(_Symbol,TimeFrame,0);
   if(curBar!=lastBar)
   {
      lastBar=curBar;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
