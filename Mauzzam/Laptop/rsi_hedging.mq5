//+------------------------------------------------------------------+
//|                                                   HedgeRSIEA.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"

// Include Trade and Position classes
#include <Trade/Trade.mql5>
#include <Trade/PositionInfo.mql5>

// Input parameters
input group "RSI Parameters"
input int                RSI_Period = 14;                // RSI Period
input ENUM_APPLIED_PRICE RSI_Applied_Price = PRICE_CLOSE; // RSI Applied Price
input double             RSI_Overbought = 70;            // RSI Overbought Level
input double             RSI_Oversold = 30;              // RSI Oversold Level

input group "Trading Parameters"
input double             Lot_Size = 0.01;                // Lot Size
input int                Take_Profit_Pips = 100;         // Take Profit (Pips)
input int                Stop_Loss_Pips = 100;           // Stop Loss (Pips)
input int                Magic_Number = 123456;          // Magic Number
input string             Trade_Comment = "HedgeRSI EA";  // Trade Comment

// Global variables
CTrade trade;
CPositionInfo positionInfo;
int rsiHandle;
bool positionsOpened = false;
double openPrice = 0;
double initialTPBuy = 0;
double initialTPSell = 0;
double breakevenLevel = 0;
bool breakevenActivated = false;
int buyPositionTicket = 0;
int sellPositionTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize RSI indicator
   rsiHandle = iRSI(_Symbol, _Period, RSI_Period, RSI_Applied_Price);
   
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Failed to create RSI indicator handle");
      return INIT_FAILED;
   }
   
   // Set trade parameters
   trade.SetExpertMagicNumber(Magic_Number);
   
   Print("HedgeRSI EA initialized successfully");
   Print("RSI Levels - Overbought: ", RSI_Overbought, ", Oversold: ", RSI_Oversold);
   Print("Lot Size: ", Lot_Size, ", TP Pips: ", Take_Profit_Pips, ", SL Pips: ", Stop_Loss_Pips);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(rsiHandle);
   }
   Print("HedgeRSI EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new trading conditions
   CheckTradingConditions();
   
   // Check for TP hits and manage positions
   CheckPositionManagement();
   
   // Check for breakeven activation
   CheckBreakevenConditions();
}

//+------------------------------------------------------------------+
//| Check trading conditions based on RSI                            |
//+------------------------------------------------------------------+
void CheckTradingConditions()
{
   // Get current RSI value
   double rsiValue[1];
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsiValue) < 1)
   {
      Print("Failed to get RSI value");
      return;
   }
   
   // Check if positions are already opened
   if(!positionsOpened && (rsiValue[0] >= RSI_Overbought || rsiValue[0] <= RSI_Oversold))
   {
      OpenHedgePositions(rsiValue[0]);
   }
}

//+------------------------------------------------------------------+
//| Open hedge positions (buy and sell)                              |
//+------------------------------------------------------------------+
void OpenHedgePositions(double currentRSI)
{
   // Get current price
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   openPrice = currentPrice;
   
   // Calculate TP and SL in points
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tpPoints = Take_Profit_Pips * 10 * point; // Convert pips to points
   double slPoints = Stop_Loss_Pips * 10 * point;   // Convert pips to points
   
   // Calculate TP and SL prices
   initialTPBuy = NormalizeDouble(currentPrice + tpPoints, digits);
   initialTPSell = NormalizeDouble(currentPrice - tpPoints, digits);
   
   double slBuy = NormalizeDouble(currentPrice - slPoints, digits);
   double slSell = NormalizeDouble(currentPrice + slPoints, digits);
   
   Print("Opening hedge positions at price: ", currentPrice);
   Print("Initial TP Buy: ", initialTPBuy, ", TP Sell: ", initialTPSell);
   
   // Open BUY position
   trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, Lot_Size, currentPrice, slBuy, initialTPBuy, Trade_Comment);
   
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      buyPositionTicket = trade.ResultOrder();
      Print("Buy position opened successfully. Ticket: ", buyPositionTicket);
   }
   else
   {
      Print("Failed to open buy position. Error: ", trade.ResultRetcodeDescription());
      return;
   }
   
   // Open SELL position
   trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, Lot_Size, currentPrice, slSell, initialTPSell, Trade_Comment);
   
   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      sellPositionTicket = trade.ResultOrder();
      Print("Sell position opened successfully. Ticket: ", sellPositionTicket);
      positionsOpened = true;
   }
   else
   {
      Print("Failed to open sell position. Error: ", trade.ResultRetcodeDescription());
      // Close buy position if sell failed
      trade.PositionClose(buyPositionTicket);
   }
}

//+------------------------------------------------------------------+
//| Check position management and TP hits                            |
//+------------------------------------------------------------------+
void CheckPositionManagement()
{
   if(!positionsOpened) return;
   
   // Check if any position hit TP
   bool buyClosed = false;
   bool sellClosed = false;
   double closePrice = 0;
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Check BUY position
   if(positionInfo.SelectByTicket(buyPositionTicket))
   {
      if(positionInfo.Profit() > 0)
      {
         Print("Buy position closed by TP at price: ", currentPrice);
         buyClosed = true;
         closePrice = currentPrice;
      }
   }
   
   // Check SELL position
   if(positionInfo.SelectByTicket(sellPositionTicket))
   {
      if(positionInfo.Profit() > 0)
      {
         Print("Sell position closed by TP at price: ", currentPrice);
         sellClosed = true;
         closePrice = currentPrice;
      }
   }
   
   // Handle TP hit scenario
   if(buyClosed || sellClosed)
   {
      HandleTPHit(closePrice, buyClosed, sellClosed);
   }
}

//+------------------------------------------------------------------+
//| Handle TP hit and open new position with SL                      |
//+------------------------------------------------------------------+
void HandleTPHit(double closePrice, bool buyClosed, bool sellClosed)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slPoints = Stop_Loss_Pips * 10 * point;
   
   if(sellClosed)
   {
      // TP hit for sell position - open new buy position with SL
      double newBuySL = NormalizeDouble(closePrice - slPoints, digits);
      
      Print("Opening new buy position after sell TP hit at: ", closePrice);
      Print("New buy SL: ", newBuySL);
      
      trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, Lot_Size, closePrice, newBuySL, 0, "Hedge Recovery Buy");
      
      if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
      {
         buyPositionTicket = trade.ResultOrder();
         
         // Calculate breakeven level
         CalculateBreakevenLevel();
      }
   }
   else if(buyClosed)
   {
      // TP hit for buy position - open new sell position with SL
      double newSellSL = NormalizeDouble(closePrice + slPoints, digits);
      
      Print("Opening new sell position after buy TP hit at: ", closePrice);
      Print("New sell SL: ", newSellSL);
      
      trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, Lot_Size, closePrice, newSellSL, 0, "Hedge Recovery Sell");
      
      if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
      {
         sellPositionTicket = trade.ResultOrder();
         
         // Calculate breakeven level
         CalculateBreakevenLevel();
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate breakeven level for two positions                      |
//+------------------------------------------------------------------+
void CalculateBreakevenLevel()
{
   double price1 = 0, price2 = 0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Get prices of both buy positions
   if(positionInfo.SelectByTicket(buyPositionTicket))
   {
      price1 = positionInfo.PriceOpen();
   }
   
   // Find the other buy position (search through all positions)
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != buyPositionTicket && PositionGetInteger(POSITION_MAGIC) == Magic_Number && 
         PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         price2 = PositionGetDouble(POSITION_PRICE_OPEN);
         break;
      }
   }
   
   if(price1 > 0 && price2 > 0)
   {
      breakevenLevel = NormalizeDouble((price1 + price2) / 2, digits);
      Print("Breakeven level calculated: ", breakevenLevel);
      Print("Price1: ", price1, ", Price2: ", price2);
   }
}

//+------------------------------------------------------------------+
//| Check breakeven conditions                                       |
//+------------------------------------------------------------------+
void CheckBreakevenConditions()
{
   if(breakevenLevel <= 0 || breakevenActivated) return;
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Check if price reached breakeven level
   if(currentPrice >= breakevenLevel && !breakevenActivated)
   {
      breakevenActivated = true;
      Print("Breakeven level reached at: ", currentPrice);
      
      // Modify TP of both positions to breakeven + 1 pip
      double newTP = NormalizeDouble(breakevenLevel + (10 * point), digits);
      
      // Modify TP for all open positions
      ModifyAllPositionsTP(newTP);
   }
}

//+------------------------------------------------------------------+
//| Modify TP for all open positions                                 |
//+------------------------------------------------------------------+
void ModifyAllPositionsTP(double newTP)
{
   Print("Modifying all positions TP to: ", newTP);
   
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == Magic_Number)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double currentSL = PositionGetDouble(POSITION_SL);
         
         trade.PositionModify(ticket, currentSL, newTP);
         
         if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            Print("Position ", ticket, " TP modified to: ", newTP);
         }
         else
         {
            Print("Failed to modify position ", ticket, ". Error: ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset all positions and variables                                |
//+------------------------------------------------------------------+
void ResetPositions()
{
   positionsOpened = false;
   openPrice = 0;
   initialTPBuy = 0;
   initialTPSell = 0;
   breakevenLevel = 0;
   breakevenActivated = false;
   buyPositionTicket = 0;
   sellPositionTicket = 0;
   
   Print("All positions reset. Ready for new trading cycle.");
}