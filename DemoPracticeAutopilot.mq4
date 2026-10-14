#property strict
#property version "2.300"
#property description "Continuous practice; hard locked to one FP Markets DEMO login; maximum USD 500 practice risk basis. Unvalidated strategy."
#include <Codex/AutopilotCore.mqh>
#include <Codex/BudgetAdmission.mqh>
#include <Codex/ForwardCore.mqh>
#include <Codex/ProfitProtection.mqh>
#include <Codex/ResearchStats.mqh>
#include <Codex/SnapshotWriter.mqh>
#include <Codex/ExecutionTiming.mqh>
#include <Codex/ExecutionQuality.mqh>
#include <Codex/EntrySlippage.mqh>

input bool AutoEntries=false;
input double RiskPercent=3;
input double PracticeCapitalUSD=500;
input double MaximumLots=0.01;
input int CooldownMinutes=5;
input int MaximumHoldMinutes=20;
input double RoundTripFeePerLotUSD=7; // Conservative fee estimate until account costs are verified.
input int SlippagePoints=20;
input int EntryWindowSeconds=120;
input double MaxSpreadFraction=0.20;
input double EntryDriftATR=0.25;
input bool EnableForwardResearch=true;
// There is deliberately no cumulative loss or daily trade-count limit in this demo-only version.
const int MAGIC=2026101217;
const string PREFIX="DAP_";
const ENUM_TIMEFRAMES ENTRY_TF=PERIOD_M5;
const int ENTRY_SECONDS=300;
string symbols[2]={"XAUUSD","XAGUSD"};
string reasons[2]={"等待报价和已完成K线","等待报价和已完成K线"};
datetime attempted[2]={0,0},last_quote_time[2]={0,0},last_arrival[2]={0,0};
bool seen_new_quote[2]={false,false},working=false,have_owner=false;
string key="AP02.48530368.",mode="初始化";
datetime last_status=0,last_sync=0;
datetime last_history_request=0;
bool closed_this_cycle=false;
datetime last_metrics_flush=0;
int last_codes[2]={0,0},check_counts[2]={0,0};
datetime last_bars[2]={0,0},last_local_checks[2]={0,0},last_server_checks[2]={0,0};
double last_budgets[2]={-1,-1},last_minimum_risks[2]={-1,-1};
double spread_minimum_risks[2]={-1,-1},current_spreads[2]={-1,-1};
bool quotes_fresh[2]={false,false};
double admission_floors[2]={-1,-1},minimum_lots[2]={-1,-1};
int admission_codes[2]={AP_SPEC_INVALID,AP_SPEC_INVALID};
datetime last_draw=0;
int loaded_closed_count=0;double loaded_closed_net=0;

struct Spec
{
   double tick,value,point,minimum,step,maximum,spread,bid,ask,slip;
   int digits;
};

string Escape(string s)
{ StringReplace(s,"\\","\\\\");StringReplace(s,"\"","\\\"");StringReplace(s,"\r"," ");StringReplace(s,"\n"," ");return s; }
string K(const string field,const int ticket=0)
{return key+field+(ticket>0?"."+IntegerToString(ticket):"");}
bool Identity()
{return APIdentity(AccountInfoInteger(ACCOUNT_TRADE_MODE),AccountNumber(),AccountServer(),IsTesting()) && AccountCurrency()=="USD";}
string OwnerMarker(){return K("owner_chart_"+IntegerToString(ChartID()));}
bool Owner()
{
   // Chart IDs exceed double's exact integer range; store the exact ID in the variable NAME.
   return have_owner && GlobalVariableCheck(K("owner")) && GlobalVariableGet(K("owner"))==1 &&
      GlobalVariableCheck(OwnerMarker()) && GlobalVariableGet(OwnerMarker())==1;
}
bool MutationAllowed()
{
   return Identity() && Owner() && IsConnected() && IsTradeAllowed() && !IsTradeContextBusy() &&
      (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && (bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
bool Paused(){return GlobalVariableGet(K("pause"))>0 || GlobalVariableGet(K("halt"))>0;}
int IndexOf(const string symbol){for(int i=0;i<2;i++)if(symbols[i]==symbol)return i;return -1;}

void Event(const string action,const string symbol,const int ticket,const string details)
{
   int f=FileOpen("DemoAutopilot\\events.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){GlobalVariableSet(K("halt"),1);mode="暂停：无法写入交易记录";return;}
   if(FileSize(f)==0)FileWrite(f,"server_time","local_time","action","symbol","ticket","details");
   FileSeek(f,0,SEEK_END);
   FileWrite(f,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),action,symbol,ticket,details);
   FileFlush(f);FileClose(f);
   Print("DemoAutopilot: ",action," ",symbol," #",ticket," ",details);
}

string DK(const int index,const string field){return K("d04."+symbols[index]+"."+field);}
void CheckOutcome(const int index,const int code,const double minimum_risk=-1,const bool force=false)
{
   reasons[index]=AP08CheckText(code);
   datetime bar=iTime(symbols[index],ENTRY_TF,0);
   if(!force&&!APEntryWindow(bar,TimeCurrent(),EntryWindowSeconds))return;
   bool changed=APRecordChanged(last_bars[index],last_codes[index],bar,code);
   last_bars[index]=bar;last_codes[index]=code;
   last_local_checks[index]=TimeLocal();last_server_checks[index]=TimeCurrent();
   last_budgets[index]=APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent);
   last_minimum_risks[index]=minimum_risk;
   if(!changed)return;
   check_counts[index]++;
   GlobalVariableSet(DK(index,"bar"),(double)bar);GlobalVariableSet(DK(index,"code"),code);
   GlobalVariableSet(DK(index,"local"),(double)last_local_checks[index]);
   GlobalVariableSet(DK(index,"server"),(double)last_server_checks[index]);
   GlobalVariableSet(DK(index,"budget"),last_budgets[index]);
   GlobalVariableSet(DK(index,"min_risk"),minimum_risk);GlobalVariableSet(DK(index,"count"),check_counts[index]);
   GlobalVariablesFlush();
   Event(code==AP_FILLED?"CHECK_ACCEPTED":"CHECK_REJECTED",symbols[index],0,
      "v0.13 timeframe=M5 bar_server="+TimeToString(bar,TIME_DATE|TIME_MINUTES)+" code="+IntegerToString(code)+
      " reason="+AP08CheckText(code)+" budget_usd="+DoubleToString(last_budgets[index],4)+
      " minimum_structural_risk_usd="+(minimum_risk>=0?DoubleToString(minimum_risk,4):"unknown")+
      " spread_gate_risk_lower_bound_usd="+(quotes_fresh[index]?DoubleToString(spread_minimum_risks[index],4):"unknown"));
}
void RestoreChecks()
{
   for(int i=0;i<2;i++)
   {
      if(!GlobalVariableCheck(DK(i,"code")))continue;
      last_codes[i]=(int)GlobalVariableGet(DK(i,"code"));last_bars[i]=(datetime)GlobalVariableGet(DK(i,"bar"));
      last_local_checks[i]=(datetime)GlobalVariableGet(DK(i,"local"));
      last_server_checks[i]=(datetime)GlobalVariableGet(DK(i,"server"));
      last_budgets[i]=GlobalVariableGet(DK(i,"budget"));last_minimum_risks[i]=GlobalVariableGet(DK(i,"min_risk"));
      check_counts[i]=(int)GlobalVariableGet(DK(i,"count"));
   }
}
string VisibleReason(const int index)
{
   for(int oi=OrdersTotal()-1;oi>=0;oi--)
      if(OrderSelect(oi,SELECT_BY_POS,MODE_TRADES)&&IsOwnedSelected()&&OrderSymbol()==symbols[index])
         return quotes_fresh[index]?"本程序持仓中；报价更新中":"本程序持仓中；等待新鲜报价";
   if(!quotes_fresh[index])return "等待新鲜报价";
   if(admission_codes[index]==AP_COST_BUDGET)
      return "暂不可入场：最小单风险至少 $"+DoubleToString(admission_floors[index],2)+
         " > $"+DoubleToString(APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent),2);
   if(admission_codes[index]!=0)return AP08CheckText(admission_codes[index]);
   if(last_codes[index]==AP_FILLED)
   {
      int wait=(int)((datetime)GlobalVariableGet(K("last_close"))+CooldownMinutes*60-TimeCurrent());
      return wait>0?"上一笔已平仓；冷却剩 "+IntegerToString(wait)+" 秒":"上一笔已平仓；等待新信号";
   }
   if(reasons[index]=="等待下一次M5收盘触发" && last_codes[index]>0)
      return "等新K线；上次 "+AP08CheckText(last_codes[index]);
   return reasons[index];
}
string Metric(const double value){return MathIsValidNumber(value)&&value>=0?DoubleToString(value,6):"null";}
string CheckJson(const int index)
{
   return "{\"last_code\":"+IntegerToString(last_codes[index])+",\"last_reason\":\""+Escape(AP08CheckText(last_codes[index]))+
      "\",\"last_check_local\":\""+(last_local_checks[index]>0?TimeToString(last_local_checks[index],TIME_DATE|TIME_SECONDS):"")+
      "\",\"last_check_server\":\""+(last_server_checks[index]>0?TimeToString(last_server_checks[index],TIME_DATE|TIME_SECONDS):"")+
      "\",\"signal_bar_close_server\":\""+(last_bars[index]>0?TimeToString(last_bars[index],TIME_DATE|TIME_SECONDS):"")+
      "\",\"last_budget_usd\":"+Metric(last_budgets[index])+",\"last_minimum_structural_risk_usd\":"+Metric(last_minimum_risks[index])+
      ",\"recorded_outcome_changes\":"+IntegerToString(check_counts[index])+",\"quotes_fresh\":"+(quotes_fresh[index]?"true":"false")+
      ",\"m5_bars\":"+IntegerToString(iBars(symbols[index],ENTRY_TF))+",\"h1_bars\":"+IntegerToString(iBars(symbols[index],PERIOD_H1))+
      ",\"admission_code\":"+IntegerToString(quotes_fresh[index]?admission_codes[index]:AP_QUOTE)+
      ",\"admission_preflight_passes\":"+(quotes_fresh[index]&&admission_codes[index]==0?"true":"false")+
      ",\"admission_risk_floor_usd\":"+(quotes_fresh[index]?Metric(admission_floors[index]):"null")+
      ",\"minimum_lots\":"+(quotes_fresh[index]?Metric(minimum_lots[index]):"null")+
      ",\"current_explanation\":\""+Escape(VisibleReason(index))+"\""+
      ",\"current_spread_price\":"+(quotes_fresh[index]?Metric(current_spreads[index]):"null")+
      ",\"current_spread_gate_risk_lower_bound_usd\":"+(quotes_fresh[index]?Metric(spread_minimum_risks[index]):"null")+"}";
}

bool ReadSpec(const int index,Spec &s)
{
   string symbol=symbols[index];MqlTick q;
   if(!SymbolInfoTick(symbol,q)||!APFinitePositive(q.bid)||!APFinitePositive(q.ask)||q.ask<q.bid)return false;
   if(q.time!=last_quote_time[index])
   {
      if(last_quote_time[index]!=0)seen_new_quote[index]=true;
      last_quote_time[index]=q.time;last_arrival[index]=TimeLocal();
   }
   if(!seen_new_quote[index] || TimeLocal()-last_arrival[index]>5 || TimeCurrent()-q.time>5 || q.time>TimeCurrent()+2)return false;
   s.bid=q.bid;s.ask=q.ask;s.spread=q.ask-q.bid;
   s.tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   s.value=MarketInfo(symbol,MODE_TICKVALUE);s.point=MarketInfo(symbol,MODE_POINT);
   s.minimum=MarketInfo(symbol,MODE_MINLOT);s.step=MarketInfo(symbol,MODE_LOTSTEP);
   s.maximum=MarketInfo(symbol,MODE_MAXLOT);s.digits=(int)MarketInfo(symbol,MODE_DIGITS);
   s.slip=index==0?0.05:0.02;
   return APFinitePositive(s.tick)&&APFinitePositive(s.value)&&APFinitePositive(s.point)&&
          APFinitePositive(s.minimum)&&APFinitePositive(s.step)&&APFinitePositive(s.maximum);
}

bool IsOwnedSelected()
{return OrderMagicNumber()==MAGIC && IndexOf(OrderSymbol())>=0 && (OrderType()==OP_BUY||OrderType()==OP_SELL);}
int OwnedCount()
{
   int count=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)&&IsOwnedSelected())count++;
   return count;
}

bool ClosedJournalSelected()
{
   int ticket=OrderTicket();if(GlobalVariableCheck(K("journal_closed",ticket)))return true;
   int f=FileOpen("DemoAutopilot\\closed-trades.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){GlobalVariableSet(K("halt"),1);return false;}
   if(FileSize(f)==0)FileWrite(f,"ticket","symbol","side","lots","open_server","close_server","open_price","close_price",
      "profit","commission","swap","net_usd","reserved_r_usd","peak_observed_estimate_usd","worst_observed_estimate_usd",
      "initial_sl_recorded","initial_tp_recorded","final_sl","final_tp","exit_intent","metrics_since_v05","outside_protection_change_seen");
   FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,ticket,OrderSymbol(),OrderType()==OP_BUY?1:-1,DoubleToString(OrderLots(),8),
      TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
      DoubleToString(OrderOpenPrice(),8),DoubleToString(OrderClosePrice(),8),DoubleToString(OrderProfit(),4),
      DoubleToString(OrderCommission(),4),DoubleToString(OrderSwap(),4),DoubleToString(OrderProfit()+OrderCommission()+OrderSwap(),4),
      DoubleToString(GlobalVariableGet(K("initial_R",ticket)),4),DoubleToString(GlobalVariableGet(K("peak",ticket)),4),
      GlobalVariableCheck(K("worst",ticket))?DoubleToString(GlobalVariableGet(K("worst",ticket)),4):"unknown",
      GlobalVariableCheck(K("initial_sl",ticket))?DoubleToString(GlobalVariableGet(K("initial_sl",ticket)),8):"unknown",
      GlobalVariableCheck(K("initial_tp",ticket))?DoubleToString(GlobalVariableGet(K("initial_tp",ticket)),8):"unknown",
      DoubleToString(OrderStopLoss(),8),DoubleToString(OrderTakeProfit(),8),
      ExitReasonText((int)GlobalVariableGet(K("exit_intent",ticket))),GlobalVariableCheck(K("worst",ticket))?"true":"false",
      GlobalVariableGet(K("outside_change",ticket))>0?"true":"false");
   FileFlush(f);FileClose(f);
   if(written==0){GlobalVariableSet(K("halt"),1);return false;}
   GlobalVariableSet(K("journal_closed",ticket),1);return true;
}

void SyncClosed()
{
   loaded_closed_count=0;loaded_closed_net=0;
   datetime latest=(datetime)GlobalVariableGet(K("last_close"));
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)||!IsOwnedSelected()||OrderCloseTime()==0)continue;
      if(OrderCloseTime()>latest)latest=OrderCloseTime();
      loaded_closed_count++;loaded_closed_net+=OrderProfit()+OrderCommission()+OrderSwap();
      int ticket=OrderTicket();
      if(!GlobalVariableCheck(K("closed_logged",ticket)))
      {
         double net=OrderProfit()+OrderCommission()+OrderSwap();
         Event("CLOSED",OrderSymbol(),ticket,"net_usd="+DoubleToString(net,2)+" exit="+DoubleToString(OrderClosePrice(),(int)MarketInfo(OrderSymbol(),MODE_DIGITS)));
         GlobalVariableSet(K("closed_logged",ticket),1);
      }
      ClosedJournalSelected();
   }
   GlobalVariableSet(K("last_close"),(double)latest);
}

// A vanished live ticket must be confirmed in history before another order can be sent.
bool ReconcileFlat()
{
   if(OrdersTotal()!=0)return false;
   int ticket=(int)GlobalVariableGet(K("last_live_ticket"));
   if(ticket>0)
   {
      if(!OrderSelect(ticket,SELECT_BY_TICKET)||!IsOwnedSelected()||OrderCloseTime()==0)return false;
      datetime closed=OrderCloseTime(),latest=(datetime)GlobalVariableGet(K("last_close"));
      GlobalVariableSet(K("last_close"),(double)(closed>latest?closed:latest));
      GlobalVariableSet(K("last_live_ticket"),0);closed_this_cycle=true;
      SyncClosed();last_sync=TimeLocal();GlobalVariablesFlush();
   }
   return true;
}
bool EntryGate()
{
   if(!Identity()||!Owner()||OrdersTotal()!=0||Paused()||!AutoEntries)return false;
   bool reconciled=ReconcileFlat();
   return APEntryCycleReady(closed_this_cycle,reconciled,TimeCurrent(),(datetime)GlobalVariableGet(K("last_close")),CooldownMinutes);
}


datetime ActionReadyAt(const int ticket,const bool closing)
{
   return APActionReadyAt((datetime)GlobalVariableGet(K(closing?"close_after":"modify_after",ticket)),
      (datetime)GlobalVariableGet(K("channel_after",ticket)),
      (datetime)GlobalVariableGet(K("action_after",ticket))); // preserve any legacy in-flight retry deadline
}
string ExitReasonText(const int intent)
{return intent==AP_EXIT_GIVEBACK?"PROFIT_PROTECTION_GIVEBACK":APExitText(intent);}

bool SafeClose(const int ticket,const int requested)
{
   if(!Identity()||!Owner()||!OrderSelect(ticket,SELECT_BY_TICKET)||OrderCloseTime()!=0||!IsOwnedSelected())return false;
   int previous_intent=(int)GlobalVariableGet(K("exit_intent",ticket));
   int intent=APStickyExit(previous_intent,requested);
   if(intent!=previous_intent){GlobalVariableSet(K("exit_intent",ticket),intent);GlobalVariablesFlush();}
   if(TimeLocal()<ActionReadyAt(ticket,true))return false;
   if(!MutationAllowed())return false;
   string symbol=OrderSymbol();int index=IndexOf(symbol);Spec s;
   RefreshRates();
   if(!ReadSpec(index,s))return false;
   double lots=OrderLots(),price=OrderType()==OP_BUY?s.bid:s.ask;
   // The same account and ownership guards are rechecked immediately before every mutation.
   if(!MutationAllowed())return false;
   int eq_side=OrderType()==OP_BUY?1:-1;uint eq_started=GetTickCount();
   ResetLastError();bool ok=OrderClose(ticket,lots,price,SlippagePoints,clrNONE);int error=GetLastError();
   uint eq_elapsed=(uint)(GetTickCount()-eq_started);double eq_actual=0;
   if(ok)
   {
      // Persist immediately; SyncClosed's periodic scan was too late in v0.4.
      datetime closed=TimeCurrent();
      if(OrderSelect(ticket,SELECT_BY_TICKET)&&OrderCloseTime()>0){closed=OrderCloseTime();eq_actual=OrderClosePrice();}
      datetime latest=(datetime)GlobalVariableGet(K("last_close"));
      GlobalVariableSet(K("last_close"),(double)(closed>latest?closed:latest));
      closed_this_cycle=true;GlobalVariablesFlush();
   }
   EQRecord(false,symbol,ticket,eq_side,lots,price,eq_actual,ok,error,eq_elapsed,s.spread,lots*s.value/s.tick);
   Event(ok?"CLOSE_ACCEPTED":"CLOSE_FAILED",symbol,ticket,ExitReasonText(intent)+" error="+IntegerToString(error));
   GlobalVariableSet(K("close_after",ticket),(double)(TimeLocal()+(ok?1:APRetrySeconds(error))));
   GlobalVariablesFlush();
   return ok;
}

bool SafeTighten(const int ticket,const double target)
{
   if(!MutationAllowed()||!OrderSelect(ticket,SELECT_BY_TICKET)||OrderCloseTime()!=0||!IsOwnedSelected())return false;
   if(GlobalVariableGet(K("exit_intent",ticket))>0||TimeLocal()<ActionReadyAt(ticket,false))return false;
   int side=OrderType()==OP_BUY?1:-1,index=IndexOf(OrderSymbol());Spec s;
   if(!ReadSpec(index,s)||!APFinitePositive(OrderStopLoss())||!APFinitePositive(OrderTakeProfit()))return false;
   double old=OrderStopLoss();
   if((side==1&&target<=old+s.tick*.5)||(side==-1&&target>=old-s.tick*.5))return false;
   double minimum=(MathMax(MarketInfo(OrderSymbol(),MODE_STOPLEVEL),MarketInfo(OrderSymbol(),MODE_FREEZELEVEL))+1)*s.point;
   if((side==1&&target>=s.bid-minimum)||(side==-1&&target<=s.ask+minimum))return false;
   string symbol=OrderSymbol();double open=OrderOpenPrice(),tp=OrderTakeProfit();
   if(!MutationAllowed())return false;
   ResetLastError();bool ok=OrderModify(ticket,open,target,tp,0,clrNONE);int error=GetLastError();
   if(ok)
   {GlobalVariableSet(K("observed_sl",ticket),target);GlobalVariableSet(K("observed_tp",ticket),tp);GlobalVariablesFlush();}
   Event(ok?"SL_TIGHTEN_ACCEPTED":"SL_TIGHTEN_FAILED",symbol,ticket,"sl="+DoubleToString(target,s.digits)+" error="+IntegerToString(error));
   GlobalVariableSet(K("modify_after",ticket),(double)(TimeLocal()+(ok?1:MathMax(5,APRetrySeconds(error)))));
   if(!ok&&APModifyBlocksClose(error))
      GlobalVariableSet(K("channel_after",ticket),(double)(TimeLocal()+APRetrySeconds(error)));
   GlobalVariablesFlush();
   return ok;
}

void ObserveProtectionSelected()
{
   int ticket=OrderTicket();double sl=OrderStopLoss(),tp=OrderTakeProfit();
   if(GlobalVariableCheck(K("observed_sl",ticket)))
   {
      double old_sl=GlobalVariableGet(K("observed_sl",ticket)),old_tp=GlobalVariableGet(K("observed_tp",ticket));
      if(MathAbs(sl-old_sl)>1e-7||MathAbs(tp-old_tp)>1e-7)
      {
         GlobalVariableSet(K("outside_change",ticket),1);
         Event("PROTECTION_CHANGED_OUTSIDE_EA",OrderSymbol(),ticket,"old_sl="+DoubleToString(old_sl,8)+" new_sl="+DoubleToString(sl,8)+
            " old_tp="+DoubleToString(old_tp,8)+" new_tp="+DoubleToString(tp,8)+" actor_unknown; retain permitted user adjustment");
      }
   }
   GlobalVariableSet(K("observed_sl",ticket),sl);GlobalVariableSet(K("observed_tp",ticket),tp);
}

void Manage()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||!IsOwnedSelected())continue;
      int ticket=OrderTicket(),side=OrderType()==OP_BUY?1:-1,index=IndexOf(OrderSymbol());
      GlobalVariableSet(K("last_live_ticket"),ticket);
      ObserveProtectionSelected();
      Spec s;if(!ReadSpec(index,s))continue;
      if(GlobalVariableGet(K("flatten"))>0){SafeClose(ticket,AP_EXIT_USER);continue;}
      if(!APFinitePositive(OrderStopLoss())||!APFinitePositive(OrderTakeProfit()))
      {GlobalVariableSet(K("halt"),1);SafeClose(ticket,AP_EXIT_PROTECTION);continue;}
      if(!GlobalVariableCheck(K("initial_R",ticket)))
      {
         // A crash immediately after OrderSend can recover the prior persisted plan.
         double pending=GlobalVariableGet(K("pending_R"));
         if(APFinitePositive(pending))GlobalVariableSet(K("initial_R",ticket),pending);
         else{GlobalVariableSet(K("halt"),1);mode="暂停：持仓初始风险状态缺失";continue;}
      }
      double r=GlobalVariableGet(K("initial_R",ticket));
      double units=OrderLots()*s.value/s.tick;
      double cost=APConservativeCost(OrderLots(),RoundTripFeePerLotUSD,OrderCommission(),OrderSwap());
      if(cost<0){GlobalVariableSet(K("halt"),1);mode="费用数据异常，暂停新单";continue;}
      double remaining_risk=MathMax(0,side*(OrderOpenPrice()-OrderStopLoss()))*units+s.slip*units+cost;
      if(remaining_risk>r+0.01)
      {GlobalVariableSet(K("halt"),1);SafeClose(ticket,AP_EXIT_RISK);continue;}
      double price=side==1?s.bid:s.ask;
      double net=APNet(side,OrderOpenPrice(),price,units,cost);
      double peak=MathMax(net,GlobalVariableGet(K("peak",ticket)));
      GlobalVariableSet(K("peak",ticket),peak);
      double worst=GlobalVariableCheck(K("worst",ticket))?GlobalVariableGet(K("worst",ticket)):net;
      GlobalVariableSet(K("worst",ticket),MathMin(net,worst));
      if(TimeLocal()-last_metrics_flush>=5){GlobalVariablesFlush();last_metrics_flush=TimeLocal();}
      int intent=(int)GlobalVariableGet(K("exit_intent",ticket));
      if(intent>0){SafeClose(ticket,intent);continue;}
      if(APProtectedGiveback(peak,net,r)){SafeClose(ticket,AP_EXIT_GIVEBACK);continue;}
      if(MaximumHoldMinutes>0 && TimeCurrent()-OrderOpenTime()>=MaximumHoldMinutes*60)
      {SafeClose(ticket,AP_EXIT_TIME);continue;}
      if(TimeLocal()<ActionReadyAt(ticket,false))continue;
      if(APProtectedNet(peak,r)>=0)
      {
         double be=APProtectedStop(OrderOpenPrice(),units,cost,s.slip,s.tick,s.digits,side,peak,r);
         if(APFinitePositive(be))SafeTighten(ticket,be);
      }
   }
   if(OwnedCount()==0 && GlobalVariableGet(K("flatten"))>0)GlobalVariableSet(K("flatten"),0);
}

int Direction(const string symbol)
{
   double close=iClose(symbol,PERIOD_H1,1),fast=iMA(symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE,1);
   return APBias(close,fast);
}

double RecentStructure(const string symbol,const int side)
{
   // Extremes of three already closed M5 bars; never shorten this stop to fit a budget.
   double first=side==1?iLow(symbol,ENTRY_TF,1):iHigh(symbol,ENTRY_TF,1);
   double second=side==1?iLow(symbol,ENTRY_TF,2):iHigh(symbol,ENTRY_TF,2);
   double third=side==1?iLow(symbol,ENTRY_TF,3):iHigh(symbol,ENTRY_TF,3);
   return APRangeExtreme(first,second,third,side);
}
void RequestHistory()
{
   MqlRates rates[];
   for(int i=0;i<2;i++)
   {
      if(iBars(symbols[i],ENTRY_TF)<101)CopyRates(symbols[i],ENTRY_TF,0,120,rates);
      if(iBars(symbols[i],PERIOD_H1)<101)CopyRates(symbols[i],PERIOD_H1,0,120,rates);
   }
}

bool EntryJournal(const int index,const int ticket,const int side,const Spec &s,const double lots,
                  const double fill,const double sl,const double tp,const double risk,const double budget)
{
   string symbol=symbols[index];int f=FileOpen("DemoAutopilot\\entry-features.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){GlobalVariableSet(K("halt"),1);return false;}
   if(FileSize(f)==0)FileWrite(f,"version","stage","ticket","server_time","symbol","side","lots","fill","sl","tp","reserved_r","budget",
      "spread","tick","tick_value","m5_signal_start","m5_open","m5_close","previous_close","m5_ema20","m5_atr14","h1_signal_start","h1_close","h1_ema50");
   FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,"0.13",ticket>0?"filled":"plan",ticket,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),symbol,side,
      DoubleToString(lots,8),DoubleToString(fill,8),DoubleToString(sl,8),DoubleToString(tp,8),DoubleToString(risk,4),DoubleToString(budget,4),
      DoubleToString(s.spread,8),DoubleToString(s.tick,8),DoubleToString(s.value,8),
      TimeToString(iTime(symbol,ENTRY_TF,1),TIME_DATE|TIME_SECONDS),DoubleToString(iOpen(symbol,ENTRY_TF,1),8),
      DoubleToString(iClose(symbol,ENTRY_TF,1),8),DoubleToString(iClose(symbol,ENTRY_TF,2),8),
      DoubleToString(iMA(symbol,ENTRY_TF,20,0,MODE_EMA,PRICE_CLOSE,1),8),DoubleToString(iATR(symbol,ENTRY_TF,14,1),8),
      TimeToString(iTime(symbol,PERIOD_H1,1),TIME_DATE|TIME_SECONDS),DoubleToString(iClose(symbol,PERIOD_H1,1),8),
      DoubleToString(iMA(symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE,1),8));
   FileFlush(f);FileClose(f);if(written==0)GlobalVariableSet(K("halt"),1);return written>0;
}

void RefreshAdmission(const int index,const Spec &s)
{
   minimum_lots[index]=s.minimum;
   admission_floors[index]=APAdmissionRiskFloor(s.spread,MaxSpreadFraction,s.slip+APEntryReserve(SlippagePoints,s.point),s.tick,s.value,s.minimum,
      RoundTripFeePerLotUSD,MarketInfo(symbols[index],MODE_STOPLEVEL),s.point);
   admission_codes[index]=APAdmissionCode(admission_floors[index],
      APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent),s.minimum,MathMin(s.maximum,MaximumLots));
}

void TryEntry(const int index)
{
   if(!EntryGate())return;
   string symbol=symbols[index];Spec s;
   if(!ReadSpec(index,s)){CheckOutcome(index,AP_QUOTE);return;}
   if(iBars(symbol,PERIOD_H1)<101||iBars(symbol,ENTRY_TF)<101){CheckOutcome(index,AP_HISTORY);return;}
   datetime bar=iTime(symbol,ENTRY_TF,0),previous=iTime(symbol,ENTRY_TF,1);
   if(previous+ENTRY_SECONDS!=bar||!APEntryWindow(bar,TimeCurrent(),EntryWindowSeconds)){reasons[index]="等待下一次M5收盘触发";return;}
   RefreshAdmission(index,s);
   if(admission_codes[index]!=0){CheckOutcome(index,admission_codes[index]);return;}
   if(attempted[index]==bar || (datetime)GlobalVariableGet(K("bar_"+symbol))==bar){reasons[index]="本根K线已检查，等待新信号";return;}
   datetime h1_end=iTime(symbol,PERIOD_H1,1)+3600;
   if(h1_end>TimeCurrent()||TimeCurrent()-h1_end>=3600){CheckOutcome(index,AP_H1_STALE);return;}
   for(int j=1;j<5;j++)if(iTime(symbol,ENTRY_TF,j)-iTime(symbol,ENTRY_TF,j+1)!=ENTRY_SECONDS)
   {CheckOutcome(index,AP_GAP);return;}
   int side=Direction(symbol);
   if(side==0){CheckOutcome(index,AP_DIRECTION);return;}
   double close=iClose(symbol,ENTRY_TF,1),open=iOpen(symbol,ENTRY_TF,1);
   double ema=iMA(symbol,ENTRY_TF,20,0,MODE_EMA,PRICE_CLOSE,1),previous_close=iClose(symbol,ENTRY_TF,2);
   if(!APMomentum(side,open,close,previous_close,ema)){CheckOutcome(index,AP_TRIGGER);return;}
   double atr=iATR(symbol,ENTRY_TF,14,1),structure=RecentStructure(symbol,side);
   if(!APFinitePositive(atr)||!APFinitePositive(structure)){CheckOutcome(index,AP_STRUCTURE);return;}
   if(MathAbs(s.bid-close)>APDriftLimit(atr,s.tick,EntryDriftATR)){CheckOutcome(index,AP_DRIFT);return;}
   double structural_sl=APStop(structure,atr,side,s.spread,s.tick,s.digits),fill=side==1?s.ask:s.bid;
   double sl=APCostAwareInitialStop(structural_sl,fill,s.spread,MaxSpreadFraction,s.tick,s.digits,side);
   double distance=side*(fill-sl);
   if(!APFinitePositive(sl)||!APFinitePositive(distance)){CheckOutcome(index,AP_STOP);return;}
   double entry_reserve=APEntryReserve(SlippagePoints,s.point);
   if(entry_reserve<0){CheckOutcome(index,AP_SPEC_INVALID);return;}
   double minimum_risk=((distance+s.slip+entry_reserve)/s.tick*s.value+RoundTripFeePerLotUSD)*s.minimum;
   if(s.spread>MaxSpreadFraction*distance){CheckOutcome(index,AP_SPREAD,minimum_risk);return;}
   double budget=APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent);
   double lots=APLots(budget,distance,s.slip+entry_reserve,s.tick,s.value,s.minimum,s.step,MathMin(s.maximum,MaximumLots),RoundTripFeePerLotUSD);
   if(lots==0){CheckOutcome(index,AP_BUDGET,minimum_risk);return;}
   double tp=APPrice(fill+side*2*distance,s.tick,s.digits,side==1);
   double stop_distance=(MarketInfo(symbol,MODE_STOPLEVEL)+1)*s.point;
   if((side==1&&(s.bid-sl<stop_distance||tp-s.bid<stop_distance)) ||
      (side==-1&&(sl-s.ask<stop_distance||s.ask-tp<stop_distance)))
   {CheckOutcome(index,AP_STOP_LEVEL,minimum_risk);return;}
   int type=side==1?OP_BUY:OP_SELL;ResetLastError();
   double free=AccountFreeMarginCheck(symbol,type,lots);int margin_error=GetLastError();
   if(margin_error!=0||free<=0||MarketInfo(symbol,MODE_TRADEALLOWED)==0){CheckOutcome(index,AP_MARGIN,minimum_risk);return;}
   if(!MutationAllowed()||!EntryGate()){CheckOutcome(index,AP_PERMISSION,minimum_risk);return;}
   // Persist signal consumption before sending. Unknown execution errors NEVER trigger an immediate duplicate resend.
   attempted[index]=bar;GlobalVariableSet(K("bar_"+symbol),(double)bar);
   double risk=(distance+s.slip+entry_reserve)/s.tick*s.value*lots+RoundTripFeePerLotUSD*lots;
   GlobalVariableSet(K("pending_R"),risk);GlobalVariablesFlush();
   Event("ENTRY_PLAN",symbol,0,"side="+IntegerToString(side)+" lots="+DoubleToString(lots,8)+" risk_usd="+DoubleToString(risk,4)+" sl="+DoubleToString(sl,s.digits)+" tp="+DoubleToString(tp,s.digits));
   if(!EntryJournal(index,0,side,s,lots,fill,sl,tp,risk,budget))return;
   if(!MutationAllowed()||!EntryGate())return;
   uint eq_started=GetTickCount();
   ResetLastError();int ticket=OrderSend(symbol,type,lots,fill,SlippagePoints,sl,tp,"DemoAutopilot-v0.13",MAGIC,0,clrNONE);
   int error=GetLastError();uint eq_elapsed=(uint)(GetTickCount()-eq_started);
   if(ticket<0)
   {
      EQRecord(true,symbol,0,side,lots,fill,0,false,error,eq_elapsed,s.spread,lots*s.value/s.tick);
      Event("ENTRY_FAILED",symbol,0,"error="+IntegerToString(error));
      if(error==128||error==6){GlobalVariableSet(K("halt"),1);Event("HALT",symbol,0,"uncertain execution; inspect account before manual recovery");}
      CheckOutcome(index,AP_SEND_ERROR,minimum_risk,true);return;
   }
   GlobalVariableSet(K("initial_R",ticket),risk);GlobalVariableSet(K("peak",ticket),0);
   GlobalVariableSet(K("last_live_ticket"),ticket);GlobalVariablesFlush();
   Event("ENTRY_ACCEPTED",symbol,ticket,"server returned ticket");
   if(!OrderSelect(ticket,SELECT_BY_TICKET)||OrderCloseTime()!=0||!IsOwnedSelected())
   {GlobalVariableSet(K("halt"),1);Event("HALT",symbol,ticket,"cannot verify accepted ticket");return;}
   double eq_actual_fill=OrderOpenPrice(),eq_actual_lots=OrderLots();
   double actual=(MathAbs(OrderOpenPrice()-OrderStopLoss())+s.slip)/s.tick*s.value*OrderLots()+RoundTripFeePerLotUSD*OrderLots();
   GlobalVariableSet(K("initial_R",ticket),actual);
   GlobalVariableSet(K("initial_sl",ticket),OrderStopLoss());GlobalVariableSet(K("initial_tp",ticket),OrderTakeProfit());
   GlobalVariableSet(K("observed_sl",ticket),OrderStopLoss());GlobalVariableSet(K("observed_tp",ticket),OrderTakeProfit());
   GlobalVariablesFlush();
   EntryJournal(index,ticket,side,s,OrderLots(),OrderOpenPrice(),OrderStopLoss(),OrderTakeProfit(),actual,budget);
   if(!APFinitePositive(OrderStopLoss())||!APFinitePositive(OrderTakeProfit())||actual>budget+0.01)
   {GlobalVariableSet(K("halt"),1);SafeClose(ticket,AP_EXIT_FILL);}
   if(GlobalVariableGet(K("halt"))==0)EPStart(ticket,index,s);
   EQRecord(true,symbol,ticket,side,eq_actual_lots,fill,eq_actual_fill,true,0,eq_elapsed,s.spread,eq_actual_lots*s.value/s.tick);
   CheckOutcome(index,AP_FILLED,minimum_risk,true);
}

void Label(const string name,const string text,const int y)
{
   string obj=PREFIX+name;if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,24);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,obj,OBJPROP_COLOR,clrDarkSlateGray);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,10);ObjectSetInteger(0,obj,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,obj,OBJPROP_FONT,"Microsoft YaHei");ObjectSetString(0,obj,OBJPROP_TEXT,text);
}
void Button(const string name,const string text,const int x)
{
   string obj=PREFIX+name;if(ObjectFind(0,obj)<0)ObjectCreate(0,obj,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,204);ObjectSetInteger(0,obj,OBJPROP_XSIZE,235);ObjectSetInteger(0,obj,OBJPROP_YSIZE,30);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clrDarkSlateGray);ObjectSetInteger(0,obj,OBJPROP_BGCOLOR,clrWhiteSmoke);
   ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,10);ObjectSetString(0,obj,OBJPROP_FONT,"Microsoft YaHei");ObjectSetString(0,obj,OBJPROP_TEXT,text);
}

double OwnedFloatingNet()
{
   double result=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)&&IsOwnedSelected())result+=OrderProfit()+OrderCommission()+OrderSwap();
   return result;
}
string SignedMoney(const double value){return (value>=0?"+":"")+DoubleToString(value,2);}
string RuntimeDetail()
{
   if(!Identity()||!Owner())return "等待指定模拟账户和程序就绪";
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||!IsOwnedSelected())continue;
      int ticket=OrderTicket(),intent=(int)GlobalVariableGet(K("exit_intent",ticket));
      string pos=(OrderSymbol()==symbols[0]?"黄金":"白银")+(OrderType()==OP_BUY?"多单 ":"空单 ")+DoubleToString(OrderLots(),2)+"手";
      if(!IsConnected()||!quotes_fresh[IndexOf(OrderSymbol())])return pos+" | 行情中断；等待新报价";
      if(intent>0)return pos+" | 正在尝试平仓；重试等待 "+IntegerToString(APSecondsLeft(ActionReadyAt(ticket,true),TimeLocal()))+"秒";
      int left=APHoldSecondsLeft(OrderOpenTime(),TimeCurrent(),MaximumHoldMinutes);
      if(left==0)return pos+" | 持仓时限已到，等待平仓处理";
      return pos+(left<0?" | 实时管理":" | 最迟约 "+IntegerToString(left/60)+":"+(left%60<10?"0":"")+IntegerToString(left%60)+" 后尝试平仓");
   }
   if(!IsConnected())return "行情中断；等待连接恢复";
   if(Paused()||!AutoEntries)return "已暂停新单；持仓管理仍保留";
   int wait=APSecondsLeft((datetime)GlobalVariableGet(K("last_close"))+CooldownMinutes*60,TimeCurrent());
   return wait>0?"平仓冷却剩 "+IntegerToString(wait)+" 秒；继续观察":"空仓观察 | M5收盘找机会；同时一笔";
}

void Display()
{
   string bg=PREFIX+"bg";if(ObjectFind(0,bg)<0)ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);ObjectSetInteger(0,bg,OBJPROP_XSIZE,590);ObjectSetInteger(0,bg,OBJPROP_YSIZE,226);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrWhite);ObjectSetInteger(0,bg,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   Label("title","模拟练习 v0.13  |  杠杆1:"+IntegerToString(AccountLeverage())+"  |  "+mode,30);
   Label("balance",Identity()?"模拟余额 "+DoubleToString(AccountBalance(),2)+" |  练习预算 "+DoubleToString(PracticeCapitalUSD,0)+" |  计划风险≤"+DoubleToString(APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent),2)+" USD":"账户不匹配：禁止任何交易",57);
   Label("gold","黄金："+VisibleReason(0),84);Label("silver","白银："+VisibleReason(1),109);
   int next=APNextBarSeconds(iTime(symbols[0],ENTRY_TF,0),TimeCurrent(),ENTRY_SECONDS);
   Label("rule",RuntimeDetail(),137);
   Label("heartbeat","更新 "+TimeToString(TimeLocal(),TIME_SECONDS)+"  |  "+
      (IsConnected()&&quotes_fresh[0]&&next>=0?"下根M5约 "+IntegerToString(next/60)+":"+(next%60<10?"0":"")+IntegerToString(next%60):"等待行情恢复")+(EQPingMs()>0?" | 网络 "+DoubleToString(EQPingMs(),0)+"ms":""),181);
   Label("research","已平记录 "+IntegerToString(loaded_closed_count)+"笔 "+SignedMoney(loaded_closed_net)+" USD | 浮动 "+SignedMoney(OwnedFloatingNet())+" USD",158);
   Button("pause",Paused()?"继续模拟入场":"暂停新单（继续管理持仓）",24);
   Button("flatten","平仓并停止（本程序订单）",270);ChartRedraw();
}

string PositionsJson()
{
   string out="[";int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)||!IsOwnedSelected())continue;
      if(count++>0)out+=",";
      int ticket=OrderTicket();double r=GlobalVariableGet(K("initial_R",ticket)),peak=GlobalVariableGet(K("peak",ticket));
      double cost=APConservativeCost(OrderLots(),RoundTripFeePerLotUSD,OrderCommission(),OrderSwap());
      out+="{\"ticket\":"+IntegerToString(ticket)+",\"symbol\":\""+OrderSymbol()+"\",\"side\":\""+(OrderType()==OP_BUY?"buy":"sell")+"\""+
         ",\"lots\":"+DoubleToString(OrderLots(),8)+",\"open_price\":"+DoubleToString(OrderOpenPrice(),8)+
         ",\"stop_loss\":"+DoubleToString(OrderStopLoss(),8)+",\"take_profit\":"+DoubleToString(OrderTakeProfit(),8)+
         ",\"broker_net_floating_usd\":"+DoubleToString(OrderProfit()+OrderCommission()+OrderSwap(),4)+
         ",\"management_estimated_net_usd\":"+DoubleToString(OrderProfit()-cost,4)+",\"initial_planned_risk_usd\":"+Metric(r)+
         ",\"observed_peak_estimated_net_usd\":"+Metric(peak)+",\"desired_protected_net_usd\":"+Metric(APProtectedNet(peak,r))+
         ",\"exit_intent\":\""+Escape(ExitReasonText((int)GlobalVariableGet(K("exit_intent",ticket))))+"\""+
         ",\"close_retry_in_seconds\":"+IntegerToString(APSecondsLeft(ActionReadyAt(ticket,true),TimeLocal()))+
         ",\"modify_retry_in_seconds\":"+IntegerToString(APSecondsLeft(ActionReadyAt(ticket,false),TimeLocal()))+
         ",\"hold_seconds_remaining\":"+IntegerToString(APHoldSecondsLeft(OrderOpenTime(),TimeCurrent(),MaximumHoldMinutes))+
         ",\"held_seconds\":"+IntegerToString((int)(TimeCurrent()-OrderOpenTime()))+"}";
   }
   return out+"]";
}

void Status()
{
   // Persist fresh measurements at the existing five-second snapshot cadence.
   if(Identity()&&Owner())
   {
      for(int i=0;i<2;i++)if(last_local_checks[i]>0)
      {
         GlobalVariableSet(DK(i,"local"),(double)last_local_checks[i]);
         GlobalVariableSet(DK(i,"server"),(double)last_server_checks[i]);
         GlobalVariableSet(DK(i,"budget"),last_budgets[i]);
         GlobalVariableSet(DK(i,"min_risk"),last_minimum_risks[i]);
      }
      GlobalVariablesFlush();
   }
   string json="{\"version\":\"0.13\",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+
      "\",\"server_time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",\"expected_demo\":"+(Identity()?"true":"false")+
      ",\"connected\":"+(IsConnected()?"true":"false")+",\"trade_allowed\":"+(IsTradeAllowed()?"true":"false")+
      ",\"global_auto_trading\":"+((bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false")+
      ",\"expert_auto_trading\":"+((bool)MQLInfoInteger(MQL_TRADE_ALLOWED)?"true":"false")+
      ",\"trade_context_busy\":"+(IsTradeContextBusy()?"true":"false")+
      ",\"auto_entries_input\":"+(AutoEntries?"true":"false")+",\"paused\":"+(Paused()?"true":"false")+
      ",\"halt\":"+(GlobalVariableGet(K("halt"))>0?"true":"false")+",\"owner\":"+(Owner()?"true":"false")+
      ",\"mode\":\""+Escape(mode)+"\",\"balance\":"+DoubleToString(Identity()?AccountBalance():0,2)+
      ",\"equity\":"+DoubleToString(Identity()?AccountEquity():0,2)+",\"open_orders\":"+IntegerToString(OrdersTotal())+
      ",\"owned_open_orders\":"+IntegerToString(OwnedCount())+",\"risk_percent\":"+DoubleToString(RiskPercent,3)+
      ",\"login\":"+IntegerToString(AccountNumber())+",\"server\":\""+AccountServer()+"\",\"leverage\":"+IntegerToString(AccountLeverage())+
      ",\"practice_risk_capital_usd\":"+DoubleToString(PracticeCapitalUSD,2)+",\"maximum_planned_risk_usd\":"+DoubleToString(APPracticeBudget(AccountBalance(),AccountEquity(),PracticeCapitalUSD,RiskPercent),4)+
      ",\"risk_percent_basis\":\"practice_risk_capital\",\"round_trip_fee_estimate_per_lot_usd\":"+DoubleToString(RoundTripFeePerLotUSD,2)+
      ",\"cumulative_loss_cap\":null,\"profitability_validated\":false,\"news_filter_installed\":false,"+
      "\"opening_slip_reserve_basis\":\"SlippagePoints times symbol point; separate from exit reserve\",\"entry_timeframe_minutes\":5,\"cooldown_minutes\":"+IntegerToString(CooldownMinutes)+
      ",\"maximum_hold_minutes\":"+IntegerToString(MaximumHoldMinutes)+",\"entry_window_seconds\":"+IntegerToString(EntryWindowSeconds)+
      ",\"max_spread_fraction\":"+DoubleToString(MaxSpreadFraction,3)+","+
      "\"last_close_server\":\""+TimeToString((datetime)GlobalVariableGet(K("last_close")),TIME_DATE|TIME_SECONDS)+
      "\",\"last_known_ticket\":"+IntegerToString((int)GlobalVariableGet(K("last_live_ticket")))+","+
      "\"forward_research_enabled\":"+(EnableForwardResearch?"true":"false")+",\"automatic_strategy_promotion\":false,"+
      "\"management_cost_basis\":\"max(estimated_round_trip_fee,observed_commission)+negative_swap\","+
      "\"gold_reason\":\""+Escape(VisibleReason(0))+"\",\"silver_reason\":\""+Escape(VisibleReason(1))+"\","+
      "\"experimental_exit_policy\":true,\"break_even_trigger_r\":0.6,\"profit_trail_activation_r\":1.0,"+
      "\"aligned_forward_enabled\":"+(EnableForwardResearch?"true":"false")+",\"execution_quality\":"+EQJson()+",\"aligned_forward_health\":"+CFHealthJson()+",\"previous_admission_forward_health\":"+BFHealthJson()+",\"legacy_aligned_forward_health\":"+AFHealthJson()+","+
      "\"execution_retry_policy\":\"separate_close_modify_with_shared_transport_backoff\","+
      "\"runtime_detail\":\""+Escape(RuntimeDetail())+"\",\"performance\":{\"history_scope\":\"loaded_MT4_history_owned_market_orders\","+
      "\"closed_count\":"+IntegerToString(loaded_closed_count)+",\"realized_net_usd\":"+DoubleToString(loaded_closed_net,4)+
      ",\"broker_floating_net_usd\":"+DoubleToString(OwnedFloatingNet(),4)+"},"+
      "\"positions\":"+PositionsJson()+",\"exit_comparison_enabled\":"+(EnableForwardResearch?"true":"false")+","+
      "\"entry_checks\":{\"XAUUSD\":"+CheckJson(0)+",\"XAGUSD\":"+CheckJson(1)+"}}";
   if(!WriteSnapshot("DemoAutopilot\\status.json",json))Print("Status snapshot not published; previous snapshot may be stale.");
}

string PermissionMode()
{
   return RSPermissionText((bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),(bool)MQLInfoInteger(MQL_TRADE_ALLOWED),
      (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)&&(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT),IsTradeContextBusy());
}

void Cycle()
{
   if(working)return;working=true;closed_this_cycle=false;uint eq_cycle_start=GetTickCount();
   if(!Identity()||!Owner()||!IsConnected())
      for(int qi=0;qi<2;qi++){quotes_fresh[qi]=false;admission_codes[qi]=AP_SPEC_INVALID;admission_floors[qi]=-1;}
   if(!Identity())mode="账户不匹配，禁止交易";
   else if(!Owner())mode="重复实例，禁止交易";
   else if(!IsConnected())mode="断线；等待连接";
   else
   {
      if(TimeLocal()-last_history_request>=5){RequestHistory();last_history_request=TimeLocal();}
      Spec tmp;for(int i=0;i<2;i++)
      {
         quotes_fresh[i]=ReadSpec(i,tmp);
         if(quotes_fresh[i])
         {
            RefreshAdmission(i,tmp);
            current_spreads[i]=tmp.spread;
            spread_minimum_risks[i]=APMinimumRiskForSpread(tmp.spread,MaxSpreadFraction,tmp.slip+APEntryReserve(SlippagePoints,tmp.point),tmp.tick,tmp.value,tmp.minimum,RoundTripFeePerLotUSD);
         }
      }
      if(TimeLocal()-last_sync>=5){SyncClosed();last_sync=TimeLocal();}
      Manage();
      bool flat_reconciled=OrdersTotal()==0?ReconcileFlat():false;
      if(GlobalVariableGet(K("halt"))>0)mode="异常暂停，检查记录";
      else if(!IsTradeAllowed())mode=PermissionMode();
      else if(AccountLeverage()!=500)mode="杠杆不是1:500，暂停新单";
      else if(!AutoEntries||Paused())mode="暂停新单";
      else if(OrdersTotal()>0)mode=OwnedCount()>0?"持仓实时管理":"已有其他订单，暂停新单";
      else if(!flat_reconciled)mode="等待平仓记录确认";
      else if(!APEntryCycleReady(closed_this_cycle,flat_reconciled,TimeCurrent(),(datetime)GlobalVariableGet(K("last_close")),CooldownMinutes))mode="平仓后冷却，继续观察";
      else
      {
         mode="持续观察，条件满足才入场";
         for(int i=0;i<2;i++){TryEntry(i);if(OrdersTotal()>0)break;}
      }
   }
   // Broker position management and entries above always run before read-only research.
   LabCycle();EPCycle();AlignedCycle();AlignedCycle12();AlignedCycle13();
   if(TimeLocal()!=last_draw){Display();last_draw=TimeLocal();}
   if(TimeLocal()-last_status>=5){Status();last_status=TimeLocal();}
   eq_cycle_last_ms=(uint)(GetTickCount()-eq_cycle_start);if(eq_cycle_last_ms>eq_cycle_max_ms)eq_cycle_max_ms=eq_cycle_last_ms;
   working=false;
}

int OnInit()
{
   if(PracticeCapitalUSD<=0||PracticeCapitalUSD>500||RiskPercent<=0||RiskPercent>3||MaximumLots<=0||MaximumLots>0.01||CooldownMinutes<0||MaximumHoldMinutes<0||RoundTripFeePerLotUSD<0||SlippagePoints<0||
      EntryWindowSeconds<1||EntryWindowSeconds>180||MaxSpreadFraction<=0||MaxSpreadFraction>0.25||EntryDriftATR<=0||EntryDriftATR>0.5)
      return INIT_PARAMETERS_INCORRECT;
   FolderCreate("DemoAutopilot");
   if(!GlobalVariableCheck(K("owner"))&&!GlobalVariableTemp(K("owner")))return INIT_FAILED;
   have_owner=GlobalVariableCheck(OwnerMarker())&&GlobalVariableGet(OwnerMarker())==1&&GlobalVariableGet(K("owner"))==1;
   if(!have_owner)
   {
      have_owner=GlobalVariableSetOnCondition(K("owner"),1,0);
      if(have_owner)
      {
         if(!GlobalVariableCheck(OwnerMarker())&&!GlobalVariableTemp(OwnerMarker()))
         {GlobalVariableSet(K("owner"),0);have_owner=false;return INIT_FAILED;}
         GlobalVariableSet(OwnerMarker(),1);
      }
   }
   if(!have_owner){Print("DemoAutopilot duplicate instance rejected.");return INIT_FAILED;}
   if(!GlobalVariableCheck(K("pause")))GlobalVariableSet(K("pause"),0);
   if(!GlobalVariableCheck(K("halt")))GlobalVariableSet(K("halt"),0);
   if(!GlobalVariableCheck(K("flatten")))GlobalVariableSet(K("flatten"),0);
   for(int i=0;i<2;i++){SymbolSelect(symbols[i],true);attempted[i]=(datetime)GlobalVariableGet(K("bar_"+symbols[i]));}
   RestoreChecks();
   if(!EventSetTimer(1))return INIT_FAILED;
   Event("START","",0,"v0.13 execution retry isolation; clearer position and PnL status; unchanged v0.9 trial; demo login locked; risk="+DoubleToString(RiskPercent,2)+"%; auto_entries="+(AutoEntries?"true":"false"));
   Cycle();return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   CFShutdown();BFShutdown();AFShutdown();EPShutdown();FLShutdown();
   if(Owner())
   {
      Event("STOP","",0,"deinit_reason="+IntegerToString(reason));
      GlobalVariableSetOnCondition(K("owner"),0,1);GlobalVariableDel(OwnerMarker());
   }
   ObjectsDeleteAll(0,PREFIX);ChartRedraw();
}
void OnTick(){Cycle();}
void OnTimer(){Cycle();}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK||!Identity()||!Owner())return;
   if(sparam==PREFIX+"pause")
   {
      // Operational faults are not cleared by the ordinary resume button.
      if(GlobalVariableGet(K("halt"))>0){mode="异常仍在，请先检查交易记录";return;}
      GlobalVariableSet(K("pause"),GlobalVariableGet(K("pause"))>0?0:1);
      Event("PAUSE_TOGGLE","",0,GlobalVariableGet(K("pause"))>0?"paused":"resumed");
   }
   if(sparam==PREFIX+"flatten")
   {GlobalVariableSet(K("pause"),1);GlobalVariableSet(K("flatten"),1);Event("USER_FLATTEN","",0,"close only this program's demo orders and remain paused");}
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);GlobalVariablesFlush();Cycle();
}

const double LegacyResearchRiskPercent=1;
#define RiskPercent LegacyResearchRiskPercent
#include <Codex/ForwardLab.mqh>
#include <Codex/PortfolioLab.mqh>

#include <Codex/ExitComparison.mqh>

#include <Codex/AlignedForward.mqh>

#include <Codex/AlignedForward12.mqh>

#undef RiskPercent
#include <Codex/AlignedForward13.mqh>
