//+------------------------------------------------------------------+
//|                             Sniper_Velas_Internas_Blindado.mq5   |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1300.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS DO ROBÔ
//====================================================================
input group      "--- GESTÃO FINANCEIRA ---"
input double     InpLotSize            = 0.02;       // Lote por ordem
input double     InpTargetProfitUSD    = 10.00;      // Meta de lucro por ciclo (US$)
input double     InpMaxLossUSD         = 40.00;      // Stop Loss máximo (Trava Geral) (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)
input bool       InpBloquearFDS        = true;       // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda  = 14;         // Hora de liberação na Segunda (Servidor)
input int        InpHoraFimSexta       = 23;         // Hora de bloqueio na Sexta (Servidor)
input bool       InpZerarNaSexta       = true;       // Fechar tudo na Sexta no horário limite

ulong    magic = 20261026;
datetime barra_viva_interna;
datetime bloco_6h_vante;
bool     ciclo_encerrado_neste_bloco = false;
bool     stop_emergencia_acionado    = false;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva_interna = 0;
   bloco_6h_vante = 0;
   ciclo_encerrado_neste_bloco = false;
   stop_emergencia_acionado    = false;
   return(INIT_SUCCEEDED); 
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Se a trava de emergência foi disparada, bloqueia qualquer execução até reinício manual
   if(stop_emergencia_acionado) return;

   datetime hora_bloco_6h_atual = iTime(_Symbol, PERIOD_H6, 0);
   datetime hora_vela_atual     = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Reinicia o ciclo na abertura de um novo candle de 6 horas (apenas se não houve Stop Loss)
   if(bloco_6h_vante != hora_bloco_6h_atual)
     {
      Print("[SINCRO] Novo candle de 6H detectado. Ciclo reiniciado.");
      bloco_6h_vante = hora_bloco_6h_atual;
      ciclo_encerrado_neste_bloco = false;
     }
   
   //====================================================================
   // ETAPA 1: AUDITORIA DE LUCRO, STOP LOSS E FECHAMENTO DE SEXTA
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
      ciclo_encerrado_neste_bloco = true;
      return;
     }

   // Verifica se bateu a meta de lucro OU o limite máximo de perda
   if(total_ordens_ativas > 0 && !ciclo_encerrado_neste_bloco)
     {
      // Caso 1: Bateu a meta de lucro -> Encerra e aguarda próximo bloco de 6H
      if(lucro_total_ciclo >= InpTargetProfitUSD)
        {
         Print("[META ATINGIDA] Lucro de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Aguardando próximo H6.");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
      // Caso 2: Bateu o Stop Loss -> Encerra tudo e TRAVA o robô definitivamente
      else if(lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
        {
         Print("[STOP LOSS GLOBAL] Prejuízo de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Robô bloqueado até reinício manual!");
         FecharTodasPosicoes();
         stop_emergencia_acionado = true;
         return;
        }
     }

   //====================================================================
   // ETAPA 2: FILTROS DE SEGURANÇA (HORÁRIO E SPREAD)
   //====================================================================
   if(!HorarioPermitido()) return;
   
   long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_atual > InpMaxSpread) return;

   //====================================================================
   // ETAPA 3: GATILHOS DE ENTRADA NAS VELAS INTERNAS
   //====================================================================
   if(!ciclo_encerrado_neste_bloco && barra_viva_interna != hora_vela_atual)
     {
      double maxima_anterior_interna = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior_interna = iLow(_Symbol, PERIOD_CURRENT, 1);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Rompimento da Máxima Anterior -> Compra
      if(ask >= maxima_anterior_interna)
        {
         Print("[COMPRA] Rompeu máxima anterior (", maxima_anterior_interna, ") | Spread: ", spread_atual);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Rompimento Interno Buy"))
            barra_viva_interna = hora_vela_atual;
        }
      // Rompimento da Mínima Anterior -> Venda
      else if(bid <= minima_anterior_interna)
        {
         Print("[VENDA] Rompeu mínima anterior (", minima_anterior_interna, ") | Spread: ", spread_atual);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Rompimento Interno Sell"))
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
   
   // Bloqueia Domingo (0) e Sábado (6)
   if(InpBloquearFDS && (tempo.day_of_week == 0 || tempo.day_of_week == 6))
      return false;
      
   // Bloqueia Segunda-feira (1) antes do horário definido
   if(tempo.day_of_week == 1 && tempo.hour < InpHoraInicioSegunda)
      return false;
      
   // Bloqueia Sexta-feira (5) a partir do horário definido
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
