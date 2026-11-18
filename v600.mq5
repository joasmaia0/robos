//+------------------------------------------------------------------+
//|                                   Ancora_Timeframe_Generico.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "25.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL PURISTA (VENDA CLOSE + STOP DIÁRIO US$ 30)
//====================================================================
input group      "--- PARÂMETROS DE CAPITAL E PROTEÇÃO ---"
input double     InpLotSize           = 0.01;  // Lote de Partida Real
input double     InpMaxLossDiarioUSD  = 30.00; // Perda máxima permitida no DIA (US$)
input bool       InpUsarStopDinamico  = false; // Ativar o stop calculado na pedra?

input group      "--- BLINDAGEM DE HORÁRIO E SPREAD ---"
input int        InpMaxSpread         = 2500;  // Spread máximo permitido (pontos)
input bool       InpBloquearFDS       = true;  // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda = 15;    // Início Segunda (15h MT5 = 10h00 Brasil)
input int        InpHoraFimSexta      = 23;    // Bloqueio Sexta (23h MT5 = 18h00 Brasil)

datetime hora_da_vela_atual = 0;
ulong    magic_number = 20260909;
int      venda = 0;

int      dia_controle = -1;
double   lucro_fechado_dia = 0.0;
bool     stop_diario_acionado = false;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   hora_da_vela_atual = 0;
   venda = 0;
   dia_controle = -1;
   lucro_fechado_dia = 0.0;
   stop_diario_acionado = false;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Função Principal a cada Tique                                    |
//+------------------------------------------------------------------+
void OnTick()
  { 
   MqlDateTime tempo;
   TimeCurrent(tempo);

   // Reinicia o contador de lucro/prejuízo na virada do dia do servidor
   if(dia_controle != tempo.day_of_year)
     {
      dia_controle = tempo.day_of_year;
      lucro_fechado_dia = 0.0;
      stop_diario_acionado = false;
     }

   // Calcula o lucro/prejuízo flutuante das posições abertas deste robô
   double lucro_flutuante = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic_number)
        {
         lucro_flutuante += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
     }

   //====================================================================
   // ETAPA 0: AUDITORIA DO STOP LOSS DIÁRIO DE US$ 30,00
   //====================================================================
   if(!stop_diario_acionado && (lucro_fechado_dia + lucro_flutuante) <= -MathAbs(InpMaxLossDiarioUSD))
     {
      Print("🛑 [STOP DIÁRIO] Limite de perda de US$ ", InpMaxLossDiarioUSD, " atingido! Pausando até amanhã.");
      stop_diario_acionado = true;
      FecharPosicoesAbertas();
      return;
     }

   if(stop_diario_acionado)
     {
      Comment("🛑 [STOP DIÁRIO ACIONADO]\nPerda máxima de US$ ", InpMaxLossDiarioUSD, " atingida hoje. Retorno automático amanhã.");
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
      venda = 0;
     }

   //====================================================================
   // ETAPA 2: FILTROS DE SEGURANÇA (FIM DE SEMANA E SPREAD)
   //====================================================================
   if(!HorarioPermitido(tempo)) return;
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;

   //====================================================================
   // ETAPA 3: GATILHO DE VENDA ABAIXO DO FECHAMENTO ANTERIOR (ANTI-SPAM)
   //====================================================================
   static datetime ultima_tentativa = 0;

   if(venda == 0 && (TimeCurrent() - ultima_tentativa) >= 15)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double close_anterior = iClose(_Symbol, PERIOD_CURRENT, 1);
      
      if(bid < close_anterior)
        {
         ultima_tentativa = TimeCurrent();
         double sl = 0;
         if(InpUsarStopDinamico)
           {
            double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
            double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
            double tamanho_candle_anterior = maxima_anterior - minima_anterior;
            sl = NormalizeDouble(maxima_anterior + (tamanho_candle_anterior / 3.0), _Digits);
           }

         if(trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "Estouro Close Sell"))
           {
            venda = 1;
           }
        }
     }

   Comment("🟢 [ÂNCORA GENÉRICO - VENDA CLOSE]\n",
           "Resultado do Dia: US$ ", DoubleToString(lucro_fechado_dia + lucro_flutuante, 2), " / Stop Diário: -US$ ", InpMaxLossDiarioUSD, "\n",
           "Lote Fixo: ", InpLotSize);
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
         double res = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(trade.PositionClose(PositionGetTicket(i)))
           {
            lucro_fechado_dia += res;
           }
        }
     }
  }
