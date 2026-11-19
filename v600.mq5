//+------------------------------------------------------------------+
//|                                 Sniper_Extremos_Vela_Purista.mq5 |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

input double InpLotSize           = 0.02;  // Lote fixo por operação
input double InpMaxLossDiarioUSD  = 20.00; // Perda máxima permitida no DIA (US$)
input bool   InpBloquearFDS       = true;  // Bloquear Sábado e Domingo
input int    InpHoraInicioSegunda = 15;    // Início Segunda (15h MT5 = 10h00 Brasil)
input int    InpHoraFimSexta      = 23;    // Bloqueio Sexta (23h MT5 = 18h00 Brasil)

datetime hora_vela = 0;
ulong    magic = 20261125;
bool     operou_vela = false;

int OnInit()
  {
   trade.SetExpertMagicNumber(magic);
   return(INIT_SUCCEEDED);
  }

void OnTick()
  { 
   MqlDateTime t;
   TimeCurrent(t);

   // Trava de Perda Máxima Diária (Fechado + Aberto)
   double res_hoje = ResultadoDia();
   if(res_hoje <= -MathAbs(InpMaxLossDiarioUSD))
     {
      FecharTudo();
      Comment("🛑 [STOP DIÁRIO ATINGIDO]\nPerda líquida hoje: US$ ", DoubleToString(res_hoje, 2), " (Limite: -US$ ", InpMaxLossDiarioUSD, ").\nRetorno automático amanhã.");
      return;
     }

   // Encerramento forçado na Sexta-feira à noite
   if(t.day_of_week == 5 && t.hour >= InpHoraFimSexta)
     { FecharTudo(); Comment("Pausa Sexta à noite."); return; }

   datetime vela_viva = iTime(_Symbol, PERIOD_CURRENT, 0);

   // Virada do candle -> Encerra a operação anterior e libera novo cartucho
   if(hora_vela != vela_viva)
     {
      FecharTudo();
      hora_vela = vela_viva;
      operou_vela = false;
     }

   // Filtro de Fim de Semana e Segunda até as 10h00
   if((InpBloquearFDS && (t.day_of_week == 0 || t.day_of_week == 6)) ||
      (t.day_of_week == 1 && t.hour < InpHoraInicioSegunda))
     { Comment("Pausa programada (Fim de semana / Segunda cedo)."); return; }

   // Gatilhos nos extremos da vela anterior (1 operação por candle)
   if(!operou_vela)
     {
      double max_ant = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double min_ant = iLow(_Symbol, PERIOD_CURRENT, 1);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Bateu ou passou da máxima -> VENDE
      if(bid >= max_ant)
        {
         if(trade.Sell(InpLotSize, _Symbol, bid, 0, 0, "Sell Maxima"))
            operou_vela = true;
        }
      // Bateu ou passou da mínima -> COMPRA
      else if(ask <= min_ant)
        {
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Buy Minima"))
            operou_vela = true;
        }
     }

   Comment("🟢 [SNIPER EXTREMOS + STOP DIÁRIO]\n",
           "Resultado Hoje: US$ ", DoubleToString(res_hoje, 2), " / Stop Diário: -US$ ", InpMaxLossDiarioUSD, "\n",
           "Status: ", (operou_vela ? "POSICIONADO (FECHA NO FIM DO CANDLE)" : "VIGIANDO MÁXIMA E MÍNIMA"), "\n",
           "Venda na Máx: ", iHigh(_Symbol, PERIOD_CURRENT, 1), " | Compra na Mín: ", iLow(_Symbol, PERIOD_CURRENT, 1));
  }

double ResultadoDia()
  {
   double tot = 0.0;
   if(HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent()))
     for(int i=0; i<HistoryDealsTotal(); i++)
       {
        ulong tk = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(tk, DEAL_MAGIC) == magic && HistoryDealGetString(tk, DEAL_SYMBOL) == _Symbol &&
           (HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_OUT || HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_INOUT))
          tot += HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
       }
   for(int i=PositionsTotal()-1; i>=0; i--)
     if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
       tot += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   return tot;
  }

void FecharTudo()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
       trade.PositionClose(PositionGetTicket(i));
  }
