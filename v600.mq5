
//+------------------------------------------------------------------+
//|                             Sniper_Velas_Internas_Blindado.mq5   |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "2010.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS (INÍCIO SINCRONIZADO NA VIRADA DO H6)
//====================================================================
input group      "--- GESTÃO FINANCEIRA E DE ORDENS ---"
input double     InpLotSize            = 0.01;       // Lote fixo em todas as ordens
input int        InpMaxOrdens          = 8;          // Máximo de ordens abertas (fecha tudo ao atingir)
input double     InpTargetProfitUSD    = 10.00;      // Meta de lucro líquido por ciclo (US$)
input double     InpMaxLossUSD         = 10.00;      // Stop Loss máximo por ciclo H6 (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)
input bool       InpBloquearFDS        = true;       // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda  = 14;         // Hora de liberação na Segunda (Servidor)
input int        InpHoraFimSexta       = 23;         // Hora de bloqueio na Sexta (Servidor)
input bool       InpZerarNaSexta       = true;       // Fechar tudo na Sexta no horário limite

ulong    magic = 20261026;
datetime barra_viva_interna;
datetime bloco_6h_vante;
bool     ciclo_encerrado_neste_bloco = true;

//+------------------------------------------------------------------+
//| Inicialização do Robô (Nasce travado até o próximo candle H6)    |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva_interna = 0;
   
   // Registra o bloco H6 atual e trava até nascer a PRÓXIMA vela de 6 horas!
   bloco_6h_vante = iTime(_Symbol, PERIOD_H6, 0);
   ciclo_encerrado_neste_bloco = true;
   
   Print("⏳ [QG-MQL5] Sniper V2010 em modo de espera! Aguardando abertura do próximo candle H6 para iniciar!");
   return(INIT_SUCCEEDED); 
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime hora_bloco_6h_atual = iTime(_Symbol, PERIOD_H6, 0);
   datetime hora_vela_atual     = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   //====================================================================
   // ETAPA 1: VIRADA DE 6 HORAS -> DESTRAVA AUTOMATICAMENTE O NOVO CICLO
   //====================================================================
   if(bloco_6h_vante != hora_bloco_6h_atual)
     {
      bloco_6h_vante = hora_bloco_6h_atual;
      ciclo_encerrado_neste_bloco = false;
      Print("🚀 [VIRADA H6 CONFIRMADA] Novo candle de 6 horas nasceu! Gatilhos liberados!");
     }
   
   //====================================================================
   // ETAPA 2: AUDITORIA DE META (US$ 10), TETO DE 8 ORDENS E STOP US$ 10
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

   // Verifica Meta de Lucro, Máximo de 8 Ordens ou Stop Loss de US$ 10
   if(total_ordens_ativas > 0 && !ciclo_encerrado_neste_bloco)
     {
      if(lucro_total_ciclo >= InpTargetProfitUSD)
        {
         Print("[META ATINGIDA] Lucro líquido de US$ ", DoubleToString(lucro_total_ciclo, 2), "! Retomando no próximo H6.");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
      else if(total_ordens_ativas >= InpMaxOrdens)
        {
         Print("[TETO ATINGIDO] Limite máximo de ", InpMaxOrdens, " ordens simultâneas! Retomando no próximo H6.");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
      else if(lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
        {
         Print("[STOP LOSS CICLO] Perda de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Retornando automaticamente no próximo H6!");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
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
   if(!ciclo_encerrado_neste_bloco && barra_viva_interna != hora_vela_atual)
     {
      double maxima_anterior_interna = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior_interna = iLow(_Symbol, PERIOD_CURRENT, 1);
      double tamanho_candle          = maxima_anterior_interna - minima_anterior_interna;
      
      if(tamanho_candle <= 0) return;
      
      double dois_decimos   = (tamanho_candle / 10.0) * 2.0;
      double gatilho_compra = maxima_anterior_interna - dois_decimos;
      double gatilho_venda  = minima_anterior_interna + dois_decimos;
      
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      if(ask >= gatilho_compra)
        {
         Print("[COMPRA 2/10] Ordem ", (total_ordens_ativas + 1), "/", InpMaxOrdens, " | Lote: ", InpLotSize);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Sniper 2/10 Buy"))
            barra_viva_interna = hora_vela_atual;
        }
      else if(bid <= gatilho_venda)
        {
         Print("[VENDA 2/10] Ordem ", (total_ordens_ativas + 1), "/", InpMaxOrdens, " | Lote: ", InpLotSize);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Sniper 2/10 Sell"))
            barra_viva_interna = hora_vela_atual;
        }
     }

   Comment("🟢 [SNIPER VELAS INTERNAS V2010 - SINCRONIZADO H6]\n",
           "Status Ciclo: ", (ciclo_encerrado_neste_bloco ? "⏳ AGUARDANDO PRÓXIMO CANDLE DE 6H (H6)" : "⚡ CICLO ATIVO NA PISTA"), "\n",
           "Ordens Ativas: ", total_ordens_ativas, " / ", InpMaxOrdens, " | Flutuante: US$ ", DoubleToString(lucro_total_ciclo, 2));
  }

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
