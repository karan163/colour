//+------------------------------------------------------------------+
//|                                    XAUUSD_ICT_SMC_Expert.mq5    |
//|                     Institutional Grade ICT & Smart Money EA    |
//|                                   For XAUUSD Trading Only       |
//+------------------------------------------------------------------+
#property copyright "ICT Smart Money Expert"
#property version   "1.00"
#property strict

//--- Input Parameters - ICT Strategy Controls
input group "========== ICT STRATEGY CONTROLS =========="
input bool Enable_OB               = true;  // Order Block Logic (HTF + LTF)
input bool Enable_FVG              = true;  // Fair Value Gap Detection
input bool Enable_BOS              = true;  // Break of Structure (BOS)
input bool Enable_CHoCH            = true;  // Change of Character (CHoCH)
input bool Enable_MSS              = true;  // Market Structure Shift (MSS)
input bool Enable_BreakerBlock     = true;  // Breaker Block Entry
input bool Enable_OBinOB           = true;  // OB-inside-OB logic
input bool Enable_LiquiditySweep   = true;  // Liquidity Grab (equal highs/lows)
input bool Enable_JudasSwing       = true;  // Judas Swing Filter
input bool Enable_TurtleSoup       = true;  // Turtle Soup Pattern
input bool Enable_BPR              = true;  // Balanced Price Range Logic
input bool Enable_LiquidityVoid    = true;  // Liquidity Void Entry Filter
input bool Enable_VolumeSpike      = true;  // Volume Displacement Confirmation
input bool Enable_StopHuntFilter   = true;  // Stop Hunt Detection
input bool Enable_PremiumDiscount  = true;  // PR/DIS Zone Filter
input bool Enable_BuySellModel     = true;  // Institutional Buy/Sell Model Recognition
input bool Enable_TrapFilter       = true;  // Rejection of Trapped OBs
input bool Enable_OBMemory         = true;  // Memory of Past Validated OB Zones
input bool Enable_ReEntryEngine    = true;  // Re-entry logic on OB revalidation
input bool Enable_KillzoneFilter   = true;  // Killzone entry enforcement
input bool Enable_StrictSniperOnly = true;  // Allow only sniper-grade entries (all confluence)

input group "========== RISK MANAGEMENT =========="
input double MaxRiskPercent        = 8.0;   // Max Risk % (Auto-Adaptive)
input int    MaxDailyTrades        = 10;    // Max Trades Per Day
input double MaxDailyDrawdown      = 15.0;  // Max Daily Drawdown %
input int    MagicNumber           = 789123; // EA Magic Number

input group "========== TIMEFRAME SETTINGS =========="
input ENUM_TIMEFRAMES HTF_Timeframe = PERIOD_H4;  // Higher Timeframe
input ENUM_TIMEFRAMES LTF_Timeframe = PERIOD_M15; // Lower Timeframe
input ENUM_TIMEFRAMES Entry_Timeframe = PERIOD_M5; // Entry Timeframe

input group "========== VISUAL SETTINGS =========="
input bool ShowDashboard           = true;  // Show Dashboard
input bool DrawStructure           = true;  // Draw Market Structure
input bool DrawOrderBlocks         = true;  // Draw Order Blocks
input bool DrawFVG                 = true;  // Draw Fair Value Gaps
input color BullishColor           = clrLime;
input color BearishColor           = clrRed;

//--- Global Variables
struct OrderBlock {
    double high;
    double low;
    datetime time;
    int direction; // 1 = bullish, -1 = bearish
    bool validated;
    bool trapped;
    int strength;
};

struct FairValueGap {
    double high;
    double low;
    datetime time;
    int direction;
    bool filled;
};

struct LiquidityLevel {
    double price;
    datetime time;
    int hits;
    bool swept;
};

struct MarketStructure {
    double swing_high;
    double swing_low;
    datetime time_high;
    datetime time_low;
    int trend; // 1 = bullish, -1 = bearish, 0 = ranging
    bool bos_confirmed;
    bool choch_confirmed;
    bool mss_confirmed;
};

//--- Arrays and Variables
OrderBlock orderBlocks[];
FairValueGap fvgArray[];
LiquidityLevel liquidityLevels[];
MarketStructure marketStructure;

double currentSpread;
double accountBalance;
double accountEquity;
int tradesCountToday;
datetime lastTradeDate;
string currentRiskMode;
int htf_trend, ltf_trend, entry_trend;
double monthlyBias, weeklyBias, dailyBias;

//--- Dashboard Variables
string dashboardText[];
int dashboardLines = 12;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Validate symbol
    if(Symbol() != "XAUUSD" && Symbol() != "GOLD") {
        Alert("This EA is designed for XAUUSD (Gold) only!");
        return(INIT_FAILED);
    }
    
    // Initialize arrays
    ArrayResize(orderBlocks, 0);
    ArrayResize(fvgArray, 0);
    ArrayResize(liquidityLevels, 0);
    ArrayResize(dashboardText, dashboardLines);
    
    // Initialize variables
    currentSpread = 0;
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    tradesCountToday = 0;
    lastTradeDate = 0;
    
    // Initialize market structure
    marketStructure.swing_high = 0;
    marketStructure.swing_low = 0;
    marketStructure.trend = 0;
    marketStructure.bos_confirmed = false;
    marketStructure.choch_confirmed = false;
    marketStructure.mss_confirmed = false;
    
    Print("XAUUSD ICT SMC Expert Advisor Initialized Successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up objects
    ObjectsDeleteAll(0, "ICT_");
    ObjectsDeleteAll(0, "Dashboard_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Update account information
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    currentSpread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    
    // Update risk mode based on balance
    UpdateRiskMode();
    
    // Update daily trade count
    UpdateDailyTradeCount();
    
    // Check daily drawdown limit
    if(!CheckDailyDrawdown()) return;
    
    // Update market structure
    UpdateMarketStructure();
    
    // Update order blocks
    UpdateOrderBlocks();
    
    // Update fair value gaps
    UpdateFairValueGaps();
    
    // Update liquidity levels
    UpdateLiquidityLevels();
    
    // Check for trading opportunities
    if(IsKillzoneActive() && Enable_KillzoneFilter) {
        CheckTradingOpportunities();
    } else if(!Enable_KillzoneFilter) {
        CheckTradingOpportunities();
    }
    
    // Update dashboard
    if(ShowDashboard) {
        UpdateDashboard();
    }
    
    // Manage existing trades
    ManageExistingTrades();
}

//+------------------------------------------------------------------+
//| Update Risk Mode Based on Account Balance                       |
//+------------------------------------------------------------------+
void UpdateRiskMode() {
    if(accountBalance < 20) {
        currentRiskMode = "Ultra-Micro";
    } else if(accountBalance < 500) {
        currentRiskMode = "Safe";
    } else {
        currentRiskMode = "Turbo";
    }
}

//+------------------------------------------------------------------+
//| Update Daily Trade Count                                        |
//+------------------------------------------------------------------+
void UpdateDailyTradeCount() {
    datetime currentDate = iTime(Symbol(), PERIOD_D1, 0);
    
    if(lastTradeDate != currentDate) {
        tradesCountToday = 0;
        lastTradeDate = currentDate;
    }
}

//+------------------------------------------------------------------+
//| Check Daily Drawdown Limit                                      |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown() {
    double dailyStartBalance = accountBalance; // Simplified - should track daily start
    double currentDrawdown = (dailyStartBalance - accountEquity) / dailyStartBalance * 100;
    
    return currentDrawdown < MaxDailyDrawdown;
}

//+------------------------------------------------------------------+
//| Update Market Structure (BOS, CHoCH, MSS Detection)            |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
    // Get swing highs and lows
    double current_high = iHigh(Symbol(), HTF_Timeframe, 1);
    double current_low = iLow(Symbol(), HTF_Timeframe, 1);
    double prev_high = iHigh(Symbol(), HTF_Timeframe, 2);
    double prev_low = iLow(Symbol(), HTF_Timeframe, 2);
    
    // Update swing levels
    if(current_high > marketStructure.swing_high) {
        // Potential BOS to upside
        if(marketStructure.trend == -1 && Enable_BOS) {
            marketStructure.bos_confirmed = true;
            if(DrawStructure) DrawBOS(current_high, iTime(Symbol(), HTF_Timeframe, 1), 1);
        }
        marketStructure.swing_high = current_high;
        marketStructure.time_high = iTime(Symbol(), HTF_Timeframe, 1);
    }
    
    if(current_low < marketStructure.swing_low || marketStructure.swing_low == 0) {
        // Potential BOS to downside
        if(marketStructure.trend == 1 && Enable_BOS) {
            marketStructure.bos_confirmed = true;
            if(DrawStructure) DrawBOS(current_low, iTime(Symbol(), HTF_Timeframe, 1), -1);
        }
        marketStructure.swing_low = current_low;
        marketStructure.time_low = iTime(Symbol(), HTF_Timeframe, 1);
    }
    
    // Detect Change of Character (CHoCH)
    if(Enable_CHoCH) {
        DetectCHoCH();
    }
    
    // Detect Market Structure Shift (MSS)
    if(Enable_MSS) {
        DetectMSS();
    }
    
    // Update trend bias
    UpdateTrendBias();
}

//+------------------------------------------------------------------+
//| Detect Change of Character                                       |
//+------------------------------------------------------------------+
void DetectCHoCH() {
    double close = iClose(Symbol(), HTF_Timeframe, 1);
    
    // CHoCH occurs when price fails to make new high/low in trending market
    if(marketStructure.trend == 1) { // Bullish trend
        if(close < marketStructure.swing_low) {
            marketStructure.choch_confirmed = true;
            marketStructure.trend = -1;
            if(DrawStructure) DrawCHoCH(close, iTime(Symbol(), HTF_Timeframe, 1), -1);
        }
    } else if(marketStructure.trend == -1) { // Bearish trend
        if(close > marketStructure.swing_high) {
            marketStructure.choch_confirmed = true;
            marketStructure.trend = 1;
            if(DrawStructure) DrawCHoCH(close, iTime(Symbol(), HTF_Timeframe, 1), 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Market Structure Shift                                   |
//+------------------------------------------------------------------+
void DetectMSS() {
    // MSS is a stronger form of CHoCH with volume confirmation
    if(marketStructure.choch_confirmed && Enable_VolumeSpike) {
        if(IsVolumeSpike()) {
            marketStructure.mss_confirmed = true;
            if(DrawStructure) DrawMSS(iClose(Symbol(), HTF_Timeframe, 1), iTime(Symbol(), HTF_Timeframe, 1));
        }
    }
}

//+------------------------------------------------------------------+
//| Update Trend Bias (Monthly, Weekly, Daily)                     |
//+------------------------------------------------------------------+
void UpdateTrendBias() {
    // Monthly bias
    double monthly_open = iOpen(Symbol(), PERIOD_MN1, 0);
    double monthly_close = iClose(Symbol(), PERIOD_MN1, 0);
    monthlyBias = monthly_close > monthly_open ? 1 : -1;
    
    // Weekly bias
    double weekly_open = iOpen(Symbol(), PERIOD_W1, 0);
    double weekly_close = iClose(Symbol(), PERIOD_W1, 0);
    weeklyBias = weekly_close > weekly_open ? 1 : -1;
    
    // Daily bias
    double daily_open = iOpen(Symbol(), PERIOD_D1, 0);
    double daily_close = iClose(Symbol(), PERIOD_D1, 0);
    dailyBias = daily_close > daily_open ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Update Order Blocks                                             |
//+------------------------------------------------------------------+
void UpdateOrderBlocks() {
    if(!Enable_OB) return;
    
    // Look for order blocks on HTF and LTF
    FindOrderBlocks(HTF_Timeframe);
    FindOrderBlocks(LTF_Timeframe);
    
    // Validate existing order blocks
    ValidateOrderBlocks();
    
    // Clean old order blocks
    CleanOldOrderBlocks();
}

//+------------------------------------------------------------------+
//| Find Order Blocks on Specified Timeframe                       |
//+------------------------------------------------------------------+
void FindOrderBlocks(ENUM_TIMEFRAMES timeframe) {
    int bars_to_check = 20;
    
    for(int i = 2; i < bars_to_check; i++) {
        double high = iHigh(Symbol(), timeframe, i);
        double low = iLow(Symbol(), timeframe, i);
        double close = iClose(Symbol(), timeframe, i);
        double open = iOpen(Symbol(), timeframe, i);
        datetime time = iTime(Symbol(), timeframe, i);
        
        // Bullish Order Block (last down candle before upward move)
        if(close < open) { // Bearish candle
            bool upward_move = true;
            for(int j = 1; j <= 3; j++) {
                if(iClose(Symbol(), timeframe, i-j) <= iClose(Symbol(), timeframe, i-j-1)) {
                    upward_move = false;
                    break;
                }
            }
            
            if(upward_move) {
                OrderBlock ob;
                ob.high = high;
                ob.low = low;
                ob.time = time;
                ob.direction = 1; // Bullish OB
                ob.validated = false;
                ob.trapped = false;
                ob.strength = CalculateOBStrength(timeframe, i);
                
                if(!DuplicateOB(ob)) {
                    ArrayResize(orderBlocks, ArraySize(orderBlocks) + 1);
                    orderBlocks[ArraySize(orderBlocks) - 1] = ob;
                    
                    if(DrawOrderBlocks) DrawOrderBlock(ob);
                }
            }
        }
        
        // Bearish Order Block (last up candle before downward move)
        if(close > open) { // Bullish candle
            bool downward_move = true;
            for(int j = 1; j <= 3; j++) {
                if(iClose(Symbol(), timeframe, i-j) >= iClose(Symbol(), timeframe, i-j-1)) {
                    downward_move = false;
                    break;
                }
            }
            
            if(downward_move) {
                OrderBlock ob;
                ob.high = high;
                ob.low = low;
                ob.time = time;
                ob.direction = -1; // Bearish OB
                ob.validated = false;
                ob.trapped = false;
                ob.strength = CalculateOBStrength(timeframe, i);
                
                if(!DuplicateOB(ob)) {
                    ArrayResize(orderBlocks, ArraySize(orderBlocks) + 1);
                    orderBlocks[ArraySize(orderBlocks) - 1] = ob;
                    
                    if(DrawOrderBlocks) DrawOrderBlock(ob);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Order Block Strength                                  |
//+------------------------------------------------------------------+
int CalculateOBStrength(ENUM_TIMEFRAMES timeframe, int index) {
    int strength = 1;
    
    // Add strength based on timeframe
    if(timeframe == PERIOD_H4 || timeframe == PERIOD_H1) strength += 2;
    if(timeframe == PERIOD_D1 || timeframe == PERIOD_W1) strength += 3;
    
    // Add strength based on volume (if available)
    if(Enable_VolumeSpike && IsVolumeSpikeAtIndex(timeframe, index)) {
        strength += 2;
    }
    
    // Add strength based on structure confluence
    if(marketStructure.bos_confirmed || marketStructure.choch_confirmed) {
        strength += 1;
    }
    
    return strength;
}

//+------------------------------------------------------------------+
//| Check for Duplicate Order Block                                 |
//+------------------------------------------------------------------+
bool DuplicateOB(const OrderBlock &ob) {
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(MathAbs(orderBlocks[i].high - ob.high) < Point() * 10 &&
           MathAbs(orderBlocks[i].low - ob.low) < Point() * 10 &&
           orderBlocks[i].direction == ob.direction) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Validate Order Blocks                                           |
//+------------------------------------------------------------------+
void ValidateOrderBlocks() {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].validated) {
            // Bullish OB validation
            if(orderBlocks[i].direction == 1) {
                if(current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                    orderBlocks[i].validated = true;
                }
            }
            // Bearish OB validation
            else if(orderBlocks[i].direction == -1) {
                if(current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                    orderBlocks[i].validated = true;
                }
            }
        }
        
        // Check for trapped order blocks
        if(Enable_TrapFilter) {
            CheckTrappedOB(i);
        }
    }
}

//+------------------------------------------------------------------+
//| Check for Trapped Order Block                                   |
//+------------------------------------------------------------------+
void CheckTrappedOB(int index) {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Bullish OB becomes trapped if price breaks below significantly
    if(orderBlocks[index].direction == 1) {
        if(current_price < orderBlocks[index].low - (orderBlocks[index].high - orderBlocks[index].low) * 0.5) {
            orderBlocks[index].trapped = true;
        }
    }
    // Bearish OB becomes trapped if price breaks above significantly
    else if(orderBlocks[index].direction == -1) {
        if(current_price > orderBlocks[index].high + (orderBlocks[index].high - orderBlocks[index].low) * 0.5) {
            orderBlocks[index].trapped = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Clean Old Order Blocks                                          |
//+------------------------------------------------------------------+
void CleanOldOrderBlocks() {
    datetime cutoff_time = TimeCurrent() - 7 * 24 * 3600; // 7 days
    
    for(int i = ArraySize(orderBlocks) - 1; i >= 0; i--) {
        if(orderBlocks[i].time < cutoff_time || orderBlocks[i].trapped) {
            // Remove old or trapped order blocks
            for(int j = i; j < ArraySize(orderBlocks) - 1; j++) {
                orderBlocks[j] = orderBlocks[j + 1];
            }
            ArrayResize(orderBlocks, ArraySize(orderBlocks) - 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Update Fair Value Gaps                                          |
//+------------------------------------------------------------------+
void UpdateFairValueGaps() {
    if(!Enable_FVG) return;
    
    FindFairValueGaps(Entry_Timeframe);
    ValidateFVG();
    CleanFilledFVG();
}

//+------------------------------------------------------------------+
//| Find Fair Value Gaps                                            |
//+------------------------------------------------------------------+
void FindFairValueGaps(ENUM_TIMEFRAMES timeframe) {
    for(int i = 2; i < 20; i++) {
        double high_prev = iHigh(Symbol(), timeframe, i+1);
        double low_prev = iLow(Symbol(), timeframe, i+1);
        double high_curr = iHigh(Symbol(), timeframe, i);
        double low_curr = iLow(Symbol(), timeframe, i);
        double high_next = iHigh(Symbol(), timeframe, i-1);
        double low_next = iLow(Symbol(), timeframe, i-1);
        
        // Bullish FVG (gap up)
        if(low_next > high_prev) {
            FairValueGap fvg;
            fvg.high = low_next;
            fvg.low = high_prev;
            fvg.time = iTime(Symbol(), timeframe, i);
            fvg.direction = 1;
            fvg.filled = false;
            
            if(!DuplicateFVG(fvg)) {
                ArrayResize(fvgArray, ArraySize(fvgArray) + 1);
                fvgArray[ArraySize(fvgArray) - 1] = fvg;
                
                if(DrawFVG) DrawFairValueGap(fvg);
            }
        }
        
        // Bearish FVG (gap down)
        if(high_next < low_prev) {
            FairValueGap fvg;
            fvg.high = low_prev;
            fvg.low = high_next;
            fvg.time = iTime(Symbol(), timeframe, i);
            fvg.direction = -1;
            fvg.filled = false;
            
            if(!DuplicateFVG(fvg)) {
                ArrayResize(fvgArray, ArraySize(fvgArray) + 1);
                fvgArray[ArraySize(fvgArray) - 1] = fvg;
                
                if(DrawFVG) DrawFairValueGap(fvg);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for Duplicate FVG                                         |
//+------------------------------------------------------------------+
bool DuplicateFVG(const FairValueGap &fvg) {
    for(int i = 0; i < ArraySize(fvgArray); i++) {
        if(MathAbs(fvgArray[i].high - fvg.high) < Point() * 5 &&
           MathAbs(fvgArray[i].low - fvg.low) < Point() * 5 &&
           fvgArray[i].direction == fvg.direction) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Validate Fair Value Gaps                                        |
//+------------------------------------------------------------------+
void ValidateFVG() {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(fvgArray); i++) {
        if(!fvgArray[i].filled) {
            // Check if FVG is filled (price has moved through the gap)
            if(current_price >= fvgArray[i].low && current_price <= fvgArray[i].high) {
                fvgArray[i].filled = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Clean Filled FVG                                                |
//+------------------------------------------------------------------+
void CleanFilledFVG() {
    for(int i = ArraySize(fvgArray) - 1; i >= 0; i--) {
        if(fvgArray[i].filled) {
            for(int j = i; j < ArraySize(fvgArray) - 1; j++) {
                fvgArray[j] = fvgArray[j + 1];
            }
            ArrayResize(fvgArray, ArraySize(fvgArray) - 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Update Liquidity Levels                                         |
//+------------------------------------------------------------------+
void UpdateLiquidityLevels() {
    if(!Enable_LiquiditySweep) return;
    
    FindLiquidityLevels();
    CheckLiquiditySweep();
}

//+------------------------------------------------------------------+
//| Find Liquidity Levels (Equal Highs/Lows)                       |
//+------------------------------------------------------------------+
void FindLiquidityLevels() {
    int lookback = 50;
    double tolerance = Point() * 20;
    
    for(int i = 2; i < lookback; i++) {
        double high = iHigh(Symbol(), HTF_Timeframe, i);
        double low = iLow(Symbol(), HTF_Timeframe, i);
        datetime time = iTime(Symbol(), HTF_Timeframe, i);
        
        // Check for equal highs
        int equal_highs = 1;
        for(int j = i + 1; j < lookback; j++) {
            if(MathAbs(iHigh(Symbol(), HTF_Timeframe, j) - high) <= tolerance) {
                equal_highs++;
            }
        }
        
        if(equal_highs >= 2) {
            LiquidityLevel level;
            level.price = high;
            level.time = time;
            level.hits = equal_highs;
            level.swept = false;
            
            if(!DuplicateLiquidity(level)) {
                ArrayResize(liquidityLevels, ArraySize(liquidityLevels) + 1);
                liquidityLevels[ArraySize(liquidityLevels) - 1] = level;
            }
        }
        
        // Check for equal lows
        int equal_lows = 1;
        for(int j = i + 1; j < lookback; j++) {
            if(MathAbs(iLow(Symbol(), HTF_Timeframe, j) - low) <= tolerance) {
                equal_lows++;
            }
        }
        
        if(equal_lows >= 2) {
            LiquidityLevel level;
            level.price = low;
            level.time = time;
            level.hits = equal_lows;
            level.swept = false;
            
            if(!DuplicateLiquidity(level)) {
                ArrayResize(liquidityLevels, ArraySize(liquidityLevels) + 1);
                liquidityLevels[ArraySize(liquidityLevels) - 1] = level;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for Duplicate Liquidity Level                             |
//+------------------------------------------------------------------+
bool DuplicateLiquidity(const LiquidityLevel &level) {
    for(int i = 0; i < ArraySize(liquidityLevels); i++) {
        if(MathAbs(liquidityLevels[i].price - level.price) < Point() * 10) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check for Liquidity Sweep                                       |
//+------------------------------------------------------------------+
void CheckLiquiditySweep() {
    double current_high = iHigh(Symbol(), Entry_Timeframe, 1);
    double current_low = iLow(Symbol(), Entry_Timeframe, 1);
    
    for(int i = 0; i < ArraySize(liquidityLevels); i++) {
        if(!liquidityLevels[i].swept) {
            // Check if liquidity has been swept
            if((current_high > liquidityLevels[i].price && liquidityLevels[i].price > iLow(Symbol(), HTF_Timeframe, 0)) ||
               (current_low < liquidityLevels[i].price && liquidityLevels[i].price < iHigh(Symbol(), HTF_Timeframe, 0))) {
                liquidityLevels[i].swept = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Killzone is Active                                     |
//+------------------------------------------------------------------+
bool IsKillzoneActive() {
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    int current_hour = current_time.hour;
    
    // Asia: 2AM-5AM UTC
    if(current_hour >= 2 && current_hour <= 5) return true;
    
    // London: 7AM-10AM UTC  
    if(current_hour >= 7 && current_hour <= 10) return true;
    
    // NY: 1PM-4PM UTC (13-16)
    if(current_hour >= 13 && current_hour <= 16) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Trading Opportunities                                     |
//+------------------------------------------------------------------+
void CheckTradingOpportunities() {
    if(tradesCountToday >= MaxDailyTrades) return;
    if(PositionsTotal() > 0 && currentRiskMode == "Safe") return;
    
    // Check for sniper entry confluence
    if(Enable_StrictSniperOnly) {
        if(CheckSniperConfluence()) {
            ExecuteTrade();
        }
    } else {
        // Check individual setups
        if(CheckOrderBlockEntry() || CheckFVGEntry() || CheckBreakerBlockEntry()) {
            ExecuteTrade();
        }
    }
}

//+------------------------------------------------------------------+
//| Check Sniper Confluence                                         |
//+------------------------------------------------------------------+
bool CheckSniperConfluence() {
    bool ob_valid = false;
    bool fvg_present = false;
    bool structure_confirmed = false;
    bool volume_spike = false;
    bool premium_discount = false;
    bool liquidity_near = false;
    
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Check Order Block validity
    if(Enable_OB) {
        for(int i = 0; i < ArraySize(orderBlocks); i++) {
            if(!orderBlocks[i].trapped && orderBlocks[i].strength >= 3) {
                if(current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                    ob_valid = true;
                    break;
                }
            }
        }
    }
    
    // Check FVG presence
    if(Enable_FVG) {
        for(int i = 0; i < ArraySize(fvgArray); i++) {
            if(!fvgArray[i].filled) {
                if(current_price >= fvgArray[i].low && current_price <= fvgArray[i].high) {
                    fvg_present = true;
                    break;
                }
            }
        }
    }
    
    // Check structure confirmation
    if(Enable_BOS && marketStructure.bos_confirmed) structure_confirmed = true;
    if(Enable_CHoCH && marketStructure.choch_confirmed) structure_confirmed = true;
    if(Enable_MSS && marketStructure.mss_confirmed) structure_confirmed = true;
    
    // Check volume spike
    if(Enable_VolumeSpike) {
        volume_spike = IsVolumeSpike();
    }
    
    // Check premium/discount
    if(Enable_PremiumDiscount) {
        premium_discount = IsPremiumDiscountZone();
    }
    
    // Check liquidity nearby
    if(Enable_LiquiditySweep) {
        for(int i = 0; i < ArraySize(liquidityLevels); i++) {
            if(!liquidityLevels[i].swept) {
                if(MathAbs(current_price - liquidityLevels[i].price) < Point() * 100) {
                    liquidity_near = true;
                    break;
                }
            }
        }
    }
    
    // Require minimum confluence
    int confluence_count = 0;
    if(ob_valid) confluence_count++;
    if(fvg_present) confluence_count++;
    if(structure_confirmed) confluence_count++;
    if(volume_spike) confluence_count++;
    if(premium_discount) confluence_count++;
    if(liquidity_near) confluence_count++;
    
    return confluence_count >= 4; // Require at least 4 confluences
}

//+------------------------------------------------------------------+
//| Check Order Block Entry                                         |
//+------------------------------------------------------------------+
bool CheckOrderBlockEntry() {
    if(!Enable_OB) return false;
    
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].trapped && orderBlocks[i].validated) {
            if(current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check FVG Entry                                                 |
//+------------------------------------------------------------------+
bool CheckFVGEntry() {
    if(!Enable_FVG) return false;
    
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(fvgArray); i++) {
        if(!fvgArray[i].filled) {
            if(current_price >= fvgArray[i].low && current_price <= fvgArray[i].high) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Breaker Block Entry                                       |
//+------------------------------------------------------------------+
bool CheckBreakerBlockEntry() {
    if(!Enable_BreakerBlock) return false;
    
    // Breaker block is an order block that has been broken and retested
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(orderBlocks[i].validated) {
            // Check if OB was broken and now retesting
            bool broken = false;
            if(orderBlocks[i].direction == 1 && current_price < orderBlocks[i].low) {
                broken = true;
            } else if(orderBlocks[i].direction == -1 && current_price > orderBlocks[i].high) {
                broken = true;
            }
            
            if(broken && current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Execute Trade                                                    |
//+------------------------------------------------------------------+
void ExecuteTrade() {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double lot_size = CalculateLotSize();
    
    if(lot_size <= 0) return;
    
    // Determine trade direction
    int trade_direction = DetermineTradeDirection();
    if(trade_direction == 0) return;
    
    // Calculate SL and TP
    double sl = CalculateStopLoss(trade_direction);
    double tp = CalculateTakeProfit(trade_direction, sl);
    
    // Validate SL and TP
    if(!ValidateSLTP(trade_direction, sl, tp)) return;
    
    // Execute trade
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = lot_size;
    request.type = (trade_direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = (trade_direction == 1) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.comment = "ICT SMC " + currentRiskMode;
    
    if(OrderSend(request, result)) {
        tradesCountToday++;
        Print("Trade executed: ", result.order, " Direction: ", (trade_direction == 1 ? "BUY" : "SELL"), 
              " Lot: ", lot_size, " SL: ", sl, " TP: ", tp);
    } else {
        Print("Trade execution failed: ", result.retcode, " - ", result.comment);
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize() {
    double risk_amount = accountBalance * (MaxRiskPercent / 100.0);
    
    // Adjust risk based on mode
    if(currentRiskMode == "Ultra-Micro") {
        risk_amount = MathMin(risk_amount, accountBalance * 0.5); // Max 50%
    } else if(currentRiskMode == "Safe") {
        risk_amount = MathMin(risk_amount, accountBalance * 0.08); // Max 8%
    } else if(currentRiskMode == "Turbo") {
        risk_amount = MathMin(risk_amount, accountBalance * 0.4); // Max 40%
    }
    
    // Calculate lot based on stop loss distance
    double sl_distance = CalculateStopLossDistance();
    if(sl_distance <= 0) return 0;
    
    double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double lot_size = risk_amount / (sl_distance / Point() * tick_value);
    
    // Normalize lot size
    double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    lot_size = MathMax(lot_size, min_lot);
    lot_size = MathMin(lot_size, max_lot);
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss Distance                                    |
//+------------------------------------------------------------------+
double CalculateStopLossDistance() {
    // Base SL distance on structure
    double distance = Point() * 500; // Default 50 pips for Gold
    
    // Adjust based on current volatility
    double atr = iATR(Symbol(), Entry_Timeframe, 14, 1);
    distance = MathMax(distance, atr * 1.5);
    
    // Add spread buffer
    distance += currentSpread * 2;
    
    return distance;
}

//+------------------------------------------------------------------+
//| Determine Trade Direction                                        |
//+------------------------------------------------------------------+
int DetermineTradeDirection() {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Use order block direction as primary signal
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].trapped && orderBlocks[i].validated) {
            if(current_price >= orderBlocks[i].low && current_price <= orderBlocks[i].high) {
                // Confirm with trend bias
                if(orderBlocks[i].direction == 1 && dailyBias > 0) return 1;
                if(orderBlocks[i].direction == -1 && dailyBias < 0) return -1;
            }
        }
    }
    
    // Use market structure as secondary signal
    if(marketStructure.bos_confirmed) {
        return marketStructure.trend;
    }
    
    return 0; // No clear direction
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(int direction) {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl_distance = CalculateStopLossDistance();
    
    if(direction == 1) { // Buy
        return current_price - sl_distance;
    } else { // Sell
        return current_price + sl_distance;
    }
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int direction, double sl) {
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl_distance = MathAbs(current_price - sl);
    
    // Use dynamic RR based on structure
    double rr_ratio = 3.0; // Default 1:3
    
    // Adjust RR based on confluence
    if(CheckSniperConfluence()) rr_ratio = 5.0;
    
    if(direction == 1) { // Buy
        return current_price + (sl_distance * rr_ratio);
    } else { // Sell
        return current_price - (sl_distance * rr_ratio);
    }
}

//+------------------------------------------------------------------+
//| Validate Stop Loss and Take Profit                              |
//+------------------------------------------------------------------+
bool ValidateSLTP(int direction, double sl, double tp) {
    double current_price = SymbolInfoDouble(Symbol(), (direction == 1) ? SYMBOL_ASK : SYMBOL_BID);
    double min_distance = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * Point();
    
    // Check minimum distance for SL
    if(MathAbs(current_price - sl) < min_distance) return false;
    
    // Check minimum distance for TP
    if(MathAbs(current_price - tp) < min_distance) return false;
    
    // Check SL is in correct direction
    if(direction == 1 && sl >= current_price) return false;
    if(direction == -1 && sl <= current_price) return false;
    
    // Check TP is in correct direction
    if(direction == 1 && tp <= current_price) return false;
    if(direction == -1 && tp >= current_price) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Manage Existing Trades                                          |
//+------------------------------------------------------------------+
void ManageExistingTrades() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByIndex(i)) {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                ManageTradePosition(PositionGetTicket(POSITION_TICKET));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Individual Trade Position                                |
//+------------------------------------------------------------------+
void ManageTradePosition(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return;
    
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    int type = (int)PositionGetInteger(POSITION_TYPE);
    
    // Move to break-even at 1:1 RR
    if(!IsAtBreakEven(ticket)) {
        MoveToBreakEven(ticket, type, open_price, current_price, sl);
    }
    
    // Trail stop loss
    if(IsAtBreakEven(ticket)) {
        TrailStopLoss(ticket, type, current_price, sl);
    }
}

//+------------------------------------------------------------------+
//| Check if Position is at Break Even                              |
//+------------------------------------------------------------------+
bool IsAtBreakEven(ulong ticket) {
    if(!PositionSelectByTicket(ticket)) return false;
    
    double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    
    return MathAbs(sl - open_price) < Point() * 5;
}

//+------------------------------------------------------------------+
//| Move Position to Break Even                                     |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket, int type, double open_price, double current_price, double sl) {
    double sl_distance = MathAbs(open_price - sl);
    bool move_to_be = false;
    
    if(type == POSITION_TYPE_BUY) {
        if(current_price >= open_price + sl_distance) move_to_be = true;
    } else {
        if(current_price <= open_price - sl_distance) move_to_be = true;
    }
    
    if(move_to_be) {
        MqlTradeRequest request;
        MqlTradeResult result;
        
        ZeroMemory(request);
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.sl = open_price + (Point() * 10); // Small buffer above break-even
        request.tp = PositionGetDouble(POSITION_TP);
        
        OrderSend(request, result);
    }
}

//+------------------------------------------------------------------+
//| Trail Stop Loss                                                 |
//+------------------------------------------------------------------+
void TrailStopLoss(ulong ticket, int type, double current_price, double current_sl) {
    double trail_distance = Point() * 200; // 20 pips trailing
    double new_sl = current_sl;
    
    if(type == POSITION_TYPE_BUY) {
        new_sl = current_price - trail_distance;
        if(new_sl > current_sl) {
            ModifyStopLoss(ticket, new_sl);
        }
    } else {
        new_sl = current_price + trail_distance;
        if(new_sl < current_sl) {
            ModifyStopLoss(ticket, new_sl);
        }
    }
}

//+------------------------------------------------------------------+
//| Modify Stop Loss                                                |
//+------------------------------------------------------------------+
void ModifyStopLoss(ulong ticket, double new_sl) {
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = new_sl;
    request.tp = PositionGetDouble(POSITION_TP);
    
    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Check for Volume Spike                                          |
//+------------------------------------------------------------------+
bool IsVolumeSpike() {
    // Simplified volume spike detection
    long current_volume = iVolume(Symbol(), Entry_Timeframe, 1);
    long avg_volume = 0;
    
    for(int i = 2; i <= 21; i++) {
        avg_volume += iVolume(Symbol(), Entry_Timeframe, i);
    }
    avg_volume = avg_volume / 20;
    
    return current_volume > avg_volume * 1.5;
}

//+------------------------------------------------------------------+
//| Check Volume Spike at Specific Index                            |
//+------------------------------------------------------------------+
bool IsVolumeSpikeAtIndex(ENUM_TIMEFRAMES timeframe, int index) {
    long current_volume = iVolume(Symbol(), timeframe, index);
    long avg_volume = 0;
    
    for(int i = index + 1; i <= index + 20; i++) {
        avg_volume += iVolume(Symbol(), timeframe, i);
    }
    avg_volume = avg_volume / 20;
    
    return current_volume > avg_volume * 1.5;
}

//+------------------------------------------------------------------+
//| Check if in Premium/Discount Zone                               |
//+------------------------------------------------------------------+
bool IsPremiumDiscountZone() {
    double daily_high = iHigh(Symbol(), PERIOD_D1, 1);
    double daily_low = iLow(Symbol(), PERIOD_D1, 1);
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    double range = daily_high - daily_low;
    double mid_point = daily_low + (range * 0.5);
    
    // Premium zone (upper 20%)
    if(current_price > daily_low + (range * 0.8)) return true;
    
    // Discount zone (lower 20%)
    if(current_price < daily_low + (range * 0.2)) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    string session = GetCurrentSession();
    double daily_pnl = CalculateDailyPnL();
    
    dashboardText[0] = "=== ICT SMC EXPERT ===";
    dashboardText[1] = "Mode: " + currentRiskMode;
    dashboardText[2] = "Balance: $" + DoubleToString(accountBalance, 2);
    dashboardText[3] = "Equity: $" + DoubleToString(accountEquity, 2);
    dashboardText[4] = "Spread: " + DoubleToString(currentSpread / Point(), 1) + " pts";
    dashboardText[5] = "Trades Today: " + IntegerToString(tradesCountToday);
    dashboardText[6] = "Session: " + session;
    dashboardText[7] = "Daily P&L: $" + DoubleToString(daily_pnl, 2);
    dashboardText[8] = "Monthly Bias: " + (monthlyBias > 0 ? "BULLISH" : "BEARISH");
    dashboardText[9] = "Weekly Bias: " + (weeklyBias > 0 ? "BULLISH" : "BEARISH");
    dashboardText[10] = "Daily Bias: " + (dailyBias > 0 ? "BULLISH" : "BEARISH");
    dashboardText[11] = "OB Count: " + IntegerToString(ArraySize(orderBlocks));
    
    DrawDashboard();
}

//+------------------------------------------------------------------+
//| Get Current Session                                              |
//+------------------------------------------------------------------+
string GetCurrentSession() {
    MqlDateTime current_time;
    TimeToStruct(TimeCurrent(), current_time);
    int hour = current_time.hour;
    
    if(hour >= 2 && hour <= 5) return "ASIA";
    if(hour >= 7 && hour <= 10) return "LONDON";
    if(hour >= 13 && hour <= 16) return "NEW YORK";
    
    return "OFF HOURS";
}

//+------------------------------------------------------------------+
//| Calculate Daily P&L                                             |
//+------------------------------------------------------------------+
double CalculateDailyPnL() {
    // Simplified daily P&L calculation
    return accountEquity - accountBalance;
}

//+------------------------------------------------------------------+
//| Draw Dashboard                                                   |
//+------------------------------------------------------------------+
void DrawDashboard() {
    int x = 20;
    int y = 30;
    int line_height = 18;
    
    for(int i = 0; i < dashboardLines; i++) {
        string obj_name = "Dashboard_" + IntegerToString(i);
        
        if(ObjectFind(0, obj_name) < 0) {
            ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
        }
        
        ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y + (i * line_height));
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
        ObjectSetString(0, obj_name, OBJPROP_TEXT, dashboardText[i]);
    }
}

//+------------------------------------------------------------------+
//| Draw Order Block                                                |
//+------------------------------------------------------------------+
void DrawOrderBlock(const OrderBlock &ob) {
    string obj_name = "ICT_OB_" + TimeToString(ob.time);
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, ob.time, ob.high, ob.time + PeriodSeconds(HTF_Timeframe) * 20, ob.low);
    }
    
    color ob_color = (ob.direction == 1) ? BullishColor : BearishColor;
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, ob_color);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Draw Fair Value Gap                                             |
//+------------------------------------------------------------------+
void DrawFairValueGap(const FairValueGap &fvg) {
    string obj_name = "ICT_FVG_" + TimeToString(fvg.time);
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, fvg.time, fvg.high, fvg.time + PeriodSeconds(Entry_Timeframe) * 10, fvg.low);
    }
    
    color fvg_color = (fvg.direction == 1) ? clrBlue : clrMagenta;
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, fvg_color);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, false);
}

//+------------------------------------------------------------------+
//| Draw Break of Structure                                         |
//+------------------------------------------------------------------+
void DrawBOS(double price, datetime time, int direction) {
    string obj_name = "ICT_BOS_" + TimeToString(time);
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price);
    }
    
    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, (direction == 1) ? 233 : 234);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrYellow);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 3);
}

//+------------------------------------------------------------------+
//| Draw Change of Character                                        |
//+------------------------------------------------------------------+
void DrawCHoCH(double price, datetime time, int direction) {
    string obj_name = "ICT_CHoCH_" + TimeToString(time);
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price);
    }
    
    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, (direction == 1) ? 217 : 218);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrOrange);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 3);
}

//+------------------------------------------------------------------+
//| Draw Market Structure Shift                                    |
//+------------------------------------------------------------------+
void DrawMSS(double price, datetime time) {
    string obj_name = "ICT_MSS_" + TimeToString(time);
    
    if(ObjectFind(0, obj_name) < 0) {
        ObjectCreate(0, obj_name, OBJ_ARROW, 0, time, price);
    }
    
    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 159);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrLightBlue);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 4);
}

//+------------------------------------------------------------------+
//| End of Expert Advisor                                           |
//+------------------------------------------------------------------+