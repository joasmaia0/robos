//+------------------------------------------------------------------+
//|                                   Ancora_Timeframe_Generico.mq5  |
//|                                           Engenheiro Chefe QG    |
//+------------------------------------------------------------------+
#property copyright "Engenheiro Chefe QG - 2026"
#property version   "29.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
// PAINEL CONFIGURÁVEL PURISTA (FILTRO EMA 50/200 + STOP DIÁRIO)
//====================================================================
input group      "--- PARÂMETROS DE CAPITAL E STOP LOSS ---"
input double     InpLotSize           = 0.01;  // Lote de Partida Real
input double     InpFracaoStopOpen    = 3.0;   // Margem do SL na abertura em décimos da vela anterior
input int        InpMinStopPontos     = 50;    // Distância mínima de segurança do SL (pontos)
input double     InpMaxLossDiarioUSD  = 30.00; // Perda máxima permitida no DIA (US$)

input group      "--- FILTRO DE TENDÊNCIA (MÉDIAS EXPONENCIAIS) ---"
input int        InpEmaRapida         = 50;    // Período da Média Rápida (EMA 50)
input int        InpEmaLenta          = 200;   // Período da Média Lenta (EMA 200)
input int        InpMinDistEmaPontos  = 20;    // Distância mínima entre EMA 50 e 200 para confirmar tendência

input group      "--- BLINDAGEM DE HORÁRIO E SPREAD ---"
input int        InpMaxSpread         = 2500;  // Spread máximo permitido (pontos)
input bool       InpBloquearFDS       = true;  // Bloquear Sábado e Domingo
input int        InpHoraInicioSegunda = 15;    // Início Segunda (15h MT5 = 10h00 Brasil)
input int        InpHoraFimSexta      = 23;    // Bloqueio Sexta (23h MT5 = 18h00 Brasil)

datetime hora_da_vela_atual = 0;
ulong    magic_number = 20260909;
int      operacao_vela = 0;

int      handle_ema50;
int      handle_ema200;

//+------------------------------------------------------------------+
//| Inicialização do Robô                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(magic_number);
   
   handle_ema50  = iMA(_Symbol, PERIOD_CURRENT, InpEmaRapida, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema200 = iMA(_Symbol, PERIOD_CURRENT, InpEmaLenta, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handle_ema50 == INVALID_HANDLE || handle_ema200 == INVALID_HANDLE)
     {
      Print("❌ Erro ao inicializar indicadores EMA!");
      return(INIT_FAILED);
     }
     
   hora_da_vela_atual = 0;
   operacao_vela = 0;
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
   // TRAVA 1: PERDA MÁXIMA DIÁRIA (US$ 30,00)
   //====================================================================
   double resultado_hoje = CalcularResultadoRealDoDia();
   if(resultado_hoje <= -MathAbs(InpMaxLossDiarioUSD))
     {
      FecharPosicoesAbertas();
      Comment("🛑 [STOP DIÁRIO ATINGIDO]\nPerda hoje: US$ ", DoubleToString(resultado_hoje, 2), ". Retorno automático amanhã.");
      return;
     }

   //====================================================================
   // TRAVA 2: ENCERRAMENTO FORÇADO NA SEXTA-FEIRA À NOITE
   //====================================================================
   if(tempo.day_of_week == 5 && tempo.hour >= InpHoraFimSexta)
     {
      FecharPosicoesAbertas();
      Comment("⏸️ [PAUSA SEXTA À NOITE]\nPosições zeradas para o fim de semana.");
      return;
     }

   datetime tempo_vela_viva = iTime(_Symbol, PERIOD_CURRENT, 0);

   //====================================================================
   // ETAPA 1: VELA VIRADA -> FECHA POSIÇÃO ANTERIOR E LIBERA NOVO TIRO
   //====================================================================
   if(hora_da_vela_atual != tempo_vela_viva)
     {
      FecharPosicoesAbertas();
      hora_da_vela_atual = tempo_vela_viva;
      operacao_vela = 0;
     }

   //====================================================================
   // ETAPA 2: FILTROS DE SEGURANÇA (FIM DE SEMANA E SPREAD)
   //====================================================================
   if(!HorarioPermitido(tempo))
     {
      Comment("⏸️ [HORÁRIO BLOQUEADO]\nAguardando abertura permitida (Segunda 10h00 Brasil / 15h00 Servidor).");
      return;
     }
   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpread) return;

   //====================================================================
   // ETAPA 3: LEITURA DA TENDÊNCIA (EMA 50 vs EMA 200)
   //====================================================================
   double ema50[], ema200[];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(ema200, true);
   
   if(CopyBuffer(handle_ema50, 0, 0, 2, ema50) < 2) return;
   if(CopyBuffer(handle_ema200, 0, 0, 2, ema200) < 2) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist_min_ema = InpMinDistEmaPontos * _Point;

   bool em_tendencia_alta  = (bid > ema200[0] && (ema50[0] - ema200[0]) >= dist_min_ema);
   bool em_tendencia_baixa = (ask < ema200[0] && (ema200[0] - ema50[0]) >= dist_min_ema);

   string status_mercado = "⚠️ MERCADO LATERALIZADO (AGUARDANDO DIREÇÃO)";
   if(em_tendencia_alta)  status_mercado = "📈 TENDÊNCIA DE ALTA (MODO COMPRA ATIVO)";
   if(em_tendencia_baixa) status_mercado = "📉 TENDÊNCIA DE BAIXA (MODO VENDA ATIVO)";

   //====================================================================
   // ETAPA 4: EXECUÇÃO DIRECIONAL (COMPRA NA ALTA / VENDA NA BAIXA)
   //====================================================================
   static datetime ultima_tentativa = 0;

   if(operacao_vela == 0 && (TimeCurrent() - ultima_tentativa) >= 15)
     {
      double close_anterior  = iClose(_Symbol, PERIOD_CURRENT, 1);
      double open_atual      = iOpen(_Symbol, PERIOD_CURRENT, 0);
      double maxima_anterior = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double minima_anterior = iLow(_Symbol, PERIOD_CURRENT, 1);
      double amp_anterior    = maxima_anterior - minima_anterior;

      double margem_stop = (amp_anterior / 10.0) * InpFracaoStopOpen;
      if(margem_stop < (InpMinStopPontos * _Point))
         margem_stop = InpMinStopPontos * _Point;

      long stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double min_broker = (stop_level + 10) * _Point;

      // 1. MODO COMPRA (TENDÊNCIA DE ALTA CONFIRMADA + ROMPEU CLOSE ANTERIOR)
      if(em_tendencia_alta && ask > close_anterior)
        {
         ultima_tentativa = TimeCurrent();
         double sl = NormalizeDouble(open_atual - margem_stop, _Digits);
         if((ask - sl) < min_broker) sl = NormalizeDouble(ask - min_broker, _Digits);

         if(trade.Buy(InpLotSize, _Symbol, ask, sl, 0, "Ancora Alta Buy"))
           {
            operacao_vela = 1;
           }
        }
      // 2. MODO VENDA (TENDÊNCIA DE BAIXA CONFIRMADA + CAIU ABAIXO DO CLOSE ANTERIOR)
      else if(em_tendencia_baixa && bid < close_anterior)
        {
         ultima_tentativa = TimeCurrent();
         double sl = NormalizeDouble(open_atual + margem_stop, _Digits);
         if((sl - bid) < min_broker) sl = NormalizeDouble(bid + min_broker, _Digits);

         if(trade.Sell(InpLotSize, _Symbol, bid, sl, 0, "Ancora Baixa Sell"))
           {
            operacao_vela = 1;
           }
        }
     }

   Comment("📡 [ÂNCORA GENÉRICO V29 - FILTRO EMA 50/200]\n",
           "Diagnóstico: ", status_mercado, "\n",
           "Resultado Hoje: US$ ", DoubleToString(resultado_hoje, 2), " / Stop Diário: -US$ ", InpMaxLossDiarioUSD, "\n",
           "Lote Fixo: ", InpLotSize);
  }

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
