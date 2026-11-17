//+------------------------------------------------------------------+
//|                                   Ancora_Timeframe_Generico.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "23.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL PURISTA (ASK > CLOSE_ANTERIOR + ANTI-SPAM)
//====================================================================
input group      "--- PARÂMETROS DE CAPITAL E PROTEÇÃO ---"
input double     InpLotSize           = 0.01;  // Lote de Partida Real
input bool       InpUsarStopDinamico  = false; // Ativar o gatilho_stop calculado na pedra?

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
   // ETAPA 3: GATILHO DE COMPRA ACIMA DO FECHAMENTO ANTERIOR (ANTI-SPAM)
   //====================================================================
   static datetime ultima_tentativa = 0;

   if(compra == 0 && (TimeCurrent() - ultima_tentativa) >= 15)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double close_anterior = iClose(_Symbol, PERIOD_CURRENT, 1);
      
      if(ask > close_anterior)
        {
         ultima_tentativa = TimeCurrent(); // Registra o horário para não repetir em milissegundos
         double sl = 0;
         if(InpUsarStopDinamico)
           {
            double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
            double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
            double tamanho_candle_anterior = maxima_anterior - minima_anterior;
            sl = NormalizeDouble(minima_anterior - (tamanho_candle_anterior / 3.0), _Digits);
           }

         if(trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "Estouro Close"))
           {
            compra = 1;
           }
        }
     }
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
