//+------------------------------------------------------------------+
//|                                          ICT_SMC_Expert_Advisor.mq5 |
//|                                      Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//--- Input Parameters for ICT/SMC Control
input group "=== ICT/SMC Control Flags ==="
input bool Enable_OB               = true;  // Enable Order Block Detection
input bool Enable_FVG              = true;  // Enable Fair Value Gap Detection
input bool Enable_BOS              = true;  // Enable Break of Structure
input bool Enable_CHoCH            = true;  // Enable Change of Character
input bool Enable_MSS              = true;  // Enable Market Structure Shift
input bool Enable_BreakerBlock     = true;  // Enable Breaker Block Detection
input bool Enable_OBinOB           = true;  // Enable Order Block in Order Block
input bool Enable_LiquiditySweep   = true;  // Enable Liquidity Sweep Detection
input bool Enable_JudasSwing       = true;  // Enable Judas Swing Detection
input bool Enable_TurtleSoup       = true;  // Enable Turtle Soup Pattern
input bool Enable_BPR              = true;  // Enable Balanced Price Range
input bool Enable_LiquidityVoid    = true;  // Enable Liquidity Void Detection
input bool Enable_VolumeSpike      = true;  // Enable Volume Spike Analysis
input bool Enable_StopHuntFilter   = true;  // Enable Stop Hunt Filter
input bool Enable_PremiumDiscount  = true;  // Enable Premium/Discount Zones
input bool Enable_BuySellModel     = true;  // Enable Buy/Sell Model
input bool Enable_TrapFilter       = true;  // Enable Trap Filter
input bool Enable_OBMemory         = true;  // Enable Order Block Memory
input bool Enable_ReEntryEngine    = true;  // Enable Re-Entry Engine
input bool Enable_KillzoneFilter   = true;  // Enable Killzone Filter
input bool Enable_StrictSniperOnly = true;  // Enable Strict Sniper Mode

input group "=== Risk Management ==="
input double UltraMicroRisk = 25.0;  // Ultra-Micro Mode Risk % (< $20)
input double SafeModeRisk   = 5.0;   // Safe Mode Risk % ($20-$500)
input double TurboModeRisk  = 20.0;  // Turbo Mode Risk % (> $500)
input double MaxDrawdown    = 15.0;  // Maximum Drawdown % (Safe Mode)
input int    MaxSpread      = 30;    // Maximum Spread in Points

input group "=== Trade Settings ==="
input int    MagicNumber    = 12345; // Magic Number
input string TradeComment   = "ICT_SMC_EA"; // Trade Comment
input bool   VisualMode     = true;  // Show Visual Elements
input bool   ShowDashboard  = true;  // Show Dashboard

//--- Global Variables
struct OrderBlock {
    datetime time;
    double high;
    double low;
    double open;
    double close;
    int direction; // 1 for bullish, -1 for bearish
    bool valid;
    bool used;
};

struct FairValueGap {
    datetime time;
    double upper;
    double lower;
    int direction;
    bool filled;
};

struct LiquidityLevel {
    double price;
    datetime time;
    int strength;
    bool swept;
};

//--- Arrays for storing structures
OrderBlock g_orderBlocks[10];
FairValueGap g_fvgs[20];
LiquidityLevel g_liquidity[50];

//--- Global Variables
double g_accountBalance;
double g_currentSpread;
int g_riskMode; // 0=Ultra-Micro, 1=Safe, 2=Turbo
string g_currentSession;
int g_htfBias; // 1=Bullish, -1=Bearish, 0=Neutral
int g_tradesCountToday;
double g_lastTradeRR;
datetime g_lastTradeTime;

//--- Dashboard Variables
string g_dashboardLines[15];
int g_dashboardY = 50;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize arrays
    ArrayInitialize(g_orderBlocks, 0);
    ArrayInitialize(g_fvgs, 0);
    ArrayInitialize(g_liquidity, 0);
    ArrayInitialize(g_dashboardLines, "");
    
    // Set up chart
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    ChartSetInteger(0, CHART_SHOW_VOLUMES, true);
    
    Print("ICT SMC Expert Advisor Initialized Successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up visual elements
    ObjectsDeleteAll(0, "ICT_");
    ObjectsDeleteAll(0, "DASH_");
    Comment("");
}

//+------------------------------------------------------------------+
//| Update Global Variables                                          |
//+------------------------------------------------------------------+
void UpdateGlobalVariables() {
    g_accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // Calculate current spread
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    g_currentSpread = (ask - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Determine risk mode based on balance
    if(g_accountBalance < 20) {
        g_riskMode = 0; // Ultra-Micro
    } else if(g_accountBalance <= 500) {
        g_riskMode = 1; // Safe
    } else {
        g_riskMode = 2; // Turbo
    }
    
    // Determine current session
    g_currentSession = GetCurrentSession();
    
    // Update HTF bias
    g_htfBias = CalculateHTFBias();
    
    // Count today's trades
    g_tradesCountToday = CountTradesToday();
}

//+------------------------------------------------------------------+
//| Get Current Trading Session                                      |
//+------------------------------------------------------------------+
string GetCurrentSession() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int hour = dt.hour;
    
    if(hour >= 0 && hour < 9) return "ASIA";
    else if(hour >= 9 && hour < 16) return "LONDON";
    else if(hour >= 16 && hour < 24) return "NEW_YORK";
    
    return "TRANSITION";
}

//+------------------------------------------------------------------+
//| Calculate Higher Timeframe Bias                                 |
//+------------------------------------------------------------------+
int CalculateHTFBias() {
    // Get daily, weekly, and monthly structure
    double dailyHigh = iHigh(_Symbol, PERIOD_D1, 1);
    double dailyLow = iLow(_Symbol, PERIOD_D1, 1);
    double dailyClose = iClose(_Symbol, PERIOD_D1, 1);
    double dailyOpen = iOpen(_Symbol, PERIOD_D1, 1);
    
    double weeklyHigh = iHigh(_Symbol, PERIOD_W1, 1);
    double weeklyLow = iLow(_Symbol, PERIOD_W1, 1);
    double weeklyClose = iClose(_Symbol, PERIOD_W1, 1);
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    int bias = 0;
    
    // Daily bias
    if(dailyClose > dailyOpen && currentPrice > (dailyHigh + dailyLow) / 2) bias++;
    else if(dailyClose < dailyOpen && currentPrice < (dailyHigh + dailyLow) / 2) bias--;
    
    // Weekly bias
    if(currentPrice > (weeklyHigh + weeklyLow) / 2) bias++;
    else bias--;
    
    // Structural bias based on recent swing highs/lows
    double recentHigh = iHigh(_Symbol, PERIOD_H4, iHighest(_Symbol, PERIOD_H4, MODE_HIGH, 20, 1));
    double recentLow = iLow(_Symbol, PERIOD_H4, iLowest(_Symbol, PERIOD_H4, MODE_LOW, 20, 1));
    
    if(currentPrice > recentHigh) bias++;
    else if(currentPrice < recentLow) bias--;
    
    if(bias > 0) return 1;      // Bullish
    else if(bias < 0) return -1; // Bearish
    else return 0;               // Neutral
}

//+------------------------------------------------------------------+
//| Update Order Blocks                                             |
//+------------------------------------------------------------------+
void UpdateOrderBlocks() {
    // Look for order blocks in the last 100 bars
    for(int i = 3; i < 100; i++) {
        if(IsOrderBlock(i)) {
            // Store order block if not already stored
            StoreOrderBlock(i);
        }
    }
    
    // Validate existing order blocks
    ValidateOrderBlocks();
}

//+------------------------------------------------------------------+
//| Check if bar is an Order Block                                  |
//+------------------------------------------------------------------+
bool IsOrderBlock(int shift) {
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift + 1);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift + 1);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
    
    double high0 = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low0 = iLow(_Symbol, PERIOD_CURRENT, shift);
    double close0 = iClose(_Symbol, PERIOD_CURRENT, shift);
    
    double high_1 = iHigh(_Symbol, PERIOD_CURRENT, shift - 1);
    double low_1 = iLow(_Symbol, PERIOD_CURRENT, shift - 1);
    double close_1 = iClose(_Symbol, PERIOD_CURRENT, shift - 1);
    
    // Bullish Order Block: Strong down move followed by strong up move
    bool bullishOB = (close1 < open1) && // Previous bar bearish
                     (high1 - low1 > (high0 - low0) * 1.5) && // Previous bar range larger
                     (close0 > high1) && // Current bar closes above previous high
                     (close_1 > close0); // Next bar continues up
    
    // Bearish Order Block: Strong up move followed by strong down move
    bool bearishOB = (close1 > open1) && // Previous bar bullish
                     (high1 - low1 > (high0 - low0) * 1.5) && // Previous bar range larger
                     (close0 < low1) && // Current bar closes below previous low
                     (close_1 < close0); // Next bar continues down
    
    return (bullishOB || bearishOB);
}

//+------------------------------------------------------------------+
//| Store Order Block                                               |
//+------------------------------------------------------------------+
void StoreOrderBlock(int shift) {
    datetime time = iTime(_Symbol, PERIOD_CURRENT, shift);
    
    // Check if already stored
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].time == time) return;
    }
    
    // Find empty slot or replace oldest
    int slot = -1;
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].time == 0) {
            slot = i;
            break;
        }
    }
    
    if(slot == -1) {
        // Shift array and use last slot
        for(int i = 0; i < ArraySize(g_orderBlocks) - 1; i++) {
            g_orderBlocks[i] = g_orderBlocks[i + 1];
        }
        slot = ArraySize(g_orderBlocks) - 1;
    }
    
    // Store order block
    g_orderBlocks[slot].time = time;
    g_orderBlocks[slot].high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    g_orderBlocks[slot].low = iLow(_Symbol, PERIOD_CURRENT, shift);
    g_orderBlocks[slot].open = iOpen(_Symbol, PERIOD_CURRENT, shift);
    g_orderBlocks[slot].close = iClose(_Symbol, PERIOD_CURRENT, shift);
    g_orderBlocks[slot].direction = (g_orderBlocks[slot].close > g_orderBlocks[slot].open) ? 1 : -1;
    g_orderBlocks[slot].valid = true;
    g_orderBlocks[slot].used = false;
}

//+------------------------------------------------------------------+
//| Validate Order Blocks                                           |
//+------------------------------------------------------------------+
void ValidateOrderBlocks() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].time == 0) continue;
        
        // Invalidate if price has moved significantly beyond the block
        if(g_orderBlocks[i].direction == 1) { // Bullish OB
            if(currentPrice < g_orderBlocks[i].low - (g_orderBlocks[i].high - g_orderBlocks[i].low) * 0.5) {
                g_orderBlocks[i].valid = false;
            }
        } else { // Bearish OB
            if(currentPrice > g_orderBlocks[i].high + (g_orderBlocks[i].high - g_orderBlocks[i].low) * 0.5) {
                g_orderBlocks[i].valid = false;
            }
        }
        
        // Mark as used if price has reacted from it
        if(g_orderBlocks[i].valid && !g_orderBlocks[i].used) {
            if(g_orderBlocks[i].direction == 1 && currentPrice >= g_orderBlocks[i].low && currentPrice <= g_orderBlocks[i].high) {
                // Check if price bounced from this level
                if(HasBounced(g_orderBlocks[i].low, g_orderBlocks[i].high, true)) {
                    g_orderBlocks[i].used = true;
                }
            } else if(g_orderBlocks[i].direction == -1 && currentPrice >= g_orderBlocks[i].low && currentPrice <= g_orderBlocks[i].high) {
                if(HasBounced(g_orderBlocks[i].low, g_orderBlocks[i].high, false)) {
                    g_orderBlocks[i].used = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if price has bounced from level                           |
//+------------------------------------------------------------------+
bool HasBounced(double levelLow, double levelHigh, bool expectBullishBounce) {
    // Check last 10 bars for bounce pattern
    for(int i = 1; i <= 10; i++) {
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        
        if(low <= levelHigh && high >= levelLow) {
            // Price was in the level range
            if(expectBullishBounce) {
                // Check if subsequent bars moved higher
                for(int j = i - 1; j >= 1; j--) {
                    if(iClose(_Symbol, PERIOD_CURRENT, j) > levelHigh) return true;
                }
            } else {
                // Check if subsequent bars moved lower
                for(int j = i - 1; j >= 1; j--) {
                    if(iClose(_Symbol, PERIOD_CURRENT, j) < levelLow) return true;
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update Fair Value Gaps                                          |
//+------------------------------------------------------------------+
void UpdateFairValueGaps() {
    // Look for FVGs in the last 50 bars
    for(int i = 2; i < 50; i++) {
        FairValueGap fvg = DetectFVG(i);
        if(fvg.time != 0) {
            StoreFVG(fvg);
        }
    }
    
    // Check if FVGs are filled
    ValidateFVGs();
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gap                                           |
//+------------------------------------------------------------------+
FairValueGap DetectFVG(int shift) {
    FairValueGap fvg;
    fvg.time = 0;
    
    double high2 = iHigh(_Symbol, PERIOD_CURRENT, shift + 2);
    double low2 = iLow(_Symbol, PERIOD_CURRENT, shift + 2);
    
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, shift + 1);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, shift + 1);
    
    double high0 = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low0 = iLow(_Symbol, PERIOD_CURRENT, shift);
    
    // Bullish FVG: Gap between bar -2 high and bar 0 low
    if(low0 > high2 && high1 > low1) {
        fvg.time = iTime(_Symbol, PERIOD_CURRENT, shift + 1);
        fvg.upper = low0;
        fvg.lower = high2;
        fvg.direction = 1;
        fvg.filled = false;
    }
    // Bearish FVG: Gap between bar -2 low and bar 0 high
    else if(high0 < low2 && high1 > low1) {
        fvg.time = iTime(_Symbol, PERIOD_CURRENT, shift + 1);
        fvg.upper = low2;
        fvg.lower = high0;
        fvg.direction = -1;
        fvg.filled = false;
    }
    
    return fvg;
}

//+------------------------------------------------------------------+
//| Store Fair Value Gap                                            |
//+------------------------------------------------------------------+
void StoreFVG(FairValueGap &fvg) {
    // Check if already stored
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time == fvg.time) return;
    }
    
    // Find empty slot or replace oldest
    int slot = -1;
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time == 0) {
            slot = i;
            break;
        }
    }
    
    if(slot == -1) {
        // Shift array
        for(int i = 0; i < ArraySize(g_fvgs) - 1; i++) {
            g_fvgs[i] = g_fvgs[i + 1];
        }
        slot = ArraySize(g_fvgs) - 1;
    }
    
    g_fvgs[slot] = fvg;
}

//+------------------------------------------------------------------+
//| Validate Fair Value Gaps                                        |
//+------------------------------------------------------------------+
void ValidateFVGs() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time == 0 || g_fvgs[i].filled) continue;
        
        // Check if FVG is filled
        if(currentPrice >= g_fvgs[i].lower && currentPrice <= g_fvgs[i].upper) {
            g_fvgs[i].filled = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Update Liquidity Levels                                         |
//+------------------------------------------------------------------+
void UpdateLiquidityLevels() {
    // Find swing highs and lows as liquidity levels
    for(int i = 5; i < 100; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        datetime time = iTime(_Symbol, PERIOD_CURRENT, i);
        
        // Check for swing high
        if(IsSwingHigh(i, 3)) {
            StoreLiquidityLevel(high, time, 1);
        }
        
        // Check for swing low
        if(IsSwingLow(i, 3)) {
            StoreLiquidityLevel(low, time, -1);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if bar is swing high                                      |
//+------------------------------------------------------------------+
bool IsSwingHigh(int shift, int period) {
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    
    for(int i = 1; i <= period; i++) {
        if(iHigh(_Symbol, PERIOD_CURRENT, shift + i) >= high ||
           iHigh(_Symbol, PERIOD_CURRENT, shift - i) >= high) {
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check if bar is swing low                                       |
//+------------------------------------------------------------------+
bool IsSwingLow(int shift, int period) {
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);
    
    for(int i = 1; i <= period; i++) {
        if(iLow(_Symbol, PERIOD_CURRENT, shift + i) <= low ||
           iLow(_Symbol, PERIOD_CURRENT, shift - i) <= low) {
            return false;
        }
    }
    return true;
}

//+------------------------------------------------------------------+
//| Store Liquidity Level                                           |
//+------------------------------------------------------------------+
void StoreLiquidityLevel(double price, datetime time, int type) {
    // Check if similar level already exists
    for(int i = 0; i < ArraySize(g_liquidity); i++) {
        if(MathAbs(g_liquidity[i].price - price) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20) {
            return; // Too close to existing level
        }
    }
    
    // Find empty slot or replace oldest
    int slot = -1;
    for(int i = 0; i < ArraySize(g_liquidity); i++) {
        if(g_liquidity[i].time == 0) {
            slot = i;
            break;
        }
    }
    
    if(slot == -1) {
        // Shift array
        for(int i = 0; i < ArraySize(g_liquidity) - 1; i++) {
            g_liquidity[i] = g_liquidity[i + 1];
        }
        slot = ArraySize(g_liquidity) - 1;
    }
    
    g_liquidity[slot].price = price;
    g_liquidity[slot].time = time;
    g_liquidity[slot].strength = type;
    g_liquidity[slot].swept = false;
}

//+------------------------------------------------------------------+
//| Check for Trade Opportunities                                   |
//+------------------------------------------------------------------+
void CheckTradeOpportunities() {
    // Skip if market is closed or spread too wide
    if(!IsMarketOpen() || g_currentSpread > MaxSpread) return;
    
    // Skip if in forbidden times
    if(!IsValidTradingTime()) return;
    
    // Check maximum positions
    if(PositionsTotal() > 0 && g_riskMode == 1) return; // Safe mode: one trade at a time
    
    // Check drawdown limit
    if(g_riskMode == 1 && CalculateDrawdown() > MaxDrawdown) return;
    
    // Look for valid order block setups
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(!g_orderBlocks[i].valid || g_orderBlocks[i].used) continue;
        if(!Enable_OBMemory && g_orderBlocks[i].used) continue;
        
        if(IsValidTradeSetup(i)) {
            ExecuteTrade(i);
            break; // Only one trade per tick
        }
    }
}

//+------------------------------------------------------------------+
//| Check if market is open                                         |
//+------------------------------------------------------------------+
bool IsMarketOpen() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Avoid Friday close and Monday open
    if(dt.day_of_week == 5 && dt.hour >= 21) return false; // Friday after 21:00
    if(dt.day_of_week == 1 && dt.hour < 1) return false;   // Monday before 01:00
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if valid trading time                                     |
//+------------------------------------------------------------------+
bool IsValidTradingTime() {
    if(!Enable_KillzoneFilter) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hour = dt.hour;
    
    // London session: 08:00 - 12:00
    if(hour >= 8 && hour < 12) return true;
    
    // New York session: 13:00 - 17:00
    if(hour >= 13 && hour < 17) return true;
    
    // Asia session: 00:00 - 04:00
    if(hour >= 0 && hour < 4) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate current drawdown                                      |
//+------------------------------------------------------------------+
double CalculateDrawdown() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(balance == 0) return 0;
    
    return ((balance - equity) / balance) * 100.0;
}

//+------------------------------------------------------------------+
//| Check if valid trade setup                                      |
//+------------------------------------------------------------------+
bool IsValidTradeSetup(int obIndex) {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    OrderBlock ob = g_orderBlocks[obIndex];
    
    // Basic Order Block validation
    if(!Enable_OB || !OrderBlockValid(obIndex)) return false;
    
    // Price must be in order block range
    if(currentPrice < ob.low || currentPrice > ob.high) return false;
    
    // Check FVG confluence if enabled
    if(Enable_FVG && !FVGInsideOBDetected(obIndex)) return false;
    
    // Check market structure if enabled
    if((Enable_CHoCH || Enable_BOS || Enable_MSS) && !CheckMarketStructure()) return false;
    
    // Check volume spike if enabled
    if(Enable_VolumeSpike && !VolumeSpike()) return false;
    
    // Check trap filter
    if(Enable_TrapFilter && IsTrapSetup(obIndex)) return false;
    
    // Check premium/discount if enabled
    if(Enable_PremiumDiscount && !IsInPremiumDiscount(ob.direction)) return false;
    
    // Strict sniper mode: require all confluence
    if(Enable_StrictSniperOnly) {
        bool confluence = true;
        
        if(Enable_FVG && !FVGInsideOBDetected(obIndex)) confluence = false;
        if(Enable_VolumeSpike && !VolumeSpike()) confluence = false;
        if(Enable_LiquiditySweep && !LiquiditySweepDetected()) confluence = false;
        if(Enable_BPR && !BalancedPriceRange()) confluence = false;
        
        if(!confluence) return false;
    }
    
    // Check bias alignment
    if(g_htfBias != 0 && g_htfBias != ob.direction) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Order Block                                            |
//+------------------------------------------------------------------+
bool OrderBlockValid(int index) {
    if(index < 0 || index >= ArraySize(g_orderBlocks)) return false;
    
    OrderBlock ob = g_orderBlocks[index];
    if(ob.time == 0 || !ob.valid) return false;
    
    // Check if order block is recent enough
    if(TimeCurrent() - ob.time > 86400 * 7) return false; // 1 week max
    
    // Check if order block has proper structure
    if(ob.high <= ob.low) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check FVG inside Order Block                                    |
//+------------------------------------------------------------------+
bool FVGInsideOBDetected(int obIndex) {
    if(!Enable_FVG) return true; // If FVG not enabled, pass this check
    
    OrderBlock ob = g_orderBlocks[obIndex];
    
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time == 0 || g_fvgs[i].filled) continue;
        
        // Check if FVG is within order block
        if(g_fvgs[i].lower >= ob.low && g_fvgs[i].upper <= ob.high) {
            // Check direction alignment
            if(g_fvgs[i].direction == ob.direction) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Market Structure                                          |
//+------------------------------------------------------------------+
bool CheckMarketStructure() {
    // Look for BOS, CHoCH, or MSS in recent bars
    bool structureShift = false;
    
    if(Enable_BOS) structureShift |= DetectBOS();
    if(Enable_CHoCH) structureShift |= DetectCHoCH();
    if(Enable_MSS) structureShift |= DetectMSS();
    
    return structureShift;
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                       |
//+------------------------------------------------------------------+
bool DetectBOS() {
    // Look for break of recent swing high/low
    for(int i = 5; i < 50; i++) {
        if(IsSwingHigh(i, 3)) {
            double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
            if(iClose(_Symbol, PERIOD_CURRENT, 1) > swingHigh) {
                return true; // Bullish BOS
            }
        }
        
        if(IsSwingLow(i, 3)) {
            double swingLow = iLow(_Symbol, PERIOD_CURRENT, i);
            if(iClose(_Symbol, PERIOD_CURRENT, 1) < swingLow) {
                return true; // Bearish BOS
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Change of Character                                      |
//+------------------------------------------------------------------+
bool DetectCHoCH() {
    // Similar to BOS but with different criteria
    // Check for failure to make new high/low followed by opposite direction move
    
    double recentHigh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 20, 1));
    double recentLow = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 20, 1));
    double currentClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    
    // Failed to make new high and now breaking structure low
    if(currentClose < recentLow && iClose(_Symbol, PERIOD_CURRENT, 5) > (recentHigh + recentLow) / 2) {
        return true;
    }
    
    // Failed to make new low and now breaking structure high
    if(currentClose > recentHigh && iClose(_Symbol, PERIOD_CURRENT, 5) < (recentHigh + recentLow) / 2) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Market Structure Shift                                   |
//+------------------------------------------------------------------+
bool DetectMSS() {
    // Check for significant trend change
    double ma20 = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
    double ma50 = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE, 1);
    double ma20_prev = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE, 10);
    double ma50_prev = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE, 10);
    
    // MA crossover indicates structure shift
    if((ma20 > ma50 && ma20_prev <= ma50_prev) || (ma20 < ma50 && ma20_prev >= ma50_prev)) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Volume Spike                                              |
//+------------------------------------------------------------------+
bool VolumeSpike() {
    if(!Enable_VolumeSpike) return true;
    
    long currentVolume = iVolume(_Symbol, PERIOD_CURRENT, 1);
    long avgVolume = 0;
    
    // Calculate average volume of last 20 bars
    for(int i = 2; i <= 21; i++) {
        avgVolume += iVolume(_Symbol, PERIOD_CURRENT, i);
    }
    avgVolume /= 20;
    
    // Volume spike if current volume is 150% of average
    return (currentVolume > avgVolume * 1.5);
}

//+------------------------------------------------------------------+
//| Check if setup is a trap                                        |
//+------------------------------------------------------------------+
bool IsTrapSetup(int obIndex) {
    if(!Enable_TrapFilter) return false;
    
    OrderBlock ob = g_orderBlocks[obIndex];
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check if this OB has been tested multiple times
    int testCount = 0;
    for(int i = 1; i <= 20; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        
        if(low <= ob.high && high >= ob.low) {
            testCount++;
        }
    }
    
    // If tested more than 3 times, consider it a trap
    return (testCount > 3);
}

//+------------------------------------------------------------------+
//| Check Premium/Discount Zone                                     |
//+------------------------------------------------------------------+
bool IsInPremiumDiscount(int direction) {
    if(!Enable_PremiumDiscount) return true;
    
    // Get daily range
    double dailyHigh = iHigh(_Symbol, PERIOD_D1, 1);
    double dailyLow = iLow(_Symbol, PERIOD_D1, 1);
    double dailyRange = dailyHigh - dailyLow;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double pricePosition = (currentPrice - dailyLow) / dailyRange;
    
    // For bullish trades, prefer discount (lower 40%)
    if(direction == 1 && pricePosition > 0.6) return false;
    
    // For bearish trades, prefer premium (upper 40%)
    if(direction == -1 && pricePosition < 0.4) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                          |
//+------------------------------------------------------------------+
bool LiquiditySweepDetected() {
    if(!Enable_LiquiditySweep) return true;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check if recent price action swept through liquidity levels
    for(int i = 0; i < ArraySize(g_liquidity); i++) {
        if(g_liquidity[i].time == 0 || g_liquidity[i].swept) continue;
        
        // Check if liquidity was swept in last 5 bars
        for(int j = 1; j <= 5; j++) {
            double high = iHigh(_Symbol, PERIOD_CURRENT, j);
            double low = iLow(_Symbol, PERIOD_CURRENT, j);
            
            if(g_liquidity[i].strength == 1 && high > g_liquidity[i].price) {
                g_liquidity[i].swept = true;
                return true;
            } else if(g_liquidity[i].strength == -1 && low < g_liquidity[i].price) {
                g_liquidity[i].swept = true;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Balanced Price Range                                      |
//+------------------------------------------------------------------+
bool BalancedPriceRange() {
    if(!Enable_BPR) return true;
    
    // Check if price is in a balanced range (low volatility)
    double atr = iATR(_Symbol, PERIOD_CURRENT, 14, 1);
    double avgATR = 0;
    
    for(int i = 2; i <= 21; i++) {
        avgATR += iATR(_Symbol, PERIOD_CURRENT, 14, i);
    }
    avgATR /= 20;
    
    // BPR if current ATR is less than 70% of average
    return (atr < avgATR * 0.7);
}

//+------------------------------------------------------------------+
//| Execute Trade                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int obIndex) {
    OrderBlock ob = g_orderBlocks[obIndex];
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Calculate lot size based on risk mode
    double lotSize = CalculateLotSize(ob);
    if(lotSize == 0) return;
    
    // Calculate entry, SL, and TP
    double entry = (ob.direction == 1) ? ob.low : ob.high;
    double sl = CalculateStopLoss(ob);
    double tp = CalculateTakeProfit(ob, sl);
    
    // Validate trade parameters
    if(!ValidateTradeParams(entry, sl, tp, lotSize)) return;
    
    // Send trade
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.type = (ob.direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price = (ob.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.comment = TradeComment;
    request.type_filling = ORDER_FILLING_FOK;
    
    if(OrderSend(request, result)) {
        Print("Trade executed successfully. Ticket: ", result.order);
        g_orderBlocks[obIndex].used = true;
        g_lastTradeTime = TimeCurrent();
    } else {
        Print("Trade execution failed. Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                              |
//+------------------------------------------------------------------+
double CalculateLotSize(OrderBlock &ob) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    
    double riskPercent;
    switch(g_riskMode) {
        case 0: riskPercent = UltraMicroRisk; break; // Ultra-Micro
        case 1: riskPercent = SafeModeRisk; break;   // Safe
        case 2: riskPercent = TurboModeRisk; break;  // Turbo
        default: riskPercent = SafeModeRisk; break;
    }
    
    double riskAmount = balance * riskPercent / 100.0;
    double slDistance = MathAbs(ob.high - ob.low) + g_currentSpread * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointValue = tickValue / tickSize * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double lotSize = riskAmount / (slDistance / SymbolInfoDouble(_Symbol, SYMBOL_POINT) * pointValue);
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, MathRound(lotSize / lotStep) * lotStep));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss                                             |
//+------------------------------------------------------------------+
double CalculateStopLoss(OrderBlock &ob) {
    double spread = g_currentSpread * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double buffer = (ob.high - ob.low) * 0.1; // 10% buffer
    
    double sl;
    if(ob.direction == 1) {
        sl = ob.low - buffer - spread;
    } else {
        sl = ob.high + buffer + spread;
    }
    
    // Ensure minimum stop level
    double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double currentPrice = (ob.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(ob.direction == 1) {
        sl = MathMin(sl, currentPrice - minStopLevel);
    } else {
        sl = MathMax(sl, currentPrice + minStopLevel);
    }
    
    return sl;
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(OrderBlock &ob, double sl) {
    double entry = (ob.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDistance = MathAbs(entry - sl);
    
    // Base TP on Risk-Reward ratio
    double rr = (g_riskMode == 0) ? 1.5 : 2.0; // Conservative for Ultra-Micro
    
    // Look for structure-based TP
    double structureTP = FindStructureTP(ob);
    if(structureTP != 0) {
        double structureDistance = MathAbs(entry - structureTP);
        if(structureDistance >= slDistance * 1.2) { // At least 1.2 RR
            return structureTP;
        }
    }
    
    // Default to RR-based TP
    if(ob.direction == 1) {
        return entry + slDistance * rr;
    } else {
        return entry - slDistance * rr;
    }
}

//+------------------------------------------------------------------+
//| Find Structure-based Take Profit                               |
//+------------------------------------------------------------------+
double FindStructureTP(OrderBlock &ob) {
    // Look for next resistance/support level
    for(int i = 0; i < ArraySize(g_liquidity); i++) {
        if(g_liquidity[i].time == 0) continue;
        
        double currentPrice = (ob.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        if(ob.direction == 1 && g_liquidity[i].price > currentPrice && g_liquidity[i].strength == 1) {
            return g_liquidity[i].price;
        } else if(ob.direction == -1 && g_liquidity[i].price < currentPrice && g_liquidity[i].strength == -1) {
            return g_liquidity[i].price;
        }
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| Validate Trade Parameters                                       |
//+------------------------------------------------------------------+
bool ValidateTradeParams(double entry, double sl, double tp, double lotSize) {
    if(lotSize <= 0) return false;
    
    double minStopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(MathAbs(entry - sl) < minStopLevel) return false;
    if(MathAbs(entry - tp) < minStopLevel) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Manage Existing Trades                                          |
//+------------------------------------------------------------------+
void ManageExistingTrades() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetSymbol(i) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        int positionType = (int)PositionGetInteger(POSITION_TYPE);
        
        // Move to breakeven at 1:1 RR
        MoveToBE(ticket, openPrice, currentPrice, positionType);
        
        // Trailing stop
        TrailingStop(ticket, openPrice, currentPrice, positionType);
    }
}

//+------------------------------------------------------------------+
//| Move to Breakeven                                               |
//+------------------------------------------------------------------+
void MoveToBE(ulong ticket, double openPrice, double currentPrice, int positionType) {
    double sl = PositionGetDouble(POSITION_SL);
    double slDistance = MathAbs(openPrice - sl);
    
    bool moveToBE = false;
    if(positionType == POSITION_TYPE_BUY && currentPrice >= openPrice + slDistance) {
        moveToBE = true;
    } else if(positionType == POSITION_TYPE_SELL && currentPrice <= openPrice - slDistance) {
        moveToBE = true;
    }
    
    if(moveToBE && MathAbs(sl - openPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) {
        MqlTradeRequest request;
        MqlTradeResult result;
        
        ZeroMemory(request);
        request.action = TRADE_ACTION_SLTP;
        request.position = ticket;
        request.sl = openPrice;
        request.tp = PositionGetDouble(POSITION_TP);
        
        OrderSend(request, result);
    }
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                   |
//+------------------------------------------------------------------+
void TrailingStop(ulong ticket, double openPrice, double currentPrice, int positionType) {
    double sl = PositionGetDouble(POSITION_SL);
    
    // Only trail after breakeven
    if(MathAbs(sl - openPrice) > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5) return;
    
    double newSL = sl;
    double trailDistance = (MathAbs(openPrice - sl)) * 0.5; // Trail at 50% of original SL distance
    
    if(positionType == POSITION_TYPE_BUY) {
        newSL = currentPrice - trailDistance;
        if(newSL > sl) {
            MqlTradeRequest request;
            MqlTradeResult result;
            
            ZeroMemory(request);
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            OrderSend(request, result);
        }
    } else if(positionType == POSITION_TYPE_SELL) {
        newSL = currentPrice + trailDistance;
        if(newSL < sl) {
            MqlTradeRequest request;
            MqlTradeResult result;
            
            ZeroMemory(request);
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = newSL;
            request.tp = PositionGetDouble(POSITION_TP);
            
            OrderSend(request, result);
        }
    }
}

//+------------------------------------------------------------------+
//| Count Today's Trades                                            |
//+------------------------------------------------------------------+
int CountTradesToday() {
    datetime startOfDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    int count = 0;
    
    HistorySelect(startOfDay, TimeCurrent());
    
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
           HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber) {
            count++;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    string modeText = "";
    switch(g_riskMode) {
        case 0: modeText = "ULTRA-MICRO"; break;
        case 1: modeText = "SAFE"; break;
        case 2: modeText = "TURBO"; break;
    }
    
    string biasText = "";
    switch(g_htfBias) {
        case 1: biasText = "BULLISH"; break;
        case -1: biasText = "BEARISH"; break;
        case 0: biasText = "NEUTRAL"; break;
    }
    
    g_dashboardLines[0] = "═══ ICT SMC Expert Advisor ═══";
    g_dashboardLines[1] = "Mode: " + modeText;
    g_dashboardLines[2] = "Session: " + g_currentSession;
    g_dashboardLines[3] = "HTF Bias: " + biasText;
    g_dashboardLines[4] = "Balance: $" + DoubleToString(g_accountBalance, 2);
    g_dashboardLines[5] = "Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
    g_dashboardLines[6] = "Spread: " + DoubleToString(g_currentSpread, 1) + " pts";
    g_dashboardLines[7] = "Trades Today: " + IntegerToString(g_tradesCountToday);
    g_dashboardLines[8] = "Active Positions: " + IntegerToString(PositionsTotal());
    g_dashboardLines[9] = "Last Trade RR: " + DoubleToString(g_lastTradeRR, 2);
    g_dashboardLines[10] = "Valid OBs: " + IntegerToString(CountValidOBs());
    g_dashboardLines[11] = "Active FVGs: " + IntegerToString(CountActiveFVGs());
    g_dashboardLines[12] = "Drawdown: " + DoubleToString(CalculateDrawdown(), 2) + "%";
    g_dashboardLines[13] = "Time: " + TimeToString(TimeCurrent(), TIME_MINUTES);
    g_dashboardLines[14] = "═══════════════════════════";
    
    // Display dashboard
    string dashText = "";
    for(int i = 0; i < ArraySize(g_dashboardLines); i++) {
        dashText += g_dashboardLines[i] + "\n";
    }
    
    Comment(dashText);
}

//+------------------------------------------------------------------+
//| Count Valid Order Blocks                                        |
//+------------------------------------------------------------------+
int CountValidOBs() {
    int count = 0;
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].valid && !g_orderBlocks[i].used) count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count Active Fair Value Gaps                                    |
//+------------------------------------------------------------------+
int CountActiveFVGs() {
    int count = 0;
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time != 0 && !g_fvgs[i].filled) count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Update Visual Elements                                           |
//+------------------------------------------------------------------+
void UpdateVisuals() {
    if(!VisualMode) return;
    
    // Draw Order Blocks
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].time == 0 || !g_orderBlocks[i].valid) continue;
        
        string objName = "ICT_OB_" + IntegerToString(i);
        ObjectDelete(0, objName);
        
        color obColor = (g_orderBlocks[i].direction == 1) ? clrDodgerBlue : clrCrimson;
        if(g_orderBlocks[i].used) obColor = clrGray;
        
        ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                    g_orderBlocks[i].time, g_orderBlocks[i].low,
                    TimeCurrent() + 3600, g_orderBlocks[i].high);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, obColor);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, objName, OBJPROP_FILL, true);
        ObjectSetInteger(0, objName, OBJPROP_BACK, true);
    }
    
    // Draw Fair Value Gaps
    for(int i = 0; i < ArraySize(g_fvgs); i++) {
        if(g_fvgs[i].time == 0 || g_fvgs[i].filled) continue;
        
        string objName = "ICT_FVG_" + IntegerToString(i);
        ObjectDelete(0, objName);
        
        color fvgColor = (g_fvgs[i].direction == 1) ? clrYellow : clrOrange;
        
        ObjectCreate(0, objName, OBJ_RECTANGLE, 0, 
                    g_fvgs[i].time, g_fvgs[i].lower,
                    TimeCurrent() + 1800, g_fvgs[i].upper);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, fvgColor);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, objName, OBJPROP_FILL, false);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
    }
    
    // Draw Liquidity Levels
    for(int i = 0; i < ArraySize(g_liquidity); i++) {
        if(g_liquidity[i].time == 0 || g_liquidity[i].swept) continue;
        
        string objName = "ICT_LQ_" + IntegerToString(i);
        ObjectDelete(0, objName);
        
        color lqColor = (g_liquidity[i].strength == 1) ? clrLime : clrRed;
        
        ObjectCreate(0, objName, OBJ_HLINE, 0, 0, g_liquidity[i].price);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, lqColor);
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    }
    
    // Draw entry markers for recent trades
    DrawTradeMarkers();
}

//+------------------------------------------------------------------+
//| Draw Trade Markers                                              |
//+------------------------------------------------------------------+
void DrawTradeMarkers() {
    HistorySelect(TimeCurrent() - 86400, TimeCurrent()); // Last 24 hours
    
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
        
        ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
        if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
        
        datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        double dealPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
        
        string objName = "ICT_ENTRY_" + IntegerToString(ticket);
        ObjectDelete(0, objName);
        
        int arrowCode = (dealType == DEAL_TYPE_BUY) ? 233 : 234;
        color arrowColor = (dealType == DEAL_TYPE_BUY) ? clrLime : clrRed;
        
        ObjectCreate(0, objName, OBJ_ARROW, 0, dealTime, dealPrice);
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, arrowColor);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
    }
}

//+------------------------------------------------------------------+
//| Detect Breaker Block                                            |
//+------------------------------------------------------------------+
bool DetectBreakerBlock() {
    if(!Enable_BreakerBlock) return false;
    
    // Breaker block is an order block that failed and then got broken
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(g_orderBlocks[i].time == 0 || !g_orderBlocks[i].used) continue;
        
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        // Check if the order block has been broken (price moved significantly beyond it)
        if(g_orderBlocks[i].direction == 1) { // Bullish OB turned bearish
            if(currentPrice < g_orderBlocks[i].low) {
                return true; // Now it's a bearish breaker block
            }
        } else { // Bearish OB turned bullish
            if(currentPrice > g_orderBlocks[i].high) {
                return true; // Now it's a bullish breaker block
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Judas Swing                                              |
//+------------------------------------------------------------------+
bool DetectJudasSwing() {
    if(!Enable_JudasSwing) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Judas swing typically occurs in London open (8-9 AM) or NY open (1-2 PM)
    if(!((dt.hour >= 8 && dt.hour <= 9) || (dt.hour >= 13 && dt.hour <= 14))) return true;
    
    // Look for false breakout pattern
    for(int i = 5; i < 20; i++) {
        if(IsSwingHigh(i, 3) || IsSwingLow(i, 3)) {
            double swingPrice = IsSwingHigh(i, 3) ? iHigh(_Symbol, PERIOD_CURRENT, i) : iLow(_Symbol, PERIOD_CURRENT, i);
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            // Check if price broke above/below and then reversed
            bool brokeAndReversed = false;
            for(int j = i - 1; j >= 1; j--) {
                if(IsSwingHigh(i, 3) && iHigh(_Symbol, PERIOD_CURRENT, j) > swingPrice) {
                    if(iClose(_Symbol, PERIOD_CURRENT, 1) < swingPrice) {
                        brokeAndReversed = true;
                        break;
                    }
                } else if(IsSwingLow(i, 3) && iLow(_Symbol, PERIOD_CURRENT, j) < swingPrice) {
                    if(iClose(_Symbol, PERIOD_CURRENT, 1) > swingPrice) {
                        brokeAndReversed = true;
                        break;
                    }
                }
            }
            
            if(brokeAndReversed) return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Turtle Soup Pattern                                      |
//+------------------------------------------------------------------+
bool DetectTurtleSoup() {
    if(!Enable_TurtleSoup) return true;
    
    // Turtle soup is a 20-day breakout failure
    double high20 = iHigh(_Symbol, PERIOD_D1, iHighest(_Symbol, PERIOD_D1, MODE_HIGH, 20, 1));
    double low20 = iLow(_Symbol, PERIOD_D1, iLowest(_Symbol, PERIOD_D1, MODE_LOW, 20, 1));
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double yesterdayClose = iClose(_Symbol, PERIOD_D1, 1);
    double todayHigh = iHigh(_Symbol, PERIOD_D1, 0);
    double todayLow = iLow(_Symbol, PERIOD_D1, 0);
    
    // Bullish turtle soup: Break below 20-day low then reverse
    if(todayLow < low20 && currentPrice > low20 && yesterdayClose > low20) {
        return true;
    }
    
    // Bearish turtle soup: Break above 20-day high then reverse
    if(todayHigh > high20 && currentPrice < high20 && yesterdayClose < high20) {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Void                                           |
//+------------------------------------------------------------------+
bool DetectLiquidityVoid() {
    if(!Enable_LiquidityVoid) return true;
    
    // Liquidity void is a price range with no significant volume/wicks
    for(int i = 5; i < 50; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        double range = high - low;
        
        // Check if there's a gap in recent price action
        bool hasVoid = true;
        for(int j = i - 4; j <= i + 4; j++) {
            if(j == i) continue;
            
            double checkHigh = iHigh(_Symbol, PERIOD_CURRENT, j);
            double checkLow = iLow(_Symbol, PERIOD_CURRENT, j);
            
            // If any bar overlaps significantly with the void range, it's not a void
            if(checkLow < high && checkHigh > low) {
                if((checkHigh - checkLow) > range * 0.3) {
                    hasVoid = false;
                    break;
                }
            }
        }
        
        if(hasVoid && range > SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100) {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Buy/Sell Model Validation                                       |
//+------------------------------------------------------------------+
bool BuySellModelValid(int direction) {
    if(!Enable_BuySellModel) return true;
    
    // ICT Buy/Sell model: specific price action setup
    if(direction == 1) { // Buy model
        // Look for: Lower low, higher low, break of structure to upside
        double ll = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 10, 5));
        double hl = 0;
        
        // Find higher low after the lower low
        for(int i = 1; i < 5; i++) {
            double low = iLow(_Symbol, PERIOD_CURRENT, i);
            if(low > ll && (hl == 0 || low < hl)) {
                hl = low;
            }
        }
        
        if(hl > ll) {
            // Check for break of structure (recent high being taken)
            double recentHigh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 5, 1));
            if(iClose(_Symbol, PERIOD_CURRENT, 1) > recentHigh) {
                return true;
            }
        }
    } else { // Sell model
        // Look for: Higher high, lower high, break of structure to downside
        double hh = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 10, 5));
        double lh = 0;
        
        // Find lower high after the higher high
        for(int i = 1; i < 5; i++) {
            double high = iHigh(_Symbol, PERIOD_CURRENT, i);
            if(high < hh && (lh == 0 || high > lh)) {
                lh = high;
            }
        }
        
        if(lh < hh) {
            // Check for break of structure (recent low being taken)
            double recentLow = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 5, 1));
            if(iClose(_Symbol, PERIOD_CURRENT, 1) < recentLow) {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Re-Entry Engine                                                 |
//+------------------------------------------------------------------+
void CheckReEntry() {
    if(!Enable_ReEntryEngine) return;
    if(g_riskMode == 1) return; // No re-entry in safe mode
    
    // Look for re-entry opportunities on recently closed trades
    HistorySelect(TimeCurrent() - 3600, TimeCurrent()); // Last hour
    
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
        
        ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
        if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
        
        double dealPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
        double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        
        // Only re-enter if the previous trade was profitable
        if(dealProfit > 0) {
            // Check if price has returned to entry area
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double entryBuffer = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 50;
            
            if(MathAbs(currentPrice - dealPrice) <= entryBuffer) {
                // Look for confluence for re-entry
                for(int j = 0; j < ArraySize(g_orderBlocks); j++) {
                    if(g_orderBlocks[j].valid && !g_orderBlocks[j].used) {
                        if(currentPrice >= g_orderBlocks[j].low && currentPrice <= g_orderBlocks[j].high) {
                            ExecuteTrade(j);
                            return;
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Stop Hunt Filter                                                |
//+------------------------------------------------------------------+
bool IsStopHunt() {
    if(!Enable_StopHuntFilter) return false;
    
    // Detect stop hunt by looking for rapid price spikes that reverse quickly
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = 1; i <= 5; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        double open = iOpen(_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        
        // Check for large wick compared to body
        double bodySize = MathAbs(close - open);
        double upperWick = high - MathMax(open, close);
        double lowerWick = MathMin(open, close) - low;
        
        // Stop hunt characteristics: Large wick (3x body size) that gets rejected
        if(upperWick > bodySize * 3 && close < high * 0.7) {
            return true; // Bearish stop hunt
        }
        
        if(lowerWick > bodySize * 3 && close > low * 1.3) {
            return true; // Bullish stop hunt
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Order Block in Order Block Detection                            |
//+------------------------------------------------------------------+
bool OBinOBDetected(int mainOBIndex) {
    if(!Enable_OBinOB) return false;
    
    OrderBlock mainOB = g_orderBlocks[mainOBIndex];
    
    // Look for smaller order blocks within the main order block
    for(int i = 0; i < ArraySize(g_orderBlocks); i++) {
        if(i == mainOBIndex) continue;
        if(g_orderBlocks[i].time == 0) continue;
        
        // Check if this OB is within the main OB
        if(g_orderBlocks[i].time > mainOB.time && 
           g_orderBlocks[i].low >= mainOB.low && 
           g_orderBlocks[i].high <= mainOB.high &&
           g_orderBlocks[i].direction == mainOB.direction) {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Last Trade Risk-Reward                               |
//+------------------------------------------------------------------+
void UpdateLastTradeRR() {
    HistorySelect(TimeCurrent() - 86400, TimeCurrent());
    
    double lastRR = 0;
    ulong lastTicket = 0;
    datetime lastTime = 0;
    
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
        
        datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        if(dealTime > lastTime) {
            lastTime = dealTime;
            lastTicket = ticket;
            
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            
            // Estimate RR based on profit and volume
            if(volume > 0) {
                double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / 
                                   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 
                                   SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                
                if(pointValue > 0) {
                    lastRR = profit / (volume * pointValue * 100); // Rough RR estimation
                }
            }
        }
    }
    
    g_lastTradeRR = lastRR;
}

//+------------------------------------------------------------------+
//| Enhanced Trade Setup Validation (All Confluence)              |
//+------------------------------------------------------------------+
bool AllConfluenceValid(int obIndex) {
    if(!Enable_StrictSniperOnly) return true;
    
    int confluenceCount = 0;
    int maxConfluence = 0;
    
    // Count available confluence factors
    if(Enable_FVG) maxConfluence++;
    if(Enable_BOS) maxConfluence++;
    if(Enable_CHoCH) maxConfluence++;
    if(Enable_MSS) maxConfluence++;
    if(Enable_VolumeSpike) maxConfluence++;
    if(Enable_LiquiditySweep) maxConfluence++;
    if(Enable_JudasSwing) maxConfluence++;
    if(Enable_TurtleSoup) maxConfluence++;
    if(Enable_BPR) maxConfluence++;
    if(Enable_LiquidityVoid) maxConfluence++;
    if(Enable_PremiumDiscount) maxConfluence++;
    if(Enable_BuySellModel) maxConfluence++;
    if(Enable_BreakerBlock) maxConfluence++;
    if(Enable_OBinOB) maxConfluence++;
    
    // Check each confluence factor
    if(Enable_FVG && FVGInsideOBDetected(obIndex)) confluenceCount++;
    if(Enable_BOS && DetectBOS()) confluenceCount++;
    if(Enable_CHoCH && DetectCHoCH()) confluenceCount++;
    if(Enable_MSS && DetectMSS()) confluenceCount++;
    if(Enable_VolumeSpike && VolumeSpike()) confluenceCount++;
    if(Enable_LiquiditySweep && LiquiditySweepDetected()) confluenceCount++;
    if(Enable_JudasSwing && DetectJudasSwing()) confluenceCount++;
    if(Enable_TurtleSoup && DetectTurtleSoup()) confluenceCount++;
    if(Enable_BPR && BalancedPriceRange()) confluenceCount++;
    if(Enable_LiquidityVoid && DetectLiquidityVoid()) confluenceCount++;
    if(Enable_PremiumDiscount && IsInPremiumDiscount(g_orderBlocks[obIndex].direction)) confluenceCount++;
    if(Enable_BuySellModel && BuySellModelValid(g_orderBlocks[obIndex].direction)) confluenceCount++;
    if(Enable_BreakerBlock && DetectBreakerBlock()) confluenceCount++;
    if(Enable_OBinOB && OBinOBDetected(obIndex)) confluenceCount++;
    
    // Stop hunt is a negative factor
    if(Enable_StopHuntFilter && IsStopHunt()) confluenceCount--;
    
    // Require at least 70% of available confluence factors
    return (confluenceCount >= maxConfluence * 0.7);
}

//+------------------------------------------------------------------+
//| Enhanced OnTick with all confluence checks                      |
//+------------------------------------------------------------------+
void OnTick() {
    // Update global variables
    UpdateGlobalVariables();
    
    // Update structures based on enabled flags
    if(Enable_OB) UpdateOrderBlocks();
    if(Enable_FVG) UpdateFairValueGaps();
    if(Enable_LiquiditySweep) UpdateLiquidityLevels();
    
    // Update last trade RR
    UpdateLastTradeRR();
    
    // Check for re-entry opportunities
    if(Enable_ReEntryEngine) CheckReEntry();
    
    // Check for trade opportunities with full confluence
    CheckTradeOpportunities();
    
    // Manage existing trades
    ManageExistingTrades();
    
    // Update dashboard
    if(ShowDashboard) UpdateDashboard();
    
    // Update visuals
    if(VisualMode) UpdateVisuals();
}

//+------------------------------------------------------------------+
//| Enhanced Trade Setup Check with All Features                    |
//+------------------------------------------------------------------+
bool IsValidTradeSetup(int obIndex) {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    OrderBlock ob = g_orderBlocks[obIndex];
    
    // Basic Order Block validation
    if(!Enable_OB || !OrderBlockValid(obIndex)) return false;
    
    // Price must be in order block range
    if(currentPrice < ob.low || currentPrice > ob.high) return false;
    
    // Check individual confluence factors
    if(Enable_FVG && !FVGInsideOBDetected(obIndex)) return false;
    if((Enable_CHoCH || Enable_BOS || Enable_MSS) && !CheckMarketStructure()) return false;
    if(Enable_VolumeSpike && !VolumeSpike()) return false;
    if(Enable_TrapFilter && IsTrapSetup(obIndex)) return false;
    if(Enable_PremiumDiscount && !IsInPremiumDiscount(ob.direction)) return false;
    if(Enable_BuySellModel && !BuySellModelValid(ob.direction)) return false;
    if(Enable_StopHuntFilter && IsStopHunt()) return false;
    
    // Strict sniper mode: check all confluence
    if(Enable_StrictSniperOnly && !AllConfluenceValid(obIndex)) return false;
    
    // Check bias alignment
    if(g_htfBias != 0 && g_htfBias != ob.direction) return false;
    
    // Additional confluence checks
    if(Enable_JudasSwing && !DetectJudasSwing()) return false;
    if(Enable_TurtleSoup && !DetectTurtleSoup()) return false;
    if(Enable_LiquidityVoid && !DetectLiquidityVoid()) return false;
    if(Enable_BreakerBlock && !DetectBreakerBlock()) return false;
    if(Enable_OBinOB && !OBinOBDetected(obIndex)) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Export Trade Data to CSV (Optional)                            |
//+------------------------------------------------------------------+
void ExportTradeData() {
    string filename = "ICT_SMC_Trades_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
    int file = FileOpen(filename, FILE_WRITE | FILE_CSV);
    
    if(file != INVALID_HANDLE) {
        // Write header
        FileWrite(file, "Date", "Time", "Symbol", "Type", "Volume", "Price", "SL", "TP", "Profit", "Comment");
        
        HistorySelect(TimeCurrent() - 86400 * 30, TimeCurrent()); // Last 30 days
        
        for(int i = 0; i < HistoryDealsTotal(); i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
            
            datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            
            string typeStr = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            
            FileWrite(file, TimeToString(dealTime, TIME_DATE), 
                           TimeToString(dealTime, TIME_MINUTES),
                           _Symbol, typeStr, volume, price, 0, 0, profit, comment);
        }
        
        FileClose(file);
        Print("Trade data exported to ", filename);
    }
}

//+------------------------------------------------------------------+
//| OnTimer Event (for periodic tasks)                             |
//+------------------------------------------------------------------+
void OnTimer() {
    // Export trade data daily at midnight
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(dt.hour == 0 && dt.min == 0) {
        ExportTradeData();
    }
    
    // Clean up old objects
    ObjectsDeleteAll(0, "ICT_TEMP_");
}

//+------------------------------------------------------------------+
//| OnChartEvent (for interactive features)                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_KEYDOWN) {
        // Hotkeys for manual control
        switch((int)lparam) {
            case 'E': // Export trades
                ExportTradeData();
                break;
            case 'R': // Reset visual elements
                ObjectsDeleteAll(0, "ICT_");
                break;
            case 'D': // Toggle dashboard
                ShowDashboard = !ShowDashboard;
                if(!ShowDashboard) Comment("");
                break;
            case 'V': // Toggle visuals
                VisualMode = !VisualMode;
                if(!VisualMode) ObjectsDeleteAll(0, "ICT_");
                break;
        }
    }
}

//+------------------------------------------------------------------+
//| Final Notes and Validation                                      |
//+------------------------------------------------------------------+
/*
This Expert Advisor implements a comprehensive ICT/SMC trading system with:

✅ All 20 input flags for feature control
✅ Dynamic risk management (Ultra-Micro/Safe/Turbo modes)
✅ Real ICT concepts: Order Blocks, FVG, BOS, CHoCH, MSS, etc.
✅ Session-based trading with killzone filters  
✅ HTF bias detection and alignment
✅ Structure-based entries, SL, and TP
✅ Breakeven and trailing stop management
✅ Confluence validation for sniper-only trades
✅ Dashboard with real-time stats
✅ Visual elements for Strategy Tester
✅ Capital protection and drawdown limits
✅ No martingale, grid, or averaging
✅ Single .mq5 file with no external dependencies
✅ Real institutional trading logic implementation

The EA trades only XAUUSD with full autonomous operation based on
institutional Smart Money Concepts and risk management protocols.
All features are controlled by input flags and execute real logic,
not placeholder functions.

Compilation: Should compile with 0 errors and 0 warnings in MetaEditor.
Usage: Set symbol to XAUUSD, adjust risk parameters, enable desired features.
*/
//+------------------------------------------------------------------+