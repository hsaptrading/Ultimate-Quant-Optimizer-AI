//=======================================================================
//                    ONTESTER (DATABANK GENERATION)
//=======================================================================
double OnTester()
{
   if(!InpUseDatabank) return 0.0;
   
   // Obtener estadísticas del Backtest
   double profit     = TesterStatistics(STAT_PROFIT);
   double equity_dd  = TesterStatistics(STAT_EQUITY_DDREL_PERCENT); // Max DD Relativo %
   double trades     = TesterStatistics(STAT_DEALS);
   double sharpe     = TesterStatistics(STAT_SHARPE_RATIO);
   double pf         = TesterStatistics(STAT_PROFIT_FACTOR);
   double recovery   = TesterStatistics(STAT_RECOVERY_FACTOR);
   double expected   = TesterStatistics(STAT_EXPECTED_PAYOFF);
   
   // Calcular Retorno / MaxDD
   double ret_dd = 0.0;
   double dd_money = TesterStatistics(STAT_EQUITY_DD);
   
   if(dd_money > 0)
      ret_dd = profit / dd_money;
   else if(profit > 0)
      ret_dd = 999.0; // Caso ideal sin DD significativo

   
   // --- FILTROS DE CALIDAD ---
   if(profit <= 0) return -1000.0; // Descartar perdedoras
   if(equity_dd > InpMaxDrawdownPercent) return -5000.0; // Descartar DD alto
   if(trades < InpMinTrades) return -2000.0; // Descartar pocas operaciones
   if(pf < InpMinProfitFactor) return -3000.0; // Descartar PF bajo
   if(ret_dd < InpMinRetDD) return -4000.0; // Descartar bajo retorno/riesgo
   
   // --- GUARDAR EN CSV (DATABANK) ---
   string filename = "OptimizationDatabank_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_CSV|FILE_READ|FILE_WRITE|FILE_ANSI, ';'); // Append mode simulado
   
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      if(FileTell(handle) == 0)
      {
         // Escribir cabecera si es nuevo
         FileWrite(handle, "Profit", "DD%", "Ret/DD", "Trades", "Sharpe", "PF", "Params->", 
                   "SL", "UseATR", "ATR_Mult", "RiskReward", "StructFilter", "AntiHedge", "TrendFilter", "VolFilter");
      }
      
      // Escribir datos
      FileWrite(handle, 
                DoubleToString(profit, 2), 
                DoubleToString(equity_dd, 2), 
                DoubleToString(ret_dd, 2),
                (string)trades, 
                DoubleToString(sharpe, 2), 
                DoubleToString(pf, 2),
                "->",
                (string)InpStopLossPoints,
                (string)InpUseATRDistance,
                DoubleToString(InpATRMultiplier, 1),
                DoubleToString(InpRiskReward, 1),
                (string)InpUseStructureFilter,
                (string)InpBlockOppositeDirections,
                (string)InpUseDailyTrendFilter,
                (string)InpUseActivityFilter
                );
                
      FileClose(handle);
   }
   
   // Retornar métrica personalizada para el optimizador (Maximizar esto)
   // Fórmula: (Profit * Sharpe) / DD
   double score = (profit * (sharpe > 0 ? sharpe : 0.1)) / (dd_money > 0 ? dd_money : 1.0);
   return score;
}
