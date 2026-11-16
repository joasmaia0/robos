//+------------------------------------------------------------------+
//|                                  Grid_Institucional_NoPrumo.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "22.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL NO PRUMO (LINHA FIXA + SAÍDA EM DÓLARES)
//====================================================================
input group      "--- PARÂMETROS DO COFRE ---"
input double     InpLotInicial         = 0.02;       // Lote da primeira ordem
input double     InpLotStepAdd         = 0.02;       // Soma do degrau por nível
input double     InpMetaLucroUSD       = 5.00;       // Fecha tudo ao bater esse lucro líquido (US$)
input double     InpStopLossMaxUSD     = 30.00;      // Trava de segurança máxima (US$)
input int        InpMaxTotalTrades     = 10;         // Limite máximo de ordens por ciclo

input group      "--- DISTÂNCIAS INTERBANCÁRIAS ---"
input int        InpGridStep           = 100;        // Espaçamento em pontos acima/abaixo da linha

ulong    magic = 20260909;

double   lote = 0.02;
string   chave_1 = "aberta";
string   chave_2 = "fechada";
double   r_max_fixa = 0.0;
bool     ciclo_ativo = false;
datetime vela_ultimo_tiro = 0;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   ResetarCiclo();
   return(INIT_SUCCEEDED); 
  }

void ResetarCiclo()
  {
   lote = InpLotInicial;
   chave_1 = "aberta";
   chave_2 = "fechada";
   r_max_fixa = 0.0;
   ciclo_ativo = false;
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime hora_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Audita posições reais e soma o lucro líquido da cesta
   int total_vivas = 0;
   double lucro_cesta = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         total_vivas++;
         lucro_cesta += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
     }

   //====================================================================
   // ETAPA 1: ENCERRAMENTO PELO FINANCEIRO REAL (META OU STOP)
   //====================================================================
   if(total_vivas > 0)
     {
      if(lucro_cesta >= InpMetaLucroUSD || lucro_cesta <= -MathAbs(InpStopLossMaxUSD))
        {
         Print("[ENCERRAMENTO] Resultado líquido do ciclo: US$ ", DoubleToString(lucro_cesta, 2));
         FecharTodasPosicoes();
         ResetarCiclo();
         vela_ultimo_tiro = hora_vela_atual;
         return;
        }
     }
   else if(ciclo_ativo)
     {
      ResetarCiclo();
     }

   // Se não há ciclo ativo, captura a máxima da vela anterior e aguarda o primeiro tiro
   if(!ciclo_ativo)
     {
      r_max_fixa = iHigh(_Symbol, PERIOD_CURRENT, 1);
     }

   // Garante no máximo 1 entrada por candle para não queimar lotes no ruído
   if(vela_ultimo_tiro == hora_vela_atual) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double margem_step = InpGridStep * _Point;

   //====================================================================
   // ETAPA 2: DISPARO BUY ACIMA DA LINHA CONGELADA
   //====================================================================
   if(ask > (r_max_fixa + margem_step) && chave_1 == "aberta" && total_vivas < InpMaxTotalTrades)
     {
      double lote_envio = NormalizeDouble(lote, 2);
      if(trade.Buy(lote_envio, _Symbol, ask, 0, 0, "Grid Buy NoPrumo"))
        {
         ciclo_ativo = true;
         lote = NormalizeDouble(lote + InpLotStepAdd, 2);
         chave_1 = "fechada";
         chave_2 = "aberta";
         vela_ultimo_tiro = hora_vela_atual;
        }
     }

   //====================================================================
   // ETAPA 3: DISPARO SELL ABAIXO DA LINHA CONGELADA
   //====================================================================
   else if(bid < (r_max_fixa - margem_step) && chave_2 == "aberta" && total_vivas < InpMaxTotalTrades)
     {
      double lote_envio = NormalizeDouble(lote, 2);
      if(trade.Sell(lote_envio, _Symbol, bid, 0, 0, "Grid Sell NoPrumo"))
        {
         ciclo_ativo = true;
         lote = NormalizeDouble(lote + InpLotStepAdd, 2);
         chave_1 = "aberta";
         chave_2 = "fechada";
         vela_ultimo_tiro = hora_vela_atual;
        }
     }

   Comment("🟢 [GRID NO PRUMO - LINHA CONGELADA + SAÍDA USD]\n",
           "Resultado Aberto: US$ ", DoubleToString(lucro_cesta, 2), " / Meta: US$ ", InpMetaLucroUSD, "\n",
           "Ordens Ativas: ", total_vivas, " / ", InpMaxTotalTrades, "\n",
           "Linha Congelada: ", r_max_fixa, "\n",
           "Próximo Lote: ", lote);
  }

void FecharTodasPosicoes()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         trade.PositionClose(PositionGetTicket(i));
        }
     }
  }
