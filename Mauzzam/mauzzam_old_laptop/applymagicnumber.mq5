//+------------------------------------------------------------------+
//| ApplyMagicNumber.mq5                                            |
//| Script to provide instructions for managing magic numbers       |
//+------------------------------------------------------------------+

#property copyright "Deepseek AI Assistant"
#property version   "1.00"
#property description "Provides instructions for managing magic numbers in MQL5"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    string message = "MQL5 Magic Number Management:\n\n" +
                    "In MQL5, magic numbers cannot be modified for existing positions.\n\n" +
                    "To use the AutoSLTP EA with your manual trades:\n" +
                    "1. Attach the EA to your chart before opening new positions\n" +
                    "2. The EA will automatically apply SL/TP to new positions\n" +
                    "3. For existing positions, you need to close them and reopen\n" +
                    "   with the EA attached to have them managed automatically\n\n" +
                    "The EA will use magic number: 12345 (configurable in inputs)";
    
    Alert(message);
    Print(message);
    
    // Show current positions
    int total = PositionsTotal();
    Print("Current positions for ", _Symbol, ": ", total);
    
    for(int i = 0; i < total; i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            Print("Position #", ticket, " Magic: ", magic);
        }
    }
}