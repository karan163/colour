//+------------------------------------------------------------------+
//|                                              ICT_SMC_XAUUSD_EA.mq5 |
//|                                    Institutional ICT/SMC Expert Advisor |
//|                                                      XAUUSD Trading |
//+------------------------------------------------------------------+
#property copyright "ICT SMC EA"
#property link      ""
#property version   "1.00"
#property description "Complete ICT/SMC Expert Advisor for XAUUSD"

//--- Input parameters
input group "=== RISK MANAGEMENT ==="
input double RiskPercent = 2.0;                    // Risk per trade (%)
input double MaxDDPercent = 20.0;                  // Max drawdown for small accounts (%)
input bool UseCompounding = true;                  // Enable compounding
input double MinLotSize = 0.01;                    // Minimum lot size
input double MaxLotSize = 100.0;                   // Maximum lot size

input group "=== ICT/SMC SETTINGS ==="
input int LookbackBars = 500;                      // Lookback bars for analysis
input int OBMinSize = 5;                           // Minimum OB size in bars
input int FVGMinSize = 3;                          // Minimum FVG size in pips
input double VolumeThreshold = 1.5;                // Volume threshold multiplier
input bool RequireHTFBias = true;                  // Require HTF bias confirmation
input int DisplacementMinPips = 10;                // Minimum displacement in pips

input group "=== TRADE MANAGEMENT ==="
input double TPMultiplier = 2.0;                   // Dynamic TP multiplier
input double BreakEvenRR = 1.5;                    // Move to BE at this RR
input double PartialTPRR = 1.5;                    // Partial TP at this RR
input double PartialTPPercent = 50.0;               // Partial TP percentage
input bool UseTrailingStop = true;                 // Enable trailing stop
input double TrailingStartRR = 2.0;                // Start trailing at this RR

input group "=== VISUAL SETTINGS ==="
input bool ShowDashboard = true;                   // Show dashboard
input bool DrawStructures = true;                  // Draw structures on chart
input color BOSColor = clrYellow;                  // BOS color
input color CHoCHColor = clrOrange;                // CHoCH color
input color OBBuyColor = clrLimeGreen;             // Buy OB color
input color OBSellColor = clrRed;                  // Sell OB color
input color FVGColor = clrAqua;                    // FVG color

//--- Global variables
struct OrderBlock {
    datetime time;
    double high;
    double low;
    double open;
    double close;
    bool is_bullish;
    bool is_mitigated;
    int strength;
    bool has_fvg;
    datetime fvg_time;
    double fvg_high;
    double fvg_low;
};

struct FairValueGap {
    datetime time;
    double high;
    double low;
    bool is_bullish;
    bool is_mitigated;
    int timeframe;
};

struct LiquidityLevel {
    double price;
    datetime time;
    bool is_high;
    bool is_swept;
    int strength;
};

struct TradeInfo {
    int ticket;
    datetime entry_time;
    double entry_price;
    double sl;
    double tp;
    double lot_size;
    string bias;
    string entry_type;
    bool be_moved;
    bool partial_closed;
};

//--- Arrays and variables
OrderBlock order_blocks[];
FairValueGap fvgs[];
LiquidityLevel liquidity_levels[];
TradeInfo active_trades[];

double current_equity;
double initial_balance;
string htf_bias = "NEUTRAL";
string current_market_structure = "RANGE";
int trades_today = 0;
datetime last_trade_date;
bool displacement_detected = false;
datetime last_displacement_time;

//--- Timeframes for HTF analysis
ENUM_TIMEFRAMES htf_timeframes[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M30, PERIOD_M15, PERIOD_M5, PERIOD_M1};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialize arrays
    ArrayResize(order_blocks, 0);
    ArrayResize(fvgs, 0);
    ArrayResize(liquidity_levels, 0);
    ArrayResize(active_trades, 0);
    
    initial_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Validate symbol
    if(_Symbol != "XAUUSD" && _Symbol != "GOLD" && _Symbol != "XAUUSD.") {
        Print("WARNING: This EA is optimized for XAUUSD trading");
    }
    
    // Create dashboard
    if(ShowDashboard) {
        CreateDashboard();
    }
    
    Print("ICT SMC EA initialized successfully for ", _Symbol);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Clean up dashboard
    if(ShowDashboard) {
        ObjectsDeleteAll(0, "Dashboard_");
    }
    
    // Clean up chart objects
    ObjectsDeleteAll(0, "ICT_");
    ObjectsDeleteAll(0, "SMC_");
    
    Print("ICT SMC EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Update current values
    current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Check if new day for trade counting
    if(TimeToStruct(TimeCurrent()).day != TimeToStruct(last_trade_date).day) {
        trades_today = 0;
        last_trade_date = TimeCurrent();
    }
    
    // Update HTF bias
    UpdateHTFBias();
    
    // Analyze market structure
    AnalyzeMarketStructure();
    
    // Detect displacement
    DetectDisplacement();
    
    // Find and update order blocks
    FindOrderBlocks();
    
    // Find Fair Value Gaps
    FindFairValueGaps();
    
    // Update liquidity levels
    UpdateLiquidityLevels();
    
    // Manage existing trades
    ManageOpenTrades();
    
    // Look for new trade opportunities
    ScanForEntries();
    
    // Update dashboard
    if(ShowDashboard) {
        UpdateDashboard();
    }
}

//+------------------------------------------------------------------+
//| Update HTF Bias                                                 |
//+------------------------------------------------------------------+
void UpdateHTFBias() {
    int bullish_count = 0;
    int bearish_count = 0;
    
    for(int tf = 0; tf < ArraySize(htf_timeframes); tf++) {
        ENUM_TIMEFRAMES timeframe = htf_timeframes[tf];
        
        // Get structure for this timeframe
        double high_50 = iHigh(_Symbol, timeframe, iHighest(_Symbol, timeframe, MODE_HIGH, 50, 1));
        double low_50 = iLow(_Symbol, timeframe, iLowest(_Symbol, timeframe, MODE_LOW, 50, 1));
        double current_price = iClose(_Symbol, timeframe, 1);
        
        // Determine bias based on position in range and recent structure
        double range_position = (current_price - low_50) / (high_50 - low_50);
        
        // Check for recent BOS
        bool recent_bullish_bos = CheckForBOS(timeframe, true);
        bool recent_bearish_bos = CheckForBOS(timeframe, false);
        
        if(recent_bullish_bos || range_position > 0.6) {
            bullish_count++;
        } else if(recent_bearish_bos || range_position < 0.4) {
            bearish_count++;
        }
    }
    
    // Determine overall bias
    if(bullish_count > bearish_count + 2) {
        htf_bias = "BULLISH";
    } else if(bearish_count > bullish_count + 2) {
        htf_bias = "BEARISH";
    } else {
        htf_bias = "NEUTRAL";
    }
}

//+------------------------------------------------------------------+
//| Check for Break of Structure                                    |
//+------------------------------------------------------------------+
bool CheckForBOS(ENUM_TIMEFRAMES timeframe, bool bullish) {
    double close_prices[20];
    double high_prices[20];
    double low_prices[20];
    
    if(CopyClose(_Symbol, timeframe, 1, 20, close_prices) != 20) return false;
    if(CopyHigh(_Symbol, timeframe, 1, 20, high_prices) != 20) return false;
    if(CopyLow(_Symbol, timeframe, 1, 20, low_prices) != 20) return false;
    
    if(bullish) {
        // Look for bullish BOS - close above previous high
        double prev_high = high_prices[ArrayMaximum(high_prices, 5, 10)];
        return close_prices[0] > prev_high;
    } else {
        // Look for bearish BOS - close below previous low
        double prev_low = low_prices[ArrayMinimum(low_prices, 5, 10)];
        return close_prices[0] < prev_low;
    }
}

//+------------------------------------------------------------------+
//| Analyze Market Structure                                        |
//+------------------------------------------------------------------+
void AnalyzeMarketStructure() {
    // Get recent price data
    double highs[50];
    double lows[50];
    double closes[50];
    
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 50, highs) != 50) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 50, lows) != 50) return;
    if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 50, closes) != 50) return;
    
    // Find swing highs and lows
    int hh_count = 0, ll_count = 0;
    int hl_count = 0, lh_count = 0;
    
    for(int i = 5; i < 45; i++) {
        bool is_swing_high = true;
        bool is_swing_low = true;
        
        // Check if it's a swing high
        for(int j = i-5; j <= i+5; j++) {
            if(j != i && highs[j] >= highs[i]) {
                is_swing_high = false;
                break;
            }
        }
        
        // Check if it's a swing low
        for(int j = i-5; j <= i+5; j++) {
            if(j != i && lows[j] <= lows[i]) {
                is_swing_low = false;
                break;
            }
        }
        
        if(is_swing_high) {
            // Compare with previous swing high
            for(int k = i+1; k < 45; k++) {
                bool prev_is_swing_high = true;
                for(int l = k-5; l <= k+5 && l < 50; l++) {
                    if(l != k && l >= 0 && highs[l] >= highs[k]) {
                        prev_is_swing_high = false;
                        break;
                    }
                }
                if(prev_is_swing_high) {
                    if(highs[i] > highs[k]) hh_count++;
                    else lh_count++;
                    break;
                }
            }
        }
        
        if(is_swing_low) {
            // Compare with previous swing low
            for(int k = i+1; k < 45; k++) {
                bool prev_is_swing_low = true;
                for(int l = k-5; l <= k+5 && l < 50; l++) {
                    if(l != k && l >= 0 && lows[l] <= lows[k]) {
                        prev_is_swing_low = false;
                        break;
                    }
                }
                if(prev_is_swing_low) {
                    if(lows[i] < lows[k]) ll_count++;
                    else hl_count++;
                    break;
                }
            }
        }
    }
    
    // Determine market structure
    if(hh_count > 0 && ll_count > 0) {
        current_market_structure = "UPTREND";
    } else if(lh_count > 0 && hl_count > 0) {
        current_market_structure = "DOWNTREND";
    } else {
        current_market_structure = "RANGE";
    }
}

//+------------------------------------------------------------------+
//| Detect Displacement                                             |
//+------------------------------------------------------------------+
void DetectDisplacement() {
    double prices[10];
    long volumes[10];
    
    if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 10, prices) != 10) return;
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, 10, volumes) != 10) return;
    
    // Calculate average volume
    long avg_volume = 0;
    for(int i = 0; i < 10; i++) {
        avg_volume += volumes[i];
    }
    avg_volume /= 10;
    
    // Check for displacement
    double price_change = MathAbs(prices[0] - prices[1]) / _Point;
    double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
    double displacement_pips = price_change * pip_value;
    
    if(displacement_pips >= DisplacementMinPips && volumes[0] > avg_volume * VolumeThreshold) {
        displacement_detected = true;
        last_displacement_time = TimeCurrent();
        
        if(DrawStructures) {
            string obj_name = "ICT_Displacement_" + TimeToString(TimeCurrent());
            ObjectCreate(0, obj_name, OBJ_ARROW, 0, TimeCurrent(), prices[0]);
            ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 233);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrMagenta);
        }
    }
}

//+------------------------------------------------------------------+
//| Find Order Blocks                                               |
//+------------------------------------------------------------------+
void FindOrderBlocks() {
    double opens[LookbackBars];
    double highs[LookbackBars];
    double lows[LookbackBars];
    double closes[LookbackBars];
    long volumes[LookbackBars];
    
    if(CopyOpen(_Symbol, PERIOD_CURRENT, 1, LookbackBars, opens) != LookbackBars) return;
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, LookbackBars, highs) != LookbackBars) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, LookbackBars, lows) != LookbackBars) return;
    if(CopyClose(_Symbol, PERIOD_CURRENT, 1, LookbackBars, closes) != LookbackBars) return;
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, LookbackBars, volumes) != LookbackBars) return;
    
    // Clear old mitigated order blocks
    for(int i = ArraySize(order_blocks) - 1; i >= 0; i--) {
        if(order_blocks[i].is_mitigated) {
            ArrayRemove(order_blocks, i, 1);
        }
    }
    
    // Find new order blocks
    for(int i = OBMinSize; i < LookbackBars - OBMinSize; i++) {
        // Check for bullish order block (strong buying)
        bool is_bullish_ob = false;
        bool is_bearish_ob = false;
        
        // Bullish OB: strong up candle followed by retracement then continuation
        if(closes[i] > opens[i] && (closes[i] - opens[i]) > (highs[i] - lows[i]) * 0.7) {
            // Check if this candle caused displacement
            double body_size = MathAbs(closes[i] - opens[i]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(body_size * pip_value >= DisplacementMinPips * 0.5 && volumes[i] > volumes[i+1] * 1.2) {
                // Check for retracement and continuation
                bool retracement_found = false;
                bool continuation_found = false;
                
                for(int j = i - 1; j >= MathMax(0, i - OBMinSize); j--) {
                    if(lows[j] <= opens[i] + (closes[i] - opens[i]) * 0.5) {
                        retracement_found = true;
                    }
                    if(closes[j] > closes[i] && retracement_found) {
                        continuation_found = true;
                        break;
                    }
                }
                
                if(retracement_found && continuation_found) {
                    is_bullish_ob = true;
                }
            }
        }
        
        // Bearish OB: strong down candle followed by retracement then continuation
        if(closes[i] < opens[i] && (opens[i] - closes[i]) > (highs[i] - lows[i]) * 0.7) {
            double body_size = MathAbs(opens[i] - closes[i]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(body_size * pip_value >= DisplacementMinPips * 0.5 && volumes[i] > volumes[i+1] * 1.2) {
                bool retracement_found = false;
                bool continuation_found = false;
                
                for(int j = i - 1; j >= MathMax(0, i - OBMinSize); j--) {
                    if(highs[j] >= closes[i] + (opens[i] - closes[i]) * 0.5) {
                        retracement_found = true;
                    }
                    if(closes[j] < closes[i] && retracement_found) {
                        continuation_found = true;
                        break;
                    }
                }
                
                if(retracement_found && continuation_found) {
                    is_bearish_ob = true;
                }
            }
        }
        
        // Add order block if found
        if(is_bullish_ob || is_bearish_ob) {
            OrderBlock ob;
            ob.time = iTime(_Symbol, PERIOD_CURRENT, i);
            ob.high = highs[i];
            ob.low = lows[i];
            ob.open = opens[i];
            ob.close = closes[i];
            ob.is_bullish = is_bullish_ob;
            ob.is_mitigated = false;
            ob.strength = (int)(volumes[i] / volumes[i+1] * 100);
            
            // Check for FVG in vicinity
            CheckForFVGInOB(ob, i, highs, lows, closes);
            
            // Check if this OB already exists
            bool exists = false;
            for(int k = 0; k < ArraySize(order_blocks); k++) {
                if(MathAbs(order_blocks[k].time - ob.time) < 3600) {
                    exists = true;
                    break;
                }
            }
            
            if(!exists) {
                ArrayResize(order_blocks, ArraySize(order_blocks) + 1);
                order_blocks[ArraySize(order_blocks) - 1] = ob;
                
                // Draw order block
                if(DrawStructures) {
                    DrawOrderBlock(ob);
                }
            }
        }
    }
    
    // Check for mitigation of existing order blocks
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    for(int i = 0; i < ArraySize(order_blocks); i++) {
        if(!order_blocks[i].is_mitigated) {
            if(order_blocks[i].is_bullish) {
                // Bullish OB mitigated if price closes below the low
                if(current_price < order_blocks[i].low) {
                    order_blocks[i].is_mitigated = true;
                }
            } else {
                // Bearish OB mitigated if price closes above the high
                if(current_price > order_blocks[i].high) {
                    order_blocks[i].is_mitigated = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for FVG in Order Block                                   |
//+------------------------------------------------------------------+
void CheckForFVGInOB(OrderBlock &ob, int ob_index, double &highs[], double &lows[], double &closes[]) {
    ob.has_fvg = false;
    
    // Look for FVG within OB range
    for(int i = MathMax(0, ob_index - 5); i <= MathMin(ArraySize(highs) - 3, ob_index + 5); i++) {
        // Check for bullish FVG (gap up)
        if(i >= 2 && lows[i-2] > highs[i] && closes[i-1] > opens[i-1]) {
            double gap_size = (lows[i-2] - highs[i]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(gap_size * pip_value >= FVGMinSize) {
                ob.has_fvg = true;
                ob.fvg_time = iTime(_Symbol, PERIOD_CURRENT, i);
                ob.fvg_high = lows[i-2];
                ob.fvg_low = highs[i];
                break;
            }
        }
        
        // Check for bearish FVG (gap down)
        if(i >= 2 && highs[i-2] < lows[i] && closes[i-1] < opens[i-1]) {
            double gap_size = (lows[i] - highs[i-2]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(gap_size * pip_value >= FVGMinSize) {
                ob.has_fvg = true;
                ob.fvg_time = iTime(_Symbol, PERIOD_CURRENT, i);
                ob.fvg_high = lows[i];
                ob.fvg_low = highs[i-2];
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find Fair Value Gaps                                           |
//+------------------------------------------------------------------+
void FindFairValueGaps() {
    double highs[100];
    double lows[100];
    double opens[100];
    double closes[100];
    
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 100, highs) != 100) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 100, lows) != 100) return;
    if(CopyOpen(_Symbol, PERIOD_CURRENT, 1, 100, opens) != 100) return;
    if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 100, closes) != 100) return;
    
    // Clear old mitigated FVGs
    for(int i = ArraySize(fvgs) - 1; i >= 0; i--) {
        if(fvgs[i].is_mitigated) {
            ArrayRemove(fvgs, i, 1);
        }
    }
    
    // Find new FVGs
    for(int i = 2; i < 98; i++) {
        // Bullish FVG: Low of candle 2 bars ago > High of current candle
        if(lows[i+2] > highs[i]) {
            double gap_size = (lows[i+2] - highs[i]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(gap_size * pip_value >= FVGMinSize) {
                FairValueGap fvg;
                fvg.time = iTime(_Symbol, PERIOD_CURRENT, i);
                fvg.high = lows[i+2];
                fvg.low = highs[i];
                fvg.is_bullish = true;
                fvg.is_mitigated = false;
                fvg.timeframe = PERIOD_CURRENT;
                
                // Check if already exists
                bool exists = false;
                for(int j = 0; j < ArraySize(fvgs); j++) {
                    if(MathAbs(fvgs[j].time - fvg.time) < 600) {
                        exists = true;
                        break;
                    }
                }
                
                if(!exists) {
                    ArrayResize(fvgs, ArraySize(fvgs) + 1);
                    fvgs[ArraySize(fvgs) - 1] = fvg;
                    
                    if(DrawStructures) {
                        DrawFVG(fvg);
                    }
                }
            }
        }
        
        // Bearish FVG: High of candle 2 bars ago < Low of current candle
        if(highs[i+2] < lows[i]) {
            double gap_size = (lows[i] - highs[i+2]) / _Point;
            double pip_value = (_Symbol == "XAUUSD" || _Symbol == "GOLD") ? 0.1 : 0.0001;
            
            if(gap_size * pip_value >= FVGMinSize) {
                FairValueGap fvg;
                fvg.time = iTime(_Symbol, PERIOD_CURRENT, i);
                fvg.high = lows[i];
                fvg.low = highs[i+2];
                fvg.is_bullish = false;
                fvg.is_mitigated = false;
                fvg.timeframe = PERIOD_CURRENT;
                
                // Check if already exists
                bool exists = false;
                for(int j = 0; j < ArraySize(fvgs); j++) {
                    if(MathAbs(fvgs[j].time - fvg.time) < 600) {
                        exists = true;
                        break;
                    }
                }
                
                if(!exists) {
                    ArrayResize(fvgs, ArraySize(fvgs) + 1);
                    fvgs[ArraySize(fvgs) - 1] = fvg;
                    
                    if(DrawStructures) {
                        DrawFVG(fvg);
                    }
                }
            }
        }
    }
    
    // Check for mitigation
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    for(int i = 0; i < ArraySize(fvgs); i++) {
        if(!fvgs[i].is_mitigated) {
            if(fvgs[i].is_bullish) {
                // Bullish FVG mitigated if price goes back into the gap
                if(current_price <= fvgs[i].low) {
                    fvgs[i].is_mitigated = true;
                }
            } else {
                // Bearish FVG mitigated if price goes back into the gap
                if(current_price >= fvgs[i].high) {
                    fvgs[i].is_mitigated = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update Liquidity Levels                                        |
//+------------------------------------------------------------------+
void UpdateLiquidityLevels() {
    double highs[100];
    double lows[100];
    
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 100, highs) != 100) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 100, lows) != 100) return;
    
    // Clear old swept levels
    for(int i = ArraySize(liquidity_levels) - 1; i >= 0; i--) {
        if(liquidity_levels[i].is_swept) {
            ArrayRemove(liquidity_levels, i, 1);
        }
    }
    
    // Find equal highs and lows
    for(int i = 10; i < 90; i++) {
        // Check for equal highs
        for(int j = i + 5; j < 95; j++) {
            if(MathAbs(highs[i] - highs[j]) <= _Point * 2) {
                // Found equal highs
                LiquidityLevel level;
                level.price = (highs[i] + highs[j]) / 2;
                level.time = iTime(_Symbol, PERIOD_CURRENT, i);
                level.is_high = true;
                level.is_swept = false;
                level.strength = 1;
                
                // Check if already exists
                bool exists = false;
                for(int k = 0; k < ArraySize(liquidity_levels); k++) {
                    if(MathAbs(liquidity_levels[k].price - level.price) <= _Point * 3) {
                        exists = true;
                        liquidity_levels[k].strength++;
                        break;
                    }
                }
                
                if(!exists && ArraySize(liquidity_levels) < 50) {
                    ArrayResize(liquidity_levels, ArraySize(liquidity_levels) + 1);
                    liquidity_levels[ArraySize(liquidity_levels) - 1] = level;
                }
                break;
            }
        }
        
        // Check for equal lows
        for(int j = i + 5; j < 95; j++) {
            if(MathAbs(lows[i] - lows[j]) <= _Point * 2) {
                // Found equal lows
                LiquidityLevel level;
                level.price = (lows[i] + lows[j]) / 2;
                level.time = iTime(_Symbol, PERIOD_CURRENT, i);
                level.is_high = false;
                level.is_swept = false;
                level.strength = 1;
                
                // Check if already exists
                bool exists = false;
                for(int k = 0; k < ArraySize(liquidity_levels); k++) {
                    if(MathAbs(liquidity_levels[k].price - level.price) <= _Point * 3) {
                        exists = true;
                        liquidity_levels[k].strength++;
                        break;
                    }
                }
                
                if(!exists && ArraySize(liquidity_levels) < 50) {
                    ArrayResize(liquidity_levels, ArraySize(liquidity_levels) + 1);
                    liquidity_levels[ArraySize(liquidity_levels) - 1] = level;
                }
                break;
            }
        }
    }
    
    // Check for sweeps
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    for(int i = 0; i < ArraySize(liquidity_levels); i++) {
        if(!liquidity_levels[i].is_swept) {
            if(liquidity_levels[i].is_high && current_ask > liquidity_levels[i].price) {
                liquidity_levels[i].is_swept = true;
                
                if(DrawStructures) {
                    string obj_name = "ICT_LiqSweep_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, obj_name, OBJ_ARROW, 0, TimeCurrent(), liquidity_levels[i].price);
                    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 233);
                    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrYellow);
                }
            } else if(!liquidity_levels[i].is_high && current_price < liquidity_levels[i].price) {
                liquidity_levels[i].is_swept = true;
                
                if(DrawStructures) {
                    string obj_name = "ICT_LiqSweep_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, obj_name, OBJ_ARROW, 0, TimeCurrent(), liquidity_levels[i].price);
                    ObjectSetInteger(0, obj_name, OBJPROP_ARROWCODE, 234);
                    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clrYellow);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Open Trades                                             |
//+------------------------------------------------------------------+
void ManageOpenTrades() {
    // Update active trades array
    ArrayResize(active_trades, 0);
    
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol) {
                TradeInfo trade;
                trade.ticket = (int)PositionGetInteger(POSITION_TICKET);
                trade.entry_time = (datetime)PositionGetInteger(POSITION_TIME);
                trade.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
                trade.sl = PositionGetDouble(POSITION_SL);
                trade.tp = PositionGetDouble(POSITION_TP);
                trade.lot_size = PositionGetDouble(POSITION_VOLUME);
                
                ArrayResize(active_trades, ArraySize(active_trades) + 1);
                active_trades[ArraySize(active_trades) - 1] = trade;
                
                // Manage this trade
                ManageIndividualTrade(trade);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Individual Trade                                        |
//+------------------------------------------------------------------+
void ManageIndividualTrade(TradeInfo &trade) {
    if(!PositionSelectByTicket(trade.ticket)) return;
    
    double current_price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double profit_points = 0;
    if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
        profit_points = (current_price - trade.entry_price) / _Point;
    } else {
        profit_points = (trade.entry_price - current_price) / _Point;
    }
    
    double sl_points = MathAbs(trade.entry_price - trade.sl) / _Point;
    double rr_ratio = sl_points > 0 ? profit_points / sl_points : 0;
    
    // Move to breakeven
    if(!trade.be_moved && rr_ratio >= BreakEvenRR) {
        MqlTradeRequest request;
        MqlTradeResult result;
        
        ZeroMemory(request);
        request.action = TRADE_ACTION_SLTP;
        request.symbol = _Symbol;
        request.sl = trade.entry_price;
        request.tp = trade.tp;
        request.position = trade.ticket;
        
        if(OrderSend(request, result)) {
            trade.be_moved = true;
            Print("Moved trade ", trade.ticket, " to breakeven");
        }
    }
    
    // Partial TP
    if(!trade.partial_closed && rr_ratio >= PartialTPRR) {
        double partial_volume = trade.lot_size * PartialTPPercent / 100.0;
        partial_volume = NormalizeDouble(partial_volume, 2);
        
        if(partial_volume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
            MqlTradeRequest request;
            MqlTradeResult result;
            
            ZeroMemory(request);
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = partial_volume;
            request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.position = trade.ticket;
            request.deviation = 10;
            
            if(OrderSend(request, result)) {
                trade.partial_closed = true;
                Print("Partial TP executed for trade ", trade.ticket);
            }
        }
    }
    
    // Trailing stop
    if(UseTrailingStop && rr_ratio >= TrailingStartRR) {
        double new_sl = 0;
        
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            // For buy position, trail below recent lows
            double recent_low = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 10, 1));
            new_sl = recent_low - _Point * 50; // 5 pip buffer
            
            if(new_sl > trade.sl && new_sl < current_price) {
                MqlTradeRequest request;
                MqlTradeResult result;
                
                ZeroMemory(request);
                request.action = TRADE_ACTION_SLTP;
                request.symbol = _Symbol;
                request.sl = new_sl;
                request.tp = trade.tp;
                request.position = trade.ticket;
                
                if(OrderSend(request, result)) {
                    Print("Trailing stop updated for trade ", trade.ticket);
                }
            }
        } else {
            // For sell position, trail above recent highs
            double recent_high = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 10, 1));
            new_sl = recent_high + _Point * 50; // 5 pip buffer
            
            if((trade.sl == 0 || new_sl < trade.sl) && new_sl > current_price) {
                MqlTradeRequest request;
                MqlTradeResult result;
                
                ZeroMemory(request);
                request.action = TRADE_ACTION_SLTP;
                request.symbol = _Symbol;
                request.sl = new_sl;
                request.tp = trade.tp;
                request.position = trade.ticket;
                
                if(OrderSend(request, result)) {
                    Print("Trailing stop updated for trade ", trade.ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Scan for Entry Opportunities                                   |
//+------------------------------------------------------------------+
void ScanForEntries() {
    // Don't enter if already in trade
    if(ArraySize(active_trades) > 0) return;
    
    double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Scan for bullish entries
    for(int i = 0; i < ArraySize(order_blocks); i++) {
        if(order_blocks[i].is_bullish && !order_blocks[i].is_mitigated) {
            // Check if price is in OB zone
            if(current_bid >= order_blocks[i].low && current_bid <= order_blocks[i].high) {
                // Check confluence factors
                if(CheckBullishConfluence(order_blocks[i])) {
                    ExecuteBuyTrade(order_blocks[i]);
                    return;
                }
            }
        }
    }
    
    // Scan for bearish entries
    for(int i = 0; i < ArraySize(order_blocks); i++) {
        if(!order_blocks[i].is_bullish && !order_blocks[i].is_mitigated) {
            // Check if price is in OB zone
            if(current_ask <= order_blocks[i].high && current_ask >= order_blocks[i].low) {
                // Check confluence factors
                if(CheckBearishConfluence(order_blocks[i])) {
                    ExecuteSellTrade(order_blocks[i]);
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Bullish Confluence                                       |
//+------------------------------------------------------------------+
bool CheckBullishConfluence(OrderBlock &ob) {
    // Check HTF bias
    if(RequireHTFBias && htf_bias != "BULLISH" && htf_bias != "NEUTRAL") {
        return false;
    }
    
    // Check for recent displacement
    if(TimeCurrent() - last_displacement_time > 3600) {
        return false;
    }
    
    // Check for FVG in OB
    if(!ob.has_fvg) {
        // Look for nearby FVG
        bool fvg_found = false;
        for(int i = 0; i < ArraySize(fvgs); i++) {
            if(fvgs[i].is_bullish && !fvgs[i].is_mitigated) {
                if(fvgs[i].low >= ob.low && fvgs[i].high <= ob.high) {
                    fvg_found = true;
                    break;
                }
            }
        }
        if(!fvg_found) return false;
    }
    
    // Check for recent liquidity sweep
    bool liquidity_swept = false;
    for(int i = 0; i < ArraySize(liquidity_levels); i++) {
        if(!liquidity_levels[i].is_high && liquidity_levels[i].is_swept) {
            if(TimeCurrent() - liquidity_levels[i].time < 1800) {
                liquidity_swept = true;
                break;
            }
        }
    }
    
    // Check market structure
    if(current_market_structure == "DOWNTREND") {
        return false;
    }
    
    return liquidity_swept || current_market_structure == "UPTREND";
}

//+------------------------------------------------------------------+
//| Check Bearish Confluence                                       |
//+------------------------------------------------------------------+
bool CheckBearishConfluence(OrderBlock &ob) {
    // Check HTF bias
    if(RequireHTFBias && htf_bias != "BEARISH" && htf_bias != "NEUTRAL") {
        return false;
    }
    
    // Check for recent displacement
    if(TimeCurrent() - last_displacement_time > 3600) {
        return false;
    }
    
    // Check for FVG in OB
    if(!ob.has_fvg) {
        // Look for nearby FVG
        bool fvg_found = false;
        for(int i = 0; i < ArraySize(fvgs); i++) {
            if(!fvgs[i].is_bullish && !fvgs[i].is_mitigated) {
                if(fvgs[i].low >= ob.low && fvgs[i].high <= ob.high) {
                    fvg_found = true;
                    break;
                }
            }
        }
        if(!fvg_found) return false;
    }
    
    // Check for recent liquidity sweep
    bool liquidity_swept = false;
    for(int i = 0; i < ArraySize(liquidity_levels); i++) {
        if(liquidity_levels[i].is_high && liquidity_levels[i].is_swept) {
            if(TimeCurrent() - liquidity_levels[i].time < 1800) {
                liquidity_swept = true;
                break;
            }
        }
    }
    
    // Check market structure
    if(current_market_structure == "UPTREND") {
        return false;
    }
    
    return liquidity_swept || current_market_structure == "DOWNTREND";
}

//+------------------------------------------------------------------+
//| Execute Buy Trade                                              |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(OrderBlock &ob) {
    double lot_size = CalculateLotSize(true, ob);
    if(lot_size < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
    
    double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = ob.low - _Point * 20; // SL below OB with buffer
    double tp = CalculateTP(entry_price, sl, true);
    
    // Validate SL/TP levels
    double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    if(entry_price - sl < min_stop_level || tp - entry_price < min_stop_level) {
        return;
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot_size;
    request.type = ORDER_TYPE_BUY;
    request.price = entry_price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "ICT SMC Buy";
    
    if(OrderSend(request, result)) {
        Print("Buy trade executed: Ticket ", result.order, " Entry: ", entry_price, " SL: ", sl, " TP: ", tp);
        trades_today++;
        
        // Mark OB as used
        ob.is_mitigated = true;
    }
}

//+------------------------------------------------------------------+
//| Execute Sell Trade                                             |
//+------------------------------------------------------------------+
void ExecuteSellTrade(OrderBlock &ob) {
    double lot_size = CalculateLotSize(false, ob);
    if(lot_size < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
    
    double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = ob.high + _Point * 20; // SL above OB with buffer
    double tp = CalculateTP(entry_price, sl, false);
    
    // Validate SL/TP levels
    double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    if(sl - entry_price < min_stop_level || entry_price - tp < min_stop_level) {
        return;
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot_size;
    request.type = ORDER_TYPE_SELL;
    request.price = entry_price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "ICT SMC Sell";
    
    if(OrderSend(request, result)) {
        Print("Sell trade executed: Ticket ", result.order, " Entry: ", entry_price, " SL: ", sl, " TP: ", tp);
        trades_today++;
        
        // Mark OB as used
        ob.is_mitigated = true;
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(bool is_buy, OrderBlock &ob) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Use equity if it's less than balance (account in DD)
    double account_value = MathMin(balance, equity);
    
    // For small accounts, allow higher risk initially
    double risk_percent = RiskPercent;
    if(account_value < 100) {
        // Allow up to MaxDDPercent for very small accounts
        double current_dd = (balance - equity) / balance * 100;
        if(current_dd < MaxDDPercent / 2) {
            risk_percent = MathMin(MaxDDPercent, RiskPercent * 2);
        }
    }
    
    double risk_amount = account_value * risk_percent / 100.0;
    
    // Calculate SL distance
    double entry_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl_price = is_buy ? ob.low - _Point * 20 : ob.high + _Point * 20;
    double sl_distance = MathAbs(entry_price - sl_price);
    
    // Calculate lot size
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lot_size = risk_amount / (sl_distance / tick_size * tick_value);
    
    // Normalize lot size
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    
    // Apply limits
    lot_size = MathMax(lot_size, MinLotSize);
    lot_size = MathMin(lot_size, MaxLotSize);
    lot_size = MathMin(lot_size, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
    
    return NormalizeDouble(lot_size, 2);
}

//+------------------------------------------------------------------+
//| Calculate Take Profit                                          |
//+------------------------------------------------------------------+
double CalculateTP(double entry_price, double sl_price, bool is_buy) {
    double sl_distance = MathAbs(entry_price - sl_price);
    double tp_distance = sl_distance * TPMultiplier;
    
    // Adjust TP based on market structure and nearby levels
    if(is_buy) {
        double tp_price = entry_price + tp_distance;
        
        // Check for resistance levels
        for(int i = 0; i < ArraySize(liquidity_levels); i++) {
            if(liquidity_levels[i].is_high && !liquidity_levels[i].is_swept) {
                if(liquidity_levels[i].price > entry_price && liquidity_levels[i].price < tp_price) {
                    tp_price = liquidity_levels[i].price - _Point * 10;
                    break;
                }
            }
        }
        
        return tp_price;
    } else {
        double tp_price = entry_price - tp_distance;
        
        // Check for support levels
        for(int i = 0; i < ArraySize(liquidity_levels); i++) {
            if(!liquidity_levels[i].is_high && !liquidity_levels[i].is_swept) {
                if(liquidity_levels[i].price < entry_price && liquidity_levels[i].price > tp_price) {
                    tp_price = liquidity_levels[i].price + _Point * 10;
                    break;
                }
            }
        }
        
        return tp_price;
    }
}

//+------------------------------------------------------------------+
//| Draw Order Block                                               |
//+------------------------------------------------------------------+
void DrawOrderBlock(OrderBlock &ob) {
    string obj_name = "ICT_OB_" + TimeToString(ob.time);
    
    ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, ob.time, ob.high, ob.time + 3600, ob.low);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, ob.is_bullish ? OBBuyColor : OBSellColor);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
    
    // Add text label
    string label_name = obj_name + "_Label";
    ObjectCreate(0, label_name, OBJ_TEXT, 0, ob.time, ob.is_bullish ? ob.high : ob.low);
    ObjectSetString(0, label_name, OBJPROP_TEXT, "OB " + (ob.is_bullish ? "Buy" : "Sell"));
    ObjectSetInteger(0, label_name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| Draw Fair Value Gap                                            |
//+------------------------------------------------------------------+
void DrawFVG(FairValueGap &fvg) {
    string obj_name = "ICT_FVG_" + TimeToString(fvg.time);
    
    ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, fvg.time, fvg.high, fvg.time + 1800, fvg.low);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, FVGColor);
    ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, obj_name, OBJPROP_FILL, false);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Create Dashboard                                               |
//+------------------------------------------------------------------+
void CreateDashboard() {
    int x = 20;
    int y = 50;
    int width = 200;
    int height = 20;
    
    // Background panel
    ObjectCreate(0, "Dashboard_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_XDISTANCE, x - 5);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_YDISTANCE, y - 5);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_XSIZE, width + 10);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_YSIZE, height * 8 + 10);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_BGCOLOR, clrBlack);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "Dashboard_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
    
    // Title
    ObjectCreate(0, "Dashboard_Title", OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "Dashboard_Title", OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, "Dashboard_Title", OBJPROP_YDISTANCE, y);
    ObjectSetString(0, "Dashboard_Title", OBJPROP_TEXT, "ICT SMC Dashboard");
    ObjectSetInteger(0, "Dashboard_Title", OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, "Dashboard_Title", OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, "Dashboard_Title", OBJPROP_FONT, "Arial Bold");
    
    // Create labels
    string labels[] = {"Equity:", "HTF Bias:", "Market Structure:", "Trades Today:", "Active OBs:", "Active FVGs:", "Open DD:"};
    
    for(int i = 0; i < ArraySize(labels); i++) {
        ObjectCreate(0, "Dashboard_Label_" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Dashboard_Label_" + IntegerToString(i), OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, "Dashboard_Label_" + IntegerToString(i), OBJPROP_YDISTANCE, y + (i + 1) * height);
        ObjectSetString(0, "Dashboard_Label_" + IntegerToString(i), OBJPROP_TEXT, labels[i]);
        ObjectSetInteger(0, "Dashboard_Label_" + IntegerToString(i), OBJPROP_COLOR, clrLightGray);
        ObjectSetInteger(0, "Dashboard_Label_" + IntegerToString(i), OBJPROP_FONTSIZE, 8);
        
        ObjectCreate(0, "Dashboard_Value_" + IntegerToString(i), OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_XDISTANCE, x + 100);
        ObjectSetInteger(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_YDISTANCE, y + (i + 1) * height);
        ObjectSetInteger(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_FONTSIZE, 8);
    }
}

//+------------------------------------------------------------------+
//| Update Dashboard                                               |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    if(!ShowDashboard) return;
    
    // Count active structures
    int active_obs = 0;
    for(int i = 0; i < ArraySize(order_blocks); i++) {
        if(!order_blocks[i].is_mitigated) active_obs++;
    }
    
    int active_fvgs = 0;
    for(int i = 0; i < ArraySize(fvgs); i++) {
        if(!fvgs[i].is_mitigated) active_fvgs++;
    }
    
    // Calculate DD
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double dd_percent = balance > 0 ? (balance - equity) / balance * 100 : 0;
    
    // Update values
    string values[] = {
        "$" + DoubleToString(equity, 2),
        htf_bias,
        current_market_structure,
        IntegerToString(trades_today),
        IntegerToString(active_obs),
        IntegerToString(active_fvgs),
        DoubleToString(dd_percent, 1) + "%"
    };
    
    for(int i = 0; i < ArraySize(values); i++) {
        ObjectSetString(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_TEXT, values[i]);
        
        // Color coding
        color text_color = clrWhite;
        if(i == 1) { // HTF Bias
            if(htf_bias == "BULLISH") text_color = clrLimeGreen;
            else if(htf_bias == "BEARISH") text_color = clrRed;
        } else if(i == 6) { // DD
            if(dd_percent > 10) text_color = clrRed;
            else if(dd_percent > 5) text_color = clrOrange;
            else text_color = clrLimeGreen;
        }
        ObjectSetInteger(0, "Dashboard_Value_" + IntegerToString(i), OBJPROP_COLOR, text_color);
    }
}