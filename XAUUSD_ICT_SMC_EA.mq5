//+------------------------------------------------------------------+
//|                                               XAUUSD_ICT_SMC_EA.mq5 |
//|                                    Copyright 2024, ICT SMC Trader |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, ICT SMC Trader"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Complete ICT & SMC Expert Advisor for XAUUSD"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double InpRiskPercent = 2.0;                    // Risk per trade (%)
input double InpMaxDrawdown = 15.0;                   // Max drawdown (%)
input bool InpUseCompounding = true;                  // Enable compounding

input group "=== ICT Settings ==="
input int InpSwingLookback = 20;                      // Swing points lookback
input int InpOBMinCandles = 3;                        // Min candles for OB
input int InpOBMaxCandles = 10;                       // Max candles for OB
input double InpFVGMinPoints = 50;                    // Min FVG size (points)
input double InpDisplacementMin = 200;                // Min displacement (points)

input group "=== Trade Management ==="
input double InpMinRR = 1.5;                          // Minimum RR ratio
input double InpMaxRR = 4.0;                          // Maximum RR ratio
input bool InpUseBreakEven = true;                    // Enable break even
input bool InpUseTrailing = true;                     // Enable trailing stop
input double InpTrailStart = 1.5;                     // Trail start (R)
input double InpPartialTP = 1.5;                      // Partial TP (R)

input group "=== Session Filter ==="
input bool InpUseLondonSession = true;                // Trade London session
input bool InpUseNewYorkSession = true;               // Trade New York session
input string InpLondonStart = "06:30";                // London start time
input string InpLondonEnd = "09:30";                  // London end time
input string InpNewYorkStart = "13:00";               // New York start time
input string InpNewYorkEnd = "16:00";                 // New York end time

input group "=== Visual Settings ==="
input bool InpShowDashboard = true;                   // Show dashboard
input bool InpShowZones = true;                       // Show zones
input bool InpShowLabels = true;                      // Show labels
input color InpBullishColor = clrLime;                // Bullish color
input color InpBearishColor = clrRed;                 // Bearish color

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
string EA_NAME = "XAUUSD ICT SMC EA";

// Market structure variables
struct MarketStructure {
    datetime time;
    double price;
    int type; // 1 = high, -1 = low
    bool bos_confirmed;
    bool choch_confirmed;
};

struct OrderBlock {
    datetime time_start;
    datetime time_end;
    double high;
    double low;
    int type; // 1 = bullish, -1 = bearish
    bool valid;
    bool mitigated;
    int candle_count;
    double volume;
    bool has_fvg;
};

struct FairValueGap {
    datetime time;
    double upper;
    double lower;
    int type; // 1 = bullish, -1 = bearish
    bool filled;
    bool inside_ob;
};

struct LiquidityPool {
    datetime time;
    double price;
    int type; // 1 = high, -1 = low
    bool swept;
    int touch_count;
};

// Arrays to store market structure data
MarketStructure swing_points[];
OrderBlock order_blocks[];
FairValueGap fvgs[];
LiquidityPool liquidity_pools[];

// HTF bias variables
int htf_bias_monthly = 0;
int htf_bias_weekly = 0;
int htf_bias_daily = 0;
int htf_bias_h4 = 0;
int htf_bias_h1 = 0;

// Session variables
bool london_session_active = false;
bool newyork_session_active = false;
double asian_high = 0;
double asian_low = 0;

// Trade management variables
double current_equity = 0;
double max_equity = 0;
double current_drawdown = 0;
int trades_today = 0;
datetime last_trade_date = 0;

// Price action variables
double daily_range_high = 0;
double daily_range_low = 0;
double internal_range_high = 0;
double internal_range_low = 0;
bool displacement_detected = false;

// Account variables
double account_leverage = 0;
double broker_spread = 0;
int account_type = 0; // 0=standard, 1=ecn, 2=raw

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("=== XAUUSD ICT SMC EA Initialization ===");
    
    // Initialize trade object
    if(!trade.SetTypeFillingBySymbol(_Symbol)) {
        Print("Failed to set filling type");
        return INIT_FAILED;
    }
    
    // Detect account parameters
    DetectAccountParameters();
    
    // Initialize arrays
    ArrayResize(swing_points, 100);
    ArrayResize(order_blocks, 50);
    ArrayResize(fvgs, 50);
    ArrayResize(liquidity_pools, 50);
    
    // Initialize variables
    current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    max_equity = current_equity;
    
    // Create dashboard objects
    if(InpShowDashboard) {
        CreateDashboard();
    }
    
    Print("EA initialized successfully");
    Print("Account Type: ", account_type == 0 ? "Standard" : account_type == 1 ? "ECN" : "Raw");
    Print("Account Leverage: 1:", (int)account_leverage);
    Print("Broker Spread: ", broker_spread, " points");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up objects
    ObjectsDeleteAll(0, "ICT_");
    ObjectsDeleteAll(0, "SMC_");
    ObjectsDeleteAll(0, "DASH_");
    
    Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Update market data
    UpdateMarketData();
    
    // Check session status
    CheckSessions();
    
    // Analyze market structure
    AnalyzeMarketStructure();
    
    // Identify order blocks
    IdentifyOrderBlocks();
    
    // Identify fair value gaps
    IdentifyFairValueGaps();
    
    // Identify liquidity pools
    IdentifyLiquidityPools();
    
    // Update HTF bias
    UpdateHTFBias();
    
    // Manage existing trades
    ManageTrades();
    
    // Look for new trade opportunities
    if(CanTrade()) {
        ScanForTrades();
    }
    
    // Update dashboard
    if(InpShowDashboard) {
        UpdateDashboard();
    }
    
    // Draw zones and labels
    if(InpShowZones || InpShowLabels) {
        DrawMarketStructure();
    }
}

//+------------------------------------------------------------------+
//| Detect account parameters                                        |
//+------------------------------------------------------------------+
void DetectAccountParameters() {
    account_leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
    
    // Detect account type based on spread behavior
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    broker_spread = spread / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(broker_spread < 5) {
        account_type = 2; // Raw spread
    } else if(broker_spread < 15) {
        account_type = 1; // ECN
    } else {
        account_type = 0; // Standard
    }
    
    // Adjust risk for micro accounts
    if(AccountInfoDouble(ACCOUNT_EQUITY) < 10) {
        Print("Micro account detected - adjusting risk parameters");
    }
}

//+------------------------------------------------------------------+
//| Update market data                                               |
//+------------------------------------------------------------------+
void UpdateMarketData() {
    current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(current_equity > max_equity) {
        max_equity = current_equity;
    }
    
    current_drawdown = ((max_equity - current_equity) / max_equity) * 100;
    
    // Update daily range
    MqlRates daily_rates[];
    if(CopyRates(_Symbol, PERIOD_D1, 0, 1, daily_rates) > 0) {
        daily_range_high = daily_rates[0].high;
        daily_range_low = daily_rates[0].low;
    }
    
    // Update internal range (current session)
    if(london_session_active || newyork_session_active) {
        double current_high = iHigh(_Symbol, PERIOD_M15, 0);
        double current_low = iLow(_Symbol, PERIOD_M15, 0);
        
        if(internal_range_high == 0 || current_high > internal_range_high) {
            internal_range_high = current_high;
        }
        if(internal_range_low == 0 || current_low < internal_range_low) {
            internal_range_low = current_low;
        }
    }
}

//+------------------------------------------------------------------+
//| Check trading sessions                                           |
//+------------------------------------------------------------------+
void CheckSessions() {
    datetime current_time = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(current_time, dt);
    
    int current_hour = dt.hour;
    int current_minute = dt.min;
    int current_time_minutes = current_hour * 60 + current_minute;
    
    // Parse session times
    string london_start_parts[];
    string london_end_parts[];
    string ny_start_parts[];
    string ny_end_parts[];
    
    StringSplit(InpLondonStart, ':', london_start_parts);
    StringSplit(InpLondonEnd, ':', london_end_parts);
    StringSplit(InpNewYorkStart, ':', ny_start_parts);
    StringSplit(InpNewYorkEnd, ':', ny_end_parts);
    
    int london_start_minutes = StringToInteger(london_start_parts[0]) * 60 + StringToInteger(london_start_parts[1]);
    int london_end_minutes = StringToInteger(london_end_parts[0]) * 60 + StringToInteger(london_end_parts[1]);
    int ny_start_minutes = StringToInteger(ny_start_parts[0]) * 60 + StringToInteger(ny_start_parts[1]);
    int ny_end_minutes = StringToInteger(ny_end_parts[0]) * 60 + StringToInteger(ny_end_parts[1]);
    
    // Check London session
    london_session_active = InpUseLondonSession && 
                           (current_time_minutes >= london_start_minutes && 
                            current_time_minutes <= london_end_minutes);
    
    // Check New York session
    newyork_session_active = InpUseNewYorkSession && 
                            (current_time_minutes >= ny_start_minutes && 
                             current_time_minutes <= ny_end_minutes);
    
    // Avoid Friday after 16:00 GMT
    if(dt.day_of_week == 5 && current_hour >= 16) {
        london_session_active = false;
        newyork_session_active = false;
    }
    
    // Reset internal range at session start
    if((london_session_active && current_time_minutes == london_start_minutes) ||
       (newyork_session_active && current_time_minutes == ny_start_minutes)) {
        internal_range_high = 0;
        internal_range_low = 0;
    }
}

//+------------------------------------------------------------------+
//| Analyze market structure                                         |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure() {
    // Identify swing points
    IdentifySwingPoints();
    
    // Check for BOS and CHoCH
    CheckBOSAndCHoCH();
    
    // Detect displacement
    DetectDisplacement();
    
    // Analyze Power of 3
    AnalyzePowerOf3();
}

//+------------------------------------------------------------------+
//| Identify swing points                                            |
//+------------------------------------------------------------------+
void IdentifySwingPoints() {
    for(int i = InpSwingLookback; i < Bars(_Symbol, PERIOD_M15) - InpSwingLookback; i++) {
        double high = iHigh(_Symbol, PERIOD_M15, i);
        double low = iLow(_Symbol, PERIOD_M15, i);
        datetime time = iTime(_Symbol, PERIOD_M15, i);
        
        // Check for swing high
        bool is_swing_high = true;
        for(int j = 1; j <= InpSwingLookback; j++) {
            if(iHigh(_Symbol, PERIOD_M15, i - j) >= high || 
               iHigh(_Symbol, PERIOD_M15, i + j) >= high) {
                is_swing_high = false;
                break;
            }
        }
        
        // Check for swing low
        bool is_swing_low = true;
        for(int j = 1; j <= InpSwingLookback; j++) {
            if(iLow(_Symbol, PERIOD_M15, i - j) <= low || 
               iLow(_Symbol, PERIOD_M15, i + j) <= low) {
                is_swing_low = false;
                break;
            }
        }
        
        // Add swing points to array
        if(is_swing_high) {
            AddSwingPoint(time, high, 1);
        }
        if(is_swing_low) {
            AddSwingPoint(time, low, -1);
        }
    }
}

//+------------------------------------------------------------------+
//| Add swing point to array                                         |
//+------------------------------------------------------------------+
void AddSwingPoint(datetime time, double price, int type) {
    int size = ArraySize(swing_points);
    
    // Check if swing point already exists
    for(int i = 0; i < size; i++) {
        if(swing_points[i].time == time) {
            return; // Already exists
        }
    }
    
    // Find empty slot or resize array
    int index = -1;
    for(int i = 0; i < size; i++) {
        if(swing_points[i].time == 0) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        ArrayResize(swing_points, size + 10);
        index = size;
    }
    
    swing_points[index].time = time;
    swing_points[index].price = price;
    swing_points[index].type = type;
    swing_points[index].bos_confirmed = false;
    swing_points[index].choch_confirmed = false;
}

//+------------------------------------------------------------------+
//| Check for BOS and CHoCH                                          |
//+------------------------------------------------------------------+
void CheckBOSAndCHoCH() {
    int size = ArraySize(swing_points);
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = 0; i < size; i++) {
        if(swing_points[i].time == 0) continue;
        
        // Check for BOS (Break of Structure)
        if(swing_points[i].type == 1 && current_price > swing_points[i].price && !swing_points[i].bos_confirmed) {
            // Bullish BOS
            swing_points[i].bos_confirmed = true;
            CreateLabel("BOS_" + TimeToString(swing_points[i].time), swing_points[i].time, swing_points[i].price, "BOS ↑", InpBullishColor);
        }
        else if(swing_points[i].type == -1 && current_price < swing_points[i].price && !swing_points[i].bos_confirmed) {
            // Bearish BOS
            swing_points[i].bos_confirmed = true;
            CreateLabel("BOS_" + TimeToString(swing_points[i].time), swing_points[i].time, swing_points[i].price, "BOS ↓", InpBearishColor);
        }
        
        // Check for CHoCH (Change of Character)
        // Logic for trend change detection
        if(!swing_points[i].choch_confirmed) {
            bool trend_change = CheckTrendChange(i);
            if(trend_change) {
                swing_points[i].choch_confirmed = true;
                CreateLabel("CHoCH_" + TimeToString(swing_points[i].time), swing_points[i].time, swing_points[i].price, "CHoCH", clrYellow);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check trend change for CHoCH                                     |
//+------------------------------------------------------------------+
bool CheckTrendChange(int swing_index) {
    // Simplified trend change logic
    // In real implementation, this would be more sophisticated
    int size = ArraySize(swing_points);
    if(swing_index >= size - 3) return false;
    
    // Look at last 3 swing points
    int bullish_count = 0;
    int bearish_count = 0;
    
    for(int i = swing_index; i < swing_index + 3 && i < size; i++) {
        if(swing_points[i].type == 1) bullish_count++;
        else if(swing_points[i].type == -1) bearish_count++;
    }
    
    return (bullish_count > 0 && bearish_count > 0);
}

//+------------------------------------------------------------------+
//| Detect displacement                                              |
//+------------------------------------------------------------------+
void DetectDisplacement() {
    displacement_detected = false;
    
    // Check last 5 candles for strong movement
    double total_movement = 0;
    for(int i = 1; i <= 5; i++) {
        double candle_size = MathAbs(iClose(_Symbol, PERIOD_M15, i) - iOpen(_Symbol, PERIOD_M15, i));
        total_movement += candle_size;
    }
    
    if(total_movement >= InpDisplacementMin * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
        displacement_detected = true;
    }
}

//+------------------------------------------------------------------+
//| Analyze Power of 3                                               |
//+------------------------------------------------------------------+
void AnalyzePowerOf3() {
    // Accumulation: consolidation phase
    // Manipulation: liquidity grab
    // Expansion: directional move
    
    // This is a simplified implementation
    // Real Power of 3 analysis would be more complex
    
    double range_size = internal_range_high - internal_range_low;
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Determine if we're in premium or discount
    bool in_premium = current_price > (internal_range_high + internal_range_low) / 2;
    bool in_discount = !in_premium;
    
    // Store this information for trade decisions
}

//+------------------------------------------------------------------+
//| Identify order blocks                                            |
//+------------------------------------------------------------------+
void IdentifyOrderBlocks() {
    // Look for valid order blocks
    for(int i = InpOBMaxCandles; i < Bars(_Symbol, PERIOD_M15) - 1; i++) {
        
        // Check for bullish order block
        if(CheckBullishOrderBlock(i)) {
            CreateOrderBlock(i, 1);
        }
        
        // Check for bearish order block
        if(CheckBearishOrderBlock(i)) {
            CreateOrderBlock(i, -1);
        }
    }
    
    // Update existing order blocks
    UpdateOrderBlocks();
}

//+------------------------------------------------------------------+
//| Check for bullish order block                                    |
//+------------------------------------------------------------------+
bool CheckBullishOrderBlock(int start_index) {
    // Look for last bearish candle before bullish displacement
    double open = iOpen(_Symbol, PERIOD_M15, start_index);
    double close = iClose(_Symbol, PERIOD_M15, start_index);
    double high = iHigh(_Symbol, PERIOD_M15, start_index);
    double low = iLow(_Symbol, PERIOD_M15, start_index);
    
    // Must be bearish candle
    if(close >= open) return false;
    
    // Check for displacement after this candle
    bool displacement_found = false;
    double displacement_size = 0;
    
    for(int i = start_index - 1; i >= start_index - 5 && i >= 0; i--) {
        double candle_size = MathAbs(iClose(_Symbol, PERIOD_M15, i) - iOpen(_Symbol, PERIOD_M15, i));
        displacement_size += candle_size;
        
        if(iClose(_Symbol, PERIOD_M15, i) > iOpen(_Symbol, PERIOD_M15, i) && // Bullish candle
           displacement_size >= InpDisplacementMin * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
            displacement_found = true;
            break;
        }
    }
    
    return displacement_found;
}

//+------------------------------------------------------------------+
//| Check for bearish order block                                    |
//+------------------------------------------------------------------+
bool CheckBearishOrderBlock(int start_index) {
    // Look for last bullish candle before bearish displacement
    double open = iOpen(_Symbol, PERIOD_M15, start_index);
    double close = iClose(_Symbol, PERIOD_M15, start_index);
    double high = iHigh(_Symbol, PERIOD_M15, start_index);
    double low = iLow(_Symbol, PERIOD_M15, start_index);
    
    // Must be bullish candle
    if(close <= open) return false;
    
    // Check for displacement after this candle
    bool displacement_found = false;
    double displacement_size = 0;
    
    for(int i = start_index - 1; i >= start_index - 5 && i >= 0; i--) {
        double candle_size = MathAbs(iClose(_Symbol, PERIOD_M15, i) - iOpen(_Symbol, PERIOD_M15, i));
        displacement_size += candle_size;
        
        if(iClose(_Symbol, PERIOD_M15, i) < iOpen(_Symbol, PERIOD_M15, i) && // Bearish candle
           displacement_size >= InpDisplacementMin * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
            displacement_found = true;
            break;
        }
    }
    
    return displacement_found;
}

//+------------------------------------------------------------------+
//| Create order block                                               |
//+------------------------------------------------------------------+
void CreateOrderBlock(int candle_index, int type) {
    datetime time_start = iTime(_Symbol, PERIOD_M15, candle_index);
    double high = iHigh(_Symbol, PERIOD_M15, candle_index);
    double low = iLow(_Symbol, PERIOD_M15, candle_index);
    double volume = iTickVolume(_Symbol, PERIOD_M15, candle_index);
    
    // Check if order block already exists
    int size = ArraySize(order_blocks);
    for(int i = 0; i < size; i++) {
        if(order_blocks[i].time_start == time_start) {
            return; // Already exists
        }
    }
    
    // Find empty slot or resize array
    int index = -1;
    for(int i = 0; i < size; i++) {
        if(order_blocks[i].time_start == 0) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        ArrayResize(order_blocks, size + 10);
        index = size;
    }
    
    order_blocks[index].time_start = time_start;
    order_blocks[index].time_end = time_start + PeriodSeconds(PERIOD_M15) * InpOBMaxCandles;
    order_blocks[index].high = high;
    order_blocks[index].low = low;
    order_blocks[index].type = type;
    order_blocks[index].valid = true;
    order_blocks[index].mitigated = false;
    order_blocks[index].candle_count = 1;
    order_blocks[index].volume = volume;
    order_blocks[index].has_fvg = false;
    
    // Draw order block
    if(InpShowZones) {
        string name = "OB_" + TimeToString(time_start);
        color ob_color = (type == 1) ? InpBullishColor : InpBearishColor;
        CreateRectangle(name, time_start, high, order_blocks[index].time_end, low, ob_color);
    }
}

//+------------------------------------------------------------------+
//| Update order blocks                                              |
//+------------------------------------------------------------------+
void UpdateOrderBlocks() {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int size = ArraySize(order_blocks);
    
    for(int i = 0; i < size; i++) {
        if(order_blocks[i].time_start == 0 || !order_blocks[i].valid) continue;
        
        // Check if order block is mitigated
        if(order_blocks[i].type == 1 && current_price < order_blocks[i].low) {
            order_blocks[i].mitigated = true;
            order_blocks[i].valid = false;
        }
        else if(order_blocks[i].type == -1 && current_price > order_blocks[i].high) {
            order_blocks[i].mitigated = true;
            order_blocks[i].valid = false;
        }
        
        // Check if order block expired
        if(TimeCurrent() > order_blocks[i].time_end) {
            order_blocks[i].valid = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Identify fair value gaps                                         |
//+------------------------------------------------------------------+
void IdentifyFairValueGaps() {
    // Look for 3-candle FVG pattern
    for(int i = 2; i < Bars(_Symbol, PERIOD_M15) - 1; i++) {
        
        double high1 = iHigh(_Symbol, PERIOD_M15, i + 1);
        double low1 = iLow(_Symbol, PERIOD_M15, i + 1);
        double high2 = iHigh(_Symbol, PERIOD_M15, i);
        double low2 = iLow(_Symbol, PERIOD_M15, i);
        double high3 = iHigh(_Symbol, PERIOD_M15, i - 1);
        double low3 = iLow(_Symbol, PERIOD_M15, i - 1);
        
        datetime time = iTime(_Symbol, PERIOD_M15, i);
        
        // Bullish FVG: low of candle 3 > high of candle 1
        if(low3 > high1) {
            double gap_size = (low3 - high1) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            if(gap_size >= InpFVGMinPoints) {
                CreateFVG(time, low3, high1, 1);
            }
        }
        
        // Bearish FVG: high of candle 3 < low of candle 1
        if(high3 < low1) {
            double gap_size = (low1 - high3) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            if(gap_size >= InpFVGMinPoints) {
                CreateFVG(time, low1, high3, -1);
            }
        }
    }
    
    // Update existing FVGs
    UpdateFVGs();
}

//+------------------------------------------------------------------+
//| Create fair value gap                                            |
//+------------------------------------------------------------------+
void CreateFVG(datetime time, double upper, double lower, int type) {
    // Check if FVG already exists
    int size = ArraySize(fvgs);
    for(int i = 0; i < size; i++) {
        if(fvgs[i].time == time) {
            return; // Already exists
        }
    }
    
    // Find empty slot or resize array
    int index = -1;
    for(int i = 0; i < size; i++) {
        if(fvgs[i].time == 0) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        ArrayResize(fvgs, size + 10);
        index = size;
    }
    
    fvgs[index].time = time;
    fvgs[index].upper = upper;
    fvgs[index].lower = lower;
    fvgs[index].type = type;
    fvgs[index].filled = false;
    fvgs[index].inside_ob = CheckFVGInsideOB(upper, lower);
    
    // Draw FVG
    if(InpShowZones) {
        string name = "FVG_" + TimeToString(time);
        color fvg_color = (type == 1) ? clrLimeGreen : clrOrangeRed;
        CreateRectangle(name, time, upper, time + PeriodSeconds(PERIOD_M15) * 20, lower, fvg_color);
    }
}

//+------------------------------------------------------------------+
//| Check if FVG is inside order block                               |
//+------------------------------------------------------------------+
bool CheckFVGInsideOB(double fvg_upper, double fvg_lower) {
    int size = ArraySize(order_blocks);
    
    for(int i = 0; i < size; i++) {
        if(order_blocks[i].time_start == 0 || !order_blocks[i].valid) continue;
        
        if(fvg_upper <= order_blocks[i].high && fvg_lower >= order_blocks[i].low) {
            order_blocks[i].has_fvg = true;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update fair value gaps                                           |
//+------------------------------------------------------------------+
void UpdateFVGs() {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int size = ArraySize(fvgs);
    
    for(int i = 0; i < size; i++) {
        if(fvgs[i].time == 0 || fvgs[i].filled) continue;
        
        // Check if FVG is filled
        if(current_price >= fvgs[i].lower && current_price <= fvgs[i].upper) {
            fvgs[i].filled = true;
        }
    }
}

//+------------------------------------------------------------------+
//| Identify liquidity pools                                         |
//+------------------------------------------------------------------+
void IdentifyLiquidityPools() {
    // Look for equal highs and lows
    for(int i = 1; i < Bars(_Symbol, PERIOD_M15) - 1; i++) {
        double high = iHigh(_Symbol, PERIOD_M15, i);
        double low = iLow(_Symbol, PERIOD_M15, i);
        datetime time = iTime(_Symbol, PERIOD_M15, i);
        
        // Check for equal highs
        int equal_highs = CountEqualLevels(high, true, i);
        if(equal_highs >= 2) {
            CreateLiquidityPool(time, high, 1, equal_highs);
        }
        
        // Check for equal lows
        int equal_lows = CountEqualLevels(low, false, i);
        if(equal_lows >= 2) {
            CreateLiquidityPool(time, low, -1, equal_lows);
        }
    }
    
    // Update liquidity pools
    UpdateLiquidityPools();
}

//+------------------------------------------------------------------+
//| Count equal levels                                               |
//+------------------------------------------------------------------+
int CountEqualLevels(double price, bool is_high, int start_index) {
    int count = 1;
    double tolerance = 50 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // 5 pips tolerance
    
    // Look back for equal levels
    for(int i = start_index + 1; i < start_index + 20 && i < Bars(_Symbol, PERIOD_M15); i++) {
        double compare_price = is_high ? iHigh(_Symbol, PERIOD_M15, i) : iLow(_Symbol, PERIOD_M15, i);
        
        if(MathAbs(price - compare_price) <= tolerance) {
            count++;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Create liquidity pool                                            |
//+------------------------------------------------------------------+
void CreateLiquidityPool(datetime time, double price, int type, int touch_count) {
    // Check if liquidity pool already exists
    int size = ArraySize(liquidity_pools);
    for(int i = 0; i < size; i++) {
        if(MathAbs(liquidity_pools[i].price - price) <= 50 * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
            liquidity_pools[i].touch_count = MathMax(liquidity_pools[i].touch_count, touch_count);
            return; // Update existing
        }
    }
    
    // Find empty slot or resize array
    int index = -1;
    for(int i = 0; i < size; i++) {
        if(liquidity_pools[i].time == 0) {
            index = i;
            break;
        }
    }
    
    if(index == -1) {
        ArrayResize(liquidity_pools, size + 10);
        index = size;
    }
    
    liquidity_pools[index].time = time;
    liquidity_pools[index].price = price;
    liquidity_pools[index].type = type;
    liquidity_pools[index].swept = false;
    liquidity_pools[index].touch_count = touch_count;
    
    // Draw liquidity level
    if(InpShowZones) {
        string name = "LIQ_" + TimeToString(time);
        color liq_color = (type == 1) ? clrBlue : clrPurple;
        CreateHorizontalLine(name, price, liq_color);
    }
}

//+------------------------------------------------------------------+
//| Update liquidity pools                                           |
//+------------------------------------------------------------------+
void UpdateLiquidityPools() {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int size = ArraySize(liquidity_pools);
    
    for(int i = 0; i < size; i++) {
        if(liquidity_pools[i].time == 0 || liquidity_pools[i].swept) continue;
        
        double tolerance = 20 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        
        // Check if liquidity is swept
        if(liquidity_pools[i].type == 1 && current_price > liquidity_pools[i].price + tolerance) {
            liquidity_pools[i].swept = true;
            CreateLabel("SWEPT_" + TimeToString(liquidity_pools[i].time), liquidity_pools[i].time, 
                       liquidity_pools[i].price, "SWEPT", clrRed);
        }
        else if(liquidity_pools[i].type == -1 && current_price < liquidity_pools[i].price - tolerance) {
            liquidity_pools[i].swept = true;
            CreateLabel("SWEPT_" + TimeToString(liquidity_pools[i].time), liquidity_pools[i].time, 
                       liquidity_pools[i].price, "SWEPT", clrRed);
        }
    }
}

//+------------------------------------------------------------------+
//| Update higher timeframe bias                                     |
//+------------------------------------------------------------------+
void UpdateHTFBias() {
    // Monthly bias
    htf_bias_monthly = GetBias(PERIOD_MN1);
    
    // Weekly bias
    htf_bias_weekly = GetBias(PERIOD_W1);
    
    // Daily bias
    htf_bias_daily = GetBias(PERIOD_D1);
    
    // H4 bias
    htf_bias_h4 = GetBias(PERIOD_H4);
    
    // H1 bias
    htf_bias_h1 = GetBias(PERIOD_H1);
}

//+------------------------------------------------------------------+
//| Get bias for timeframe                                           |
//+------------------------------------------------------------------+
int GetBias(ENUM_TIMEFRAMES timeframe) {
    MqlRates rates[];
    if(CopyRates(_Symbol, timeframe, 0, 20, rates) < 20) {
        return 0; // Neutral if can't get data
    }
    
    // Simple bias calculation based on recent structure
    int bullish_count = 0;
    int bearish_count = 0;
    
    for(int i = 1; i < 10; i++) {
        if(rates[i].close > rates[i].open) {
            bullish_count++;
        } else {
            bearish_count++;
        }
    }
    
    // Also consider overall trend
    double sma_fast = 0;
    double sma_slow = 0;
    
    for(int i = 0; i < 5; i++) {
        sma_fast += rates[i].close;
    }
    sma_fast /= 5;
    
    for(int i = 0; i < 10; i++) {
        sma_slow += rates[i].close;
    }
    sma_slow /= 10;
    
    if(sma_fast > sma_slow && bullish_count > bearish_count) {
        return 1; // Bullish
    } else if(sma_fast < sma_slow && bearish_count > bullish_count) {
        return -1; // Bearish
    }
    
    return 0; // Neutral
}

//+------------------------------------------------------------------+
//| Check if can trade                                               |
//+------------------------------------------------------------------+
bool CanTrade() {
    // Check if in trading session
    if(!london_session_active && !newyork_session_active) {
        return false;
    }
    
    // Check drawdown
    if(current_drawdown > InpMaxDrawdown) {
        return false;
    }
    
    // Check if weekend
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day_of_week == 6 || dt.day_of_week == 0) {
        return false;
    }
    
    // Count trades today
    datetime today_start = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(last_trade_date < today_start) {
        trades_today = 0;
        last_trade_date = TimeCurrent();
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Scan for trade opportunities                                     |
//+------------------------------------------------------------------+
void ScanForTrades() {
    // Look for sniper setups
    ScanForSniperBuy();
    ScanForSniperSell();
}

//+------------------------------------------------------------------+
//| Scan for sniper buy setup                                        |
//+------------------------------------------------------------------+
void ScanForSniperBuy() {
    if(PositionsTotal() > 0) return; // Only one trade at a time
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Check HTF bias alignment
    if(htf_bias_daily <= 0 || htf_bias_h4 <= 0 || htf_bias_h1 <= 0) {
        return; // Need bullish bias
    }
    
    // Look for valid bullish order block with FVG
    int ob_size = ArraySize(order_blocks);
    for(int i = 0; i < ob_size; i++) {
        if(order_blocks[i].time_start == 0 || !order_blocks[i].valid || order_blocks[i].type != 1) {
            continue;
        }
        
        // Check if price is in order block
        if(current_price >= order_blocks[i].low && current_price <= order_blocks[i].high) {
            
            // Check if order block has FVG
            if(!order_blocks[i].has_fvg) continue;
            
            // Check if we're in discount (lower half of range)
            double range_mid = (internal_range_high + internal_range_low) / 2;
            if(current_price > range_mid) continue; // Must be in discount
            
            // Check for recent BOS confirmation
            bool bos_confirmed = false;
            int swing_size = ArraySize(swing_points);
            for(int j = 0; j < swing_size; j++) {
                if(swing_points[j].time > order_blocks[i].time_start && 
                   swing_points[j].bos_confirmed && 
                   swing_points[j].type == -1) { // Bullish BOS (breaking below previous low)
                    bos_confirmed = true;
                    break;
                }
            }
            
            if(!bos_confirmed) continue;
            
            // Check for liquidity sweep
            bool liquidity_swept = false;
            int liq_size = ArraySize(liquidity_pools);
            for(int k = 0; k < liq_size; k++) {
                if(liquidity_pools[k].type == -1 && liquidity_pools[k].swept &&
                   liquidity_pools[k].time > order_blocks[i].time_start) {
                    liquidity_swept = true;
                    break;
                }
            }
            
            if(!liquidity_swept) continue;
            
            // All conditions met - execute buy trade
            ExecuteBuyTrade(order_blocks[i]);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Scan for sniper sell setup                                       |
//+------------------------------------------------------------------+
void ScanForSniperSell() {
    if(PositionsTotal() > 0) return; // Only one trade at a time
    
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check HTF bias alignment
    if(htf_bias_daily >= 0 || htf_bias_h4 >= 0 || htf_bias_h1 >= 0) {
        return; // Need bearish bias
    }
    
    // Look for valid bearish order block with FVG
    int ob_size = ArraySize(order_blocks);
    for(int i = 0; i < ob_size; i++) {
        if(order_blocks[i].time_start == 0 || !order_blocks[i].valid || order_blocks[i].type != -1) {
            continue;
        }
        
        // Check if price is in order block
        if(current_price >= order_blocks[i].low && current_price <= order_blocks[i].high) {
            
            // Check if order block has FVG
            if(!order_blocks[i].has_fvg) continue;
            
            // Check if we're in premium (upper half of range)
            double range_mid = (internal_range_high + internal_range_low) / 2;
            if(current_price < range_mid) continue; // Must be in premium
            
            // Check for recent BOS confirmation
            bool bos_confirmed = false;
            int swing_size = ArraySize(swing_points);
            for(int j = 0; j < swing_size; j++) {
                if(swing_points[j].time > order_blocks[i].time_start && 
                   swing_points[j].bos_confirmed && 
                   swing_points[j].type == 1) { // Bearish BOS (breaking above previous high)
                    bos_confirmed = true;
                    break;
                }
            }
            
            if(!bos_confirmed) continue;
            
            // Check for liquidity sweep
            bool liquidity_swept = false;
            int liq_size = ArraySize(liquidity_pools);
            for(int k = 0; k < liq_size; k++) {
                if(liquidity_pools[k].type == 1 && liquidity_pools[k].swept &&
                   liquidity_pools[k].time > order_blocks[i].time_start) {
                    liquidity_swept = true;
                    break;
                }
            }
            
            if(!liquidity_swept) continue;
            
            // All conditions met - execute sell trade
            ExecuteSellTrade(order_blocks[i]);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(OrderBlock &ob) {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl_price = ob.low - (100 * SymbolInfoDouble(_Symbol, SYMBOL_POINT)); // SL below OB
    double tp_distance = current_price - sl_price;
    double tp_price = current_price + (tp_distance * InpMinRR);
    
    // Adjust for spread and broker requirements
    double min_sl_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if((current_price - sl_price) < min_sl_distance) {
        sl_price = current_price - min_sl_distance - (broker_spread * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
    }
    
    // Calculate lot size
    double lot_size = CalculateLotSize(current_price - sl_price);
    
    // Place trade
    if(trade.Buy(lot_size, _Symbol, current_price, sl_price, tp_price, "ICT SMC Buy")) {
        trades_today++;
        Print("Buy trade executed at ", current_price, " SL: ", sl_price, " TP: ", tp_price);
        
        // Create trade label
        CreateLabel("TRADE_BUY_" + TimeToString(TimeCurrent()), TimeCurrent(), current_price, "BUY", InpBullishColor);
    }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade(OrderBlock &ob) {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl_price = ob.high + (100 * SymbolInfoDouble(_Symbol, SYMBOL_POINT)); // SL above OB
    double tp_distance = sl_price - current_price;
    double tp_price = current_price - (tp_distance * InpMinRR);
    
    // Adjust for spread and broker requirements
    double min_sl_distance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if((sl_price - current_price) < min_sl_distance) {
        sl_price = current_price + min_sl_distance + (broker_spread * SymbolInfoDouble(_Symbol, SYMBOL_POINT));
    }
    
    // Calculate lot size
    double lot_size = CalculateLotSize(sl_price - current_price);
    
    // Place trade
    if(trade.Sell(lot_size, _Symbol, current_price, sl_price, tp_price, "ICT SMC Sell")) {
        trades_today++;
        Print("Sell trade executed at ", current_price, " SL: ", sl_price, " TP: ", tp_price);
        
        // Create trade label
        CreateLabel("TRADE_SELL_" + TimeToString(TimeCurrent()), TimeCurrent(), current_price, "SELL", InpBearishColor);
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance) {
    double risk_amount = current_equity * (InpRiskPercent / 100.0);
    
    // For micro accounts, allow higher risk initially
    if(current_equity < 10 && max_equity < 15) {
        risk_amount = current_equity * 0.20; // 20% risk for micro accounts
    }
    
    double point_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double sl_points = sl_distance / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    double lot_size = risk_amount / (sl_points * point_value);
    
    // Normalize lot size
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    lot_size = NormalizeDouble(lot_size / lot_step, 0) * lot_step;
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Manage existing trades                                            |
//+------------------------------------------------------------------+
void ManageTrades() {
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionSelectByTicket(ticket)) {
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                  SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            
            // Calculate R (risk) distance
            double r_distance = MathAbs(open_price - sl);
            double current_r = 0;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                current_r = (current_price - open_price) / r_distance;
            } else {
                current_r = (open_price - current_price) / r_distance;
            }
            
            // Break even logic
            if(InpUseBreakEven && current_r >= 1.0 && sl != open_price) {
                double new_sl = open_price;
                if(trade.PositionModify(ticket, new_sl, tp)) {
                    Print("Position moved to break even. Ticket: ", ticket);
                }
            }
            
            // Trailing stop logic
            if(InpUseTrailing && current_r >= InpTrailStart) {
                double new_sl = sl;
                
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    new_sl = current_price - (r_distance * 0.5); // Trail at 0.5R
                    if(new_sl > sl) {
                        if(trade.PositionModify(ticket, new_sl, tp)) {
                            Print("Buy position trailed. Ticket: ", ticket, " New SL: ", new_sl);
                        }
                    }
                } else {
                    new_sl = current_price + (r_distance * 0.5); // Trail at 0.5R
                    if(new_sl < sl) {
                        if(trade.PositionModify(ticket, new_sl, tp)) {
                            Print("Sell position trailed. Ticket: ", ticket, " New SL: ", new_sl);
                        }
                    }
                }
            }
            
            // Partial TP logic
            if(current_r >= InpPartialTP) {
                double current_volume = PositionGetDouble(POSITION_VOLUME);
                double partial_volume = current_volume * 0.5; // Close 50%
                
                if(partial_volume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                    if(trade.PositionClosePartial(ticket, partial_volume)) {
                        Print("Partial TP executed. Ticket: ", ticket, " Volume: ", partial_volume);
                    }
                }
            }
            
            // Dynamic TP extension
            if(displacement_detected && current_r >= 2.0) {
                double new_tp = tp;
                
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    new_tp = current_price + (r_distance * InpMaxRR);
                } else {
                    new_tp = current_price - (r_distance * InpMaxRR);
                }
                
                if(new_tp != tp) {
                    if(trade.PositionModify(ticket, sl, new_tp)) {
                        Print("TP extended due to displacement. Ticket: ", ticket, " New TP: ", new_tp);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Create dashboard                                                  |
//+------------------------------------------------------------------+
void CreateDashboard() {
    int x = 20;
    int y = 30;
    int line_height = 20;
    
    CreateTextLabel("DASH_TITLE", x, y, "XAUUSD ICT SMC EA", clrWhite, 12);
    y += line_height * 2;
    
    CreateTextLabel("DASH_EQUITY", x, y, "Equity: ", clrWhite, 10);
    y += line_height;
    
    CreateTextLabel("DASH_DRAWDOWN", x, y, "Drawdown: ", clrWhite, 10);
    y += line_height;
    
    CreateTextLabel("DASH_TRADES", x, y, "Trades Today: ", clrWhite, 10);
    y += line_height;
    
    CreateTextLabel("DASH_SESSION", x, y, "Session: ", clrWhite, 10);
    y += line_height;
    
    CreateTextLabel("DASH_BIAS_TITLE", x, y, "HTF Bias:", clrYellow, 10);
    y += line_height;
    
    CreateTextLabel("DASH_BIAS_D1", x, y, "D1: ", clrWhite, 9);
    y += line_height;
    
    CreateTextLabel("DASH_BIAS_H4", x, y, "H4: ", clrWhite, 9);
    y += line_height;
    
    CreateTextLabel("DASH_BIAS_H1", x, y, "H1: ", clrWhite, 9);
}

//+------------------------------------------------------------------+
//| Update dashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    ObjectSetString(0, "DASH_EQUITY", OBJPROP_TEXT, "Equity: $" + DoubleToString(current_equity, 2));
    ObjectSetString(0, "DASH_DRAWDOWN", OBJPROP_TEXT, "Drawdown: " + DoubleToString(current_drawdown, 2) + "%");
    ObjectSetString(0, "DASH_TRADES", OBJPROP_TEXT, "Trades Today: " + IntegerToString(trades_today));
    
    string session = "None";
    if(london_session_active) session = "London";
    if(newyork_session_active) session = "New York";
    ObjectSetString(0, "DASH_SESSION", OBJPROP_TEXT, "Session: " + session);
    
    string bias_d1 = htf_bias_daily == 1 ? "Bullish" : htf_bias_daily == -1 ? "Bearish" : "Neutral";
    string bias_h4 = htf_bias_h4 == 1 ? "Bullish" : htf_bias_h4 == -1 ? "Bearish" : "Neutral";
    string bias_h1 = htf_bias_h1 == 1 ? "Bullish" : htf_bias_h1 == -1 ? "Bearish" : "Neutral";
    
    ObjectSetString(0, "DASH_BIAS_D1", OBJPROP_TEXT, "D1: " + bias_d1);
    ObjectSetString(0, "DASH_BIAS_H4", OBJPROP_TEXT, "H4: " + bias_h4);
    ObjectSetString(0, "DASH_BIAS_H1", OBJPROP_TEXT, "H1: " + bias_h1);
    
    color d1_color = htf_bias_daily == 1 ? InpBullishColor : htf_bias_daily == -1 ? InpBearishColor : clrGray;
    color h4_color = htf_bias_h4 == 1 ? InpBullishColor : htf_bias_h4 == -1 ? InpBearishColor : clrGray;
    color h1_color = htf_bias_h1 == 1 ? InpBullishColor : htf_bias_h1 == -1 ? InpBearishColor : clrGray;
    
    ObjectSetInteger(0, "DASH_BIAS_D1", OBJPROP_COLOR, d1_color);
    ObjectSetInteger(0, "DASH_BIAS_H4", OBJPROP_COLOR, h4_color);
    ObjectSetInteger(0, "DASH_BIAS_H1", OBJPROP_COLOR, h1_color);
}

//+------------------------------------------------------------------+
//| Draw market structure                                             |
//+------------------------------------------------------------------+
void DrawMarketStructure() {
    // This function is called to refresh drawings
    // Most drawing is done in the individual functions
    // This could be used for dynamic updates
}

//+------------------------------------------------------------------+
//| Create text label                                                 |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text, color clr, int font_size) {
    if(ObjectFind(0, name) >= 0) {
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        return;
    }
    
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, datetime time, double price, string text, color clr) {
    if(!InpShowLabels) return;
    
    if(ObjectFind(0, name) >= 0) return;
    
    ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Create rectangle                                                  |
//+------------------------------------------------------------------+
void CreateRectangle(string name, datetime time1, double price1, datetime time2, double price2, color clr) {
    if(!InpShowZones) return;
    
    if(ObjectFind(0, name) >= 0) return;
    
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Create horizontal line                                            |
//+------------------------------------------------------------------+
void CreateHorizontalLine(string name, double price, color clr) {
    if(!InpShowZones) return;
    
    if(ObjectFind(0, name) >= 0) return;
    
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| On trade transaction                                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                       const MqlTradeRequest &request,
                       const MqlTradeResult &result) {
    // Log trade results for analysis
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        LogTradeResult(trans, result);
    }
}

//+------------------------------------------------------------------+
//| Log trade result                                                  |
//+------------------------------------------------------------------+
void LogTradeResult(const MqlTradeTransaction &trans, const MqlTradeResult &result) {
    // Create CSV log entry
    string log_entry = TimeToString(TimeCurrent()) + "," +
                      _Symbol + "," +
                      DoubleToString(trans.volume, 2) + "," +
                      DoubleToString(trans.price, 5) + "," +
                      IntegerToString(trans.type) + "," +
                      DoubleToString(result.profit, 2) + "\n";
    
    // In a real implementation, this would write to a file
    Print("Trade logged: ", log_entry);
}