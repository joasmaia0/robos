//+--------------------------------==================================+
//|                                   Ancora_Timeframe_Generico.mq5  |
//|                                           Engenheiro Chefe QG    |
//+--------------------------------==================================+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "19.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL PURISTA (TEMPO GRÁFICO AUTOMÁTICO E GENÉRICO)
//====================================================================
input double InpLotSize = 0.01; // O CANHÃO DO CHEFE: Lote de Partida Real

//--- Variáveis globais ocultas de controle rígido na RAM
datetime hora_da_vela_atual = 0;
ulong    magic_number = 20260909;
int      compra = 0; // A sua gaveta de trava biométrica contra duplicação!

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   Print("🔌 [QG-MQL5] Usina Genérica Ativada! Operando no tempo gráfico atual do monitor!");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  { 
   // 🌟 CONSERTO GENÉRICO: Troca da trava fixa pelo DNA do tempo do gráfico ativo (PERIOD_CURRENT)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);

   //====================================================================
   // 🪓 ETAPA 1: O RELÓGIO APITOU? VELA VIRADA? GUILHOTINA A MERCADO NO ATO!
   //====================================================================
   // Se o tempo da vela mudou e existe uma ordem aberta de antes, passa a faca!
   if(hora_da_vela_atual != iTime(_Symbol, PERIOD_CURRENT, 0))
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
           {
            Print("🪓 [CRONÔMETRO] Bloco de tempo encerrado! Liquidando Posição a Mercado!");
            hora_da_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
            trade.PositionClose(PositionGetTicket(i));
            compra = 0; // Reseta a trava para o próximo candle
           }
        }
     }

   //====================================================================
   // 🟢 ETAPA 2: O BLOQUEIO DE SEGURANÇA MÁXIMA (ANTI-DUPLICAÇÃO)
   //====================================================================
   if(hora_da_vela_atual != iTime(_Symbol, PERIOD_CURRENT, 0))
     {
      hora_da_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
      compra = 0;
     }
 
   // 🎯 O SEU GATILHO PURISTA: Bid estourou a máxima anterior do gráfico e a trava tá livre (compra == 0)!
   if((iHigh(_Symbol, PERIOD_CURRENT, 0) > maxima_anterior) && (compra == 0))
     {
       Print("🔴 [ESTOURO CONFIRMADO] Preço Bid ultrapassou a Máxima do gráfico (", maxima_anterior, ")!");
       Print("📡 Disparando o TIRO ÚNICO do cesto. Lote cravado: ", InpLotSize);
         
       // Dispara o tiro seco de Venda (Sell) para faturar no pavio de exaustão da vela atual
       if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Estouro Close"))
         {
          // 🔒 O CADENADO INDESTRUTÍVEL: Trava a fiação mudando o status para 1!
          compra = 1;
          Print("🔒 [TRAVA DE SEGURANÇA ATIVADA] Cartucho gasto! Cesto trancado até a vira do bloco.");
         }
     }
  }
  
  
