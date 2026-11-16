//+--------------------------------==================================+
//|                                     Grid_Institucional_300.mq5   |
//|                                           Engenheiro Chefe QG    |
//+--------------------------------==================================+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "20.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL ULTRA AGRESSIVO (300 ORDENS + LOTE POR LUCRO)
//====================================================================
input group      "--- PARÂMETROS DO COFRE ---"
input double     InpBaseAccountBalance = 1000.00;    // Saldo de Partida da Conta (Referência de Fábrica)
input double     InpLotStepAdd         = 0.02;       // 💥 SOMA DO DEGRAU: O quanto soma por nível (Ex: 0.10 -> 0.12 -> 0.14)
input int        InpMaxTotalTrades     = 300;        // 💥 O TETO DO CHEFE: Até 300 operações por ciclo!

input group      "--- DISTÂNCIAS INTERBANCÁRIAS ---"
input int        InpGridStep           = 100;        // Espaçamento do Grid em Pontos
input int        InpTakeProfit         = 10;        // Alvo de Lucro individual em Pontos
input ENUM_TIMEFRAMES InpTimeframe     = PERIOD_M5;  // Gráfico operando em M5 livre

//--- Variáveis globais ocultas de RAM
ulong magic = 20260901;

int OnInit() { trade.SetExpertMagicNumber(magic); return(INIT_SUCCEEDED); }

void OnTick()
  {
   int total_buys = 0, total_sells = 0, total_vivas = 0;
   double menor_preco_buy = 999999, total_lots_buy = 0, maior_lote_visto = 0;

   // 📊 MONITORAMENTO EM TEMPO REAL: Varre e audita as posições vivas na RAM
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
        {
         total_vivas++;
         long type = PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         
         if(type == POSITION_TYPE_BUY)
           {
            total_buys++;
            total_lots_buy += volume;
            if(volume > maior_lote_visto) maior_lote_visto = volume;
            if(PositionGetDouble(POSITION_PRICE_OPEN) < menor_preco_buy) 
               menor_preco_buy = PositionGetDouble(POSITION_PRICE_OPEN);
           }
         if(type == POSITION_TYPE_SELL) total_sells++;
        }
     }

   // 📈 CALCULO DO LOTE INICIAL DINÂMICO AUTOMÁTICO VIA LUCRO REAL
   double saldo_atual = AccountInfoDouble(ACCOUNT_BALANCE);
   double lote_inicial_calculado = 0.02; // Ponto de partida padrão
   
   if(saldo_atual >= InpBaseAccountBalance)
     {
      // A cada bloco de lucro proporcional, ele escala o lote inicial sozinho de 0.02 para 0.05, 0.10...
      double multiplicador_lucro = saldo_atual / InpBaseAccountBalance;
      lote_inicial_calculado = NormalizeDouble(0.02 * multiplicador_lucro, 2);
      
      // Ajusta para travar nos pisos mínimos que você desenhou na mente
      if(saldo_atual >= (InpBaseAccountBalance * 2.5) && lote_inicial_calculado < 0.05) lote_inicial_calculado = 0.05;
      if(saldo_atual >= (InpBaseAccountBalance * 5.0)) lote_inicial_calculado = 0.10;
     }
   if(lote_inicial_calculado < 0.02) lote_inicial_calculado = 0.02;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //====================================================================
   // 🎛️ ETAPA 1: RECOMEÇO CONTÍNUO (ZÉRO TRAVA DE VELA - INICIA NO ATO)
   //====================================================================
   if(total_vivas == 0)
     {
      double fechamento_passado = iClose(_Symbol, InpTimeframe, 1);
      if(ask > fechamento_passado)
        {
         double tp = ask + (InpTakeProfit * _Point);
         if(trade.Buy(lote_inicial_calculado, _Symbol, ask, 0, tp, "Start Dinamico"))
           {
            Print("🟢 [CICLO INICIADO] Tela zerada! Lote de partida calibrado por lucro: ", lote_inicial_calculado);
           }
        }
     }

   //====================================================================
   // 🎛️ ETAPA 2: REFORÇOS DE ESCALA CIRÚRGICA ATÉ O LIMITE DE 300
   //====================================================================
   if(total_buys > 0 && total_vivas < InpMaxTotalTrades)
     {
      if(ask < (menor_preco_buy - (InpGridStep * _Point)))
        {
         // 🎯 A EXIGÊNCIA DO CHEFE: Pega o maior lote da tela e soma +0.02 de forma rígida por degrau!
         double lote_reforco = NormalizeDouble(maior_lote_visto + InpLotStepAdd, 2);
         if(lote_reforco > 5.0) lote_reforco = 5.0; // Teto de segurança máxima por clique
         
         double tp = ask + (InpTakeProfit * _Point);
         Print("⚠️ [MARTINGALE ESCALA] Disparando nível ", total_buys+1, ". Lote somado: ", lote_reforco);
         trade.Buy(lote_reforco, _Symbol, ask, 0, tp, "Grid Escala Buy");
        }
     }

   //====================================================================
   // 🎛️ ETAPA 3: HEDGE DE TRAVAMENTO INDUSTRIAL FLUTUANTE
   //====================================================================
   if(total_buys >= 4 && total_sells == 0 && total_vivas < InpMaxTotalTrades)
     {
      double lote_hedge = NormalizeDouble(total_lots_buy * 1.2, 2);
      if(lote_hedge > 10.0) lote_hedge = 10.0; // Teto de margem
      
      double tp_hedge = bid - (100 * _Point);
      Print("🛡️ [HEDGE PROTEÇÃO] Travando a RAM com Sell pesado de lote: ", lote_hedge);
      trade.Sell(lote_hedge, _Symbol, bid, 0, tp_hedge, "Hedge Escala Sell");
     }
  }
