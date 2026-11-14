//+------------------------------------------------------------------+
//|                                Sniper_Reversao_2Decimos_24_7.mq5 |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1800.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PARÂMETROS CONFIGURÁVEIS DO ROBÔ (REVERSÃO EXTERNA 2/10 + 24/7)
//====================================================================
input group      "--- GESTÃO FINANCEIRA ---"
input double     InpLotSize            = 0.02;       // Lote fixo em todas as ordens
input double     InpMaxLossUSD         = 30.00;      // Stop Loss máximo (Trava Geral) (US$)

input group      "--- BLINDAGEM DE MERCADO ---"
input int        InpMaxSpread          = 2500;       // Spread máximo permitido (pontos)

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
   Print("🟢 [QG-IGNIÇÃO] Robô Reversão Externa 2/10 (24/7) Inicializado!");
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
   // ETAPA 2: AUDITORIA DE STOP LOSS DE EMERGÊNCIA (-US$ 30)
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

   // Verifica se bateu o Stop Loss de Emergência
   if(total_ordens_ativas > 0 && lucro_total_ciclo <= -MathAbs(InpMaxLossUSD))
     {
      Print("[STOP LOSS GLOBAL] Prejuízo de US$ ", DoubleToString(lucro_total_ciclo, 2), ". Robô bloqueado até reinício manual!");
      FecharTodasPosicoes();
      stop_emergencia_acionado = true;
      return;
     }

   //====================================================================
   // ETAPA 3: FILTRO DE SPREAD E GATILHOS INVERTIDOS 2/10 (24/7)
   //====================================================================
   long spread_atual = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_atual > InpMaxSpread) return;

   if(barra_viva_interna != hora_vela_atual)
     {
      double maxima_anterior_interna = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior_interna = iLow(_Symbol, PERIOD_CURRENT, 1);
      double tamanho_candle          = maxima_anterior_interna - minima_anterior_interna;
      
      if(tamanho_candle <= 0) return;
      
      double dois_decimos  = (tamanho_candle / 10.0) * 2.0;
      double gatilho_venda = maxima_anterior_interna + dois_decimos; // 2/10 ACIMA da máxima -> VENDE
      double gatilho_compra = minima_anterior_interna - dois_decimos; // 2/10 ABAIXO da mínima -> COMPRA
      
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Preço esticou 2/10 ACIMA da máxima anterior -> VENDE (Reversão)
      if(bid >= gatilho_venda)
        {
         Print("[VENDA 2/10 ACIMA] Lote: ", InpLotSize, " | Bid: ", bid, " >= Gatilho: ", gatilho_venda);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Reversao 2/10 Acima Sell"))
            barra_viva_interna = hora_vela_atual;
        }
      // Preço caiu 2/10 ABAIXO da mínima anterior -> COMPRA (Reversão)
      else if(ask <= gatilho_compra)
        {
         Print("[COMPRA 2/10 ABAIXO] Lote: ", InpLotSize, " | Ask: ", ask, " <= Gatilho: ", gatilho_compra);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Reversao 2/10 Abaixo Buy"))
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
