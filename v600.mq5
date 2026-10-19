
//+------------------------------------------------------------------+
//|                                                   v700.mq5       |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "700.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL (COMPRA EM TODO CANDLE COM SL E TP FIXOS)
//====================================================================
input group      "--- PARÂMETROS DE CAPITAL ---"
input double InpLotSize   = 0.02; // Lote de Partida Real (ProCent de 2.361 centavos)

input group      "--- MATEMÁTICA ALVO (EM PONTOS) ---"
input int    InpTakeProfit = 600;  // Alvo de Lucro (Take Profit) em Pontos
input int    InpStopLoss   = 200;  // Limite de Perda (Stop Loss) em Pontos

ulong    magic_number = 20261012;
datetime hora_da_vela_atual = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   hora_da_vela_atual = 0;
   Print("🔌 [QG-MQL5] Sniper V700 Ativado! Entrada exaustiva em todo candle com TP 300 e SL 100!");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  { 
   // DNA do tempo do candle vivo atual (Barra 0)
   datetime tempo_vela_viva = iTime(_Symbol, PERIOD_CURRENT, 0);

   //====================================================================
   // 🪓 ETAPA 1: O RELÓGIO APITOU? NOVO CANDLE NASCEU?
   //====================================================================
   if(tempo_vela_viva != hora_da_vela_atual)
     {
      hora_da_vela_atual = tempo_vela_viva;
      // Preço de compra Ask vivo vindo direto do satélite de Londres
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // CÁLCULO CIRÚRGICO DA BLINDAGEM DA BOLETA
      double preco_tp = ask + (InpTakeProfit * _Point);
      double preco_sl = ask - (InpStopLoss * _Point);
      
      Print("📡 [SNIPER BUY EXAUSTIVO] Novo candle detectado! Disparando COMPRA a mercado!");
      Print("📐 Configuração de Alvos -> Preço: ", ask, " | SL: ", preco_sl, " | TP: ", preco_tp);
      
      // Executa o soco seco de compra injetando SL e TP direto na carcaça da ordem
      if(trade.Buy(InpLotSize, _Symbol, ask, preco_sl, preco_tp, "Exaustivo V700"))
        {
         // 🔒 Passa o cadeado biométrico para proibir novos tiros nesta mesma barra
         //hora_da_vela_atual = tempo_vela_viva;
        }
     }

   // Exibição do status no teto do gráfico para auditoria em tempo real
   Comment("🟢 [SNIPER EXAUSTIVO V700]\nLote cravado: ", InpLotSize, "\nTake Profit Fixo: ", InpTakeProfit, " pontos\nStop Loss Fixo: ", InpStopLoss, " pontos\nÚltimo Candle Processado: ", TimeToString(hora_da_vela_atual));
  }
