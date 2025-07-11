//+------------------------------------------------------------------+
//|                                                 GoldSniperEA.mq5 |
//|                                    Institutional Gold Sniper EA |
//|                                              Built for XAUUSD   |
//+------------------------------------------------------------------+
#property copyright   "Gold Sniper EA"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Autonomous XAUUSD EA using ICT & Smart Money Concepts"

//--- EA Properties
#property strict
#include <Trade\Trade.mqh>

//--- Global Trading Objects
CTrade trade;
CPositionInfo position;
COrderInfo order;

//--- Input Parameters
input group "=== RISK MANAGEMENT ==="
input double MinLotSize = 0.01;              // Minimum lot size
input double MaxRiskPercent = 5.0;           // Max risk per trade (%)
input bool EnableUltraMicroMode = true;      // Enable Ultra-Micro mode for small accounts
input double UltraMicroThreshold = 20.0;    // Ultra-Micro mode threshold ($)
input double SafeModeThreshold = 500.0;     // Safe to Turbo mode threshold ($)

input group "=== TRADING LOGIC ==="
input bool EnableScalping = true;           // Enable M1-M15 scalping
input bool EnableSwing = true;              // Enable H1-H4 swing trading
input bool EnablePosition = true;           // Enable D1-W1 position trading
input int MaxSpreadPoints = 30;             // Max spread in points
input bool RequireVolumeConfirmation = true; // Require volume confirmation

input group "=== SESSION FILTERS ==="
input bool EnableAsiaSession = true;        // Enable Asia session (23:00-08:00)
input bool EnableLondonSession = true;      // Enable London session (07:00-16:00)
input bool EnableNYSession = true;          // Enable NY session (13:00-22:00)
input bool AllowOutOfSessionIfPerfect = true; // Allow trades outside sessions if perfect setup

input group "=== VISUAL SETTINGS ==="
input bool ShowDashboard = true;            // Show on-chart dashboard
input bool ShowOrderBlocks = true;          // Show Order Blocks
input bool ShowFVG = true;                  // Show Fair Value Gaps
input bool ShowStructure = true;            // Show BOS/CHoCH
input color DashboardColor = clrWhite;      // Dashboard text color
input int DashboardFontSize = 10;           // Dashboard font size

//--- Global Variables
enum TRADE_MODE {
    MODE_ULTRA_MICRO,    // $5-$20: High risk sniper-only
    MODE_SAFE,           // $20-$500: Capital protection
    MODE_TURBO           // $500+: High compounding
};

enum MARKET_STRUCTURE {
    STRUCTURE_BULLISH,
    STRUCTURE_BEARISH,
    STRUCTURE_RANGING
};

enum TRADE_TYPE {
    TRADE_SCALP,
    TRADE_SWING,
    TRADE_POSITION
};

struct OrderBlock {
    datetime time;
    double high;
    double low;
    double volume;
    bool is_bullish;
    bool is_valid;
    int timeframe;
};

struct FairValueGap {
    datetime time;
    double high;
    double low;
    bool is_bullish;
    bool is_valid;
    int timeframe;
};

struct LiquidityLevel {
    double price;
    datetime time;
    bool is_high;
    bool is_swept;
    int touches;
};

//--- Global Arrays and Variables
OrderBlock g_orderBlocks[];
FairValueGap g_fairValueGaps[];
LiquidityLevel g_liquidityLevels[];

TRADE_MODE g_currentMode = MODE_SAFE;
MARKET_STRUCTURE g_marketStructure = STRUCTURE_RANGING;
double g_currentSpread = 0;
double g_accountLeverage = 0;
double g_dailyDrawdown = 0;
datetime g_lastTradeTime = 0;
double g_dayStartBalance = 0;
int g_dailyTradeCount = 0;
bool g_tradingEnabled = true;

//--- Dashboard Variables
string g_dashboardText = "";
int g_dashboardX = 20;
int g_dashboardY = 30;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Validate symbol
    if(Symbol() != "XAUUSD" && StringFind(Symbol(), "GOLD") == -1 && StringFind(Symbol(), "XAU") == -1) {
        Print("WARNING: This EA is designed specifically for XAUUSD/Gold trading!");
    }
    
    // Initialize arrays
    ArrayResize(g_orderBlocks, 100);
    ArrayResize(g_fairValueGaps, 100);
    ArrayResize(g_liquidityLevels, 50);
    
    // Initialize trading objects
    trade.SetExpertMagicNumber(987654321);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Detect account properties
    DetectAccountProperties();
    
    // Set day start balance
    g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Initialize dashboard
    if(ShowDashboard) {
        CreateDashboard();
    }
    
    Print("Gold Sniper EA initialized successfully");
    Print("Account Balance: $", AccountInfoDouble(ACCOUNT_BALANCE));
    Print("Current Mode: ", EnumToString(g_currentMode));
    Print("Leverage: 1:", g_accountLeverage);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up dashboard
    if(ShowDashboard) {
        ObjectsDeleteAll(0, "Dashboard_");
    }
    
    // Clean up chart objects
    ObjectsDeleteAll(0, "OB_");
    ObjectsDeleteAll(0, "FVG_");
    ObjectsDeleteAll(0, "BOS_");
    ObjectsDeleteAll(0, "CHoCH_");
    
    Print("Gold Sniper EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Update current spread
    g_currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    
    // Check if spread is too wide
    if(g_currentSpread > MaxSpreadPoints) {
        return;
    }
    
    // Update trading mode based on account balance
    UpdateTradingMode();
    
    // Check daily drawdown limits
    CheckDailyDrawdown();
    
    // Update market structure analysis
    UpdateMarketStructure();
    
    // Update order blocks and FVGs
    UpdateOrderBlocks();
    UpdateFairValueGaps();
    UpdateLiquidityLevels();
    
    // Check for trading opportunities
    if(g_tradingEnabled && IsSessionActive()) {
        CheckTradingOpportunities();
    }
    
    // Manage existing trades
    ManageExistingTrades();
    
    // Update dashboard
    if(ShowDashboard) {
        UpdateDashboard();
    }
}

//+------------------------------------------------------------------+
//| Detect account properties                                        |
//+------------------------------------------------------------------+
void DetectAccountProperties() {
    // Detect leverage
    g_accountLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    if(g_accountLeverage == 0) g_accountLeverage = 100; // Default fallback
    
    // Detect account type
    string accountType = "Unknown";
    double commission = SymbolInfoDouble(Symbol(), SYMBOL_COMMISSION_TYPE);
    
    if(commission == 0) {
        accountType = "Standard/STP";
    } else {
        accountType = "Raw/ECN";
    }
    
    Print("Account Type Detected: ", accountType);
    Print("Leverage Detected: 1:", g_accountLeverage);
    Print("Spread: ", g_currentSpread, " points");
}

//+------------------------------------------------------------------+
//| Update trading mode based on account balance                    |
//+------------------------------------------------------------------+
void UpdateTradingMode() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(EnableUltraMicroMode && balance <= UltraMicroThreshold) {
        g_currentMode = MODE_ULTRA_MICRO;
    } else if(balance <= SafeModeThreshold) {
        g_currentMode = MODE_SAFE;
    } else {
        g_currentMode = MODE_TURBO;
    }
}

//+------------------------------------------------------------------+
//| Check daily drawdown limits                                     |
//+------------------------------------------------------------------+
void CheckDailyDrawdown() {
    // Reset daily counters at start of new day
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    static int lastDay = -1;
    if(dt.day != lastDay) {
        lastDay = dt.day;
        g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_dailyDrawdown = 0;
        g_dailyTradeCount = 0;
    }
    
    // Calculate current daily drawdown
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_dailyDrawdown = (g_dayStartBalance - currentBalance) / g_dayStartBalance * 100;
    
    // Disable trading if daily drawdown exceeds limit (Safe mode only)
    if(g_currentMode == MODE_SAFE && g_dailyDrawdown > 15.0) {
        g_tradingEnabled = false;
        Print("Daily drawdown limit reached. Trading disabled for today.");
    } else {
        g_tradingEnabled = true;
    }
}

//+------------------------------------------------------------------+
//| Check if current session allows trading                         |
//+------------------------------------------------------------------+
bool IsSessionActive() {
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    int hour = dt.hour;
    int dayOfWeek = dt.day_of_week;
    
    // Skip Friday NY close and Monday Asia open
    if(dayOfWeek == 5 && hour >= 21) return false; // Friday after 21:00
    if(dayOfWeek == 1 && hour <= 1) return false;  // Monday before 01:00
    
    // Check session times (GMT)
    bool asiaSession = (hour >= 23 || hour <= 8) && EnableAsiaSession;
    bool londonSession = (hour >= 7 && hour <= 16) && EnableLondonSession;
    bool nySession = (hour >= 13 && hour <= 22) && EnableNYSession;
    
    return asiaSession || londonSession || nySession;
}

//+------------------------------------------------------------------+
//| Update market structure analysis                                 |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
    // Get recent high and low prices
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol(), PERIOD_H1, 0, 50, high) <= 0) return;
    if(CopyLow(Symbol(), PERIOD_H1, 0, 50, low) <= 0) return;
    if(CopyClose(Symbol(), PERIOD_H1, 0, 50, close) <= 0) return;
    
    // Simple structure analysis
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double recent20High = high[ArrayMaximum(high, 1, 20)];
    double recent20Low = low[ArrayMinimum(low, 1, 20)];
    
    if(currentPrice > recent20High * 0.999) {
        g_marketStructure = STRUCTURE_BULLISH;
    } else if(currentPrice < recent20Low * 1.001) {
        g_marketStructure = STRUCTURE_BEARISH;
    } else {
        g_marketStructure = STRUCTURE_RANGING;
    }
}

//+------------------------------------------------------------------+
//| Update order blocks                                              |
//+------------------------------------------------------------------+
void UpdateOrderBlocks() {
    // Clear old invalid order blocks
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].is_valid) {
            // Check if order block is still valid (not violated)
            double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            if(g_orderBlocks[i].is_bullish && currentPrice < g_orderBlocks[i].low) {
                g_orderBlocks[i].is_valid = false;
            } else if(!g_orderBlocks[i].is_bullish && currentPrice > g_orderBlocks[i].high) {
                g_orderBlocks[i].is_valid = false;
            }
        }
    }
    
    // Detect new order blocks on multiple timeframes
    DetectOrderBlocks(PERIOD_M15);
    DetectOrderBlocks(PERIOD_H1);
    DetectOrderBlocks(PERIOD_H4);
    
    // Draw order blocks if enabled
    if(ShowOrderBlocks) {
        DrawOrderBlocks();
    }
}

//+------------------------------------------------------------------+
//| Detect order blocks on specific timeframe                       |
//+------------------------------------------------------------------+
void DetectOrderBlocks(ENUM_TIMEFRAMES timeframe) {
    double high[], low[], close[], volume[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(volume, true);
    
    if(CopyHigh(Symbol(), timeframe, 0, 20, high) <= 0) return;
    if(CopyLow(Symbol(), timeframe, 0, 20, low) <= 0) return;
    if(CopyClose(Symbol(), timeframe, 0, 20, close) <= 0) return;
    if(CopyTickVolume(Symbol(), timeframe, 0, 20, volume) <= 0) return;
    
    // Look for order blocks (strong rejection candles with high volume)
    for(int i = 3; i < 15; i++) {
        double bodySize = MathAbs(close[i] - close[i+1]);
        double candleRange = high[i] - low[i];
        double volumeRatio = volume[i] / ((volume[i+1] + volume[i+2] + volume[i+3]) / 3.0);
        
        // Bullish order block criteria
        if(low[i] < low[i+1] && low[i] < low[i-1] && 
           high[i] > high[i+1] && volumeRatio > 1.5 &&
           bodySize > candleRange * 0.6) {
            
            AddOrderBlock(iTime(Symbol(), timeframe, i), high[i], low[i], volume[i], true, timeframe);
        }
        
        // Bearish order block criteria
        if(high[i] > high[i+1] && high[i] > high[i-1] && 
           low[i] < low[i+1] && volumeRatio > 1.5 &&
           bodySize > candleRange * 0.6) {
            
            AddOrderBlock(iTime(Symbol(), timeframe, i), high[i], low[i], volume[i], false, timeframe);
        }
    }
}

//+------------------------------------------------------------------+
//| Add order block to array                                         |
//+------------------------------------------------------------------+
void AddOrderBlock(datetime time, double high, double low, double vol, bool is_bullish, int tf) {
    // Find empty slot or replace oldest
    int index = -1;
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].is_valid) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        // Replace oldest
        index = 0;
        for(int i = 1; i < ArraySize(g_orderBlocks); i++) {
            if(g_orderBlocks[i].time < g_orderBlocks[index].time) {
                index = i;
            }
        }
    }
    
    g_orderBlocks[index].time = time;
    g_orderBlocks[index].high = high;
    g_orderBlocks[index].low = low;
    g_orderBlocks[index].volume = vol;
    g_orderBlocks[index].is_bullish = is_bullish;
    g_orderBlocks[index].is_valid = true;
    g_orderBlocks[index].timeframe = tf;
}

//+------------------------------------------------------------------+
//| Update Fair Value Gaps                                          |
//+------------------------------------------------------------------+
void UpdateFairValueGaps() {
    // Clear old invalid FVGs
    for(int i = 0; i < ArraySize(g_fairValueGaps); i++) {
        if(g_fairValueGaps[i].is_valid) {
            double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            // FVG is invalid if price has moved through it
            if(currentPrice > g_fairValueGaps[i].low && currentPrice < g_fairValueGaps[i].high) {
                g_fairValueGaps[i].is_valid = false;
            }
        }
    }
    
    // Detect new FVGs
    DetectFairValueGaps(PERIOD_M15);
    DetectFairValueGaps(PERIOD_H1);
    DetectFairValueGaps(PERIOD_H4);
    
    // Draw FVGs if enabled
    if(ShowFVG) {
        DrawFairValueGaps();
    }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps                                          |
//+------------------------------------------------------------------+
void DetectFairValueGaps(ENUM_TIMEFRAMES timeframe) {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(Symbol(), timeframe, 0, 20, high) <= 0) return;
    if(CopyLow(Symbol(), timeframe, 0, 20, low) <= 0) return;
    
    // Look for gaps between candles
    for(int i = 2; i < 15; i++) {
        // Bullish FVG: gap between low[i+1] and high[i-1]
        if(low[i+1] > high[i-1]) {
            double gapSize = low[i+1] - high[i-1];
            double atr = CalculateATR(timeframe, 14);
            
            if(gapSize > atr * 0.3) { // Significant gap
                AddFairValueGap(iTime(Symbol(), timeframe, i), low[i+1], high[i-1], true, timeframe);
            }
        }
        
        // Bearish FVG: gap between high[i+1] and low[i-1]
        if(high[i+1] < low[i-1]) {
            double gapSize = low[i-1] - high[i+1];
            double atr = CalculateATR(timeframe, 14);
            
            if(gapSize > atr * 0.3) { // Significant gap
                AddFairValueGap(iTime(Symbol(), timeframe, i), low[i-1], high[i+1], false, timeframe);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Add Fair Value Gap to array                                     |
//+------------------------------------------------------------------+
void AddFairValueGap(datetime time, double high, double low, bool is_bullish, int tf) {
    int index = -1;
    for(int i = 0; i < ArraySize(g_fairValueGaps); i++) {
        if(!g_fairValueGaps[i].is_valid) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        index = 0;
        for(int i = 1; i < ArraySize(g_fairValueGaps); i++) {
            if(g_fairValueGaps[i].time < g_fairValueGaps[index].time) {
                index = i;
            }
        }
    }
    
    g_fairValueGaps[index].time = time;
    g_fairValueGaps[index].high = high;
    g_fairValueGaps[index].low = low;
    g_fairValueGaps[index].is_bullish = is_bullish;
    g_fairValueGaps[index].is_valid = true;
    g_fairValueGaps[index].timeframe = tf;
}

//+------------------------------------------------------------------+
//| Update liquidity levels                                          |
//+------------------------------------------------------------------+
void UpdateLiquidityLevels() {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(Symbol(), PERIOD_H1, 0, 50, high) <= 0) return;
    if(CopyLow(Symbol(), PERIOD_H1, 0, 50, low) <= 0) return;
    
    // Find equal highs and lows
    for(int i = 2; i < 45; i++) {
        // Equal highs
        if(MathAbs(high[i] - high[i+1]) < Point() * 5 && 
           MathAbs(high[i] - high[i+2]) < Point() * 5) {
            AddLiquidityLevel(high[i], iTime(Symbol(), PERIOD_H1, i), true);
        }
        
        // Equal lows
        if(MathAbs(low[i] - low[i+1]) < Point() * 5 && 
           MathAbs(low[i] - low[i+2]) < Point() * 5) {
            AddLiquidityLevel(low[i], iTime(Symbol(), PERIOD_H1, i), false);
        }
    }
}

//+------------------------------------------------------------------+
//| Add liquidity level                                              |
//+------------------------------------------------------------------+
void AddLiquidityLevel(double price, datetime time, bool is_high) {
    int index = -1;
    
    // Check if level already exists
    for(int i = 0; i < ArraySize(g_liquidityLevels); i++) {
        if(MathAbs(g_liquidityLevels[i].price - price) < Point() * 10) {
            g_liquidityLevels[i].touches++;
            return;
        }
        if(g_liquidityLevels[i].price == 0) {
            index = i;
            break;
        }
    }
    
    if(index == -1) return;
    
    g_liquidityLevels[index].price = price;
    g_liquidityLevels[index].time = time;
    g_liquidityLevels[index].is_high = is_high;
    g_liquidityLevels[index].is_swept = false;
    g_liquidityLevels[index].touches = 1;
}

//+------------------------------------------------------------------+
//| Check for trading opportunities                                  |
//+------------------------------------------------------------------+
void CheckTradingOpportunities() {
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Check for sniper entries
    CheckSniperEntries();
    
    // Check different trade types based on timeframe
    if(EnableScalping) CheckScalpingOpportunities();
    if(EnableSwing) CheckSwingOpportunities();
    if(EnablePosition) CheckPositionOpportunities();
}

//+------------------------------------------------------------------+
//| Check for sniper entries (highest probability setups)           |
//+------------------------------------------------------------------+
void CheckSniperEntries() {
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double atr = CalculateATR(PERIOD_H1, 14);
    
    // Look for confluence: OB + FVG + Structure + Volume
    for(int ob = 0; ob < ArraySize(g_orderBlocks); ob++) {
        if(!g_orderBlocks[ob].is_valid) continue;
        
        // Check if price is near order block
        bool nearOB = false;
        if(g_orderBlocks[ob].is_bullish && 
           currentPrice >= g_orderBlocks[ob].low && 
           currentPrice <= g_orderBlocks[ob].high + atr * 0.2) {
            nearOB = true;
        } else if(!g_orderBlocks[ob].is_bullish && 
                  currentPrice <= g_orderBlocks[ob].high && 
                  currentPrice >= g_orderBlocks[ob].low - atr * 0.2) {
            nearOB = true;
        }
        
        if(!nearOB) continue;
        
        // Look for FVG in same direction
        bool fvgConfirmation = false;
        for(int fvg = 0; fvg < ArraySize(g_fairValueGaps); fvg++) {
            if(!g_fairValueGaps[fvg].is_valid) continue;
            
            if(g_orderBlocks[ob].is_bullish == g_fairValueGaps[fvg].is_bullish &&
               currentPrice >= g_fairValueGaps[fvg].low &&
               currentPrice <= g_fairValueGaps[fvg].high) {
                fvgConfirmation = true;
                break;
            }
        }
        
        // Check volume confirmation
        bool volumeConfirmation = true;
        if(RequireVolumeConfirmation) {
            volumeConfirmation = CheckVolumeConfirmation();
        }
        
        // Check displacement (price movement confirmation)
        bool displacement = CheckDisplacement(g_orderBlocks[ob].is_bullish);
        
        // Execute sniper entry if all conditions met
        if(fvgConfirmation && volumeConfirmation && displacement) {
            ExecuteSniperEntry(g_orderBlocks[ob].is_bullish, currentPrice, atr);
            break; // Only one sniper entry at a time
        }
    }
}

//+------------------------------------------------------------------+
//| Check volume confirmation                                        |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation() {
    double volume[];
    ArraySetAsSeries(volume, true);
    
    if(CopyTickVolume(Symbol(), PERIOD_M15, 0, 5, volume) <= 0) return false;
    
    double avgVolume = (volume[1] + volume[2] + volume[3]) / 3.0;
    return volume[0] > avgVolume * 1.3; // Current volume 30% above average
}

//+------------------------------------------------------------------+
//| Check displacement                                               |
//+------------------------------------------------------------------+
bool CheckDisplacement(bool is_bullish) {
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol(), PERIOD_M15, 0, 5, high) <= 0) return false;
    if(CopyLow(Symbol(), PERIOD_M15, 0, 5, low) <= 0) return false;
    if(CopyClose(Symbol(), PERIOD_M15, 0, 5, close) <= 0) return false;
    
    double displacement = 0;
    if(is_bullish) {
        displacement = high[0] - low[2];
    } else {
        displacement = high[2] - low[0];
    }
    
    double atr = CalculateATR(PERIOD_M15, 14);
    return displacement > atr * 0.5; // Significant displacement
}

//+------------------------------------------------------------------+
//| Execute sniper entry                                             |
//+------------------------------------------------------------------+
void ExecuteSniperEntry(bool is_buy, double entry_price, double atr) {
    // Calculate lot size based on current mode and risk
    double lotSize = CalculateLotSize(atr);
    if(lotSize < MinLotSize) return;
    
    // Calculate SL and TP based on structure
    double sl, tp;
    CalculateStructuralSLTP(is_buy, entry_price, atr, sl, tp);
    
    // Adjust for spread
    double spread = g_currentSpread * Point();
    if(is_buy) {
        entry_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        sl -= spread;
    } else {
        entry_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        sl += spread;
    }
    
    // Validate SL distance
    double minSL = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * Point();
    if(MathAbs(entry_price - sl) < minSL + spread) {
        Print("SL too close to current price. Skipping trade.");
        return;
    }
    
    // Execute trade
    string comment = StringFormat("Sniper_%s_M%d", 
                                  is_buy ? "BUY" : "SELL", 
                                  g_currentMode);
    
    bool result;
    if(is_buy) {
        result = trade.Buy(lotSize, Symbol(), entry_price, sl, tp, comment);
    } else {
        result = trade.Sell(lotSize, Symbol(), entry_price, sl, tp, comment);
    }
    
    if(result) {
        g_lastTradeTime = TimeCurrent();
        g_dailyTradeCount++;
        Print(StringFormat("Sniper entry executed: %s %.2f lots at %.5f, SL: %.5f, TP: %.5f",
                          is_buy ? "BUY" : "SELL", lotSize, entry_price, sl, tp));
    } else {
        Print("Trade execution failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double atr) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskPercent;
    
    // Determine risk based on current mode
    switch(g_currentMode) {
        case MODE_ULTRA_MICRO:
            riskPercent = 20.0; // High risk for small accounts
            break;
        case MODE_SAFE:
            riskPercent = MaxRiskPercent;
            break;
        case MODE_TURBO:
            riskPercent = MaxRiskPercent * 1.5;
            break;
    }
    
    double riskAmount = balance * riskPercent / 100.0;
    double slDistance = atr * 1.5; // Typical SL distance
    
    double lotSize = riskAmount / (slDistance / Point() * SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE));
    
    // Apply lot size limits
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
    
    // Additional safety for small accounts
    if(balance < 100 && lotSize > balance / 1000) {
        lotSize = balance / 1000;
        lotSize = MathMax(lotSize, minLot);
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate structural SL and TP                                  |
//+------------------------------------------------------------------+
void CalculateStructuralSLTP(bool is_buy, double entry, double atr, double &sl, double &tp) {
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    CopyHigh(Symbol(), PERIOD_H1, 0, 20, high);
    CopyLow(Symbol(), PERIOD_H1, 0, 20, low);
    
    if(is_buy) {
        // Find recent significant low for SL
        sl = low[ArrayMinimum(low, 1, 10)] - Point() * 5;
        
        // TP based on structure or R:R
        double resistance = FindNearestResistance(entry);
        if(resistance > 0) {
            tp = resistance - Point() * 5;
        } else {
            tp = entry + (entry - sl) * 2.0; // 1:2 RR minimum
        }
    } else {
        // Find recent significant high for SL
        sl = high[ArrayMaximum(high, 1, 10)] + Point() * 5;
        
        // TP based on structure or R:R
        double support = FindNearestSupport(entry);
        if(support > 0) {
            tp = support + Point() * 5;
        } else {
            tp = entry - (sl - entry) * 2.0; // 1:2 RR minimum
        }
    }
    
    // Ensure minimum RR ratio
    double riskDistance = MathAbs(entry - sl);
    double rewardDistance = MathAbs(tp - entry);
    
    if(rewardDistance < riskDistance * 1.5) {
        if(is_buy) {
            tp = entry + riskDistance * 2.0;
        } else {
            tp = entry - riskDistance * 2.0;
        }
    }
}

//+------------------------------------------------------------------+
//| Find nearest resistance level                                    |
//+------------------------------------------------------------------+
double FindNearestResistance(double price) {
    double resistance = 0;
    double minDistance = 999999;
    
    for(int i = 0; i < ArraySize(g_liquidityLevels); i++) {
        if(g_liquidityLevels[i].price > price && g_liquidityLevels[i].is_high) {
            double distance = g_liquidityLevels[i].price - price;
            if(distance < minDistance) {
                minDistance = distance;
                resistance = g_liquidityLevels[i].price;
            }
        }
    }
    
    return resistance;
}

//+------------------------------------------------------------------+
//| Find nearest support level                                       |
//+------------------------------------------------------------------+
double FindNearestSupport(double price) {
    double support = 0;
    double minDistance = 999999;
    
    for(int i = 0; i < ArraySize(g_liquidityLevels); i++) {
        if(g_liquidityLevels[i].price < price && !g_liquidityLevels[i].is_high) {
            double distance = price - g_liquidityLevels[i].price;
            if(distance < minDistance) {
                minDistance = distance;
                support = g_liquidityLevels[i].price;
            }
        }
    }
    
    return support;
}

//+------------------------------------------------------------------+
//| Check scalping opportunities                                     |
//+------------------------------------------------------------------+
void CheckScalpingOpportunities() {
    // Scalping logic for M1-M15 timeframes
    // Looking for quick OB reactions with tight risk
    
    if(g_currentMode == MODE_ULTRA_MICRO) return; // Only sniper entries in ultra-micro
    
    // Check for fresh order blocks on M15
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].is_valid || g_orderBlocks[i].timeframe != PERIOD_M15) continue;
        
        double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        bool nearOB = false;
        
        if(g_orderBlocks[i].is_bullish && 
           currentPrice >= g_orderBlocks[i].low * 0.9999 && 
           currentPrice <= g_orderBlocks[i].high * 1.0001) {
            nearOB = true;
        } else if(!g_orderBlocks[i].is_bullish && 
                  currentPrice <= g_orderBlocks[i].high * 1.0001 && 
                  currentPrice >= g_orderBlocks[i].low * 0.9999) {
            nearOB = true;
        }
        
        if(nearOB && CheckVolumeConfirmation()) {
            // Execute scalp trade with tight SL
            ExecuteScalpTrade(g_orderBlocks[i].is_bullish, currentPrice);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Execute scalp trade                                              |
//+------------------------------------------------------------------+
void ExecuteScalpTrade(bool is_buy, double price) {
    double atr = CalculateATR(PERIOD_M15, 14);
    double lotSize = CalculateLotSize(atr) * 0.5; // Smaller size for scalping
    
    if(lotSize < MinLotSize) return;
    
    double sl, tp;
    if(is_buy) {
        sl = price - atr * 0.8;
        tp = price + atr * 1.6; // 1:2 RR
        price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    } else {
        sl = price + atr * 0.8;
        tp = price - atr * 1.6; // 1:2 RR
        price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }
    
    string comment = StringFormat("Scalp_%s", is_buy ? "BUY" : "SELL");
    
    bool result;
    if(is_buy) {
        result = trade.Buy(lotSize, Symbol(), price, sl, tp, comment);
    } else {
        result = trade.Sell(lotSize, Symbol(), price, sl, tp, comment);
    }
    
    if(result) {
        g_dailyTradeCount++;
        Print(StringFormat("Scalp trade executed: %s %.2f lots", is_buy ? "BUY" : "SELL", lotSize));
    }
}

//+------------------------------------------------------------------+
//| Check swing opportunities                                        |
//+------------------------------------------------------------------+
void CheckSwingOpportunities() {
    // Swing trading logic for H1-H4 timeframes
    // Looking for MSS + OB zone + FVG confluence
    
    if(g_currentMode == MODE_ULTRA_MICRO) return;
    
    // Check H1 and H4 order blocks for swing setups
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].is_valid) continue;
        if(g_orderBlocks[i].timeframe != PERIOD_H1 && g_orderBlocks[i].timeframe != PERIOD_H4) continue;
        
        if(CheckSwingConfluence(g_orderBlocks[i])) {
            double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
            ExecuteSwingTrade(g_orderBlocks[i].is_bullish, currentPrice);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Check swing confluence                                           |
//+------------------------------------------------------------------+
bool CheckSwingConfluence(const OrderBlock &ob) {
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Check if price is in OB zone
    bool inZone = (currentPrice >= ob.low && currentPrice <= ob.high);
    if(!inZone) return false;
    
    // Check for HTF bias alignment
    bool htfBias = false;
    if(ob.is_bullish && g_marketStructure == STRUCTURE_BULLISH) htfBias = true;
    if(!ob.is_bullish && g_marketStructure == STRUCTURE_BEARISH) htfBias = true;
    
    return htfBias && CheckVolumeConfirmation();
}

//+------------------------------------------------------------------+
//| Execute swing trade                                              |
//+------------------------------------------------------------------+
void ExecuteSwingTrade(bool is_buy, double price) {
    double atr = CalculateATR(PERIOD_H4, 14);
    double lotSize = CalculateLotSize(atr);
    
    if(lotSize < MinLotSize) return;
    
    double sl, tp;
    CalculateStructuralSLTP(is_buy, price, atr, sl, tp);
    
    if(is_buy) {
        price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    } else {
        price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }
    
    string comment = StringFormat("Swing_%s", is_buy ? "BUY" : "SELL");
    
    bool result;
    if(is_buy) {
        result = trade.Buy(lotSize, Symbol(), price, sl, tp, comment);
    } else {
        result = trade.Sell(lotSize, Symbol(), price, sl, tp, comment);
    }
    
    if(result) {
        g_dailyTradeCount++;
        Print(StringFormat("Swing trade executed: %s %.2f lots", is_buy ? "BUY" : "SELL", lotSize));
    }
}

//+------------------------------------------------------------------+
//| Check position opportunities                                     |
//+------------------------------------------------------------------+
void CheckPositionOpportunities() {
    // Position trading logic for D1-W1 timeframes
    // Looking for major HTF OB + Volume Void + Strong Bias
    
    if(g_currentMode != MODE_TURBO) return; // Only in turbo mode
    
    // Check for major weekly/daily levels
    OrderBlock dailyOB[];
    if(GetDailyOrderBlocks(dailyOB)) {
        for(int i = 0; i < ArraySize(dailyOB); i++) {
            if(CheckPositionConfluence(dailyOB[i])) {
                double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                ExecutePositionTrade(dailyOB[i].is_bullish, currentPrice);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get daily order blocks                                           |
//+------------------------------------------------------------------+
bool GetDailyOrderBlocks(OrderBlock &blocks[]) {
    ArrayResize(blocks, 5);
    
    double high[], low[], volume[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(volume, true);
    
    if(CopyHigh(Symbol(), PERIOD_D1, 0, 20, high) <= 0) return false;
    if(CopyLow(Symbol(), PERIOD_D1, 0, 20, low) <= 0) return false;
    if(CopyTickVolume(Symbol(), PERIOD_D1, 0, 20, volume) <= 0) return false;
    
    int count = 0;
    for(int i = 2; i < 15 && count < 5; i++) {
        double volumeRatio = volume[i] / ((volume[i+1] + volume[i+2]) / 2.0);
        
        if(volumeRatio > 1.8) { // High volume day
            blocks[count].time = iTime(Symbol(), PERIOD_D1, i);
            blocks[count].high = high[i];
            blocks[count].low = low[i];
            blocks[count].volume = volume[i];
            blocks[count].is_bullish = (high[i] > high[i+1] && low[i] > low[i+1]);
            blocks[count].is_valid = true;
            blocks[count].timeframe = PERIOD_D1;
            count++;
        }
    }
    
    return count > 0;
}

//+------------------------------------------------------------------+
//| Check position confluence                                        |
//+------------------------------------------------------------------+
bool CheckPositionConfluence(const OrderBlock &ob) {
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Must be in OB zone
    if(currentPrice < ob.low || currentPrice > ob.high) return false;
    
    // Must have strong HTF bias
    if(ob.is_bullish && g_marketStructure != STRUCTURE_BULLISH) return false;
    if(!ob.is_bullish && g_marketStructure != STRUCTURE_BEARISH) return false;
    
    // Check for volume confirmation
    return CheckVolumeConfirmation();
}

//+------------------------------------------------------------------+
//| Execute position trade                                           |
//+------------------------------------------------------------------+
void ExecutePositionTrade(bool is_buy, double price) {
    double atr = CalculateATR(PERIOD_D1, 14);
    double lotSize = CalculateLotSize(atr) * 1.5; // Larger size for position trades
    
    if(lotSize < MinLotSize) return;
    
    double sl, tp;
    if(is_buy) {
        sl = price - atr * 2.0;
        tp = price + atr * 6.0; // 1:3 RR for position trades
        price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    } else {
        sl = price + atr * 2.0;
        tp = price - atr * 6.0;
        price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }
    
    string comment = StringFormat("Position_%s", is_buy ? "BUY" : "SELL");
    
    bool result;
    if(is_buy) {
        result = trade.Buy(lotSize, Symbol(), price, sl, tp, comment);
    } else {
        result = trade.Sell(lotSize, Symbol(), price, sl, tp, comment);
    }
    
    if(result) {
        g_dailyTradeCount++;
        Print(StringFormat("Position trade executed: %s %.2f lots", is_buy ? "BUY" : "SELL", lotSize));
    }
}

//+------------------------------------------------------------------+
//| Manage existing trades                                           |
//+------------------------------------------------------------------+
void ManageExistingTrades() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != Symbol()) continue;
        
        // Move to break-even after 1:1 RR
        MoveToBreakEven(position.Ticket());
        
        // Trail stop loss
        TrailStopLoss(position.Ticket());
        
        // Check for additional entries (re-entries)
        CheckReEntry(position.Ticket());
    }
}

//+------------------------------------------------------------------+
//| Move trade to break-even                                         |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket) {
    if(!position.SelectByTicket(ticket)) return;
    
    double openPrice = position.PriceOpen();
    double currentSL = position.StopLoss();
    double currentPrice = position.Type() == POSITION_TYPE_BUY ? 
                         SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                         SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    bool is_buy = position.Type() == POSITION_TYPE_BUY;
    double riskDistance = MathAbs(openPrice - currentSL);
    double currentProfit = is_buy ? currentPrice - openPrice : openPrice - currentPrice;
    
    // Move to BE after 1:1 profit
    if(currentProfit >= riskDistance && 
       ((is_buy && currentSL < openPrice) || (!is_buy && currentSL > openPrice))) {
        
        double newSL = openPrice;
        if(is_buy) newSL += Point() * 5; // Small buffer
        else newSL -= Point() * 5;
        
        trade.PositionModify(ticket, newSL, position.TakeProfit());
        Print("Moved position ", ticket, " to break-even");
    }
}

//+------------------------------------------------------------------+
//| Trail stop loss                                                  |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket) {
    if(!position.SelectByTicket(ticket)) return;
    
    double currentSL = position.StopLoss();
    double currentPrice = position.Type() == POSITION_TYPE_BUY ? 
                         SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                         SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    
    bool is_buy = position.Type() == POSITION_TYPE_BUY;
    double atr = CalculateATR(PERIOD_H1, 14);
    double trailDistance = atr * 1.0;
    
    double newSL = 0;
    if(is_buy) {
        newSL = currentPrice - trailDistance;
        if(newSL > currentSL + Point() * 10) {
            trade.PositionModify(ticket, newSL, position.TakeProfit());
        }
    } else {
        newSL = currentPrice + trailDistance;
        if(newSL < currentSL - Point() * 10) {
            trade.PositionModify(ticket, newSL, position.TakeProfit());
        }
    }
}

//+------------------------------------------------------------------+
//| Check for re-entry opportunities                                 |
//+------------------------------------------------------------------+
void CheckReEntry(ulong ticket) {
    // Only allow re-entries in Turbo mode
    if(g_currentMode != MODE_TURBO) return;
    
    if(!position.SelectByTicket(ticket)) return;
    
    // Check if original setup is still valid
    bool is_buy = position.Type() == POSITION_TYPE_BUY;
    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Look for revalidated order blocks in same direction
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].is_valid) continue;
        if(g_orderBlocks[i].is_bullish != is_buy) continue;
        
        bool nearOB = false;
        if(is_buy && currentPrice >= g_orderBlocks[i].low && currentPrice <= g_orderBlocks[i].high) {
            nearOB = true;
        } else if(!is_buy && currentPrice <= g_orderBlocks[i].high && currentPrice >= g_orderBlocks[i].low) {
            nearOB = true;
        }
        
        if(nearOB && CheckVolumeConfirmation()) {
            // Add to existing position (pyramid)
            double lotSize = position.Volume() * 0.5; // Half the original size
            lotSize = MathMax(lotSize, MinLotSize);
            
            double atr = CalculateATR(PERIOD_H1, 14);
            double sl, tp;
            CalculateStructuralSLTP(is_buy, currentPrice, atr, sl, tp);
            
            string comment = StringFormat("ReEntry_%s", is_buy ? "BUY" : "SELL");
            
            bool result;
            if(is_buy) {
                result = trade.Buy(lotSize, Symbol(), 0, sl, tp, comment);
            } else {
                result = trade.Sell(lotSize, Symbol(), 0, sl, tp, comment);
            }
            
            if(result) {
                Print("Re-entry executed for position ", ticket);
            }
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                    |
//+------------------------------------------------------------------+
double CalculateATR(ENUM_TIMEFRAMES timeframe, int period) {
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol(), timeframe, 0, period + 1, high) <= 0) return 0.01;
    if(CopyLow(Symbol(), timeframe, 0, period + 1, low) <= 0) return 0.01;
    if(CopyClose(Symbol(), timeframe, 0, period + 1, close) <= 0) return 0.01;
    
    double atr = 0;
    for(int i = 1; i < period; i++) {
        double tr = MathMax(high[i] - low[i], 
                   MathMax(MathAbs(high[i] - close[i+1]), 
                          MathAbs(low[i] - close[i+1])));
        atr += tr;
    }
    
    return atr / period;
}

//+------------------------------------------------------------------+
//| Create dashboard                                                 |
//+------------------------------------------------------------------+
void CreateDashboard() {
    // Create background rectangle
    ObjectCreate(0, "Dashboard_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_XDISTANCE, g_dashboardX - 5);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_YDISTANCE, g_dashboardY - 5);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_XSIZE, 300);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_YSIZE, 200);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_BGCOLOR, C'25,25,25');
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_BACK, false);
    
    // Create text labels
    for(int i = 0; i < 10; i++) {
        string objName = "Dashboard_Line" + IntegerToString(i);
        ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, g_dashboardX);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, g_dashboardY + i * 18);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, DashboardColor);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, DashboardFontSize);
        ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    }
}

//+------------------------------------------------------------------+
//| Update dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    if(!ShowDashboard) return;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    string lines[10];
    lines[0] = "=== GOLD SNIPER EA ===";
    lines[1] = StringFormat("Mode: %s", GetModeString());
    lines[2] = StringFormat("Balance: $%.2f", balance);
    lines[3] = StringFormat("Equity: $%.2f", equity);
    lines[4] = StringFormat("Spread: %.1f pts", g_currentSpread);
    lines[5] = StringFormat("Leverage: 1:%.0f", g_accountLeverage);
    lines[6] = StringFormat("Session: %s", GetCurrentSession());
    lines[7] = StringFormat("Daily Trades: %d", g_dailyTradeCount);
    lines[8] = StringFormat("Market: %s", GetStructureString());
    lines[9] = StringFormat("Status: %s", g_tradingEnabled ? "ACTIVE" : "PAUSED");
    
    for(int i = 0; i < 10; i++) {
        string objName = "Dashboard_Line" + IntegerToString(i);
        ObjectSetString(0, objName, OBJPROP_TEXT, lines[i]);
    }
}

//+------------------------------------------------------------------+
//| Get mode string                                                  |
//+------------------------------------------------------------------+
string GetModeString() {
    switch(g_currentMode) {
        case MODE_ULTRA_MICRO: return "ULTRA-MICRO";
        case MODE_SAFE: return "SAFE";
        case MODE_TURBO: return "TURBO";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Get current session                                              |
//+------------------------------------------------------------------+
string GetCurrentSession() {
    datetime currentTime = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    
    int hour = dt.hour;
    
    if(hour >= 23 || hour <= 8) return "ASIA";
    if(hour >= 7 && hour <= 16) return "LONDON";
    if(hour >= 13 && hour <= 22) return "NEW YORK";
    
    return "OFF-HOURS";
}

//+------------------------------------------------------------------+
//| Get structure string                                             |
//+------------------------------------------------------------------+
string GetStructureString() {
    switch(g_marketStructure) {
        case STRUCTURE_BULLISH: return "BULLISH";
        case STRUCTURE_BEARISH: return "BEARISH";
        case STRUCTURE_RANGING: return "RANGING";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Draw order blocks                                                |
//+------------------------------------------------------------------+
void DrawOrderBlocks() {
    // Clear old order block drawings
    ObjectsDeleteAll(0, "OB_");
    
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].is_valid) continue;
        
        string objName = StringFormat("OB_%d", i);
        ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                    g_orderBlocks[i].time, g_orderBlocks[i].high,
                    TimeCurrent() + PeriodSeconds(PERIOD_H1) * 10, g_orderBlocks[i].low);
        
        color blockColor = g_orderBlocks[i].is_bullish ? C'0,100,0' : C'100,0,0';
        ObjectSetInteger(0, objName, OBJPROP_COLOR, blockColor);
        ObjectSetInteger(0, objName, OBJPROP_FILL, true);
        ObjectSetInteger(0, objName, OBJPROP_BACK, true);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    }
}

//+------------------------------------------------------------------+
//| Draw Fair Value Gaps                                            |
//+------------------------------------------------------------------+
void DrawFairValueGaps() {
    // Clear old FVG drawings
    ObjectsDeleteAll(0, "FVG_");
    
    for(int i = 0; i < ArraySize(g_fairValueGaps); i++) {
        if(!g_fairValueGaps[i].is_valid) continue;
        
        string objName = StringFormat("FVG_%d", i);
        ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                    g_fairValueGaps[i].time, g_fairValueGaps[i].high,
                    TimeCurrent() + PeriodSeconds(PERIOD_H1) * 5, g_fairValueGaps[i].low);
        
        color gapColor = g_fairValueGaps[i].is_bullish ? C'0,0,100' : C'100,100,0';
        ObjectSetInteger(0, objName, OBJPROP_COLOR, gapColor);
        ObjectSetInteger(0, objName, OBJPROP_FILL, true);
        ObjectSetInteger(0, objName, OBJPROP_BACK, true);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    }
}

//+------------------------------------------------------------------+
//| Handle chart events                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    // Handle chart events if needed
    if(id == CHARTEVENT_CHART_CHANGE) {
        // Redraw objects if needed
        if(ShowOrderBlocks) DrawOrderBlocks();
        if(ShowFVG) DrawFairValueGaps();
    }
}

//+------------------------------------------------------------------+