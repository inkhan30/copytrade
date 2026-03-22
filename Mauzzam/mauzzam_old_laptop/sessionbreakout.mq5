//+------------------------------------------------------------------+
//|                                                      SessionBreakoutEA.mq5 |
//|                                      Copyright 2024, Your Company Name |
//|                                       https://www.yourwebsite.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "Session Settings"
input string   LondonSessionStart  = "08:00";     // London session start (Broker time)
input string   LondonSessionEnd    = "17:00";     // London session end
input string   NewYorkSessionStart = "13:00";     // New York session start
input string   NewYorkSessionEnd   = "22:00";     // New York session end
input bool     UseLondonSession    = true;        // Trade London session
input bool     UseNewYorkSession   = true;        // Trade New York session

input group "Trading Parameters"
input int      LookbackPeriod      = 20;          // Lookback period for recent high/low
input int      EMA_Period          = 50;          // EMA trend filter period
input double   StopLossPips        = 30;          // Stop Loss in pips
input double   TakeProfitPips      = 60;          // Take Profit in pips
input bool     UseATRStopLoss      = false;       // Use ATR-based stop loss
input double   ATR_Multiplier      = 2.0;         // ATR multiplier for stop loss
input int      ATR_Period          = 14;          // ATR period

input group "Risk Management"
input double   RiskPerTrade        = 0.5;         // Risk per trade (% of account)
input double   MaxRiskPerTrade     = 1.0;         // Maximum risk per trade (%)
input int      MaxTradesPerDay     = 2;           // Maximum trades per day
input double   DailyLossLimit      = 2.0;         // Daily loss limit (% of account)
input double   MinLotSize          = 0.01;        // Minimum lot size
input double   MaxLotSize          = 10.0;        // Maximum lot size
input int      MagicNumber         = 202412;      // Magic number

input group "Additional Settings"
input int      Slippage            = 3;           // Slippage in points
input bool     CloseOnOppositeSignal = true;      // Close trades on opposite signal
input bool     SendEmailAlerts     = false;       // Send email alerts
input bool     ShowPanel           = true;        // Show info panel

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
datetime lastTradeDate = 0;
int tradesToday = 0;
double dailyProfitLoss = 0.0;
double accountEquityStart = 0.0;
bool tradingEnabled = true;
int emaHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize indicator handles
   emaHandle = iMA(_Symbol, _Period, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   
   if(emaHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   // Set initial account equity for daily loss calculation
   accountEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Check trading permissions
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("Trading is not allowed in the terminal settings!");
      return(INIT_FAILED);
   }
   
   // Check symbol trading
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
   {
      Alert("Trading is not allowed for ", _Symbol);
      return(INIT_FAILED);
   }
   
   // Reset daily counters if new day
   if(TimeCurrent() > lastTradeDate + 86400)
   {
      tradesToday = 0;
      dailyProfitLoss = 0.0;
      accountEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   
   if(ShowPanel)
   {
      CreateInfoPanel();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   
   // Delete graphical objects if panel was created
   ObjectsDeleteAll(0, "Panel_");
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new bar
   static datetime lastBarTime = 0;
   datetime currentTime = iTime(_Symbol, _Period, 0);
   if(currentTime == lastBarTime)
      return;
   lastBarTime = currentTime;
   
   // Reset daily counters if new day
   CheckNewDay();
   
   // Check if trading is enabled
   if(!tradingEnabled)
   {
      if(ShowPanel)
         UpdatePanel();
      return;
   }else{
      Print("Trading not enabled");
   }
   
   // Check daily loss limit
   if(CheckDailyLossLimit())
   {
      tradingEnabled = false;
      Print("Daily loss limit reached. Trading stopped for today.");
      if(SendEmailAlerts)
         SendMail("Trading Alert", "Daily loss limit reached. Trading stopped.");
      return;
   }
   
   // Check if we can trade today
   if(tradesToday >= MaxTradesPerDay)
   {
      if(ShowPanel)
         UpdatePanel();
      return;
   }
   
   // Check trading sessions
   if(!IsTradingSession())
   {
      if(ShowPanel)
         UpdatePanel();
      return;
   }
   
   // Get current market data
   double ema[];
   double atr[];
   double close[];
   double high[];
   double low[];
   
   if(CopyBuffer(emaHandle, 0, 0, LookbackPeriod+1, ema) <= 0 ||
      CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0 ||
      CopyClose(_Symbol, _Period, 0, LookbackPeriod+1, close) <= 0 ||
      CopyHigh(_Symbol, _Period, 0, LookbackPeriod+1, high) <= 0 ||
      CopyLow(_Symbol, _Period, 0, LookbackPeriod+1, low) <= 0)
   {
      Print("Error copying data");
      return;
   }
   
   // Get recent high/low
   double recentHigh = high[ArrayMaximum(high, 1, LookbackPeriod)];
   double recentLow = low[ArrayMinimum(low, 1, LookbackPeriod)];
   
   // Check for existing positions
   bool hasBuyPosition = PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   bool hasSellPosition = PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL;
   
   // Check for entry signals
   bool buySignal = false;
   bool sellSignal = false;
   
   // Check EMA trend filter and breakout
   if(close[1] > ema[1]) // Uptrend
   {
      if(close[0] > recentHigh && close[1] <= recentHigh)
      {
         buySignal = true;
         if(CloseOnOppositeSignal && hasSellPosition)
            CloseAllPositions(POSITION_TYPE_SELL);
      }
   }
   else if(close[1] < ema[1]) // Downtrend
   {
      if(close[0] < recentLow && close[1] >= recentLow)
      {
         sellSignal = true;
         if(CloseOnOppositeSignal && hasBuyPosition)
            CloseAllPositions(POSITION_TYPE_BUY);
      }
   }
   
   // Execute trades
   if(buySignal && !hasBuyPosition)
   {
      if(ExecuteBuyTrade())
      {
         tradesToday++;
         lastTradeDate = TimeCurrent();
      }
   }
   else if(sellSignal && !hasSellPosition)
   {
      if(ExecuteSellTrade())
      {
         tradesToday++;
         lastTradeDate = TimeCurrent();
      }
   }
   
   // Update panel
   if(ShowPanel)
      UpdatePanel();
}

//+------------------------------------------------------------------+
//| Check if current time is within trading sessions                |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   string currentTimeStr = StringFormat("%02d:%02d", timeStruct.hour, timeStruct.min);
   
   bool inLondonSession = false;
   bool inNewYorkSession = false;
   
   // Check London session
   if(UseLondonSession)
   {
      if(currentTimeStr >= LondonSessionStart && currentTimeStr < LondonSessionEnd)
         inLondonSession = true;
   }
   
   // Check New York session
   if(UseNewYorkSession)
   {
      if(currentTimeStr >= NewYorkSessionStart && currentTimeStr < NewYorkSessionEnd)
         inNewYorkSession = true;
   }
   
   return (inLondonSession || inNewYorkSession);
}

//+------------------------------------------------------------------+
//| Execute buy trade                                               |
//+------------------------------------------------------------------+
bool ExecuteBuyTrade()
{
   // Calculate position size based on risk
   double lotSize = CalculatePositionSize(POSITION_TYPE_BUY);
   if(lotSize <= 0)
      return false;
   
   // Calculate stop loss and take profit
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(UseATRStopLoss)
   {
      double atr[];
      if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
      {
         double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double atrValue = atr[0];
         stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - (atrValue * ATR_Multiplier);
         takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_BID) + (atrValue * ATR_Multiplier * 2);
      }
   }
   else
   {
      stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_BID) - (StopLossPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
      takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_BID) + (TakeProfitPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
   }
   
   // Execute trade
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl = NormalizeDouble(stopLoss, _Digits);
   request.tp = NormalizeDouble(takeProfit, _Digits);
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "SessionBreakoutEA Buy";
   
   if(!OrderSend(request, result))
   {
      Print("Buy order failed: ", GetLastError());
      return false;
   }
   
   Print("Buy order executed. Lot size: ", lotSize, ", SL: ", request.sl, ", TP: ", request.tp);
   return true;
}

//+------------------------------------------------------------------+
//| Execute sell trade                                              |
//+------------------------------------------------------------------+
bool ExecuteSellTrade()
{
   // Calculate position size based on risk
   double lotSize = CalculatePositionSize(POSITION_TYPE_SELL);
   if(lotSize <= 0)
      return false;
   
   // Calculate stop loss and take profit
   double stopLoss = 0;
   double takeProfit = 0;
   
   if(UseATRStopLoss)
   {
      double atr[];
      if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
      {
         double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double atrValue = atr[0];
         stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (atrValue * ATR_Multiplier);
         takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (atrValue * ATR_Multiplier * 2);
      }
   }
   else
   {
      stopLoss = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + (StopLossPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
      takeProfit = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (TakeProfitPips * SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
   }
   
   // Execute trade
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = NormalizeDouble(stopLoss, _Digits);
   request.tp = NormalizeDouble(takeProfit, _Digits);
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "SessionBreakoutEA Sell";
   
   if(!OrderSend(request, result))
   {
      Print("Sell order failed: ", GetLastError());
      return false;
   }
   
   Print("Sell order executed. Lot size: ", lotSize, ", SL: ", request.sl, ", TP: ", request.tp);
   return true;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk management                |
//+------------------------------------------------------------------+
double CalculatePositionSize(int tradeType)
{
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = accountEquity * (RiskPerTrade / 100);
   
   // Ensure risk is within limits
   riskAmount = MathMin(riskAmount, accountEquity * (MaxRiskPerTrade / 100));
   
   // Calculate stop loss in points
   double stopLossPoints = 0;
   if(UseATRStopLoss)
   {
      double atr[];
      if(CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
      {
         stopLossPoints = atr[0] * ATR_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      }
   }
   else
   {
      stopLossPoints = StopLossPips * 10;
   }
   
   if(stopLossPoints <= 0)
      return MinLotSize;
   
   // Calculate tick value
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Calculate lot size
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotSize = (riskAmount / (stopLossPoints * tickValue * tickSize)) * lotStep;
   
   // Normalize lot size
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Apply min/max limits
   lotSize = MathMax(lotSize, MinLotSize);
   lotSize = MathMin(lotSize, MaxLotSize);
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Check daily loss limit                                          |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPercentage = ((accountEquityStart - currentEquity) / accountEquityStart) * 100;
   
   return (lossPercentage >= DailyLossLimit);
}

//+------------------------------------------------------------------+
//| Check for new day and reset counters                            |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime currentTimeStruct;
   TimeCurrent(currentTimeStruct);
   
   MqlDateTime lastTradeDateStruct;
   TimeToStruct(lastTradeDate, lastTradeDateStruct);
   
   if(currentTimeStruct.day != lastTradeDateStruct.day ||
      currentTimeStruct.mon != lastTradeDateStruct.mon ||
      currentTimeStruct.year != lastTradeDateStruct.year)
   {
      tradesToday = 0;
      dailyProfitLoss = 0.0;
      accountEquityStart = AccountInfoDouble(ACCOUNT_EQUITY);
      tradingEnabled = true;
      Print("New day started. Counters reset.");
   }
}

//+------------------------------------------------------------------+
//| Close all positions of specific type                            |
//+------------------------------------------------------------------+
void CloseAllPositions(int positionType)
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         if(PositionGetInteger(POSITION_TYPE) == positionType)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = Slippage;
            request.magic = MagicNumber;
            request.comment = "Closed by EA";
            
            if(positionType == POSITION_TYPE_BUY)
            {
               request.type = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else
            {
               request.type = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }
            
            if(!OrderSend(request, result))
               Print("Failed to close position: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Create information panel                                        |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   // Create panel background
   ObjectCreate(0, "Panel_Background", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_XSIZE, 250);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_YSIZE, 180);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "Panel_Background", OBJPROP_BORDER_COLOR, clrGray);
   
   // Create title
   ObjectCreate(0, "Panel_Title", OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "Panel_Title", OBJPROP_TEXT, "Session Breakout EA");
   ObjectSetInteger(0, "Panel_Title", OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, "Panel_Title", OBJPROP_YDISTANCE, 25);
   ObjectSetInteger(0, "Panel_Title", OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, "Panel_Title", OBJPROP_FONTSIZE, 10);
   
   // Create info labels
   CreatePanelLabel("TradesToday", "Trades Today: 0", 20, 45);
   CreatePanelLabel("DailyPL", "Daily P/L: $0.00", 20, 65);
   CreatePanelLabel("Status", "Status: Active", 20, 85);
   CreatePanelLabel("Session", "Session: None", 20, 105);
   CreatePanelLabel("Equity", "Equity: $0.00", 20, 125);
   CreatePanelLabel("Risk", "Risk/Trade: 0.5%", 20, 145);
   CreatePanelLabel("LossLimit", "Loss Limit: 2.0%", 20, 165);
}

void CreatePanelLabel(string name, string text, int x, int y)
{
   ObjectCreate(0, "Panel_" + name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, "Panel_" + name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, "Panel_" + name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "Panel_" + name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, "Panel_" + name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "Panel_" + name, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| Update information panel                                        |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // Update trades today
   ObjectSetString(0, "Panel_TradesToday", OBJPROP_TEXT, "Trades Today: " + IntegerToString(tradesToday) + "/" + IntegerToString(MaxTradesPerDay));
   
   // Update daily P/L
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPL = currentEquity - accountEquityStart;
   ObjectSetString(0, "Panel_DailyPL", OBJPROP_TEXT, "Daily P/L: $" + DoubleToString(dailyPL, 2));
   
   // Update status
   string statusText = tradingEnabled ? "Active" : "Stopped";
   if(tradesToday >= MaxTradesPerDay)
      statusText = "Max Trades Reached";
   ObjectSetString(0, "Panel_Status", OBJPROP_TEXT, "Status: " + statusText);
   
   // Update session status
   string sessionText = IsTradingSession() ? "Active" : "Closed";
   ObjectSetString(0, "Panel_Session", OBJPROP_TEXT, "Session: " + sessionText);
   
   // Update equity
   ObjectSetString(0, "Panel_Equity", OBJPROP_TEXT, "Equity: $" + DoubleToString(currentEquity, 2));
   
   // Update risk
   ObjectSetString(0, "Panel_Risk", OBJPROP_TEXT, "Risk/Trade: " + DoubleToString(RiskPerTrade, 1) + "%");
   
   // Update loss limit
   double lossPercentage = ((accountEquityStart - currentEquity) / accountEquityStart) * 100;
   ObjectSetString(0, "Panel_LossLimit", OBJPROP_TEXT, 
                   "Loss Limit: " + DoubleToString(DailyLossLimit, 1) + "% (" + 
                   DoubleToString(lossPercentage, 1) + "%)");
   
   // Change color based on loss
   if(lossPercentage >= DailyLossLimit)
      ObjectSetInteger(0, "Panel_LossLimit", OBJPROP_COLOR, clrRed);
   else if(lossPercentage >= DailyLossLimit * 0.7)
      ObjectSetInteger(0, "Panel_LossLimit", OBJPROP_COLOR, clrOrange);
   else
      ObjectSetInteger(0, "Panel_LossLimit", OBJPROP_COLOR, clrWhite);
}
//+------------------------------------------------------------------+