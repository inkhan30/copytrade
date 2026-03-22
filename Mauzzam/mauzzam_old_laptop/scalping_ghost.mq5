//+------------------------------------------------------------------+
//| Check if BUY or SELL position already open                       |
//+------------------------------------------------------------------+
bool IsPositionOpen(int type)
{
   if(PositionSelect(_Symbol))  // select open position for current symbol
   {
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetInteger(POSITION_TYPE) == type)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Trailing Stop for current symbol                                 |
//+------------------------------------------------------------------+
void CheckTrailingStop()
{
   if(!PositionSelect(_Symbol)) return; // no open position

   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    type    = (int)PositionGetInteger(POSITION_TYPE);
   double sl      = PositionGetDouble(POSITION_SL);
   double tp      = PositionGetDouble(POSITION_TP);
   double price   = PositionGetDouble(POSITION_PRICE_OPEN);

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.symbol = _Symbol;
   request.magic  = MagicNumber;
   request.tp     = tp;

   if(type == POSITION_TYPE_BUY)
   {
      double newSL = bid - TrailingStop * point;
      if(newSL > sl)
      {
         request.sl = newSL;
         if(!OrderSend(request,result))
            Print("Trailing stop update failed BUY: ",GetLastError());
      }
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double newSL = ask + TrailingStop * point;
      if(newSL < sl || sl == 0)
      {
         request.sl = newSL;
         if(!OrderSend(request,result))
            Print("Trailing stop update failed SELL: ",GetLastError());
      }
   }
}
