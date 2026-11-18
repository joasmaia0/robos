//+------------------------------------------------------------------+
//|                                   Ancora_Timeframe_Generico.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "22.60"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL PURISTA (ASK > CLOSE_ANTERIOR + STOP DIÁRIO)
//====================================================================
input group      "--- PARÂMETROS DE CAPITAL E PROTEÇÃO ---"
input double     InpLotSize           = 0.01;  // Lote de Partida Real
input double     InpMaxLossDiarioUSD  = 30.00; // Perda máxima permitida no DIA (US$)

input group      "--- BLINDAGEM DE HORÁRIO E SPREAD ---"
input int        InpMaxSpread         = 2500;  // Spread máximo permitido (pontos)
input bool       InpBloquearFDS       = true;  // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda = 15;    // Início Segunda (15h MT5 = 10h00 Brasil)
input int        InpHoraFimSexta      = 23;    // Bloqueio Sexta (23h MT5 = 18h00 Brasil)

datetime hora_da_vela_atual = 0;
ulong    magic_number = 20260909;
int      compra = 0;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   hora_da_vela_atual = 0;
   compra = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  { 
   MqlDateTime tempo;
   TimeCurrent(tempo);

   //====================================================================
   // TRAVA DE PERDA MÁXIMA DIÁRIA (US$ 30,00)
   //====================================================================
   if(CalcularResultadoRealDoDia() <= -MathAbs(InpMaxLossDiarioUSD))
     {
      FecharPosicoesAbertas();
      return;
     }

   // Encerramento forçado na Sexta-feira à noite
   if(tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta)
     {
      FecharPosicoesAbertas();
      return;
     }

   datetime tempo_vela_viva = iTime(_Symbol, PERIOD_CURRENT, 0);

   //====================================================================
   // ETAPA 1: VELA VIRADA -> FECHA TUDO PRIMEIRO E SÓ DEPOIS RESETA A TRAVA
   //====================================================================
   if(hora_da_vela_atual != tempo_vela_viva)
     {
      FecharPosicoesAbertas();
      hora_da_vela_atual = tempo_vela_viva;
      compra = 0;
     }

   //====================================================================
   // ETAPA 2: FILTROS DE SEGURANÇA (FIM DE SEMANA E SPREAD)
   //====================================================================
   if(!HorarioPermitido(tempo)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;

   //====================================================================
   // ETAPA 3: GATILHO DE COMPRA ACIMA DO FECHAMENTO ANTERIOR
   //====================================================================
   if(compra == 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double close_anterior = iClose(_Symbol, PERIOD_CURRENT, 1);
      
      if(ask > close_anterior)
        {
         if(trade.Buy(InpLotSize, _Symbol, ask, 0, 0, "Estouro Close"))
           {
            compra = 1;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calcula o lucro/perda real do dia (Fechado + Aberto)             |
//+------------------------------------------------------------------+
double CalcularResultadoRealDoDia()
  {
   datetime inicio_dia = iTime(_Symbol, PERIOD_D1, 0);
   double total_dia = 0.0;

   if(HistorySelect(inicio_dia, TimeCurrent()))
     {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magic_number && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
           {
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
              {
               total_dia += HistoryDealGetDouble(ticket, DEAL_PROFIT) 
                          + HistoryDealGetDouble(ticket, DEAL_SWAP) 
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
              }
           }
        }
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
        {
         total_dia += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
     }

   return total_dia;
  }

bool HorarioPermitido(MqlDateTime &tempo)
  {
   if(InpBloquearFDS && (tempo.day_of_week == 0 || tempo.day_of_week == 6)) return false;
   if(tempo.day_of_week == 1 && tempo.hour < InpHoraInicioSegunda) return false;
   if(tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta) return false;
   return true;
  }

void FecharPosicoesAbertas()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
        {
         trade.PositionClose(PositionGetTicket(i));
        }
     }
  }
