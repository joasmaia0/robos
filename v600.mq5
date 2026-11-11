//+------------------------------------------------------------------+
//|                                   Reversao_1Candle_Blindado.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "2000.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS DO ROBÔ (M10 + PROTEÇÃO DE TENDÊNCIA)
//====================================================================
input group      "--- GESTÃO FINANCEIRA ---"
input double     InpLotSize            = 0.01;       // Lote fixo por operação
input double     InpMaxLossOrdemUSD    = 2.00;       // Stop Loss máximo por ordem (US$)
input double     InpMaxLossDiarioUSD   = 6.00;       // Stop Loss máximo no DIA (US$)

input group      "--- PROTEÇÃO CONTRA TENDÊNCIA FORTE ---"
input int        InpMaxPerdasSeguidas  = 2;          // Pausar após X candles seguidos de perda
input int        InpCandlesDePausa     = 6;          // Quantos candles ficar pausado (6 no M10 = 1h)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 1200;       // Spread máximo permitido (pontos)
input bool       InpBloquearFDS        = true;       // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda  = 14;         // Hora de liberação na Segunda (Servidor)
input int        InpHoraFimSexta       = 23;         // Hora de bloqueio na Sexta (Servidor)
input bool       InpZerarNaSexta       = true;       // Fechar tudo na Sexta no horário limite

ulong    magic = 20261115;
datetime barra_viva;
datetime vela_controle_fechamento;
int      dia_atual_controle = -1;

double   resultado_acumulado_dia = 0.0;
int      perdas_consecutivas     = 0;
int      candles_restantes_pausa = 0;
bool     stop_diario_atingido    = false;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva = 0;
   vela_controle_fechamento = 0;
   resultado_acumulado_dia = 0.0;
   perdas_consecutivas = 0;
   candles_restantes_pausa = 0;
   stop_diario_atingido = false;
   return(INIT_SUCCEEDED); 
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   MqlDateTime tempo;
   TimeCurrent(tempo);

   // Reinicia o controle diário na virada do dia do servidor
   if(dia_atual_controle != tempo.day_of_year)
     {
      dia_atual_controle = tempo.day_of_year;
      resultado_acumulado_dia = 0.0;
      perdas_consecutivas = 0;
      candles_restantes_pausa = 0;
      stop_diario_atingido = false;
      Print("[NOVO DIA] Contadores diários zerados. Robô liberado.");
     }

   if(stop_diario_atingido) return;

   datetime hora_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   //====================================================================
   // ETAPA 1: VIRADA DE CANDLE -> ENCERRA ORDEM E CONTABILIZA RESULTADO
   //====================================================================
   if(vela_controle_fechamento != hora_vela_atual)
     {
      if(vela_controle_fechamento != 0)
        {
         FecharEContabilizar();
        }
      vela_controle_fechamento = hora_vela_atual;

      // Desconta 1 candle caso esteja em pausa por sequência negativa
      if(candles_restantes_pausa > 0)
        {
         candles_restantes_pausa--;
         Print("[PAUSA TENDÊNCIA] Aguardando mercado acalmar. Candles restantes: ", candles_restantes_pausa);
        }
     }

   //====================================================================
   // ETAPA 2: AUDITORIA DE STOP LOSS INDIVIDUAL, DIÁRIO E SEXTA-FEIRA
   //====================================================================
   double lucro_flutuante = 0;
   int total_ordens_ativas = 0;
   
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         lucro_flutuante += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         total_ordens_ativas++;
        }
     }

   // Fechamento forçado na Sexta-feira à noite
   if(InpZerarNaSexta && tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta && total_ordens_ativas > 0)
     {
      Print("[SEXTA-FEIRA] Horário limite atingido. Zerando posições.");
      FecharEContabilizar();
      return;
     }

   // Verifica se a ordem atual bateu o Stop Individual OU se a soma com o dia bateu o Stop Diário
   if(total_ordens_ativas > 0)
     {
      if(lucro_flutuante <= -MathAbs(InpMaxLossOrdemUSD) || (resultado_acumulado_dia + lucro_flutuante) <= -MathAbs(InpMaxLossDiarioUSD))
        {
         Print("[STOP ACIONADO] Encerrando posição por limite de perda.");
         FecharEContabilizar();
         return;
        }
     }

   //====================================================================
   // ETAPA 3: FILTROS DE SEGURANÇA E GATILHO DO CANDLE ATUAL
   //====================================================================
   if(candles_restantes_pausa > 0 || stop_diario_atingido) return;

   if(barra_viva != hora_vela_atual)
     {
      if(!HorarioPermitido(tempo)) return;
      
      long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread_atual > InpMaxSpread) return;

      double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Bateu ou passou da Máxima Anterior -> VENDE (Reversão)
      if(bid >= maxima_anterior)
        {
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Reversao M10 Sell"))
            barra_viva = hora_vela_atual;
        }
      // Bateu ou caiu abaixo da Mínima Anterior -> COMPRA (Reversão)
      else if(ask <= minima_anterior)
        {
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Reversao M10 Buy"))
            barra_viva = hora_vela_atual;
        }
     }
  }

//+------------------------------------------------------------------+
//| Fecha posições, atualiza saldo do dia e checa sequência de perda |
//+------------------------------------------------------------------+
void FecharEContabilizar()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double resultado_ordem = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         
         if(trade.PositionClose(ticket))
           {
            resultado_acumulado_dia += resultado_ordem;
            
            if(resultado_ordem < 0)
              {
               perdas_consecutivas++;
               Print("[PERDA] Ordem fechada em: US$ ", DoubleToString(resultado_ordem, 2), " | Perdas seguidas: ", perdas_consecutivas);
               
               if(perdas_consecutivas >= InpMaxPerdasSeguidas)
                 {
                  candles_restantes_pausa = InpCandlesDePausa;
                  perdas_consecutivas = 0;
                  Print("[BLINDAGEM] Tendência forte detectada! Robô pausado por ", InpCandlesDePausa, " candles.");
                 }
              }
            else if(resultado_ordem > 0)
              {
               perdas_consecutivas = 0; // Zera a contagem de perdas ao ter um lucro
               Print("[LUCRO] Ordem fechada em: US$ ", DoubleToString(resultado_ordem, 2), " | Saldo dia: US$ ", DoubleToString(resultado_acumulado_dia, 2));
              }

            // Verifica se atingiu o teto de perda diária
            if(resultado_acumulado_dia <= -MathAbs(InpMaxLossDiarioUSD))
              {
               stop_diario_atingido = true;
               Print("[STOP DIÁRIO] Limite de perda de US$ ", InpMaxLossDiarioUSD, " atingido. Robô pausado até amanhã!");
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Verifica se o dia da semana e horário estão liberados            |
//+------------------------------------------------------------------+
bool HorarioPermitido(MqlDateTime &tempo)
  {
   if(InpBloquearFDS && (tempo.day_of_week == 0 || tempo.day_of_week == 6)) return false;
   if(tempo.day_of_week == 1 && tempo.hour < InpHoraInicioSegunda) return false;
   if(tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta) return false;
   return true;
  }
