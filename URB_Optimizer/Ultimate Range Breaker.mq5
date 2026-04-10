//+------------------------------------------------------------------+
//|                                       Ultimate Range Breaker.mq5 |
//|                              Estrategia de Breakout Horario      |
//|               Fusión con sistemas de gestión de DualEA           |
//+------------------------------------------------------------------+
#property copyright "SA TRADING TOOLS"
#property version   "3.00"
#property description "EA de breakout basado en rangos horarios"
#property description "Con gestión profesional de riesgo tipo Prop Firm"
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
enum ENUM_ENTRY_TYPE
{
   ENTRY_CROSS = 0,        // Cross - Entrada al cruzar nivel
   ENTRY_BAR_CLOSE = 1     // Cierre de Vela - Espera confirmación
};

enum ENUM_LOT_SIZING_MODE
{
   Fixed_Lot = 0,          // Lote Fijo
   Risk_Percent = 1        // Porcentaje de Riesgo
};

enum ENUM_SL_MODE
{
   SL_Fixed_Points = 0,    // Fijo en Puntos
   SL_ATR_Based = 1,       // Basado en ATR
   SL_Range_Based = 2      // Basado en Tamaño del Rango
};

enum ENUM_EXIT_STRATEGY_MODE
{
   Exit_Strategy_Off = 0,      // Off
   Breakeven_Points = 1,       // Breakeven (Puntos)
   Trailing_Stop_Points = 2,   // Trailing Stop (Puntos)
   Trailing_Stop_ATR = 3       // Trailing Stop (ATR)
};

enum ENUM_LIMIT_MODE
{
   Limit_Off = 0,          // Off
   Limit_Percent = 1,      // Porcentaje
   Limit_Money = 2         // Dinero
};

enum ENUM_NEWS_FILTER_MODE
{
   News_Filter_Off = 0,            // Off
   Block_New_Trades_Only = 1,      // Solo Bloquear Nuevos Trades
   Manage_Open_Trades_Only = 2,    // Solo Gestionar Trades Abiertos
   Block_And_Manage = 3            // Bloquear y Gestionar
};

//+------------------------------------------------------------------+
//| INPUTS - CONFIGURACIÓN GENERAL                                    |
//+------------------------------------------------------------------+
input group "========== CONFIGURACIÓN GENERAL =========="
input long         InpMagicNumber = 100820;              // Magic Number
input string       InpTradeComment = "URB";              // Comentario de Trade
input ENUM_LOT_SIZING_MODE InpLotSizingMode = Risk_Percent; // Modo de Lotaje
input double       InpFixedLot = 0.01;                   // Lote Fijo
input double       InpRiskPerTradePct = 1.0;             // Riesgo por Trade (%)
input int          InpMaxTradesPerSymbol = 1;            // Máx Trades por Símbolo
input int          InpSlippagePoints = 10;               // Slippage Máximo (Puntos)
input double       InpMaxSpreadPoints = 0;               // Spread Máximo (0=off)

//+------------------------------------------------------------------+
//| INPUTS - HORARIO DEL RANGO                                        |
//+------------------------------------------------------------------+
input group "========== HORARIO DEL RANGO =========="
input int          InpRangeStartHour = 12;               // Hora Inicio del Rango
input int          InpRangeStartMin = 15;                // Minuto Inicio del Rango
input int          InpRangeEndHour = 16;                 // Hora Fin del Rango
input int          InpRangeEndMin = 0;                   // Minuto Fin del Rango

//+------------------------------------------------------------------+
//| INPUTS - VENTANA DE TRADING (KILL ZONE)                           |
//+------------------------------------------------------------------+
input group "========== VENTANA DE TRADING (Kill Zone) =========="
input int          InpTradingStartHour = 16;             // Hora Inicio de Trading
input int          InpTradingStartMin = 30;              // Minuto Inicio de Trading
input int          InpTradingEndHour = 17;               // Hora Fin de Trading
input int          InpTradingEndMin = 30;                // Minuto Fin de Trading

//+------------------------------------------------------------------+
//| INPUTS - BREAKOUT                                                  |
//+------------------------------------------------------------------+
input group "========== BREAKOUT =========="
input ENUM_ENTRY_TYPE InpEntryType = ENTRY_CROSS;        // Tipo de Entrada
input double       InpBreakoutBuffer = 2000;             // Buffer de Breakout (Puntos)
input double       InpMinBodyPercent = 50;               // % Mín de Cuerpo (Bar Close)
input int          InpMinBarsAfterLoss = 5;              // Barras Mín Después de Pérdida
input int          InpMinBarsAfterAnyTrade = 2;          // Barras Mín Entre Trades

//+------------------------------------------------------------------+
//| INPUTS - RISK MANAGEMENT (SL & TP)                                 |
//+------------------------------------------------------------------+
input group "========== GESTIÓN DE RIESGO (SL & TP) =========="
input ENUM_SL_MODE InpSlMethod = SL_Fixed_Points;        // Método de Stop Loss
input double       InpFixedSL_In_Points = 5000;          // SL Fijo (Puntos)
input int          InpAtrSlPeriod = 14;                  // Período ATR para SL
input double       InpAtrSlMultiplier = 1.5;             // Multiplicador ATR para SL
input double       InpSLRangeMultiplier = 0.5;           // Multiplicador Rango para SL
input double       InpRiskRewardRatio = 2.0;             // Ratio Riesgo:Beneficio

//+------------------------------------------------------------------+
//| INPUTS - BREAKEVEN & TRAILING STOP                                 |
//+------------------------------------------------------------------+
input group "========== BREAKEVEN & TRAILING STOP =========="
input ENUM_EXIT_STRATEGY_MODE InpExitStrategyMode = Trailing_Stop_Points; // Modo de Salida
input double       InpBreakevenTriggerPoints = 3000;     // Breakeven Trigger (Puntos)
input double       InpBreakevenOffsetPoints = 500;       // Breakeven Offset (Puntos)
input double       InpTrailingStartPoints = 5000;        // Trailing Start (Puntos)
input double       InpTrailingStepPoints = 5000;         // Trailing Step (Puntos)
input int          InpAtrTrailingPeriod = 14;            // Período ATR para Trailing
input double       InpAtrTrailingMultiplier = 1.0;       // Multiplicador ATR Trailing

//+------------------------------------------------------------------+
//| INPUTS - PROP FIRM SETTINGS                                        |
//+------------------------------------------------------------------+
input group "========== CONFIGURACIÓN PROP FIRM =========="
input ENUM_LIMIT_MODE InpDailyLossMode = Limit_Percent;  // Modo Límite Pérdida Diaria
input double       InpDailyLossValue = 4.5;              // Límite Pérdida Diaria (%)
input ENUM_LIMIT_MODE InpTotalLossMode = Limit_Percent;  // Modo Límite Pérdida Total
input double       InpTotalLossValue = 9.5;              // Límite Pérdida Total (%)
input int          InpMaxAccountOpenTrades = 0;          // Máx Trades Abiertos (0=off)
input double       InpMaxAccountOpenLots = 0.0;          // Máx Lotes Abiertos (0=off)

//+------------------------------------------------------------------+
//| INPUTS - WEEKEND & HEDGING                                         |
//+------------------------------------------------------------------+
input group "========== FIN DE SEMANA & HEDGING =========="
input bool         InpUseWeekendManagement = true;       // Gestión de Fin de Semana
input bool         InpCloseOnFriday = true;              // Cerrar Posiciones el Viernes
input int          InpFridayCloseHour = 20;              // Hora de Cierre Viernes
input bool         InpBlockLateFriday = true;            // Bloquear Entradas Viernes Tarde
input int          InpFridayBlockHour = 18;              // Hora de Bloqueo Viernes
input bool         InpBlockOppositeDirections = true;    // Bloquear Direcciones Opuestas

//+------------------------------------------------------------------+
//| INPUTS - NEWS FILTER                                               |
//+------------------------------------------------------------------+
input group "========== FILTRO DE NOTICIAS =========="
input ENUM_NEWS_FILTER_MODE InpNewsFilterMode = News_Filter_Off; // Modo Filtro Noticias
input int          InpNewsWindowMin = 10;                // Minutos Antes/Después Noticia

//+------------------------------------------------------------------+
//| INPUTS - VARIABLE RISK MANAGEMENT                                  |
//+------------------------------------------------------------------+
input group "========== VARIABLE RISK (Challenges) =========="
input bool         InpUseVariableRisk = false;           // Usar Riesgo Variable
input double       InpBaseRiskPercent = 1.0;             // Riesgo Base (%)
input double       InpMaxRiskPercent = 2.5;              // Riesgo Máximo (%)
input double       InpProfitTargetPerLevel = 500.0;      // Objetivo Profit por Nivel ($)
input double       InpRiskIncreasePercent = 0.25;        // Incremento Riesgo por Nivel (%)
input double       InpLossReductionFactor = 0.75;        // Factor Reducción por Pérdida
input int          InpReductionTrades = 2;               // Trades con Riesgo Reducido

//+------------------------------------------------------------------+
//| INPUTS - VISUALIZACIÓN                                             |
//+------------------------------------------------------------------+
input group "========== VISUALIZACIÓN =========="
input bool         InpShowPanel = true;                  // Mostrar Panel
input bool         InpDrawLevels = true;                 // Dibujar Niveles S/R
input color        InpSupportColor = clrDodgerBlue;      // Color Soporte
input color        InpResistanceColor = clrCrimson;      // Color Resistencia

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

//--- Indicator Handles
int          gATRHandle = INVALID_HANDLE;

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
      gATRHandle = iATR(_Symbol, PERIOD_M15, atr_period);
      if(gATRHandle == INVALID_HANDLE)
      {
         Print("Error al crear indicador ATR");
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

   //--- Verificar señales de entrada (solo si estamos en ventana de trading)
   if(IsInTradingWindow() && !gIsEaStopped)
   {
      if(SpreadOK())
         CheckForTradeSignals();
   }
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
   
   int totalBars = iBars(_Symbol, PERIOD_M15);
   for(int i = 0; i < totalBars; i++)
   {
      datetime barTime = iTime(_Symbol, PERIOD_M15, i);
      
      if(barTime >= rangeStartTime && barTime < rangeEndTime)
      {
         double h = iHigh(_Symbol, PERIOD_M15, i);
         double l = iLow(_Symbol, PERIOD_M15, i);
         
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
               TimeToString(gRangeEndTime + PeriodSeconds(PERIOD_M15), TIME_MINUTES),
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
      datetime currentBarTime = iTime(_Symbol, PERIOD_M15, 0);
      
      if(currentBarTime == lastBarTime)
         return;
      
      lastBarTime = currentBarTime;
      
      double prevClose = iClose(_Symbol, PERIOD_M15, 1);
      double prevOpen = iOpen(_Symbol, PERIOD_M15, 1);
      double prevHigh = iHigh(_Symbol, PERIOD_M15, 1);
      double prevLow = iLow(_Symbol, PERIOD_M15, 1);
      
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
            sl_points = gRangeSize * InpSLRangeMultiplier;
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
//| RISK MANAGEMENT - Variable Risk                                   |
//+------------------------------------------------------------------+
double CalculateVariableRisk()
{
   if(!InpUseVariableRisk) 
      return InpRiskPerTradePct;
   
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int current_level = (int)MathFloor((current_balance - gDailyStartBalance) / InpProfitTargetPerLevel);
   current_level = MathMax(0, current_level);
   
   double risk_percent = InpBaseRiskPercent + (current_level * InpRiskIncreasePercent);
   
   if(gReductionTradesRemaining > 0)
      risk_percent *= InpLossReductionFactor;
   
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
   
   //--- Daily Loss Check
   if(InpDailyLossMode != Limit_Off && InpDailyLossValue > 0)
   {
      bool limit_hit = false;
      
      if(InpDailyLossMode == Limit_Percent && daily_dd_pct >= InpDailyLossValue)
         limit_hit = true;
      else if(InpDailyLossMode == Limit_Money && daily_dd >= InpDailyLossValue)
         limit_hit = true;
      
      if(limit_hit)
      {
         Print("=== DAILY LOSS LIMIT HIT ===");
         gIsEaStopped = true;
         gResetTime = GetNextDayStart();
         return false;
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
   
   int bars_to_wait = gLastCloseWasLoss ? InpMinBarsAfterLoss : InpMinBarsAfterAnyTrade;
   long bars_elapsed = (TimeCurrent() - gLastTradeTime) / PeriodSeconds(PERIOD_M15);
   
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
void DrawLevels()
{
   string prefix = "RB_";
   
   //--- Línea de Resistencia
   string resName = prefix + "Resistance";
   if(ObjectFind(0, resName) < 0)
      ObjectCreate(0, resName, OBJ_HLINE, 0, 0, gResistanceLevel);
   else
      ObjectSetDouble(0, resName, OBJPROP_PRICE, gResistanceLevel);
   
   ObjectSetInteger(0, resName, OBJPROP_COLOR, InpResistanceColor);
   ObjectSetInteger(0, resName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, resName, OBJPROP_WIDTH, 2);
   
   //--- Línea de Soporte
   string supName = prefix + "Support";
   if(ObjectFind(0, supName) < 0)
      ObjectCreate(0, supName, OBJ_HLINE, 0, 0, gSupportLevel);
   else
      ObjectSetDouble(0, supName, OBJPROP_PRICE, gSupportLevel);
   
   ObjectSetInteger(0, supName, OBJPROP_COLOR, InpSupportColor);
   ObjectSetInteger(0, supName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, supName, OBJPROP_WIDTH, 2);
   
   //--- Líneas verticales del rango
   string startName = prefix + "RangeStart";
   if(ObjectFind(0, startName) < 0)
      ObjectCreate(0, startName, OBJ_VLINE, 0, gRangeStartTime, 0);
   else
      ObjectSetInteger(0, startName, OBJPROP_TIME, gRangeStartTime);
   
   ObjectSetInteger(0, startName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, startName, OBJPROP_STYLE, STYLE_DOT);
   
   string endName = prefix + "RangeEnd";
   datetime rangeEndDisplay = gRangeEndTime + PeriodSeconds(PERIOD_M15);
   if(ObjectFind(0, endName) < 0)
      ObjectCreate(0, endName, OBJ_VLINE, 0, rangeEndDisplay, 0);
   else
      ObjectSetInteger(0, endName, OBJPROP_TIME, rangeEndDisplay);
   
   ObjectSetInteger(0, endName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, endName, OBJPROP_STYLE, STYLE_DOT);
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
