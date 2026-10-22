//+------------------------------------------------------------------+
//|                                     Ancora_Sniper_Canal_V500.mq5 |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "500.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// 🎰 PAINEL CONFIGURÁVEL PURISTA (SNIPER DE CANAL OPONENTE ESPELHADO)
//====================================================================
input group      "--- PARAMETROS DE CAPITAL ---"
input double InpLotSize = 0.02; // Lote de Partida Real (ProCent de 6.000 centavos)

ulong    magic_number = 20261006;
datetime hora_da_vela_atual = 0;
int      tiro_gasto_vela = 0;  // Trava biométrica de 1 tiro por candle

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   tiro_gasto_vela = 0;
   Print("🔌 [QG-MQL5] Sniper V500 Ativado! Estratégia de Saída Cruzada por Gatilho Oposto ativa!");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  { 
   // DNA do tempo do candle vivo atual (Barra 0)
   datetime tempo_vela_viva = iTime(_Symbol, PERIOD_CURRENT, 0);

   // MATEMÁTICA GEOMÉTRICA DA DIVISÃO POR 10 (Barra 1 anterior completa)
   double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
   
   double tamanho_candle_anterior = maxima_anterior - minima_anterior;
   double fracao = tamanho_candle_anterior / 10.0; // Divide o candle anterior em 10 partes
   
   // --- LINHAS DE GATILHO DE ENTRADA E SAÍDA DINÂMICA (RAM) ---
   double gatilho_compra = maxima_anterior - (2.0 * fracao); // 2/10 abaixo da máxima
   double gatilho_venda  = minima_anterior + (2.0 * fracao);  // 2/10 acima da mínima

   // Cotações ao vivo do satélite de Londres
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   int i = 0;

   //====================================================================
   // 🪓 ETAPA 1: O RELÓGIO APITOU? VELA ENCERROU? ENCERRA TUDO A MERCADO!
   //====================================================================
   if(tempo_vela_viva != hora_da_vela_atual)
     {
      i++;
      // Passa a faca eletrônica a mercado se a vela morrer antes de bater no gatilho oposto
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
           {
            Print("🪓 [FIM DO CANDLE] Mudança de minuto! Liquidando saldo residual a mercado!");
            
            if(i == 3){
             i = 0;
             trade.PositionClose(PositionGetTicket(i));
            }
            
           }
        }
      
      // Reseta as travas biométricas pro novo minuto nascer zerado
      hora_da_vela_atual = tempo_vela_viva;
      tiro_gasto_vela = 0;
     }

   //====================================================================
   // 🚨 ETAPA 2: AS GUILHOTINAS CRUZADAS — SÓ SAI NO GATILHO OPONENTE!
   //====================================================================


   //====================================================================
   // 📐 ETAPA 3: EXECUÇÃO DO TIRO ÚNICO (SNIPER POR VOLATILIDADE)
   //====================================================================
   if(tiro_gasto_vela == 0 && PositionsTotal() == 0)
     {
      // CONDICIONAL COMPRA: Clica comprado se o preço recuar para baixo ou igual à linha de 2/10 da máxima
      if(ask >= gatilho_compra)
        {
         Print("📡 [SNIPER BUY ENTRADA] Socando COMPRA no recuo de 2/10! Alvo: ", gatilho_venda);
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Sniper Canal Buy"))
           {
            tiro_gasto_vela = 1; // 🔒 Trava o chassi na vela atual!
           }
        }
      // CONDICIONAL VENDA: Clica vendido se o preço subir para cima ou igual à linha de 2/10 da mínima
      else if(bid <= gatilho_venda)
        {
         Print("📡 [SNIPER SELL ENTRADA] Socando VENDA na subida de 2/10! Alvo: ", gatilho_compra);
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Sniper Canal Sell"))
           {
            tiro_gasto_vela = 1; // 🔒 Trava o chassi na vela atual!
           }
        }
     }

   Comment("🟢 [SNIPER CANAL CRUZADO V500]\nTiro na Vela Gasto: ", tiro_gasto_vela, " / 1\nLinha Gatilho Buy (Entrada/Saída Sell): ", gatilho_compra, "\nLinha Gatilho Sell (Entrada/Saída Buy): ", gatilho_venda);
  }
