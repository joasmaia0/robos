//+------------------------------------------------------------------+
//|                                   Malha_5Partes_Simultanea.mq5   |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "26.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL (MALHA SIMULTÂNEA DE 5 PARTES EM TODOS CANDLES)
//====================================================================
input group      "--- PARÂMETROS DO COFRE ---"
input double     InpLotSize            = 0.02;       // Lote fixo por cada disparo nas 5 partes
input double     InpMetaLucroGeralUSD  = 10.00;      // Fecha todas juntas se a soma bater X dólares (US$)
input double     InpStopLossGeralUSD   = 40.00;      // Trava de segurança máxima da conta (US$)
input int        InpMaxOrdensAbertas   = 15;         // Limite máximo total de ordens simultâneas

input group      "--- GEOMETRIA DAS 5 PARTES ---"
input int        InpDivisoesCandle     = 5;          // Divide o candle em 5 partes iguais

ulong    magic = 20260920;

datetime vela_atual_controle = 0;
bool     disparou_cima[6];   // Controle independente das 5 partes superiores no candle
bool     disparou_baixo[6];  // Controle independente das 5 partes inferiores no candle

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   ResetarGatilhosVela();
   Print("🌐 [MALHA 5 PARTES] Sistema Simultâneo em Todos os Candles Inicializado!");
   return(INIT_SUCCEEDED); 
  }

void ResetarGatilhosVela()
  {
   for(int p = 1; p <= 5; p++)
     {
      disparou_cima[p]  = false;
      disparou_baixo[p] = false;
     }
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime hora_vela = iTime(_Symbol, PERIOD_CURRENT, 0);

   // A cada novo candle que nasce, libera as 5 partes para operarem novamente
   if(vela_atual_controle != hora_vela)
     {
      ResetarGatilhosVela();
      vela_atual_controle = hora_vela;
     }

   // Audita todas as posições simultâneas abertas
   int total_vivas = 0;
   double lucro_total_flutuante = 0.0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         total_vivas++;
         lucro_total_flutuante += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
     }

   //====================================================================
   // ETAPA 1: COLHEITA GERAL SE BATER A META COLETIVA OU STOP MÁXIMO
   //====================================================================
   if(total_vivas > 0)
     {
      if(lucro_total_flutuante >= InpMetaLucroGeralUSD || lucro_total_flutuante <= -MathAbs(InpStopLossGeralUSD))
        {
         Print("💰 [COLHEITA MALHA] Resultado líquido: US$ ", DoubleToString(lucro_total_flutuante, 2));
         FecharTodasPosicoes();
         return;
        }
     }

   //====================================================================
   // ETAPA 2: VARREDURA SIMULTÂNEA DAS 5 PARTES DO CANDLE ANTERIOR
   //====================================================================
   double r_max = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double r_min = iLow(_Symbol, PERIOD_CURRENT, 1);
   double amplitude = r_max - r_min;
   
   if(amplitude <= (10 * _Point)) return;

   // Divide a vela anterior em 5 partes iguais
   double uma_parte = amplitude / (double)InpDivisoesCandle;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   long stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_dist = stop_level * _Point;

   // Varre as 5 partes de forma simultânea e independente
   for(int parte = 1; parte <= InpDivisoesCandle; parte++)
     {
      if(total_vivas >= InpMaxOrdensAbertas) break;

      // Calcula a linha superior e inferior de cada uma das 5 partes
      double linha_cima  = NormalizeDouble(r_max + (parte * uma_parte), _Digits);
      double linha_baixo = NormalizeDouble(r_min - (parte * uma_parte), _Digits);

      // 1. Bateu na parte de cima -> Compra simultânea com alvo de 1 parte acima
      if(!disparou_cima[parte] && ask >= linha_cima)
        {
         double tp_buy = NormalizeDouble(ask + uma_parte, _Digits);
         if((tp_buy - ask) <= min_dist) tp_buy = 0; // Se o alvo for menor que o mínimo da corretora, deixa sem TP fixo
         
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, tp_buy, "Malha 5P Buy P" + IntegerToString(parte)))
           {
            disparou_cima[parte] = true;
            total_vivas++;
           }
        }

      // 2. Desceu e bateu na parte de baixo -> Venda simultânea com alvo de 1 parte abaixo
      if(!disparou_baixo[parte] && bid <= linha_baixo && total_vivas < InpMaxOrdensAbertas)
        {
         double tp_sell = NormalizeDouble(bid - uma_parte, _Digits);
         if((bid - tp_sell) <= min_dist) tp_sell = 0;
         
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, tp_sell, "Malha 5P Sell P" + IntegerToString(parte)))
           {
            disparou_baixo[parte] = true;
            total_vivas++;
           }
        }
     }

   Comment("🌐 [MALHA SIMULTÂNEA 5 PARTES - TODOS OS CANDLES]\n",
           "Ordens Simultâneas Ativas: ", total_vivas, " / ", InpMaxOrdensAbertas, "\n",
           "Lucro Flutuante Total: US$ ", DoubleToString(lucro_total_flutuante, 2), " / Meta: US$ ", InpMetaLucroGeralUSD, "\n",
           "Tamanho de Cada Parte (1/5): ", DoubleToString(uma_parte / _Point, 0), " pontos");
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
