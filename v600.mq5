//+------------------------------------------------------------------+
//|                               Sniper_Velas_Internas_V2.mq5        |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "900.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL NOMAD DIGITAL (EMPILHAMENTO DESBLOQUEADO)
//====================================================================
input group      "--- PARÂMETROS DO COFRE ---"
input double     InpLotSize            = 0.02;       // Lote padrão de cada tiro micro
input double     InpTargetProfitUSD    = 10.00;      // Alvo de lucro em DÓLARES no bolso

ulong magic = 20261024;
datetime barra_viva;

int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva = 0;
   return(INIT_SUCCEEDED); 
  }

void OnTick()
  {
   // ⏳ TRAVA DO RELÓGIO: PEGA O TEMPO DO GRÁFICO ATUAL (EX: H1 ONDE O ROBÔ ESTÁ)
   datetime hora_vela_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // 📡 BUSCA A MÁXIMA E MÍNIMA DA VELA INTERNA ANTERIOR (BARRA 1 DO TIMEFRAME ATUAL)
   double maxima_anterior_interna = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double minima_anterior_interna = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //====================================================================
   // 🪓 ETAPA 1: AUDITORIA DO COFRE (ALVO FINANCEIRO ACUMULADO DE US$ 10)
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
     
   // SE O EXTRATO ACUMULADO BATER 10 DÓLARES: FECHAMENTO HIDRÁULICO IMEDIATO!
   if(total_ordens_ativas > 0 && lucro_total_ciclo >= InpTargetProfitUSD)
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
           {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            Print("🪓 [ALVO ATINGIDO] US$ ", lucro_total_ciclo, "! Fechando ticket físico: ", ticket);
            trade.PositionClose(ticket);
           }
        }
      barra_viva = hora_vela_atual; // Tranca o disjuntor para não operar mais na mesma vela do Take
      return;
     }

   //====================================================================
   // 🎛️ ETAPA 2: GATILHOS SNIPER (SÓ MIRA O RELÓGIO DO CANDLE ATUAL)
   //====================================================================
   // 🔥 CORREÇÃO ULTRA: Removeu o bloqueio da gaveta cheia! Agora só checa o tempo da barra!
   if(barra_viva != hora_vela_atual)
     {
      // 🟢 TIRO BUY: O preço Ask atual estourou a MÁXIMA da velinha anterior!
      if(ask >= maxima_anterior_interna)
        {
         Print("🚀 [SNIPER BUY] Rompeu a máxima anterior interna (", maxima_anterior_interna, "). Abrindo boleta!");
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Rompimento Interno Buy");
         barra_viva = hora_vela_atual; // Fecha o cadeado estritamente para este candle atual
        }
      // 🔴 TIRO SELL: O preço Bid atual rasgou a MÍNIMA da velinha anterior!
      else if(bid <= minima_anterior_interna)
        {
         Print("📉 [SNIPER SELL] Rompeu a mínima anterior interna (", minima_anterior_interna, "). Abrindo boleta!");
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Rompimento Interno Sell");
         barra_viva = hora_vela_atual; // Fecha o cadeado estritamente para este candle atual
        }
     }
  }
