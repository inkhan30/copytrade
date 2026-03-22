//+------------------------------------------------------------------+
//|                                             XAUUSD_Averaging.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Includes
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Indicators/Trend.mqh>
#include <Indicators/Oscilators.mqh>

//--- Input Parameters
input group "Trade Settings"
input bool     AllowManualEntries = true;    // Allow Manual Entries
input double   LotSize = 0.01;               // Initial Lot Size
input int      MagicNumber = 12345;          // Magic Number

input group "Stop Loss Settings"
input bool     UseStopLoss = true;           // Enable Stop Loss
input double   StopLossDollars = 50.0;       // Stop Loss ($)
input bool     UseTrailingSL = false;        // Enable Trailing SL

input group "Take Profit Settings"
input bool     UseTakeProfit = true;         // Enable Take Profit
input double   TakeProfitDollars = 100.0;    // Take Profit ($)
input bool     UseTrailingTP = false;        // Enable Trailing TP
input double   TrailingTPDistance = 30.0;    // Trailing TP Distance ($)

input group "Averaging Strategy"
input bool     EnableAveraging = true;       // Enable Averaging
input int      MaxAveragingTrades = 3;       // Maximum Averaging Trades
input double   AveragingMultiplier = 2.0;    // Lot Size Multiplier
input double   AveragingTrigger = 20.0;      // Loss Trigger ($) for Averaging
input int      RangePeriod = 50;             // Range Detection Period (bars)
input double   RangeBreakoutFactor = 1.5;    // Range Breakout Factor

input group "Indicator Settings"
input ENUM_MA_METHOD MAType = MODE_SMA;      // Moving Average Type
input int       MAPeriod = 20;               // Moving Average Period
input int       ATRPeriod = 14;              // ATR Period
input double    RSIOverbought = 70.0;        // RSI Overbought
input double    RSIOversold = 30.0;          // RSI Oversold

//--- Global Variables
CTrade          *trade;
CPositionInfo   position;
CSymbolInfo     symbol;
CAccountInfo    account;

CiMA            ma;
CiATR           atr;
CiRSI           rsi;

double          initialPrice;
double          rangeHigh;
double          rangeLow;
bool            rangeDefined;
datetime        lastRangeUpdate;
int             averagingCount;
double          totalVolume;
double          averagePrice;
double          totalProfitLoss;

bool            tradeInProgress = false;
ulong           lastTradeTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create trade object
   trade = new CTrade();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetAsyncMode(false);
   
   //--- Initialize symbol info
   symbol.Name(Symbol());
   symbol.RefreshRates();
   
   //--- Initialize indicators
   if(!ma.Create(Symbol(), PERIOD_CURRENT, MAPeriod, 0, MAType, PRICE_CLOSE))
      Print("Failed to create MA indicator");
   
   if(!atr.Create(Symbol(), PERIOD_CURRENT, ATRPeriod))
      Print("Failed to create ATR indicator");
   
   if(!rsi.Create(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE))
      Print("Failed to create RSI indicator");
   
   //--- Initialize averaging variables
   rangeDefined = false;
   averagingCount = 0;
   totalVolume = 0;
   averagePrice = 0;
   totalProfitLoss = 0;
   
   //--- Set chart properties
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, clrBlack);
   
   //--- Create display objects
   CreateInfoPanel();
   
   Print("EA initialized successfully on ", Symbol());
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete trade object
   delete trade;
   
   //--- Delete all objects
   ObjectsDeleteAll(0, -1, -1);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update symbol rates
   symbol.RefreshRates();
   
   //--- Update indicators
   if(ma.Handle() != INVALID_HANDLE) 
      ma.Refresh(-1);
   if(atr.Handle() != INVALID_HANDLE) 
      atr.Refresh(-1);
   if(rsi.Handle() != INVALID_HANDLE) 
      rsi.Refresh(-1);
   
   //--- Manage existing positions
   ManagePositions();
   
   //--- Update averaging strategy
   if(EnableAveraging)
      CheckAveragingOpportunity();
   
   //--- Update range detection
   UpdateRangeDetection();
   
   //--- Update display
   UpdateInfoPanel();
}

//+------------------------------------------------------------------+
//| Create information panel                                         |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   int x_pos = 10;
   int y_pos = 20;
   int y_spacing = 20;
   
   //--- Create background
   ObjectCreate(0, "PanelBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "PanelBG", OBJPROP_XDISTANCE, x_pos - 5);
   ObjectSetInteger(0, "PanelBG", OBJPROP_YDISTANCE, y_pos - 5);
   ObjectSetInteger(0, "PanelBG", OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, "PanelBG", OBJPROP_YSIZE, 340);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BGCOLOR, clrGray);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BORDER_COLOR, clrSilver);
   ObjectSetInteger(0, "PanelBG", OBJPROP_BACK, true);
   
   //--- Create title
   CreateLabel("Title", "XAUUSD Averaging EA", x_pos, y_pos, clrGold, 12, "Arial Black");
   y_pos += y_spacing + 10;
   
   //--- Create information labels
   CreateLabel("Symbol", "Symbol: " + Symbol(), x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("Bid", "Bid: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("Ask", "Ask: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("Positions", "Open Positions: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("AvgPrice", "Average Price: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("PL", "Current P/L: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("TotalPL", "Total P/L: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("Range", "Range: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("AvgCount", "Averaging Count: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("MA", "MA Direction: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("RSI", "RSI: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("ATR", "ATR: ", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("TradeInfo", "Last Trade: None", x_pos, y_pos);
   y_pos += y_spacing;
   
   CreateLabel("Hotkeys", "Hotkeys: F1=Buy, F2=Sell, F3=Close", x_pos, y_pos);
}

//+------------------------------------------------------------------+
//| Create a label                                                   |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr = clrWhite, 
                 int size = 10, string font = "Arial")
{
   string labelName = "Label_" + name;
   
   ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, labelName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, labelName, OBJPROP_FONT, font);
   ObjectSetInteger(0, labelName, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Update information panel                                         |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   //--- Get current positions
   int positions = PositionsTotal();
   double currentPL = CalculateCurrentProfitLoss();
   
   //--- Update labels
   ObjectSetString(0, "Label_Bid", OBJPROP_TEXT, "Bid: " + DoubleToString(symbol.Bid(), 2));
   ObjectSetString(0, "Label_Ask", OBJPROP_TEXT, "Ask: " + DoubleToString(symbol.Ask(), 2));
   ObjectSetString(0, "Label_Positions", OBJPROP_TEXT, "Open Positions: " + IntegerToString(positions));
   ObjectSetString(0, "Label_AvgPrice", OBJPROP_TEXT, "Average Price: " + DoubleToString(averagePrice, 2));
   ObjectSetString(0, "Label_PL", OBJPROP_TEXT, "Current P/L: $" + DoubleToString(currentPL, 2));
   ObjectSetString(0, "Label_TotalPL", OBJPROP_TEXT, "Total P/L: $" + DoubleToString(totalProfitLoss, 2));
   ObjectSetString(0, "Label_AvgCount", OBJPROP_TEXT, "Averaging Count: " + IntegerToString(averagingCount));
   
   //--- Range information
   if(rangeDefined)
      ObjectSetString(0, "Label_Range", OBJPROP_TEXT, "Range: " + DoubleToString(rangeLow, 2) + 
                     " - " + DoubleToString(rangeHigh, 2));
   else
      ObjectSetString(0, "Label_Range", OBJPROP_TEXT, "Range: Not Defined");
   
   //--- Indicator values
   double maValue = 0, prevMA = 0;
   if(ma.Handle() != INVALID_HANDLE && ma.Main(0) != EMPTY_VALUE && ma.Main(1) != EMPTY_VALUE)
   {
      maValue = ma.Main(0);
      prevMA = ma.Main(1);
   }
   
   string maDirection = "NEUTRAL";
   if(maValue > prevMA) maDirection = "BULLISH";
   else if(maValue < prevMA) maDirection = "BEARISH";
   
   ObjectSetString(0, "Label_MA", OBJPROP_TEXT, "MA Direction: " + maDirection);
   
   double rsiValue = 50;
   if(rsi.Handle() != INVALID_HANDLE && rsi.Main(0) != EMPTY_VALUE)
      rsiValue = rsi.Main(0);
   ObjectSetString(0, "Label_RSI", OBJPROP_TEXT, "RSI: " + DoubleToString(rsiValue, 1));
   
   double atrValue = 0;
   if(atr.Handle() != INVALID_HANDLE && atr.Main(0) != EMPTY_VALUE)
      atrValue = atr.Main(0);
   ObjectSetString(0, "Label_ATR", OBJPROP_TEXT, "ATR: " + DoubleToString(atrValue, 2));
   
   //--- Last trade info
   if(lastTradeTicket > 0)
   {
      if(position.SelectByTicket(lastTradeTicket))
      {
         string typeStr = position.PositionType() == POSITION_TYPE_BUY ? "Buy" : "Sell";
         ObjectSetString(0, "Label_TradeInfo", OBJPROP_TEXT, 
                        "Last: " + typeStr + " SL:" + DoubleToString(position.StopLoss(), 2) + 
                        " TP:" + DoubleToString(position.TakeProfit(), 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   int positions = PositionsTotal();
   
   for(int i = positions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(position.SelectByTicket(ticket))
         {
            if(position.Magic() == MagicNumber && position.Symbol() == Symbol())
            {
               // Apply SL/TP if not set
               ApplyMissingSLTP(ticket);
               
               // Manage trailing stops if enabled
               ManageTrailingStop(ticket);
               
               // Check for close conditions
               CheckForClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply missing SL/TP                                              |
//+------------------------------------------------------------------+
void ApplyMissingSLTP(ulong ticket)
{
   if(!position.SelectByTicket(ticket)) return;
   
   double currentSL = position.StopLoss();
   double currentTP = position.TakeProfit();
   bool needModify = false;
   double newSL = currentSL;
   double newTP = currentTP;
   
   if(position.PositionType() == POSITION_TYPE_BUY)
   {
      // Apply Stop Loss if enabled and not set
      if(UseStopLoss && currentSL == 0)
      {
         newSL = position.PriceOpen() - CalculatePriceFromDollars(StopLossDollars, false);
         needModify = true;
      }
      
      // Apply Take Profit if enabled and not set
      if(UseTakeProfit && currentTP == 0)
      {
         newTP = position.PriceOpen() + CalculatePriceFromDollars(TakeProfitDollars, true);
         needModify = true;
      }
   }
   else // SELL position
   {
      // Apply Stop Loss if enabled and not set
      if(UseStopLoss && currentSL == 0)
      {
         newSL = position.PriceOpen() + CalculatePriceFromDollars(StopLossDollars, true);
         needModify = true;
      }
      
      // Apply Take Profit if enabled and not set
      if(UseTakeProfit && currentTP == 0)
      {
         newTP = position.PriceOpen() - CalculatePriceFromDollars(TakeProfitDollars, false);
         needModify = true;
      }
   }
   
   if(needModify)
   {
      trade.PositionModify(ticket, newSL, newTP);
      Print("Applied SL/TP for ticket ", ticket, " - SL: ", newSL, " TP: ", newTP);
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop(ulong ticket)
{
   if(!position.SelectByTicket(ticket)) return;
   
   double currentSL = position.StopLoss();
   double newSL = currentSL;
   bool needModify = false;
   
   if(position.PositionType() == POSITION_TYPE_BUY)
   {
      if(UseTrailingSL && currentSL > 0)
      {
         double trailingLevel = symbol.Bid() - CalculatePriceFromDollars(StopLossDollars, false);
         if(trailingLevel > currentSL)
         {
            newSL = trailingLevel;
            needModify = true;
         }
      }
      
      if(UseTrailingTP)
      {
         double currentTP = position.TakeProfit();
         if(currentTP > 0)
         {
            double trailingLevel = symbol.Bid() - CalculatePriceFromDollars(TrailingTPDistance, false);
            if(currentTP < trailingLevel)
            {
               trade.PositionModify(ticket, currentSL, trailingLevel);
               needModify = true;
            }
         }
      }
   }
   else // SELL position
   {
      if(UseTrailingSL && currentSL > 0)
      {
         double trailingLevel = symbol.Ask() + CalculatePriceFromDollars(StopLossDollars, true);
         if(trailingLevel < currentSL)
         {
            newSL = trailingLevel;
            needModify = true;
         }
      }
      
      if(UseTrailingTP)
      {
         double currentTP = position.TakeProfit();
         if(currentTP > 0)
         {
            double trailingLevel = symbol.Ask() + CalculatePriceFromDollars(TrailingTPDistance, true);
            if(currentTP > trailingLevel)
            {
               trade.PositionModify(ticket, currentSL, trailingLevel);
               needModify = true;
            }
         }
      }
   }
   
   if(needModify && newSL != currentSL)
   {
      trade.PositionModify(ticket, newSL, position.TakeProfit());
   }
}

//+------------------------------------------------------------------+
//| Check for position close                                         |
//+------------------------------------------------------------------+
void CheckForClose(ulong ticket)
{
   if(!position.SelectByTicket(ticket)) return;
   
   double rsiValue = 50;
   if(rsi.Handle() != INVALID_HANDLE && rsi.Main(0) != EMPTY_VALUE)
      rsiValue = rsi.Main(0);
   
   if(position.PositionType() == POSITION_TYPE_BUY)
   {
      if(rsiValue > RSIOverbought)
      {
         trade.PositionClose(ticket);
         Print("Closed buy position due to overbought RSI: ", rsiValue);
      }
   }
   else // SELL position
   {
      if(rsiValue < RSIOversold)
      {
         trade.PositionClose(ticket);
         Print("Closed sell position due to oversold RSI: ", rsiValue);
      }
   }
}

//+------------------------------------------------------------------+
//| Update range detection                                           |
//+------------------------------------------------------------------+
void UpdateRangeDetection()
{
   if(!rangeDefined || TimeCurrent() - lastRangeUpdate > 3600)
   {
      int bars = MathMin(RangePeriod, 1000);
      double highest = GetHighestPrice(bars);
      double lowest = GetLowestPrice(bars);
      
      double atrValue = 0;
      if(atr.Handle() != INVALID_HANDLE && atr.Main(0) != EMPTY_VALUE)
         atrValue = atr.Main(0);
      
      double rangeSize = highest - lowest;
      
      if(atrValue > 0 && rangeSize < atrValue * RangeBreakoutFactor)
      {
         rangeHigh = highest;
         rangeLow = lowest;
         rangeDefined = true;
         lastRangeUpdate = TimeCurrent();
         Print("New range detected: ", rangeLow, " - ", rangeHigh);
      }
   }
}

//+------------------------------------------------------------------+
//| Get highest price in specified period                            |
//+------------------------------------------------------------------+
double GetHighestPrice(int bars)
{
   double high = 0;
   int count = MathMin(bars, iBars(Symbol(), PERIOD_CURRENT) - 1);
   
   for(int i = 1; i <= count; i++)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(Symbol(), PERIOD_CURRENT, i, 1, rates) == 1)
      {
         if(rates[0].high > high || i == 1)
            high = rates[0].high;
      }
   }
   
   return high;
}

//+------------------------------------------------------------------+
//| Get lowest price in specified period                             |
//+------------------------------------------------------------------+
double GetLowestPrice(int bars)
{
   double low = DBL_MAX;
   int count = MathMin(bars, iBars(Symbol(), PERIOD_CURRENT) - 1);
   
   for(int i = 1; i <= count; i++)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(Symbol(), PERIOD_CURRENT, i, 1, rates) == 1)
      {
         if(rates[0].low < low || i == 1)
            low = rates[0].low;
      }
   }
   
   if(low == DBL_MAX)
      low = symbol.Bid();
   
   return low;
}

//+------------------------------------------------------------------+
//| Check averaging opportunity                                      |
//+------------------------------------------------------------------+
void CheckAveragingOpportunity()
{
   int positions = PositionsTotal();
   
   if(positions == 0) 
   {
      averagingCount = 0;
      totalVolume = 0;
      averagePrice = 0;
      return;
   }
   
   // Calculate current average price and P/L
   CalculateAveragePrice();
   double currentPL = CalculateCurrentProfitLoss();
   
   // Check if we should average
   if(currentPL < -AveragingTrigger && averagingCount < MaxAveragingTrades)
   {
      bool shouldAverage = false;
      
      if(rangeDefined)
      {
         // Check if price is in range or has retraced back into range
         if(symbol.Bid() > rangeLow && symbol.Bid() < rangeHigh)
         {
            shouldAverage = true;
         }
         // Check for retracement after breakout
         else if(symbol.Bid() < rangeLow && symbol.Bid() > (rangeLow - (rangeHigh - rangeLow)))
         {
            shouldAverage = true;
         }
      }
      else
      {
         // Use indicator-based decision if no range is defined
         double rsiValue = 50;
         if(rsi.Handle() != INVALID_HANDLE && rsi.Main(0) != EMPTY_VALUE)
            rsiValue = rsi.Main(0);
         
         if(rsiValue < (RSIOversold + 10))
         {
            shouldAverage = true;
         }
      }
      
      if(shouldAverage)
      {
         ExecuteAveragingTrade();
      }
   }
}

//+------------------------------------------------------------------+
//| Execute averaging trade                                          |
//+------------------------------------------------------------------+
void ExecuteAveragingTrade()
{
   if(PositionsTotal() == 0) return;
   
   // Get direction of first position
   ulong ticket = PositionGetTicket(0);
   if(!position.SelectByTicket(ticket)) return;
   
   ENUM_POSITION_TYPE posType = position.PositionType();
   
   // Calculate new lot size
   double avgLotSize = LotSize * MathPow(AveragingMultiplier, averagingCount);
   avgLotSize = NormalizeDouble(avgLotSize, 2);
   
   // Check lot size limits
   double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   if(avgLotSize < minLot) avgLotSize = minLot;
   if(avgLotSize > maxLot) avgLotSize = maxLot;
   avgLotSize = MathRound(avgLotSize / lotStep) * lotStep;
   
   // Calculate SL and TP
   double sl = 0, tp = 0;
   
   if(posType == POSITION_TYPE_BUY)
   {
      if(UseStopLoss) 
         sl = symbol.Ask() - CalculatePriceFromDollars(StopLossDollars, false);
      if(UseTakeProfit) 
         tp = symbol.Ask() + CalculatePriceFromDollars(TakeProfitDollars, true);
      
      if(!tradeInProgress)
      {
         tradeInProgress = true;
         if(trade.Buy(avgLotSize, Symbol(), symbol.Ask(), sl, tp, "Averaging Buy #" + IntegerToString(averagingCount + 1)))
         {
            lastTradeTicket = trade.ResultOrder();
            averagingCount++;
            Print("Averaging buy trade executed. Lot size: ", avgLotSize, " SL: ", sl, " TP: ", tp);
         }
         tradeInProgress = false;
      }
   }
   else // SELL
   {
      if(UseStopLoss) 
         sl = symbol.Bid() + CalculatePriceFromDollars(StopLossDollars, true);
      if(UseTakeProfit) 
         tp = symbol.Bid() - CalculatePriceFromDollars(TakeProfitDollars, false);
      
      if(!tradeInProgress)
      {
         tradeInProgress = true;
         if(trade.Sell(avgLotSize, Symbol(), symbol.Bid(), sl, tp, "Averaging Sell #" + IntegerToString(averagingCount + 1)))
         {
            lastTradeTicket = trade.ResultOrder();
            averagingCount++;
            Print("Averaging sell trade executed. Lot size: ", avgLotSize, " SL: ", sl, " TP: ", tp);
         }
         tradeInProgress = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate average price                                          |
//+------------------------------------------------------------------+
void CalculateAveragePrice()
{
   int positions = PositionsTotal();
   totalVolume = 0;
   double totalPriceVolume = 0;
   
   for(int i = 0; i < positions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && position.SelectByTicket(ticket))
      {
         if(position.Magic() == MagicNumber && position.Symbol() == Symbol())
         {
            double volume = position.Volume();
            double entryPrice = position.PriceOpen();
            
            totalVolume += volume;
            totalPriceVolume += volume * entryPrice;
         }
      }
   }
   
   if(totalVolume > 0)
      averagePrice = totalPriceVolume / totalVolume;
   else
      averagePrice = 0;
}

//+------------------------------------------------------------------+
//| Calculate current profit/loss                                    |
//+------------------------------------------------------------------+
double CalculateCurrentProfitLoss()
{
   double totalPL = 0;
   int positions = PositionsTotal();
   
   for(int i = 0; i < positions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && position.SelectByTicket(ticket))
      {
         if(position.Magic() == MagicNumber && position.Symbol() == Symbol())
         {
            totalPL += position.Profit() + position.Swap();
         }
      }
   }
   
   return totalPL;
}

//+------------------------------------------------------------------+
//| Calculate price from dollars                                     |
//+------------------------------------------------------------------+
double CalculatePriceFromDollars(double dollars, bool isForTakeProfit)
{
   // For XAUUSD (Gold), we need to calculate the price movement for a given dollar amount
   // 1 pip (0.01) movement = approximately $0.01 for 0.01 lot
   // But this varies with price. More accurate calculation:
   
   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE_LOSS);
   
   if(tickValue > 0 && tickSize > 0)
   {
      // Calculate how many ticks needed for the dollar amount
      double ticksNeeded = dollars / (LotSize * tickValue);
      // Convert ticks to price
      return ticksNeeded * tickSize;
   }
   
   // Fallback: approximate calculation for XAUUSD
   // At price 2000, 1 pip (0.01) = $0.01 for 0.01 lot
   // So for $50 loss, we need 50/0.01 = 5000 pips = 50.00 price movement
   // But this is too large! Let's use a more reasonable calculation
   
   // For XAUUSD, approximate: $1 per 1 pip for 0.01 lot
   return dollars * 0.01; // Convert dollars to pips (1 pip = 0.01)
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && AllowManualEntries)
   {
      // F1 for Buy
      if(lparam == 112)
      {
         ExecuteManualTrade(POSITION_TYPE_BUY);
      }
      // F2 for Sell
      else if(lparam == 113)
      {
         ExecuteManualTrade(POSITION_TYPE_SELL);
      }
      // F3 for Close All
      else if(lparam == 114)
      {
         CloseAllTrades();
      }
   }
}

//+------------------------------------------------------------------+
//| Execute manual trade                                             |
//+------------------------------------------------------------------+
void ExecuteManualTrade(ENUM_POSITION_TYPE tradeType)
{
   if(tradeInProgress) return;
   
   tradeInProgress = true;
   
   double sl = 0, tp = 0;
   double lot = LotSize;
   
   // Calculate SL and TP based on dollar amounts
   if(tradeType == POSITION_TYPE_BUY)
   {
      if(UseStopLoss)
         sl = symbol.Ask() - CalculatePriceFromDollars(StopLossDollars, false);
      if(UseTakeProfit)
         tp = symbol.Ask() + CalculatePriceFromDollars(TakeProfitDollars, true);
         
      if(trade.Buy(lot, Symbol(), symbol.Ask(), sl, tp, "Manual Buy"))
      {
         lastTradeTicket = trade.ResultOrder();
         Print("Manual Buy executed. Price: ", symbol.Ask(), " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Manual Buy failed. Error: ", trade.ResultRetcodeDescription());
      }
   }
   else // SELL
   {
      if(UseStopLoss)
         sl = symbol.Bid() + CalculatePriceFromDollars(StopLossDollars, true);
      if(UseTakeProfit)
         tp = symbol.Bid() - CalculatePriceFromDollars(TakeProfitDollars, false);
         
      if(trade.Sell(lot, Symbol(), symbol.Bid(), sl, tp, "Manual Sell"))
      {
         lastTradeTicket = trade.ResultOrder();
         Print("Manual Sell executed. Price: ", symbol.Bid(), " SL: ", sl, " TP: ", tp);
      }
      else
      {
         Print("Manual Sell failed. Error: ", trade.ResultRetcodeDescription());
      }
   }
   
   tradeInProgress = false;
}

//+------------------------------------------------------------------+
//| Close all trades                                                 |
//+------------------------------------------------------------------+
void CloseAllTrades()
{
   int positions = PositionsTotal();
   
   for(int i = positions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(position.SelectByTicket(ticket))
         {
            if(position.Magic() == MagicNumber && position.Symbol() == Symbol())
            {
               trade.PositionClose(ticket);
            }
         }
      }
   }
   
   // Reset averaging variables
   averagingCount = 0;
   totalVolume = 0;
   averagePrice = 0;
   
   Print("All trades closed");
}

//+------------------------------------------------------------------+