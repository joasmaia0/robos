//+------------------------------------------------------------------+
//|                               Sniper_Velas_Internas_H6_24_7.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "2100.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS (CICLO H6 + META US$ 10 + 24/7)
//====================================================================
input group      "--- GESTÃO FINANCEIRA E DE ORDENS ---"
input double     InpLotSize            = 0.02;       // Lote fixo em todas as ordens
input int        InpMaxOrdens          = 8;          // Máximo de ordens abertas (fecha tudo ao atingir)
input double     InpTargetProfitUSD    = 10.00;      // Meta de lucro líquido por ciclo (US$)
input double     InpMaxLossUSD         = 30.00;      // Stop Loss máximo (Trava Geral) (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)

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
   Print("🟢 [QG-IGNIÇÃO] Robô Sincronizado H6 (24/7 + Meta US$ 10 + Teto 8 Ordens) Iniciado!");
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
   // ETAPA 1: VIRADA DO CANDLE DE 6 HORAS -> DESTRAVA O NOVO CICLO
   //====================================================================
   if(bloco_6h_vante != hora_bloco_6h_atual)
     {
      Print("[SINCRO 6H] Novo candle de 6 horas iniciado! Liberando gatilhos do ciclo.");
      bloco_6h_vante = hora_bloco_6h_atual;
      ciclo_encerrado_neste_bloco = false;
     }
   
   //====================================================================
   // ETAPA 2: AUDITORIA DE META (US$ 10), TETO DE 8 ORDENS E STOP LOSS
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

   if(total_ordens_ativas > 0 && !ciclo_encerrado_neste_bloco)
     {
      // Caso 1: Bateu a meta de US$ 10,00 -> Fecha tudo e aguarda próximo candle de 6H
      if(lucro_total_ciclo >= InpTargetProfitUSD)
        {
         Print("[META ATINGIDA] Lucro líquido de US$ ", DoubleToString(lucro_total_ciclo, 2), "! Aguardando próximo H6.");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
      // Caso 2: Atingiu o máximo de 8 ordens simultâneas -> Fecha tudo e aguarda próximo H6
      else if(total_ordens_ativas >= InpMaxOrdens)
        {
         Print("[TETO ATINGIDO] Limite máximo de ", InpMaxOrdens, " ordens simultâneas! Aguardando próximo H6.");
         FecharTodasPosicoes();
         ciclo_encerrado_neste_bloco = true;
         return;
        }
      // Caso 3: Bateu o Stop Loss Global -> Encerra tudo e TRAVA o robô definitivamente
      else if(lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
        {
         Print("[STOP LOSS GLOBAL] Prejuízo de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Robô bloqueado até reinício manual!");
         FecharTodasPosicoes();
         stop_emergencia_acionado = true;
         return;
        }
     }

   //====================================================================
   // ETAPA 3: FILTRO DE SPREAD E GATILHOS 2/10 NAS VELAS INTERNAS
   //====================================================================
   long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_atual > InpMaxSpread) return;

   if(!ciclo_encerrado_neste_bloco && barra_viva_interna != hora_vela_atual)
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
         Print("[COMPRA 2/10] Ordem ", (total_ordens_ativas + 1), "/", InpMaxOrdens, " | Lote: ", InpLotSize);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Sniper 2/10 Buy"))
            barra_viva_interna = hora_vela_atual;
        }
      // Venda 2/10 acima da mínima anterior
      else if(bid <= gatilho_venda)
        {
         Print("[VENDA 2/10] Ordem ", (total_ordens_ativas + 1), "/", InpMaxOrdens, " | Lote: ", InpLotSize);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Sniper 2/10 Sell"))
            barra_viva_interna = hora_vela_atual;
        }
     }
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
