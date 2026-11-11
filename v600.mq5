//+------------------------------------------------------------------+
//|                                      Reversao_1Candle_Alpha.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1900.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS DO ROBÔ (REVERSÃO + FECHAMENTO POR CANDLE)
//====================================================================
input group      "--- GESTÃO FINANCEIRA ---"
input double     InpLotSize            = 0.02;       // Lote fixo por operação
input double     InpMaxLossUSD         = 30.00;      // Stop Loss máximo de emergência (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)
input bool       InpBloquearFDS        = true;       // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda  = 14;         // Hora de liberação na Segunda (Servidor)
input int        InpHoraFimSexta       = 23;         // Hora de bloqueio na Sexta (Servidor)
input bool       InpZerarNaSexta       = true;       // Fechar tudo na Sexta no horário limite

ulong    magic = 20261114;
datetime barra_viva;
datetime vela_controle_fechamento;
bool     stop_emergencia_acionado = false;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva = 0;
   vela_controle_fechamento = 0;
   stop_emergencia_acionado = false;
   return(INIT_SUCCEEDED); 
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(stop_emergencia_acionado) return;

   datetime hora_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   //====================================================================
   // ETAPA 1: VIRADA DE CANDLE -> ENCERRA A OPERAÇÃO DO CANDLE ANTERIOR
   //====================================================================
   if(vela_controle_fechamento != hora_vela_atual)
     {
      if(vela_controle_fechamento != 0)
        {
         FecharTodasPosicoes();
        }
      vela_controle_fechamento = hora_vela_atual;
     }

   //====================================================================
   // ETAPA 2: AUDITORIA DE STOP LOSS DE EMERGÊNCIA E SEXTA-FEIRA
   //====================================================================
   double lucro_total_ciclo = 0;
   int total_ordens_ativas = 0;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         lucro_total_ciclo += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         total_ordens_ativas++;
        }
     }

   // Fechamento forçado na Sexta-feira à noite
   MqlDateTime tempo;
   TimeCurrent(tempo);
   if(InpZerarNaSexta && tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta && total_ordens_ativas > 0)
     {
      Print("[SEXTA-FEIRA] Horário limite atingido. Zerando posições.");
      FecharTodasPosicoes();
      return;
     }

   // Verifica Stop Loss de Emergência
   if(total_ordens_ativas > 0 && lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
     {
      Print("[STOP LOSS GLOBAL] Prejuízo de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Robô bloqueado!");
      FecharTodasPosicoes();
      stop_emergencia_acionado = true;
      return;
     }

   //====================================================================
   // ETAPA 3: FILTROS DE SEGURANÇA E GATILHO DO CANDLE ATUAL
   //====================================================================
   if(barra_viva != hora_vela_atual)
     {
      if(!HorarioPermitido()) return;
      
      long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread_atual > InpMaxSpread) return;

      double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Bateu ou passou da Máxima Anterior -> VENDE (Reversão)
      if(bid >= maxima_anterior)
        {
         Print("[VENDA REVERSÃO] Preço atingiu máxima anterior (", maxima_anterior, ")");
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Reversao 1Candle Sell"))
            barra_viva = hora_vela_atual;
        }
      // Bateu ou caiu abaixo da Mínima Anterior -> COMPRA (Reversão)
      else if(ask <= minima_anterior)
        {
         Print("[COMPRA REVERSÃO] Preço atingiu mínima anterior (", minima_anterior, ")");
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Reversao 1Candle Buy"))
            barra_viva = hora_vela_atual;
        }
     }
  }

//+------------------------------------------------------------------+
//| Verifica se o dia da semana e horário estão liberados            |
//+------------------------------------------------------------------+
bool HorarioPermitido()
  {
   MqlDateTime tempo;
   TimeCurrent(tempo);
   
   if(InpBloquearFDS && (tempo.day_of_week == 0 || tempo.day_of_week == 6))
      return false;
      
   if(tempo.day_of_week == 1 && tempo.hour < InpHoraInicioSegunda)
      return false;
      
   if(tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta)
      return false;
      
   return true;
  }

//+------------------------------------------------------------------+
//| Fecha todas as posições abertas pelo robô                        |
//+------------------------------------------------------------------+
void FecharTodasPosicoes()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(ticket);
        }
     }
  }
