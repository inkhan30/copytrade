#include <Trade/Trade.mqh>
CTrade trade;

input double LotSize = 0.1;
input int StopLossPips = 50;
input int TakeProfitPips = 100;

// Signal Scoring System
struct EntrySignal {
    int score;          // Total score (higher = stronger)
    bool isBuy;         // True for buy, false for sell
    string reason;      // Why this signal triggered
    double confidence;  // 0.0 to 1.0
};

EntrySignal GetCompositeSignal() {
    EntrySignal signal;
    signal.score = 0;
    signal.confidence = 0.0;
    
    // 1. Trend Direction (40% weight)
    if(isUptrend()) {
        signal.score += 40;
        signal.isBuy = true;
        signal.reason += "Uptrend; ";
    } else if(isDowntrend()) {
        signal.score += 40;
        signal.isBuy = false;
        signal.reason += "Downtrend; ";
    }
    
    // 2. Momentum (30% weight)
    RSI_SIGNAL rsiSignal = GetRSISignal();
    if((rsiSignal == RSI_OVERSOLD_BUY && signal.isBuy) ||
       (rsiSignal == RSI_OVERBOUGHT_SELL && !signal.isBuy)) {
        signal.score += 30;
        signal.reason += "RSI confirmed; ";
    }
    
    // 3. Price Action (20% weight)
    if((IsBullishPinBar() && signal.isBuy) ||
       (IsBearishPinBar() && !signal.isBuy)) {
        signal.score += 20;
        signal.reason += "Pin bar pattern; ";
    }
    
    // 4. Volume Confirmation (10% weight)
    if(IsVolumeSpike()) {
        signal.score += 10;
        signal.reason += "Volume spike; ";
    }
    
    // Calculate confidence
    signal.confidence = signal.score / 100.0;
    
    return signal;
}

bool isUptrend() {
    double fastMA = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE, 0);
    double slowMA = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE, 0);
    return fastMA > slowMA;
}

bool isDowntrend() {
    double fastMA = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE, 0);
    double slowMA = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE, 0);
    return fastMA < slowMA;
}

void OnTick() {
    // Only check at new bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(lastBarTime == currentBarTime) return;
    lastBarTime = currentBarTime;
    
    // Get signal
    EntrySignal signal = GetCompositeSignal();
    
    // Minimum threshold for entry
    if(signal.score >= 70 && signal.confidence >= 0.7) {
        ExecuteTrade(signal);
    }
}

void ExecuteTrade(EntrySignal &signal) {
    double price = signal.isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double sl = signal.isBuy ? price - StopLossPips * _Point
                              : price + StopLossPips * _Point;
    
    double tp = signal.isBuy ? price + TakeProfitPips * _Point
                              : price - TakeProfitPips * _Point;
    
    if(signal.isBuy) {
        trade.Buy(LotSize, _Symbol, price, sl, tp, signal.reason);
    } else {
        trade.Sell(LotSize, _Symbol, price, sl, tp, signal.reason);
    }
    
    Print("Entry executed: ", signal.reason, 
          " Score: ", signal.score, 
          " Confidence: ", signal.confidence);
}