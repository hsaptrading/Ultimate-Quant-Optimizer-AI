//+------------------------------------------------------------------+
//|                                       Ultimate Range Breaker.mq5 |
//|                              Time-Based Breakout Strategy        |
//|               Fusion with DualEA Management Systems              |
//+------------------------------------------------------------------+
#property copyright "SA TRADING TOOLS"
#property version   "3.00"
#property description "Range breakout EA based on time windows"
#property description "With professional Prop Firm risk management"
#property strict

//--- Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Objetos de trading
CTrade         trade;
CPositionInfo  position;
CSymbolInfo    symbolInfo;

//+------------------------------------------------------------------+
//| ENUMERACIONES                                                     |
//+------------------------------------------------------------------+
enum ENUM_EXECUTION_MODE
{
   EXECUTION_PENDING_STOP = 0, // Pending Orders (Buy/Sell Stop)
   EXECUTION_MARKET = 1        // Market Execution (Manual)
};

enum ENUM_ENTRY_TYPE
{
   ENTRY_CROSS = 0,        // Cross - Entry when price crosses level
   ENTRY_BAR_CLOSE = 1     // Bar Close - Wait for candle confirmation
};

enum ENUM_LOT_SIZING_MODE
{
   Fixed_Lot = 0,          // Fixed Lot
   Risk_Percent = 1        // Risk Percent
};

enum ENUM_SL_MODE
{
   SL_Fixed_Points = 0,    // Fixed Points
   SL_ATR_Based = 1,       // ATR Based
   SL_Range_Based = 2      // Range Based
};

enum ENUM_EXIT_STRATEGY_MODE
{
   Exit_Strategy_Off = 0,      // Off
   Breakeven_Points = 1,       // Breakeven (Points)
   Trailing_Stop_Points = 2,   // Trailing Stop (Points)
   Trailing_Stop_ATR = 3       // Trailing Stop (ATR)
};

enum ENUM_LIMIT_MODE
{
   Limit_Off = 0,          // Off
   Limit_Percent = 1,      // Percent
   Limit_Money = 2         // Money
};

enum ENUM_NEWS_FILTER_MODE
{
   News_Filter_Off = 0,            // Off
   Block_New_Trades_Only = 1,      // Block New Trades Only
   Manage_Open_Trades_Only = 2,    // Manage Open Trades Only
   Block_And_Manage = 3            // Block And Manage
};

enum ENUM_TRADE_DIRECTION
{
   Buys_Only = 0,           // Buys Only
   Sells_Only = 1,          // Sells Only
   Both_Directions = 2      // Both Directions
};

enum ENUM_SCALPING_TIMEFRAME
{
   TF_M5 = PERIOD_M5,       // M5
   TF_M15 = PERIOD_M15,     // M15
   TF_M30 = PERIOD_M30      // M30
};

enum ENUM_TIME_BASED_CLOSE
{
   TimeClose_Off = 0,  // Off
   TimeClose_01 = 1,   // 01:00 (Server)
   TimeClose_02 = 2,   // 02:00 (Server)
   TimeClose_03 = 3,   // 03:00 (Server)
   TimeClose_04 = 4,   // 04:00 (Server)
   TimeClose_05 = 5,   // 05:00 (Server)
   TimeClose_06 = 6,   // 06:00 (Server)
   TimeClose_07 = 7,   // 07:00 (Server)
   TimeClose_08 = 8,   // 08:00 (Server)
   TimeClose_09 = 9,   // 09:00 (Server)
   TimeClose_10 = 10,  // 10:00 (Server)
   TimeClose_11 = 11,  // 11:00 (Server)
   TimeClose_12 = 12,  // 12:00 (Server)
   TimeClose_13 = 13,  // 13:00 (Server)
   TimeClose_14 = 14,  // 14:00 (Server)
   TimeClose_15 = 15,  // 15:00 (Server)
   TimeClose_16 = 16,  // 16:00 (Server)
   TimeClose_17 = 17,  // 17:00 (Server)
   TimeClose_18 = 18,  // 18:00 (Server)
   TimeClose_19 = 19,  // 19:00 (Server)
   TimeClose_20 = 20,  // 20:00 (Server)
   TimeClose_21 = 21,  // 21:00 (Server)
   TimeClose_22 = 22,  // 22:00 (Server)
   TimeClose_23 = 23   // 23:00 (Server)
};

enum ENUM_RISK_SCOPE
{
   Scope_EA_ChartOnly = 0,  // EA Trades (Only Chart Trades)
   Scope_EA_AllCharts = 1,  // EA Trades (All Charts)
   Scope_AllTrades = 2      // All Trades (EA, 3rd Party EA And Manual)
};

enum ENUM_NEWS_WINDOW
{
   N2 = 2,     // 2 Minutes
   N5 = 5,     // 5 Minutes
   N10 = 10,   // 10 Minutes
   N15 = 15,   // 15 Minutes
   N30 = 30,   // 30 Minutes
   N60 = 60,   // 60 Minutes
   N120 = 120  // 120 Minutes
};

enum ENUM_NEWS_IMPACT_TO_MANAGE
{
   Manage_High_Impact = 0,    // High Impact
   Manage_Medium_Impact = 1,  // Medium Impact
   Manage_Both = 2            // Both
};

enum ENUM_NEWS_VISUALIZER_MODE
{
   Visualizer_Off = 0,          // Off
   High_Impact_Only = 1,        // High Impact Only
   Medium_Impact_Only = 2,      // Medium Impact Only
   High_And_Medium_Impact = 3   // High And Medium Impact
};

enum ENUM_ADX_TREND_MODE
{
   ADX_Trend_Off = 0,       // Off
   ADX_Trend_Strong = 1     // ADX Strong (> Threshold)
};

enum ENUM_RSI_CONFIRM_MODE
{
   RSI_Confirm_Off = 0,     // Off
   RSI_Confirm_50 = 1       // Confirm 50 Level
};

//+------------------------------------------------------------------+
//| INPUTS - GENERAL SETTINGS                                         |
//+------------------------------------------------------------------+
input group "========== GENERAL SETTINGS =========="
input long         InpMagicNumber = 100820;              // Magic Number
input string       InpTradeComment = "URB";              // Trade Comment
input ENUM_TRADE_DIRECTION InpTradeDirection = Both_Directions; // Trade Direction
input ENUM_SCALPING_TIMEFRAME InpSignalTF = TF_M15;       // Chart Timeframe
input bool         InpUseMultiTimeframe = false;          // Enable Multi-Timeframe

//+------------------------------------------------------------------+
//| INPUTS - RANGE SCHEDULE                                           |
//+------------------------------------------------------------------+
input group "========== RANGE SCHEDULE =========="
input int          InpRangeStartHour = 12;               // Range Start Hour
input int          InpRangeStartMin = 15;                // Range Start Minute
input int          InpRangeEndHour = 16;                 // Range End Hour
input int          InpRangeEndMin = 0;                   // Range End Minute

//+------------------------------------------------------------------+
//| INPUTS - TRADING WINDOW (KILL ZONE)                                |
//+------------------------------------------------------------------+
input group "========== TRADING WINDOW (Kill Zone) =========="
input int          InpTradingStartHour = 16;             // Trading Start Hour
input int          InpTradingStartMin = 30;              // Trading Start Minute
input int          InpTradingEndHour = 17;               // Trading End Hour
input int          InpTradingEndMin = 30;                // Trading End Minute

//+------------------------------------------------------------------+
//| INPUTS - EXECUTION & BREAKOUT                                      |
//+------------------------------------------------------------------+
input group "========== EXECUTION & BREAKOUT =========="
input ENUM_EXECUTION_MODE InpExecutionMode = EXECUTION_PENDING_STOP; // Execution Mode
input ENUM_ENTRY_TYPE InpEntryType = ENTRY_CROSS;        // Entry Type (Market Only)
input double       InpBreakoutBuffer = 2000;             // Breakout Buffer (Points)
input double       InpMinBodyPercent = 50;               // Min Body % (Bar Close)
input int          InpMinBarsAfterLoss = 5;              // Min Bars After Loss
input int          InpMinBarsAfterAnyTrade = 2;          // Min Bars Between Trades

//+------------------------------------------------------------------+
//| INPUTS - RISK MANAGEMENT (STOP LOSS & TAKE PROFIT)                |
//+------------------------------------------------------------------+
input group "========== RISK MANAGEMENT (STOP LOSS & TAKE PROFIT) =========="
input ENUM_LOT_SIZING_MODE InpLotSizingMode = Risk_Percent;      // Lot Sizing Mode
input double               InpFixedLot = 0.01;                   // Fixed Lot Size
input double               InpRiskPerTradePct = 1.0;             // Risk Per Trade %
input ENUM_SL_MODE         InpSlMethod = SL_Fixed_Points;        // Stop Loss Method
input double               InpFixedSL_In_Points = 5000;          // Fixed SL (Points)
input int                  InpAtrSlPeriod = 14;                  // ATR Period for Stop Loss
input double               InpAtrSlMultiplier = 1.5;             // ATR Multiplier for Stop Loss
input double               InpSLRangeMultiplier = 0.5;           // Range Multiplier for SL
input double               InpSLRangeMinPoints = 1000;           // Range SL Min (Points)
input double               InpSLRangeMaxPoints = 10000;          // Range SL Max (Points)
input double               InpRiskRewardRatio = 2.0;             // Risk:Reward Ratio (TP = SL * Ratio)
input ENUM_TIME_BASED_CLOSE InpTimeBasedClose = TimeClose_Off;   // Time-Based Close (Server Time)
input int                  InpMaxTradesPerSymbol = 1;            // Max Trades Per Symbol (1-3)
input double               InpSecondTradeLotMultiplier = 1.0;    // Second Trade Lot Multiplier
input int                  InpCooldownMinutesAfterClose = 5;     // Cooldown Minutes After Position Close
input double               InpMinDistance_In_Points = 1000;      // Min Distance Before Re-entry (Points)
input bool                 InpRequireSetupConfirmation = true;   // Require Setup Confirmation for Additional Trades
input int                  InpSlippagePoints = 10;               // Max Slippage (Points)
input double               InpMaxSpreadPoints = 0;                // Max Spread (Points, 0=off)

//+------------------------------------------------------------------+
//| INPUTS - BREAKEVEN & TRAILING STOP                                 |
//+------------------------------------------------------------------+
input group "========== BREAKEVEN & TRAILING STOP =========="
input ENUM_EXIT_STRATEGY_MODE InpExitStrategyMode = Trailing_Stop_Points; // Exit Strategy Mode
input double               InpBreakevenTriggerPoints = 3000;     // Breakeven Trigger (Points)
input double               InpBreakevenOffsetPoints = 500;       // Breakeven Offset (Points)
input double               InpTrailingStartPoints = 5000;        // Trailing Start (Points)
input double               InpTrailingStepPoints = 5000;         // Trailing Step (Points)
input double               InpAtrTrailingMultiplier = 1.0;       // ATR Trailing Multiplier
input int                  InpAtrTrailingPeriod = 14;            // ATR Period for Trailing Stop

//+------------------------------------------------------------------+
//| INPUTS - SETTINGS FOR PROP FIRM                                    |
//+------------------------------------------------------------------+
input group "========== SETTINGS FOR PROP FIRM =========="
input ENUM_LIMIT_MODE      InpDailyLossMode = Limit_Percent;     // Daily Loss Limit Mode
input double               InpDailyLossValue = 4.5;              // Daily Loss Limit Value (0=Off)
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

//+------------------------------------------------------------------+
//| INPUTS - WEEKEND, CORRELATION & HEDGING FILTER                    |
//+------------------------------------------------------------------+
input group "========== WEEKEND, CORRELATION & HEDGING FILTER =========="
input bool                 InpUseWeekendManagement = true;       // Enable Weekend Management
input bool                 InpCloseOnFriday = true;              // Close Positions Before Weekend
input int                  InpFridayCloseHour = 20;              // Friday Close Hour
input bool                 InpBlockLateFriday = true;            // Block New Entries Late Friday
input int                  InpFridayBlockHour = 18;              // Friday Block Hour
input bool                 InpBlockOppositeDirections = true;    // Block Opposite Direction Trades (Hedging)
input bool                 InpUseCorrelationFilter = false;      // Use Correlation Filter
input int                  InpMaxCorrelatedPositions = 2;        // Max Positions in Correlated Pairs
input string               InpCorrelatedPairs = "US30,US100;US30,US500;US100,US500"; // Correlated Pairs

//+------------------------------------------------------------------+
//| INPUTS - NEWS FILTER                                               |
//+------------------------------------------------------------------+
input group "========== NEWS FILTER =========="
input ENUM_NEWS_FILTER_MODE InpNewsFilterMode = Block_And_Manage;    // News Filter Mode
input ENUM_NEWS_IMPACT_TO_MANAGE InpNewsImpactToManage = Manage_Both; // News Impact to Manage
input ENUM_NEWS_WINDOW     InpNewsWindowMin = N10;                   // Minutes Before/After News
input int                  InpDaysLookahead = 7;                     // Days to Look Ahead for News
input bool                 InpNewsTimesAreUTC = true;                // News Times are UTC (TESTER)
input int                  InpManualUtcOffset = 0;                   // Manual UTC to Server Offset (Hours, TESTER)
input ENUM_NEWS_VISUALIZER_MODE InpNewsVisualizerMode = Visualizer_Off; // News Visualizer Mode (TESTER ONLY)

//+------------------------------------------------------------------+
//| INPUTS - VARIABLE RISK MANAGEMENT                                  |
//+------------------------------------------------------------------+
input group "========== VARIABLE RISK MANAGEMENT (Challenges Only) =========="
input bool         InpUseVariableRisk = false;           // Use Variable Risk Management
input double       InpBaseRiskPercent = 1.0;             // Base Risk Per Trade (%)
input double       InpProfitTargetPerLevel = 500.0;      // Profit Target Per Level ($)
input double       InpRiskIncreasePercent = 0.25;        // Risk Increase Per Level (%)
input double       InpMaxRiskPercent = 2.5;              // Maximum Risk Per Trade (%)
input double       InpLossReductionFactor = 0.75;        // Risk Reduction After Loss
input int          InpReductionTrades = 2;               // Trades to Maintain Reduced Risk
input double       InpVarRiskDailyLossLimit = 5.0;       // Daily Loss Limit (%)


//+------------------------------------------------------------------+
//| INPUTS - MARKET ACTIVITY FILTER                                    |
//+------------------------------------------------------------------+
input group "========== MARKET ACTIVITY FILTER =========="
input bool                 InpUseActivityFilter = false;          // Use Market Activity Filter
input int                  InpActivityVolumePeriod = 20;          // Volume Average Period
input double               InpMinActivityMultiple = 1.2;          // Minimum Activity Multiple
input bool                 InpAvoidLowActivity = true;            // Block Trades in Low Activity

//+------------------------------------------------------------------+
//| INPUTS - ADX TREND FILTER                                          |
//+------------------------------------------------------------------+
input group "========== ADX TREND FILTER =========="
input ENUM_ADX_TREND_MODE  InpAdxTrendMode = ADX_Trend_Off;        // ADX Trend Mode
input int                  InpAdxTrendPeriod = 14;                 // ADX Period
input double               InpAdxTrendThreshold = 25.0;            // ADX Threshold (Strong Trend)

//+------------------------------------------------------------------+
//| INPUTS - RSI CONFIRM FILTER                                        |
//+------------------------------------------------------------------+
input group "========== RSI CONFIRM FILTER =========="
input ENUM_RSI_CONFIRM_MODE InpRsiConfirmMode = RSI_Confirm_Off;   // RSI Confirm Mode
input int                  InpRsiPeriod = 14;                      // RSI Period
input double               InpRsiConfirmLevel = 50.0;              // RSI Confirmation Level


//+------------------------------------------------------------------+
//| INPUTS - VISUALIZATION                                             |
//+------------------------------------------------------------------+
input group "========== VISUALIZATION =========="
input bool         InpShowPanel = true;                  // Show Panel
input bool         InpDrawLevels = true;                 // Draw S/R Levels
input color        InpSupportColor = clrDodgerBlue;      // Support Color
input color        InpResistanceColor = clrCrimson;      // Resistance Color

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                 |
//+------------------------------------------------------------------+
//--- Range Breaker Variables
double       gSupportLevel = 0;
double       gResistanceLevel = 0;
double       gRangeSize = 0;
datetime     gRangeStartTime = 0;
datetime     gRangeEndTime = 0;
datetime     gLastRangeCalcDay = 0;
bool         gRangeCalculatedToday = false;
bool         gCrossedUp = false;
bool         gCrossedDown = false;

//--- Trading State
datetime     gLastTradeTime = 0;
datetime     gLastPositionCloseTime = 0;
bool         gLastCloseWasLoss = false;
bool         gIsEaStopped = false;
datetime     gResetTime = 0;

//--- News Filter Structure and Data
struct NewsEvent_EA
{
   datetime time;
   string   currency;
   string   name;
   int      importance;    // 1=Low, 2=Medium, 3=High
};
NewsEvent_EA g_all_news[];
datetime     g_lastNewsLoad = 0;

//--- Indicator Handles
int          gATRHandle = INVALID_HANDLE;
int          gADXHandle = INVALID_HANDLE;
int          gRSIHandle = INVALID_HANDLE;

//--- Symbol Info
double       gPointValue;
int          gDigits;

//--- Daily Metrics
int          gLastDay = -1;
double       gDailyStartBalance = 0;
double       gTotalStartEquity = 0;
double       gInitialEquity = 0;

//--- Variable Risk State
int          gConsecutiveLosses = 0;
int          gReductionTradesRemaining = 0;
bool         gDailyLimitReached = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Configurar símbolo
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Error al configurar símbolo");
      return(INIT_FAILED);
   }

   //--- Configurar punto y dígitos
   gPointValue = symbolInfo.Point();
   gDigits = (int)symbolInfo.Digits();

   //--- Configurar trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   //--- Inicializar ATR si se necesita
   if(InpSlMethod == SL_ATR_Based || InpExitStrategyMode == Trailing_Stop_ATR)
   {
      int atr_period = (InpSlMethod == SL_ATR_Based) ? InpAtrSlPeriod : InpAtrTrailingPeriod;
      gATRHandle = iATR(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, atr_period);
      if(gATRHandle == INVALID_HANDLE)
      {
         Print("Error al crear indicador ATR");
         return(INIT_FAILED);
      }
   }

   //--- Inicializar ADX si se necesita
   if(InpAdxTrendMode != ADX_Trend_Off)
   {
      gADXHandle = iADX(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, InpAdxTrendPeriod);
      if(gADXHandle == INVALID_HANDLE)
      {
         Print("Error al crear indicador ADX");
         return(INIT_FAILED);
      }
   }

   //--- Inicializar RSI si se necesita
   if(InpRsiConfirmMode != RSI_Confirm_Off)
   {
      gRSIHandle = iRSI(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, InpRsiPeriod, PRICE_CLOSE);
      if(gRSIHandle == INVALID_HANDLE)
      {
         Print("Error al crear indicador RSI");
         return(INIT_FAILED);
      }
   }

   //--- Inicializar métricas diarias
   gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gTotalStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gInitialEquity = gTotalStartEquity;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   gLastDay = dt.day;

   //--- Crear panel si está habilitado
   if(InpShowPanel)
      CreateInfoPanel();

   //--- Load news data for news filter
   if(InpNewsFilterMode != News_Filter_Off)
      LoadNews();

   Print("=== Ultimate Range Breaker v3.0 Iniciado ===");
   PrintFormat("Rango: %02d:%02d - %02d:%02d | Trading: %02d:%02d - %02d:%02d",
               InpRangeStartHour, InpRangeStartMin, InpRangeEndHour, InpRangeEndMin,
               InpTradingStartHour, InpTradingStartMin, InpTradingEndHour, InpTradingEndMin);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gATRHandle != INVALID_HANDLE) 
      IndicatorRelease(gATRHandle);
   if(gADXHandle != INVALID_HANDLE)
      IndicatorRelease(gADXHandle);
   if(gRSIHandle != INVALID_HANDLE)
      IndicatorRelease(gRSIHandle);
   
   ObjectsDeleteAll(0, "RB_");
   Print("EA detenido. Razón: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Actualizar datos del símbolo
   if(!symbolInfo.RefreshRates()) 
      return;

   //--- Actualizar métricas diarias
   UpdateDailyMetrics();

   //--- Verificar límites de riesgo (Prop Firm)
   if(!RiskOverlaysOK())
      return;

   //--- Gestión de fin de semana
   if(InpUseWeekendManagement)
      WeekendManagement();

   //--- Verificar y calcular rango
   CheckAndCalculateRange();

   //--- Dibujar niveles
   if(InpDrawLevels && gSupportLevel > 0 && gResistanceLevel > 0)
      DrawLevels();

   //--- Actualizar panel
   if(InpShowPanel) 
      UpdateInfoPanel();

   //--- Gestionar breakeven y trailing
   if(InpExitStrategyMode == Breakeven_Points)
      ManageBreakeven();
   else if(InpExitStrategyMode == Trailing_Stop_Points || InpExitStrategyMode == Trailing_Stop_ATR)
      ManageTrailingStop();

   //--- Time-Based Close
   if(InpTimeBasedClose != TimeClose_Off)
      CheckTimeBasedClose();

   //--- Verificar señales de entrada (solo si estamos en ventana de trading)
   if(IsInTradingWindow() && !gIsEaStopped)
   {
      if(SpreadOK())
      {
         if(InpExecutionMode == EXECUTION_PENDING_STOP)
            ManagePendingOrders();
         else
            CheckForTradeSignals();
      }
   }
   else
   {
      // Fuera de horas, limpiar pendientes
      DeletePendingOrders();
   }
}

//+------------------------------------------------------------------+
//| PENDING ORDERS LOGIC                                              |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   if(gSupportLevel <= 0 || gResistanceLevel <= 0)
      return;
      
   if(CountOpenPositions() >= InpMaxTradesPerSymbol)
   {
      // Si ya tenemos trades abiertos, borrar pendientes restantes (OCO)
      if(InpBlockOppositeDirections)
         DeletePendingOrders();
      return;
   }
   
   double bufferPoints = InpBreakoutBuffer * gPointValue;
   double buyStopPrice = gResistanceLevel + bufferPoints;
   double sellStopPrice = gSupportLevel - bufferPoints;
   
   // Normalizar precios
   buyStopPrice = NormalizeDouble(buyStopPrice, gDigits);
   sellStopPrice = NormalizeDouble(sellStopPrice, gDigits);
   
   // Colocar Buy Stop si no existe
   if(!HasOrderType(ORDER_TYPE_BUY_STOP) && !HasPositionType(POSITION_TYPE_BUY))
   {
      if(!InpBlockOppositeDirections || !HasPositionType(POSITION_TYPE_SELL))
         PlacePendingOrder(ORDER_TYPE_BUY_STOP, buyStopPrice);
   }
   
   // Colocar Sell Stop si no existe
   if(!HasOrderType(ORDER_TYPE_SELL_STOP) && !HasPositionType(POSITION_TYPE_SELL))
   {
       if(!InpBlockOppositeDirections || !HasPositionType(POSITION_TYPE_BUY))
         PlacePendingOrder(ORDER_TYPE_SELL_STOP, sellStopPrice);
   }
}

void PlacePendingOrder(ENUM_ORDER_TYPE type, double price)
{
   //--- Calcular SL y TP
   double sl_points = DetermineSLPoints();
   double tp_points = CalculateTPPoints(sl_points);
   
   double lotSize = CalcLotsByRisk(sl_points);
   if(lotSize <= 0) 
   {
      Print("[DEBUG] PlacePendingOrder: lotSize <= 0, no se puede colocar orden");
      return;
   }
   
   double sl = 0, tp = 0;
   
   if(sl_points > 0)
   {
      double slDistance = sl_points * gPointValue;
      sl = (type == ORDER_TYPE_BUY_STOP) ? price - slDistance : price + slDistance;
      sl = NormalizeDouble(sl, gDigits);
   }
   
   if(tp_points > 0)
   {
      double tpDistance = tp_points * gPointValue;
      tp = (type == ORDER_TYPE_BUY_STOP) ? price + tpDistance : price - tpDistance;
      tp = NormalizeDouble(tp, gDigits);
   }
   
   string comment = InpTradeComment;
   
   PrintFormat("[DEBUG] Colocando %s @ %.2f | SL: %.2f | TP: %.2f | Lot: %.2f",
               (type == ORDER_TYPE_BUY_STOP) ? "BUY STOP" : "SELL STOP",
               price, sl, tp, lotSize);
   
   bool result = false;
   if(type == ORDER_TYPE_BUY_STOP)
      result = trade.BuyStop(lotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   else
      result = trade.SellStop(lotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
   
   if(!result)
      PrintFormat("[ERROR] Falló envío de orden. Error: %d - %s", 
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else
      PrintFormat("[OK] Orden enviada. Ticket: %d", trade.ResultOrder());
}

void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

bool HasOrderType(ENUM_ORDER_TYPE type)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && 
            OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && 
            (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnTrade - Track closed positions                                  |
//+------------------------------------------------------------------+
void OnTrade()
{
   static int lastDealCount = 0;
   
   HistorySelect(0, TimeCurrent());
   int currentDealCount = HistoryDealsTotal();
   
   if(currentDealCount > lastDealCount)
   {
      ulong ticket = HistoryDealGetTicket(currentDealCount - 1);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
         {
            gLastPositionCloseTime = TimeCurrent();
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            gLastCloseWasLoss = (profit < 0);
            
            if(InpUseVariableRisk)
               UpdateVariableRiskOnTrade(!gLastCloseWasLoss);
         }
      }
   }
   lastDealCount = currentDealCount;
}

//+------------------------------------------------------------------+
//| RANGE LOGIC - Verificar y calcular rango                         |
//+------------------------------------------------------------------+
void CheckAndCalculateRange()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dtNow;
   TimeToStruct(currentTime, dtNow);
   
   int currentMinutes = dtNow.hour * 60 + dtNow.min;
   int rangeEndMinutes = InpRangeEndHour * 60 + InpRangeEndMin;
   
   MqlDateTime dtLastCalc;
   TimeToStruct(gLastRangeCalcDay, dtLastCalc);
   
   bool isNewDay = (dtNow.day != dtLastCalc.day || 
                    dtNow.mon != dtLastCalc.mon || 
                    dtNow.year != dtLastCalc.year);
   
   if(isNewDay && currentMinutes >= rangeEndMinutes)
   {
      CalculateRangeLevels();
      gLastRangeCalcDay = currentTime;
      gRangeCalculatedToday = true;
   }
   else if(gSupportLevel == 0 || gResistanceLevel == 0)
   {
      CalculateRangeLevels();
      if(gSupportLevel > 0 && gResistanceLevel > 0)
         gLastRangeCalcDay = currentTime;
   }
}

//+------------------------------------------------------------------+
//| RANGE LOGIC - Calcular niveles de Soporte y Resistencia          |
//+------------------------------------------------------------------+
void CalculateRangeLevels()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime dtNow;
   TimeToStruct(currentTime, dtNow);
   
   MqlDateTime dtStart;
   TimeToStruct(currentTime, dtStart);
   dtStart.hour = InpRangeStartHour;
   dtStart.min = InpRangeStartMin;
   dtStart.sec = 0;
   datetime rangeStartTime = StructToTime(dtStart);
   
   MqlDateTime dtEnd;
   TimeToStruct(currentTime, dtEnd);
   dtEnd.hour = InpRangeEndHour;
   dtEnd.min = InpRangeEndMin;
   dtEnd.sec = 0;
   datetime rangeEndTime = StructToTime(dtEnd);
   
   if(rangeEndTime <= rangeStartTime)
      rangeEndTime += 86400;
   
   if(currentTime < rangeEndTime)
   {
      rangeStartTime -= 86400;
      rangeEndTime -= 86400;
   }
   
   double highest = 0;
   double lowest = DBL_MAX;
   datetime firstBarTime = 0;
   datetime lastBarTime = 0;
   int barsFound = 0;
   
   int totalBars = iBars(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF);
   for(int i = 0; i < totalBars; i++)
   {
      datetime barTime = iTime(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, i);
      
      if(barTime >= rangeStartTime && barTime < rangeEndTime)
      {
         double h = iHigh(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, i);
         double l = iLow(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, i);
         
         if(h > highest) highest = h;
         if(l < lowest) lowest = l;
         
         if(firstBarTime == 0 || barTime < firstBarTime)
            firstBarTime = barTime;
         if(barTime > lastBarTime)
            lastBarTime = barTime;
         
         barsFound++;
      }
      
      if(barTime < rangeStartTime)
         break;
   }
   
   if(barsFound == 0 || highest == 0 || lowest == DBL_MAX)
   {
      Print("Error: No se encontraron barras en el rango especificado");
      return;
   }
   
   gResistanceLevel = highest;
   gSupportLevel = lowest;
   gRangeSize = (highest - lowest) / gPointValue;
   gRangeStartTime = firstBarTime;
   gRangeEndTime = lastBarTime;
   
   gCrossedUp = false;
   gCrossedDown = false;
   
   PrintFormat("Rango: [%s - %s] | S:%.2f | R:%.2f | Size:%.0f pts",
               TimeToString(gRangeStartTime, TIME_MINUTES),
               TimeToString(gRangeEndTime + PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF), TIME_MINUTES),
               gSupportLevel, gResistanceLevel, gRangeSize);
}

//+------------------------------------------------------------------+
//| RANGE LOGIC - Verificar ventana de trading                       |
//+------------------------------------------------------------------+
bool IsInTradingWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   int currentMinutes = dt.hour * 60 + dt.min;
   int tradingStartMinutes = InpTradingStartHour * 60 + InpTradingStartMin;
   int tradingEndMinutes = InpTradingEndHour * 60 + InpTradingEndMin;
   
   if(tradingEndMinutes > tradingStartMinutes)
      return (currentMinutes >= tradingStartMinutes && currentMinutes <= tradingEndMinutes);
   else
      return (currentMinutes >= tradingStartMinutes || currentMinutes <= tradingEndMinutes);
}

//+------------------------------------------------------------------+
//| RANGE LOGIC - Verificar señales de trading                       |
//+------------------------------------------------------------------+
void CheckForTradeSignals()
{
   if(gSupportLevel <= 0 || gResistanceLevel <= 0)
      return;

   if(CountOpenPositions() >= InpMaxTradesPerSymbol)
      return;

   if(!CheckMinBarsElapsed())
      return;

   double bid = symbolInfo.Bid();
   double ask = symbolInfo.Ask();
   double bufferPoints = InpBreakoutBuffer * gPointValue;
   
   bool buySignal = false;
   bool sellSignal = false;
   
   if(InpEntryType == ENTRY_CROSS)
   {
      bool currentlyAboveResistance = (bid > gResistanceLevel + bufferPoints);
      bool currentlyBelowSupport = (ask < gSupportLevel - bufferPoints);
      
      if(currentlyAboveResistance && !gCrossedUp)
      {
         buySignal = true;
         gCrossedUp = true;
      }
      
      if(currentlyBelowSupport && !gCrossedDown)
      {
         sellSignal = true;
         gCrossedDown = true;
      }
   }
   else if(InpEntryType == ENTRY_BAR_CLOSE)
   {
      static datetime lastBarTime = 0;
      datetime currentBarTime = iTime(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 0);
      
      if(currentBarTime == lastBarTime)
         return;
      
      lastBarTime = currentBarTime;
      
      double prevClose = iClose(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 1);
      double prevOpen = iOpen(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 1);
      double prevHigh = iHigh(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 1);
      double prevLow = iLow(_Symbol, (ENUM_TIMEFRAMES)InpSignalTF, 1);
      
      double bodySize = MathAbs(prevClose - prevOpen);
      double candleRange = prevHigh - prevLow;
      
      double bodyPercent = 0;
      if(candleRange > 0)
         bodyPercent = (bodySize / candleRange) * 100;
      
      if(prevClose > gResistanceLevel + bufferPoints && !gCrossedUp)
      {
         if(prevClose > prevOpen && bodyPercent >= InpMinBodyPercent)
         {
            buySignal = true;
            gCrossedUp = true;
         }
      }
      
      if(prevClose < gSupportLevel - bufferPoints && !gCrossedDown)
      {
         if(prevClose < prevOpen && bodyPercent >= InpMinBodyPercent)
         {
            sellSignal = true;
            gCrossedDown = true;
         }
      }
   }
   
   //--- Verificar hedging
   if(InpBlockOppositeDirections)
   {
      if(buySignal && HasPositionType(POSITION_TYPE_SELL))
         buySignal = false;
      if(sellSignal && HasPositionType(POSITION_TYPE_BUY))
         sellSignal = false;
   }
   
   //--- Filtrar por Trade Direction
   if(InpTradeDirection == Buys_Only && sellSignal)
      sellSignal = false;
   if(InpTradeDirection == Sells_Only && buySignal)
      buySignal = false;
   
   if(buySignal)
      OpenTrade(ORDER_TYPE_BUY);
   
   if(sellSignal)
      OpenTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - Calcular lote por riesgo                       |
//+------------------------------------------------------------------+
double CalcLotsByRisk(double sl_points)
{
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vol_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   double lots = InpFixedLot;
   
   if(InpLotSizingMode == Risk_Percent && sl_points > 0)
   {
      double money_per_tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(money_per_tick > 0)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double risk_pct = InpUseVariableRisk ? CalculateVariableRisk() : InpRiskPerTradePct;
         if(risk_pct <= 0) return 0;
         
         double risk_money = equity * (risk_pct / 100.0);
         double sl_money_per_lot = sl_points * money_per_tick;
         lots = (sl_money_per_lot > 0) ? risk_money / sl_money_per_lot : InpFixedLot;
      }
   }
   
   if(vol_step <= 0) vol_step = 0.01;
   lots = MathMax(vol_min, MathMin(vol_max, MathFloor(lots / vol_step) * vol_step));
   
   return lots;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - Determinar SL en puntos                        |
//+------------------------------------------------------------------+
double DetermineSLPoints()
{
   double sl_points = InpFixedSL_In_Points;
   
   switch(InpSlMethod)
   {
      case SL_Fixed_Points:
         sl_points = InpFixedSL_In_Points;
         break;
         
      case SL_ATR_Based:
         if(gATRHandle != INVALID_HANDLE)
         {
            double atr_buffer[];
            ArraySetAsSeries(atr_buffer, true);
            if(CopyBuffer(gATRHandle, 0, 0, 1, atr_buffer) > 0)
               sl_points = (atr_buffer[0] / gPointValue) * InpAtrSlMultiplier;
         }
         break;
         
      case SL_Range_Based:
         if(gRangeSize > 0)
         {
            sl_points = gRangeSize * InpSLRangeMultiplier;
            // Apply Min/Max limits for optimization
            if(sl_points < InpSLRangeMinPoints)
               sl_points = InpSLRangeMinPoints;
            if(sl_points > InpSLRangeMaxPoints)
               sl_points = InpSLRangeMaxPoints;
         }
         else
            sl_points = InpFixedSL_In_Points;
         break;
   }
   
   return sl_points;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - Calcular TP                                    |
//+------------------------------------------------------------------+
double CalculateTPPoints(double sl_points)
{
   if(InpRiskRewardRatio <= 0 || sl_points <= 0)
      return 0;
   
   return sl_points * InpRiskRewardRatio;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - Variable Risk (Challenges Only)                 |
//+------------------------------------------------------------------+
double CalculateVariableRisk()
{
   if(!InpUseVariableRisk) 
      return InpRiskPerTradePct;
   
   // Check daily limits
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != gLastDay || gDailyStartBalance <= 0.0)
   {
      gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gDailyLimitReached = false;
   }
   
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double daily_loss_pct = ((gDailyStartBalance - current_balance) / gDailyStartBalance) * 100.0;
   
   // Variable Risk daily loss limit check
   if(InpVarRiskDailyLossLimit > 0 && daily_loss_pct >= InpVarRiskDailyLossLimit)
   {
      gDailyLimitReached = true;
      PrintFormat("[VARIABLE RISK] Daily loss limit reached: %.2f%%", daily_loss_pct);
      return 0.0;  // Block trading
   }
   
   // Calculate risk level based on profit
   int current_level = (int)MathFloor((current_balance - gDailyStartBalance) / InpProfitTargetPerLevel);
   current_level = MathMax(0, current_level);
   
   double risk_percent = InpBaseRiskPercent + (current_level * InpRiskIncreasePercent);
   
   // Apply loss reduction if active
   if(gReductionTradesRemaining > 0)
   {
      risk_percent *= InpLossReductionFactor;
      PrintFormat("[VARIABLE RISK] Reduced risk: %.2f%%, trades remaining: %d", risk_percent, gReductionTradesRemaining);
   }
   
   return MathMin(risk_percent, InpMaxRiskPercent);
}

void UpdateVariableRiskOnTrade(bool trade_won)
{
   if(!InpUseVariableRisk) return;
   
   if(trade_won)
   {
      gConsecutiveLosses = 0;
      gReductionTradesRemaining = 0;
   }
   else
   {
      gConsecutiveLosses++;
      if(gConsecutiveLosses >= 1)
         gReductionTradesRemaining = InpReductionTrades;
   }
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT - Prop Firm Risk Overlays                        |
//+------------------------------------------------------------------+
bool RiskOverlaysOK()
{
   if(gIsEaStopped)
      return false;
   
   double daily_pl, daily_pl_pct, daily_dd, daily_dd_pct;
   CalculateDailyPerformance(daily_pl, daily_pl_pct, daily_dd, daily_dd_pct);
   
   // Get scope-specific P/L based on InpRiskScope
   double scope_dd = daily_dd;
   double scope_dd_pct = daily_dd_pct;
   double scope_pl = daily_pl;
   double scope_pl_pct = daily_pl_pct;
   
   if(InpRiskScope == Scope_EA_ChartOnly)
   {
      // Only count trades from this EA on this chart
      GetEAGroupDailyPL(true, scope_pl, scope_pl_pct, scope_dd, scope_dd_pct);
   }
   else if(InpRiskScope == Scope_EA_AllCharts)
   {
      // Count trades from this EA across all charts (same magic or comment)
      GetEAGroupDailyPL(false, scope_pl, scope_pl_pct, scope_dd, scope_dd_pct);
   }
   // Scope_AllTrades uses the full account metrics (already calculated)
   
   //--- Daily Loss Check
   if(InpDailyLossMode != Limit_Off && InpDailyLossValue > 0)
   {
      bool limit_hit = false;
      
      if(InpDailyLossMode == Limit_Percent && scope_dd_pct >= InpDailyLossValue)
         limit_hit = true;
      else if(InpDailyLossMode == Limit_Money && scope_dd >= InpDailyLossValue)
         limit_hit = true;
      
      if(limit_hit)
      {
         PrintFormat("=== DAILY LOSS LIMIT HIT === (Scope: %s, DD: %.2f%%)", 
                     EnumToString((ENUM_RISK_SCOPE)InpRiskScope), scope_dd_pct);
         gIsEaStopped = true;
         gResetTime = GetNextDayStart();
         return false;
      }
   }
   
   //--- Daily Profit Check (stop trading on profit target)
   if(InpUseDailyProfitLimit && InpDailyProfitMode != Limit_Off && InpDailyProfitValue > 0)
   {
      bool profit_hit = false;
      
      if(InpDailyProfitMode == Limit_Percent && scope_pl_pct >= InpDailyProfitValue)
         profit_hit = true;
      else if(InpDailyProfitMode == Limit_Money && scope_pl >= InpDailyProfitValue)
         profit_hit = true;
      
      if(profit_hit)
      {
         PrintFormat("=== DAILY PROFIT LIMIT HIT === (Profit: %.2f%%)", scope_pl_pct);
         return false;  // Don't set gIsEaStopped - just skip new trades
      }
   }
   
   //--- Total Loss Check
   if(InpTotalLossMode != Limit_Off && InpTotalLossValue > 0)
   {
      double total_dd = gInitialEquity - AccountInfoDouble(ACCOUNT_EQUITY);
      double total_dd_pct = (gInitialEquity > 0) ? (total_dd / gInitialEquity) * 100 : 0;
      
      bool limit_hit = false;
      
      if(InpTotalLossMode == Limit_Percent && total_dd_pct >= InpTotalLossValue)
         limit_hit = true;
      else if(InpTotalLossMode == Limit_Money && total_dd >= InpTotalLossValue)
         limit_hit = true;
      
      if(limit_hit)
      {
         Print("=== TOTAL LOSS LIMIT HIT ===");
         gIsEaStopped = true;
         return false;
      }
   }
   
   //--- Max Open Trades
   if(InpMaxAccountOpenTrades > 0)
   {
      if(PositionsTotal() >= InpMaxAccountOpenTrades)
         return false;
   }
   
   //--- Max Open Lots
   if(InpMaxAccountOpenLots > 0)
   {
      double total_lots = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(position.SelectByIndex(i))
            total_lots += position.Volume();
      }
      if(total_lots >= InpMaxAccountOpenLots)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get EA Group Key (for cross-chart synchronization)                |
//+------------------------------------------------------------------+
string GetEAGroupKey()
{
   string key = InpTradeComment;
   if(key == "") key = "URB";
   StringToUpper(key);
   // Sanitize to alnum underscore only
   string cleaned = "";
   for(int i = 0; i < StringLen(key); i++)
   {
      ushort ch = StringGetCharacter(key, i);
      if((ch >= 65 && ch <= 90) || (ch >= 48 && ch <= 57) || ch == 95)
         cleaned += CharToString((uchar)ch);
   }
   if(cleaned == "") cleaned = "URB";
   return cleaned;
}

//+------------------------------------------------------------------+
//| Get EA Group Daily P/L (for all RiskScope modes)                   |
//+------------------------------------------------------------------+
void GetEAGroupDailyPL(bool only_chart, double &daily_pl, double &daily_pl_pct, double &daily_dd, double &daily_dd_pct)
{
   daily_pl = 0.0; daily_pl_pct = 0.0; daily_dd = 0.0; daily_dd_pct = 0.0;
   
   MqlDateTime dt; 
   TimeToStruct(TimeCurrent(), dt);
   datetime day_start = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
   HistorySelect(day_start, TimeCurrent());
   
   // Closed deals
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      long magic = (long)HistoryDealGetInteger(ticket, DEAL_MAGIC);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      
      bool match = false;
      if(only_chart)
      {
         // Only this EA on this chart (magic + symbol)
         match = (magic == InpMagicNumber && symbol == _Symbol);
      }
      else
      {
         // Consider same EA across charts by magic or comment
         if(magic == InpMagicNumber) match = true;
         if(!match && InpTradeComment != "" && StringFind(comment, InpTradeComment) >= 0) match = true;
      }
      
      if(match)
      {
         double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                  + HistoryDealGetDouble(ticket, DEAL_SWAP)
                  + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         daily_pl += p;
      }
   }
   
   // Floating PL from open positions
   for(int j = 0; j < PositionsTotal(); j++)
   {
      if(!position.SelectByIndex(j)) continue;
      
      long magic = (long)position.Magic();
      string symbol = position.Symbol();
      string comment = position.Comment();
      
      bool match = false;
      if(only_chart)
      {
         match = (magic == InpMagicNumber && symbol == _Symbol);
      }
      else
      {
         if(magic == InpMagicNumber) match = true;
         if(!match && InpTradeComment != "" && StringFind(comment, InpTradeComment) >= 0) match = true;
      }
      
      if(match) 
         daily_pl += position.Profit() + position.Swap();
   }
   
   // Calculate percentages
   if(daily_pl >= 0.0)
   {
      daily_dd = 0.0; 
      daily_dd_pct = 0.0;
      daily_pl_pct = (gDailyStartBalance > 0) ? (daily_pl / gDailyStartBalance) * 100.0 : 0.0;
   }
   else
   {
      daily_dd = -daily_pl;
      daily_dd_pct = (gDailyStartBalance > 0) ? (daily_dd / gDailyStartBalance) * 100.0 : 0.0;
      daily_pl_pct = (gDailyStartBalance > 0) ? (daily_pl / gDailyStartBalance) * 100.0 : 0.0;
   }
}

//+------------------------------------------------------------------+
//| Check Correlation Filter (for correlated indices/pairs)           |
//+------------------------------------------------------------------+
bool IsCorrelationOK()
{
   if(!InpUseCorrelationFilter) return true;
   
   string groups[];
   int group_count = StringSplit(InpCorrelatedPairs, ';', groups);
   
   for(int g = 0; g < group_count; g++)
   {
      string pairs_in_group[];
      StringSplit(groups[g], ',', pairs_in_group);
      
      // Check if current symbol is in this group
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
      
      // If symbol is in group, count positions in the group
      if(symbol_in_group)
      {
         int positions_in_group = 0;
         for(int i = 0; i < PositionsTotal(); i++)
         {
            if(!position.SelectByIndex(i)) continue;
            if(position.Magic() != InpMagicNumber) continue;
            
            for(int p = 0; p < ArraySize(pairs_in_group); p++)
            {
               if(pairs_in_group[p] == position.Symbol())
               {
                  positions_in_group++;
                  break;
               }
            }
         }
         
         if(positions_in_group >= InpMaxCorrelatedPositions)
         {
            PrintFormat("[CORRELATION] Max positions reached in group: %d/%d", 
                        positions_in_group, InpMaxCorrelatedPositions);
            return false;
         }
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check Market Activity (Low Volume / Holiday Protection)           |
//+------------------------------------------------------------------+
bool IsMarketActive()
{
   if(!InpUseActivityFilter) return true;
   
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)InpSignalTF;
   double volume_avg = 0.0;
   
   // Calculate average volume over the specified period
   for(int i = 1; i <= InpActivityVolumePeriod; i++)
      volume_avg += (double)iVolume(_Symbol, tf, i);
   volume_avg /= InpActivityVolumePeriod;
   
   if(volume_avg <= 0.0) return true;  // Avoid division by zero
   
   // Calculate activity ratio (current volume vs average)
   double activity_ratio = (double)iVolume(_Symbol, tf, 1) / volume_avg;
   
   // Check if activity meets minimum threshold
   bool is_active = activity_ratio >= (1.0 / InpMinActivityMultiple);
   
   if(!is_active && InpAvoidLowActivity)
   {
      PrintFormat("[ACTIVITY] Low market activity blocked: Ratio: %.2f, Required: %.2f", 
                  activity_ratio, 1.0/InpMinActivityMultiple);
   }
   
   return InpAvoidLowActivity ? is_active : true;
}

//+------------------------------------------------------------------+
//| Check ADX Trend Strength (Avoid weak breakouts)                    |
//+------------------------------------------------------------------+
bool IsTrendStrong()
{
   if(InpAdxTrendMode == ADX_Trend_Off) return true;
   if(gADXHandle == INVALID_HANDLE) return true;
   
   double adx_buffer[];
   ArraySetAsSeries(adx_buffer, true);
   
   if(CopyBuffer(gADXHandle, 0, 0, 2, adx_buffer) < 2)
   {
      Print("[ADX] Error reading ADX buffer");
      return true;  // Allow trade on error
   }
   
   double adx_value = adx_buffer[0];
   
   bool is_strong = (adx_value >= InpAdxTrendThreshold);
   
   if(!is_strong)
   {
      PrintFormat("[ADX] Weak trend blocked: ADX=%.2f, Threshold=%.2f", 
                  adx_value, InpAdxTrendThreshold);
   }
   
   return is_strong;
}

//+------------------------------------------------------------------+
//| Check RSI Confirmation (Confirm momentum matches breakout)        |
//+------------------------------------------------------------------+
bool IsRsiConfirmed(bool isBuy)
{
   if(InpRsiConfirmMode == RSI_Confirm_Off) return true;
   if(gRSIHandle == INVALID_HANDLE) return true;
   
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   
   if(CopyBuffer(gRSIHandle, 0, 0, 2, rsi_buffer) < 2)
   {
      Print("[RSI] Error reading RSI buffer");
      return true;  // Allow trade on error
   }
   
   double rsi_value = rsi_buffer[0];
   bool confirmed = false;
   
   // Confirm_50_Level mode:
   // - For BUY: RSI should be >= confirmation level (50 = bullish momentum)
   // - For SELL: RSI should be <= (100 - confirmation level) (50 = bearish momentum)
   if(isBuy)
   {
      confirmed = (rsi_value >= InpRsiConfirmLevel);
   }
   else
   {
      confirmed = (rsi_value <= (100.0 - InpRsiConfirmLevel));
   }
   
   if(!confirmed)
   {
      PrintFormat("[RSI] Momentum not confirmed: RSI=%.2f, Required %s %.2f", 
                  rsi_value, isBuy ? ">=" : "<=", 
                  isBuy ? InpRsiConfirmLevel : (100.0 - InpRsiConfirmLevel));
   }
   
   return confirmed;
}

//+------------------------------------------------------------------+
//| Check Spread (Protection against high spread)                     |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return true;  // Filter disabled
   
   int current_spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(current_spread > InpMaxSpreadPoints)
   {
      PrintFormat("[SPREAD] Spread too high: %d points, Max allowed: %.0f", 
                  current_spread, InpMaxSpreadPoints);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check Consistency Rules (Max Lot Size, Max Profit)                |
//+------------------------------------------------------------------+
bool CheckConsistencyRules(double planned_lot_size, double sl_points)
{
   if(!InpUseConsistencyRules) return true;
   
   // Max Lot Size Per Trade
   if(InpUseLotSizeLimit && InpMaxLotSizePerTrade > 0)
   {
      if(planned_lot_size > InpMaxLotSizePerTrade)
      {
         PrintFormat("[CONSISTENCY] Lot size %.2f exceeds max %.2f", 
                     planned_lot_size, InpMaxLotSizePerTrade);
         return false;
      }
   }
   
   // Max Profit Per Trade check
   if(InpMaxProfitPerTrade > 0 && sl_points > 0)
   {
      double potential_profit = planned_lot_size * sl_points * gPointValue * InpRiskRewardRatio;
      double max_allowed = AccountInfoDouble(ACCOUNT_BALANCE) * (InpMaxProfitPerTrade / 100.0);
      
      if(potential_profit > max_allowed)
      {
         PrintFormat("[CONSISTENCY] Potential profit $%.2f exceeds max %.1f%% ($%.2f)", 
                     potential_profit, InpMaxProfitPerTrade, max_allowed);
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| DAILY METRICS                                                     |
//+------------------------------------------------------------------+
void UpdateDailyMetrics()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.day != gLastDay)
   {
      gLastDay = dt.day;
      gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      gIsEaStopped = false;
      gResetTime = 0;
      gCrossedUp = false;
      gCrossedDown = false;
   }
}

void CalculateDailyPerformance(double &daily_pl, double &daily_pl_pct, double &daily_dd, double &daily_dd_pct)
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   daily_pl = current_equity - gDailyStartBalance;
   
   if(daily_pl >= 0)
   {
      daily_dd = 0;
      daily_dd_pct = 0;
      daily_pl_pct = (gDailyStartBalance > 0) ? (daily_pl / gDailyStartBalance) * 100 : 0;
   }
   else
   {
      daily_dd = -daily_pl;
      daily_dd_pct = (gDailyStartBalance > 0) ? (daily_dd / gDailyStartBalance) * 100 : 0;
      daily_pl = 0;
      daily_pl_pct = 0;
   }
}

datetime GetNextDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.day++;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| EXIT MANAGEMENT - Time-Based Close                                 |
//+------------------------------------------------------------------+
void CheckTimeBasedClose()
{
   if(InpTimeBasedClose == TimeClose_Off) return;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Check if current hour matches the close hour
   if(dt.hour == (int)InpTimeBasedClose)
   {
      static bool close_executed_today = false;
      static int last_close_day = -1;
      
      // Reset flag on new day
      if(dt.day != last_close_day)
      {
         close_executed_today = false;
         last_close_day = dt.day;
      }
      
      // Close all positions once per day at the specified hour
      if(!close_executed_today)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!position.SelectByIndex(i)) continue;
            if(position.Symbol() != _Symbol) continue;
            if(position.Magic() != InpMagicNumber) continue;
            
            trade.PositionClose(position.Ticket());
            PrintFormat("[TIME-BASED CLOSE] Position #%d closed at %02d:00 server time", 
                        position.Ticket(), (int)InpTimeBasedClose);
         }
         close_executed_today = true;
         gLastPositionCloseTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| EXIT MANAGEMENT - Breakeven                                       |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   double trigger = InpBreakevenTriggerPoints * gPointValue;
   double offset = InpBreakevenOffsetPoints * gPointValue;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(position.Magic() != InpMagicNumber) continue;
      
      double openPrice = position.PriceOpen();
      double currentSL = position.StopLoss();
      double currentPrice = (position.PositionType() == POSITION_TYPE_BUY) ? 
                            symbolInfo.Bid() : symbolInfo.Ask();
      
      if(position.PositionType() == POSITION_TYPE_BUY)
      {
         if(currentPrice >= openPrice + trigger)
         {
            double newSL = openPrice + offset;
            if(newSL > currentSL || currentSL == 0)
            {
               trade.PositionModify(position.Ticket(), NormalizeDouble(newSL, gDigits), position.TakeProfit());
            }
         }
      }
      else // SELL
      {
         if(currentPrice <= openPrice - trigger)
         {
            double newSL = openPrice - offset;
            if(newSL < currentSL || currentSL == 0)
            {
               trade.PositionModify(position.Ticket(), NormalizeDouble(newSL, gDigits), position.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXIT MANAGEMENT - Trailing Stop                                   |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double trailStart, trailStep;
   
   if(InpExitStrategyMode == Trailing_Stop_ATR && gATRHandle != INVALID_HANDLE)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      if(CopyBuffer(gATRHandle, 0, 0, 1, atr_buffer) > 0)
      {
         trailStart = atr_buffer[0] * InpAtrTrailingMultiplier;
         trailStep = trailStart * 0.5;
      }
      else
      {
         trailStart = InpTrailingStartPoints * gPointValue;
         trailStep = InpTrailingStepPoints * gPointValue;
      }
   }
   else
   {
      trailStart = InpTrailingStartPoints * gPointValue;
      trailStep = InpTrailingStepPoints * gPointValue;
   }
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol) continue;
      if(position.Magic() != InpMagicNumber) continue;
      
      double openPrice = position.PriceOpen();
      double currentSL = position.StopLoss();
      
      if(position.PositionType() == POSITION_TYPE_BUY)
      {
         double currentPrice = symbolInfo.Bid();
         if(currentPrice >= openPrice + trailStart)
         {
            double newSL = currentPrice - trailStart;
            newSL = NormalizeDouble(newSL, gDigits);
            
            if(newSL > currentSL + trailStep || currentSL == 0)
            {
               trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
            }
         }
      }
      else // SELL
      {
         double currentPrice = symbolInfo.Ask();
         if(currentPrice <= openPrice - trailStart)
         {
            double newSL = currentPrice + trailStart;
            newSL = NormalizeDouble(newSL, gDigits);
            
            if(newSL < currentSL - trailStep || currentSL == 0)
            {
               trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| WEEKEND MANAGEMENT                                                |
//+------------------------------------------------------------------+
void WeekendManagement()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.day_of_week != 5) return; // Solo viernes
   
   //--- Cerrar posiciones el viernes
   if(InpCloseOnFriday && dt.hour >= InpFridayCloseHour)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         {
            trade.PositionClose(position.Ticket());
            Print("Posición cerrada por fin de semana");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OPEN TRADE                                                        |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   //--- Weekend block
   if(InpBlockLateFriday)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= InpFridayBlockHour)
      {
         Print("Trade bloqueado: Viernes tarde");
         return;
      }
   }
   
   //--- Check Spread
   if(!IsSpreadOK())
   {
      Print("Trade blocked by Spread Filter");
      return;
   }
   
   //--- Calcular SL y TP
   double sl_points = DetermineSLPoints();
   double tp_points = CalculateTPPoints(sl_points);
   
   //--- Calcular lote
   double lotSize = CalcLotsByRisk(sl_points);
   if(lotSize <= 0)
   {
      Print("Lote inválido");
      return;
   }
   
   //--- Check Consistency Rules (Prop Firm)
   if(!CheckConsistencyRules(lotSize, sl_points))
   {
      Print("Trade blocked by Consistency Rules");
      return;
   }
   
   //--- Check Correlation Filter
   if(!IsCorrelationOK())
   {
      Print("Trade blocked by Correlation Filter");
      return;
   }
   
   //--- Check News Filter
   if(IsNewsBlockingTrades())
   {
      Print("Trade blocked by News Filter");
      return;
   }
   
   //--- Check Market Activity
   if(!IsMarketActive())
   {
      Print("Trade blocked by Low Market Activity");
      return;
   }
   
   //--- Check ADX Trend Strength
   if(!IsTrendStrong())
   {
      Print("Trade blocked by ADX Trend Filter");
      return;
   }
   
   //--- Check RSI Confirmation
   bool isBuyOrder = (orderType == ORDER_TYPE_BUY);
   if(!IsRsiConfirmed(isBuyOrder))
   {
      Print("Trade blocked by RSI Confirm Filter");
      return;
   }
   
   //--- Preparar precios
   double price = (orderType == ORDER_TYPE_BUY) ? symbolInfo.Ask() : symbolInfo.Bid();
   double sl = 0, tp = 0;
   
   if(sl_points > 0)
   {
      double slDistance = sl_points * gPointValue;
      sl = (orderType == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;
      sl = NormalizeDouble(sl, gDigits);
   }
   
   if(tp_points > 0)
   {
      double tpDistance = tp_points * gPointValue;
      tp = (orderType == ORDER_TYPE_BUY) ? price + tpDistance : price - tpDistance;
      tp = NormalizeDouble(tp, gDigits);
   }
   
   //--- Ejecutar orden
   string comment = InpTradeComment;
   bool result = false;
   
   if(orderType == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, price, sl, tp, comment);
   else
      result = trade.Sell(lotSize, _Symbol, price, sl, tp, comment);
   
   if(result)
   {
      gLastTradeTime = TimeCurrent();
      PrintFormat("TRADE: %s | Price:%.2f | SL:%.2f | TP:%.2f | Lot:%.2f",
                  (orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
                  price, sl, tp, lotSize);
   }
   else
   {
      Print("Error al abrir trade: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                 |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == InpMagicNumber)
         count++;
   }
   return count;
}

bool HasPositionType(ENUM_POSITION_TYPE type)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && 
         position.Magic() == InpMagicNumber && position.PositionType() == type)
         return true;
   }
   return false;
}

bool CheckMinBarsElapsed()
{
   if(gLastTradeTime == 0) return true;
   
   // Check cooldown after position close (in minutes)
   if(InpCooldownMinutesAfterClose > 0 && gLastPositionCloseTime > 0)
   {
      long minutes_elapsed = (TimeCurrent() - gLastPositionCloseTime) / 60;
      if(minutes_elapsed < InpCooldownMinutesAfterClose)
         return false;
   }
   
   int bars_to_wait = gLastCloseWasLoss ? InpMinBarsAfterLoss : InpMinBarsAfterAnyTrade;
   long bars_elapsed = (TimeCurrent() - gLastTradeTime) / PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF);
   
   return (bars_elapsed >= bars_to_wait);
}

bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0) return true;
   
   double spread = (symbolInfo.Ask() - symbolInfo.Bid()) / gPointValue;
   return (spread <= InpMaxSpreadPoints);
}

double NormalizeLotSize(double desired)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(minLot <= 0) minLot = desired;
   
   double lot = MathMax(desired, minLot);
   if(step > 0)
   {
      double steps = MathFloor((lot - minLot) / step + 0.5);
      lot = minLot + steps * step;
   }
   
   if(maxLot > 0 && lot > maxLot) lot = maxLot;
   
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| VISUAL - Draw Levels                                              |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| VISUAL - Draw Levels                                              |
//+------------------------------------------------------------------+
void DrawLevels()
{
   string prefix = "RB_";
   
   //--- Coordenadas
   datetime startTime = gRangeStartTime;
   datetime endTime = gRangeEndTime;
   // Ajustamos el visual para que cubra visualmente hasta el final de la barra
   datetime endDisplay = endTime + PeriodSeconds((ENUM_TIMEFRAMES)InpSignalTF); 
   
   //--- TEXTOS DE HORA (Start & End)
   string lblStartTop = prefix + "Lbl_Start_Top";
   string lblEndTop = prefix + "Lbl_End_Top";
   string lblStartBot = prefix + "Lbl_Start_Bot";
   string lblEndBot = prefix + "Lbl_End_Bot";
   
   string startStr = TimeToString(startTime, TIME_MINUTES);
   string endStr = TimeToString(endDisplay, TIME_MINUTES); // O endTime
   
   // Helper para crear texto
   DrawTextLabel(lblStartTop, startTime, gResistanceLevel, startStr + " ", InpResistanceColor, ANCHOR_RIGHT_LOWER);
   DrawTextLabel(lblEndTop, endDisplay, gResistanceLevel, " " + endStr, InpResistanceColor, ANCHOR_LEFT_LOWER);
   
   DrawTextLabel(lblStartBot, startTime, gSupportLevel, startStr + " ", InpSupportColor, ANCHOR_RIGHT_UPPER);
   DrawTextLabel(lblEndBot, endDisplay, gSupportLevel, " " + endStr, InpSupportColor, ANCHOR_LEFT_UPPER);
   
   //--- Línea de Resistencia (Trendline)
   string resName = prefix + "Resistance";
   if(ObjectFind(0, resName) < 0)
      ObjectCreate(0, resName, OBJ_TREND, 0, startTime, gResistanceLevel, endDisplay, gResistanceLevel);
   else
   {
      ObjectSetInteger(0, resName, OBJPROP_TIME, 0, startTime);
      ObjectSetDouble(0, resName, OBJPROP_PRICE, 0, gResistanceLevel);
      ObjectSetInteger(0, resName, OBJPROP_TIME, 1, endDisplay);
      ObjectSetDouble(0, resName, OBJPROP_PRICE, 1, gResistanceLevel);
   }
   
   ObjectSetInteger(0, resName, OBJPROP_COLOR, InpResistanceColor);
   ObjectSetInteger(0, resName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, resName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, resName, OBJPROP_RAY_RIGHT, false); // Importante: Sin rayo infinito
   
   //--- Línea de Soporte (Trendline)
   string supName = prefix + "Support";
   if(ObjectFind(0, supName) < 0)
      ObjectCreate(0, supName, OBJ_TREND, 0, startTime, gSupportLevel, endDisplay, gSupportLevel);
   else
   {
      ObjectSetInteger(0, supName, OBJPROP_TIME, 0, startTime);
      ObjectSetDouble(0, supName, OBJPROP_PRICE, 0, gSupportLevel);
      ObjectSetInteger(0, supName, OBJPROP_TIME, 1, endDisplay);
      ObjectSetDouble(0, supName, OBJPROP_PRICE, 1, gSupportLevel);
   }
   
   ObjectSetInteger(0, supName, OBJPROP_COLOR, InpSupportColor);
   ObjectSetInteger(0, supName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, supName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, supName, OBJPROP_RAY_RIGHT, false); // Importante: Sin rayo infinito
   
   //--- Líneas verticales del rango (Opcional, las podemos dejar o quitar si ensucian)
   // Las dejamos pero punteadas finas
   string startName = prefix + "RangeStart";
   if(ObjectFind(0, startName) < 0)
      ObjectCreate(0, startName, OBJ_VLINE, 0, startTime, 0);
   else
      ObjectSetInteger(0, startName, OBJPROP_TIME, startTime);
   
   ObjectSetInteger(0, startName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, startName, OBJPROP_STYLE, STYLE_DOT);
   
   string endName = prefix + "RangeEnd";
   if(ObjectFind(0, endName) < 0)
      ObjectCreate(0, endName, OBJ_VLINE, 0, endDisplay, 0);
   else
      ObjectSetInteger(0, endName, OBJPROP_TIME, endDisplay);
   
   ObjectSetInteger(0, endName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, endName, OBJPROP_STYLE, STYLE_DOT);
}

void DrawTextLabel(string name, datetime time, double price, string text, color clr, ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price);
   else
   {
       ObjectSetInteger(0, name, OBJPROP_TIME, time);
       ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   }
   
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| VISUAL - Panel                                                    |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   string prefix = "RB_Panel_";
   int x = 10, y = 30;
   
   ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, 220);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, 180);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, C'30,30,40');
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void UpdateInfoPanel()
{
   string prefix = "RB_Panel_";
   int x = 15, y = 35;
   int lineHeight = 18;
   int line = 0;
   
   //--- Título
   CreateLabel(prefix + "Title", x, y + lineHeight * line++, "Ultimate Range Breaker v3.0", clrDodgerBlue, 10);
   CreateLabel(prefix + "Sep1", x, y + lineHeight * line++, "─────────────────────", clrGray, 8);
   
   //--- Estado
   string status = gIsEaStopped ? "STOPPED" : (IsInTradingWindow() ? "ACTIVE" : "WAITING");
   color statusColor = gIsEaStopped ? clrRed : (IsInTradingWindow() ? clrLime : clrYellow);
   CreateLabel(prefix + "Status", x, y + lineHeight * line++, "Estado: " + status, statusColor, 9);
   
   //--- Rango
   CreateLabel(prefix + "Range", x, y + lineHeight * line++, 
               StringFormat("Rango: %02d:%02d-%02d:%02d", InpRangeStartHour, InpRangeStartMin, InpRangeEndHour, InpRangeEndMin), 
               clrWhite, 9);
   
   //--- Niveles
   CreateLabel(prefix + "Resistance", x, y + lineHeight * line++, 
               StringFormat("Resistencia: %.2f", gResistanceLevel), InpResistanceColor, 9);
   CreateLabel(prefix + "Support", x, y + lineHeight * line++, 
               StringFormat("Soporte: %.2f", gSupportLevel), InpSupportColor, 9);
   CreateLabel(prefix + "Size", x, y + lineHeight * line++, 
               StringFormat("Tamaño: %.0f pts", gRangeSize), clrWhite, 9);
   
   //--- Daily DD
   double daily_pl, daily_pl_pct, daily_dd, daily_dd_pct;
   CalculateDailyPerformance(daily_pl, daily_pl_pct, daily_dd, daily_dd_pct);
   
   color ddColor = (daily_dd_pct > InpDailyLossValue * 0.8) ? clrRed : clrWhite;
   CreateLabel(prefix + "DailyDD", x, y + lineHeight * line++, 
               StringFormat("Daily DD: %.2f%%", daily_dd_pct), ddColor, 9);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

//+------------------------------------------------------------------+
//| NEWS FILTER - Load News Data                                       |
//+------------------------------------------------------------------+
void LoadNews()
{
   ArrayResize(g_all_news, 0);
   
   if(MQLInfoInteger(MQL_TESTER))
   {
      // TESTER MODE: Use embedded news data
      LoadEmbeddedNews();
   }
   else
   {
      // LIVE MODE: Use MqlCalendar API
      MqlCalendarValue values[];
      if(CalendarValueHistory(values, 
         (datetime)(TimeCurrent() - (long)(4 * 24 * 3600)), 
         (datetime)(TimeCurrent() + (long)(InpDaysLookahead * 24 * 3600))))
      {
         for(int i = 0; i < ArraySize(values); i++)
         {
            MqlCalendarEvent event_info;
            MqlCalendarCountry country_info;
            if(!CalendarEventById(values[i].event_id, event_info) || 
               !CalendarCountryById(event_info.country_id, country_info)) continue;
            
            NewsEvent_EA evt;
            evt.time = (datetime)values[i].time;
            evt.currency = country_info.currency;
            evt.name = event_info.name;
            evt.importance = event_info.importance;
            
            // Validation: reject suspicious data
            if(evt.currency == "" || evt.name == "" || 
               evt.time <= 0 || evt.importance < 1 || evt.importance > 3)
               continue;
            
            int size = ArraySize(g_all_news);
            ArrayResize(g_all_news, size + 1);
            g_all_news[size] = evt;
         }
      }
   }
   
   // Sort news chronologically
   for(int i = 0; i < ArraySize(g_all_news) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(g_all_news); j++)
      {
         if(g_all_news[i].time > g_all_news[j].time)
         {
            NewsEvent_EA temp = g_all_news[i];
            g_all_news[i] = g_all_news[j];
            g_all_news[j] = temp;
         }
      }
   }
   
   g_lastNewsLoad = TimeCurrent();
   PrintFormat("[NEWS] Loaded %d events", ArraySize(g_all_news));
}

//+------------------------------------------------------------------+
//| NEWS FILTER - Load Embedded News for Tester                        |
//+------------------------------------------------------------------+
void LoadEmbeddedNews()
{
   int server_offset = 0;
   if(InpNewsTimesAreUTC && InpManualUtcOffset != 0)
      server_offset = InpManualUtcOffset;
   
   // Use the g_embedded_news_data array defined at the end of the file
   for(int i = 0; i < ArraySize(g_embedded_news_data); i++)
   {
      string parts[];
      if(StringSplit(g_embedded_news_data[i], '|', parts) < 4) continue;
      
      NewsEvent_EA evt;
      evt.time = StringToTime(parts[0]);
      if(evt.time == 0) continue;
      
      if(InpNewsTimesAreUTC)
         evt.time = (datetime)(evt.time + server_offset * 3600);
      
      evt.currency = parts[1];
      
      string impact_str = parts[2];
      StringToUpper(impact_str);
      if(impact_str == "H") evt.importance = 3;
      else if(impact_str == "M") evt.importance = 2;
      else evt.importance = 1;
      
      evt.name = parts[3];
      
      int size = ArraySize(g_all_news);
      ArrayResize(g_all_news, size + 1);
      g_all_news[size] = evt;
   }
}

//+------------------------------------------------------------------+
//| NEWS FILTER - Check if inside news window                          |
//+------------------------------------------------------------------+
bool IsInsideNewsWindow()
{
   if(InpNewsFilterMode == News_Filter_Off) return false;
   if(ArraySize(g_all_news) == 0) return false;
   
   long window_sec = (long)InpNewsWindowMin * 60;
   datetime now = TimeCurrent();
   
   // For indices like US30/US100, check USD news
   string base_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   string quote_curr = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   
   // If symbol is an index, default to USD
   if(StringFind(_Symbol, "US30") >= 0 || StringFind(_Symbol, "US100") >= 0 || 
      StringFind(_Symbol, "US500") >= 0 || StringFind(_Symbol, "NAS") >= 0 ||
      StringFind(_Symbol, "DOW") >= 0 || StringFind(_Symbol, "SPX") >= 0)
   {
      base_curr = "USD";
      quote_curr = "USD";
   }
   
   for(int i = 0; i < ArraySize(g_all_news); i++)
   {
      // Check if event matches impact filter
      bool is_relevant = false;
      switch(InpNewsImpactToManage)
      {
         case Manage_High_Impact:   if(g_all_news[i].importance == 3) is_relevant = true; break;
         case Manage_Medium_Impact: if(g_all_news[i].importance == 2) is_relevant = true; break;
         case Manage_Both:          if(g_all_news[i].importance >= 2) is_relevant = true; break;
      }
      
      // Check if event currency matches symbol
      if(!is_relevant) continue;
      if(g_all_news[i].currency != "" && 
         g_all_news[i].currency != base_curr && 
         g_all_news[i].currency != quote_curr) continue;
      
      // Check if we're inside the news window
      if(now >= (datetime)(g_all_news[i].time - window_sec) && 
         now < (datetime)(g_all_news[i].time + window_sec))
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| NEWS FILTER - Should block new trades                              |
//+------------------------------------------------------------------+
bool IsNewsBlockingTrades()
{
   if(InpNewsFilterMode == News_Filter_Off) return false;
   if(InpNewsFilterMode == Manage_Open_Trades_Only) return false;
   
   // Block_New_Trades_Only or Block_And_Manage
   return IsInsideNewsWindow();
}

//=====================================================================
// =================== NEWS DATABASE (TESTER ONLY) ====================
// Add your news events here for backtesting. Format: "YYYY.MM.DD HH:MM|CURRENCY|IMPACT|EVENT_NAME"
// IMPACT: H = High, M = Medium, L = Low
// This array is at the end of the file for easy access when adding events.
//=====================================================================
string g_embedded_news_data[] =
{
   "2025.01.10 13:30|USD|H|Employment Report",
   "2025.01.15 13:30|USD|H|Core CPI",
   "2025.01.29 19:00|USD|H|FOMC Statement",
   "2025.02.07 13:30|USD|H|Employment Report",
   "2025.02.12 13:30|USD|H|Core CPI",
   "2025.02.19 19:00|USD|H|FOMC Minutes",
   "2025.03.07 13:30|USD|H|Employment Report",
   "2025.03.12 12:30|USD|H|Core CPI",
   "2025.03.19 18:00|USD|H|FOMC Statement",
   "2025.04.04 12:30|USD|H|Employment Report",
   "2025.04.10 12:30|USD|H|Core CPI",
   "2025.05.02 12:30|USD|H|Employment Report",
   "2025.05.07 18:00|USD|H|FOMC Statement",
   "2025.05.13 12:30|USD|H|Core CPI",
   "2025.06.06 12:30|USD|H|Employment Report",
   "2025.06.11 12:30|USD|H|Core CPI",
   "2025.06.18 18:00|USD|H|FOMC Statement"
};
//+------------------------------------------------------------------+
