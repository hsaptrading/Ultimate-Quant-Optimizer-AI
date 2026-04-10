//+------------------------------------------------------------------+
//|                                     UltimateDualEA.mq5           |
//|   EA con doble filtro de entrada: Triple EMA + RSI, SL-TP fijo/ATR,|
//|   multiplicador de lote en rachas perdedoras, superposiciones de riesgo,|
//|   y Filtro/Visualizador de Noticias integrado (amigable para tester).|
//|                                                                  |
//|   Autor:  SA TRADING TOOLS                                      |
//|   Notas:                                                         |
//|   - v2.64: Corregido bug de tooltips (OBJPROP_SELECTABLE).       |
//|   - v2.65: Sistema de persistencia para evitar bypass al recompilar. |
//|   - v2.66: Input para Daily Loss Mode (EA only vs All trades). |
//|   - v2.67: Daily Loss considera trades manuales en l?mites de riesgo. |
//|   - v2.68: Sincronizaci?n global entre instancias del EA. |
//|   - v2.69: STATUS cambia a INACTIVE cuando daily loss hit. |
//|   - v2.70: Sincronizaci?n simplificada a 2 modos con l?mite m?nimo. |
//+------------------------------------------------------------------+
#property strict


#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
// Usar la versi?n local del panel para asegurar cambios recientes
#include "UltimateDualPanel.mqh"
#include "UltimateDualButtons.mqh"

// ========================= L?gica de Noticias (Reconstrucci?n) =========================

// Estructura principal para almacenar datos de noticias cargados
struct NewsEvent_EA
{
    datetime time;
    string currency;
    string name;
    int importance;
};
NewsEvent_EA   g_all_news[];
string g_ea_prefix = ""; // Prefijo global y ?nico para todos los objetos del EA.

//+------------------------------------------------------------------+
//| FASE 3: Nueva l?gica de dibujo de l?neas de noticias (Aislada)    |
//+------------------------------------------------------------------+
void UpdateNewsLinesOnChart()
{
    bool is_tester = (MQLInfoInteger(MQL_TESTER) != 0);
    bool debug_news = (is_tester && InpDebug_StatusChanges);
    string line_prefix = "NL_" + (string)InpMagicNumber + "_";
    if(debug_news)
    {
        static int call_count = 0;
        call_count++;
        PrintFormat("[NEWS] Update #%d | mode=%s | events=%d", call_count, EnumToString(g_news_display_mode), ArraySize(g_all_news));
    }
    ObjectsDeleteAll(0, line_prefix, 0, OBJ_VLINE);
    if(!g_show_high_news_lines && !g_show_med_news_lines)
    {
        if(debug_news)
            Print("[NEWS] News buttons OFF -> no lines drawn");
        return;
    }
    datetime now = TimeCurrent();
    datetime past_limit = now - (3 * 24 * 3600);
    datetime future_limit = now + (7 * 24 * 3600);
    string base_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    string quote_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    StringToUpper(base_curr);
    StringToUpper(quote_curr);
    int lines_created = 0;
    for(int i = 0; i < ArraySize(g_all_news); i++)
    {
        NewsEvent_EA event = g_all_news[i];
        if(event.time < past_limit || event.time > future_limit)
            continue;
        string event_curr = event.currency;
        StringToUpper(event_curr);
        if(event_curr != base_curr && event_curr != quote_curr)
            continue;
        bool draw_line = false;
        color line_color = clrNONE;
        int z_order = 0;
        string impact_label = "";
        if(event.importance == 3 && g_show_high_news_lines)
        {
            draw_line = true;
            line_color = HIGH_IMPACT_COLOR;
            z_order = 2;
            impact_label = "HIGH";
        }
        else if(event.importance == 2 && g_show_med_news_lines)
        {
            draw_line = true;
            line_color = MEDIUM_IMPACT_COLOR;
            z_order = 1;
            impact_label = "MEDIUM";
        }
        if(draw_line)
        {
             string event_name_short = event.name;
             if(StringLen(event_name_short) > 30)
                 event_name_short = StringSubstr(event_name_short, 0, 27) + "...";
             string event_datetime = TimeToString(event.time, TIME_DATE|TIME_MINUTES);
             StringReplace(event_datetime, ".", "/");
             string label_text = StringFormat("%s - %s | Impact: %s | Time: %s",
                                 event.currency,
                                 event_name_short,
                                 impact_label,
                                 event_datetime);
             string obj_name = line_prefix + label_text;
            if(ObjectCreate(0, obj_name, OBJ_VLINE, 0, event.time, 0))
            {
                ObjectSetInteger(0, obj_name, OBJPROP_COLOR, line_color);
                ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DOT);
                ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
                ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
                ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, true);
                ObjectSetInteger(0, obj_name, OBJPROP_ZORDER, z_order);
                string tooltip_live = StringFormat("%s - %s\nImpact: %s\nTime: %s",
                                                   event.currency,
                                                   event.name,
                                                   impact_label,
                                                   TimeToString(event.time, TIME_DATE|TIME_MINUTES));
                string tooltip_tester = StringFormat("%s - %s | Impact: %s | Time: %s",
                                                     event.currency,
                                                     event.name,
                                                     impact_label,
                                                     TimeToString(event.time, TIME_DATE|TIME_MINUTES));
                string tooltip_final = is_tester ? tooltip_tester : tooltip_live;
                ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, tooltip_final);
                ObjectSetString(0, obj_name, OBJPROP_TEXT, tooltip_final);
                if(debug_news && lines_created < 5)
                {
                    PrintFormat("[NEWS] Line %d ready | %s | %s", lines_created + 1, obj_name, tooltip_final);
                }
                lines_created++;
            }
            else if(debug_news)
            {
                PrintFormat("[NEWS] Failed to create line for '%s'", obj_name);
            }
        }
    }
    if(debug_news)
        PrintFormat("[NEWS] Lines created: %d", lines_created);
}// =======================================================================================
#property copyright "SA TRADING TOOLS"
#property version   "2.70"

//=====================================================================
// ========================= ENUMERATIONS ==============================
enum ENUM_LOT_SIZING_MODE
{
    Fixed_Lot,      //Fixed Lot
    Risk_Percent    //Risk Percent
};
enum ENUM_LIMIT_MODE
{
    Limit_Off,      //Off
    Limit_Percent,  //Percent
    Limit_Money     //Money
};
enum ENUM_SL_MODE
{
    SL_Fixed_Points,//Fixed Points
    SL_ATR_Based    //ATR Based
};
enum ENUM_EXIT_STRATEGY_MODE
{
    Exit_Strategy_Off,    //Off
    Breakeven_Points,     //Breakeven (Points)
    Trailing_Stop_Points, //Trailing Stop (Points)
    Trailing_Stop_ATR     //Trailing Stop (ATR)
};
enum ENUM_TIME_BASED_CLOSE
{
    TimeClose_Off = 0, //Off
    TimeClose_01 = 1,  //01:00 (Server)
    TimeClose_02 = 2,  //02:00 (Server)
    TimeClose_03 = 3,  //03:00 (Server)
    TimeClose_04 = 4,  //04:00 (Server)
    TimeClose_05 = 5,  //05:00 (Server)
    TimeClose_06 = 6,  //06:00 (Server)
    TimeClose_07 = 7,  //07:00 (Server)
    TimeClose_08 = 8,  //08:00 (Server)
    TimeClose_09 = 9,  //09:00 (Server)
    TimeClose_10 = 10, //10:00 (Server)
    TimeClose_11 = 11, //11:00 (Server)
    TimeClose_12 = 12, //12:00 (Server)
    TimeClose_13 = 13, //13:00 (Server)
    TimeClose_14 = 14, //14:00 (Server)
    TimeClose_15 = 15, //15:00 (Server)
    TimeClose_16 = 16, //16:00 (Server)
    TimeClose_17 = 17, //17:00 (Server)
    TimeClose_18 = 18, //18:00 (Server)
    TimeClose_19 = 19, //19:00 (Server)
    TimeClose_20 = 20, //20:00 (Server)
    TimeClose_21 = 21, //21:00 (Server)
    TimeClose_22 = 22, //22:00 (Server)
    TimeClose_23 = 23  //23:00 (Server) - 1h before rollover
};
enum ENUM_TRADE_DIRECTION
{
    Buys_Only,       //Buys Only
    Sells_Only,      //Sells Only
    Both_Directions  //Both Directions
};
enum ENUM_UNIQUENESS_LEVEL
{
    Unique_Trades_Off,    //Off
    Unique_Trades_Low,    //Low
    Unique_Trades_Medium, //Medium
    Unique_Trades_High    //High
};
enum ENUM_OPTIMIZATION_TIMEFRAME
{
    OPT_H1 = PERIOD_H1,   //H1
    OPT_H4 = PERIOD_H4,   //H4
    OPT_D1 = PERIOD_D1    //D1
};
enum ENUM_MTF_TIMEFRAME
{
    MTF_H1 = PERIOD_H1,   //H1
    MTF_H4 = PERIOD_H4,   //H4
    MTF_D1 = PERIOD_D1    //D1
};
enum ENUM_NEWS_FILTER_MODE
{
    News_Filter_Off,        //Off
    Block_New_Trades_Only,  //Block New Trades Only
    Manage_Open_Trades_Only,//Manage Open Trades Only
    Block_And_Manage        //Block And Manage
};
enum ENUM_NEWS_WINDOW
{
    N2 = 2,     //2 Minutes
    N5 = 5,     //5 Minutes
    N10 = 10,   //10 Minutes
    N15 = 15,   //15 Minutes
    N30 = 30,   //30 Minutes
    N60 = 60,   //60 Minutes
    N120 = 120  //120 Minutes
};
enum ENUM_NEWS_VISUALIZER_MODE
{
    Visualizer_Off,         //Off
    High_Impact_Only,       //High Impact Only
    Medium_Impact_Only,     //Medium Impact Only
    High_And_Medium_Impact  //High And Medium Impact
};
enum ENUM_ENTRY_MODE
{
    Market_Order,         //Market Order
    Delayed_Market_Order  //Delayed Market Order
};
enum ENUM_FAST_EMA { F2=2,F3=3,F4=4,F5=5,F6=6,F7=7,F8=8,F9=9,F10=10,F11=11,F12=12,F13=13,F14=14,F15=15,F16=16,F17=17,F18=18,F19=19,F20=20 };
enum ENUM_MEDIUM_EMA { M20=20,M22=22,M24=24,M26=26,M28=28,M30=30,M32=32,M34=34,M36=36,M38=38,M40=40,M42=42,M44=44,M46=46,M48=48,M50=50,M52=52,M54=54,M56=56,M58=58,M60=60,M62=62,M64=64,M66=66,M68=68,M70=70 };
enum ENUM_SLOW_EMA { S80=80,S85=85,S90=90,S95=95,S100=100,S105=105,S110=110,S115=115,S120=120,S125=125,S130=130,S135=135,S140=140,S145=145,S150=150,S155=155,S160=160,S165=165,S170=170,S175=175,S180=180,S185=185,S190=190,S195=195,S200=200 };
enum ENUM_EMA_RULE
{
    EMA_Trend_Only,         //Trend Only
    EMA_Counter_Trend_Only, //Counter Trend Only
    EMA_Range_Only          //Range Only
};
enum ENUM_RSI_MODE
{
    Overbought_Oversold, //Overbought/Oversold
    Confirm_50_Level     //Confirm 50 Level
};
enum ENUM_RANGE_MODE
{
    Range_Filter_Off, //Off
    EMA_Distance,     //EMA Distance
    ATR_Pips,         //ATR Pips
    ADX_Low           //ADX Low
};
enum ENUM_TREND_METHOD
{
    Trend_Filter_Off, //Off
    ADX_Strong,       //ADX Strong
    ATR_Breakout,     //ATR Breakout
    EMA_Momentum      //EMA Momentum
};
enum ENUM_VOLATILITY_FILTER
{
    Filter_Off = 0,       //Off
    ATR_Only = 1,         //ATR Only
    ADX_Only = 2,         //ADX Only
    ATR_and_ADX = 3       //ATR And ADX
};
enum ENUM_MODE_SETTING
{
    Any = 0,              //Any
    Trend_Only = 1,       //Trend Only
    Counter_Trend_Only = 2, //Counter Trend Only
    Range_Only = 3        //Range Only
};
// Enum con opcion Range solo para Bollinger Bands
enum ENUM_FILTER_MODE_BB
{
    BB_Trend_Only = 0,         //Trend Only
    BB_Counter_Trend_Only = 1, //Counter Trend Only
    BB_Range_Only = 2          //Range Only
};
// Enum sin opcion Range para Keltner, Stochastic, CCI, Fisher
enum ENUM_FILTER_MODE
{
    Filter_Trend_Only = 0,         //Trend Only
    Filter_Counter_Trend_Only = 1  //Counter Trend Only
};
// Enum personalizado para Applied Price con capitalizacion correcta
enum ENUM_PRICE_TYPE
{
    Price_Close = PRICE_CLOSE,       //Close Price
    Price_Open = PRICE_OPEN,         //Open Price
    Price_High = PRICE_HIGH,         //High Price
    Price_Low = PRICE_LOW,           //Low Price
    Price_Median = PRICE_MEDIAN,     //Median Price
    Price_Typical = PRICE_TYPICAL,   //Typical Price
    Price_Weighted = PRICE_WEIGHTED  //Weighted Price
};
enum ENUM_SESSION
{
    All_Session,       //All Sessions
    Asia,              //Asia
    London,            //London
    NY,                //New York
    Asia_and_London,   //Asia And London
    London_and_NY      //London And New York
};
enum ENUM_NEWS_IMPACT_TO_MANAGE
{
    Manage_High_Impact,   //High Impact
    Manage_Medium_Impact, //Medium Impact
    Manage_Both           //Both
};
enum ENUM_TESTING_MODE
{
    TestingMode_Off,              //Testing Disabled
    TestingMode_ForceBypass,      //Force Entries (Bypass Filters)
    TestingMode_RespectFilters    //Force Entries (Respect Filters)
};
// Unified risk scope for daily loss handling
enum ENUM_RISK_SCOPE
{
    Scope_EA_ChartOnly,     //EA Trades (Only Chart Trades)
    Scope_EA_AllCharts,     //EA Trades (All Charts)
    Scope_AllTrades         //All Trades (EA, 3rd Party EA And Manual)
};
//=====================================================================
// ============================ INPUTS ================================
input group "========== GENERAL SETTINGS ==========";
input string               InpLicenseKey = "TRIAL-LICENSE";        // License Key
input string               InpRegisteredEmail = "your.email@gmail.com"; // Registered Email
input long                 InpMagicNumber = 777001;              // Magic Number
input string               InpTradeComment = "UltimateDualEA";     // Trade Comment
input ENUM_TRADE_DIRECTION InpTradeDirection = Both_Directions;  // Trade Direction
input ENUM_OPTIMIZATION_TIMEFRAME InpSignalTF = OPT_H1;             // Chart Timeframe (Single TF Mode)
input bool                 InpUseMultiTimeframe = false;           // Enable Multi-Timeframe Analysis
input ENUM_UNIQUENESS_LEVEL InpUniquenessLevel = Unique_Trades_Off; // Unique Trades
input ENUM_ENTRY_MODE      InpEntryMode = Market_Order;            // Entry Mode
input int                  InpDelayBars = 2;                       // Bars to Wait (Delayed Mode)
input double               InpMinCandleRangePips = 5.0;            // Min Candle Range (Points)
input group "========== RISK MANAGEMENT (STOP LOSS & TAKE PROFIT) ==========";
input ENUM_LOT_SIZING_MODE InpLotSizingMode = Risk_Percent;      // Lot Sizing Mode
input double               InpFixedLot = 0.01;                   // Fixed Lot Size
input double               InpRiskPerTradePct = 1.0;             // Risk Per Trade %
input ENUM_SL_MODE         InpSlMethod = SL_Fixed_Points;        // Stop Loss Method
input double               InpFixedSL_In_Points = 200.0;         // Fixed SL (Points)
input int                  InpAtrSlPeriod = 14;                    // ATR Period for Stop Loss
input double               InpAtrSlMultiplier_SL = 1.5;            // ATR Multiplier for Stop Loss
input double               InpRiskRewardRatio = 1.0;             // Risk Reward Ratio (TP=SL*Ratio)
input ENUM_TIME_BASED_CLOSE InpTimeBasedClose = TimeClose_Off;   // Time-Based Close (Server Time, up to 1h before rollover)
input int                  InpMaxTradesPerSymbol = 2;            // Max Trades Per Symbol (1-3)
input double               InpSecondTradeLotMultiplier = 1.5;    // Second Trade Lot Multiplier (1.0-1.5)
input int                  InpMinBarsAfterLoss = 5;              // Min Bars After Loss Before Re-entry
input int                  InpMinBarsAfterAnyTrade = 2;          // Min Bars After Any Trade
input int                  InpCooldownMinutesAfterClose = 5;     // Cooldown Minutes After Position Close
input double               InpMinDistance_In_Points = 100.0;     // Min Distance Before Re-entry (Points)
input bool                 InpRequireSetupConfirmation = true;   // Require Setup Confirmation for Additional Trades
input int                  InpSlippagePoints = 10;               // Max Slippage (Points)
input double               InpMaxSpreadPoints = 0;               // Max Spread (Points, 0=off)
input group "========== BREAKEVEN & TRAILING STOP ==========";
input ENUM_EXIT_STRATEGY_MODE InpExitStrategyMode = Exit_Strategy_Off; // Exit Strategy Mode
input double               InpBreakevenTriggerPoints = 30.0;       // Breakeven Trigger (Points)
input double               InpBreakevenOffsetPoints = 5.0;         // Breakeven Offset (Points)
input double               InpTrailingStartPoints = 20.0;          // Trailing Start (Points)
input double               InpTrailingStepPoints = 10.0;           // Trailing Step (Points)
input double               InpAtrTrailingMultiplier = 1.0;       // ATR Trailing Multiplier
input int                  InpAtrTrailingPeriod = 14;              // ATR Period for Trailing Stop
input group "========== SETTINGS FOR PROP FIRM ==========";
input ENUM_LIMIT_MODE      InpDailyLossMode = Limit_Percent;     // Daily Loss Limit Mode
input double               InpDailyLossValue = 4.5;              // Daily Loss Limit Value (0=Off, reset after 24H)
input ENUM_RISK_SCOPE      InpRiskScope = Scope_AllTrades;       // Risk Scope for Daily Loss
input ENUM_LIMIT_MODE      InpTotalLossMode = Limit_Percent;     // Total Loss Limit Mode
input double               InpTotalLossValue = 9.5;              // Total Loss Limit Value
input ENUM_LIMIT_MODE      InpDailyProfitMode = Limit_Off;       // Daily Profit Limit Mode
input double               InpDailyProfitValue = 1000.0;         // Daily Profit Limit Value
input int                  InpMaxAccountOpenTrades = 0;          // Max Account Open Trades (0=off)
input double               InpMaxAccountOpenLots = 0.0;          // Max Account Open Lots (0=off)
input bool                 InpUseConsistencyRules = false;       // Enable Consistency Rules
input bool                 InpUseDailyProfitLimit = false;       // Enable Daily Profit Limit
input bool                 InpUseLotSizeLimit = true;            // Enable Lot Size Consistency
input double               InpMaxProfitPerTrade = 2.0;           // Max Profit Per Trade %
input double               InpMaxLotSizePerTrade = 1.0;          // Max Lot Size Per Trade
input group "========== WEEKEND, CORRELATION & HEDGING FILTER ==========";
input bool                 InpUseWeekendManagement = false;      // Enable Weekend Management
input bool                 InpCloseOnFriday = true;              // Close Positions Before Weekend
input int                  InpFridayCloseHour = 20;              // Friday Close Hour
input bool                 InpBlockLateFriday = true;            // Block New Entries Late Friday
input int                  InpFridayBlockHour = 18;              // Friday Block Hour
input bool                 InpBlockOppositeDirections = true;    // Block Opposite Direction Trades (Hedging)
input bool                 InpUseCorrelationFilter = false;      // Use Correlation Filter
input int                  InpMaxCorrelatedPositions = 2;        // Max Positions in Correlated Pairs
input string               InpCorrelatedPairs = "EURUSD,GBPUSD;AUDUSD,NZDUSD;USDCAD,USDCHF"; // Correlated Pairs
//+------------------------------------------------------------------+
//| DEBUG & DIAGNOSTICS                                              |
//+------------------------------------------------------------------+
input group "========== NEWS FILTER ==========";
input ENUM_NEWS_FILTER_MODE InpNewsFilterMode = Block_And_Manage;   // News Filter Mode
input ENUM_NEWS_IMPACT_TO_MANAGE InpNewsImpactToManage = Manage_Both; // News Impact to Manage
input ENUM_NEWS_WINDOW     InpNewsWindowMin = N10;                 // Minutes Before/After News
input int                  InpDaysLookahead = 7;                 // Days to Look Ahead for news
input bool                 InpNewsTimesAreUTC = true;              // News Times are UTC (TESTER)
input int                  InpManualUtcOffset = 0;               // Manual UTC to Server Offset (Hours, TESTER)
input ENUM_NEWS_VISUALIZER_MODE InpNewsVisualizerMode = Visualizer_Off; // News Visualizer Mode (TESTER ONLY)
input group "========== VARIABLE RISK MANAGEMENT (Challenges Only) ==========";
input bool                 InpUseVariableRisk = false;           // Use Variable Risk Management
input double               InpBaseRiskPercent = 1.0;             // Base Risk Per Trade (%)
input double               InpProfitTargetPerLevel = 500.0;      // Profit Target Per Level ($)
input double               InpRiskIncreasePercent = 0.25;        // Risk Increase Per Level (%)
input double               InpMaxRiskPercent = 2.5;              // Maximum Risk Per Trade (%)
input double               InpLossReductionFactor = 0.75;        // Risk Reduction After Loss
input int                  InpReductionTrades = 2;               // Trades to Maintain Reduced Risk
input double               InpDailyLossLimit = 5.0;              // Daily Loss Limit (%)
input group "========== TRADING SESSIONS ==========";
input ENUM_SESSION         InpMondaySession    = All_Session;    // Monday
input ENUM_SESSION         InpTuesdaySession   = All_Session;    // Tuesday
input ENUM_SESSION         InpWednesdaySession = All_Session;    // Wednesday
input ENUM_SESSION         InpThursdaySession  = All_Session;    // Thursday
input ENUM_SESSION         InpFridaySession    = All_Session;    // Friday
input group "========== VOLATILITY FILTER ==========";
input ENUM_VOLATILITY_FILTER InpVolatilityFilter = Filter_Off; // Volatility Filter Mode
input ENUM_MTF_TIMEFRAME   InpAtrTimeframe = MTF_H1;               // ATR Timeframe
input int                  InpAtrPeriod = 14;                      // ATR Period (for Analysis)
input double               InpAtrMinThreshold = 0.0001;             // ATR Min Threshold
input double               InpAtrMaxThreshold = 0.0100;             // ATR Max Threshold
input ENUM_MTF_TIMEFRAME   InpAdxTimeframe = MTF_H1;               // ADX Timeframe
input int                  InpAdxPeriod = 14;                      // ADX Period
input double               InpAdxMinThreshold = 15.0;              // ADX Min Threshold
input double               InpAdxMaxThreshold = 50.0;              // ADX Max Threshold
input group "========== RANGE MARKET SETTINGS (Low Volatility) ==========";
input ENUM_RANGE_MODE      InpRangeMethod = Range_Filter_Off;      // Range Detection Method
input double               InpRangeEmaThresholdPips = 5.0;       // Range EMA Threshold (Points)
input double               InpRangeAtrThresholdPips = 10.0;      // Range ATR Threshold (Points)
input double               InpRangeAdxThreshold = 20.0;          // Range ADX Threshold
input group "========== TREND MARKET SETTINGS (High Volatility) ==========";
input ENUM_TREND_METHOD    InpTrendMethod = Trend_Filter_Off;      // Trend Detection Method
input double               InpTrendAdxThreshold = 30.0;          // Trend ADX Threshold
input double               InpTrendAtrMultiplier = 1.2;          // Trend ATR Breakout Multiplier
input double               InpTrendEmaThreshold = 8.0;           // Trend EMA Momentum Threshold (Points)
input group "========== MARKET ACTIVITY FILTER ==========";
input bool                 InpUseActivityFilter = true;          // Use Market Activity Filter
input int                  InpActivityVolumePeriod = 20;         // Volume Average Period
input double               InpMinActivityMultiple = 1.2;         // Minimum Activity Multiple
input bool                 InpAvoidLowActivity = true;           // Block Trades in Low Activity
input group "========== EMA FILTER ==========";
input bool                 InpUseEmaFilter = true;               // Use EMA Filter
input ENUM_MTF_TIMEFRAME   InpEmaTimeframe = MTF_H1;             // EMA Timeframe
input ENUM_EMA_RULE        InpEmaRule = EMA_Counter_Trend_Only;  // EMA Rule
input ENUM_FAST_EMA        InpFastEmaPeriod = F10;               // Fast EMA Period
input ENUM_MEDIUM_EMA      InpMediumEmaPeriod = M30;             // Medium EMA Period
input ENUM_SLOW_EMA        InpSlowEmaPeriod = S100;              // Slow EMA Period
input group "========== RSI FILTER ==========";
input bool                 InpUseRsiFilter = false;              // Use RSI Filter
input ENUM_MTF_TIMEFRAME   InpRsiTimeframe = MTF_H1;             // RSI Timeframe
input ENUM_RSI_MODE        InpRsiMode = Confirm_50_Level;        // RSI Mode
input int                  InpRsiPeriod = 14;                    // RSI Period
input double               InpRsiOversold = 30.0;                // RSI Oversold Level
input double               InpRsiOverbought = 70.0;              // RSI Overbought Level
input double               InpRsiConfirm = 50.0;                 // RSI Confirmation Level
input group "========== MOMENTUM FILTER (MACD) ==========";
input bool                 InpUseMacdFilter = false;             // Use MACD Filter
input ENUM_MTF_TIMEFRAME   InpMacdTimeframe = MTF_H1;            // MACD Timeframe
input int                  InpMacdFastEMA = 12;                  // MACD Fast EMA
input int                  InpMacdSlowEMA = 26;                  // MACD Slow EMA
input int                  InpMacdSignal = 9;                    // MACD Signal Period
input double               InpMacdMinDivergence = 0.0001;        // Minimum MACD Divergence

input group "========== BOLLINGER BANDS ==========";
input bool                 InpUseBollingerFilter = false;        // Use Bollinger Filter
input ENUM_MTF_TIMEFRAME   InpBollingerTimeframe = MTF_H1;       // Bollinger Timeframe
input ENUM_FILTER_MODE_BB  InpBollingerMode = BB_Trend_Only;     // Bollinger Rule
input int                  InpBollingerPeriod = 20;              // Bollinger Period
input double               InpBollingerDeviation = 2.0;          // Bollinger Deviation
input ENUM_PRICE_TYPE      InpBollingerPrice = Price_Close;      // Bollinger Applied Price

input group "========== KELTNER CHANNEL ==========";
input bool                 InpUseKeltnerFilter = false;          // Use Keltner Filter
input ENUM_MTF_TIMEFRAME   InpKeltnerTimeframe = MTF_H1;         // Keltner Timeframe
input ENUM_FILTER_MODE     InpKeltnerMode = Filter_Trend_Only;   // Keltner Rule
input int                  InpKeltnerPeriod = 20;                // Keltner EMA Period
input int                  InpKeltnerAtrPeriod = 10;             // Keltner ATR Period
input double               InpKeltnerMultiplier = 2.0;            // Keltner Multiplier

input group "========== STANDARD DEVIATION ==========";
input bool                 InpUseStdDevFilter = false;           // Use StdDev Filter
input ENUM_MTF_TIMEFRAME   InpStdDevTimeframe = MTF_H1;          // StdDev Timeframe
input int                  InpStdDevPeriod = 20;                 // StdDev Period
input double               InpStdDevLowThreshold = 0.0005;       // Low Volatility Threshold

input group "========== STOCHASTIC ==========";
input bool                 InpUseStochFilter = false;            // Use Stochastic Filter
input ENUM_MTF_TIMEFRAME   InpStochTimeframe = MTF_H1;           // Stochastic Timeframe
input ENUM_FILTER_MODE     InpStochMode = Filter_Counter_Trend_Only; // Stochastic Rule
input int                  InpStochKPeriod = 5;                  // %K Period
input int                  InpStochDPeriod = 3;                  // %D Period
input int                  InpStochSlowing = 3;                  // Slowing

input group "========== CCI ==========";
input bool                 InpUseCCIFilter = false;              // Use CCI Filter
input ENUM_MTF_TIMEFRAME   InpCCITimeframe = MTF_H1;             // CCI Timeframe
input ENUM_FILTER_MODE     InpCCIMode = Filter_Trend_Only;       // CCI Rule
input int                  InpCCIPeriod = 14;                    // CCI Period
input double               InpCCIExtreme = 100;                  // Extreme Threshold

input group "========== FISHER TRANSFORM ==========";
input bool                 InpUseFisherFilter = false;           // Use Fisher Filter
input ENUM_MTF_TIMEFRAME   InpFisherTimeframe = MTF_H1;          // Fisher Timeframe
input ENUM_FILTER_MODE     InpFisherMode = Filter_Trend_Only;    // Fisher Rule
input int                  InpFisherPeriod = 10;                 // Fisher Period
input double               InpFisherThreshold = 2.0;             // Fisher Threshold

input group "========== PARABOLIC SAR ==========";
input bool                 InpUseSAR = false;                    // Use Parabolic SAR
input double               InpSARStep = 0.02;                    // SAR Step
input double               InpSARMax = 0.2;                      // SAR Maximum

input group "========== DONCHIAN CHANNEL ==========";
input bool                 InpUseDonchian = false;               // Use Donchian Channel
input int                  InpDonchianPeriod = 20;               // Donchian Period
//+------------------------------------------------------------------+
//| TESTING MODE (Tester Only)                                       |
//+------------------------------------------------------------------+
input group "========== TESTING MODE (Tester Only) ==========";
input ENUM_TESTING_MODE InpTestingMode = TestingMode_Off; // Testing Mode Behavior (Tester Only)
input int      InpTestPositions = 3;                // Number of Test Positions to Open
input double   InpTestLotSize = 0.01;               // Test Position Lot Size
input int      InpTestResult = -100;                // Test Position Result ($) - Negative=Loss
input int      InpTestDelayBars = 5;                // Bars to Wait Before Testing
// --- Hedging test helpers (Tester Only) ---
input bool     InpTestOppositeEntry = false;        // After initial test entries, try opposite entry
input int      InpOppositeDelayMinutes = 5;         // Minutes after initial test entries to try opposite
// --- Correlation test helpers (Tester Only) ---
input bool     InpTestCorrelationEnabled = false;   // Enable correlation scenario (multi-symbol)
input string   InpTestCorrelationSymbols = "";      // Symbols to pre-open (comma-separated)
input double   InpTestCorrelationLots = 0.01;       // Lot size for correlation symbols
input bool     InpCorrAlternateDirections = true;   // Alternate BUY/SELL across listed symbols
input int      InpCorrelationAttemptDelayMin = 5;   // Minutes before attempting current-symbol entry
// --- Live on-chart test trades (non-Tester) ---
enum ENUM_LIVE_TEST_DIR { LiveTest_Buy, LiveTest_Sell, LiveTest_BuySell };
input bool     InpOpenLiveTestTrades = false;       // Open live test trades on this chart
input int      InpLiveTestPositions  = 2;           // Number of live test trades to open
input int      InpLiveTestDelayMin   = 5;           // Minutes to wait between live test trades
input ENUM_LIVE_TEST_DIR InpLiveTestDirection = LiveTest_BuySell; // Direction of live test trades
// Hedging/Correlation helpers (defined above)
//+------------------------------------------------------------------+
//| DEBUG & DIAGNOSTICS                                              |
//+------------------------------------------------------------------+
input group "========== DEBUG & DIAGNOSTICS ==========";

input bool InpDebug_Persistence = false;         // [FASE 1] Persistence System (Global Variables)
input bool InpDebug_DailyLossMode = false;       // [FASE 2] Daily Loss Mode/Scope
input bool InpDebug_DailyDdFilters = false;      // Debug: Daily DD filter by chart/comment
input bool InpDebug_ManualTrades = false;        // [FASE 3] Manual Trades Detection
input bool InpDebug_GlobalSync = false;          // [FASE 4] Global Synchronization
input bool InpDebug_StatusChanges = false;       // [FASE 6] STATUS Changes & Reset
input bool InpDebug_RiskLimits = false;          // [RISK] Daily/Total Loss Limit Events
input bool     InpDebugTestingMode = false;         // Debug: Show Testing Mode Details
//=====================================================================
// ========================= GLOBAL STATE ============================
CTrade              trade;
CPositionInfo       pos;
CUltimateDualPanel  g_panel;
CUltimateDualButtons g_buttons;
bool g_panel_visible = true;
ENUM_NEWS_VISUALIZER_MODE g_news_display_mode = Visualizer_Off;
bool g_show_high_news_lines = false;
bool g_show_med_news_lines = false;
double g_manual_button_lot = 0.01;
int hEMA_Fast = INVALID_HANDLE, hEMA_Med = INVALID_HANDLE, hEMA_Slow = INVALID_HANDLE;
int hEMA_Keltner = INVALID_HANDLE;
int hRSI = INVALID_HANDLE, hATR = INVALID_HANDLE, hADX = INVALID_HANDLE, hMACD = INVALID_HANDLE;
int hATR_Keltner = INVALID_HANDLE;
int hBollinger = INVALID_HANDLE, hStdDev = INVALID_HANDLE, hStochastic = INVALID_HANDLE;
int hCCI = INVALID_HANDLE, hSAR = INVALID_HANDLE;
double g_fisher_buffer[];
double g_fisher_price[];
string g_comment_override = ""; // optional override for EA comment (e.g., live test)
// --- Uniqueness Actual Values ---
int g_actualFastEmaPeriod, g_actualMediumEmaPeriod, g_actualSlowEmaPeriod, g_actualRsiPeriod;
double g_actualAtrSlMultiplier, g_actualRiskRewardRatio, g_actualFixedSlPoints;
int g_actualMacdFastEMA, g_actualMacdSlowEMA, g_actualMacdSignal, g_actualAtrPeriod, g_actualAdxPeriod;
double g_actualRangeAdxThreshold, g_actualTrendAdxThreshold;
// --- Risk Management State ---
int g_lastDay = -1;
double g_dailyStartBalance = 0.0, g_dailyStartEquity = 0.0, g_totalStartEquity = 0.0, g_initialEquity = 0.0;
bool g_isEaStopped = false;
datetime g_resetTime = 0;
// --- Live test trades (non-Tester) ---
bool     g_live_test_active_prev = false;
int      g_live_test_opened = 0;
datetime g_live_test_last_open = 0;
// --- Consistency Rules State ---
double g_dailyProfitAccum = 0.0;
int    g_lastConsistencyDay = -1;
// --- News & TP Management ---
struct TPManagement {
   long ticket;
   string symbol;
   double tp_original;
   datetime saved_time;
   bool is_removed;
};
TPManagement g_tp_management[];
datetime g_last_tp_check = 0;
int g_tp_status = 0; // 0=OK, 1=Removed, 2=Restored
int g_tp_status_state = 0; // For panel display state
datetime g_tp_restored_end_time = 0;
// --- Timers & State Management ---
datetime g_last_trailing_check = 0, g_last_trade_time = 0, g_last_position_close_time = 0;
datetime g_last_time_close_day = 0;
bool g_last_close_was_loss = false;
// --- Indicator Cache ---
struct IndicatorCache { double emaF, emaM, emaS, rsi, atr, adx, macd; datetime last_update; bool is_valid; };
IndicatorCache g_indicator_cache;
// --- Variable Risk Management ---
// --- Testing Mode State ---
struct TestingModeConfig
{
    int    positions;
    double lot_size;
    int    target_result;
    int    delay_bars;
    bool   opposite_entry;
    int    opposite_delay_min;
    bool   correlation_enabled;
    string correlation_symbols;
    double correlation_lots;
    bool   correlation_alternate;
    int    correlation_attempt_delay_min;
    bool   bypass_filters;
};
TestingModeConfig g_testing_cfg;
string g_testing_label = "[TESTING MODE]";
bool g_testing_mode_active = false;
bool g_test_positions_opened = false;
int g_test_bar_counter = 0;
datetime g_last_test_bar = 0;
double CurrentRiskLevel = 0.0;
int ConsecutiveLosses = 0, ReductionTradesRemaining = 0;
bool DailyLimitReached = false;
// Hedging test state (Tester Only)
bool g_test_opp_pending = false;
datetime g_test_opp_time = 0;
bool g_test_opp_done = false;
// Correlation test state (Tester Only)
bool g_corr_test_started = false;
bool g_corr_attempt_scheduled = false;
datetime g_corr_attempt_time = 0;
bool g_corr_attempt_done = false;
// Impacto acumulado de operaciones manuales (solo para l?mites de riesgo)
double g_manual_trades_impact_today = 0.0;
// Estado diario: si se alcanz? el l?mite de p?rdida diaria
bool g_daily_loss_was_reached = false;  // Tracks if daily loss was hit today
double g_cached_global_trigger_ts = 0.0;
string g_cached_global_trigger_symbol = "";
double g_cached_ea_trigger_ts = 0.0;
string g_cached_ea_trigger_symbol = "";
string g_cached_ea_trigger_key = "";
// --- Delayed Entry Management ---
struct DelayedSignal { int signal; datetime first_seen; int bars_waited; double entry_price; bool is_active; };
DelayedSignal g_delayed_signal;
// ======================= PROTOTYPES =========================
void UpdatePanelData();
bool AllTradeConditionsMet(int signal, double lots, double sl_points);
bool EvaluateTradeConditions(int signal, double lots, double sl_points, string &reason);
bool IsCorrelationOK_Check(string &reason);
void GetEAGroupDailyPL(bool only_chart, double &daily_pl, double &daily_pl_pct, double &daily_dd, double &daily_dd_pct);
string GetEAGroupKey();
double GetLowestEAGlobalDailyLimit();
bool IsEAGlobalDailyLossReached();
void SetEAGlobalDailyLossFlag();
void ResetTestingHelperState();
bool ActivateTestingMode();
double CalculateTestingPoints();
bool CreateTestingPosition(int signal, double points_for_result, const string &order_comment);
double DetermineSLPoints();
bool CanOpenAdditionalTrade(int signal, string &reason);
bool HasOppositeDirectionTrade(int signal, string &reason);
bool GlobalLimitsOK(double lots_of_this_trade, string &reason);
bool CheckConsistencyRules(double planned_lot_size, double sl_points, string &reason);
bool IsCooldownAfterCloseActive(double &remaining_minutes);
void ManageTimeBasedClose();
int GetTimeBasedCloseHour();
string FormatCountdown(datetime target_time);
string ResolveTriggerSymbol(const string prefix, double timestamp);
string GetGlobalTriggerSymbol(double timestamp);
string GetEATriggerSymbol(const string key, double timestamp);
datetime ComputeNextResetTime(datetime reference_time);
void ExecuteDailyLossStop(double dd_value, double dd_pct_value);
void TogglePanelVisibility();
void ToggleNewsHighLines();
void ToggleNewsMedLines();
void CloseAllPositionsEmergency();
void ManualButtonOrder(const int signal);
void LoadPanelState();
void SavePanelState();
string GetPanelStateKey();
void LoadNewsModeState();
void SaveNewsModeState();
string GetNewsModeKey();
void ApplyNewsMode(ENUM_NEWS_VISUALIZER_MODE mode);
void SetNewsModeFromFlags(bool high,bool med);
// ======================= UTILITY FUNCTIONS =========================
//+------------------------------------------------------------------+
//| Global Variable Management for Multi-Instance Sync               |
//+------------------------------------------------------------------+
string GetGlobalVarPrefix()
{
    // Kept for backward compatibility; account-wide uses fixed prefix now
    return "ACCOUNT_GLOBAL_";
}

// ===== EA group (same EA across charts) helpers =====
string GetEAGroupKey()
{
    string key = InpTradeComment;
    if(key == "") key = "UDEA";
    StringToUpper(key);
    // Sanitize to alnum underscore only
    string cleaned = "";
    for(int i=0;i<StringLen(key);i++)
    {
        ushort ch = StringGetCharacter(key, i);
        if((ch >= 65 && ch <= 90) || (ch >= 48 && ch <= 57) || ch==95)
            cleaned += CharToString((uchar)ch);
    }
    if(cleaned == "") cleaned = "UDEA";
    return cleaned;
}

// Build EA comment with ChartID suffix in Chart Only scope
string GetEAComment()
{
    string comment = (g_comment_override != "") ? g_comment_override : InpTradeComment;
    if(comment == "") comment = "UltimateDualEA";
    if(InpRiskScope == Scope_EA_ChartOnly)
    {
        string suffix = "_C" + (string)ChartID();
        if(StringFind(comment, suffix) < 0)
            comment += suffix;
    }
    return comment;
}

// Check if a position/comment belongs to this chart (magic + symbol + comment/suffix)
bool IsPositionFromThisChart(long magic, const string &symbol, const string &comment)
{
    if(magic != InpMagicNumber) return false;
    if(symbol != _Symbol) return false;

    string comment_up = comment;      StringToUpper(comment_up);
    string base_up = InpTradeComment; StringToUpper(base_up);
    string suffix = "_C" + (string)ChartID();
    string suffix_up = suffix;        StringToUpper(suffix_up);

    // Priority: exact suffix match
    if(StringFind(comment_up, suffix_up) >= 0)
        return true;

    bool has_suffix = (StringFind(comment, "_C") >= 0);

    // If base comment coincide, aceptar aunque el sufijo sea distinto (re-attach chart)
    if(base_up != "" && StringFind(comment_up, base_up) >= 0)
        return true;

    // Legacy: sin sufijo y sin base
    if(!has_suffix && base_up == "")
        return true;

    return false;
}

double GetLowestEAGlobalDailyLimit()
{
    string key = GetEAGroupKey();
    string active_name = "EA_GLOBAL_" + key + "_ActiveLimits";
    if(!GlobalVariableCheck(active_name)) return 0.0;
    double lowest_limit = 999999.0; bool found = false;
    for(int i=0;i<10;i++)
    {
        string var_name = "EA_GLOBAL_" + key + "_Limit_" + (string)i;
        if(GlobalVariableCheck(var_name))
        {
            double limit = GlobalVariableGet(var_name);
            if(limit > 0 && limit < lowest_limit) { lowest_limit = limit; found = true; }
        }
    }
    return found ? lowest_limit : 0.0;
}

void RegisterEAGlobalDailyLimit()
{
    if(InpRiskScope != Scope_EA_AllCharts) return;
    if(InpDailyLossMode == Limit_Off || InpDailyLossValue <= 0) return;
    string key = GetEAGroupKey();
    long chart_id = ChartID();
    string var_name = "EA_GLOBAL_" + key + "_Limit_" + (string)(chart_id % 10);
    GlobalVariableSet(var_name, InpDailyLossValue);
    GlobalVariableSet("EA_GLOBAL_" + key + "_ActiveLimits", 1.0);
    if(InpDebug_GlobalSync)
        PrintFormat("[EA SYNC] Registered EA-group limit (key=%s): %.2f%%", key, InpDailyLossValue);
}

bool IsEAGlobalDailyLossReached()
{
    string key = GetEAGroupKey();
    string name = "EA_GLOBAL_" + key + "_LossFlag";
    return (GlobalVariableCheck(name) && GlobalVariableGet(name) > 0.5);
}

void SetEAGlobalDailyLossFlag()
{
    if(InpRiskScope != Scope_EA_AllCharts) return;
    string key = GetEAGroupKey();
    GlobalVariableSet("EA_GLOBAL_" + key + "_LossFlag", 1.0);
}

string FormatCountdown(datetime target_time)
{
    if(target_time <= 0) return "";
    long seconds_remaining = (long)(target_time - TimeCurrent());
    if(seconds_remaining <= 0) return "00:00:00";
    long hours = seconds_remaining / 3600;
    long minutes = (seconds_remaining % 3600) / 60;
    long secs = seconds_remaining % 60;
    return StringFormat("%02d:%02d:%02d", (int)hours, (int)minutes, (int)secs);
}

datetime ComputeNextResetTime(datetime reference_time)
{
    datetime base = (reference_time > 0) ? reference_time : TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(base, dt);
    dt.day += 1;
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    return StructToTime(dt);
}

string ResolveTriggerSymbol(const string prefix, double timestamp)
{
    if(timestamp <= 0.0) return "";
    int total = GlobalVariablesTotal();
    int prefix_len = StringLen(prefix);
    for(int i = 0; i < total; i++)
    {
        string name = GlobalVariableName(i);
        if(StringLen(name) <= prefix_len) continue;
        if(StringSubstr(name, 0, prefix_len) != prefix) continue;
        double stored = GlobalVariableGet(name);
        if(MathAbs(stored - timestamp) < 0.5)
            return StringSubstr(name, prefix_len);
    }
    return "";
}

string GetGlobalTriggerSymbol(double timestamp)
{
    if(timestamp <= 0.0) return "";
    if(MathAbs(timestamp - g_cached_global_trigger_ts) < 0.5 && g_cached_global_trigger_symbol != "")
        return g_cached_global_trigger_symbol;
    string sym = ResolveTriggerSymbol("ACCOUNT_GLOBAL_TriggerSymbol_", timestamp);
    if(sym != "")
    {
        g_cached_global_trigger_ts = timestamp;
        g_cached_global_trigger_symbol = sym;
    }
    return sym;
}

string GetEATriggerSymbol(const string key, double timestamp)
{
    if(timestamp <= 0.0) return "";
    if(g_cached_ea_trigger_key == key && MathAbs(timestamp - g_cached_ea_trigger_ts) < 0.5 && g_cached_ea_trigger_symbol != "")
        return g_cached_ea_trigger_symbol;
    string prefix = "EA_GLOBAL_" + key + "_TriggerSymbol_";
    string sym = ResolveTriggerSymbol(prefix, timestamp);
    if(sym != "")
    {
        g_cached_ea_trigger_key = key;
        g_cached_ea_trigger_ts = timestamp;
        g_cached_ea_trigger_symbol = sym;
    }
    return sym;
}

// Calculate EA-group daily PL/DD (realized + floating), relative to account start balance
void GetEAGroupDailyPL(bool only_chart, double &daily_pl, double &daily_pl_pct, double &daily_dd, double &daily_dd_pct)
{
    daily_pl = 0.0; daily_pl_pct = 0.0; daily_dd = 0.0; daily_dd_pct = 0.0;
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    datetime day_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
    HistorySelect(day_start, TimeCurrent());
    string key = GetEAGroupKey();
    // Closed deals
    for(int i=0;i<HistoryDealsTotal();i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
        long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
        string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
        string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
        bool match = false;
        if(only_chart)
            match = IsPositionFromThisChart(magic, symbol, comment);
        else
        {
            // Consider same EA across charts by comment or magic
            if(magic == InpMagicNumber) match = true;
            if(!match && InpTradeComment != "" && StringFind(comment, InpTradeComment) >= 0) match = true;
        }
        if(InpDebug_DailyDdFilters && only_chart)
            PrintFormat("[DD-CHK][CLOSED] #%I64u %s | Magic=%I64d | Comment='%s' | Match=%s",
                        ticket, symbol, magic, comment, match ? "YES" : "NO");
        if(match)
        {
            double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                     + HistoryDealGetDouble(ticket, DEAL_SWAP)
                     + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            daily_pl += p;
        }
    }
    if(InpDebug_DailyDdFilters && only_chart)
        PrintFormat("[DD-DEBUG][CLOSED] Symbol=%s | Magic=%d | PL=%.2f", _Symbol, InpMagicNumber, daily_pl);
    // Floating PL
    for(int j=0;j<PositionsTotal();j++)
    {
        if(!pos.SelectByIndex(j)) continue;
        long magic = (long)pos.Magic();
        string symbol = pos.Symbol();
        string comment = pos.Comment();
        bool match = false;
        if(only_chart)
            match = IsPositionFromThisChart(magic, symbol, comment);
        else
        {
            if(magic == InpMagicNumber) match = true;
            if(!match && InpTradeComment != "" && StringFind(comment, InpTradeComment) >= 0) match = true;
        }
        if(InpDebug_DailyDdFilters && only_chart)
            PrintFormat("[DD-CHK][OPEN]   #%I64u %s | Magic=%I64d | Comment='%s' | Match=%s | PL=%.2f",
                        pos.Ticket(), symbol, magic, comment, match ? "YES" : "NO", pos.Profit());
        if(match) daily_pl += pos.Profit();
    }
    if(InpDebug_DailyDdFilters && only_chart)
        PrintFormat("[DD-DEBUG][FLOAT] Symbol=%s | Magic=%d | PL=%.2f", _Symbol, InpMagicNumber, daily_pl);
    if(daily_pl >= 0.0)
    {
        daily_dd = 0.0; daily_dd_pct = 0.0;
        daily_pl_pct = (g_dailyStartBalance > 0) ? (daily_pl / g_dailyStartBalance) * 100.0 : 0.0;
    }
    else
    {
        daily_dd = -daily_pl;
        daily_dd_pct = (g_dailyStartBalance > 0) ? (daily_dd / g_dailyStartBalance) * 100.0 : 0.0;
        daily_pl = 0.0; daily_pl_pct = 0.0;
    }
}

bool IsGlobalDailyLossReached()
{
    // Account-wide global flag (set by any instance running Scope_AllTrades)
    string var_name = "ACCOUNT_GLOBAL_LossFlag";
    return (GlobalVariableCheck(var_name) && GlobalVariableGet(var_name) > 0.5);
}

void SetGlobalDailyLossFlag()
{
    if(InpRiskScope != Scope_AllTrades) return;
    GlobalVariableSet("ACCOUNT_GLOBAL_LossFlag", 1.0);
}

void ResetGlobalDailyVariables()
{
    // Keep compatibility: reset account-wide variables if present
    GlobalVariableSet("ACCOUNT_GLOBAL_DailyStart", AccountInfoDouble(ACCOUNT_BALANCE));
    GlobalVariableSet("ACCOUNT_GLOBAL_DailyPL", 0.0);
    GlobalVariableSet("ACCOUNT_GLOBAL_LossFlag", 0.0);
    GlobalVariableSet("ACCOUNT_GLOBAL_TriggerTimestamp", 0.0);
    GlobalVariablesDeleteAll("ACCOUNT_GLOBAL_TriggerSymbol_");
}

// Returns the lowest active global daily loss limit among All Charts instances
double GetLowestGlobalDailyLimit()
{
    if(!GlobalVariableCheck("ACCOUNT_GLOBAL_ActiveLimits"))
        return 0.0;  // No global mode active
    double lowest_limit = 999999.0;
    bool found_limit = false;
    for(int i = 0; i < 10; i++)
    {
        string var_name = "ACCOUNT_GLOBAL_Limit_" + (string)i;
        if(GlobalVariableCheck(var_name))
        {
            double limit = GlobalVariableGet(var_name);
            if(limit > 0 && limit < lowest_limit)
            {
                lowest_limit = limit;
                found_limit = true;
            }
        }
    }
    return found_limit ? lowest_limit : 0.0;
}

void RegisterGlobalDailyLimit()
{
    if(InpRiskScope != Scope_AllTrades) return;
    if(InpDailyLossMode == Limit_Off || InpDailyLossValue <= 0) return;
    long chart_id = ChartID();
    string var_name = "ACCOUNT_GLOBAL_Limit_" + (string)(chart_id % 10);
    double limit_value = InpDailyLossValue;
    GlobalVariableSet(var_name, limit_value);
    GlobalVariableSet("ACCOUNT_GLOBAL_ActiveLimits", 1.0);
    if(InpDebug_GlobalSync)
    {
        PrintFormat("[GLOBAL SYNC] Registered account-wide daily limit: %.2f%%", limit_value);
        PrintFormat("[GLOBAL SYNC] Lowest active limit: %.2f%%", GetLowestGlobalDailyLimit());
    }
}
//+------------------------------------------------------------------+
//|  Calculates Daily P&L and DD by reconstructing the day's start  |
//+------------------------------------------------------------------+
void CalculateDailyPerformance(double &daily_pl, double &daily_pl_pct, double &daily_dd, double &daily_dd_pct)
{
    // --- START: FIX FOR STRATEGY TESTER ---
    // In the tester, history-based reconstruction can be unreliable at the start.
    // We use the globally managed 'g_dailyStartBalance' for a stable calculation.
    // This logic is isolated to the tester to avoid any impact on live trading.
    if(MQLInfoInteger(MQL_TESTER))
    {
        double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Calculate P/L based on the stable start-of-day balance
        daily_pl = current_equity - g_dailyStartBalance;
        
        // Separate the result into Profit or Drawdown
        if(daily_pl >= 0)
        {
            daily_dd = 0.0;
            daily_dd_pct = 0.0;
            daily_pl_pct = (g_dailyStartBalance > 0) ? (daily_pl / g_dailyStartBalance) * 100.0 : 0.0;
        }
        else // It's a loss
        {
            daily_dd = -daily_pl;
            daily_dd_pct = (g_dailyStartBalance > 0) ? (daily_dd / g_dailyStartBalance) * 100.0 : 0.0;
            daily_pl = 0.0;
            daily_pl_pct = 0.0;
        }
        
        // Exit here for tester mode
        return;
    }
    // --- END: FIX FOR STRATEGY TESTER ---

    // The original robust logic for LIVE trading remains completely untouched below.

    // 1. Define the start of the current day (server time)
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime day_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
    
    // 2. Request the deal history for the current day
    if(!HistorySelect(day_start, TimeCurrent()))
    {
        Print("Error selecting deal history for today.");
        return;
    }
    
    // 3. Calculate the total impact of all balance-altering transactions for today
    double closed_trades_impact_today = 0.0;
    double non_trading_impact_today = 0.0;
    // Reiniciar el contador de trades manuales para este c?lculo del d?a
    g_manual_trades_impact_today = 0.0;
    
    if(InpDebug_DailyLossMode)
    {
        Print("--- Daily P&L Diagnostic Report ---");
    }
    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
        
        double current_deal_impact = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                                     HistoryDealGetDouble(ticket, DEAL_COMMISSION) + 
                                     HistoryDealGetDouble(ticket, DEAL_SWAP);

        if(deal_type == DEAL_TYPE_BUY || deal_type == DEAL_TYPE_SELL)
        {
            // Always include in account-wide calculation; track manual impact for diagnostics
            bool include_deal = true;
            long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if(deal_magic != InpMagicNumber)
            {
                g_manual_trades_impact_today += current_deal_impact;
                if(InpDebug_ManualTrades)
                    PrintFormat("[FASE 3] Manual/Other EA trade: Deal #%i, Magic=%d, Impact=$%.2f", i, deal_magic, current_deal_impact);
            }
            
            if(include_deal)
            {
                closed_trades_impact_today += current_deal_impact;
                if(InpDebug_DailyLossMode)
                {
                    long deal_magic2 = HistoryDealGetInteger(ticket, DEAL_MAGIC);
                    PrintFormat("[FASE 2] Deal #%i: Magic=%d, Impact=$%.2f, Included=Yes (Accum=$%.2f)", 
                                i, (int)deal_magic2, current_deal_impact, closed_trades_impact_today);
                }
            }
        }
        else if (deal_type == DEAL_TYPE_BALANCE)
        {
            non_trading_impact_today += current_deal_impact;
            if(InpDebug_DailyLossMode)
            {
                PrintFormat("  [Balance Deal #%i] Impact: %.2f (Accumulated: %.2f)", 
                            i, current_deal_impact, non_trading_impact_today);
            }
        }
    }
    
    // 4. Reconstruct the balance at the start of the day
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double daily_start_balance = current_balance - (closed_trades_impact_today + non_trading_impact_today);
    
    // 5. Calculate Daily P&L
    double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    daily_pl = current_equity - daily_start_balance;
    
    // 6. Calculate P&L Percentage
    daily_pl_pct = (daily_start_balance > 0) ? (daily_pl / daily_start_balance) * 100.0 : 0.0;
    
    // --- Nueva l?gica simple: O Profit O DD, nunca ambos ---
    if(daily_pl >= 0)
    {
        daily_dd = 0.0;
        daily_dd_pct = 0.0;
    }
    else
    {
        daily_dd = -daily_pl;
        daily_dd_pct = -daily_pl_pct;
        daily_pl = 0.0;
        daily_pl_pct = 0.0;
    }
    
    // Debug diagn?stico espec?fico
    if(InpDebug_DailyLossMode)
    {
        double total_floating = 0.0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(pos.SelectByIndex(i) && (long)pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol)  
            {
                total_floating += pos.Profit() + pos.Swap();
            }
        }
        string scope_str = (InpRiskScope == Scope_AllTrades) ? "All Trades" : (InpRiskScope == Scope_EA_AllCharts ? "EA All Charts" : "EA Chart");
        PrintFormat("[FASE 2] Daily Loss Scope: %s", scope_str);
        Print("===== DAILY PROFIT DIAGNOSTIC =====");
        PrintFormat("1. Current Balance:      $%.2f", current_balance);
        PrintFormat("2. Closed Trades Impact: $%.2f", closed_trades_impact_today);
        PrintFormat("3. Non-Trading Impact:   $%.2f", non_trading_impact_today);
        PrintFormat("4. Calculated Start Bal: $%.2f (Balance - All Impacts)", daily_start_balance);
        PrintFormat("5. Current Equity:       $%.2f", current_equity);
        PrintFormat("6. Total Floating P/L:   $%.2f", total_floating);
        PrintFormat("7. FINAL Daily Profit:   $%.2f (%.2f%%)", daily_pl, daily_pl_pct);
        PrintFormat("8. VERIFICATION (P/L):   $%.2f (Closed Trades + Floating)", closed_trades_impact_today + total_floating);
        Print("===================================");
    }
}
void UpdateDailyMetrics()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day != g_lastDay)
    {
       g_lastDay = dt.day;
        g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_manual_trades_impact_today = 0.0;
       
       // Reset global variables for new day
       ResetGlobalDailyVariables();
       // Reset global loss flag and re-register active limit
        if(GlobalVariableCheck("ACCOUNT_GLOBAL_LossFlag"))
            GlobalVariableSet("ACCOUNT_GLOBAL_LossFlag", 0.0);
        GlobalVariableSet("ACCOUNT_GLOBAL_TriggerTimestamp", 0.0);
        GlobalVariablesDeleteAll("ACCOUNT_GLOBAL_TriggerSymbol_");
        RegisterGlobalDailyLimit();
       
       if(false)
           PrintFormat("[DAILY RESET] Day changed to %d, balance: %.2f", dt.day, g_dailyStartBalance);
       
        // Reset daily loss reached flag and local stop/reset times
        g_daily_loss_was_reached = false;
        g_isEaStopped = false;
        g_resetTime = 0;
        // Clear per-magic/chart stop GV
        string stop_var = "UDEA_M" + (string)InpMagicNumber + "_C" + (string)ChartID() + "_IsEaStopped";
        if(GlobalVariableCheck(stop_var)) GlobalVariableDel(stop_var);
        // Clear group/account flags (new day)
        if(GlobalVariableCheck("ACCOUNT_GLOBAL_LossFlag")) GlobalVariableSet("ACCOUNT_GLOBAL_LossFlag", 0.0);
        if(InpRiskScope == Scope_EA_AllCharts)
        {
            string key = GetEAGroupKey();
            if(GlobalVariableCheck("EA_GLOBAL_"+key+"_LossFlag")) GlobalVariableSet("EA_GLOBAL_"+key+"_LossFlag", 0.0);
            if(GlobalVariableCheck("EA_GLOBAL_"+key+"_TriggerTimestamp")) GlobalVariableSet("EA_GLOBAL_"+key+"_TriggerTimestamp", 0.0);
            GlobalVariablesDeleteAll("EA_GLOBAL_"+key+"_TriggerSymbol_");
        }
    }
}
double GetClosedProfitToday(){    MqlDateTime dt;    TimeToStruct(TimeCurrent(), dt);    datetime day_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));        HistorySelect(day_start, TimeCurrent());        double total_closed = 0.0;    for(int i = 0; i < HistoryDealsTotal(); i++)    {        ulong ticket = HistoryDealGetTicket(i);                if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)        {            total_closed += HistoryDealGetDouble(ticket, DEAL_PROFIT);            total_closed += HistoryDealGetDouble(ticket, DEAL_SWAP);            total_closed += HistoryDealGetDouble(ticket, DEAL_COMMISSION);        }    }        return total_closed;}
string GetCorrelationStatusString()
{
    if(!InpUseCorrelationFilter) return "OFF";
    string groups[];
    int group_count = StringSplit(InpCorrelatedPairs, ';', groups);
    for(int g = 0; g < group_count; g++)
    {
       string pairs_in_group[];
       StringSplit(groups[g], ',', pairs_in_group);
       bool symbol_in_group = false;
       for(int p = 0; p < ArraySize(pairs_in_group); p++)
       {
          StringTrimLeft(pairs_in_group[p]);
          StringTrimRight(pairs_in_group[p]);
          if(pairs_in_group[p] == _Symbol) { symbol_in_group = true; break; }
       }
       if(symbol_in_group)
       {
          int positions_in_group = 0;
          for(int i = 0; i < PositionsTotal(); i++)
          {
             if(pos.SelectByIndex(i) && (long)pos.Magic() == InpMagicNumber)
             {
                for(int p = 0; p < ArraySize(pairs_in_group); p++)
                {
                   if(pairs_in_group[p] == pos.Symbol()) { positions_in_group++; break; }
                }
             }
          }
          return StringFormat("%d/%d", positions_in_group, InpMaxCorrelatedPositions);
       }
    }
    return "N/A";
}
int GetPipPointsMultiplier() { return 1; }
double ATRtoPips(double atr_price) { return (atr_price / _Point) / GetPipPointsMultiplier(); }
bool IsRangeEMA(double efast, double emed, double eslow, double threshold_pips)
{
    double maxd = MathMax(MathAbs(efast - emed), MathAbs(emed - eslow));
    return ((maxd / _Point) / GetPipPointsMultiplier()) <= threshold_pips;
}
double CalcLotsByRisk(double sl_points)
{
    double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lots = InpFixedLot;
    double final_sl_points = sl_points;
    if (OpenPositionsCount() > 0 && InpSlMethod == SL_ATR_Based)
    {
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && (long)pos.Magic() == InpMagicNumber)
            {
                final_sl_points = MathAbs(pos.PriceOpen() - pos.StopLoss()) / _Point;
                if(false) PrintFormat("[ATR MULTI-TRADE] Using SL of first trade (%.1f points) for lot calc.", final_sl_points);
                break;
            }
        }
    }
    if(InpLotSizingMode == Risk_Percent)
     {
        double money_per_tick_per_lot = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        if(final_sl_points > 0.0 && money_per_tick_per_lot > 0.0)
        {
           double equity = AccountInfoDouble(ACCOUNT_EQUITY);
           double actual_risk_pct = CalculateVariableRisk();
           if(actual_risk_pct <= 0.0) return 0.0;
           double risk_money = equity * (actual_risk_pct / 100.0);
           double stop_money_per_lot = final_sl_points * money_per_tick_per_lot;
           if(false) PrintFormat("Risk Calc: Eq:%.2f, Risk$:%.2f, SL_Pts:%.2f, TickVal:%.4f, Risk/Lot:%.2f", equity, risk_money, final_sl_points, money_per_tick_per_lot, stop_money_per_lot);
           lots = (stop_money_per_lot > 0.0) ? risk_money / stop_money_per_lot : InpFixedLot;
        }
     }
    if(OpenPositionsCount() > 0 && InpSecondTradeLotMultiplier != 1.0)
     {
        lots *= InpSecondTradeLotMultiplier;
        if(false) PrintFormat("[MULTI-TRADE] Applied lot multiplier %.2f for trade #%d", InpSecondTradeLotMultiplier, OpenPositionsCount() + 1);
     }
    if(vol_step <= 0.0) vol_step = 0.01;
    lots = MathMax(vol_min, MathMin(vol_max, MathFloor(lots/vol_step)*vol_step));
    if(lots < vol_min || lots > vol_max)
    {
        PrintFormat("Error: Calculated lot size (%.2f) is outside allowed range (Min: %.2f, Max: %.2f) for %s.", lots, vol_min, vol_max, _Symbol);
        return 0.0;
    }
    return lots;
}
double CalculateVariableRisk()
{
    if(!InpUseVariableRisk) return InpRiskPerTradePct;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day != g_lastDay || g_dailyStartBalance <= 0.0)
     {
        g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        DailyLimitReached = false;
     }
    double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double daily_loss_pct = ((g_dailyStartBalance - current_balance) / g_dailyStartBalance) * 100.0;
    if(daily_loss_pct >= InpDailyLossLimit)
     {
        DailyLimitReached = true;
        if(false) PrintFormat("[VARIABLE RISK] Daily loss limit reached: %.2f%%", daily_loss_pct);
        return 0.0;
     }
    int current_level = (int)MathFloor((current_balance - g_dailyStartBalance) / InpProfitTargetPerLevel);
    current_level = MathMax(0, current_level);
    double risk_percent = InpBaseRiskPercent + (current_level * InpRiskIncreasePercent);
    if(ReductionTradesRemaining > 0)
     {
        risk_percent *= InpLossReductionFactor;
        if(false) PrintFormat("[VARIABLE RISK] Reduced risk: %.2f%%, trades remaining: %d", risk_percent, ReductionTradesRemaining);
     }
    risk_percent = MathMin(risk_percent, InpMaxRiskPercent);
    if(false) PrintFormat("[VARIABLE RISK] Level: %d, Base: %.2f%%, Final: %.2f%%", current_level, InpBaseRiskPercent, risk_percent);
    return risk_percent;
}
void UpdateVariableRiskOnTrade(bool trade_won)
{
    if(!InpUseVariableRisk) return;
    if(trade_won)
     {
        ConsecutiveLosses = 0;
        ReductionTradesRemaining = 0;
     }
    else
     {
        ConsecutiveLosses++;
        if(ConsecutiveLosses >= 1) ReductionTradesRemaining = InpReductionTrades;
     }
}
void OnTrade(){    static int last_deal_count = 0;    if((int)HistoryDealsTotal() > last_deal_count)    {        ulong ticket = HistoryDealGetTicket((int)HistoryDealsTotal() - 1);        if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)        {            if(InpDebug_DailyLossMode)                 PrintFormat("[POSITION CLOSED] Deal #%lu closed. Panel will update on next tick.", ticket);                        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)            {                g_last_close_was_loss = (HistoryDealGetDouble(ticket, DEAL_PROFIT) < 0);                if(InpUseVariableRisk) UpdateVariableRiskOnTrade(!g_last_close_was_loss);            }        }    }    last_deal_count = (int)HistoryDealsTotal();}
bool CanOpenAdditionalTrade(int signal, string &reason)
{
    reason = "";
    if(false)
        PrintFormat("[BARS FILTER] Check | LastTrade:%s | MinBars:%d | Elapsed:%d bars",
                    TimeToString(g_last_trade_time),
                    InpMinBarsAfterAnyTrade,
                    (int)((TimeCurrent() - g_last_trade_time) / PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF)));
    int open_positions = OpenPositionsCount();
    if(open_positions == 0)
     {
        int bars_to_wait = g_last_close_was_loss ? InpMinBarsAfterLoss : InpMinBarsAfterAnyTrade;
        if (g_last_position_close_time > 0 && TimeCurrent() - g_last_position_close_time < (long)bars_to_wait * PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF))
        {
           if(false) PrintFormat("[TIME FILTER] Waiting %d bars after last close.", bars_to_wait);
           reason = StringFormat("Waiting %d bars after last close", bars_to_wait);
           return false;
        }
     }
    else
     {
        if (g_last_trade_time > 0 && TimeCurrent() - g_last_trade_time < (long)InpMinBarsAfterAnyTrade * PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF))
        {
           if(false) PrintFormat("[TIME FILTER] Waiting %d bars before re-entry.", InpMinBarsAfterAnyTrade);
           reason = StringFormat("Waiting %d bars before new trade", InpMinBarsAfterAnyTrade);
           return false;
        }
     }
    if(open_positions >= InpMaxTradesPerSymbol)
    {
        reason = StringFormat("Max trades per symbol (%d) reached", InpMaxTradesPerSymbol);
        return false;
    }
    if(open_positions > 0)
     {
        double current_price = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
        double last_entry_price = 0.0;
        datetime last_entry_time = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
           if(!pos.SelectByIndex(i) || pos.Symbol() != _Symbol || (long)pos.Magic() != InpMagicNumber) continue;
           if(last_entry_time == 0 || pos.Time() > last_entry_time)
           {
               last_entry_price = pos.PriceOpen();
               last_entry_time = pos.Time();
           }
        }
        if(last_entry_time > 0)
        {
           if(MathAbs(current_price - last_entry_price) / _Point < InpMinDistance_In_Points)
           {
               reason = "Min distance between trades not met";
               return false;
           }
           if(signal > 0 && current_price >= last_entry_price)
           {
               reason = "Price not favorable for additional BUY";
               return false;
           }
           if(signal < 0 && current_price <= last_entry_price)
           {
               reason = "Price not favorable for additional SELL";
               return false;
           }
        }
        if(InpRequireSetupConfirmation)
        {
           double eF, eM, eS, r, atr, adx, macd_val;
           if(!GetCachedBuffers(1,eF,eM,eS,r,atr,adx,macd_val))
           {
               reason = "Indicator cache unavailable for confirmation";
               return false;
           }
           if(GetSignal() != signal)
           {
               reason = "Setup confirmation failed";
               return false;
           }
           if(false) Print("[MULTI-TRADE] Setup confirmed for additional trade");
        }
     }
    return true;
}
bool HasOppositeDirectionTrade(int signal, string &reason)
{
    reason = "";
    if(!InpBlockOppositeDirections) return false;
    for(int i = 0; i < PositionsTotal(); i++)
    {
       if(!pos.SelectByIndex(i) || pos.Symbol() != _Symbol || (long)pos.Magic() != InpMagicNumber) continue;
       if((signal > 0 && pos.PositionType() == POSITION_TYPE_SELL) || (signal < 0 && pos.PositionType() == POSITION_TYPE_BUY))
       {
           reason = "Hedging filter (opposite direction)";
           return true;
       }
    }
    return false;
}
int DetectServerUTCOffset()
{
    return (int)MathRound((double)(TimeCurrent() - TimeGMT())/3600.0);
}
bool IsTradingSessionActive()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    ENUM_SESSION current_day_session;
    switch(dt.day_of_week)
    {
       case 1: current_day_session = InpMondaySession; break;
       case 2: current_day_session = InpTuesdaySession; break;
       case 3: current_day_session = InpWednesdaySession; break;
       case 4: current_day_session = InpThursdaySession; break;
       case 5: current_day_session = InpFridaySession; break;
       default: return false;
    }
    if(current_day_session == All_Session) return true;
    int server_gmt_offset = DetectServerUTCOffset();
    int hour = dt.hour;
    bool is_asia = (hour >= (0 + server_gmt_offset) % 24 && hour < (9 + server_gmt_offset) % 24);
    bool is_london = (hour >= (8 + server_gmt_offset) % 24 && hour < (17 + server_gmt_offset) % 24);
    bool is_ny = (hour >= (13 + server_gmt_offset) % 24 && hour < (22 + server_gmt_offset) % 24);
    switch(current_day_session)
    {
       case Asia: return is_asia;
       case London: return is_london;
       case NY: return is_ny;
       case Asia_and_London: return is_asia || is_london;
       case London_and_NY: return is_london || is_ny;
    }
    return false;
}
bool SpreadOK()
{
    if(InpMaxSpreadPoints <= 0) return true;
    return ((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID))/_Point <= InpMaxSpreadPoints);
}
bool RiskOverlaysOK()  {  
    double eq = AccountInfoDouble(ACCOUNT_EQUITY);  
    // Check global loss flag first
    if(IsGlobalDailyLossReached())
    {
        if(InpDebug_GlobalSync)
            PrintFormat("[FASE 4] Global loss flag detected - all instances stopping");
        return false;
    }
    double daily_pl, daily_pl_pct, daily_dd, daily_dd_pct;  
    CalculateDailyPerformance(daily_pl, daily_pl_pct, daily_dd, daily_dd_pct);  
    if(g_totalStartEquity <= 0.0) g_totalStartEquity = g_initialEquity;  
    if(g_initialEquity <= 0.0) g_initialEquity = eq;  

    // ===== PRECEDENCE: Account-wide loss flag (All Trades scope) =====
    if(IsGlobalDailyLossReached())
    {
        if(InpDebug_GlobalSync)
            Print("[RISK] Account global loss flag active - blocking trading");
        return false;
    }

    // ===== CHECK ACCOUNT-WIDE LIMIT (if any instance registered All Trades) =====
    if(GlobalVariableCheck("ACCOUNT_GLOBAL_ActiveLimits"))
    {
        double global_limit = GetLowestGlobalDailyLimit();
        if(global_limit > 0)
        {
            if(InpDailyLossMode != Limit_Off && daily_dd_pct > global_limit)
            {
                if(InpDebug_GlobalSync)
                {
                    PrintFormat("[FASE 4] Account DD %.2f%% exceeds global limit %.2f%%", daily_dd_pct, global_limit);
                    PrintFormat("[FASE 4] Lowest active limit among all instances");
                }
                datetime trigger_time = TimeCurrent();
                double trigger_stamp = (double)trigger_time;
                GlobalVariableSet("ACCOUNT_GLOBAL_LossFlag", 1.0);
                GlobalVariableSet("ACCOUNT_GLOBAL_TriggerTimestamp", trigger_stamp);
                GlobalVariableSet("ACCOUNT_GLOBAL_TriggerSymbol_" + _Symbol, trigger_stamp);
                g_daily_loss_was_reached = true;
                PrintFormat("[DAILY LOSS LIMIT] Global limit reached. Closing all positions...");
                int closed_count_gl = 0;
                // Close ALL positions in the account (any magic, any EA, manual)
                for(int i = PositionsTotal() - 1; i >= 0; i--)
                {
                    if(pos.SelectByIndex(i))
                    {
                        ulong t = pos.Ticket();
                        if(trade.PositionClose(t))
                        {
                            closed_count_gl++;
                            PrintFormat("[EMERGENCY STOP] Closed position #%I64u (Global limit protection)", t);
                        }
                        else
                        {
                            PrintFormat("[EMERGENCY STOP][ERROR] Failed to close position #%I64u | Error:%d", t, GetLastError());
                        }
                    }
                }
                // Schedule local reset display
                if(!g_isEaStopped)
                {
                    g_isEaStopped = true;
                    MqlDateTime dt_next; TimeToStruct(trigger_time, dt_next); dt_next.day += 1; dt_next.hour = 0; dt_next.min = 0; dt_next.sec = 0; g_resetTime = StructToTime(dt_next);
                }
                return false;
            }
        }
    }

    // ===== PRECEDENCE: EA-group flag (EA Trades All Charts) =====
    if(IsEAGlobalDailyLossReached())
    {
        if(InpDebug_GlobalSync)
            Print("[RISK] EA-group loss flag active - blocking EA trading");
        return false;
    }

    bool daily_dd_hit = false;  
    
    // CRITICAL: Always include manual trades in risk limits (prop firm rules)
    double total_daily_dd_for_limits = daily_dd;
    double total_daily_dd_pct = (g_dailyStartBalance > 0) ? 
                                (total_daily_dd_for_limits / g_dailyStartBalance) * 100.0 : 0.0;

    // Scope-based evaluation
    if(InpRiskScope == Scope_AllTrades)
    {
        if(InpDailyLossMode == Limit_Percent && InpDailyLossValue > 0 && total_daily_dd_pct > InpDailyLossValue)
            daily_dd_hit = true;
        else if(InpDailyLossMode == Limit_Money && InpDailyLossValue > 0 && total_daily_dd_for_limits > InpDailyLossValue)
            daily_dd_hit = true;
    }
    else if(InpRiskScope == Scope_EA_AllCharts)
    {
        double ea_pl, ea_pl_pct, ea_dd, ea_dd_pct; GetEAGroupDailyPL(false, ea_pl, ea_pl_pct, ea_dd, ea_dd_pct);
        if(InpDailyLossMode == Limit_Percent && InpDailyLossValue > 0 && ea_dd_pct > InpDailyLossValue) daily_dd_hit = true;
        else if(InpDailyLossMode == Limit_Money && InpDailyLossValue > 0 && ea_dd > InpDailyLossValue) daily_dd_hit = true;
        // Override metrics for logs
        total_daily_dd_for_limits = ea_dd; total_daily_dd_pct = ea_dd_pct; daily_dd_pct = ea_dd_pct;
    }
    else // Scope_EA_ChartOnly
    {
        double ea_pl, ea_pl_pct, ea_dd, ea_dd_pct; GetEAGroupDailyPL(true, ea_pl, ea_pl_pct, ea_dd, ea_dd_pct);
        if(InpDailyLossMode == Limit_Percent && InpDailyLossValue > 0 && ea_dd_pct > InpDailyLossValue) daily_dd_hit = true;
        else if(InpDailyLossMode == Limit_Money && InpDailyLossValue > 0 && ea_dd > InpDailyLossValue) daily_dd_hit = true;
        total_daily_dd_for_limits = ea_dd; total_daily_dd_pct = ea_dd_pct; daily_dd_pct = ea_dd_pct;
    }
      
    if(daily_dd_hit)
    {
        ExecuteDailyLossStop(total_daily_dd_for_limits, total_daily_dd_pct);
        return false;
    }
      
    if(InpTotalLossMode == Limit_Percent && InpTotalLossValue > 0 && g_totalStartEquity > 0)  
    {  
        if(100.0 * (g_totalStartEquity - eq) / g_totalStartEquity > InpTotalLossValue) return false;  
    }  
    else if (InpTotalLossMode == Limit_Money && InpTotalLossValue > 0)  
    {  
        if((g_totalStartEquity - eq) > InpTotalLossValue) return false;  
    }  
    if(InpDailyProfitMode == Limit_Percent && InpDailyProfitValue > 0 && daily_pl_pct > InpDailyProfitValue) return false;  
    if(InpDailyProfitMode == Limit_Money && InpDailyProfitValue > 0 && daily_pl > InpDailyProfitValue) return false;  
    return true;  
}  
void MonitorDailyLossLimit(){
    if(InpDailyLossMode == Limit_Off || InpDailyLossValue <= 0) return;
    bool hit = false; double dd=0, dd_pct=0;
    if(InpRiskScope == Scope_AllTrades)
    {
        double daily_pl, daily_pl_pct, daily_dd, daily_dd_pct; CalculateDailyPerformance(daily_pl, daily_pl_pct, daily_dd, daily_dd_pct);
        dd = daily_dd; dd_pct = daily_dd_pct;
        if(InpDailyLossMode == Limit_Percent && dd_pct > InpDailyLossValue) hit = true;
        else if(InpDailyLossMode == Limit_Money && dd > InpDailyLossValue) hit = true;
    }
    else if(InpRiskScope == Scope_EA_AllCharts)
    {
        double ea_pl, ea_pl_pct, ea_dd, ea_dd_pct; GetEAGroupDailyPL(false, ea_pl, ea_pl_pct, ea_dd, ea_dd_pct);
        dd = ea_dd; dd_pct = ea_dd_pct;
        if(InpDailyLossMode == Limit_Percent && dd_pct > InpDailyLossValue) hit = true;
        else if(InpDailyLossMode == Limit_Money && dd > InpDailyLossValue) hit = true;
    }
    else
    {
        double ea_pl, ea_pl_pct, ea_dd, ea_dd_pct; GetEAGroupDailyPL(true, ea_pl, ea_pl_pct, ea_dd, ea_dd_pct);
        dd = ea_dd; dd_pct = ea_dd_pct;
        if(InpDailyLossMode == Limit_Percent && dd_pct > InpDailyLossValue) hit = true;
        else if(InpDailyLossMode == Limit_Money && dd > InpDailyLossValue) hit = true;
    }
    if(InpDebug_DailyDdFilters)
        PrintFormat("[DAILY LOSS] Scope=%s | DD=%.2f (%.2f%%) | Limit=%s %.2f | Hit=%s",
            (InpRiskScope == Scope_AllTrades ? "AllTrades" :
                (InpRiskScope == Scope_EA_AllCharts ? "EA_AllCharts" : "EA_ChartOnly")),
            dd, dd_pct,
            (InpDailyLossMode == Limit_Percent ? "Pct" : "Money"),
            InpDailyLossValue,
            hit ? "YES" : "NO");
    // Auto-reactivate if previously hit but now below limit (all scopes)
    if(g_daily_loss_was_reached && !hit)
    {
        g_daily_loss_was_reached = false;
        g_isEaStopped = false;
        g_resetTime = 0;
        if(InpRiskScope == Scope_EA_ChartOnly)
        {
            string stop_var = "UDEA_M" + (string)InpMagicNumber + "_C" + (string)ChartID() + "_IsEaStopped";
            if(GlobalVariableCheck(stop_var)) GlobalVariableDel(stop_var);
        }
        else if(InpRiskScope == Scope_EA_AllCharts)
        {
            string key = GetEAGroupKey();
            string flag = "EA_GLOBAL_" + key + "_LossFlag";
            string ts   = "EA_GLOBAL_" + key + "_TriggerTimestamp";
            if(GlobalVariableCheck(flag)) GlobalVariableDel(flag);
            if(GlobalVariableCheck(ts))   GlobalVariableDel(ts);
            GlobalVariablesDeleteAll("EA_GLOBAL_" + key + "_TriggerSymbol_");
        }
        else if(InpRiskScope == Scope_AllTrades)
        {
            if(GlobalVariableCheck("ACCOUNT_GLOBAL_LossFlag")) GlobalVariableDel("ACCOUNT_GLOBAL_LossFlag");
            if(GlobalVariableCheck("ACCOUNT_GLOBAL_TriggerTimestamp")) GlobalVariableDel("ACCOUNT_GLOBAL_TriggerTimestamp");
            GlobalVariablesDeleteAll("ACCOUNT_GLOBAL_TriggerSymbol_");
        }
        SaveCriticalState();
        if(InpDebug_DailyDdFilters || InpDebug_StatusChanges)
            Print("[DAILY LOSS] Auto-reactivation: DD below limit, flags cleared for current scope");
        return;
    }
    if(g_daily_loss_was_reached) return;
    if(hit)
    {
        if(InpDebug_RiskLimits)
            PrintFormat("[DAILY LOSS] Monitor: DD=%.2f (%.2f%%) - triggering stop", dd, dd_pct);
        ExecuteDailyLossStop(dd, dd_pct);
    }
}
void ExecuteDailyLossStop(double dd_value, double dd_pct_value)
{
    if(g_daily_loss_was_reached && g_isEaStopped)
        return;

    datetime trigger_time = TimeCurrent();

    if(InpRiskScope == Scope_AllTrades)
        SetGlobalDailyLossFlag();
    else if(InpRiskScope == Scope_EA_AllCharts)
        SetEAGlobalDailyLossFlag();

    g_daily_loss_was_reached = true;
    g_isEaStopped = true;
    if(InpRiskScope == Scope_EA_ChartOnly)
    {
        string stop_var = "UDEA_M" + (string)InpMagicNumber + "_C" + (string)ChartID() + "_IsEaStopped";
        GlobalVariableSet(stop_var, 1.0);
    }

    if(InpDebug_StatusChanges)
        PrintFormat("[FASE 6] STATUS changed to INACTIVE (DD=$%.2f | %.2f%%)", dd_value, dd_pct_value);

    string limit_text;
    if(InpDailyLossMode == Limit_Percent)
        limit_text = StringFormat("%.2f%%", InpDailyLossValue);
    else
        limit_text = StringFormat("$%.2f", InpDailyLossValue);

    PrintFormat("[DAILY LOSS LIMIT] Limit reached: DD=$%.2f (%.2f%%) vs %s. Closing positions...",
                dd_value, dd_pct_value, limit_text);

    int closed_count = 0;
    if(InpRiskScope == Scope_AllTrades)
    {
        Print("[DAILY LOSS LIMIT] Global mode - closing ALL positions in account");
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!pos.SelectByIndex(i)) continue;
            ulong ticket = pos.Ticket();
            string symbol = pos.Symbol();
            long magic = pos.Magic();
            if(trade.PositionClose(ticket))
            {
                closed_count++;
                PrintFormat("[CLOSING] Closed position #%I64u (Symbol: %s, Magic: %I64d)", ticket, symbol, magic);
            }
            else
            {
                PrintFormat("[ERROR] Failed to close position #%I64u | Error: %d", ticket, GetLastError());
            }
        }
    }
    else if(InpRiskScope == Scope_EA_AllCharts)
    {
        Print("[DAILY LOSS LIMIT] EA All Charts - closing EA positions only");
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!pos.SelectByIndex(i)) continue;
            long magic = (long)pos.Magic();
            string symbol = pos.Symbol();
            string comment = pos.Comment();
            bool match = (magic == InpMagicNumber) || (InpTradeComment != "" && StringFind(comment, InpTradeComment) >= 0);
            if(!match) continue;
            ulong ticket = pos.Ticket();
            if(trade.PositionClose(ticket))
            {
                closed_count++;
                PrintFormat("[CLOSING] Closed EA position #%I64u (Magic: %I64d, Symbol: %s)", ticket, magic, symbol);
            }
            else
            {
                PrintFormat("[ERROR] Failed to close EA position #%I64u | Error: %d", ticket, GetLastError());
            }
        }
    }
    else
    {
        PrintFormat("[DAILY LOSS LIMIT] This Chart Only - closing %s positions (Magic %I64d)", _Symbol, InpMagicNumber);
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(!pos.SelectByIndex(i)) continue;
            long magic = (long)pos.Magic();
            string symbol = pos.Symbol();
            string pos_comment = pos.Comment();
            ulong ticket = pos.Ticket();
            if(IsPositionFromThisChart(magic, symbol, pos_comment))
            {
            if(trade.PositionClose(ticket))
            {
                closed_count++;
                PrintFormat("[CLOSING] Closed position #%I64u (Magic: %I64d, Symbol: %s, Comment: %s)", ticket, magic, symbol, pos_comment);
            }
            else
            {
                PrintFormat("[ERROR] Failed to close position #%I64u | Error: %d", ticket, GetLastError());
            }
        }
        else if(InpDebug_StatusChanges)
        {
            PrintFormat("[SKIP] Position #%I64u not closed (Magic: %I64d, Symbol: %s, Comment: %s)", ticket, magic, symbol, pos_comment);
        }
        }
    }

    PrintFormat("[DAILY LOSS] Stop completed. %d positions closed. EA stopped.", closed_count);
    if(InpRiskScope == Scope_AllTrades)
        Print("[DAILY LOSS] Mode: All Trades - entire account flat");
    else if(InpRiskScope == Scope_EA_AllCharts)
        Print("[DAILY LOSS] Mode: EA Trades (All Charts) - EA positions closed");
    else
        PrintFormat("[DAILY LOSS] Mode: Chart Only - %s (Magic %I64d) positions closed", _Symbol, InpMagicNumber);

    MqlDateTime dt_next;
    TimeToStruct(trigger_time, dt_next);
    dt_next.day += 1; dt_next.hour = 0; dt_next.min = 0; dt_next.sec = 0;
    g_resetTime = StructToTime(dt_next);
    double trigger_stamp = (double)trigger_time;
    if(InpRiskScope == Scope_AllTrades)
    {
        GlobalVariableSet("ACCOUNT_GLOBAL_TriggerTimestamp", trigger_stamp);
        GlobalVariableSet("ACCOUNT_GLOBAL_TriggerSymbol_" + _Symbol, trigger_stamp);
    }
    else if(InpRiskScope == Scope_EA_AllCharts)
    {
        string key = GetEAGroupKey();
        GlobalVariableSet("EA_GLOBAL_" + key + "_TriggerTimestamp", trigger_stamp);
        GlobalVariableSet("EA_GLOBAL_" + key + "_TriggerSymbol_" + _Symbol, trigger_stamp);
    }

    SaveCriticalState();
    if(InpDebug_StatusChanges)
        PrintFormat("[FASE 6] Auto-reset scheduled for %s", TimeToString(g_resetTime));
}
bool IsMarketActive()
{
    if(!InpUseActivityFilter) return true;
    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)InpSignalTF;
    double volume_avg = 0.0;
    for(int i = 1; i <= InpActivityVolumePeriod; i++) volume_avg += (double)iVolume(_Symbol, tf, i);
    volume_avg /= InpActivityVolumePeriod;
    if(volume_avg <= 0.0) return true;
    double activity_ratio = (double)iVolume(_Symbol, tf, 1) / volume_avg;
    bool is_active = activity_ratio >= (1.0/InpMinActivityMultiple);
    if(false) PrintFormat("[ACTIVITY] Ratio: %.2f, MinRequired: %.2f, Result: %s", activity_ratio, (1.0/InpMinActivityMultiple), is_active ? "ALLOWED" : "BLOCKED");
    return InpAvoidLowActivity ? is_active : true;
}
bool IsCorrelationOK_Check(string &reason)
{
    reason = "";
    if(!InpUseCorrelationFilter) return true;
    string groups[];
    int group_count = StringSplit(InpCorrelatedPairs, ';', groups);
    for(int g = 0; g < group_count; g++)
    {
        string pairs_in_group[];
        StringSplit(groups[g], ',', pairs_in_group);
        bool symbol_in_group = false;
        for(int p = 0; p < ArraySize(pairs_in_group); p++)
        {
            StringTrimLeft(pairs_in_group[p]);
            StringTrimRight(pairs_in_group[p]);
            if(pairs_in_group[p] == _Symbol)
            {
                symbol_in_group = true;
                break;
            }
        }
        if(symbol_in_group)
        {
            int positions_in_group = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
                if(pos.SelectByIndex(i) && (long)pos.Magic() == InpMagicNumber)
                {
                    for(int p = 0; p < ArraySize(pairs_in_group); p++)
                    {
                        if(pairs_in_group[p] == pos.Symbol())
                        {
                            positions_in_group++;
                            break;
                        }
                    }
                }
            }
            if(positions_in_group >= InpMaxCorrelatedPositions)
            {
                if(false) PrintFormat("[CORRELATION] Max positions reached in group: %d/%d", positions_in_group, InpMaxCorrelatedPositions);
                reason = "Correlation filter: max positions in group";
                return false;
            }
        }
    }
    return true;
}
void ManageWeekendLogic()
{
    if(!InpUseWeekendManagement) return;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(InpCloseOnFriday && dt.day_of_week == 5 && dt.hour >= InpFridayCloseHour)
    {
       for(int i = PositionsTotal() - 1; i >= 0; i--)
       {
          if(pos.SelectByIndex(i) && (long)pos.Magic() == InpMagicNumber) trade.PositionClose(pos.Ticket());
       }
    }
}
int GetTimeBasedCloseHour()
{
    switch(InpTimeBasedClose)
    {
        case TimeClose_01: return 1;
        case TimeClose_02: return 2;
        case TimeClose_03: return 3;
        case TimeClose_04: return 4;
        case TimeClose_05: return 5;
        case TimeClose_06: return 6;
        case TimeClose_07: return 7;
        case TimeClose_08: return 8;
        case TimeClose_09: return 9;
        case TimeClose_10: return 10;
        case TimeClose_11: return 11;
        case TimeClose_12: return 12;
        case TimeClose_13: return 13;
        case TimeClose_14: return 14;
        case TimeClose_15: return 15;
        case TimeClose_16: return 16;
        case TimeClose_17: return 17;
        case TimeClose_18: return 18;
        case TimeClose_19: return 19;
        case TimeClose_20: return 20;
        case TimeClose_21: return 21;
        case TimeClose_22: return 22;
        case TimeClose_23: return 23;
        default: return -1;
    }
}
void ManageTimeBasedClose()
{
    int close_hour = GetTimeBasedCloseHour();
    if(close_hour < 0) return;

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime day_start = (datetime)StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
    if(g_last_time_close_day == day_start) return;
    if(dt.hour < close_hour) return;

    int closed = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!pos.SelectByIndex(i)) continue;
        if((long)pos.Magic() != InpMagicNumber) continue;
        if(pos.Symbol() != _Symbol) continue;
        if(trade.PositionClose(pos.Ticket())) closed++;
    }
    g_last_time_close_day = day_start;
    if(closed > 0 && InpDebug_StatusChanges)
        PrintFormat("[TIME CLOSE] Closed %d position(s) at %02d:00 server time", closed, close_hour);
}
void ManageExitStrategy()
{
    if(InpExitStrategyMode == Exit_Strategy_Off) return;
    if(TimeCurrent() - g_last_trailing_check < 3) return;
    g_last_trailing_check = TimeCurrent();
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
       if(!pos.SelectByIndex(i) || pos.Symbol() != _Symbol || (long)pos.Magic() != InpMagicNumber) continue;
       if(InpExitStrategyMode == Breakeven_Points) ManageBreakeven(pos.Ticket());
       else ManageTrailingStop(pos.Ticket());
    }
}
void ManageBreakeven(long ticket)
{
    if(!pos.SelectByTicket(ticket)) return;
    double open_price = pos.PriceOpen();
    double current_sl = pos.StopLoss();
    double new_sl = 0;
    if(pos.PositionType() == POSITION_TYPE_BUY)
    {
       new_sl = open_price + InpBreakevenOffsetPoints * _Point;
       if(SymbolInfoDouble(_Symbol, SYMBOL_BID) > open_price + InpBreakevenTriggerPoints * _Point && current_sl < new_sl)
       {
          trade.PositionModify(ticket, new_sl, pos.TakeProfit());
       }
    }
    else
    {
       new_sl = open_price - InpBreakevenOffsetPoints * _Point;
       if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) < open_price - InpBreakevenTriggerPoints * _Point && (current_sl > new_sl || current_sl == 0))
       {
          trade.PositionModify(ticket, new_sl, pos.TakeProfit());
       }
    }
}
void ManageTrailingStop(long ticket)
{
    if(!pos.SelectByTicket(ticket)) return;
    double open_price = pos.PriceOpen();
    double current_sl = pos.StopLoss();
    long position_type = pos.PositionType();
    double current_price = (position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double trailing_distance = 0;
    if(InpExitStrategyMode == Trailing_Stop_ATR)
    {
       double atr_buffer[];
       ENUM_TIMEFRAMES tf_atr = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpAtrTimeframe : (ENUM_TIMEFRAMES)InpSignalTF;
       int hATR_Trailing = iATR(_Symbol, tf_atr, InpAtrTrailingPeriod);
       if(CopyBuffer(hATR_Trailing, 0, 1, 1, atr_buffer) > 0) trailing_distance = InpAtrTrailingMultiplier * atr_buffer[0];
       IndicatorRelease(hATR_Trailing);
    }
    else trailing_distance = InpTrailingStepPoints * _Point;
    if(trailing_distance <= 0) return;
    if(((position_type == POSITION_TYPE_BUY) ? (current_price - open_price) : (open_price - current_price)) >= InpTrailingStartPoints * _Point)
    {
       double new_sl = 0;
       if(position_type == POSITION_TYPE_BUY)
       {
          new_sl = current_price - trailing_distance;
          if(new_sl > current_sl) trade.PositionModify(ticket, new_sl, pos.TakeProfit());
       }
       else
       {
          new_sl = current_price + trailing_distance;
          if(new_sl < current_sl || current_sl == 0) trade.PositionModify(ticket, new_sl, pos.TakeProfit());
       }
    }
}
void UpdatePositionCloseTime()
{
    static int last_positions_count = -1;
    int current_positions = OpenPositionsCount();
    if(last_positions_count > current_positions && current_positions >= 0)
    {
       g_last_position_close_time = TimeCurrent();
       SaveCriticalState(); // Guardar inmediatamente
       
    }
    last_positions_count = current_positions;
}
bool IsLateFridayEntryBlocked()
{
    if(!InpUseWeekendManagement || !InpBlockLateFriday) return false;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day_of_week == 5 && dt.hour >= InpFridayBlockHour)
    {
    if(false) PrintFormat("[WEEKEND] New trades blocked after %d:00 on Friday.", InpFridayBlockHour);
       return true;
    }
    return false;
}
bool LoadEmbeddedNews(){    ArrayResize(g_all_news, 0);    int server_offset = 0;    if(InpNewsTimesAreUTC)    {        server_offset = DetectServerUTCOffset();        if(InpManualUtcOffset != 0)           server_offset = InpManualUtcOffset;    }    int total_events = ArraySize(g_embedded_news_data);    int loaded_count = 0;        for(int i = 0; i < total_events; i++)    {       string parts[];       int split_result = StringSplit(g_embedded_news_data[i], '|', parts);              if(split_result < 4)       {           if(false)                PrintFormat("[LoadEmbeddedNews] Skipping malformed data (expected 4 parts, got %d): %s",                            split_result, g_embedded_news_data[i]);           continue;       }              NewsEvent_EA evt;       evt.time = (datetime)StringToTime(parts[0]);       if(evt.time == 0)       {           if(false)                PrintFormat("[LoadEmbeddedNews] Skipping invalid date format: %s", parts[0]);           continue;       }              if(InpNewsTimesAreUTC)          evt.time = (datetime)(evt.time + server_offset * 3600);              evt.currency = parts[1];
      // VALIDACI?N CR?TICA: Rechazar cualquier dato con "Label"
      if(parts[1] == "Label" || parts[3] == "Label")
      {
          if(false)
              PrintFormat("[LoadEmbeddedNews] Rechazando evento con Label: %s | %s", parts[1], parts[3]);
          continue;
      }
      string impact_str = parts[2];       StringToUpper(impact_str);       if(impact_str == "H") evt.importance = 3;       else if(impact_str == "M") evt.importance = 2;       else evt.importance = 1;              evt.name = parts[3];              int size = ArraySize(g_all_news);       ArrayResize(g_all_news, size + 1);       g_all_news[size] = evt;       loaded_count++;    }        if(false || loaded_count == 0)        PrintFormat("[NEWS] Loaded %d/%d events from embedded data for tester.", loaded_count, total_events);        return(ArraySize(g_all_news) > 0);}

void LoadNews()
{
    ArrayResize(g_all_news, 0);
    if(MQLInfoInteger(MQL_TESTER)) { LoadEmbeddedNews(); }
    else // Live Mode
    {
        MqlCalendarValue values[];
        if(CalendarValueHistory(values, (datetime)(TimeCurrent() - (long)(4 * 24 * 3600)), (datetime)(TimeCurrent() + (long)(8 * 24 * 3600))))
        {
            for(int i=0; i < ArraySize(values); i++)
            {
                MqlCalendarEvent event_info;
                MqlCalendarCountry country_info;
                if(!CalendarEventById(values[i].event_id, event_info) || !CalendarCountryById(event_info.country_id, country_info)) continue;
                NewsEvent_EA evt;
                evt.time = (datetime)values[i].time;
                evt.currency = country_info.currency;
                evt.name = event_info.name;
                evt.importance = event_info.importance;
                // VALIDACI?N CR?TICA: Rechazar cualquier dato sospechoso
                if(evt.currency == "Label" || evt.name == "Label" ||
                   evt.currency == "" || evt.name == "" ||
                   evt.time <= 0 || evt.importance < 1 || evt.importance > 3)
                {
                    if(false)
                        PrintFormat("[LoadNews LIVE] Rechazando evento inv?lido: %s | %s | Time:%s",
                                     evt.currency, evt.name, TimeToString(evt.time));
                    continue;
                }
                int size = ArraySize(g_all_news);
                ArrayResize(g_all_news, size + 1);
                g_all_news[size] = evt;
            }
        }
        if(false) PrintFormat("[NEWS] Loaded %d events from Calendar API.", ArraySize(g_all_news));
    }
    // Sort news chronologically
    for(int i = 0; i < ArraySize(g_all_news) - 1; i++) {
       for(int j = i + 1; j < ArraySize(g_all_news); j++) {
          if(g_all_news[i].time > g_all_news[j].time) {
             NewsEvent_EA temp = g_all_news[i];
             g_all_news[i] = g_all_news[j];
             g_all_news[j] = temp;
          }
       }
    }
    // DEBUG #1: Inspeccionar array global despu?s de cargar
    if(false)
    {
        Print("========================================");
        Print("[DEBUG #1] DESPUES DE LoadNews()");
        Print("Total eventos en g_all_news[]: ", ArraySize(g_all_news));
        // Mostrar primeros 3 eventos para detectar "Label"
        for(int i = 0; i < MathMin(3, ArraySize(g_all_news)); i++)
        {
            PrintFormat("  Evento[%d]: Currency='%s' | Name='%s' | Time=%s | Importance=%d",
                        i,
                        g_all_news[i].currency,
                        g_all_news[i].name,
                        TimeToString(g_all_news[i].time, TIME_DATE|TIME_MINUTES),
                        g_all_news[i].importance);
        }
        Print("========================================");
    }
}
bool GetActiveNewsEventDetails(datetime &event_time)
{
    long window_sec = (long)InpNewsWindowMin * 60;
    datetime now = TimeCurrent();
    string base_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    string quote_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    datetime soonest_event_time = 0;
    for(int i = 0; i < ArraySize(g_all_news); i++)
    {
        bool is_relevant = false;
        switch(InpNewsImpactToManage)
        {
            case Manage_High_Impact:   if(g_all_news[i].importance == 3) is_relevant = true; break;
            case Manage_Medium_Impact: if(g_all_news[i].importance == 2) is_relevant = true; break;
            case Manage_Both:          if(g_all_news[i].importance >= 2) is_relevant = true; break;
        }
        if(!is_relevant || (g_all_news[i].currency != "" && g_all_news[i].currency != base_curr && g_all_news[i].currency != quote_curr)) continue;
        if (now >= (datetime)(g_all_news[i].time - window_sec) && now < (datetime)(g_all_news[i].time + window_sec))
        {
            if (soonest_event_time == 0 || g_all_news[i].time < soonest_event_time) soonest_event_time = g_all_news[i].time;
        }
    }
    if (soonest_event_time > 0) { event_time = soonest_event_time; return true; }
    return false;
}
bool CalculateActiveNewsWindow(datetime &window_start, datetime &window_end, datetime &next_standby_start)
{
    struct NewsWindow { datetime start; datetime end; };
    NewsWindow windows[];
    long window_sec = (long)InpNewsWindowMin * 60;
    string base_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    string quote_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    for(int i = 0; i < ArraySize(g_all_news); i++)
    {
        bool is_relevant = false;
        switch(InpNewsImpactToManage)
        {
            case Manage_High_Impact: if(g_all_news[i].importance == 3) is_relevant = true; break;
            case Manage_Medium_Impact: if(g_all_news[i].importance == 2) is_relevant = true; break;
            case Manage_Both: if(g_all_news[i].importance >= 2) is_relevant = true; break;
        }
        if(!is_relevant || (g_all_news[i].currency != "" && g_all_news[i].currency != base_curr && g_all_news[i].currency != quote_curr)) continue;
        int size = ArraySize(windows);
        ArrayResize(windows, size + 1);
        windows[size].start = (datetime)(g_all_news[i].time - window_sec);
        windows[size].end = (datetime)(g_all_news[i].time + window_sec);
    }
    if(ArraySize(windows) == 0) return false;
    for(int i = 0; i < ArraySize(windows) - 1; i++) for(int j = i + 1; j < ArraySize(windows); j++) if(windows[i].start > windows[j].start) { NewsWindow temp = windows[i]; windows[i] = windows[j]; windows[j] = temp; }
    NewsWindow merged[];
    if(ArraySize(windows) > 0)
    {
        ArrayResize(merged, 1);
        merged[0] = windows[0];
        for(int i = 1; i < ArraySize(windows); i++)
        {
            int last = ArraySize(merged) - 1;
            if(windows[i].start <= merged[last].end) { if(windows[i].end > merged[last].end) merged[last].end = windows[i].end; }
            else { int size = ArraySize(merged); ArrayResize(merged, size + 1); merged[size] = windows[i]; }
        }
    }
    datetime now = TimeCurrent();
    next_standby_start = 0;
    for(int i = 0; i < ArraySize(merged); i++)
    {
        if(now >= merged[i].start && now < merged[i].end) { window_start = merged[i].start; window_end = merged[i].end; return true; }
        if(merged[i].start > now && next_standby_start == 0) next_standby_start = merged[i].start;
    }
    return false;
}
bool IsInNewsWindow(){    if(InpNewsFilterMode == News_Filter_Off) return false;        datetime start, end, next_standby;    return CalculateActiveNewsWindow(start, end, next_standby);}
long GetNewsCountdownSeconds(){
    datetime start, end, next_standby;
    bool is_in_window = CalculateActiveNewsWindow(start, end, next_standby);
    datetime now = TimeCurrent();
    if(is_in_window)
    {
        datetime event_time = 0;
        if(GetActiveNewsEventDetails(event_time))
        {
            long window_sec = (long)InpNewsWindowMin * 60;
            if(now < event_time)
            {
                long countdown = (event_time > now) ? (event_time - now) : 0;
                return countdown;
            }
            else
            {
                datetime after_end = (datetime)(event_time + window_sec);
                long countdown = (after_end > now) ? (after_end - now) : 0;
                return countdown;
            }
        }
        else
        {
            long countdown = (end > now) ? (end - now) : 0;
            return countdown;
        }
    }
    if(next_standby > now)
    {
        long countdown = next_standby - now;
        return countdown;
    }
    return 0;
}

//+------------------------------------------------------------------+
//|  FASE 2: Nueva funci?n para obtener m?ltiples eventos de noticias |
//+------------------------------------------------------------------+
int GetUpcomingNewsEvents(NewsEventData &events[], int max_events)
{
    // INICIALIZACI?N FORZADA DEL ARRAY DE SALIDA
    for(int i = 0; i < max_events; i++)
    {
        events[i].time = 0;
        events[i].currency = "";
        events[i].name = "";
        events[i].importance = 0;
    }
    int count = 0;
    datetime now = TimeCurrent();
    string base_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
    string quote_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
    StringToUpper(base_curr);
    StringToUpper(quote_curr);

    // 1. Filtrar todos los eventos relevantes en un array temporal
    NewsEvent_EA relevant_events[];
    for(int i = 0; i < ArraySize(g_all_news); i++)
    {
        bool is_impact_relevant = false;
        switch(InpNewsImpactToManage)
        {
            case Manage_High_Impact:   if(g_all_news[i].importance == 3) is_impact_relevant = true; break;
            case Manage_Medium_Impact: if(g_all_news[i].importance == 2) is_impact_relevant = true; break;
            case Manage_Both:          if(g_all_news[i].importance >= 2) is_impact_relevant = true; break;
        }
        if(!is_impact_relevant) continue;

        string event_curr = g_all_news[i].currency;
        StringToUpper(event_curr);
        // L?gica de filtrado estricta seg?n el plan
        bool currency_matches = (event_curr == "" || event_curr == base_curr || event_curr == quote_curr);

        if(currency_matches)
        {
            int size = ArraySize(relevant_events);
            ArrayResize(relevant_events, size + 1);
            relevant_events[size] = g_all_news[i];
        }
    }

    // 2. Encontrar el ?ndice del primer evento futuro
    int first_future_idx = -1;
    for(int i = 0; i < ArraySize(relevant_events); i++)
    {
        if(relevant_events[i].time >= now)
        {
            first_future_idx = i;
            break;
        }
    }

    // 3. Determinar el ?ndice de inicio para mostrar eventos pasados y futuros
    int start_idx = 0;
    if(first_future_idx != -1)
    {
        // Intentar mostrar 2 eventos pasados, si es posible
        start_idx = MathMax(0, first_future_idx - 2);
    }
    else if(ArraySize(relevant_events) > 0)
    {
        // Si no hay eventos futuros, mostrar los ?ltimos eventos del final de la lista
        start_idx = MathMax(0, ArraySize(relevant_events) - max_events);
    }

    // 4. Llenar el array de salida desde el ?ndice de inicio
    for(int i = start_idx; i < ArraySize(relevant_events) && count < max_events; i++)
    {
        events[count].time = relevant_events[i].time;
        events[count].currency = relevant_events[i].currency;
        events[count].name = relevant_events[i].name;
        events[count].importance = relevant_events[i].importance;
        count++;
    }
    // DEBUG #3: Ver qu? se copi? al array de salida ANTES del filtro
    if(false && count > 0)
    {
        Print("----------------------------------------");
        Print("[DEBUG #3] DENTRO GetUpcomingNewsEvents - ANTES DEL FILTRO");
        PrintFormat("Count antes de filtrar: %d", count);
        for(int i = 0; i < MathMin(3, count); i++)
        {
            PrintFormat("  PreFilter[%d]: Currency='%s' | Name='%s'",
                        i, events[i].currency, events[i].name);
        }
    }
    
    // FILTRO ULTRA-AGRESIVO: Rechazar cualquier evento sospechoso
    int filtered_count = 0;
    for(int i = 0; i < count; i++)
    {
        // Validaciones m?ltiples
        bool is_valid = true;
        // Verificar que no sea "Label"
        if(events[i].currency == "Label" || events[i].name == "Label")
            is_valid = false;
        // Verificar que no est? vac?o
        if(events[i].currency == "" || events[i].name == "")
            is_valid = false;
        // Verificar timestamp v?lido
        if(events[i].time <= 0)
            is_valid = false;
        // Verificar importancia en rango
        if(events[i].importance < 1 || events[i].importance > 3)
            is_valid = false;
        if(is_valid)
        {
            if(filtered_count != i)
            {
                events[filtered_count] = events[i];
            }
            filtered_count++;
        }
        else if(false)
        {
            PrintFormat("[GetUpcomingNewsEvents] Evento rechazado en filtro final: Currency='%s' Name='%s' Time=%s Importance=%d",
                        events[i].currency, events[i].name, TimeToString(events[i].time), events[i].importance);
        }
    }
    // Limpiar posiciones sobrantes
    for(int i = filtered_count; i < max_events; i++)
    {
        events[i].time = 0;
        events[i].currency = "";
        events[i].name = "";
        events[i].importance = 0;
    }
    if(false)
        PrintFormat("[GetUpcomingNewsEvents] Eventos filtrados: %d de %d originales", filtered_count, count);
    return filtered_count;
}


//=========================== INDICATORS ==============================
bool BuildIndicators()
{
    if(hEMA_Fast!=INVALID_HANDLE) IndicatorRelease(hEMA_Fast);
    if(hEMA_Med !=INVALID_HANDLE) IndicatorRelease(hEMA_Med);
    if(hEMA_Slow!=INVALID_HANDLE) IndicatorRelease(hEMA_Slow);
    if(hEMA_Keltner!=INVALID_HANDLE) IndicatorRelease(hEMA_Keltner);
    if(hRSI     !=INVALID_HANDLE) IndicatorRelease(hRSI);
    if(hATR     !=INVALID_HANDLE) IndicatorRelease(hATR);
    if(hATR_Keltner != INVALID_HANDLE) IndicatorRelease(hATR_Keltner);
    if(hADX     !=INVALID_HANDLE) IndicatorRelease(hADX);
    if(hMACD    !=INVALID_HANDLE) IndicatorRelease(hMACD);
    if(hBollinger != INVALID_HANDLE) IndicatorRelease(hBollinger);
    if(hStdDev != INVALID_HANDLE) IndicatorRelease(hStdDev);
    if(hStochastic != INVALID_HANDLE) IndicatorRelease(hStochastic);
    if(hCCI != INVALID_HANDLE) IndicatorRelease(hCCI);
    if(hSAR != INVALID_HANDLE) IndicatorRelease(hSAR);
    ENUM_TIMEFRAMES tf_chart = (ENUM_TIMEFRAMES)InpSignalTF;
    ENUM_TIMEFRAMES tf_ema = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpEmaTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_rsi = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpRsiTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_atr = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpAtrTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_adx = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpAdxTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_macd = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpMacdTimeframe : tf_chart;
    // Timeframes para filtros adicionales
    ENUM_TIMEFRAMES tf_bollinger = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpBollingerTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_keltner = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpKeltnerTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_stddev = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpStdDevTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_stoch = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpStochTimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_cci = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpCCITimeframe : tf_chart;
    ENUM_TIMEFRAMES tf_fisher = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpFisherTimeframe : tf_chart;
    if(InpUseEmaFilter)
    {
       hEMA_Fast = iMA(_Symbol, tf_ema, g_actualFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
       hEMA_Med  = iMA(_Symbol, tf_ema, g_actualMediumEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
       hEMA_Slow = iMA(_Symbol, tf_ema, g_actualSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    }
    if(InpUseRsiFilter) hRSI = iRSI(_Symbol, tf_rsi, g_actualRsiPeriod, PRICE_CLOSE);
    if(InpUseMacdFilter) hMACD = iMACD(_Symbol, tf_macd, g_actualMacdFastEMA, g_actualMacdSlowEMA, g_actualMacdSignal, PRICE_CLOSE);
    if(InpUseBollingerFilter)
    {
       hBollinger = iBands(_Symbol, tf_bollinger, InpBollingerPeriod, 0, InpBollingerDeviation, InpBollingerPrice);
    }
    if(InpUseStdDevFilter)
    {
       hStdDev = iStdDev(_Symbol, tf_stddev, InpStdDevPeriod, 0, MODE_SMA, PRICE_CLOSE);
    }
    if(InpUseStochFilter)
    {
       hStochastic = iStochastic(_Symbol, tf_stoch, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
    }
    if(InpUseCCIFilter)
    {
       hCCI = iCCI(_Symbol, tf_cci, InpCCIPeriod, PRICE_TYPICAL);
    }
    if(InpUseKeltnerFilter)
    {
       hEMA_Keltner = iMA(_Symbol, tf_keltner, InpKeltnerPeriod, 0, MODE_EMA, PRICE_CLOSE);
    }
    if(InpUseSAR)
    {
       hSAR = iSAR(_Symbol, tf_chart, InpSARStep, InpSARMax);
    }
    if(InpUseFisherFilter)
    {
       int fisher_bars = MathMax(1, Bars(_Symbol, tf_fisher));
       ArrayResize(g_fisher_buffer, fisher_bars);
       ArrayResize(g_fisher_price, fisher_bars);
       ArraySetAsSeries(g_fisher_buffer, true);
       ArraySetAsSeries(g_fisher_price, true);
    }
    bool isAtrNeeded = (InpSlMethod == SL_ATR_Based) || (InpExitStrategyMode == Trailing_Stop_ATR) ||
                       (InpRangeMethod == ATR_Pips) || (InpTrendMethod == ATR_Breakout) ||
                       (InpVolatilityFilter == ATR_Only || InpVolatilityFilter == ATR_and_ADX) ||
                       InpUseKeltnerFilter || (InpUseBollingerFilter && InpBollingerMode == BB_Range_Only);
    bool isAdxNeeded = (InpRangeMethod == ADX_Low) || (InpTrendMethod == ADX_Strong) ||
                       (InpVolatilityFilter == ADX_Only || InpVolatilityFilter == ATR_and_ADX) ||
                       (InpUseStochFilter && InpStochMode == Filter_Trend_Only);
    if(isAtrNeeded) hATR = iATR(_Symbol, tf_atr, g_actualAtrPeriod);
    if(InpUseKeltnerFilter)
        hATR_Keltner = iATR(_Symbol, tf_keltner, InpKeltnerAtrPeriod);
    if(isAdxNeeded) hADX = iADX(_Symbol, tf_adx, g_actualAdxPeriod);
    bool ok = (!InpUseEmaFilter || (hEMA_Fast!=INVALID_HANDLE && hEMA_Med!=INVALID_HANDLE && hEMA_Slow!=INVALID_HANDLE)) &&
              (!InpUseRsiFilter || hRSI!=INVALID_HANDLE) &&
              (!InpUseMacdFilter || hMACD!=INVALID_HANDLE) &&
              (!isAtrNeeded || hATR!=INVALID_HANDLE) &&
              (!isAdxNeeded || hADX!=INVALID_HANDLE) &&
              (!InpUseBollingerFilter || hBollinger != INVALID_HANDLE) &&
              (!InpUseStdDevFilter || hStdDev != INVALID_HANDLE) &&
              (!InpUseStochFilter || hStochastic != INVALID_HANDLE) &&
              (!InpUseCCIFilter || hCCI != INVALID_HANDLE) &&
              (!InpUseSAR || hSAR != INVALID_HANDLE) &&
              (!InpUseKeltnerFilter || (hATR_Keltner != INVALID_HANDLE && hEMA_Keltner != INVALID_HANDLE));
    if(!ok) Print("[Init] Failed to create one or more required indicator handles.");
    return ok;
}
bool GetBuffers(int shift, double &emaF, double &emaM, double &emaS, double &rsi, double &atr, double &adx, double &macd)
{
    double b[];
    if(hEMA_Fast != INVALID_HANDLE && (CopyBuffer(hEMA_Fast, 0, shift, 1, b) <= 0 || (emaF=b[0])==EMPTY_VALUE || CopyBuffer(hEMA_Med, 0, shift, 1, b) <= 0 || (emaM=b[0])==EMPTY_VALUE || CopyBuffer(hEMA_Slow, 0, shift, 1, b) <= 0 || (emaS=b[0])==EMPTY_VALUE)) return false;
    if(hRSI != INVALID_HANDLE && (CopyBuffer(hRSI, 0, shift, 1, b) <= 0 || (rsi=b[0])==EMPTY_VALUE)) return false;
    if(hMACD != INVALID_HANDLE && (CopyBuffer(hMACD, 0, shift, 1, b) <= 0 || (macd=b[0])==EMPTY_VALUE)) return false;
    if(hATR != INVALID_HANDLE && (CopyBuffer(hATR, 0, shift, 1, b) <= 0 || (atr=b[0])==EMPTY_VALUE)) return false;
    if(hADX != INVALID_HANDLE && (CopyBuffer(hADX, 0, shift, 1, b) <= 0 || (adx=b[0])==EMPTY_VALUE)) return false;
    return true;
}
bool GetCachedBuffers(int shift, double &emaF, double &emaM, double &emaS, double &rsi, double &atr, double &adx, double &macd)
{
    if(g_indicator_cache.is_valid && g_indicator_cache.last_update == TimeCurrent() && shift == 1)
     {
        emaF = g_indicator_cache.emaF; emaM = g_indicator_cache.emaM; emaS = g_indicator_cache.emaS;
        rsi = g_indicator_cache.rsi; atr = g_indicator_cache.atr; adx = g_indicator_cache.adx; macd = g_indicator_cache.macd;
        return true;
     }
    if(GetBuffers(shift, emaF, emaM, emaS, rsi, atr, adx, macd))
     {
        if(shift == 1)
        {
           g_indicator_cache.emaF = emaF;
           g_indicator_cache.emaM = emaM;
           g_indicator_cache.emaS = emaS;
           g_indicator_cache.rsi = rsi;
           g_indicator_cache.atr = atr;
           g_indicator_cache.adx = adx;
           g_indicator_cache.macd = macd;
           g_indicator_cache.last_update = TimeCurrent();
           g_indicator_cache.is_valid = true;
        }
        return true;
     }
    return false;
}
bool IsVolatilityConditionMet(double eF, double eM, double eS, double atr_val, double adx_val)
{
    bool range_ok = true, trend_ok = true;
    if(InpRangeMethod != Range_Filter_Off)
     {
        switch(InpRangeMethod)
        {
           case EMA_Distance: range_ok = IsRangeEMA(eF,eM,eS,InpRangeEmaThresholdPips); break;
           case ATR_Pips:     range_ok = (ATRtoPips(atr_val) <= InpRangeAtrThresholdPips); break;
           case ADX_Low:      range_ok = (adx_val <= g_actualRangeAdxThreshold); break;
        }
     }
    if(InpTrendMethod != Trend_Filter_Off)
     {
        switch(InpTrendMethod)
        {
           case ADX_Strong:   trend_ok = (adx_val >= g_actualTrendAdxThreshold); break;
           case ATR_Breakout: { double b[]; trend_ok = CopyBuffer(hATR, 0, 2, 1, b) > 0 && (atr_val >= b[0] * InpTrendAtrMultiplier); break; }
           case EMA_Momentum: trend_ok = ((MathAbs(eF - eS) / _Point) / GetPipPointsMultiplier() >= InpTrendEmaThreshold); break;
        }
     }
    return range_ok && trend_ok;
}
bool VolatilityFilterCheck()
{
    if(InpVolatilityFilter == Filter_Off)
        return true;
    
    bool atr_ok = true;
    bool adx_ok = true;
    
    if(InpVolatilityFilter == ATR_Only || InpVolatilityFilter == ATR_and_ADX)
    {
        if(hATR == INVALID_HANDLE)
        {
            Print("[VOLATILITY] ATR handle invalid");
            return true;
        }
        
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(hATR, 0, 1, 1, atr) > 0)
        {
            if(atr[0] < InpAtrMinThreshold)
            {
                if(InpDebug_StatusChanges)
                    PrintFormat("[VOLATILITY] ATR too low: %.5f < %.5f", atr[0], InpAtrMinThreshold);
                atr_ok = false;
            }
            else if(atr[0] > InpAtrMaxThreshold)
            {
                if(InpDebug_StatusChanges)
                    PrintFormat("[VOLATILITY] ATR too high: %.5f > %.5f", atr[0], InpAtrMaxThreshold);
                atr_ok = false;
            }
        }
        else
        {
            Print("[VOLATILITY] Failed to copy ATR buffer");
            return true;
        }
    }
    
    if(InpVolatilityFilter == ADX_Only || InpVolatilityFilter == ATR_and_ADX)
    {
        if(hADX == INVALID_HANDLE)
        {
            Print("[VOLATILITY] ADX handle invalid");
            return true;
        }
        
        double adx[];
        ArraySetAsSeries(adx, true);
        if(CopyBuffer(hADX, 0, 1, 1, adx) > 0)
        {
            if(adx[0] < InpAdxMinThreshold)
            {
                if(InpDebug_StatusChanges)
                    PrintFormat("[VOLATILITY] ADX too low: %.2f < %.2f", adx[0], InpAdxMinThreshold);
                adx_ok = false;
            }
            else if(adx[0] > InpAdxMaxThreshold)
            {
                if(InpDebug_StatusChanges)
                    PrintFormat("[VOLATILITY] ADX too high: %.2f > %.2f", adx[0], InpAdxMaxThreshold);
                adx_ok = false;
            }
        }
        else
        {
            Print("[VOLATILITY] Failed to copy ADX buffer");
            return true;
        }
    }
    
    switch(InpVolatilityFilter)
    {
        case ATR_Only:       return atr_ok;
        case ADX_Only:       return adx_ok;
        case ATR_and_ADX:    return (atr_ok && adx_ok);
        default: return true;
    }
}

struct KeltnerValues
{
    double upper;
    double middle;
    double lower;
};

KeltnerValues CalculateKeltner(int shift)
{
    KeltnerValues kelt;
    kelt.upper = 0.0;
    kelt.middle = 0.0;
    kelt.lower = 0.0;

    if(hEMA_Keltner == INVALID_HANDLE)
        return kelt;

    double ema[], atr[];
    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(hEMA_Keltner, 0, shift, 1, ema) <= 0)
        return kelt;

    kelt.middle = ema[0];
    double atr_value = 0.0;
    if(hATR_Keltner != INVALID_HANDLE && CopyBuffer(hATR_Keltner, 0, shift, 1, atr) > 0)
        atr_value = atr[0];

    kelt.upper = kelt.middle + (InpKeltnerMultiplier * atr_value);
    kelt.lower = kelt.middle - (InpKeltnerMultiplier * atr_value);
    return kelt;
}

void CalculateFisher(int start_bar = 0)
{
    if(!InpUseFisherFilter || InpFisherPeriod < 1)
        return;

    int total = Bars(_Symbol, PERIOD_CURRENT);
    if(total <= 0) return;
    if(start_bar == 0) start_bar = InpFisherPeriod;

    for(int i = start_bar; i < total && i < ArraySize(g_fisher_buffer); i++)
    {
        int highest = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpFisherPeriod, i);
        int lowest = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpFisherPeriod, i);
        double max_high = (highest >= 0) ? iHigh(_Symbol, PERIOD_CURRENT, highest) : 0.0;
        double min_low = (lowest >= 0) ? iLow(_Symbol, PERIOD_CURRENT, lowest) : 0.0;
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        g_fisher_price[i] = close;

        double value = 0.0;
        if(max_high != min_low)
            value = 2.0 * ((close - min_low) / (max_high - min_low)) - 1.0;
        value = MathMax(-0.999, MathMin(value, 0.999));

        double fisher_raw = 0.5 * MathLog((1.0 + value) / (1.0 - value));
        if(i > 0)
            g_fisher_buffer[i] = fisher_raw + 0.5 * g_fisher_buffer[i-1];
        else
            g_fisher_buffer[i] = fisher_raw;
    }
}

struct DonchianValues
{
    double upper;
    double lower;
};

DonchianValues CalculateDonchian(int shift)
{
    DonchianValues don;
    don.upper = 0.0;
    don.lower = 0.0;
    if(InpDonchianPeriod < 1)
        return don;

    int highest = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpDonchianPeriod, shift);
    int lowest = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpDonchianPeriod, shift);
    if(highest >= 0) don.upper = iHigh(_Symbol, PERIOD_CURRENT, highest);
    if(lowest >= 0) don.lower = iLow(_Symbol, PERIOD_CURRENT, lowest);
    return don;
}

bool IsIndicatorModeValid(ENUM_MODE_SETTING indicator_mode)
{
    return true; // Sin Strategy Type Filter, siempre valido
}

// Sobrecarga para ENUM_FILTER_MODE
bool IsIndicatorModeValid(ENUM_FILTER_MODE indicator_mode)
{
    return true; // Sin Strategy Type Filter, siempre valido
}

// Sobrecarga para ENUM_FILTER_MODE_BB
bool IsIndicatorModeValid(ENUM_FILTER_MODE_BB indicator_mode)
{
    return true; // Sin Strategy Type Filter, siempre valido
}

//=========================== SIGNALS =================================
//=========================== SIGNALS =================================
int GetSignal()
{
    //+------------------------------------------------------------------+
    //| ARQUITECTURA DE FILTROS EN CAPAS
    //|
    //| CAPA 1: FILTROS MACRO (Market Conditions)
    //|   - NO cuentan para InpMaxTimingFilters
    //|   - Incluye: Volatility, Range, Trend, Activity
    //|
    //| CAPA 2: FILTROS DE TIMING (Entry Signals)
    //|   - SÍ cuentan para InpMaxTimingFilters
    //|   - Incluye: EMA, RSI, MACD, Bollinger, Keltner, Stoch, CCI, Fisher, SAR, Donchian
    //+------------------------------------------------------------------+

    if(!VolatilityFilterCheck())
        return 0;

    int active_timing_filters = 0;
    int buy_votes = 0;
    int sell_votes = 0;
    double close_current = iClose(_Symbol, PERIOD_CURRENT, 1);

    // 1. BOLLINGER BANDS
    if(InpUseBollingerFilter && IsIndicatorModeValid(InpBollingerMode))
    {
        double bb_upper[], bb_middle[], bb_lower[];
        ArraySetAsSeries(bb_upper, true);
        ArraySetAsSeries(bb_middle, true);
        ArraySetAsSeries(bb_lower, true);
        bool bb_ready = CopyBuffer(hBollinger, 1, 1, 1, bb_upper) > 0 &&
                        CopyBuffer(hBollinger, 0, 1, 1, bb_middle) > 0 &&
                        CopyBuffer(hBollinger, 2, 1, 1, bb_lower) > 0;
        if(bb_ready)
        {
            active_timing_filters++;
            if(InpBollingerMode == BB_Trend_Only)
            {
                if(close_current > bb_upper[0]) buy_votes++;
                else if(close_current < bb_lower[0]) sell_votes++;
            }
            else if(InpBollingerMode == BB_Counter_Trend_Only)
            {
                if(close_current <= bb_lower[0]) buy_votes++;
                else if(close_current >= bb_upper[0]) sell_votes++;
            }
            else if(InpBollingerMode == BB_Range_Only && bb_middle[0] != 0.0 && hATR != INVALID_HANDLE)
            {
                double atr_buf[];
                ArraySetAsSeries(atr_buf, true);
                if(CopyBuffer(hATR, 0, 1, 1, atr_buf) > 0 && close_current != 0.0)
                {
                    double bb_width = (bb_upper[0] - bb_lower[0]) / MathMax(0.0000001, bb_middle[0]);
                    bool in_squeeze = (bb_width < (atr_buf[0] * 2.0 / close_current));
                    if(in_squeeze)
                        return 0;
                }
            }
        }
    }

    // 2. KELTNER CHANNEL
    if(InpUseKeltnerFilter && IsIndicatorModeValid(InpKeltnerMode))
    {
        KeltnerValues kelt = CalculateKeltner(1);
        if(kelt.middle != 0.0)
        {
            active_timing_filters++;
            if(InpKeltnerMode == Filter_Trend_Only)
            {
                if(close_current > kelt.upper) buy_votes++;
                else if(close_current < kelt.lower) sell_votes++;
            }
            else if(InpKeltnerMode == Filter_Counter_Trend_Only)
            {
                if(close_current <= kelt.lower) buy_votes++;
                else if(close_current >= kelt.upper) sell_votes++;
            }
        }
    }

    // 3. STANDARD DEVIATION
    if(InpUseStdDevFilter && hStdDev != INVALID_HANDLE)
    {
        double stddev[];
        ArraySetAsSeries(stddev, true);
        if(CopyBuffer(hStdDev, 0, 1, 1, stddev) > 0)
        {
            if(stddev[0] < InpStdDevLowThreshold)
                return 0;
        }
    }

    // 4. STOCHASTIC
    if(InpUseStochFilter && IsIndicatorModeValid(InpStochMode) && hStochastic != INVALID_HANDLE)
    {
        double stoch_k[];
        ArraySetAsSeries(stoch_k, true);
        if(CopyBuffer(hStochastic, 0, 1, 1, stoch_k) > 0)
        {
            if(InpStochMode == Filter_Counter_Trend_Only)
            {
                active_timing_filters++;
                if(stoch_k[0] < 20) buy_votes++;
                else if(stoch_k[0] > 80) sell_votes++;
            }
            else if(InpStochMode == Filter_Trend_Only)
            {
                double adx_buf[];
                ArraySetAsSeries(adx_buf, true);
                if(hADX != INVALID_HANDLE && CopyBuffer(hADX, 0, 1, 1, adx_buf) > 0)
                {
                    if(adx_buf[0] > 25)
                    {
                        active_timing_filters++;
                        if(stoch_k[0] < 20) buy_votes++;
                        else if(stoch_k[0] > 80) sell_votes++;
                    }
                }
            }
        }
    }

    // 5. CCI
    if(InpUseCCIFilter && IsIndicatorModeValid(InpCCIMode) && hCCI != INVALID_HANDLE)
    {
        double cci[];
        ArraySetAsSeries(cci, true);
        if(CopyBuffer(hCCI, 0, 1, 2, cci) > 1)
        {
            active_timing_filters++;
            if(InpCCIMode == Filter_Trend_Only)
            {
                if(cci[1] <= InpCCIExtreme && cci[0] > InpCCIExtreme) buy_votes++;
                else if(cci[1] >= -InpCCIExtreme && cci[0] < -InpCCIExtreme) sell_votes++;
            }
            else if(InpCCIMode == Filter_Counter_Trend_Only)
            {
                if(cci[0] < -200 && cci[0] > cci[1]) buy_votes++;
                else if(cci[0] > 200 && cci[0] < cci[1]) sell_votes++;
            }
        }
    }

    // 6. FISHER TRANSFORM
    if(InpUseFisherFilter && IsIndicatorModeValid(InpFisherMode))
    {
        CalculateFisher(1);
        if(ArraySize(g_fisher_buffer) > 2)
        {
            double fisher_current = g_fisher_buffer[1];
            double fisher_prev = g_fisher_buffer[2];
            active_timing_filters++;
            if(InpFisherMode == Filter_Trend_Only)
            {
                if(fisher_prev < InpFisherThreshold && fisher_current > InpFisherThreshold) buy_votes++;
                else if(fisher_prev > -InpFisherThreshold && fisher_current < -InpFisherThreshold) sell_votes++;
            }
            else if(InpFisherMode == Filter_Counter_Trend_Only)
            {
                if(fisher_current < -InpFisherThreshold) buy_votes++;
                else if(fisher_current > InpFisherThreshold) sell_votes++;
            }
        }
    }

    // 7. PARABOLIC SAR
    if(InpUseSAR && hSAR != INVALID_HANDLE)
    {
        double sar[];
        ArraySetAsSeries(sar, true);
        if(CopyBuffer(hSAR, 0, 1, 2, sar) > 1)
        {
            active_timing_filters++;
            if(sar[1] > close_current && sar[0] < close_current) buy_votes++;
            else if(sar[1] < close_current && sar[0] > close_current) sell_votes++;
        }
    }

    // 8. DONCHIAN CHANNEL
    if(InpUseDonchian)
    {
        DonchianValues don = CalculateDonchian(1);
        if(don.upper != 0.0 && don.lower != 0.0)
        {
            active_timing_filters++;
            if(close_current > don.upper) buy_votes++;
            else if(close_current < don.lower) sell_votes++;
        }
    }

    if(InpUseEmaFilter) active_timing_filters++;
    if(InpUseRsiFilter) active_timing_filters++;
    if(InpUseMacdFilter) active_timing_filters++;



    double consensus_buy = (active_timing_filters > 0) ? ((double)buy_votes / active_timing_filters) : 0.0;
    double consensus_sell = (active_timing_filters > 0) ? ((double)sell_votes / active_timing_filters) : 0.0;

    if(consensus_buy >= 0.6 && buy_votes > 0) return 1;
    if(consensus_sell >= 0.6 && sell_votes > 0) return -1;

    double eF=0, eM=0, eS=0, r=0, atr=0, adx=0, macd_val=0;
    if(!GetCachedBuffers(1,eF,eM,eS,r,atr,adx,macd_val)) return 0;
    bool macd_ok_buy = !InpUseMacdFilter || (macd_val > InpMacdMinDivergence);
    bool macd_ok_sell = !InpUseMacdFilter || (macd_val < -InpMacdMinDivergence);
    bool rsi_ok_buy = true, rsi_ok_sell = true;
    if(InpUseRsiFilter)
     {
        if(InpRsiMode == Confirm_50_Level) { rsi_ok_buy = (r >= InpRsiConfirm); rsi_ok_sell = (r <= 100.0 - InpRsiConfirm); }
        else { rsi_ok_buy = (r < InpRsiOverbought); rsi_ok_sell = (r > InpRsiOversold); }
     }
    int dir = 0;
    if(InpUseEmaFilter)
     {
        double price = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
        bool bullTrend = (eF>eM && eM>eS), bearTrend = (eF<eM && eM<eS);
        switch(InpEmaRule)
        {
           case EMA_Trend_Only:
             if(bullTrend && price>eF && rsi_ok_buy && macd_ok_buy) dir = 1;
             if(bearTrend && price<eF && rsi_ok_sell && macd_ok_sell) dir = -1;
             break;
           case EMA_Counter_Trend_Only:
             {
                double threshold = InpRangeEmaThresholdPips * GetPipPointsMultiplier() * _Point;
                bool rsi_ct_buy = !InpUseRsiFilter || (r <= InpRsiOversold);
                bool rsi_ct_sell = !InpUseRsiFilter || (r >= InpRsiOverbought);
                 if(bearTrend && rsi_ct_buy && price <= (eS + threshold) && macd_ok_buy) dir = 1;
                 if(bullTrend && rsi_ct_sell && price >= (eS - threshold) && macd_ok_sell) dir = -1;
                 break;
              }
           case EMA_Range_Only:
             {
                 if(InpRangeMethod == Range_Filter_Off || IsVolatilityConditionMet(eF,eM,eS,atr,adx))
                 {
                    double ema_avg = (eF + eM + eS) / 3.0;
                    double threshold = InpRangeEmaThresholdPips * GetPipPointsMultiplier() * _Point;
                    if(InpUseRsiFilter && InpRsiMode == Overbought_Oversold)
                    {
                       if(r <= InpRsiOversold && price < ema_avg - threshold && macd_ok_buy) dir = 1;
                       else if(r >= InpRsiOverbought && price > ema_avg + threshold && macd_ok_sell) dir = -1;
                    }
                    else
                    {
                       if(price < ema_avg - threshold && macd_ok_buy) dir = 1;
                       else if(price > ema_avg + threshold && macd_ok_sell) dir = -1;
                    }
                 }
                 break;
              }
        }
     }
    else if(InpUseRsiFilter)
     {
        if(InpRsiMode==Overbought_Oversold) { if(r <= InpRsiOversold) dir = 1; else if(r >= InpRsiOverbought) dir = -1; }
        else { if(r >= InpRsiConfirm) dir = 1; else if(r <= 100.0 - InpRsiConfirm) dir = -1; }
     }
    if(InpTradeDirection == Buys_Only && dir < 0) dir=0;
    if(InpTradeDirection == Sells_Only && dir > 0) dir=0;
    return dir;
}
bool ProcessDelayedEntry(int current_signal)
{
    if(InpEntryMode != Delayed_Market_Order) return (current_signal != 0);
    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)InpSignalTF;
    if(current_signal != 0 && !g_delayed_signal.is_active)
    {
       if(((iHigh(_Symbol, tf, 1) - iLow(_Symbol, tf, 1)) / _Point) / GetPipPointsMultiplier() >= InpMinCandleRangePips)
       {
          g_delayed_signal.signal = current_signal;
          g_delayed_signal.first_seen = TimeCurrent();
          g_delayed_signal.bars_waited = 0;
          g_delayed_signal.entry_price = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
          g_delayed_signal.is_active = true;
          if(false) PrintFormat("[DELAYED] Signal detected: %s, waiting %d bars", current_signal > 0 ? "BUY" : "SELL", InpDelayBars);
       }
       return false;
    }
    if(g_delayed_signal.is_active)
    {
       if(g_delayed_signal.first_seen > 0 && Bars(_Symbol, tf, g_delayed_signal.first_seen, TimeCurrent()) >= InpDelayBars)
       {
          g_delayed_signal.is_active = false;
          return true;
       }
       if(current_signal != g_delayed_signal.signal) g_delayed_signal.is_active = false;
    }
    return false;
}
//=========================== ORDERS =================================
double CalculateTP(long ticket, string symbol, double entry_price,
                   double stop_loss, ENUM_POSITION_TYPE pos_type){
    string pos_type_str = (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
    PrintFormat("[DIAG.CalculateTP] START | Ticket:%I64d | Symbol:%s | Entry:%.5f | SL:%.5f | Type:%s | CurrentRR:%.2f",
                ticket, symbol, entry_price, stop_loss, pos_type_str, g_actualRiskRewardRatio);
    if(g_actualRiskRewardRatio <= 0.0 || stop_loss == 0.0)
    {
        if(false)
            PrintFormat("[CalculateTP] RR=0 o SL=0, retornando TP=0 | Ticket:%I64d", ticket);
        return 0.0;
    }
    double sl_distance = MathAbs(entry_price - stop_loss);
    double tp_distance = sl_distance * g_actualRiskRewardRatio;
    double calculated_tp = 0.0;
    if(pos_type == POSITION_TYPE_BUY)
    {
        calculated_tp = entry_price + tp_distance;
    }
    else
    {
        calculated_tp = entry_price - tp_distance;
    }
    long stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double min_dist_price = (stops_level == 0 ? 10 : stops_level) * SymbolInfoDouble(symbol, SYMBOL_POINT);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double current_price = (pos_type == POSITION_TYPE_BUY) ? bid : ask;
    if(pos_type == POSITION_TYPE_BUY)
    {
        if(calculated_tp <= current_price + min_dist_price)
        {
            calculated_tp = current_price + min_dist_price * 1.5;
            if(false)
                PrintFormat("[CalculateTP] TP BUY ajustado por distancia minima | Ticket:%I64d | Original:%.5f | Ajustado:%.5f",
                            ticket, (current_price + tp_distance), calculated_tp);
        }
    }
    else
    {
        if(calculated_tp >= current_price - min_dist_price)
        {
            calculated_tp = current_price - min_dist_price * 1.5;
            if(false)
                PrintFormat("[CalculateTP] TP SELL ajustado por distancia minima | Ticket:%I64d | Original:%.5f | Ajustado:%.5f",
                            ticket, (current_price - tp_distance), calculated_tp);
        }
    }
    calculated_tp = NormalizeDouble(calculated_tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
    PrintFormat("[DIAG.CalculateTP] END | Ticket:%I64d | FinalTP:%.5f | SL_Distance:%.5f | TP_Distance:%.5f | RR_Used:%.2f",
                ticket, calculated_tp, sl_distance, tp_distance, g_actualRiskRewardRatio);
    if(false)
        PrintFormat("[CalculateTP] Calculado | Ticket:%I64d | Symbol:%s | Entry:%.5f | SL:%.5f | TP:%.5f | RR:%.2f",
                    ticket, symbol, entry_price, stop_loss, calculated_tp, g_actualRiskRewardRatio);
    return calculated_tp;
}
void RemoveAllTakeProfits(){
    if(false)
        PrintFormat("[RemoveAllTPs] Iniciando proceso de remocion de TPs | Posiciones:%d | Array:%d",
                     PositionsTotal(), ArraySize(g_tp_management));
    int removed_count = 0;
    int processed_count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!pos.SelectByIndex(i)) continue;
        // CR?TICO: Solo procesa posiciones del S?MBOLO de esta instancia
        if(pos.Symbol() != _Symbol) continue;
        if((long)pos.Magic() != InpMagicNumber) continue;
        processed_count++;
        double current_tp = pos.TakeProfit();
        // CR?TICO: Si el TP es 0, limpia el registro del array si existe
        if(current_tp == 0.0)
        {
            // Busca y elimina del array si existe
            for(int k = ArraySize(g_tp_management) - 1; k >= 0; k--)
            {
                if(g_tp_management[k].ticket == (long)pos.Ticket() &&
                   g_tp_management[k].symbol == pos.Symbol())
                {
                    // Elimina del array
                    for(int m = k; m < ArraySize(g_tp_management) - 1; m++)
                    {
                        g_tp_management[m] = g_tp_management[m + 1];
                    }
                    ArrayResize(g_tp_management, ArraySize(g_tp_management) - 1);
                    if(false)
                        PrintFormat("[RemoveAllTPs] Posicion ya sin TP, limpiando del array | Ticket:%I64u | Symbol:%s",
                                     pos.Ticket(), pos.Symbol());
                    break;
                }
            }
            continue;
        }
        bool already_saved = false;
        int saved_index = -1;
        for(int k = 0; k < ArraySize(g_tp_management); k++)
        {
            if(g_tp_management[k].ticket == (long)pos.Ticket() &&
                g_tp_management[k].symbol == pos.Symbol())
            {
                already_saved = true;
                saved_index = k;
                // CR?TICO: Si el TP actual NO es 0 pero is_removed es true,
                // significa que fue restaurado fuera de nuestro control
                // Actualizamos el array
                if(g_tp_management[k].is_removed && current_tp != 0.0)
                {
                    g_tp_management[k].tp_original = current_tp;
                    g_tp_management[k].is_removed = false;
                    if(false)
                        PrintFormat("[RemoveAllTPs] TP fue restaurado externamente, actualizando array | Ticket:%I64u | NewTP:%.5f",
                                    pos.Ticket(), current_tp);
                }
                break;
            }
        }
        if(!already_saved)
        {
            TPManagement rec;
            rec.ticket = (long)pos.Ticket();
            rec.symbol = pos.Symbol();
            rec.tp_original = current_tp;
            rec.saved_time = TimeCurrent();
            rec.is_removed = false;
            int sz = ArraySize(g_tp_management);
            ArrayResize(g_tp_management, sz + 1);
            g_tp_management[sz] = rec;
            saved_index = sz;
            if(false)
                PrintFormat("[RemoveAllTPs] TP guardado | Ticket:%I64u | Symbol:%s | TP:%.5f",
                            pos.Ticket(), pos.Symbol(), current_tp);
        }
        else
        {
            if(false)
                PrintFormat("[RemoveAllTPs] TP ya estaba guardado | Ticket:%I64u | Symbol:%s | TP:%.5f | IsRemoved:%d",
                            pos.Ticket(), pos.Symbol(), current_tp, g_tp_management[saved_index].is_removed ? 1 : 0);
        }
        if(!g_tp_management[saved_index].is_removed)
        {
            if(trade.PositionModify(pos.Ticket(), pos.StopLoss(), 0.0))
            {
                g_tp_management[saved_index].is_removed = true;
                removed_count++;
                if(false)
                    PrintFormat("[RemoveAllTPs] TP REMOVIDO | Ticket:%I64u | Symbol:%s | TPOriginal:%.5f",
                                pos.Ticket(), pos.Symbol(), g_tp_management[saved_index].tp_original);
            }
            else
            {
                PrintFormat("[ERROR.RemoveTPs] Failed to remove TP | Ticket:%I64u | Error:%d | RetCode:%d",
                            pos.Ticket(), GetLastError(), trade.ResultRetcode());
                if(false)
                    PrintFormat("[RemoveAllTPs] ERROR al remover TP | Ticket:%I64u | Error:%d",
                                pos.Ticket(), GetLastError());
            }
        }
        else
        {
            if(false)
                PrintFormat("[RemoveAllTPs] TP ya marcado como removido | Ticket:%I64u", pos.Ticket());
        }
    }
    if(false)
        PrintFormat("[RemoveAllTPs] Proceso completado | TPs removidos:%d | Total en array:%d",
                    removed_count, ArraySize(g_tp_management));
    if(removed_count > 0)
    {
        g_tp_status = 1;
        g_tp_status_state = 1;
    }
}
void RestoreAllTakeProfits(){
    if(ArraySize(g_tp_management) == 0)
    {
        if(false)
            Print("[RestoreAllTPs] Array vacio, nada que restaurar");
        return;
    }
    if(false)
        PrintFormat("[RestoreAllTPs] Iniciando restauracion | TPs en array:%d", ArraySize(g_tp_management));
    int restored_count = 0;
    int recalculated_count = 0;
    for(int k = ArraySize(g_tp_management) - 1; k >= 0; k--)
    {
        // CR?TICO: Solo procesa registros del S?MBOLO de esta instancia
        if(g_tp_management[k].symbol != _Symbol) continue;
        if(!pos.SelectByTicket((ulong)g_tp_management[k].ticket))
        {
            if(false)
                PrintFormat("[RestoreAllTPs] Posicion cerrada, limpiando del array | Ticket:%I64d",
                             g_tp_management[k].ticket);
            for(int m = k; m < ArraySize(g_tp_management) - 1; m++)
            {
                g_tp_management[m] = g_tp_management[m + 1];
            }
            ArrayResize(g_tp_management, ArraySize(g_tp_management) - 1);
            continue;
        }
        if(pos.Symbol() != g_tp_management[k].symbol)
        {
            if(false)
                PrintFormat("[RestoreAllTPs] Simbolo no coincide | Ticket:%I64d | Esperado:%s | Real:%s",
                            g_tp_management[k].ticket, g_tp_management[k].symbol, pos.Symbol());
            continue;
        }
        if(!g_tp_management[k].is_removed)
        {
            if(false)
                PrintFormat("[RestoreAllTPs] TP no estaba marcado como removido | Ticket:%I64d",
                             g_tp_management[k].ticket);
            continue;
        }
        double tp_to_restore = g_tp_management[k].tp_original;
        double current_price = (pos.PositionType() == POSITION_TYPE_BUY) ?
                                SymbolInfoDouble(pos.Symbol(), SYMBOL_BID) :
                                SymbolInfoDouble(pos.Symbol(), SYMBOL_ASK);
        double current_sl = pos.StopLoss();
        long stops_level = SymbolInfoInteger(pos.Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
        double min_dist_price = (stops_level == 0 ? 10 : stops_level) * SymbolInfoDouble(pos.Symbol(), SYMBOL_POINT);
        bool tp_is_valid = false;
        if(pos.PositionType() == POSITION_TYPE_BUY)
        {
            tp_is_valid = (tp_to_restore > current_price + min_dist_price);
        }
        else
        {
            tp_is_valid = (tp_to_restore < current_price - min_dist_price);
        }
        if(tp_is_valid)
        {
            if(trade.PositionModify(pos.Ticket(), current_sl, tp_to_restore))
            {
                restored_count++;
                if(false)
                    PrintFormat("[RestoreAllTPs] TP RESTAURADO | Ticket:%I64d | Symbol:%s | TP:%.5f",
                                g_tp_management[k].ticket, g_tp_management[k].symbol, tp_to_restore);
            }
            else
            {
                if(false)
                    PrintFormat("[RestoreAllTPs] ERROR al restaurar TP | Ticket:%I64d | Error:%d",
                                g_tp_management[k].ticket, GetLastError());
            }
        }
        else
        {
            double new_tp = CalculateTP(g_tp_management[k].ticket,
                                        pos.Symbol(),
                                        pos.PriceOpen(),
                                        current_sl,
                                        (ENUM_POSITION_TYPE)pos.PositionType());
            if(new_tp > 0.0)
            {
                if(trade.PositionModify(pos.Ticket(), current_sl, new_tp))
                {
                    recalculated_count++;
                    if(false)
                        PrintFormat("[RestoreAllTPs] TP RECALCULADO (original invalido) | Ticket:%I64d | Symbol:%s | TPOriginal:%.5f | TPNuevo:%.5f",
                                    g_tp_management[k].ticket, g_tp_management[k].symbol, tp_to_restore, new_tp);
                }
                else
                {
                    if(false)
                        PrintFormat("[RestoreAllTPs] ERROR al colocar TP recalculado | Ticket:%I64d | Error:%d",
                                    g_tp_management[k].ticket, GetLastError());
                }
            }
            else
            {
                if(false)
                    PrintFormat("[RestoreAllTPs] No se pudo calcular nuevo TP | Ticket:%I64d", g_tp_management[k].ticket);
            }
        }
        for(int m = k; m < ArraySize(g_tp_management) - 1; m++)
        {
            g_tp_management[m] = g_tp_management[m + 1];
        }
        ArrayResize(g_tp_management, ArraySize(g_tp_management) - 1);
    }
    if(false)
        PrintFormat("[RestoreAllTPs] Proceso completado | Restaurados:%d | Recalculados:%d | Restantes en array:%d",
                    restored_count, recalculated_count, ArraySize(g_tp_management));
    if(restored_count > 0 || recalculated_count > 0)
    {
        g_tp_status = 2;
        g_tp_status_state = 2;
        g_tp_restored_end_time = (datetime)(TimeCurrent() + 5 * 60);
    }
}
void EnsureTPExists(){
    if(false)
        PrintFormat("[EnsureTP] Verificando posiciones sin TP | Total posiciones:%d", PositionsTotal());
    //PrintFormat("[DIAG.EnsureTP] START | TotalPositions:%d | CurrentRR:%.2f | Symbol:%s | Magic:%d",
    //            PositionsTotal(), g_actualRiskRewardRatio, _Symbol, InpMagicNumber);
    int tps_added = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!pos.SelectByIndex(i)) continue;
        // CR?TICO: Solo procesa posiciones del S?MBOLO de esta instancia
        if(pos.Symbol() != _Symbol) continue;
        if((long)pos.Magic() != InpMagicNumber) continue;
        double current_tp = pos.TakeProfit();
        if(current_tp != 0.0)
        {
            continue;
        }
        //PrintFormat("[DIAG.EnsureTP] Found position without TP | Ticket:%I64u | Symbol:%s | CurrentSL:%.5f",
        //            pos.Ticket(), pos.Symbol(), pos.StopLoss());
        double current_sl = pos.StopLoss();
        if(current_sl == 0.0)
        {
            if(false)
                PrintFormat("[EnsureTP] Posicion sin SL, no se puede calcular TP | Ticket:%I64u | Symbol:%s",
                            pos.Ticket(), pos.Symbol());
            continue;
        }
        bool is_in_management = false;
        for(int k = 0; k < ArraySize(g_tp_management); k++)
        {
            if(g_tp_management[k].ticket == (long)pos.Ticket() &&
                g_tp_management[k].symbol == pos.Symbol() &&
               g_tp_management[k].is_removed)
            {
                is_in_management = true;
                if(false)
                    PrintFormat("[EnsureTP] Posicion en gestion de noticias, omitiendo | Ticket:%I64u | Symbol:%s",
                                pos.Ticket(), pos.Symbol());
                break;
            }
        }
        if(is_in_management)
        {
            continue;
        }
        double new_tp = CalculateTP((long)pos.Ticket(),
                                   pos.Symbol(),
                                   pos.PriceOpen(),
                                   current_sl,
                                   (ENUM_POSITION_TYPE)pos.PositionType());
        if(new_tp > 0.0)
        {
            if(trade.PositionModify(pos.Ticket(), current_sl, new_tp))
            {
                tps_added++;
                if(false)
                    PrintFormat("[EnsureTP] TP FORZADO colocado | Ticket:%I64u | Symbol:%s | Entry:%.5f | SL:%.5f | TP:%.5f",
                                pos.Ticket(), pos.Symbol(), pos.PriceOpen(), current_sl, new_tp);
            }
            else
            {
                PrintFormat("[ERROR.EnsureTP] Failed to place TP | Ticket:%I64u | Error:%d | RetCode:%d",
                            pos.Ticket(), GetLastError(), trade.ResultRetcode());
                if(false)
                    PrintFormat("[EnsureTP] ERROR al colocar TP | Ticket:%I64u | Symbol:%s | Error:%d",
                                pos.Ticket(), pos.Symbol(), GetLastError());
            }
        }
        else
        {
            if(false)
                PrintFormat("[EnsureTP] No se pudo calcular TP (RR=0 o invalido) | Ticket:%I64u | Symbol:%s",
                            pos.Ticket(), pos.Symbol());
        }
    }
    //PrintFormat("[DIAG.EnsureTP] END | TPsAdded:%d | UsedRR:%.2f",
    //            tps_added, g_actualRiskRewardRatio);
    if(tps_added > 0 && false)
        PrintFormat("[EnsureTP] Proceso completado | TPs agregados:%d", tps_added);
}
void ManageAllTakeProfit(){
    if(TimeCurrent() - g_last_tp_check < 3)
    {
        return;
    }
    g_last_tp_check = TimeCurrent();
    bool is_tp_managed_by_news = (InpNewsFilterMode == Manage_Open_Trades_Only ||
                                  InpNewsFilterMode == Block_And_Manage);
    bool in_news_window = IsInNewsWindow();
    if(!is_tp_managed_by_news)
    {
        if(ArraySize(g_tp_management) > 0)
        {
            if(false)
                PrintFormat("[ManageAllTP] Filtro de noticias OFF/Block-Only, restaurando %d TPs guardados",
                            ArraySize(g_tp_management));
            RestoreAllTakeProfits();
        }
        EnsureTPExists();
        return;
    }
    if(false)
        PrintFormat("[ManageAllTP] Estado | NewsManaged:%d | InWindow:%d | TPsEnArray:%d",
                    is_tp_managed_by_news ? 1 : 0,
                    in_news_window ? 1 : 0,
                    ArraySize(g_tp_management));
    if(in_news_window)
    {
        RemoveAllTakeProfits();
    }
    else
    {
        if(ArraySize(g_tp_management) > 0)
        {
            RestoreAllTakeProfits();
        }
        EnsureTPExists();
    }
}
int OpenPositionsCount()
{
    int total=0;
    for(int i=0;i<PositionsTotal();i++)
     {
        if(pos.SelectByIndex(i))
        {
            long mg = (long)pos.Magic();
            string sym = pos.Symbol();
            string cmt = pos.Comment();
            if(IsPositionFromThisChart(mg, sym, cmt)) total++;
        }
     }
    return total;
}
bool GlobalLimitsOK(double lots_of_this_trade, string &reason)
{
    reason = "";
    if(InpMaxAccountOpenTrades > 0 && PositionsTotal() >= InpMaxAccountOpenTrades)
    {
        reason = StringFormat("Max account trades (%d) reached", InpMaxAccountOpenTrades);
        return false;
    }
    if(InpMaxAccountOpenLots > 0.0)
    {
       double total_open_lots = 0;
       for(int i=0; i < PositionsTotal(); i++) if(pos.SelectByIndex(i)) total_open_lots += pos.Volume();
       if(total_open_lots + lots_of_this_trade > InpMaxAccountOpenLots)
       {
           reason = "Max account lots exceeded";
           return false;
       }
    }
    return true;
}
bool IsCooldownAfterCloseActive(double &remaining_minutes)
{
    remaining_minutes = 0.0;
    if(InpCooldownMinutesAfterClose <= 0) return false;
    if(g_last_position_close_time <= 0) return false;
    long cooldown_seconds = (long)InpCooldownMinutesAfterClose * 60;
    long elapsed = TimeCurrent() - g_last_position_close_time;
    if(elapsed < cooldown_seconds)
    {
        remaining_minutes = (double)(cooldown_seconds - elapsed) / 60.0;
        return true;
    }
    return false;
}
bool EvaluateTradeConditions(int signal, double lots, double sl_points, string &reason)
{
    reason = "";
    if(g_isEaStopped || g_daily_loss_was_reached)
    {
        if(InpDebug_StatusChanges)
            PrintFormat("[ENTRY BLOCKED] EA is stopped (Stopped=%d, DailyLoss=%d)",
                        g_isEaStopped ? 1 : 0, g_daily_loss_was_reached ? 1 : 0);
        reason = "EA stopped or daily loss hit";
        return false;
    }
    if(InpMinBarsAfterLoss > 0 && g_last_close_was_loss)
    {
        int open_positions_now = OpenPositionsCount();
        if(open_positions_now == 0 && g_last_position_close_time > 0)
        {
            int bars_since_loss = (int)((TimeCurrent() - g_last_position_close_time) /
                                        PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF));
            if(bars_since_loss < InpMinBarsAfterLoss)
            {
                if(InpDebug_StatusChanges)
                    PrintFormat("[ENTRY BLOCKED] Waiting cooldown after loss: %d/%d bars",
                                bars_since_loss, InpMinBarsAfterLoss);
                reason = StringFormat("Cooldown after loss: %d/%d bars",
                                      bars_since_loss, InpMinBarsAfterLoss);
                return false;
            }
        }
    }
    if((InpNewsFilterMode == Block_New_Trades_Only || InpNewsFilterMode == Block_And_Manage) && IsInNewsWindow())
    {
        reason = "News filter window active";
        return false;
    }
    if(IsLateFridayEntryBlocked())
    {
        reason = "Late Friday block";
        return false;
    }
    double cooldown_minutes = 0.0;
    if(IsCooldownAfterCloseActive(cooldown_minutes))
    {
        reason = StringFormat("Cooldown after close (%.1f min remaining)", cooldown_minutes);
        return false;
    }
    string hedging_reason = "";
    if(HasOppositeDirectionTrade(signal, hedging_reason))
    {
        reason = (hedging_reason == "" ? "Hedging filter" : hedging_reason);
        return false;
    }
    string additional_reason = "";
    if(!CanOpenAdditionalTrade(signal, additional_reason))
    {
        reason = (additional_reason == "" ? "Additional trade filter" : additional_reason);
        return false;
    }
    string global_reason = "";
    if(!GlobalLimitsOK(lots, global_reason))
    {
        reason = (global_reason == "" ? "Account/global limits" : global_reason);
        return false;
    }
    if(!IsTradingSessionActive())
    {
        reason = "Trading session inactive";
        return false;
    }
    if(!SpreadOK())
    {
        reason = "Spread filter triggered";
        return false;
    }
    if(!RiskOverlaysOK())
    {
        reason = "Risk overlays active";
        return false;
    }
    string consistency_reason = "";
    if(!CheckConsistencyRules(lots, sl_points, consistency_reason))
    {
        reason = (consistency_reason == "" ? "Consistency rules" : consistency_reason);
        return false;
    }
    if(!IsMarketActive())
    {
        reason = "Market activity filter";
        return false;
    }
    string corr_reason = "";
    if(!IsCorrelationOK_Check(corr_reason))
    {
        reason = (corr_reason == "" ? "Correlation filter" : corr_reason);
        return false;
    }
    return true;
}
bool AllTradeConditionsMet(int signal, double lots, double sl_points)
{
    string dummy_reason;
    return EvaluateTradeConditions(signal, lots, sl_points, dummy_reason);
}
void PlaceOrder(int signal)  {  
    if(signal==0) return;  
    double sl_points = DetermineSLPoints();
    double lots = CalcLotsByRisk(sl_points);  
    if(lots <= 0) return;  
    if(!AllTradeConditionsMet(signal, lots, sl_points)) return;  
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippagePoints);
    
    LoadNewsModeState();

    if(signal > 0)  
    {  
        double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);  
        double sl_price = price - sl_points * _Point;  
        trade.Buy(lots, _Symbol, price, sl_price, 0.0, GetEAComment());  
        if(trade.ResultRetcode() == TRADE_RETCODE_DONE)  
        {  
            ulong result_ticket = trade.ResultOrder();  
              
            // CR?TICO: Esperar a que la posici?n est? disponible  
            bool position_found = false;  
            int attempts = 0;  
            while(!position_found && attempts < 50)  
            {  
                for(int i = 0; i < PositionsTotal(); i++)  
                {  
                    if(pos.SelectByIndex(i) && pos.Ticket() == result_ticket)  
                    {  
                        position_found = true;  
                        break;  
                    }  
                }  
                if(!position_found)  
                {  
                    Sleep(10);  
                    attempts++;  
                }  
            }  
              
            if(position_found && pos.SelectByTicket(result_ticket))  
            {  
                double actual_entry = pos.PriceOpen();  
                double actual_sl = pos.StopLoss();  
                double tp_price = CalculateTP((long)result_ticket, _Symbol, actual_entry, actual_sl, POSITION_TYPE_BUY);  
                  
                if(tp_price > 0.0)  
                {  
                    // Usar el ticket espec?fico para modificar  
                    if(trade.PositionModify(result_ticket, actual_sl, tp_price))  
                    {  
                        if(false)  
                            PrintFormat("[PlaceOrder] BUY TP colocado | Ticket:%lu | Entry:%.5f | SL:%.5f | TP:%.5f",   
                                result_ticket, actual_entry, actual_sl, tp_price);  
                    }  
                    else  
                    {  
                        PrintFormat("[ERROR] No se pudo colocar TP | Ticket:%lu | Error:%d", result_ticket, GetLastError());  
                    }  
                }  
            }  
        }  
    }  
    else  
    {  
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);  
        double sl_price = price + sl_points * _Point;  
        trade.Sell(lots, _Symbol, price, sl_price, 0.0, GetEAComment());  
        if(trade.ResultRetcode() == TRADE_RETCODE_DONE)  
        {  
            ulong result_ticket = trade.ResultOrder();  
              
            // CR?TICO: Esperar a que la posici?n est? disponible  
            bool position_found = false;  
            int attempts = 0;  
            while(!position_found && attempts < 50)  
            {  
                for(int i = 0; i < PositionsTotal(); i++)  
                {  
                    if(pos.SelectByIndex(i) && pos.Ticket() == result_ticket)  
                    {  
                        position_found = true;  
                        break;  
                    }  
                }  
                if(!position_found)  
                {  
                    Sleep(10);  
                    attempts++;  
                }  
            }  
              
            if(position_found && pos.SelectByTicket(result_ticket))  
            {  
                double actual_entry = pos.PriceOpen();  
                double actual_sl = pos.StopLoss();  
                double tp_price = CalculateTP((long)result_ticket, _Symbol, actual_entry, actual_sl, POSITION_TYPE_SELL);  
                  
                if(tp_price > 0.0)  
                {  
                    // Usar el ticket espec?fico para modificar  
                    if(trade.PositionModify(result_ticket, actual_sl, tp_price))  
                    {  
                        if(false)  
                            PrintFormat("[PlaceOrder] SELL TP colocado | Ticket:%lu | Entry:%.5f | SL:%.5f | TP:%.5f",   
                                result_ticket, actual_entry, actual_sl, tp_price);  
                    }  
                    else  
                    {  
                        PrintFormat("[ERROR] No se pudo colocar TP | Ticket:%lu | Error:%d", result_ticket, GetLastError());  
                    }  
                }  
            }  
        }  
    }  
    if(ReductionTradesRemaining > 0) ReductionTradesRemaining--;  
    g_last_trade_time = TimeCurrent();
    SaveCriticalState(); // Guardar inmediatamente  
}  
//=========================== LIFECYCLE ==============================
//+------------------------------------------------------------------+
//| Sistema de Persistencia de Variables Cr?ticas                    |
//+------------------------------------------------------------------+
string GetPersistenceKey(string var_name)
{
    return StringFormat("EA_%s_%s_%d_%I64d", var_name, _Symbol, InpMagicNumber, ChartID());
}

void SaveCriticalState()
{
    GlobalVariableSet(GetPersistenceKey("LastTradeTime"), (double)g_last_trade_time);
    GlobalVariableSet(GetPersistenceKey("LastCloseTime"), (double)g_last_position_close_time);
    GlobalVariableSet(GetPersistenceKey("IsStopped"), g_isEaStopped ? 1.0 : 0.0);
    GlobalVariableSet(GetPersistenceKey("ResetTime"), (double)g_resetTime);
    GlobalVariableSet(GetPersistenceKey("DailyStartBalance"), g_dailyStartBalance);
    if(InpDebug_Persistence)
        Print("[FASE 1] Persistence: state saved successfully");
}

void RestoreCriticalState()
{
    bool state_restored = false;
    
    if(GlobalVariableCheck(GetPersistenceKey("LastTradeTime")))
    {
        g_last_trade_time = (datetime)GlobalVariableGet(GetPersistenceKey("LastTradeTime"));
        state_restored = true;
    }
    
    if(GlobalVariableCheck(GetPersistenceKey("LastCloseTime")))
    {
        g_last_position_close_time = (datetime)GlobalVariableGet(GetPersistenceKey("LastCloseTime"));
        state_restored = true;
    }
    
    if(GlobalVariableCheck(GetPersistenceKey("IsStopped")))
    {
        g_isEaStopped = (GlobalVariableGet(GetPersistenceKey("IsStopped")) > 0.5);
        state_restored = true;
    }
    
    if(GlobalVariableCheck(GetPersistenceKey("ResetTime")))
    {
        g_resetTime = (datetime)GlobalVariableGet(GetPersistenceKey("ResetTime"));
        state_restored = true;
    }
    
    if(GlobalVariableCheck(GetPersistenceKey("DailyStartBalance")))
    {
        double saved_balance = GlobalVariableGet(GetPersistenceKey("DailyStartBalance"));
        if(saved_balance > 0)
        {
            g_dailyStartBalance = saved_balance;
            state_restored = true;
        }
    }
    
    if(InpDebug_Persistence)
    {
        if(state_restored)
        {
            Print("[FASE 1] Persistence restored successfully");
            PrintFormat("  LastTradeTime: %s", TimeToString(g_last_trade_time));
            PrintFormat("  LastCloseTime: %s", TimeToString(g_last_position_close_time));
            PrintFormat("  IsStopped: %s", g_isEaStopped ? "TRUE" : "FALSE");
            PrintFormat("  ResetTime: %s", TimeToString(g_resetTime));
            PrintFormat("  DailyStartBalance: $%.2f", g_dailyStartBalance);
        }
        else
        {
            Print("[FASE 1] No saved state found (first run)");
        }
    }
}

void ApplyUniquenessSettings()
{
    g_actualFastEmaPeriod = (int)InpFastEmaPeriod; g_actualMediumEmaPeriod = (int)InpMediumEmaPeriod; g_actualSlowEmaPeriod = (int)InpSlowEmaPeriod;
    g_actualRsiPeriod = InpRsiPeriod; g_actualAtrSlMultiplier = InpAtrSlMultiplier_SL; g_actualRiskRewardRatio = InpRiskRewardRatio;
    g_actualFixedSlPoints = InpFixedSL_In_Points; g_actualMacdFastEMA = InpMacdFastEMA; g_actualMacdSlowEMA = InpMacdSlowEMA;
    g_actualMacdSignal = InpMacdSignal; g_actualAtrPeriod = InpAtrPeriod; g_actualAdxPeriod = InpAdxPeriod; g_actualRangeAdxThreshold = InpRangeAdxThreshold;
    g_actualTrendAdxThreshold = InpTrendAdxThreshold;
    if(InpUniquenessLevel == Unique_Trades_Off) return;
    MathSrand(GetTickCount());
    if(InpUniquenessLevel >= Unique_Trades_Low)
    {
       g_actualAtrSlMultiplier *= (1.0 + (MathRand() / 32767.0) * 0.1 - 0.05);
       g_actualFixedSlPoints *= (1.0 + (MathRand() / 32767.0) * 0.1 - 0.05);
       g_actualRiskRewardRatio *= (1.0 + (MathRand() / 32767.0) * 0.1 - 0.05);
    }
    if(InpUniquenessLevel >= Unique_Trades_Medium)
    {
       g_actualRsiPeriod = MathMax(5, InpRsiPeriod + (MathRand() % 5 - 2));
       g_actualMacdFastEMA = MathMax(5, InpMacdFastEMA + (MathRand() % 3 - 1));
       g_actualMacdSlowEMA = MathMax(g_actualMacdFastEMA + 5, InpMacdSlowEMA + (MathRand() % 5 - 2));
       g_actualMacdSignal = MathMax(2, InpMacdSignal + (MathRand() % 3 - 1));
    }
    if(InpUniquenessLevel >= Unique_Trades_High)
    {
       g_actualFastEmaPeriod = MathMax(2, (int)InpFastEmaPeriod + (MathRand() % 3 - 1));
       g_actualMediumEmaPeriod = MathMax(g_actualFastEmaPeriod + 2, (int)InpMediumEmaPeriod + (MathRand() % 5 - 2));
       g_actualSlowEmaPeriod = MathMax(g_actualMediumEmaPeriod + 5, (int)InpSlowEmaPeriod + (MathRand() % 11 - 5));
       g_actualAtrPeriod = MathMax(5, InpAtrPeriod + (MathRand() % 5 - 2));
       g_actualAdxPeriod = MathMax(5, InpAdxPeriod + (MathRand() % 5 - 2));
       g_actualRangeAdxThreshold *= (1.0 + (MathRand() / 32767.0) * 0.2 - 0.1);
       g_actualTrendAdxThreshold *= (1.0 + (MathRand() / 32767.0) * 0.2 - 0.1);
    }
}
bool ValidateIndicatorParameters()
{
    if((InpUseEmaFilter && ((int)InpFastEmaPeriod >= (int)InpMediumEmaPeriod || (int)InpMediumEmaPeriod >= (int)InpSlowEmaPeriod)) ||
       (InpUseMacdFilter && (InpMacdFastEMA >= InpMacdSlowEMA || InpMacdSignal < 1)) ||
       (InpUseRsiFilter && InpRsiPeriod < 2) || (InpAtrPeriod < 1) || (InpAdxPeriod < 1))
    {
        Print("ERROR: Invalid initial indicator parameters.");
        return false;
    }
    return true;
}
void CreateVisualIndicators()
{
#ifdef MQL5_VISUAL_MODE
    for(int i = ChartIndicatorsTotal(0, 0) - 1; i >= 0; i--) ChartIndicatorDelete(0, 0, ChartIndicatorName(0, 0, i));
    for(int w = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL) - 1; w >= 1; w--) for(int i = ChartIndicatorsTotal(0, w) - 1; i >= 0; i--) ChartIndicatorDelete(0, w, ChartIndicatorName(0, w, i));
    int sub_idx = 0;
    if(hEMA_Fast != INVALID_HANDLE) ChartIndicatorAdd(0, 0, hEMA_Fast);
    if(hRSI != INVALID_HANDLE) ChartIndicatorAdd(0, ++sub_idx, hRSI);
    if(hMACD != INVALID_HANDLE) ChartIndicatorAdd(0, ++sub_idx, hMACD);
    if(hATR != INVALID_HANDLE) ChartIndicatorAdd(0, ++sub_idx, hATR);
    if(hADX != INVALID_HANDLE) ChartIndicatorAdd(0, ++sub_idx, hADX);
    ChartRedraw();
#endif
}

void ResetTestingHelperState()
{
    g_test_positions_opened = false;
    g_test_bar_counter = 0;
    g_last_test_bar = 0;
    g_test_opp_pending = false;
    g_test_opp_done = false;
    g_test_opp_time = 0;
    g_corr_test_started = false;
    g_corr_attempt_scheduled = false;
    g_corr_attempt_done = false;
    g_corr_attempt_time = 0;
}

bool ActivateTestingMode()
{
    g_testing_label = "[TESTING MODE]";
    TestingModeConfig cfg;
    cfg.positions = InpTestPositions;
    cfg.lot_size = InpTestLotSize;
    cfg.target_result = InpTestResult;
    cfg.delay_bars = MathMax(0, InpTestDelayBars);
    cfg.opposite_entry = InpTestOppositeEntry;
    cfg.opposite_delay_min = MathMax(0, InpOppositeDelayMinutes);
    cfg.correlation_enabled = InpTestCorrelationEnabled;
    cfg.correlation_symbols = InpTestCorrelationSymbols;
    cfg.correlation_lots = InpTestCorrelationLots;
    cfg.correlation_alternate = InpCorrAlternateDirections;
    cfg.correlation_attempt_delay_min = MathMax(0, InpCorrelationAttemptDelayMin);
    cfg.bypass_filters = (InpTestingMode == TestingMode_ForceBypass);

    if(cfg.positions <= 0 || cfg.lot_size <= 0.0)
    {
        PrintFormat("%s ERROR: Invalid configuration (positions=%d, lots=%.4f). Mode disabled.",
                    g_testing_label, cfg.positions, cfg.lot_size);
        return false;
    }
    if(cfg.correlation_enabled && cfg.correlation_lots <= 0.0)
    {
        PrintFormat("%s WARNING: Correlation lots <= 0 -> correlation scenario disabled.", g_testing_label);
        cfg.correlation_enabled = false;
    }

    g_testing_mode_active = true;
    g_testing_cfg = cfg;
    ResetTestingHelperState();

    PrintFormat("%s Enabled | Positions:%d | Lots:%.2f | Target:$%.2f | Delay:%d bars",
                g_testing_label,
                g_testing_cfg.positions,
                g_testing_cfg.lot_size,
                (double)g_testing_cfg.target_result,
                g_testing_cfg.delay_bars);
    PrintFormat("%s Mode: %s entry filters",
                g_testing_label,
                g_testing_cfg.bypass_filters ? "Bypassing" : "Respecting");
    if(g_testing_cfg.opposite_entry)
        PrintFormat("%s Opposite attempt scheduled %d min after forced trades",
                    g_testing_label, g_testing_cfg.opposite_delay_min);
    if(g_testing_cfg.correlation_enabled && StringLen(g_testing_cfg.correlation_symbols) > 0)
        PrintFormat("%s Correlation symbols:%s | Lots:%.2f | Retry:%d min",
                    g_testing_label,
                    g_testing_cfg.correlation_symbols,
                    g_testing_cfg.correlation_lots,
                    g_testing_cfg.correlation_attempt_delay_min);
    return true;
}

double CalculateTestingPoints()
{
    double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(pip_value <= 0) pip_value = 1.0;
    if(g_testing_cfg.lot_size <= 0.0) return 0.0;
    return MathMax(10.0, MathAbs((double)g_testing_cfg.target_result) /
                         MathMax(0.0000001, (g_testing_cfg.lot_size * pip_value)));
}

double DetermineSLPoints()
{
    double sl_points = 0.0;
    if(InpSlMethod == SL_ATR_Based)
    {
        double atr_buffer[];
        ENUM_TIMEFRAMES tf_atr = InpUseMultiTimeframe ? (ENUM_TIMEFRAMES)InpAtrTimeframe : (ENUM_TIMEFRAMES)InpSignalTF;
        int hATR_SL = iATR(_Symbol, tf_atr, InpAtrSlPeriod);
        if(CopyBuffer(hATR_SL, 0, 1, 1, atr_buffer) > 0)
            sl_points = (InpAtrSlMultiplier_SL * atr_buffer[0]) / _Point;
        IndicatorRelease(hATR_SL);
    }
    else
    {
        sl_points = g_actualFixedSlPoints;
    }
    return MathMax(sl_points, 1.0);
}

bool TestingFiltersAllow(int signal)
{
    if(g_testing_cfg.bypass_filters)
        return true;

    double lots = g_testing_cfg.lot_size;
    if(lots <= 0.0)
        return false;

    double sl_points = DetermineSLPoints();
    if(sl_points <= 0.0)
        sl_points = 1.0;

    string reason = "";
    bool allowed = EvaluateTradeConditions(signal, lots, sl_points, reason);
    if(!allowed && InpDebugTestingMode)
        PrintFormat("%s BLOCKED: Filters prevented forced entry (signal=%d) | %s",
                    g_testing_label, signal, reason);
    return allowed;
}

bool CreateTestingPosition(int signal, double points_for_result, const string &order_comment)
{
    if(g_testing_cfg.lot_size <= 0.0)
    {
        PrintFormat("%s ERROR: Lot size invalid (%.2f). No trades opened.", g_testing_label, g_testing_cfg.lot_size);
        return false;
    }
    if(points_for_result <= 0.0)
    {
        PrintFormat("%s ERROR: Points calculation invalid. No trades opened.", g_testing_label);
        return false;
    }
    if(!TestingFiltersAllow(signal))
        return false;

    bool is_buy = (signal > 0);
    double entry_price = is_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double point = _Point;
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double sl_price, tp_price;
    if(g_testing_cfg.target_result < 0)
    {
        if(is_buy)
        {
            sl_price = entry_price - (points_for_result * point);
            tp_price = entry_price + (points_for_result * 10.0 * point);
        }
        else
        {
            sl_price = entry_price + (points_for_result * point);
            tp_price = entry_price - (points_for_result * 10.0 * point);
        }
    }
    else
    {
        if(is_buy)
        {
            tp_price = entry_price + (points_for_result * point);
            sl_price = entry_price - (points_for_result * 10.0 * point);
        }
        else
        {
            tp_price = entry_price - (points_for_result * point);
            sl_price = entry_price + (points_for_result * 10.0 * point);
        }
    }
    sl_price = NormalizeDouble(sl_price, digits);
    tp_price = NormalizeDouble(tp_price, digits);
    if(InpDebugTestingMode)
    {
        PrintFormat("[TESTING MODE DEBUG] Position setup: Type=%s | Entry=%.5f | SL=%.5f | TP=%.5f",
                    is_buy ? "BUY" : "SELL", entry_price, sl_price, tp_price);
    }
    bool success = false; ulong ticket = 0;
    if(is_buy)
    {
        success = trade.Buy(g_testing_cfg.lot_size, _Symbol, entry_price, sl_price, tp_price, order_comment);
        ticket = trade.ResultOrder();
    }
    else
    {
        success = trade.Sell(g_testing_cfg.lot_size, _Symbol, entry_price, sl_price, tp_price, order_comment);
        ticket = trade.ResultOrder();
    }
    if(success)
    {
        PrintFormat("%s Opened %s | Ticket:%I64u | Entry:%.5f | SL:%.5f | TP:%.5f | Target:$%.2f",
                    g_testing_label, is_buy ? "BUY" : "SELL", ticket, entry_price, sl_price, tp_price,
                    (double)g_testing_cfg.target_result);
    }
    else
    {
        PrintFormat("%s FAILED to open %s | Error:%d", g_testing_label, is_buy ? "BUY" : "SELL", GetLastError());
    }
    return success;
}

int OnInit()
{
   g_ea_prefix = "UDEA_" + (string)InpMagicNumber + "_" + (string)ChartID() + "_";
   ObjectsDeleteAll(0, g_ea_prefix);
    LoadPanelState();
    if(g_panel_visible) g_panel.Init(InpMagicNumber, 10, 40, 480, 620); // Altura del panel ajustada
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippagePoints);
    
    g_initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    g_lastDay = dt.day;
    // CR?TICO: Restaurar estado de sesi?n anterior
    RestoreCriticalState();
    // Restore stop flag from This-Chart-Only persistence and Global flag if applicable
   if(InpRiskScope == Scope_EA_ChartOnly)
   {
       string stop_var = "UDEA_M" + (string)InpMagicNumber + "_C" + (string)ChartID() + "_IsEaStopped";
       if(GlobalVariableCheck(stop_var))
       {
           double flag = GlobalVariableGet(stop_var);
           if(flag > 0.5)
           {
               g_isEaStopped = true;
               g_daily_loss_was_reached = true;
               if(InpDebug_Persistence)
               {
                   Print("[PERSISTENCE] EA stop flag restored: STOPPED (This Chart Only)");
                   Print("[PERSISTENCE] EA will remain stopped until manual reset or next day");
               }
           }
       }
   }
    if(InpRiskScope == Scope_AllTrades)
    {
        if(GlobalVariableCheck("ACCOUNT_GLOBAL_LossFlag") && GlobalVariableGet("ACCOUNT_GLOBAL_LossFlag") > 0.5)
        {
            g_isEaStopped = true;
            g_daily_loss_was_reached = true;
            if(InpDebug_Persistence)
                Print("[PERSISTENCE] Global loss flag active - EA will remain stopped");
        }
    }
    if(InpRiskScope == Scope_EA_AllCharts)
    {
        if(IsEAGlobalDailyLossReached())
        {
            g_isEaStopped = true;
            g_daily_loss_was_reached = true;
            if(InpDebug_Persistence)
                Print("[PERSISTENCE] EA-group loss flag active - EA will remain stopped");
        }
    }
    // Stale-flag cleanup: if no DD today and no open positions for this scope, clear local stop
    {
        double d_pl, d_pl_pct, d_dd, d_dd_pct; CalculateDailyPerformance(d_pl, d_pl_pct, d_dd, d_dd_pct);
        bool any_local_positions = false;
        for(int i=0;i<PositionsTotal();i++)
        {
            if(!pos.SelectByIndex(i)) continue;
            if((long)pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol) { any_local_positions = true; break; }
        }
        bool any_global_flags = IsGlobalDailyLossReached() || IsEAGlobalDailyLossReached();
        if(d_dd == 0.0 && !any_local_positions && !any_global_flags)
        {
            g_isEaStopped = false; g_daily_loss_was_reached = false; g_resetTime = 0; SaveCriticalState();
            string stop_var = "UDEA_M" + (string)InpMagicNumber + "_C" + (string)ChartID() + "_IsEaStopped";
            if(GlobalVariableCheck(stop_var)) GlobalVariableDel(stop_var);
            if(InpDebug_Persistence)
                Print("[PERSISTENCE] Cleared stale stop state (fresh day, no positions, no global flags)");
        }
    }
    
    g_totalStartEquity = g_initialEquity;
    ArrayResize(g_tp_management, 0);
    g_last_tp_check = 0;
    ApplyUniquenessSettings();
    if(!ValidateIndicatorParameters() || !ValidateSystemLogic() || !BuildIndicators()) return(INIT_FAILED);

    // --- FASE 4: INTEGRACI?N ---
    // Carga inicial de noticias y dibujo de l?neas con la NUEVA l?gica.
    bool debug_news_init = (InpDebug_StatusChanges && MQLInfoInteger(MQL_TESTER));
    if(debug_news_init)
        PrintFormat("[NEWS] OnInit: loading feed @ %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    LoadNews();
    if(debug_news_init)
        Print("[NEWS] OnInit: drawing news lines");
    UpdateNewsLinesOnChart();
    
    // INICIALIZACI?N DEFENSIVA: Forzar primera actualizaci?n del panel DESPU?S de cargar noticias
    if(g_panel_visible)
    {
        // Cargar noticias ANTES de mostrar el panel por primera vez
        LoadNews();
        UpdateNewsLinesOnChart();
    
        // Forzar primera actualizaci?n del panel con datos v?lidos
        UpdatePanelData();
    
    if(false)
        Print("[Init] Panel inicializado con datos de noticias pre-cargados");
    }
    if(debug_news_init)
        PrintFormat("[NEWS] OnInit: feed ready @ %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    CreateVisualIndicators();
    PrintFormat("[Init] UltimateDualEA v%s ready. TF=%s", MQLInfoString(MQL_PROGRAM_NAME), EnumToString((ENUM_TIMEFRAMES)InpSignalTF));
    
    // Register global limit if using All Charts mode
    RegisterGlobalDailyLimit();
    RegisterEAGlobalDailyLimit();
    if(InpDebug_GlobalSync)
    {
        Print("========== GLOBAL SYNC MODE ==========");
        if(InpRiskScope == Scope_AllTrades)
        {
            Print("Scope: All Trades (Account-Wide)");
            double lowest = GetLowestGlobalDailyLimit();
            if(lowest > 0) PrintFormat("[FASE 4] Active global (account) limit: %.2f%%", lowest);
        }
        else if(InpRiskScope == Scope_EA_AllCharts)
        {
            Print("Scope: EA Trades (All Charts)");
            double lowestEA = GetLowestEAGlobalDailyLimit();
            if(lowestEA > 0) PrintFormat("[FASE 4] Active EA-group limit: %.2f%%", lowestEA);
        }
        else
        {
            Print("Scope: EA Trades (This Chart Only)");
        }
        Print("======================================");
    }
    ChartRedraw();
    // ===== TESTING MODE INITIALIZATION =====
    bool is_tester_env = (MQLInfoInteger(MQL_TESTER) != 0);
    g_testing_mode_active = false;
    if(InpTestingMode != TestingMode_Off)
    {
        if(is_tester_env)
        {
            ActivateTestingMode();
        }
        else
        {
            Print("[TESTING MODE] ERROR: Testing Mode can ONLY be used in Strategy Tester! Disabled.");
        }
    }
    g_manual_button_lot = InpFixedLot;
    g_buttons.Init(ChartID(), g_manual_button_lot);
    g_buttons.UpdateStates(g_panel_visible, g_show_high_news_lines, g_show_med_news_lines);
    return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, g_ea_prefix);
    g_panel.Deinit(reason);
    g_buttons.Deinit();
    ObjectsDeleteAll(0, g_ea_prefix);
    ArrayResize(g_tp_management, 0);
    IndicatorRelease(hEMA_Fast); IndicatorRelease(hEMA_Med); IndicatorRelease(hEMA_Slow);
    IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hADX); IndicatorRelease(hMACD);
    // Clean up registration for scopes
    if(InpRiskScope == Scope_AllTrades)
    {
        long chart_id = ChartID();
        string var_name = "ACCOUNT_GLOBAL_Limit_" + (string)(chart_id % 10);
        GlobalVariableDel(var_name);
        bool any_active = false;
        for(int i = 0; i < 10; i++)
        {
            if(GlobalVariableCheck("ACCOUNT_GLOBAL_Limit_" + (string)i)) { any_active = true; break; }
        }
        if(!any_active)
        {
            GlobalVariableDel("ACCOUNT_GLOBAL_ActiveLimits");
            GlobalVariableDel("ACCOUNT_GLOBAL_LossFlag");
            GlobalVariableDel("ACCOUNT_GLOBAL_DailyStart");
            GlobalVariableDel("ACCOUNT_GLOBAL_DailyPL");
            if(GlobalVariableCheck("ACCOUNT_GLOBAL_TriggerTimestamp"))
                GlobalVariableDel("ACCOUNT_GLOBAL_TriggerTimestamp");
            GlobalVariablesDeleteAll("ACCOUNT_GLOBAL_TriggerSymbol_");
        }
    }
    if(InpRiskScope == Scope_EA_AllCharts)
    {
        string key = GetEAGroupKey();
        long chart_id = ChartID();
        string var_name = "EA_GLOBAL_" + key + "_Limit_" + (string)(chart_id % 10);
        GlobalVariableDel(var_name);
        bool any_active = false;
        for(int i=0;i<10;i++) { if(GlobalVariableCheck("EA_GLOBAL_"+key+"_Limit_"+(string)i)) { any_active = true; break; } }
        if(!any_active)
        {
            GlobalVariableDel("EA_GLOBAL_" + key + "_ActiveLimits");
            GlobalVariableDel("EA_GLOBAL_" + key + "_LossFlag");
            if(GlobalVariableCheck("EA_GLOBAL_" + key + "_TriggerTimestamp"))
                GlobalVariableDel("EA_GLOBAL_" + key + "_TriggerTimestamp");
            GlobalVariablesDeleteAll("EA_GLOBAL_" + key + "_TriggerSymbol_");
        }
    }
}
bool CheckConsistencyRules(double planned_lot_size, double sl_points, string &reason)
{
    reason = "";
    if(!InpUseConsistencyRules) return true;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.day != g_lastConsistencyDay)
     {
        g_lastConsistencyDay = dt.day;
        g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_dailyProfitAccum = 0.0;
     }
    if(InpUseDailyProfitLimit && InpMaxProfitPerTrade > 0.0)
     {
        double potential_profit = (planned_lot_size * sl_points * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * InpRiskRewardRatio);
        if(potential_profit > AccountInfoDouble(ACCOUNT_BALANCE) * (InpMaxProfitPerTrade/100.0))
        {
            reason = "Consistency: Max profit per trade exceeded";
            return false;
        }
     }
    if(InpUseLotSizeLimit && InpMaxLotSizePerTrade > 0.0 && planned_lot_size > InpMaxLotSizePerTrade)
    {
        reason = "Consistency: Lot size limit exceeded";
        return false;
    }
    return true;
}
void OnTick()
{
    UpdateDailyMetrics();
    MonitorDailyLossLimit();
    UpdatePanelData();

    // ===== TESTING MODE: Force test positions =====
    if(g_testing_mode_active && !g_test_positions_opened)
    {
        if(g_testing_cfg.delay_bars <= 0)
        {
            Print("====================================");
            PrintFormat("%s Opening %d test positions NOW", g_testing_label, g_testing_cfg.positions);
            Print("====================================");
            OpenTestPositions();
            g_test_positions_opened = true;
        }
        else
        {
            datetime current_bar = iTime(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 0);
            if(g_last_test_bar != current_bar)
            {
                g_test_bar_counter++;
                g_last_test_bar = current_bar;
                if(g_test_bar_counter >= g_testing_cfg.delay_bars)
                {
                    Print("====================================");
                    PrintFormat("%s Opening %d test positions NOW", g_testing_label, g_testing_cfg.positions);
                    Print("====================================");
                    OpenTestPositions();
                    g_test_positions_opened = true;
                }
                else if(InpDebugTestingMode && (g_test_bar_counter % 5 == 0))
                {
                    PrintFormat("%s Waiting... %d/%d bars", g_testing_label, g_test_bar_counter, g_testing_cfg.delay_bars);
                }
            }
        }
    }

    // ===== TESTING MODE: Scheduled hedging/correlation attempts =====
    if(g_testing_mode_active)
    {
        // Hedging opposite-direction attempt
        if(g_testing_cfg.opposite_entry && g_test_opp_pending && !g_test_opp_done && TimeCurrent() >= g_test_opp_time)
        {
            int longs = 0, shorts = 0;
            for(int i = 0; i < PositionsTotal(); i++)
            {
                if(!pos.SelectByIndex(i)) continue;
                if((long)pos.Magic() != InpMagicNumber || pos.Symbol() != _Symbol) continue;
                if(pos.PositionType() == POSITION_TYPE_BUY) longs++;
                else if(pos.PositionType() == POSITION_TYPE_SELL) shorts++;
            }
            int opp_signal = 0;
            if(longs > shorts) opp_signal = -1; else if(shorts > longs) opp_signal = 1; else opp_signal = 1;
            if(InpDebug_StatusChanges)
            {
                string hedge_state = InpBlockOppositeDirections ? "BLOCKED" : "ALLOWED";
                PrintFormat("%s Opposite entry attempt now (signal=%d). Hedging filter %s.",
                            g_testing_label, opp_signal, hedge_state);
            }
            if(opp_signal != 0) PlaceOrder(opp_signal);
            g_test_opp_done = true;
            g_test_opp_pending = false;
        }
        // Correlation filter attempt on current symbol
        if(g_testing_cfg.correlation_enabled && g_corr_attempt_scheduled && !g_corr_attempt_done && TimeCurrent() >= g_corr_attempt_time)
        {
            if(InpDebug_StatusChanges)
                PrintFormat("%s Attempting entry on current symbol to trigger correlation filter", g_testing_label);
            PlaceOrder(1); // Direction not critical for correlation; BUY by default
            g_corr_attempt_done = true;
        }
    }

    // --- FASE 4: INTEGRACI?N ---
    // La gesti?n y actualizaci?n de noticias ahora usa la nueva l?gica.
    // ===== LIVE TEST TRADES (non-Tester) =====
    if(InpOpenLiveTestTrades && !g_isEaStopped)
    {
        if(!g_live_test_active_prev)
        {
            g_live_test_opened = 0;
            g_live_test_last_open = 0;
            g_live_test_active_prev = true;
        }
        if(InpLiveTestPositions > 0 && g_live_test_opened < InpLiveTestPositions)
        {
            bool ready = (g_live_test_last_open == 0);
            if(!ready)
            {
                int wait_sec = InpLiveTestDelayMin * 60;
                if(wait_sec < 0) wait_sec = 0;
                ready = (TimeCurrent() - g_live_test_last_open) >= wait_sec;
            }
            if(ready)
            {
                int signal = 1;
                switch(InpLiveTestDirection)
                {
                    case LiveTest_Buy: signal = 1; break;
                    case LiveTest_Sell: signal = -1; break;
                    case LiveTest_BuySell: signal = (g_live_test_opened % 2 == 0) ? 1 : -1; break;
                    default: signal = 1; break;
                }
                // Forzar comentario del gráfico en Chart Only (override temporal)
                string saved_override = g_comment_override;
                if(InpRiskScope == Scope_EA_ChartOnly)
                {
                    string forced = InpTradeComment;
                    if(forced == "") forced = "UltimateDualEA";
                    string suffix = "_C" + (string)ChartID();
                    if(StringFind(forced, suffix) < 0) forced += suffix;
                    g_comment_override = forced;
                }
                PlaceOrder(signal);
                g_comment_override = saved_override;
                if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
                {
                    g_live_test_opened++;
                    g_live_test_last_open = TimeCurrent();
                }
            }
        }
    }
    else
    {
        g_live_test_active_prev = false;
        g_live_test_opened = 0;
        g_live_test_last_open = 0;
    }
    static datetime last_news_update = 0;
    if(TimeCurrent() - last_news_update > 300) // Actualiza cada 5 minutos
    {
        last_news_update = TimeCurrent();
        bool debug_news_refresh = (InpDebug_StatusChanges && MQLInfoInteger(MQL_TESTER));
        datetime stamp = TimeCurrent();
        if(debug_news_refresh)
            PrintFormat("[NEWS] Refresh start @ %s", TimeToString(stamp, TIME_DATE|TIME_MINUTES));
        LoadNews();
        UpdateNewsLinesOnChart();
        if(debug_news_refresh)
            PrintFormat("[NEWS] Refresh done | events=%d", ArraySize(g_all_news));
    }
    
    if(g_isEaStopped)
    {
       if(TimeCurrent() >= g_resetTime)
       {
          g_isEaStopped = false;
          g_resetTime = 0;
          UpdateDailyMetrics();
          Print("EA has been reset and will resume trading.");
       }
       else
       {
           // FASE 6: Dynamic reactivation if user raises daily loss limit intraday
           if(InpDailyLossMode != Limit_Off && InpDailyLossValue > 0)
           {
               double d_pl=0.0, d_pl_pct=0.0, d_dd=0.0, d_dd_pct=0.0;
               if(InpRiskScope == Scope_AllTrades)
               {
                   CalculateDailyPerformance(d_pl, d_pl_pct, d_dd, d_dd_pct);
               }
               else
               {
                   bool only_chart = (InpRiskScope == Scope_EA_ChartOnly);
                   GetEAGroupDailyPL(only_chart, d_pl, d_pl_pct, d_dd, d_dd_pct);
               }
               bool still_over_limit = false;
               if(InpDailyLossMode == Limit_Percent)
                   still_over_limit = (d_dd_pct >= InpDailyLossValue - 1e-6);
               else
                   still_over_limit = (d_dd >= InpDailyLossValue - 1e-6);
               if(!still_over_limit)
               {
                   g_isEaStopped = false;
                   g_daily_loss_was_reached = false;
                   g_resetTime = 0;
                   SaveCriticalState();
                   // Clear scope-specific global flags
                   if(InpRiskScope == Scope_AllTrades)
                   {
                       if(GlobalVariableCheck("ACCOUNT_GLOBAL_LossFlag")) GlobalVariableDel("ACCOUNT_GLOBAL_LossFlag");
                   }
                   else if(InpRiskScope == Scope_EA_AllCharts)
                   {
                       string key = GetEAGroupKey();
                       string flag = "EA_GLOBAL_" + key + "_LossFlag";
                       if(GlobalVariableCheck(flag)) GlobalVariableDel(flag);
                   }
                   if(InpDebug_StatusChanges)
                       Print("[REACTIVATION] Daily loss limit increased; EA re-enabled before reset time");
               }
           }
           if(g_isEaStopped) return;
       }
    }
    ManageWeekendLogic();
    ManageTimeBasedClose();
    // === GESTI?N UNIFICADA DE TAKE PROFIT ===
    ManageAllTakeProfit();
    ManageExitStrategy();
    UpdatePositionCloseTime();
    int sig = GetSignal();
    if(ProcessDelayedEntry(sig))
    {
       PlaceOrder(InpEntryMode == Delayed_Market_Order ? g_delayed_signal.signal : sig);
       if(InpEntryMode == Delayed_Market_Order) g_delayed_signal.signal = 0;
    }
}
void UpdatePanelData()
{
    if(!g_panel_visible) return;
    PanelData data;
    data.magic_number = InpMagicNumber;
    data.trade_comment = InpTradeComment;

    string ea_key = GetEAGroupKey();
    bool global_stop = IsGlobalDailyLossReached();
    bool ea_stop = IsEAGlobalDailyLossReached();
    bool local_stop = g_daily_loss_was_reached;
    double global_ts = (global_stop && GlobalVariableCheck("ACCOUNT_GLOBAL_TriggerTimestamp")) ? GlobalVariableGet("ACCOUNT_GLOBAL_TriggerTimestamp") : 0.0;
    string ea_ts_name = "EA_GLOBAL_" + ea_key + "_TriggerTimestamp";
    double ea_ts = (ea_stop && GlobalVariableCheck(ea_ts_name)) ? GlobalVariableGet(ea_ts_name) : 0.0;

    bool effective_stop = false;
    datetime effective_reset = 0;
    string trigger_symbol = "";

    if(global_stop)
    {
        effective_stop = true;
        trigger_symbol = GetGlobalTriggerSymbol(global_ts);
        if(trigger_symbol == "") trigger_symbol = "ALL TRADES";
        effective_reset = (global_ts > 0.0) ? ComputeNextResetTime((datetime)global_ts)
                                            : ((g_resetTime > 0) ? g_resetTime : ComputeNextResetTime(TimeCurrent()));
    }
    else if(ea_stop)
    {
        effective_stop = true;
        trigger_symbol = GetEATriggerSymbol(ea_key, ea_ts);
        if(trigger_symbol == "") trigger_symbol = ea_key;
        effective_reset = (ea_ts > 0.0) ? ComputeNextResetTime((datetime)ea_ts)
                                        : ((g_resetTime > 0) ? g_resetTime : ComputeNextResetTime(TimeCurrent()));
    }
    else if(local_stop)
    {
        effective_stop = true;
        trigger_symbol = _Symbol;
        effective_reset = (g_resetTime > 0) ? g_resetTime : ComputeNextResetTime(TimeCurrent());
    }

    data.ea_stopped_by_daily_loss = effective_stop;
    data.daily_loss_reached = effective_stop;
    data.reset_time = effective_reset;
    data.reset_countdown = effective_stop ? FormatCountdown(effective_reset) : "";
    if(effective_stop && trigger_symbol != "")
    {
        string trigger_label = trigger_symbol;
        StringToUpper(trigger_label);
        data.daily_dd_trigger = trigger_label + " TRIGGERED";
    }
    else
    {
        data.daily_dd_trigger = "";
    }
    
    // --- FASE 2: Reemplazada la llamada a la funci?n de noticias ---
    // Inicializar expl?citamente todos los elementos del array antes de llenarlo
    for(int i = 0; i < MAX_NEWS_DISPLAY; i++)
    {
        data.upcoming_events[i].time = 0;
        data.upcoming_events[i].currency = "";
        data.upcoming_events[i].name = "";
        data.upcoming_events[i].importance = 0;
    }
    // Ahora s?, llenar con los eventos v?lidos
    data.num_upcoming_events = GetUpcomingNewsEvents(data.upcoming_events, MAX_NEWS_DISPLAY);
    // DEBUG #2: Inspeccionar lo que devolvi? GetUpcomingNewsEvents()
    static datetime last_debug_time = 0;
    if(false && TimeCurrent() - last_debug_time > 60) // Solo cada 60 segundos
    {
        last_debug_time = TimeCurrent();
        Print("========================================");
        Print("[DEBUG #2] DESPUES DE GetUpcomingNewsEvents()");
        PrintFormat("Eventos retornados: %d", data.num_upcoming_events);
        // Mostrar TODOS los slots del array (para ver si hay "Label" escondidos)
        for(int i = 0; i < MAX_NEWS_DISPLAY; i++)
        {
            if(i < data.num_upcoming_events)
            {
                PrintFormat("  Slot[%d] VALID: Currency='%s' | Name='%s' | Time=%s | Importance=%d",
                            i,
                            data.upcoming_events[i].currency,
                            data.upcoming_events[i].name,
                            TimeToString(data.upcoming_events[i].time, TIME_DATE|TIME_MINUTES),
                            data.upcoming_events[i].importance);
            }
            else
            {
                // Estos deber?an estar vac?os
                PrintFormat("  Slot[%d] EMPTY: Currency='%s' | Name='%s' | Time=%s | Importance=%d",
                            i,
                            data.upcoming_events[i].currency,
                            data.upcoming_events[i].name,
                            TimeToString(data.upcoming_events[i].time, TIME_DATE|TIME_MINUTES),
                            data.upcoming_events[i].importance);
            }
        }
        Print("========================================");
    }
    
    data.leverage_info = "Leverage: 1:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE);
    CalculateDailyPerformance(data.daily_pl, data.daily_pl_pct, data.daily_dd, data.daily_dd_pct);
    data.is_pl_dd_calculated = true;
    switch(InpNewsFilterMode)
    {
        case News_Filter_Off: data.news_filter_status = "OFF"; break;
        case Block_New_Trades_Only: data.news_filter_status = "Block New Trades"; break;
        case Manage_Open_Trades_Only: data.news_filter_status = "Manage TP"; break;
        case Block_And_Manage: data.news_filter_status = "Block & Manage"; break;
    }
    if (InpNewsFilterMode != News_Filter_Off) data.news_window_info = " (" + IntegerToString((int)InpNewsWindowMin) + "m)";
    data.hedging_active = !InpBlockOppositeDirections;
    data.correlation_status = GetCorrelationStatusString();
    data.close_on_friday_info = (InpUseWeekendManagement && InpCloseOnFriday) ? "ON (" + IntegerToString(InpFridayCloseHour) + ":00)" : "OFF";
    data.block_late_friday_info = (InpUseWeekendManagement && InpBlockLateFriday) ? "ON (" + IntegerToString(InpFridayBlockHour) + ":00)" : "OFF";
    if(InpDailyLossMode != Limit_Off && InpDailyLossValue > 0)
        data.daily_loss_limit = (InpDailyLossMode == Limit_Percent) ? StringFormat("%.1f%% ($%.0f)", InpDailyLossValue, g_dailyStartBalance * (InpDailyLossValue/100.0)) : StringFormat("$%.0f (%.1f%%)", InpDailyLossValue, (g_dailyStartBalance > 0 ? (InpDailyLossValue / g_dailyStartBalance) * 100.0 : 0));
    else data.daily_loss_limit = "OFF";
    if(InpTotalLossMode != Limit_Off) data.total_loss_limit = (InpTotalLossMode == Limit_Percent) ? StringFormat("%.1f%% ($%.0f)", InpTotalLossValue, g_totalStartEquity * (InpTotalLossValue / 100.0)) : StringFormat("$%.0f (%.1f%%)", InpTotalLossValue, (g_totalStartEquity > 0 ? (InpTotalLossValue / g_totalStartEquity) * 100.0 : 0));
    else data.total_loss_limit = "OFF";
    if(InpUseDailyProfitLimit && InpDailyProfitMode != Limit_Off) data.daily_profit_limit = (InpDailyProfitMode == Limit_Percent) ? StringFormat("%.1f%% ($%.0f)", InpDailyProfitValue, g_dailyStartBalance * (InpDailyProfitValue / 100.0)) : StringFormat("$%.0f (%.1f%%)", InpDailyProfitValue, (g_dailyStartBalance > 0 ? (InpDailyProfitValue / g_dailyStartBalance) * 100.0 : 0));
    else data.daily_profit_limit = "OFF";
    data.auto_reset_info = (InpDailyLossMode != Limit_Off && InpDailyLossValue > 0) ? "AUTO (24H)" : "OFF";
    data.max_account_trades = (InpMaxAccountOpenTrades > 0) ? IntegerToString(InpMaxAccountOpenTrades) : "OFF";
    data.max_account_lots = (InpMaxAccountOpenLots > 0.0) ? DoubleToString(InpMaxAccountOpenLots, 1) : "OFF";
    data.consistency_rules_active = InpUseConsistencyRules;
    data.max_profit_per_trade = (InpUseConsistencyRules && InpMaxProfitPerTrade > 0) ? StringFormat("%.1f%% ($%.0f)", InpMaxProfitPerTrade, AccountInfoDouble(ACCOUNT_EQUITY) * (InpMaxProfitPerTrade / 100.0)) : "OFF";
    data.max_lot_size_per_trade = (InpUseConsistencyRules && InpUseLotSizeLimit && InpMaxLotSizePerTrade > 0) ? DoubleToString(InpMaxLotSizePerTrade, 2) : "OFF";
    bool is_tp_managed = (InpNewsFilterMode == Manage_Open_Trades_Only || InpNewsFilterMode == Block_And_Manage);
    if(is_tp_managed)
    {
        if(IsInNewsWindow())
        {
            data.tp_status_text = "MANAGING";
            data.tp_status_state = 1;
            data.tp_status_countdown = GetNewsCountdownSeconds();
            g_tp_restored_end_time = 0;
            datetime active_event_time = 0;
            if(GetActiveNewsEventDetails(active_event_time)) data.managing_period_info = (TimeCurrent() < active_event_time) ? "(before " + TimeToString(active_event_time, TIME_MINUTES) + ")" : "(after " + TimeToString(active_event_time, TIME_MINUTES) + ")";
        }
        else
        {
            if(g_tp_status == 1) { g_tp_restored_end_time = (datetime)(TimeCurrent() + 5 * 60); g_tp_status = 2; }
            if(g_tp_restored_end_time != 0 && TimeCurrent() < g_tp_restored_end_time)
            {
                data.tp_status_text = "RESTORED";
                data.tp_status_state = 2;
                long restored_rem = g_tp_restored_end_time - TimeCurrent(), standby_rem = GetNewsCountdownSeconds();
                data.restored_countdown_seconds = (standby_rem > 0 && standby_rem < restored_rem) ? standby_rem : restored_rem;
            }
            else
            {
                 if(g_tp_status_state == 2) g_tp_status_state = 3;
                 g_tp_restored_end_time = 0;
                 data.tp_status_text = "STANDBY";
                 data.tp_status_state = 3;
                 data.tp_status_countdown = GetNewsCountdownSeconds();
            }
        }
    }
    else { data.tp_status_text = "N/A"; data.tp_status_state = 0; g_tp_restored_end_time = 0; }

    // === NEW PANEL FIELDS FOR v2.68 ===

    // Unified scope display
    if(InpRiskScope == Scope_AllTrades)
    {
        data.daily_loss_mode = "All Trades";
        double gl = GetLowestGlobalDailyLimit();
        data.global_sync_status = (gl > 0) ? StringFormat("All Trades (%.1f%%)", gl) : "All Trades";
    }
    else if(InpRiskScope == Scope_EA_AllCharts)
    {
        data.daily_loss_mode = "EA Trades (All Charts)";
        double el = GetLowestEAGlobalDailyLimit();
        data.global_sync_status = (el > 0) ? StringFormat("EA All Charts (%.1f%%)", el) : "EA All Charts";
    }
    else
    {
        data.daily_loss_mode = "EA Trades (Chart)";
        data.global_sync_status = "This Chart Only";
    }

    // Manual trades impact (only show if relevant)
    data.manual_trades_impact = g_manual_trades_impact_today;
    data.show_manual_impact = (InpRiskScope != Scope_AllTrades && g_manual_trades_impact_today != 0.0);

    // Daily loss state already reflected earlier for all scopes
    g_panel.Update(data);
} 

string GetPanelStateKey()
{
    return StringFormat("UDEA_PanelVisible_%I64d", (long)ChartID());
}

string GetNewsModeKey()
{
    return StringFormat("UDEA_NewsMode_%I64d", (long)ChartID());
}

void SavePanelState()
{
    GlobalVariableSet(GetPanelStateKey(), g_panel_visible ? 1.0 : 0.0);
}

void LoadPanelState()
{
    string key = GetPanelStateKey();
    if(GlobalVariableCheck(key))
        g_panel_visible = (GlobalVariableGet(key) > 0.5);
}

void ApplyNewsMode(ENUM_NEWS_VISUALIZER_MODE mode)
{
    g_news_display_mode = mode;
    g_show_high_news_lines = (mode == High_Impact_Only || mode == High_And_Medium_Impact);
    g_show_med_news_lines = (mode == Medium_Impact_Only || mode == High_And_Medium_Impact);
}

void SaveNewsModeState()
{
    GlobalVariableSet(GetNewsModeKey(), (double)g_news_display_mode);
}

void LoadNewsModeState()
{
    string key = GetNewsModeKey();
    if(GlobalVariableCheck(key))
        ApplyNewsMode((ENUM_NEWS_VISUALIZER_MODE)(int)GlobalVariableGet(key));
}

void SetNewsModeFromFlags(bool high,bool med)
{
    if(high && med) ApplyNewsMode(High_And_Medium_Impact);
    else if(high) ApplyNewsMode(High_Impact_Only);
    else if(med) ApplyNewsMode(Medium_Impact_Only);
    else ApplyNewsMode(Visualizer_Off);
    SaveNewsModeState();
    UpdateNewsLinesOnChart();
    g_buttons.UpdateStates(g_panel_visible, g_show_high_news_lines, g_show_med_news_lines);
}

void TogglePanelVisibility()
{
    g_panel_visible = !g_panel_visible;
    if(g_panel_visible)
    {
        g_panel.Init(InpMagicNumber, 10, 40, 480, 620);
        UpdatePanelData();
    }
    else
    {
        g_panel.Deinit(0);
    }
    SavePanelState();
    g_buttons.UpdateStates(g_panel_visible, g_show_high_news_lines, g_show_med_news_lines);
}

void ToggleNewsHighLines()
{
    SetNewsModeFromFlags(!g_show_high_news_lines, g_show_med_news_lines);
}

void ToggleNewsMedLines()
{
    SetNewsModeFromFlags(g_show_high_news_lines, !g_show_med_news_lines);
}

void CloseAllPositionsEmergency()
{
    Print("[BUTTON] Closing all open positions.");
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!pos.SelectByIndex(i)) continue;
        ulong ticket = pos.Ticket();
        if(trade.PositionClose(ticket))
            PrintFormat("[BUTTON] Closed #%I64u (%s)", ticket, pos.Symbol());
        else
            PrintFormat("[BUTTON] Failed to close #%I64u | Error %d", ticket, GetLastError());
    }
}

void ManualButtonOrder(const int signal)
{
    if(signal == 0) return;
    double lot = g_buttons.GetManualLot(g_manual_button_lot);
    if(lot <= 0.0)
    {
        Print("[BUTTON] Invalid lot size for manual trade.");
        return;
    }
    g_manual_button_lot = lot;
    g_buttons.SetManualLot(g_manual_button_lot);
    PrintFormat("[BUTTON] Manual %s requested (%.2f lots)", signal > 0 ? "BUY" : "SELL", g_manual_button_lot);
    double sl_points = DetermineSLPoints();
    string block_reason = "";
    if(!EvaluateTradeConditions(signal, g_manual_button_lot, sl_points, block_reason))
    {
        if(block_reason == "") block_reason = "Entry conditions not met.";
        PrintFormat("[BUTTON] Blocked: %s", block_reason);
        return;
    }
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippagePoints);
    bool ok = false;
    string comment = (InpTradeComment != "") ? InpTradeComment : "[BUTTON] Manual Entry";
    if(StringFind(comment, "_C") < 0)
        comment = comment + "_C" + (string)ChartID();
    double entry_price = signal > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl_price = signal > 0 ? entry_price - sl_points * _Point
                                 : entry_price + sl_points * _Point;
    double tp_price = 0.0;
    if(signal > 0)
        ok = trade.Buy(g_manual_button_lot, _Symbol, entry_price, sl_price, 0, comment);
    else
        ok = trade.Sell(g_manual_button_lot, _Symbol, entry_price, sl_price, 0, comment);
    if(ok)
    {
        ulong ticket = trade.ResultOrder();
        if(pos.SelectByTicket(ticket))
        {
            double actual_entry = pos.PriceOpen();
            double actual_sl = pos.StopLoss();
            tp_price = CalculateTP((long)ticket, _Symbol, actual_entry, actual_sl,
                                   signal > 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
            if(tp_price > 0.0)
                trade.PositionModify(ticket, actual_sl, tp_price);
        }
        if(ReductionTradesRemaining > 0) ReductionTradesRemaining--;
        g_last_trade_time = TimeCurrent();
        SaveCriticalState();
        Print("[BUTTON] Manual trade opened successfully.");
    }
    else
        PrintFormat("[BUTTON] Failed manual trade | Error %d", GetLastError());
}

//+------------------------------------------------------------------+
//| TESTING MODE: Open test positions with predefined results        |
//+------------------------------------------------------------------+
void OpenTestPositions()
{
    if(!g_testing_mode_active)
    {
        Print("[TESTING MODE] ERROR: Attempted to use testing mode while disabled!");
        return;
    }
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(InpSlippagePoints);
    double points_for_result = CalculateTestingPoints();
    if(points_for_result <= 0.0) return;
    if(InpDebugTestingMode)
        PrintFormat("[TESTING MODE DEBUG] Calculated points for result: %.1f points", points_for_result);
    string order_comment = "[TEST] Forced position";
    int opened = 0;
    for(int i = 0; i < g_testing_cfg.positions; i++)
    {
        int signal_dir = ((i % 2) == 0) ? 1 : -1;
        if(CreateTestingPosition(signal_dir, points_for_result, order_comment))
            opened++;
        Sleep(100);
    }
    PrintFormat("%s Forced positions opened: %d | SL/TP manage exits | Risk rules still active",
                g_testing_label, opened);

    if(g_testing_cfg.opposite_entry)
    {
        g_test_opp_pending = true;
        g_test_opp_done = false;
        g_test_opp_time = (datetime)(TimeCurrent() + (long)g_testing_cfg.opposite_delay_min * 60);
        if(InpDebug_StatusChanges)
            PrintFormat("%s Opposite entry scheduled in %d min", g_testing_label, g_testing_cfg.opposite_delay_min);
    }

    // Build correlation scenario across provided symbols
    if(g_testing_cfg.correlation_enabled && StringLen(g_testing_cfg.correlation_symbols) > 0)
    {
        string list = g_testing_cfg.correlation_symbols;
        StringReplace(list, " ", ""); // remove spaces
        int idx = 0, opened = 0;
        while(idx >= 0)
        {
            int comma = StringFind(list, ",", idx);
            string token = (comma >= 0) ? StringSubstr(list, idx, comma - idx) : StringSubstr(list, idx);
            if(StringLen(token) > 0)
            {
                string sym = token;
                if(SymbolSelect(sym, true))
                {
                    bool buy = g_testing_cfg.correlation_alternate ? ((opened % 2) == 0) : true;
                    double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
                    double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                    double entry = buy ? ask : bid;
                    int digits_sym = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
                    double point_sym = SymbolInfoDouble(sym, SYMBOL_POINT);
                    double slp = buy ? entry - 100.0 * point_sym : entry + 100.0 * point_sym;
                    double tpp = buy ? entry + 1000.0 * point_sym : entry - 1000.0 * point_sym;
                    slp = NormalizeDouble(slp, digits_sym);
                    tpp = NormalizeDouble(tpp, digits_sym);
                    string corr_comment = "[TEST] Corr group";
                    bool ok2 = buy ? trade.Buy(g_testing_cfg.correlation_lots, sym, entry, slp, tpp, corr_comment)
                                   : trade.Sell(g_testing_cfg.correlation_lots, sym, entry, slp, tpp, corr_comment);
                    if(ok2) PrintFormat("%s Correlation: Opened %s on %s | Lots %.2f", g_testing_label, buy ? "BUY" : "SELL", sym, g_testing_cfg.correlation_lots);
                    else PrintFormat("%s Correlation: FAILED on %s | Error %d", g_testing_label, sym, GetLastError());
                    Sleep(50);
                    opened++;
                }
                else
                {
                    PrintFormat("%s Correlation: SymbolSelect failed for '%s'", g_testing_label, sym);
                }
            }
            if(comma < 0) break;
            idx = comma + 1;
        }
        if(opened > 0)
        {
            g_corr_test_started = true;
            if(g_testing_cfg.correlation_attempt_delay_min > 0)
            {
                g_corr_attempt_scheduled = true;
                g_corr_attempt_done = false;
                g_corr_attempt_time = (datetime)(TimeCurrent() + (long)g_testing_cfg.correlation_attempt_delay_min * 60);
                if(InpDebug_StatusChanges)
                    PrintFormat("%s Correlation: Current-symbol attempt scheduled in %d min",
                                g_testing_label, g_testing_cfg.correlation_attempt_delay_min);
            }
        }
    }
}

void OnTimer(){}
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    g_panel.OnEvent(id,lparam,dparam,sparam);
    double edited_lot;
    if(g_buttons.HandleLotEdit(id,sparam,edited_lot))
    {
        if(edited_lot > 0.0)
            g_manual_button_lot = edited_lot;
        return;
    }
    ENUM_BUTTON_ACTION act = g_buttons.HandleEvent(id,lparam,dparam,sparam);
    switch(act)
    {
        case Button_TogglePanel: TogglePanelVisibility(); break;
        case Button_ToggleNewsHigh: ToggleNewsHighLines(); break;
        case Button_ToggleNewsMed: ToggleNewsMedLines(); break;
        case Button_CloseAll: CloseAllPositionsEmergency(); break;
        case Button_ManualBuy: ManualButtonOrder(1); break;
        case Button_ManualSell: ManualButtonOrder(-1); break;
        default: break;
    }
}
bool ValidateSystemLogic()
{
    if((InpRangeMethod == EMA_Distance || InpTrendMethod == EMA_Momentum) && !InpUseEmaFilter)
     {
        Print("EMA Distance/Momentum filter requires EMA Filter to be enabled");
        return false;
     }
    if(InpRangeMethod != Range_Filter_Off && InpTrendMethod != Trend_Filter_Off) Print("SYSTEM INFO: Both Range and Trend filters active - trade must pass both conditions");
    Print("Logic validation completed");
    return true;
}
//=====================================================================
// =================== NEWS DATABASE ======================
string g_embedded_news_data[] =
{
"2025.07.15 13:30|USD|H|Core CPI",
"2025.07.16 10:00|EUR|M|German ZEW Economic Sentiment",
"2025.07.17 19:00|USD|H|FOMC Statement",
"2025.07.25 10:00|EUR|M|CPI",
"2025.09.26 08:30|CHF|M|CPI",
"2025.09.26 09:00|JPY|M|CPI"
};
