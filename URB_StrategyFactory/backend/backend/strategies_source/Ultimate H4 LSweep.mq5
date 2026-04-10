//+------------------------------------------------------------------+
//|                                           Ultimate H4 LSweep.mq5  |
//|                                     Liquidity Sweep Strategy v3   |
//|                                              Timeframe: H4        |
//+------------------------------------------------------------------+

#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//=======================================================================
//                              ENUMERACIONES
//=======================================================================

//--- Tipo de gestión de riesgo
//--- Risk Management Type
enum ENUM_RISK_TYPE
{
   RISK_FIXED_LOT=0,     // Fixed Lots
   RISK_PERCENT=1,       // % of Balance
   RISK_FIXED_MONEY=2    // Fixed Amount ($)
};

//--- Direction Filter Mode
enum ENUM_DIRECTION_FILTER
{
   DIR_OFF=0,            // No Filter (Both Directions)
   DIR_EMA_PRICE=1,      // Price vs 200 EMA
   DIR_EMA_SLOPE=2,      // EMA Slope
   DIR_EMA_CROSS=3       // EMA Cross 50/200
};

//--- Trend Strength Filter
enum ENUM_STRENGTH_FILTER
{
   STR_OFF=0,            // No Strength Filter
   STR_ADX_TREND=1,      // ADX > 20 (Trending)
   STR_ADX_STRONG=2      // ADX > 25 (Strong Trend)
};

//--- Pullback Filter (Oscillator Room)
enum ENUM_PULLBACK_FILTER
{
   PULL_OFF=0,           // No Pullback Filter
   PULL_RSI=1,           // RSI
   PULL_STOCH=2,         // Stochastic
   PULL_CCI=3,           // CCI
   PULL_WILLIAMS=4       // Williams %R
};

//--- ZigZag Type
enum ENUM_ZIGZAG_TYPE
{
   ZZ_STANDARD=0,        // Standard MT5 ZigZag
   ZZ_ADAPTIVE_SWING=1   // AdaptiveSwing (No-Repaint)
};

//=======================================================================
//                              INSTANCIAS
//=======================================================================
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;
CSymbolInfo symbolInfo;
CAccountInfo accountInfo;

//=======================================================================
//                              INPUTS
//=======================================================================

//--- IDENTIFICATION
input group "═══════════ IDENTIFICATION ═══════════"
input int    InpMagicNumber   = 202310; // Unique Magic Number

//--- RISK MANAGEMENT
input group "═══════════ RISK MANAGEMENT ═══════════"
input ENUM_RISK_TYPE InpRiskType = RISK_PERCENT;  // Risk Type
input double InpRiskValue        = 1.0;           // Risk Value (Lots, %, or $)
input int    InpStopLossPoints   = 525;           // Fixed Stop Loss (Points)
input double InpRiskReward       = 2.0;           // Reward:Risk Ratio for TP

//--- SWEEP DISTANCE
input group "═══════════ SWEEP DISTANCE ═══════════"
input bool   InpUseATRDistance   = true;   // Use ATR for Distance?
input int    InpATRPeriod        = 14;     // ATR Period
input double InpATRMultiplier    = 0.5;    // ATR Multiplier
input int    InpFixedDistance    = 100;    // Fixed Distance (Points)
input int    InpExpirationCandles = 3;     // Pending Order Expiration (Candles)

//--- DIRECTION FILTER
input group "═══════════ DIRECTION FILTER ═══════════"
input ENUM_DIRECTION_FILTER InpDirectionFilter = DIR_EMA_PRICE; // Direction Filter Mode
input int    InpEMA_Slow         = 200;    // Slow EMA Period
input int    InpEMA_Fast         = 50;     // Fast EMA Period
input int    InpEMA_SlopeBars    = 5;      // Bars for Slope Calculation

//--- STACKING FILTER
input group "═══════════ STACKING FILTER ═══════════"
input bool   InpEnableStackingFilter = true; // Avoid Stacking Trades?
input double InpStackingATR          = 0.5;  // Min Distance in ATR

//--- STRENGTH FILTER
input group "═══════════ STRENGTH FILTER ═══════════"
input ENUM_STRENGTH_FILTER InpStrengthFilter = STR_ADX_TREND; // Strength Filter Mode
input int    InpADXPeriod        = 14;     // ADX Period

//--- PULLBACK FILTER
input group "═══════════ PULLBACK FILTER ═══════════"
input ENUM_PULLBACK_FILTER InpPullbackFilter = PULL_OFF; // Pullback Oscillator
input int    InpRSI_Period       = 14;     // RSI Period
input int    InpStoch_K          = 14;     // Stochastic K
input int    InpStoch_D          = 3;      // Stochastic D
input int    InpStoch_Slow       = 3;      // Stochastic Slowing
input int    InpCCI_Period       = 20;     // CCI Period
input int    InpWilliams_Period  = 14;     // Williams %R Period

//--- MARKET STRUCTURE
input group "═══════════ MARKET STRUCTURE ═══════════"
input ENUM_ZIGZAG_TYPE InpZigZagType = ZZ_ADAPTIVE_SWING; // ZigZag Type
input int    InpZZ_Depth         = 12;     // ZigZag Depth (Standard)
input int    InpZZ_Deviation     = 5;      // ZigZag Deviation (Standard)
input int    InpZZ_Backstep      = 3;      // ZigZag Backstep
input int    InpAdaptiveATR      = 20;     // Adaptive: ATR Period
input double InpAdaptiveK        = 1.5;    // Adaptive: Multiplier K
input int    InpAdaptiveMinBars  = 3;      // Adaptive: Min Bars Between Pivots
input double InpMinSwingATR      = 0.5;    // Filter: Min Swing Size (x ATR)

//--- ADVANCED FILTERS (V3.1)
input group "═══════════ ADVANCED FILTERS (V3.1) ═══════════"
input bool   InpUseStructureFilter     = true;   // 1. Structure Filter (Adaptive Swing)
input bool   InpBlockOppositeDirections = true;  // 2. Anti-Hedging (One Direction Only)
input bool   InpUseDailyTrendFilter    = false;  // 3. D1 Trend Filter (Optional)
input bool   InpUseActivityFilter      = false;  // 4. Volume Activity Filter (Optional)
input int    InpActivityVolumePeriod   = 20;     // Volume Average Period
input double InpMinActivityRatio       = 0.6;    // Min Activity Ratio

//=======================================================================
//                    DATABANK GENERATION (ONTESTER)


//=======================================================================
//                         VARIABLES GLOBALES
//=======================================================================
int handleATR;
int handleEMA_Slow, handleEMA_Fast;
int handleADX;
int handleRSI, handleStoch, handleCCI, handleWilliams;
int handleZigZag;
int handleEMA_D1; // Nuevo para filtro D1

//=======================================================================
//                         INICIALIZACIÓN
//=======================================================================
int OnInit()
{
   //--- Inicializar información del símbolo
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Error: No se pudo obtener información del símbolo");
      return(INIT_FAILED);
   }
   
   //--- Inicializar handles como inválidos
   handleATR = INVALID_HANDLE;
   handleEMA_Slow = INVALID_HANDLE;
   handleEMA_Fast = INVALID_HANDLE;
   handleADX = INVALID_HANDLE;
   handleRSI = INVALID_HANDLE;
   handleStoch = INVALID_HANDLE;
   handleCCI = INVALID_HANDLE;
   handleWilliams = INVALID_HANDLE;
   handleZigZag = INVALID_HANDLE;
   
   //=== CREAR SOLO LOS INDICADORES NECESARIOS ===
   
   //--- ATR siempre necesario (para distancia de sweep)
   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   
   //--- EMAs según filtro de dirección
   if(InpDirectionFilter != DIR_OFF)
   {
      handleEMA_Slow = iMA(_Symbol, _Period, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
      if(InpDirectionFilter == DIR_EMA_CROSS)
         handleEMA_Fast = iMA(_Symbol, _Period, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   }
   
   //--- ADX solo si filtro de fuerza activo
   if(InpStrengthFilter != STR_OFF)
      handleADX = iADX(_Symbol, _Period, InpADXPeriod);
   
   //--- Indicador de pullback según selección
   switch(InpPullbackFilter)
   {
      case PULL_RSI:      handleRSI = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE); break;
      case PULL_STOCH:    handleStoch = iStochastic(_Symbol, _Period, InpStoch_K, InpStoch_D, InpStoch_Slow, MODE_SMA, STO_LOWHIGH); break;
      case PULL_CCI:      handleCCI = iCCI(_Symbol, _Period, InpCCI_Period, PRICE_TYPICAL); break;
      case PULL_WILLIAMS: handleWilliams = iWPR(_Symbol, _Period, InpWilliams_Period); break;
   }
   
   //--- Crear ZigZag según tipo seleccionado (ShowPanel=true para debug en tester)
   if(InpZigZagType == ZZ_STANDARD)
      handleZigZag = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpZZ_Depth, InpZZ_Deviation, InpZZ_Backstep);
   else // ZZ_ADAPTIVE_SWING
      handleZigZag = iCustom(_Symbol, _Period, "AdaptiveSwingDetector", InpAdaptiveATR, InpAdaptiveK, InpAdaptiveMinBars, true);
   
   //--- Validar handles críticos
   if(handleATR == INVALID_HANDLE || handleZigZag == INVALID_HANDLE)
   {
      Print("Error crítico: No se pudieron crear ATR o ZigZag");
      return(INIT_FAILED);
   }
   
   //--- Crear EMA D1 si el filtro está activo
   if(InpUseDailyTrendFilter)
   {
      handleEMA_D1 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
      if(handleEMA_D1 == INVALID_HANDLE)
      {
         Print("Error: No se pudo crear EMA D1 para filtro de tendencia");
         return(INIT_FAILED);
      }
   }
   
   //--- Validar handles de filtros activos
   if(InpDirectionFilter != DIR_OFF && handleEMA_Slow == INVALID_HANDLE)
   {
      Print("Error: No se pudo crear EMA para filtro de dirección");
      return(INIT_FAILED);
   }
   
   //--- Configurar trading
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   
   //--- Filling IOC = valor original que funcionaba
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- Verificar permisos del símbolo
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   string modeDesc = "";
   switch(tradeMode)
   {
      case SYMBOL_TRADE_MODE_DISABLED: modeDesc = "DISABLED (No trading)"; break;
      case SYMBOL_TRADE_MODE_LONGONLY: modeDesc = "LONG ONLY"; break;
      case SYMBOL_TRADE_MODE_SHORTONLY: modeDesc = "SHORT ONLY"; break;
      case SYMBOL_TRADE_MODE_CLOSEONLY: modeDesc = "CLOSE ONLY (Error 10044 causa)"; break;
      case SYMBOL_TRADE_MODE_FULL: modeDesc = "FULL (Trading OK)"; break;
      default: modeDesc = "UNKNOWN"; break;
   }
   
   //--- Mensaje de inicio
   Print("═══════════════════════════════════════════════════════");
   Print("Ultimate H4 LSweep v3.1");
   Print("Magic: ", InpMagicNumber, " | Filling: IOC");
   Print("Símbolo Trade Mode: ", modeDesc);
   Print("ZigZag: ", EnumToString(InpZigZagType));
   Print("═══════════════════════════════════════════════════════");
   
   return(INIT_SUCCEEDED);
}





//=======================================================================
//                         DEINICIALIZACIÓN
//=======================================================================
void OnDeinit(const int reason)
{
   //--- Liberar indicadores
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleCCI != INVALID_HANDLE) IndicatorRelease(handleCCI);
   if(handleWilliams != INVALID_HANDLE) IndicatorRelease(handleWilliams);
   if(handleZigZag != INVALID_HANDLE) IndicatorRelease(handleZigZag);
   if(handleEMA_D1 != INVALID_HANDLE) IndicatorRelease(handleEMA_D1);
   
   // Limpiar Variables Globales
   GlobalVariableDel("URB_StructDir");
   GlobalVariableDel("URB_Active");
   GlobalVariableDel("URB_Hedge");
   GlobalVariableDel("URB_BuyAllowed");
   GlobalVariableDel("URB_SellAllowed");
   
   Comment(""); // Limpiar gráfico
}

//=======================================================================
//                         ONTICK PRINCIPAL
//=======================================================================
void OnTick()
{

   
   //--- Verificar que el indicador ZigZag esté listo
   int barsCalculated = BarsCalculated(handleZigZag);
   if(barsCalculated <= 0)
   {
      static datetime lastWarnTime = 0;
      if(TimeCurrent() - lastWarnTime > 60)
      {
         Print("⏳ Esperando a que ZigZag calcule... BarsCalculated=", barsCalculated);
         lastWarnTime = TimeCurrent();
      }
      return;
   }
   
   //--- Gestión de posiciones existentes (Pyramiding)
   ManagePyramiding();
   
   //--- Gestión de órdenes pendientes (Trailing Entry)
   //--- Si hay orden y la estructura cambió, moverla al nuevo nivel
   if(CountPendingOrders() > 0)
   {
      ManageTrailingEntry();
      return;
   }
   
   //--- Obtener datos de indicadores
   //--- Obtener datos de indicadores (SOLO si el handle es válido)
   double atrVal = GetIndicatorValue(handleATR, 0, 1);
   
   double emaSlowVal = 0, emaFastVal = 0, emaSlopeVal = 0;
   if(handleEMA_Slow != INVALID_HANDLE) {
      emaSlowVal = GetIndicatorValue(handleEMA_Slow, 0, 1);
      emaSlopeVal = GetEMASlope(handleEMA_Slow, InpEMA_SlopeBars);
   }
   if(handleEMA_Fast != INVALID_HANDLE) emaFastVal = GetIndicatorValue(handleEMA_Fast, 0, 1);
   
   double adxVal = (handleADX != INVALID_HANDLE) ? GetIndicatorValue(handleADX, 0, 1) : 0;
   
   double rsiVal = (handleRSI != INVALID_HANDLE) ? GetIndicatorValue(handleRSI, 0, 1) : 0;
   double stochVal = (handleStoch != INVALID_HANDLE) ? GetIndicatorValue(handleStoch, 0, 1) : 0;
   double cciVal = (handleCCI != INVALID_HANDLE) ? GetIndicatorValue(handleCCI, 0, 1) : 0;
   double williamsVal = (handleWilliams != INVALID_HANDLE) ? GetIndicatorValue(handleWilliams, 0, 1) : 0;
   
   double closePrice = iClose(_Symbol, _Period, 1);
   
   //--- Verificar ATR válido (siempre necesario)
   if(atrVal == 0) return;
   
   //=== EVALUACIÓN DE DIRECCIÓN ===
   bool canBuy = false;
   bool canSell = false;
   
   switch(InpDirectionFilter)
   {
      case DIR_OFF:
         canBuy = true;
         canSell = true;
         break;
      case DIR_EMA_PRICE:
         canBuy = (closePrice > emaSlowVal);
         canSell = (closePrice < emaSlowVal);
         break;
      case DIR_EMA_SLOPE:
         canBuy = (emaSlopeVal > 0);  // EMA subiendo
         canSell = (emaSlopeVal < 0); // EMA bajando
         break;
      case DIR_EMA_CROSS:
         canBuy = (emaFastVal > emaSlowVal);
         canSell = (emaFastVal < emaSlowVal);
         break;
   }
   
   //=== EVALUACIÓN DE FUERZA ===
   bool strengthOk = false;
   
   switch(InpStrengthFilter)
   {
      case STR_OFF:
         strengthOk = true;
         break;
      case STR_ADX_TREND:
         strengthOk = (adxVal > 20);
         break;
      case STR_ADX_STRONG:
         strengthOk = (adxVal > 25);
         break;
   }
   
   //=== FILTROS AVANZADOS (V3.1) ===
   
   // 1. Estructura (Adaptive Swing)
   // Si está activo, canBuy/canSell solo son true si la estructura lo permite
   if(InpUseStructureFilter)
   {
      int structDir = GetStructureDirection(); // 1=Buy, -1=Sell, 0=Range
      if(structDir == 1) canSell = false;      // Solo compras
      else if(structDir == -1) canBuy = false; // Solo ventas
      else { canBuy = false; canSell = false; } // Rango/Indefinido -> No operar
   }
   
   // 2. Tendencia D1 (Opcional)
   if(InpUseDailyTrendFilter && handleEMA_D1 != INVALID_HANDLE)
   {
      double emaD1 = GetIndicatorValue(handleEMA_D1, 0, 1);
      if(closePrice < emaD1) canBuy = false;
      if(closePrice > emaD1) canSell = false;
   }
   
   // 3. Actividad / Volumen (Opcional)
   if(InpUseActivityFilter)
   {
      if(!IsMarketActive())
      {
         canBuy = false;
         canSell = false;
      }
   }
   
   //=== EVALUACIÓN DE PULLBACK ===
   bool buyPullbackOk = false;
   bool sellPullbackOk = false;
   
   switch(InpPullbackFilter)
   {
      case PULL_OFF:
         buyPullbackOk = true;
         sellPullbackOk = true;
         break;
      case PULL_RSI:
         buyPullbackOk = (rsiVal < 70);
         sellPullbackOk = (rsiVal > 30);
         break;
      case PULL_STOCH:
         buyPullbackOk = (stochVal < 80);
         sellPullbackOk = (stochVal > 20);
         break;
      case PULL_CCI:
         buyPullbackOk = (cciVal < 100);
         sellPullbackOk = (cciVal > -100);
         break;
      case PULL_WILLIAMS:
         buyPullbackOk = (williamsVal > -20);  // Williams va de -100 a 0
         sellPullbackOk = (williamsVal < -80);
         break;
   }
   
   //=== DIBUJAR LÍNEAS DE ZONA (Visual) ===
   UpdateZoneLines(canBuy, canSell);
   
   //=== CALCULAR PARÁMETROS COMUNES ===
   double sweepDistance = InpUseATRDistance ? (atrVal * InpATRMultiplier) : (InpFixedDistance * _Point);
   double slPoints = InpStopLossPoints * _Point;
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * _Point;
   datetime expiration = TimeCurrent() + (InpExpirationCandles * PeriodSeconds());
   
   //=================================================================
   //                    SEÑAL DE COMPRA (BUY LIMIT)
   //=================================================================
   if(canBuy && strengthOk && buyPullbackOk)
   {
      double lastLow = GetLastZigZagLow();
      
      if(lastLow <= 0)
      {
         // No hay swing LOW disponible
         return;
      }
      
      double swingSize = closePrice - lastLow;
      
      // Validar swing mínimo basado en ATR
      if(closePrice > lastLow && swingSize >= (atrVal * InpMinSwingATR))
      {
         double entryPrice = NormalizeDouble(lastLow - sweepDistance, _Digits);
         double slPrice = NormalizeDouble(entryPrice - slPoints, _Digits);
         double tpPrice = NormalizeDouble(entryPrice + (slPoints * InpRiskReward), _Digits);
         
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         // Validaciones: precio > ask actual Y NO está muy cerca de otro trade
         if(currentAsk > (entryPrice + minDist))
         {
            if(IsTradeTooClose(entryPrice, ORDER_TYPE_BUY_LIMIT, atrVal)) return;

            double lots = CalculateLotSize(slPoints);
            if(lots > 0)
            {
               if(trade.BuyLimit(lots, entryPrice, _Symbol, slPrice, tpPrice, 
                                 ORDER_TIME_SPECIFIED, expiration, "LSweep BUY"))
               {
                  Print("✓ Buy Limit @ ", entryPrice, " | SL: ", slPrice, " | TP: ", tpPrice, " | Lots: ", lots);
               }
               else
               {
                  // Imprimir explicación del fallo
                  Print("❌ BuyLimit falló. Error: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
               }
            }
            return;
         }
      }
      }

   
   //=================================================================
   //                    FILTRO ANTI-HEDGING
   //=================================================================
   if(InpBlockOppositeDirections)
   {
      if(HasOppositeDirectionTrade(1)) canBuy = false;  // Si hay Venta, bloquear Compra
      if(HasOppositeDirectionTrade(-1)) canSell = false; // Si hay Compra, bloquear Venta
   }
   
   //=================================================================
   //                    SEÑAL DE VENTA (SELL LIMIT)
   //=================================================================
   if(canSell && strengthOk && sellPullbackOk)
   {
      double lastHigh = GetLastZigZagHigh();
      double swingSize = lastHigh - closePrice;
      
      // Validar swing mínimo basado en ATR
      if(lastHigh > 0 && closePrice < lastHigh && swingSize >= (atrVal * InpMinSwingATR))
      {
         double entryPrice = NormalizeDouble(lastHigh + sweepDistance, _Digits);
         double slPrice = NormalizeDouble(entryPrice + slPoints, _Digits);
         double tpPrice = NormalizeDouble(entryPrice - (slPoints * InpRiskReward), _Digits);
         
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Validaciones: precio < bid actual Y NO está muy cerca de otro trade
         if(currentBid < (entryPrice - minDist))
         {
            if(IsTradeTooClose(entryPrice, ORDER_TYPE_SELL_LIMIT, atrVal)) return;

            double lots = CalculateLotSize(slPoints);
            if(lots > 0)
            {
               if(trade.SellLimit(lots, entryPrice, _Symbol, slPrice, tpPrice, 
                                  ORDER_TIME_SPECIFIED, expiration, "LSweep SELL"))
               {
                  Print("✓ Sell Limit @ ", entryPrice, " | SL: ", slPrice, " | TP: ", tpPrice, " | Lots: ", lots);
               }
               else
               {
                  // Imprimir explicación del fallo
                  Print("❌ SellLimit falló. Error: ", trade.ResultRetcode(), " Desc: ", trade.ResultRetcodeDescription());
               }
            }
            return;
         }
      }
   }
}

//=======================================================================
//                    FUNCIONES DE CÁLCULO DE LOTES
//=======================================================================
double CalculateLotSize(double slDistance)
{
   double lots = 0;
   
   symbolInfo.Refresh();
   double tickValue = symbolInfo.TickValue();
   double tickSize = symbolInfo.TickSize();
   double minLot = symbolInfo.LotsMin();
   double maxLot = symbolInfo.LotsMax();
   double lotStep = symbolInfo.LotsStep();
   
   if(tickValue == 0 || tickSize == 0) return minLot;
   
   switch(InpRiskType)
   {
      case RISK_FIXED_LOT:
         lots = InpRiskValue;
         break;
         
      case RISK_PERCENT:
         {
            double balance = accountInfo.Balance();
            double riskMoney = balance * (InpRiskValue / 100.0);
            double slTicks = slDistance / tickSize;
            lots = riskMoney / (slTicks * tickValue);
         }
         break;
         
      case RISK_FIXED_MONEY:
         {
            double slTicks = slDistance / tickSize;
            lots = InpRiskValue / (slTicks * tickValue);
         }
         break;
   }
   
   //--- Normalizar lotes
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   
   return NormalizeDouble(lots, 2);
}

//=======================================================================
//                    FUNCIONES DE INDICADORES
//=======================================================================
double GetIndicatorValue(int handle, int buffer, int shift)
{
   double value[];
   if(CopyBuffer(handle, buffer, shift, 1, value) <= 0) return 0;
   return value[0];
}

double GetEMASlope(int handle, int bars)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, 0, 0, bars + 1, values) <= 0) return 0;
   return values[0] - values[bars];
}

//=======================================================================
//                    FUNCIONES DE ZIGZAG
//=======================================================================

// Variable estática para controlar frecuencia de debug
static datetime lastDebugTime = 0;

//=======================================================================
//                    FUNCIONES DE ZIGZAG Y ZONAS VISUALES
//=======================================================================
bool GetZigZagSwing(int bufferIndex, double &price, datetime &time)
{
   double buffer[];
   int barsToCopy = 500;
   
   int barsCalc = BarsCalculated(handleZigZag);
   if(barsCalc < barsToCopy) barsToCopy = barsCalc;
   if(barsToCopy <= 0) return false;
   
   int copied = CopyBuffer(handleZigZag, bufferIndex, 0, barsToCopy, buffer);
   if(copied <= 0) return false;
   
   // Buscar desde la barra MÁS RECIENTE hacia atrás
   for(int i = copied - 1; i >= 0; i--)
   {
      if(buffer[i] != 0 && buffer[i] != EMPTY_VALUE)
      {
         price = buffer[i];
         int shift = copied - 1 - i;
         time = iTime(_Symbol, _Period, shift);
         return true;
      }
   }
   return false;
}

double GetLastZigZagLow()
{
   double price; datetime time;
   if(GetZigZagSwing(2, price, time)) return price;
   return 0;
}

double GetLastZigZagHigh()
{
   double price; datetime time;
   if(GetZigZagSwing(1, price, time)) return price;
   return 0;
}

void UpdateZoneLines(bool showBuy, bool showSell)
{
   string buyObj = "ZoneLine_Buy";
   string sellObj = "ZoneLine_Sell";
   
   //--- ZONA BUY (Verde)
   double lowPrice; datetime lowTime;
   if(showBuy && GetZigZagSwing(2, lowPrice, lowTime))
   {
      if(ObjectFind(0, buyObj) < 0)
      {
         ObjectCreate(0, buyObj, OBJ_TREND, 0, 0, 0, 0, 0);
         ObjectSetInteger(0, buyObj, OBJPROP_COLOR, clrLime);
         ObjectSetInteger(0, buyObj, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, buyObj, OBJPROP_RAY_RIGHT, false); 
      }
      // Modificador 0 = Punto 1, Modificador 1 = Punto 2
      ObjectSetDouble(0, buyObj, OBJPROP_PRICE, 0, lowPrice);
      ObjectSetInteger(0, buyObj, OBJPROP_TIME, 0, lowTime);
      ObjectSetDouble(0, buyObj, OBJPROP_PRICE, 1, lowPrice);
      ObjectSetInteger(0, buyObj, OBJPROP_TIME, 1, TimeCurrent());
   }
   else
   {
      ObjectDelete(0, buyObj);
   }
   
   //--- ZONA SELL (Roja)
   double highPrice; datetime highTime;
   if(showSell && GetZigZagSwing(1, highPrice, highTime))
   {
      if(ObjectFind(0, sellObj) < 0)
      {
         ObjectCreate(0, sellObj, OBJ_TREND, 0, 0, 0, 0, 0);
         ObjectSetInteger(0, sellObj, OBJPROP_COLOR, clrRed);
         ObjectSetInteger(0, sellObj, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, sellObj, OBJPROP_RAY_RIGHT, false);
      }
      // Modificador 0 = Punto 1, Modificador 1 = Punto 2
      ObjectSetDouble(0, sellObj, OBJPROP_PRICE, 0, highPrice);
      ObjectSetInteger(0, sellObj, OBJPROP_TIME, 0, highTime);
      ObjectSetDouble(0, sellObj, OBJPROP_PRICE, 1, highPrice);
      ObjectSetInteger(0, sellObj, OBJPROP_TIME, 1, TimeCurrent());
   }
   else
   {
      ObjectDelete(0, sellObj);
   }
   
   ChartRedraw(0);
   
   //=== DASHBOARD SIMPLE (V3.1) ===
   ShowDashboard(showBuy, showSell);
}

//=======================================================================
//                    NUEVAS FUNCIONES DE FILTROS (V3.1)
//=======================================================================

//--- Obtener dirección de estructura basada en ZigZag Adaptive
// Retorna: 1 (Alcista), -1 (Bajista), 0 (Indefinido)
int GetStructureDirection()
{
   double lastHigh = GetLastZigZagHigh();
   double lastLow = GetLastZigZagLow();
   
   // Necesitamos al menos un High y un Low para empezar
   if(lastHigh == 0 || lastLow == 0) return 0;
   
   double prevHigh = GetPreviousZigZagHigh(lastHigh);
   double prevLow = GetPreviousZigZagLow(lastLow);
   
   // Estructura Alcista: Low actual > Low anterior
   // Estructura Bajista: High actual < High anterior
   
   bool higherLow = (prevLow > 0 && lastLow > prevLow);
   bool lowerHigh = (prevHigh > 0 && lastHigh < prevHigh);
   
   if(higherLow && !lowerHigh) return 1;  // Estructura CLARAMENTE Alcista
   if(lowerHigh && !higherLow) return -1; // Estructura CLARAMENTE Bajista
   
   // Si tenemos LH y HL (triángulo/compresión) o LL y HH (expansión),
   // podemos optar por seguir el último quiebre o mantenernos neutrales.
   // Por seguridad (Sweep strategy), preferimos esperar claridad.
   return 0; 
}
//=======================================================================
//                    DASHBOARD VISUAL (V3.1)
//=======================================================================
void ShowDashboard(bool buyAllowed, bool sellAllowed)
{
   // Publicar estado en Variables Globales para que el Indicador AdaptiveSwingDetector lo lea
   
   // 1. Estructura
   GlobalVariableSet("URB_StructDir", GetStructureDirection());
   
   // 2. Actividad
   GlobalVariableSet("URB_Active", IsMarketActive() ? 1.0 : 0.0);
   
   // 3. Hedge Block
   GlobalVariableSet("URB_Hedge", InpBlockOppositeDirections ? 1.0 : 0.0);
   
   // 4. Señales
   GlobalVariableSet("URB_BuyAllowed", buyAllowed ? 1.0 : 0.0);
   GlobalVariableSet("URB_SellAllowed", sellAllowed ? 1.0 : 0.0);
   
   // Limpiar comentario antiguo si existe
   Comment("");
}

string GetStructureStr()
{
   if(!InpUseStructureFilter) return "OFF";
   int dir = GetStructureDirection();
   if(dir == 1) return "BULLISH (Higher Lows)";
   if(dir == -1) return "BEARISH (Lower Highs)";
   return "NEUTRAL / RANGE";
}

//=======================================================================
//                    CONTAR ÓRDENES PENDIENTES

//--- Obtener el High ANTERIOR al último (para comparar HH/LH)
double GetPreviousZigZagHigh(double currentHigh)
{
   double buffer[];
   int barsToCopy = 1000;
   if(CopyBuffer(handleZigZag, 1, 0, barsToCopy, buffer) <= 0) return 0;
   
   int foundCount = 0;
   for(int i = barsToCopy - 1; i >= 0; i--)
   {
      if(buffer[i] != 0 && buffer[i] != EMPTY_VALUE)
      {
         // El primero que encontramos es el "currentHigh" (o muy reciente)
         // Debemos ignorarlo si es igual al que ya tenemos, o contarlo como el 1ro.
         if(MathAbs(buffer[i] - currentHigh) < _Point) continue; // Es el mismo
         
         // Encontramos uno distinto -> Es el anterior
         return buffer[i];
      }
   }
   return 0;
}

//--- Obtener el Low ANTERIOR al último (para comparar HL/LL)
double GetPreviousZigZagLow(double currentLow)
{
   double buffer[];
   int barsToCopy = 1000;
   if(CopyBuffer(handleZigZag, 2, 0, barsToCopy, buffer) <= 0) return 0;
   
   for(int i = barsToCopy - 1; i >= 0; i--)
   {
      if(buffer[i] != 0 && buffer[i] != EMPTY_VALUE)
      {
         if(MathAbs(buffer[i] - currentLow) < _Point) continue;
         return buffer[i];
      }
   }
   return 0;
}

//--- Verificar si existe trade en dirección opuesta
bool HasOppositeDirectionTrade(int direction) // 1=Buy, -1=Sell
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            // Si quiero COMPRAR (1) y hay una VENTA (SELL) -> True
            if(direction == 1 && positionInfo.PositionType() == POSITION_TYPE_SELL) return true;
            
            // Si quiero VENDER (-1) y hay una COMPRA (BUY) -> True
            if(direction == -1 && positionInfo.PositionType() == POSITION_TYPE_BUY) return true;
         }
      }
   }
   return false;
}

//--- Verificar actividad de mercado (Volumen)
bool IsMarketActive()
{
   if(!InpUseActivityFilter) return true;
   
   long volAvg = 0;
   for(int i = 1; i <= InpActivityVolumePeriod; i++)
      volAvg += iVolume(_Symbol, _Period, i);
      
   volAvg /= InpActivityVolumePeriod;
   
   if(volAvg <= 0) return true;
   
   long currentVol = iVolume(_Symbol, _Period, 0); // Ojo: volumen de vela actual en formación
   // Mejor usar vela cerrada anterior para decisión estable:
   long lastClosedVol = iVolume(_Symbol, _Period, 1);
   
   return (lastClosedVol > (volAvg * InpMinActivityRatio));
}

//=======================================================================
//                    PYRAMIDING - SINCRONIZAR SL/TP
//=======================================================================
void ManagePyramiding()
{
   if(PositionsTotal() < 2) return;

   // Variables para BUY
   double newestBuySL = 0, newestBuyTP = 0;
   ulong newestBuyTicket = 0;
   datetime newestBuyTime = 0;
   
   // Variables para SELL
   double newestSellSL = 0, newestSellTP = 0;
   ulong newestSellTicket = 0;
   datetime newestSellTime = 0;

   // Buscar las operaciones más recientes
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(positionInfo.Time() > newestBuyTime)
               {
                  newestBuyTime = positionInfo.Time();
                  newestBuyTicket = positionInfo.Ticket();
                  newestBuySL = positionInfo.StopLoss();
                  newestBuyTP = positionInfo.TakeProfit();
               }
            }
            else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(positionInfo.Time() > newestSellTime)
               {
                  newestSellTime = positionInfo.Time();
                  newestSellTicket = positionInfo.Ticket();
                  newestSellSL = positionInfo.StopLoss();
                  newestSellTP = positionInfo.TakeProfit();
               }
            }
         }
      }
   }

   // Sincronizar posiciones BUY
   if(newestBuyTicket > 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber 
               && positionInfo.PositionType() == POSITION_TYPE_BUY
               && positionInfo.Ticket() != newestBuyTicket)
            {
               if(MathAbs(positionInfo.StopLoss() - newestBuySL) > _Point || 
                  MathAbs(positionInfo.TakeProfit() - newestBuyTP) > _Point)
               {
                  trade.PositionModify(positionInfo.Ticket(), newestBuySL, newestBuyTP);
                  Print("↔ Sync BUY #", positionInfo.Ticket());
               }
            }
         }
      }
   }

   // Sincronizar posiciones SELL
   if(newestSellTicket > 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber 
               && positionInfo.PositionType() == POSITION_TYPE_SELL
               && positionInfo.Ticket() != newestSellTicket)
            {
               if(MathAbs(positionInfo.StopLoss() - newestSellSL) > _Point || 
                  MathAbs(positionInfo.TakeProfit() - newestSellTP) > _Point)
               {
                  trade.PositionModify(positionInfo.Ticket(), newestSellSL, newestSellTP);
                  Print("↔ Sync SELL #", positionInfo.Ticket());
               }
            }
         }
      }
   }
}

//=======================================================================
//                    FUNCIONES AUXILIARES ZIGZAG
//=======================================================================
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber) 
            count++;
   }
   return count;
}

//=======================================================================
//         TRAILING ENTRY - MOVER ORDEN A NUEVA ESTRUCTURA
//=======================================================================
void ManageTrailingEntry()
{
   //--- Obtener valores actuales para cálculos
   double atrVal = GetIndicatorValue(handleATR, 0, 1);
   if(atrVal == 0) return;
   
   double sweepDistance = InpUseATRDistance ? (atrVal * InpATRMultiplier) : (InpFixedDistance * _Point);
   double slPoints = InpStopLossPoints * _Point;
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * _Point;
   double tolerance = atrVal * 0.1; // Tolerancia: 10% del ATR para evitar modificaciones excesivas
   
   //--- Buscar órdenes pendientes de este EA
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!orderInfo.SelectByIndex(i)) continue;
      if(orderInfo.Symbol() != _Symbol || orderInfo.Magic() != InpMagicNumber) continue;
      
      ENUM_ORDER_TYPE orderType = orderInfo.OrderType();
      ulong ticket = orderInfo.Ticket();
      double currentEntry = orderInfo.PriceOpen();
      
      //=== BUY LIMIT: Verificar si hay nuevo swing LOW ===
      if(orderType == ORDER_TYPE_BUY_LIMIT)
      {
         double lastLow = GetLastZigZagLow();
         if(lastLow <= 0) continue;
         
         double newEntry = NormalizeDouble(lastLow - sweepDistance, _Digits);
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         // Verificar si el nuevo precio es válido y diferente Y no está apilado con OTROS trades
         // (Pasamos ticket actual para ignorarlo en la comparación)
         if(currentAsk > (newEntry + minDist) && MathAbs(newEntry - currentEntry) > tolerance)
         {
             if(IsTradeTooClose(newEntry, ORDER_TYPE_BUY_LIMIT, atrVal, ticket)) continue;
             
             double newSL = NormalizeDouble(newEntry - slPoints, _Digits);
            double newTP = NormalizeDouble(newEntry + (slPoints * InpRiskReward), _Digits);
            
            // Recalcular expiración desde ahora
            datetime newExpiration = TimeCurrent() + (InpExpirationCandles * PeriodSeconds());
            
            // Intentar modificar la orden
            if(trade.OrderModify(ticket, newEntry, newSL, newTP, ORDER_TIME_SPECIFIED, newExpiration))
            {
               Print("↻ Trailing BUY LIMIT: ", currentEntry, " → ", newEntry);
            }
         }
      }
      //=== SELL LIMIT: Verificar si hay nuevo swing HIGH ===
      else if(orderType == ORDER_TYPE_SELL_LIMIT)
      {
         double lastHigh = GetLastZigZagHigh();
         if(lastHigh <= 0) continue;
         
         double newEntry = NormalizeDouble(lastHigh + sweepDistance, _Digits);
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Verificar si el nuevo precio es válido y diferente Y no está apilado
         if(currentBid < (newEntry - minDist) && MathAbs(newEntry - currentEntry) > tolerance)
         {
            if(IsTradeTooClose(newEntry, ORDER_TYPE_SELL_LIMIT, atrVal, ticket)) continue;

            double newSL = NormalizeDouble(newEntry + slPoints, _Digits);
            double newTP = NormalizeDouble(newEntry - (slPoints * InpRiskReward), _Digits);
            
            // Recalcular expiración desde ahora
            datetime newExpiration = TimeCurrent() + (InpExpirationCandles * PeriodSeconds());
            
            // Intentar modificar la orden
            if(trade.OrderModify(ticket, newEntry, newSL, newTP, ORDER_TIME_SPECIFIED, newExpiration))
            {
               Print("↻ Trailing SELL LIMIT: ", currentEntry, " → ", newEntry);
            }
         }
      }
   }
}

//=======================================================================
//                    FILTRO DE APILAMIENTO (STACKING)
//=======================================================================
bool IsTradeTooClose(double price, ENUM_ORDER_TYPE type, double atr, ulong ignoreTicket=0)
{
   if(!InpEnableStackingFilter) return false;
   
   double minDistance = atr * InpStackingATR;
   
   // Verificar Posiciones Abiertas
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == InpMagicNumber)
         {
            // Verificar solo mismo tipo (BUY con BUY LIMIT, SELL con SELL LIMIT)
            bool sameSide = (type == ORDER_TYPE_BUY_LIMIT && positionInfo.PositionType() == POSITION_TYPE_BUY) ||
                            (type == ORDER_TYPE_SELL_LIMIT && positionInfo.PositionType() == POSITION_TYPE_SELL);
            
            if(sameSide)
            {
               if(MathAbs(positionInfo.PriceOpen() - price) < minDistance) return true;
            }
         }
      }
   }
   
   // Verificar Órdenes Pendientes
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(orderInfo.SelectByIndex(i))
      {
         if(orderInfo.Symbol() == _Symbol && orderInfo.Magic() == InpMagicNumber)
         {
            if(orderInfo.Ticket() == ignoreTicket) continue; // Ignorar orden que estamos modificando
            
            if(orderInfo.OrderType() == type)
            {
               if(MathAbs(orderInfo.PriceOpen() - price) < minDistance) return true;
            }
         }
      }
   }
   
   return false;
}
//+------------------------------------------------------------------+


//=======================================================================
//                    ONTESTER (CUSTOM SCORE)
//=======================================================================
double OnTester()
{
   double profit     = TesterStatistics(STAT_PROFIT);
   double sharpe     = TesterStatistics(STAT_SHARPE_RATIO);
   double dd_money   = TesterStatistics(STAT_EQUITY_DD);
   
   // Custom Score: (Profit * Sharpe) / Drawdown
   // Maximizar retorno ajustado por riesgo
   double score = (profit * (sharpe > 0 ? sharpe : 0.1)) / (dd_money > 0 ? dd_money : 1.0);
   return score;
}
