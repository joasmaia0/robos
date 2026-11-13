//+------------------------------------------------------------------+
//|                             Sniper_Velas_Internas_Blindado.mq5   |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1700.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS DO ROBÔ (CICLO 6H + GATILHO 2/10)
//====================================================================
input group      "--- GESTÃO FINANCEIRA ---"
input double     InpLotSize            = 0.02;       // Lote fixo em todas as ordens
input double     InpMaxLossUSD         = 30.00;      // Stop Loss máximo (Trava Geral) (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)
input bool       InpBloquearFDS        = true;       // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda  = 14;         // Hora de liberação na Segunda (Servidor)
input int        InpHoraFimSexta       = 23;         // Hora de bloqueio na Sexta (Servidor)
input bool       InpZerarNaSexta       = true;       // Fechar tudo na Sexta no horário limite

ulong    magic = 20261026;
datetime barra_viva_interna;
datetime bloco_6h_vante;
bool     stop_emergencia_acionado = false;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva_interna = 0;
   bloco_6h_vante = 0;
   stop_emergencia_acionado = false;
   return(INIT_SUCCEEDED); 
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(stop_emergencia_acionado) return;

   datetime hora_bloco_6h_atual = iTime(_Symbol, PERIOD_H6, 0);
   datetime hora_vela_atual     = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   //====================================================================
   // ETAPA 1: VIRADA DO CANDLE DE 6 HORAS -> ENCERRA O CICLO ANTERIOR
   //====================================================================
   if(bloco_6h_vante != hora_bloco_6h_atual)
     {
      if(bloco_6h_vante != 0)
        {
         Print("[CRONÔMETRO 6H] Fim do candle de 6 horas! Encerrando todas as posições abertas...");
         FecharTodasPosicoes();
        }
      bloco_6h_vante = hora_bloco_6h_atual;
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
      Print("[SEXTA-FEIRA] Horário limite atingido. Zerando posições para o fim de semana.");
      FecharTodasPosicoes();
      return;
     }

   // Verifica se bateu o Stop Loss de Emergência
   if(total_ordens_ativas > 0 && lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
     {
      Print("[STOP LOSS GLOBAL] Prejuízo de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Robô bloqueado até reinício manual!");
      FecharTodasPosicoes();
      stop_emergencia_acionado = true;
      return;
     }

   //====================================================================
   // ETAPA 3: FILTROS DE SEGURANÇA (HORÁRIO E SPREAD)
   //====================================================================
   if(!HorarioPermitido()) return;
   
   long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_atual > InpMaxSpread) return;

   //====================================================================
   // ETAPA 4: GATILHOS 2/10 NAS VELAS INTERNAS (COM LOTE FIXO)
   //====================================================================
   if(barra_viva_interna != hora_vela_atual)
     {
      double maxima_anterior_interna = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior_interna = iLow(_Symbol, PERIOD_CURRENT, 1);
      double tamanho_candle          = maxima_anterior_interna - minima_anterior_interna;
      
      if(tamanho_candle <= 0) return;
      
      double dois_decimos   = (tamanho_candle / 10.0) * 2.0;
      double gatilho_compra = maxima_anterior_interna - dois_decimos; // 2/10 abaixo da máxima
      double gatilho_venda  = minima_anterior_interna + dois_decimos; // 2/10 acima da mínima
      
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Compra 2/10 abaixo da máxima anterior
      if(ask >= gatilho_compra)
        {
         Print("[COMPRA 2/10] Lote Fixo: ", InpLotSize, " | Ask: ", ask, " >= Gatilho: ", gatilho_compra);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Sniper 2/10 Buy"))
            barra_viva_interna = hora_vela_atual;
        }
      // Venda 2/10 acima da mínima anterior
      else if(bid <= gatilho_venda)
        {
         Print("[VENDA 2/10] Lote Fixo: ", InpLotSize, " | Bid: ", bid, " <= Gatilho: ", gatilho_venda);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Sniper 2/10 Sell"))
            barra_viva_interna = hora_vela_atual;
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
