//+------------------------------------------------------------------+
//|                                         XAUUSD_RSI_Martingale.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
//--- EA Settings
input group "============{EA Settings}============"
input ENUM_TIMEFRAMES Trading_TF = PERIOD_CURRENT; // Trading timeframe
input int Trade_Mode = 2; // Trade mode (0: None, 1: Buy only, 2: Sell only, 3: Both)

//--- RSI Settings
input group "============{RSI Settings}============"
input bool useRSI = true; // Use RSI indicator
input ENUM_TIMEFRAMES rsiTF = PERIOD_CURRENT; // RSI timeframe
input int InpPeriodRSI = 14; // RSI period
input ENUM_APPLIED_PRICE InpRSIAppliedPrice = PRICE_CLOSE; // RSI applied price
input double rsiOverBought = 75.0; // RSI overbought level
input double rsiOverSold = 35.0; // RSI oversold level

//--- Risk Management
input group "============{Risk Management}============"
input string LotSize_Value = "0.01,0.02,0.03,0.05,0.08,0.11,0.17,0.23,0.30,0.38,0.47,0.57,0.68,0.80,0.93,1.07,1.22,1.38,1.55,1.73,1.92,2.12"; // Lot size progression
input double Spacing = 2000.0; // Spacing between orders (points)
input double SL_Points = 100000.0; // Stop loss (points)
input int TP_Mode = 0; // Take profit mode (0: Fixed, 1: Risk/Reward)
input double TP_Value = 1000.0; // Take profit value
input int Max_pos = 20; // Maximum positions
input bool Enable_Max_DD_Stop_Mart = false; // Enable max drawdown stop
input double Max_DD_Stop_Mart = 1000.0; // Max drawdown stop value
input int Max_Slippage_Points = 20; // Max slippage (points)
input bool Use_Exp_Reduction = false; // Use exposure reduction
input double Use_Exp_Percent_To_Close = 50.0; // Exposure reduction percentage
input bool Use_Breakeven = false; // Use breakeven

//--- EA Information
input group "============{EA Information}============"
input string EAComment = "Millionaire X"; // EA comment
input int MagicNo = 280; // Magic number

//--- Profit/Loss Target
input bool usePT = false; // Use profit target
input double profitTarget = 10.0; // Profit target
input bool useLT = false; // Use loss target
input double lossTarget = 10.0; // Loss target

//--- MaxDrawDown Settings
input bool usePerMD = false; // Use percentage max drawdown
input bool useDollarMD = false; // Use dollar max drawdown
input double maxDrawDown = 10.0; // Max drawdown value

//--- MaxProfit Settings
input bool usePerMP = false; // Use percentage max profit
input bool useDollarMP = false; // Use dollar max profit
input double maxProfit = 10.0; // Max profit value

//--- Trading Range
input bool useHours = true; // Use trading hours
input double From = 0.0; // Start hour
input double To = 23.59; // End hour

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
double lotSizes[];
int rsiHandle;
double rsiBuffer[];
datetime lastBarTime;
int currentMartingaleLevel = 0;
double initialBalance;
double dailyBalance;
double dailyProfit;
double dailyLoss;
double maxDailyDrawdown;
double pointValue;
MqlRates currentRates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate point value for XAUUSD
   pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Parse lot size array - FIXED: Create a copy of the input string to avoid modifying a constant
   string lotString = LotSize_Value;
   StringReplace(lotString, " ", "");
   
   string lotArray[];
   int size = StringSplit(lotString, ',', lotArray);
   ArrayResize(lotSizes, size);
   
   for(int i = 0; i < size; i++)
   {
      lotSizes[i] = StringToDouble(lotArray[i]);
   }
   
   if(size == 0)
   {
      Print("Error: Invalid lot size array");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Create RSI handle if needed
   if(useRSI)
   {
      rsiHandle = iRSI(_Symbol, rsiTF, InpPeriodRSI, InpRSIAppliedPrice);
      if(rsiHandle == INVALID_HANDLE)
      {
         Print("Error creating RSI indicator");
         return INIT_FAILED;
      }
      ArraySetAsSeries(rsiBuffer, true);
   }

   // Initialize daily tracking
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   dailyBalance = initialBalance;
   dailyProfit = 0;
   dailyLoss = 0;
   maxDailyDrawdown = 0;
   
   // Get current rates
   ArraySetAsSeries(currentRates, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(useRSI && rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check trading hours
   if(useHours && !IsWithinTradingHours())
      return;

   // Check daily limits
   if(!CheckDailyLimits())
      return;

   // Check for new bar
   if(!IsNewBar())
      return;

   // Get current rates
   if(CopyRates(_Symbol, Trading_TF, 0, 3, currentRates) < 3)
   {
      Print("Error copying rates");
      return;
   }

   // Get RSI values if needed
   if(useRSI)
   {
      if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) < 3)
      {
         Print("Error copying RSI buffer");
         return;
      }
   }

   // Check trading signals
   CheckSignals();

   // Manage existing positions
   ManagePositions();

   // Check martingale
   CheckMartingale();
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime currentTime;
   TimeCurrent(currentTime);
   
   double currentHour = currentTime.hour + currentTime.min / 100.0;
   
   return (currentHour >= From && currentHour <= To);
}

//+------------------------------------------------------------------+
//| Check daily limits                                               |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Calculate daily profit/loss
   double currentDailyPL = balance - dailyBalance;
   
   // Update max drawdown
   if(currentDailyPL < maxDailyDrawdown)
      maxDailyDrawdown = currentDailyPL;
   
   // Check profit target
   if(usePT && currentDailyPL >= profitTarget)
      return false;
   
   // Check loss target
   if(useLT && currentDailyPL <= -lossTarget)
      return false;
   
   // Check max drawdown
   if(usePerMD && maxDailyDrawdown <= -maxDrawDown / 100.0 * dailyBalance)
      return false;
   
   if(useDollarMD && maxDailyDrawdown <= -maxDrawDown)
      return false;
   
   // Check max profit
   if(usePerMP && currentDailyPL >= maxProfit / 100.0 * dailyBalance)
      return false;
   
   if(useDollarMP && currentDailyPL >= maxProfit)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, Trading_TF, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check trading signals                                            |
//+------------------------------------------------------------------+
void CheckSignals()
{
   // Get current positions count
   int buyPositions = CountPositions(POSITION_TYPE_BUY);
   int sellPositions = CountPositions(POSITION_TYPE_SELL);
   
   // Check if we can open new positions
   if((buyPositions + sellPositions) >= Max_pos)
      return;
   
   // RSI signals
   if(useRSI && ArraySize(rsiBuffer) >= 3)
   {
      // Buy signal: RSI crosses above oversold level
      if((Trade_Mode == 1 || Trade_Mode == 3) && 
         rsiBuffer[1] < rsiOverSold && rsiBuffer[0] >= rsiOverSold)
      {
         OpenPosition(ORDER_TYPE_BUY);
      }
      
      // Sell signal: RSI crosses below overbought level
      if((Trade_Mode == 2 || Trade_Mode == 3) && 
         rsiBuffer[1] > rsiOverBought && rsiBuffer[0] <= rsiOverBought)
      {
         OpenPosition(ORDER_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType)
{
   double lotSize = lotSizes[currentMartingaleLevel % ArraySize(lotSizes)];
   
   double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                  SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = CalculateStopLoss(orderType, price);
   double tp = CalculateTakeProfit(orderType, price);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = Max_Slippage_Points;
   request.magic = MagicNo;
   request.comment = EAComment;
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Position opened successfully: ", result.order);
         currentMartingaleLevel++;
      }
      else
      {
         Print("Error opening position: ", result.retcode);
      }
   }
   else
   {
      Print("Error opening position: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double price)
{
   double sl = 0;
   
   if(SL_Points > 0)
   {
      if(orderType == ORDER_TYPE_BUY)
         sl = price - SL_Points * pointValue;
      else
         sl = price + SL_Points * pointValue;
   
      sl = NormalizeDouble(sl, _Digits);
   }
   
   return sl;
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double price)
{
   double tp = 0;
   
   if(TP_Value > 0)
   {
      if(TP_Mode == 0) // Fixed TP
      {
         if(orderType == ORDER_TYPE_BUY)
            tp = price + TP_Value * pointValue;
         else
            tp = price - TP_Value * pointValue;
      }
   
      tp = NormalizeDouble(tp, _Digits);
   }
   
   return tp;
}

//+------------------------------------------------------------------+
//| Manage positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   // Check for exposure reduction
   if(Use_Exp_Reduction)
      CheckExposureReduction();
   
   // Check for breakeven
   if(Use_Breakeven)
      CheckBreakeven();
   
   // Check for max drawdown stop
   if(Enable_Max_DD_Stop_Mart)
      CheckMaxDrawdownStop();
}

//+------------------------------------------------------------------+
//| Check exposure reduction                                         |
//+------------------------------------------------------------------+
void CheckExposureReduction()
{
   double totalProfit = CalculateTotalProfit();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(totalProfit > 0 && Use_Exp_Percent_To_Close > 0)
   {
      double percentToClose = Use_Exp_Percent_To_Close / 100.0;
      double profitToKeep = totalProfit * percentToClose;
      
      // Close positions until we reach the desired profit level
      while(totalProfit > profitToKeep && PositionsTotal() > 0)
      {
         // Find the most profitable position
         ulong ticketToClose = FindMostProfitablePosition();
         if(ticketToClose > 0)
         {
            ClosePosition(ticketToClose);
            totalProfit = CalculateTotalProfit();
         }
         else
         {
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check breakeven                                                  |
//+------------------------------------------------------------------+
void CheckBreakeven()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNo)
      {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                              SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = PositionGetDouble(POSITION_SL);
         
         // Move SL to breakeven if price has moved in our favor by Spacing points
         if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && 
             currentPrice - openPrice >= Spacing * pointValue && (sl < openPrice || sl == 0)) ||
            (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && 
             openPrice - currentPrice >= Spacing * pointValue && (sl > openPrice || sl == 0)))
         {
            ModifyPositionSL(ticket, openPrice);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check max drawdown stop                                          |
//+------------------------------------------------------------------+
void CheckMaxDrawdownStop()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = balance - equity;
   
   if(drawdown >= Max_DD_Stop_Mart)
   {
      CloseAllPositions();
      currentMartingaleLevel = 0;
   }
}

//+------------------------------------------------------------------+
//| Check martingale                                                 |
//+------------------------------------------------------------------+
void CheckMartingale()
{
   // Check if we need to add martingale levels
   if(PositionsTotal() > 0 && currentMartingaleLevel < ArraySize(lotSizes) - 1)
   {
      // Check if latest position is losing and price has moved against us by Spacing
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) == MagicNo)
         {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                                 SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                 SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            // If position is losing and price has moved against us by Spacing points
            if(profit < 0 && 
               ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && 
                 openPrice - currentPrice >= Spacing * pointValue) ||
                (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && 
                 currentPrice - openPrice >= Spacing * pointValue)))
            {
               // Open a new martingale position
               OpenPosition((ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE));
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions                                                  |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNo && 
         PositionGetInteger(POSITION_TYPE) == type)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate total profit                                           |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
   double profit = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNo)
      {
         profit += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
//| Find most profitable position                                    |
//+------------------------------------------------------------------+
ulong FindMostProfitablePosition()
{
   ulong mostProfitableTicket = 0;
   double maxProfit = -DBL_MAX;
   
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNo)
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit > maxProfit)
         {
            maxProfit = profit;
            mostProfitableTicket = ticket;
         }
      }
   }
   
   return mostProfitableTicket;
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   if(PositionSelectByTicket(ticket))
   {
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol = _Symbol;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.deviation = Max_Slippage_Points;
      request.magic = MagicNo;
      request.comment = "Exposure reduction";
      
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         request.type = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         request.type = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Position closed successfully: ", ticket);
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == MagicNo)
      {
         ClosePosition(ticket);
      }
   }
   currentMartingaleLevel = 0;
}

//+------------------------------------------------------------------+
//| Modify position SL                                               |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double newSL)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   if(PositionSelectByTicket(ticket))
   {
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = _Symbol;
      request.sl = newSL;
      request.tp = PositionGetDouble(POSITION_TP);
      request.magic = MagicNo;
      request.comment = "Breakeven";
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("SL modified successfully for position: ", ticket);
            return true;
         }
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+