//+------------------------------------------------------------------+
//|                         Sniper_Velas_Internas_Sincro_H6.mq5       |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1000.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL NOMAD DIGITAL (SINCRONIZADO NO CANDLE DE 6H)
//====================================================================
input group      "--- PARÂMETROS DO COFRE ---"
input double     InpLotSize            = 0.02;       // Lote padrão de cada tiro micro
input double     InpTargetProfitUSD    = 10.00;      // Alvo de lucro em DÓLARES no bolso

ulong magic = 20261026;
datetime barra_viva_interna;
datetime bloco_6h_vante;
bool     ciclo_encerrado_neste_bloco = false;

int OnInit() 
  { 
   trade.SetExpertMagicNumber(magic); 
   barra_viva_interna = 0;
   bloco_6h_vante = 0;
   ciclo_encerrado_neste_bloco = false;
   return(INIT_SUCCEEDED); 
  }

void OnTick()
  {
   // ⏳ RELÓGIOS DE SINCRONIA: PEGA O TEMPO DO H6 GLOBAL E DA VELINHA INTERNA ATUAL
   datetime hora_bloco_6h_atual = iTime(_Symbol, PERIOD_H6, 0);
   datetime hora_vela_atual     = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // 🔥 O ESTALO DE REINICIALIZAÇÃO: SE NASCEU UM NOVO CANDLE DE 6 HORAS, ZERA AS TRAVAS!
   if(bloco_6h_vante != hora_bloco_6h_atual)
     {
      Print("🔄 [QG-SINCRO] Novo Candle de 6 Horas detectado! Resetando o circuito para o novo ciclo!");
      bloco_6h_vante = hora_bloco_6h_atual;
      ciclo_encerrado_neste_bloco = false; // Desbloqueia o trator para operar o novo turno
     }
   
   // 📡 BUSCA A MÁXIMA E MÍNIMA DA VELA INTERNA ANTERIOR (BARRA 1 DO TIMEFRAME DO GRÁFICO)
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
   if(total_ordens_ativas > 0 && lucro_total_ciclo >= InpTargetProfitUSD && !ciclo_encerrado_neste_bloco)
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
           {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            Print("🪓 [ALVO ATINGIDO] US$ ", lucro_total_ciclo, "! Liquidando ticket do bloco: ", ticket);
            trade.PositionClose(ticket);
           }
        }
      ciclo_encerrado_neste_bloco = true; // 🔥 TRAVA DE SEGURANÇA: Congela novas entradas até o próximo H6!
      return;
     }

   //====================================================================
   // 🎛️ ETAPA 2: GATILHOS SNIPER DE VELINHAS INTERNAS (SE O BLOCO RECONHECER O SINAL)
   //====================================================================
   // Só atira se o ciclo deste bloco de 6h não tiver sido liquidado ainda e se virou a velinha interna
   if(!ciclo_encerrado_neste_bloco && barra_viva_interna != hora_vela_atual)
     {
      // 🟢 TIRO BUY: O preço Ask atual estourou a MÁXIMA da velinha interna anterior!
      if(ask >= maxima_anterior_interna)
        {
         Print("🚀 [SNIPER BUY] Rompeu a máxima anterior interna (", maxima_anterior_interna, "). Abrindo boleta!");
         trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Rompimento Interno Buy");
         barra_viva_interna = hora_vela_atual; // Fecha o cadeado estritamente para esta vela menor
        }
      // 🔴 TIRO SELL: O preço Bid atual rasgou a MÍNIMA da velinha interna anterior!
      else if(bid <= minima_anterior_interna)
        {
         Print("📉 [SNIPER SELL] Rompeu a mínima anterior interna (", minima_anterior_interna, "). Abrindo boleta!");
         trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Rompimento Interno Sell");
         barra_viva_interna = hora_vela_atual; // Fecha o cadeado estritamente para esta vela menor
        }
     }
  }
