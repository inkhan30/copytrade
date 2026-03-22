//+------------------------------------------------------------------+
//|                                            InstitutionalICT.mq5 |
//|                                  Copyright 2024, DeepSeek Trader |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, DeepSeek Trader"
#property link      "https://www.mql5.com"
#property version   "2.0"

#include <Trade/Trade.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>
#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- Risk Management
input double   LotSize              = 0.01;       // Fixed Lot Size (0 for auto)
input double   RiskPercent          = 0.5;        // Risk % for auto lots
input double   MaxDailyLoss         = 1.5;        // Max Daily Loss %
input double   MaxDailyProfit       = 2.5;        // Max Daily Profit %
input int      MaxConsecutiveLosses = 3;          // Max Consecutive Losses
input int      TradeCooldown        = 300;        // Seconds between trades

//--- Multi-Confirmation Settings
input bool     UseMultiConfirmation = true;       // Use multiple confirmations
input int      MinConfirmations     = 3;          // Minimum confirmations needed
input bool     RequireTrendAlign    = true;       // Require trend alignment
input bool     RequireVolumeConfirm = true;       // Require volume confirmation
input bool     RequireTimeFilter    = true;       // Filter by trading hours
input bool     RequireNewsFilter    = false;      // Filter news events (basic)

//--- ICT Concept Parameters
input int      OB_Lookback          = 100;        // Order Blocks lookback
input double   FVG_Threshold        = 1.5;        // FVG minimum size (USD for Gold)
input int      ATR_Period           = 14;         // ATR Period
input int      MA_Fast              = 9;          // Fast MA Period
input int      MA_Slow              = 21;         // Slow MA Period
input int      MA_Trend             = 50;         // Trend MA Period
input int      RSI_Period           = 14;         // RSI Period

//--- Multi-Timeframe Settings
input bool     UseMultiTimeframe    = true;       // Use multiple timeframes
input ENUM_TIMEFRAMES HTF1          = PERIOD_H1;  // Higher TF 1
input ENUM_TIMEFRAMES HTF2          = PERIOD_H4;  // Higher TF 2

//--- Entry Filters
input double   MinConfidence        = 75.0;       // Minimum confidence %
input double   MinTrendStrength     = 20.0;       // Min ADX for trending
input double   MinCandleSizeATR     = 0.3;        // Min candle size (ATR ratio)
input double   MaxSpread            = 30.0;       // Max spread (points)

//--- Exit Settings
input double   RiskRewardRatio      = 1.5;        // Risk:Reward Ratio
input bool     UseTrailingStop      = true;       // Use trailing stop
input double   TrailingStart        = 1.0;        // Start trailing after (x Risk)
input double   TrailingDistance     = 1.5;        // Trailing distance (ATR)

//--- Visualization
input bool     ShowLevels           = true;       // Show ICT Levels
input bool     ShowSignals          = true;       // Show entry signals
input color    ColorBullish         = clrDodgerBlue;
input color    ColorBearish         = clrOrangeRed;
input color    ColorFVG             = clrLimeGreen;
input color    ColorLiquidity       = clrGold;

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
CAccountInfo account;
CPositionInfo position;
CHistoryOrderInfo history;

// Arrays for ICT Levels
CArrayObj *bullishOBs;
CArrayObj *bearishOBs;
CArrayObj *bullishFVGs;
CArrayObj *bearishFVGs;
CArrayObj *liquidityPools;

// Trading State
datetime lastTradeTime;
int consecutiveLosses;
double dailyProfit;
double dailyVolume;
datetime lastDailyReset;
bool tradingEnabled;

// Debug
int debugCounter = 0;
string debugLog = "";

//+------------------------------------------------------------------+
//| ICT Level Class                                                  |
//+------------------------------------------------------------------+
class CICTLevel : public CObject {
public:
   enum TYPE {OB_BULLISH, OB_BEARISH, FVG_BULLISH, FVG_BEARISH, LIQUIDITY};
   
   TYPE type;
   datetime time;
   double price1;
   double price2;
   double price3; // For additional info
   int strength;
   bool mitigated;
   bool active;
   string tag;
   
   CICTLevel(TYPE t, datetime tm, double p1, double p2, double p3=0, int str=1, string tg="") {
      type = t; time = tm; price1 = p1; price2 = p2; price3 = p3;
      strength = str; mitigated = false; active = true; tag = tg;
   }
   
   double GetEntryZoneTop() {
      switch(type) {
         case OB_BULLISH: return price1 - ((price1 - price2) * 0.3);
         case OB_BEARISH: return price2 + ((price1 - price2) * 0.3);
         case FVG_BULLISH: return price1;
         case FVG_BEARISH: return price2;
         default: return price1;
      }
   }
   
   double GetEntryZoneBottom() {
      switch(type) {
         case OB_BULLISH: return price1 - ((price1 - price2) * 0.5);
         case OB_BEARISH: return price2 + ((price1 - price2) * 0.5);
         case FVG_BULLISH: return price2;
         case FVG_BEARISH: return price1;
         default: return price2;
      }
   }
   
   double GetStopLoss() {
      switch(type) {
         case OB_BULLISH: return price2 - ((price1 - price2) * 0.2);
         case OB_BEARISH: return price1 + ((price1 - price2) * 0.2);
         case FVG_BULLISH: return price3;
         case FVG_BEARISH: return price3;
         default: return 0;
      }
   }
};

//+------------------------------------------------------------------+
//| Signal Structure                                                 |
//+------------------------------------------------------------------+
struct TradeSignal {
   bool isBuy;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double confidence;
   int confirmations;
   string reason;
   CICTLevel *level;
   datetime signalTime;
};

//+------------------------------------------------------------------+
//| Confirmation Score Structure                                     |
//+------------------------------------------------------------------+
struct ConfirmationScore {
   int totalPoints;
   int maxPoints;
   string details;
   double confidence;
};

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize arrays
   bullishOBs = new CArrayObj();
   bearishOBs = new CArrayObj();
   bullishFVGs = new CArrayObj();
   bearishFVGs = new CArrayObj();
   liquidityPools = new CArrayObj();
   
   // Initialize trading state
   lastTradeTime = 0;
   consecutiveLosses = 0;
   dailyProfit = 0;
   dailyVolume = 0;
   lastDailyReset = iTime(_Symbol, PERIOD_D1, 0);
   tradingEnabled = true;
   
   // Set magic number
   trade.SetExpertMagicNumber(202412);
   
   // Check trading permissions
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
      Alert("Trading is not allowed!");
      return INIT_FAILED;
   }
   
   Print("=============================================");
   Print("Institutional ICT EA Initialized");
   Print("Symbol: ", _Symbol, " | Timeframe: ", PeriodToString(_Period));
   Print("Account Balance: $", account.Balance());
   Print("Min Confirmations: ", MinConfirmations);
   Print("Min Confidence: ", MinConfidence, "%");
   Print("=============================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Clean up
   delete bullishOBs;
   delete bearishOBs;
   delete bullishFVGs;
   delete bearishFVGs;
   delete liquidityPools;
   
   // Remove drawings
   if(ShowLevels) {
      ObjectsDeleteAll(0, "ICT_");
      ObjectsDeleteAll(0, "SIGNAL_");
   }
   
   Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Check if new candle
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(lastBarTime == currentBarTime) return;
   lastBarTime = currentBarTime;
   
   debugCounter++;
   debugLog = "";
   
   // Reset daily stats at new day
   CheckDailyReset();
   
   // Check trading conditions
   if(!CheckTradingConditions()) {
      Print("Trading conditions not met");
      return;
   }
   
   // Update market analysis
   UpdateMarketAnalysis();
   
   // Check for entry signals
   if(PositionsTotal() == 0 && tradingEnabled) {
      Print("Checking for entry signals...");
      TradeSignal signal = GenerateSignal();
      
      if(debugLog != "") {
         Print("Debug: ", debugLog);
      }
      
      if(signal.confidence > 0) {
         Print("Signal found: Confidence=", signal.confidence, "%, Confirmations=", signal.confirmations);
         Print("Signal Reason: ", signal.reason);
      }
      
      if(signal.confidence >= MinConfidence && 
         signal.confirmations >= MinConfirmations) {
         Print("EXECUTING TRADE: Confidence=", signal.confidence, "%, Confirmations=", signal.confirmations);
         ExecuteTrade(signal);
      } else {
         if(signal.confidence > 0) {
            Print("Signal rejected: Confidence=", signal.confidence, " (min=", MinConfidence, 
                  "), Confirmations=", signal.confirmations, " (min=", MinConfirmations, ")");
         }
      }
   }
   
   // Manage open positions
   if(PositionsTotal() > 0) {
      ManagePositions();
   }
}

//+------------------------------------------------------------------+
//| Update Market Analysis                                           |
//+------------------------------------------------------------------+
void UpdateMarketAnalysis() {
   // Detect ICT Levels
   DetectOrderBlocks();
   DetectFVGs();
   DetectLiquidityPools();
   
   debugLog += "OBs: " + IntegerToString(bullishOBs.Total()) + "B/" + IntegerToString(bearishOBs.Total()) + "S | ";
   debugLog += "FVGs: " + IntegerToString(bullishFVGs.Total()) + "B/" + IntegerToString(bearishFVGs.Total()) + "S | ";
   
   // Draw levels if enabled
   if(ShowLevels) {
      DrawICTLevels();
   }
}

//+------------------------------------------------------------------+
//| 1. ORDER BLOCK DETECTION                                         |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
   bullishOBs.Clear();
   bearishOBs.Clear();
   
   double currentPrice = iClose(_Symbol, _Period, 0);
   double atr = GetCurrentATR();
   
   for(int i = 3; i < OB_Lookback && i < Bars(_Symbol, _Period) - 10; i++) {
      // Bullish Order Block
      if(IsBullishOrderBlock(i, currentPrice, atr)) {
         double high = iHigh(_Symbol, _Period, i);
         double low = iLow(_Symbol, _Period, i);
         datetime time = iTime(_Symbol, _Period, i);
         int strength = CalculateOBStrength(i, true);
         
         CICTLevel *ob = new CICTLevel(CICTLevel::OB_BULLISH, time, high, low, 0, strength, "OB_BULL");
         bullishOBs.Add(ob);
         debugLog += "Found Bullish OB at bar " + IntegerToString(i) + " | ";
      }
      
      // Bearish Order Block
      if(IsBearishOrderBlock(i, currentPrice, atr)) {
         double high = iHigh(_Symbol, _Period, i);
         double low = iLow(_Symbol, _Period, i);
         datetime time = iTime(_Symbol, _Period, i);
         int strength = CalculateOBStrength(i, false);
         
         CICTLevel *ob = new CICTLevel(CICTLevel::OB_BEARISH, time, high, low, 0, strength, "OB_BEAR");
         bearishOBs.Add(ob);
         debugLog += "Found Bearish OB at bar " + IntegerToString(i) + " | ";
      }
   }
}

bool IsBullishOrderBlock(int shift, double currentPrice, double atr) {
   // Candle must be bearish
   if(iClose(_Symbol, _Period, shift) >= iOpen(_Symbol, _Period, shift)) 
      return false;
   
   // Significant candle size
   double candleSize = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
   if(candleSize < atr * MinCandleSizeATR) return false;
   
   // Next 1-3 candles should show bullish reversal
   bool bullishReversal = false;
   for(int j = 1; j <= 3; j++) {
      if(shift - j >= 0) {
         if(iClose(_Symbol, _Period, shift-j) > iOpen(_Symbol, _Period, shift-j)) {
            bullishReversal = true;
            break;
         }
      }
   }
   if(!bullishReversal) return false;
   
   // Price should have moved away (current price > OB high)
   double obHigh = iHigh(_Symbol, _Period, shift);
   
   return (currentPrice > obHigh);
}

bool IsBearishOrderBlock(int shift, double currentPrice, double atr) {
   // Candle must be bullish
   if(iClose(_Symbol, _Period, shift) <= iOpen(_Symbol, _Period, shift)) 
      return false;
   
   double candleSize = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
   if(candleSize < atr * MinCandleSizeATR) return false;
   
   // Next 1-3 candles should show bearish reversal
   bool bearishReversal = false;
   for(int j = 1; j <= 3; j++) {
      if(shift - j >= 0) {
         if(iClose(_Symbol, _Period, shift-j) < iOpen(_Symbol, _Period, shift-j)) {
            bearishReversal = true;
            break;
         }
      }
   }
   if(!bearishReversal) return false;
   
   double obLow = iLow(_Symbol, _Period, shift);
   
   return (currentPrice < obLow);
}

int CalculateOBStrength(int shift, bool isBullish) {
   int strength = 1;
   
   // 1. Volume
   double volume = iVolume(_Symbol, _Period, shift);
   double avgVolume = GetAverageVolume(20);
   if(avgVolume > 0 && volume > avgVolume * 2) strength++;
   
   // 2. Candle size
   double candleSize = iHigh(_Symbol, _Period, shift) - iLow(_Symbol, _Period, shift);
   double avgCandle = GetAverageCandleSize(20);
   if(avgCandle > 0 && candleSize > avgCandle * 2) strength++;
   
   // 3. How far price moved from OB
   double currentPrice = iClose(_Symbol, _Period, 0);
   double obLevel = isBullish ? iHigh(_Symbol, _Period, shift) : iLow(_Symbol, _Period, shift);
   double distance = MathAbs(currentPrice - obLevel);
   double atr = GetCurrentATR();
   
   if(atr > 0 && distance > atr * 2) strength++;
   
   return MathMin(strength, 5);
}

//+------------------------------------------------------------------+
//| 2. FVG DETECTION                                                 |
//+------------------------------------------------------------------+
void DetectFVGs() {
   bullishFVGs.Clear();
   bearishFVGs.Clear();
   
   double currentPrice = iClose(_Symbol, _Period, 0);
   
   for(int i = 2; i < 100 && i < Bars(_Symbol, _Period) - 10; i++) {
      // Bullish FVG
      if(iHigh(_Symbol, _Period, i+1) < iLow(_Symbol, _Period, i-1)) {
         double fvgHigh = iLow(_Symbol, _Period, i-1);
         double fvgLow = iHigh(_Symbol, _Period, i+1);
         double fvgSize = fvgHigh - fvgLow;
         
         if(fvgSize >= FVG_Threshold) {
            if(currentPrice > fvgHigh) {
               CICTLevel *fvg = new CICTLevel(CICTLevel::FVG_BULLISH, 
                  iTime(_Symbol, _Period, i), fvgLow, fvgHigh, 
                  iLow(_Symbol, _Period, i), CalculateFVGStrength(i, true), "FVG_BULL");
               bullishFVGs.Add(fvg);
               debugLog += "Found Bullish FVG at bar " + IntegerToString(i) + " | ";
            }
         }
      }
      
      // Bearish FVG
      if(iLow(_Symbol, _Period, i+1) > iHigh(_Symbol, _Period, i-1)) {
         double fvgLow = iHigh(_Symbol, _Period, i-1);
         double fvgHigh = iLow(_Symbol, _Period, i+1);
         double fvgSize = fvgHigh - fvgLow;
         
         if(fvgSize >= FVG_Threshold) {
            if(currentPrice < fvgLow) {
               CICTLevel *fvg = new CICTLevel(CICTLevel::FVG_BEARISH,
                  iTime(_Symbol, _Period, i), fvgHigh, fvgLow,
                  iHigh(_Symbol, _Period, i), CalculateFVGStrength(i, false), "FVG_BEAR");
               bearishFVGs.Add(fvg);
               debugLog += "Found Bearish FVG at bar " + IntegerToString(i) + " | ";
            }
         }
      }
   }
}

int CalculateFVGStrength(int shift, bool isBullish) {
   int strength = 1;
   
   double volume1 = iVolume(_Symbol, _Period, shift+1);
   double volume2 = iVolume(_Symbol, _Period, shift);
   double volume3 = iVolume(_Symbol, _Period, shift-1);
   double avgVol = (volume1 + volume2 + volume3) / 3;
   double marketAvgVol = GetAverageVolume(20);
   
   if(marketAvgVol > 0 && avgVol > marketAvgVol * 2) strength++;
   
   double atr = GetCurrentATR();
   double fvgSize = MathAbs(iLow(_Symbol, _Period, shift-1) - iHigh(_Symbol, _Period, shift+1));
   
   if(atr > 0 && fvgSize > atr * 0.5) strength++;
   
   int barsUnfilled = BarsSinceTime(iTime(_Symbol, _Period, shift));
   if(barsUnfilled > 20) strength++;
   
   return MathMin(strength, 5);
}

//+------------------------------------------------------------------+
//| 3. LIQUIDITY POOL DETECTION                                      |
//+------------------------------------------------------------------+
void DetectLiquidityPools() {
   liquidityPools.Clear();
   double atr = GetCurrentATR();
   
   // Recent highs (sell stops above)
   for(int i = 0; i < 3; i++) {
      int highestBar = iHighest(_Symbol, _Period, MODE_HIGH, 20, i*20);
      if(highestBar >= 0) {
         double liquidityHigh = iHigh(_Symbol, _Period, highestBar);
         double currentPrice = iClose(_Symbol, _Period, 0);
         
         if(currentPrice < liquidityHigh && 
            MathAbs(currentPrice - liquidityHigh) < atr) {
            CICTLevel *liq = new CICTLevel(CICTLevel::LIQUIDITY,
               iTime(_Symbol, _Period, highestBar),
               liquidityHigh + atr * 0.5,
               liquidityHigh - atr * 0.5,
               0, 3, "LIQ_HIGH");
            liquidityPools.Add(liq);
         }
      }
   }
   
   // Recent lows (buy stops below)
   for(int i = 0; i < 3; i++) {
      int lowestBar = iLowest(_Symbol, _Period, MODE_LOW, 20, i*20);
      if(lowestBar >= 0) {
         double liquidityLow = iLow(_Symbol, _Period, lowestBar);
         double currentPrice = iClose(_Symbol, _Period, 0);
         
         if(currentPrice > liquidityLow &&
            MathAbs(currentPrice - liquidityLow) < atr) {
            CICTLevel *liq = new CICTLevel(CICTLevel::LIQUIDITY,
               iTime(_Symbol, _Period, lowestBar),
               liquidityLow - atr * 0.5,
               liquidityLow + atr * 0.5,
               0, 3, "LIQ_LOW");
            liquidityPools.Add(liq);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 4. MULTI-CONFIRMATION LOGIC (SIMPLIFIED & WORKING)               |
//+------------------------------------------------------------------+
ConfirmationScore CheckConfirmations(TradeSignal &signal) {
   ConfirmationScore score;
   score.totalPoints = 0;
   score.maxPoints = 100;
   score.details = "";
   
   // Track each confirmation
   int trendPoints = 0;
   int pricePoints = 0;
   int volumePoints = 0;
   int mtfPoints = 0;
   int structurePoints = 0;
   
   // 1. TREND CONFIRMATION (25 points)
   if(RequireTrendAlign) {
      trendPoints = CheckTrendConfirmation(signal.isBuy);
      score.totalPoints += trendPoints;
   } else {
      score.totalPoints += 25; // Give points if not required
      trendPoints = 25;
   }
   score.details += "Trend:" + IntegerToString(trendPoints) + " ";
   
   // 2. PRICE ACTION CONFIRMATION (20 points)
   pricePoints = CheckPriceActionConfirmation(signal);
   score.totalPoints += pricePoints;
   score.details += "PA:" + IntegerToString(pricePoints) + " ";
   
   // 3. VOLUME CONFIRMATION (15 points)
   if(RequireVolumeConfirm) {
      volumePoints = CheckVolumeConfirmation(signal);
      score.totalPoints += volumePoints;
   } else {
      score.totalPoints += 15;
      volumePoints = 15;
   }
   score.details += "Vol:" + IntegerToString(volumePoints) + " ";
   
   // 4. MULTI-TIMEFRAME CONFIRMATION (20 points)
   if(UseMultiTimeframe) {
      mtfPoints = CheckMultiTimeframeConfirmation(signal.isBuy);
      score.totalPoints += mtfPoints;
   } else {
      score.totalPoints += 20;
      mtfPoints = 20;
   }
   score.details += "MTF:" + IntegerToString(mtfPoints) + " ";
   
   // 5. MARKET STRUCTURE CONFIRMATION (20 points)
   structurePoints = CheckMarketStructureConfirmation(signal);
   score.totalPoints += structurePoints;
   score.details += "MS:" + IntegerToString(structurePoints) + " ";
   
   // Calculate confidence percentage
   score.confidence = (double)score.totalPoints / score.maxPoints * 100.0;
   
   // Debug
   debugLog += "Conf: T" + IntegerToString(trendPoints) + " P" + IntegerToString(pricePoints) + 
               " V" + IntegerToString(volumePoints) + " M" + IntegerToString(mtfPoints) + 
               " S" + IntegerToString(structurePoints) + " = " + DoubleToString(score.confidence, 1) + "% | ";
   
   return score;
}

int CheckTrendConfirmation(bool isBuy) {
   int points = 0;
   
   // Get current price and MAs using direct calculations
   double currentPrice = iClose(_Symbol, _Period, 0);
   double maFast = CalculateSMA(MA_Fast, 0);
   double maSlow = CalculateSMA(MA_Slow, 0);
   double maTrend = CalculateSMA(MA_Trend, 0);
   
   // Simple MA alignment check
   if(isBuy) {
      if(currentPrice > maFast) points += 5;
      if(maFast > maSlow) points += 5;
      if(maSlow > maTrend) points += 5;
   } else {
      if(currentPrice < maFast) points += 5;
      if(maFast < maSlow) points += 5;
      if(maSlow < maTrend) points += 5;
   }
   
   // Check for trend consistency (last 5 bars)
   int consistency = 0;
   for(int i = 0; i < 5; i++) {
      double price = iClose(_Symbol, _Period, i);
      double fast = CalculateSMA(MA_Fast, i);
      
      if(isBuy && price > fast) consistency++;
      if(!isBuy && price < fast) consistency++;
   }
   
   if(consistency >= 4) points += 5;
   if(consistency == 5) points += 5; // Perfect consistency bonus
   
   return MathMin(points, 25);
}

int CheckPriceActionConfirmation(TradeSignal &signal) {
   int points = 0;
   
   double currentClose = iClose(_Symbol, _Period, 0);
   double currentOpen = iOpen(_Symbol, _Period, 0);
   double prevClose = iClose(_Symbol, _Period, 1);
   double prevOpen = iOpen(_Symbol, _Period, 1);
   
   // Candle direction (5 points)
   if(signal.isBuy && currentClose > currentOpen) {
      points += 5;
   } else if(!signal.isBuy && currentClose < currentOpen) {
      points += 5;
   }
   
   // Momentum (5 points)
   if(signal.isBuy && currentClose > prevClose) {
      points += 5;
   } else if(!signal.isBuy && currentClose < prevClose) {
      points += 5;
   }
   
   // Support/Resistance bounce (10 points)
   double atr = GetCurrentATR();
   if(atr > 0) {
      if(signal.isBuy) {
         // Check if price bounced from support
         double recentLow = GetRecentLow(10);
         if(MathAbs(currentClose - recentLow) < atr * 0.3) {
            points += 10;
         }
      } else {
         // Check if price bounced from resistance
         double recentHigh = GetRecentHigh(10);
         if(MathAbs(currentClose - recentHigh) < atr * 0.3) {
            points += 10;
         }
      }
   }
   
   return MathMin(points, 20);
}

int CheckVolumeConfirmation(TradeSignal &signal) {
   int points = 0;
   
   double currentVolume = iVolume(_Symbol, _Period, 0);
   double prevVolume = iVolume(_Symbol, _Period, 1);
   double avgVolume = GetAverageVolume(20);
   
   // Volume above average (5 points)
   if(avgVolume > 0 && currentVolume > avgVolume * 1.2) {
      points += 5;
   }
   
   // Volume increasing (5 points)
   if(currentVolume > prevVolume * 1.1) {
      points += 5;
   }
   
   // Strong volume confirmation (5 points)
   if(avgVolume > 0 && currentVolume > avgVolume * 1.5 && currentVolume > prevVolume * 1.2) {
      points += 5;
   }
   
   return MathMin(points, 15);
}

int CheckMultiTimeframeConfirmation(bool isBuy) {
   if(!UseMultiTimeframe) return 20;
   
   int points = 0;
   
   // HTF1 Confirmation
   double htf1Price = GetPriceFromTF(HTF1, 0);
   double htf1MAFast = GetMAFromTF(HTF1, MA_Fast, 0);
   double htf1MASlow = GetMAFromTF(HTF1, MA_Slow, 0);
   
   if(htf1Price > 0 && htf1MAFast > 0 && htf1MASlow > 0) {
      if(isBuy && htf1Price > htf1MAFast && htf1MAFast > htf1MASlow) {
         points += 10;
      } else if(!isBuy && htf1Price < htf1MAFast && htf1MAFast < htf1MASlow) {
         points += 10;
      }
   }
   
   // HTF2 Confirmation
   double htf2Price = GetPriceFromTF(HTF2, 0);
   double htf2MAFast = GetMAFromTF(HTF2, MA_Fast, 0);
   double htf2MASlow = GetMAFromTF(HTF2, MA_Slow, 0);
   
   if(htf2Price > 0 && htf2MAFast > 0 && htf2MASlow > 0) {
      if(isBuy && htf2Price > htf2MAFast) {
         points += 10;
      } else if(!isBuy && htf2Price < htf2MAFast) {
         points += 10;
      }
   }
   
   return MathMin(points, 20);
}

int CheckMarketStructureConfirmation(TradeSignal &signal) {
   int points = 0;
   
   // Simple structure check
   if(signal.isBuy) {
      // Check for recent higher low
      double low1 = iLow(_Symbol, _Period, 1);
      double low2 = iLow(_Symbol, _Period, 2);
      double low3 = iLow(_Symbol, _Period, 3);
      
      if(low1 > low2 && low2 > low3) {
         points += 10;
      }
      
      // Check if price above recent swing high
      double recentHigh = GetRecentHigh(10);
      double currentPrice = iClose(_Symbol, _Period, 0);
      if(currentPrice > recentHigh) {
         points += 10;
      }
   } else {
      // Check for recent lower high
      double high1 = iHigh(_Symbol, _Period, 1);
      double high2 = iHigh(_Symbol, _Period, 2);
      double high3 = iHigh(_Symbol, _Period, 3);
      
      if(high1 < high2 && high2 < high3) {
         points += 10;
      }
      
      // Check if price below recent swing low
      double recentLow = GetRecentLow(10);
      double currentPrice = iClose(_Symbol, _Period, 0);
      if(currentPrice < recentLow) {
         points += 10;
      }
   }
   
   return MathMin(points, 20);
}

//+------------------------------------------------------------------+
//| 5. SIGNAL GENERATION                                             |
//+------------------------------------------------------------------+
TradeSignal GenerateSignal() {
   TradeSignal signal;
   signal.isBuy = false;
   signal.confidence = 0;
   signal.confirmations = 0;
   signal.reason = "";
   signal.level = NULL;
   signal.signalTime = TimeCurrent();
   
   // Get current price and ATR for buffer
   double currentPrice = iClose(_Symbol, _Period, 0);
   double atr = GetCurrentATR();
   
   // Check Bullish signals first
   TradeSignal bullishSignal = CheckBullishSignals(currentPrice, atr);
   
   // Check Bearish signals
   TradeSignal bearishSignal = CheckBearishSignals(currentPrice, atr);
   
   // Choose the signal with higher confidence
   if(bullishSignal.confidence > bearishSignal.confidence) {
      signal = bullishSignal;
   } else {
      signal = bearishSignal;
   }
   
   return signal;
}

TradeSignal CheckBullishSignals(double currentPrice, double atr) {
   TradeSignal signal;
   signal.isBuy = false;
   signal.confidence = 0;
   signal.confirmations = 0;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Check Bullish Order Blocks
   for(int i = 0; i < bullishOBs.Total(); i++) {
      CICTLevel *ob = bullishOBs.At(i);
      if(ob.mitigated || !ob.active) continue;
      
      double entryZoneTop = ob.GetEntryZoneTop();
      double entryZoneBottom = ob.GetEntryZoneBottom();
      
      // Check if price is in retest zone with buffer
      double buffer = atr * 0.1;
      if(currentPrice >= (entryZoneBottom - buffer) && currentPrice <= (entryZoneTop + buffer)) {
         TradeSignal testSignal;
         testSignal.isBuy = true;
         testSignal.entryPrice = ask;
         testSignal.stopLoss = ob.GetStopLoss();
         
         // Make sure stop loss is valid
         if(testSignal.stopLoss <= 0 || testSignal.stopLoss >= testSignal.entryPrice) {
            testSignal.stopLoss = testSignal.entryPrice - (atr * 1.5);
         }
         
         testSignal.takeProfit = testSignal.entryPrice + 
                                (testSignal.entryPrice - testSignal.stopLoss) * RiskRewardRatio;
         testSignal.level = ob;
         testSignal.reason = "Bullish OB Retest";
         
         ConfirmationScore score = CheckConfirmations(testSignal);
         testSignal.confidence = score.confidence;
         testSignal.confirmations = (int)(score.totalPoints / 10); // Convert to 1-10 scale
         testSignal.reason += " | " + score.details;
         
         if(testSignal.confidence > signal.confidence) {
            signal = testSignal;
         }
      }
   }
   
   // Check Bullish FVGs
   for(int i = 0; i < bullishFVGs.Total(); i++) {
      CICTLevel *fvg = bullishFVGs.At(i);
      if(fvg.mitigated || !fvg.active) continue;
      
      double buffer = atr * 0.1;
      if(currentPrice >= (fvg.price2 - buffer) && currentPrice <= (fvg.price1 + buffer)) {
         TradeSignal testSignal;
         testSignal.isBuy = true;
         testSignal.entryPrice = ask;
         testSignal.stopLoss = fvg.GetStopLoss();
         
         if(testSignal.stopLoss <= 0 || testSignal.stopLoss >= testSignal.entryPrice) {
            testSignal.stopLoss = testSignal.entryPrice - (atr * 1.5);
         }
         
         testSignal.takeProfit = testSignal.entryPrice + 
                                (testSignal.entryPrice - testSignal.stopLoss) * RiskRewardRatio;
         testSignal.level = fvg;
         testSignal.reason = "Bullish FVG Fill";
         
         ConfirmationScore score = CheckConfirmations(testSignal);
         testSignal.confidence = score.confidence;
         testSignal.confirmations = (int)(score.totalPoints / 10);
         testSignal.reason += " | " + score.details;
         
         if(testSignal.confidence > signal.confidence) {
            signal = testSignal;
         }
      }
   }
   
   return signal;
}

TradeSignal CheckBearishSignals(double currentPrice, double atr) {
   TradeSignal signal;
   signal.isBuy = false;
   signal.confidence = 0;
   signal.confirmations = 0;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Check Bearish Order Blocks
   for(int i = 0; i < bearishOBs.Total(); i++) {
      CICTLevel *ob = bearishOBs.At(i);
      if(ob.mitigated || !ob.active) continue;
      
      double entryZoneTop = ob.GetEntryZoneTop();
      double entryZoneBottom = ob.GetEntryZoneBottom();
      
      double buffer = atr * 0.1;
      if(currentPrice >= (entryZoneBottom - buffer) && currentPrice <= (entryZoneTop + buffer)) {
         TradeSignal testSignal;
         testSignal.isBuy = false;
         testSignal.entryPrice = bid;
         testSignal.stopLoss = ob.GetStopLoss();
         
         if(testSignal.stopLoss <= 0 || testSignal.stopLoss <= testSignal.entryPrice) {
            testSignal.stopLoss = testSignal.entryPrice + (atr * 1.5);
         }
         
         testSignal.takeProfit = testSignal.entryPrice - 
                                (testSignal.stopLoss - testSignal.entryPrice) * RiskRewardRatio;
         testSignal.level = ob;
         testSignal.reason = "Bearish OB Retest";
         
         ConfirmationScore score = CheckConfirmations(testSignal);
         testSignal.confidence = score.confidence;
         testSignal.confirmations = (int)(score.totalPoints / 10);
         testSignal.reason += " | " + score.details;
         
         if(testSignal.confidence > signal.confidence) {
            signal = testSignal;
         }
      }
   }
   
   // Check Bearish FVGs
   for(int i = 0; i < bearishFVGs.Total(); i++) {
      CICTLevel *fvg = bearishFVGs.At(i);
      if(fvg.mitigated || !fvg.active) continue;
      
      double buffer = atr * 0.1;
      if(currentPrice >= (fvg.price2 - buffer) && currentPrice <= (fvg.price1 + buffer)) {
         TradeSignal testSignal;
         testSignal.isBuy = false;
         testSignal.entryPrice = bid;
         testSignal.stopLoss = fvg.GetStopLoss();
         
         if(testSignal.stopLoss <= 0 || testSignal.stopLoss <= testSignal.entryPrice) {
            testSignal.stopLoss = testSignal.entryPrice + (atr * 1.5);
         }
         
         testSignal.takeProfit = testSignal.entryPrice - 
                                (testSignal.stopLoss - testSignal.entryPrice) * RiskRewardRatio;
         testSignal.level = fvg;
         testSignal.reason = "Bearish FVG Fill";
         
         ConfirmationScore score = CheckConfirmations(testSignal);
         testSignal.confidence = score.confidence;
         testSignal.confirmations = (int)(score.totalPoints / 10);
         testSignal.reason += " | " + score.details;
         
         if(testSignal.confidence > signal.confidence) {
            signal = testSignal;
         }
      }
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| 6. TRADE EXECUTION                                               |
//+------------------------------------------------------------------+
void ExecuteTrade(TradeSignal &signal) {
   // Check cooldown
   if(TimeCurrent() - lastTradeTime < TradeCooldown) {
      Print("In cooldown period. Skipping trade.");
      return;
   }
   
   // Calculate position size
   double lotSize = CalculatePositionSize(signal);
   
   if(lotSize <= 0) {
      Print("Invalid lot size calculation.");
      return;
   }
   
   Print("=== EXECUTING TRADE ===");
   Print("Direction: ", signal.isBuy ? "BUY" : "SELL");
   Print("Entry: ", signal.entryPrice);
   Print("Stop Loss: ", signal.stopLoss);
   Print("Take Profit: ", signal.takeProfit);
   Print("Lot Size: ", lotSize);
   Print("Confidence: ", signal.confidence, "%");
   Print("Confirmations: ", signal.confirmations);
   Print("Reason: ", signal.reason);
   Print("=======================");
   
   // Execute trade
   if(signal.isBuy) {
      if(trade.Buy(lotSize, _Symbol, signal.entryPrice, signal.stopLoss, 
                  signal.takeProfit, signal.reason)) {
         OnTradeExecuted(true, signal);
      } else {
         Print("Buy order failed. Error: ", GetLastError());
      }
   } else {
      if(trade.Sell(lotSize, _Symbol, signal.entryPrice, signal.stopLoss, 
                   signal.takeProfit, signal.reason)) {
         OnTradeExecuted(false, signal);
      } else {
         Print("Sell order failed. Error: ", GetLastError());
      }
   }
}

double CalculatePositionSize(TradeSignal &signal) {
   double positionSize = LotSize;
   
   // If LotSize is 0, calculate based on risk
   if(LotSize == 0) {
      double accountBalance = account.Balance();
      double riskAmount = accountBalance * (RiskPercent / 100.0);
      double stopDistance = MathAbs(signal.entryPrice - signal.stopLoss);
      
      // For XAUUSD (Gold), 1.0 lot = 100 ounces
      // Typical point value: $0.01 per point per 0.01 lot
      double pointValue = 0.01;
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize > 0) {
         double riskPoints = stopDistance / tickSize;
         positionSize = riskAmount / (riskPoints * pointValue);
         
         // Convert to standard lot size (1.0 = 100 oz)
         positionSize = positionSize / 100.0;
      }
   }
   
   // Apply broker constraints
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   positionSize = MathMax(positionSize, minLot);
   positionSize = MathMin(positionSize, maxLot);
   
   // Round to nearest lot step
   if(lotStep > 0) {
      positionSize = MathRound(positionSize / lotStep) * lotStep;
   }
   
   return positionSize;
}

void OnTradeExecuted(bool isBuy, TradeSignal &signal) {
   lastTradeTime = TimeCurrent();
   
   if(signal.level != NULL) {
      signal.level.mitigated = true;
   }
   
   // Draw entry on chart
   if(ShowSignals) {
      string objName = "Entry_" + IntegerToString(TimeCurrent());
      if(ObjectCreate(0, objName, OBJ_ARROW_BUY, 0, TimeCurrent(), 
         isBuy ? signal.entryPrice - 0.5 : signal.entryPrice + 0.5)) {
         ObjectSetInteger(0, objName, OBJPROP_COLOR, isBuy ? clrGreen : clrRed);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
      }
   }
}

//+------------------------------------------------------------------+
//| 7. POSITION MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ManagePositions() {
   // Simple position management for now
   // Can be enhanced later
}

//+------------------------------------------------------------------+
//| 8. RISK MANAGEMENT                                               |
//+------------------------------------------------------------------+
bool CheckTradingConditions() {
   // Check if trading is enabled
   if(!tradingEnabled) {
      return false;
   }
   
   // Check spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   if(spread > MaxSpread * _Point) {
      return false;
   }
   
   // Check trading hours
   if(RequireTimeFilter && !IsTradingHours()) {
      return false;
   }
   
   return true;
}

bool IsTradingHours() {
   MqlDateTime dt;
   TimeCurrent(dt);
   int currentHour = dt.hour;
   
   // Trade London & New York overlap (13-16 GMT)
   if(currentHour >= 13 && currentHour < 16) return true;
   
   // Trade London session (8-16 GMT)
   if(currentHour >= 8 && currentHour < 16) return true;
   
   // Trade New York session (13-21 GMT)
   if(currentHour >= 13 && currentHour < 21) return true;
   
   return false;
}

void CheckDailyReset() {
   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   
   if(lastDailyReset != todayStart) {
      dailyProfit = 0;
      dailyVolume = 0;
      lastDailyReset = todayStart;
      consecutiveLosses = 0;
      tradingEnabled = true;
   }
}

//+------------------------------------------------------------------+
//| 9. UTILITY FUNCTIONS (SIMPLIFIED)                                |
//+------------------------------------------------------------------+
double GetAverageVolume(int period) {
   if(period <= 0) return 0;
   
   double total = 0;
   int count = 0;
   
   for(int i = 1; i <= period && i < Bars(_Symbol, _Period); i++) {
      total += iVolume(_Symbol, _Period, i);
      count++;
   }
   
   return count > 0 ? total / count : 0;
}

double GetAverageCandleSize(int period) {
   if(period <= 0) return 0;
   
   double total = 0;
   int count = 0;
   
   for(int i = 1; i <= period && i < Bars(_Symbol, _Period); i++) {
      total += iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i);
      count++;
   }
   
   return count > 0 ? total / count : 0;
}

double GetCurrentATR() {
   // Simple ATR calculation
   double atr = 0;
   int period = ATR_Period;
   
   if(period < 1) period = 14;
   
   for(int i = 0; i < period && i < Bars(_Symbol, _Period); i++) {
      double tr = MathMax(
         iHigh(_Symbol, _Period, i) - iLow(_Symbol, _Period, i),
         MathMax(
            MathAbs(iHigh(_Symbol, _Period, i) - iClose(_Symbol, _Period, i+1)),
            MathAbs(iLow(_Symbol, _Period, i) - iClose(_Symbol, _Period, i+1))
         )
      );
      atr += tr;
   }
   
   return atr / period;
}

double CalculateSMA(int period, int shift) {
   if(period <= 0) return 0;
   
   double sum = 0;
   int count = 0;
   
   for(int i = shift; i < shift + period && i < Bars(_Symbol, _Period); i++) {
      sum += iClose(_Symbol, _Period, i);
      count++;
   }
   
   return count > 0 ? sum / count : 0;
}

double GetPriceFromTF(ENUM_TIMEFRAMES tf, int shift) {
   datetime current = iTime(_Symbol, _Period, 0);
   int barShift = iBarShift(_Symbol, tf, current);
   
   if(barShift >= 0) {
      return iClose(_Symbol, tf, barShift + shift);
   }
   
   return 0;
}

double GetMAFromTF(ENUM_TIMEFRAMES tf, int period, int shift) {
   datetime current = iTime(_Symbol, _Period, 0);
   int barShift = iBarShift(_Symbol, tf, current);
   
   if(barShift >= 0) {
      double sum = 0;
      int count = 0;
      
      for(int i = barShift + shift; i < barShift + shift + period; i++) {
         if(i >= 0) {
            double price = iClose(_Symbol, tf, i);
            if(price > 0) {
               sum += price;
               count++;
            }
         }
      }
      
      return count > 0 ? sum / count : 0;
   }
   
   return 0;
}

int BarsSinceTime(datetime time) {
   return iBarShift(_Symbol, _Period, time);
}

double GetRecentHigh(int lookback) {
   double highest = 0;
   
   for(int i = 0; i < lookback && i < Bars(_Symbol, _Period); i++) {
      double high = iHigh(_Symbol, _Period, i);
      if(high > highest) highest = high;
   }
   
   return highest;
}

double GetRecentLow(int lookback) {
   double lowest = DBL_MAX;
   
   for(int i = 0; i < lookback && i < Bars(_Symbol, _Period); i++) {
      double low = iLow(_Symbol, _Period, i);
      if(low < lowest) lowest = low;
   }
   
   return lowest;
}

string PeriodToString(ENUM_TIMEFRAMES period) {
   switch(period) {
      case PERIOD_M1: return "M1";
      case PERIOD_M5: return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      case PERIOD_W1: return "W1";
      case PERIOD_MN1: return "MN1";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| 10. VISUALIZATION                                                |
//+------------------------------------------------------------------+
void DrawICTLevels() {
   if(!ShowLevels) return;
   
   // Clear old drawings
   ObjectsDeleteAll(0, "ICT_");
   
   // Draw Bullish OBs
   for(int i = 0; i < bullishOBs.Total(); i++) {
      CICTLevel *ob = bullishOBs.At(i);
      if(ob.active && !ob.mitigated) {
         DrawOrderBlock(ob, "OB_BULL_", ColorBullish);
      }
   }
   
   // Draw Bearish OBs
   for(int i = 0; i < bearishOBs.Total(); i++) {
      CICTLevel *ob = bearishOBs.At(i);
      if(ob.active && !ob.mitigated) {
         DrawOrderBlock(ob, "OB_BEAR_", ColorBearish);
      }
   }
   
   // Draw Bullish FVGs
   for(int i = 0; i < bullishFVGs.Total(); i++) {
      CICTLevel *fvg = bullishFVGs.At(i);
      if(fvg.active && !fvg.mitigated) {
         DrawFVG(fvg, "FVG_BULL_", ColorFVG);
      }
   }
   
   // Draw Bearish FVGs
   for(int i = 0; i < bearishFVGs.Total(); i++) {
      CICTLevel *fvg = bearishFVGs.At(i);
      if(fvg.active && !fvg.mitigated) {
         DrawFVG(fvg, "FVG_BEAR_", ColorFVG);
      }
   }
}

void DrawOrderBlock(CICTLevel *ob, string prefix, color clr) {
   string name = prefix + IntegerToString(ob.time);
   
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, ob.time, ob.price1, 
                  ob.time + PeriodSeconds(_Period) * 5, ob.price2)) {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      //ObjectSetInteger(0, name, OBJPROP_OPACITY, 20);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}

void DrawFVG(CICTLevel *fvg, string prefix, color clr) {
   string name = prefix + IntegerToString(fvg.time);
   
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, fvg.time, fvg.price1, 
                  fvg.time + PeriodSeconds(_Period) * 3, fvg.price2)) {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      //ObjectSetInteger(0, name, OBJPROP_OPACITY, 30);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}
//+------------------------------------------------------------------+