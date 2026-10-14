#ifndef CODEX_ALIGNED_FORWARD_V013
#define CODEX_ALIGNED_FORWARD_V013
#include <Codex/ForwardCore.mqh>
// Prospective virtual books only. No OrderSend, OrderModify or OrderClose calls.
const string CF_PROTOCOL="ALIGN13.R1";
const int CF_COLUMNS=53;
string cf_root="DemoAutopilot\\aligned-v013-";
double cf_initial_cash=0;
FLBook cf_books[6];long cf_campaign=0;
datetime cf_started=0,cf_last_cycle=0,cf_last_status=0,cf_checkpoint=0,cf_calendar=0;
bool cf_initialized=false,cf_fault=false;
string cf_signature="",cf_error="",cf_reasons[6]={"待初始化","待初始化","待初始化","待初始化","待初始化","待初始化"};
string CFName(const int model){return (model%3==0?"H1_BASE":model%3==1?"M15_FAST":"H1_M15_AGREE")+(model>=3?"_COST2":"_BASECOST");}
double CFFee(const int model){return RoundTripFeePerLotUSD*(model>=3?2:1);}
void CFStressSpec(const int model,Spec &s)
{
   if(model<3)return;
   double half=s.spread*.5;s.bid-=half;s.ask+=half;s.spread=s.ask-s.bid;s.slip*=2;
}
bool CFReadSpec(const int index,const int model,Spec &s)
{if(!ReadSpec(index,s))return false;CFStressSpec(model,s);return APFinitePositive(s.bid)&&s.ask>=s.bid;}
double CFBudget(const double cash)
{return APPracticeBudget(cash,cash,PracticeCapitalUSD,RiskPercent);}

string CFPath(const string suffix){return cf_root+IntegerToString(cf_campaign)+"-"+suffix;}
string CFParams()
{
   return CF_PROTOCOL+"|login=48530368|server=FPMarketsLtd-Demo2|practice_capital="+DoubleToString(PracticeCapitalUSD,8)+"|risk="+DoubleToString(RiskPercent,8)+"|lots="+DoubleToString(MaximumLots,8)+
      "|entry_slippage_points="+IntegerToString(SlippagePoints)+"|policy=v09|risk_basis=fixed_cap500|cash=broker_balance_at_start|stress=2x_spread_fee_slip|hold="+IntegerToString(MaximumHoldMinutes)+"|cool="+IntegerToString(CooldownMinutes)+
      "|fee="+DoubleToString(RoundTripFeePerLotUSD,8)+"|window="+IntegerToString(EntryWindowSeconds)+
      "|spread="+DoubleToString(MaxSpreadFraction,8)+"|drift="+DoubleToString(EntryDriftATR,8);
}
string CFNum(const double value){return DoubleToString(value,12);}
void CFFault(const string why){cf_fault=true;cf_error=why;Print("AlignedForward paused: ",why);}
bool CFSave(const int model,FLBook &p,const string action,const double net=0,const double stress=0,const double exit=0,const string why="")
{
   if(!FLStateValid(p)){CFFault("invalid experiment state");return false;}
   int f=FileOpen(CFPath("ledger.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){CFFault("cannot write experiment ledger");return false;}
   if(FileSize(f)==0)FileWrite(f,"protocol","campaign","seq","local_time","server_time","action","model","active","symbol_index","side",
      "opened_epoch","fill","sl","tp","lots","units","reserved_r","exit_slip","fee","peak","worst","last_close_epoch","cash",
      "closed_count","wins","gains","losses","stress_sum","max_drawdown","high_water","log_e_010","log_e_025","log_e_050","r_sum","score_sum",
      "gold_bar_epoch","silver_bar_epoch","initial_sl","event_net","event_stress_net","exit_price","exit_reason","m5_close","m5_ema20","m5_atr14",
      "h1_close","h1_ema50","m15_close","m15_ema20","m15_previous_ema20","entry_spread","parameter_signature","starting_cash");
   p.seq++;FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,CF_PROTOCOL,cf_campaign,p.seq,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      action,model,p.active?1:0,p.index,p.side,(long)p.opened,CFNum(p.fill),CFNum(p.sl),CFNum(p.tp),CFNum(p.lots),CFNum(p.units),CFNum(p.r),CFNum(p.slip),CFNum(p.fee),CFNum(p.peak),CFNum(p.worst),
      (long)p.last_close,CFNum(p.cash),p.n,p.wins,CFNum(p.gains),CFNum(p.losses),CFNum(p.stress_sum),CFNum(p.max_drawdown),CFNum(p.high_water),CFNum(p.log0),CFNum(p.log1),CFNum(p.log2),
      CFNum(p.r_sum),CFNum(p.score_sum),(long)p.bar_gold,(long)p.bar_silver,CFNum(p.initial_sl),CFNum(net),CFNum(stress),CFNum(exit),why,CFNum(p.m5_close),CFNum(p.m5_ema),CFNum(p.m5_atr),
      CFNum(p.h1_close),CFNum(p.h1_ema),CFNum(p.m15_close),CFNum(p.m15_ema),CFNum(p.m15_previous_ema),CFNum(p.spread),cf_signature,CFNum(p.start));
   FileFlush(f);FileClose(f);if(written==0){CFFault("experiment write returned zero");return false;}return true;
}
bool CFRestore()
{
   if(!FileIsExist(CFPath("ledger.csv")))return true;
   int f=FileOpen(CFPath("ledger.csv"),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){CFFault("cannot read experiment ledger");return false;}
   bool header=true;
   while(!FileIsEnding(f))
   {
      string row[];int count=0;
      while(!FileIsEnding(f)){ArrayResize(row,count+1);row[count++]=FileReadString(f);if(FileIsLineEnding(f))break;}
      if(count==1&&row[0]=="")continue;
      if(count!=CF_COLUMNS){FileClose(f);CFFault("incomplete ledger row; inspect before recovery");return false;}
      if(header){header=false;if(row[0]!="protocol"||row[52]!="starting_cash"){FileClose(f);CFFault("ledger schema mismatch");return false;}continue;}
      for(int k=1;k<CF_COLUMNS;k++)
      {
         if(k==3||k==4||k==5||k==41||k==51)continue;
         if(!FLNumberToken(row[k])){FileClose(f);CFFault("malformed numeric ledger field");return false;}
      }
      if(row[0]!=CF_PROTOCOL||StringToInteger(row[1])!=cf_campaign||row[51]!=cf_signature)
      {FileClose(f);CFFault("changed protocol or parameters; new campaign required");return false;}
      int model=(int)StringToInteger(row[6]);if(model<0||model>5){FileClose(f);CFFault("invalid model");return false;}
      FLBook p;ZeroMemory(p);
      p.seq=StringToInteger(row[2]);p.active=StringToInteger(row[7])==1;p.index=(int)StringToInteger(row[8]);p.side=(int)StringToInteger(row[9]);
      p.opened=(datetime)StringToInteger(row[10]);p.fill=StringToDouble(row[11]);p.sl=StringToDouble(row[12]);p.tp=StringToDouble(row[13]);
      p.lots=StringToDouble(row[14]);p.units=StringToDouble(row[15]);p.r=StringToDouble(row[16]);p.slip=StringToDouble(row[17]);p.fee=StringToDouble(row[18]);
      p.peak=StringToDouble(row[19]);p.worst=StringToDouble(row[20]);p.last_close=(datetime)StringToInteger(row[21]);p.cash=StringToDouble(row[22]);
      p.n=(int)StringToInteger(row[23]);p.wins=(int)StringToInteger(row[24]);p.gains=StringToDouble(row[25]);p.losses=StringToDouble(row[26]);
      p.stress_sum=StringToDouble(row[27]);p.max_drawdown=StringToDouble(row[28]);p.high_water=StringToDouble(row[29]);
      p.log0=StringToDouble(row[30]);p.log1=StringToDouble(row[31]);p.log2=StringToDouble(row[32]);p.r_sum=StringToDouble(row[33]);p.score_sum=StringToDouble(row[34]);
      p.bar_gold=(datetime)StringToInteger(row[35]);p.bar_silver=(datetime)StringToInteger(row[36]);p.initial_sl=StringToDouble(row[37]);
      p.m5_close=StringToDouble(row[42]);p.m5_ema=StringToDouble(row[43]);p.m5_atr=StringToDouble(row[44]);p.h1_close=StringToDouble(row[45]);p.h1_ema=StringToDouble(row[46]);
      p.m15_close=StringToDouble(row[47]);p.m15_ema=StringToDouble(row[48]);p.m15_previous_ema=StringToDouble(row[49]);p.spread=StringToDouble(row[50]);p.start=StringToDouble(row[52]);
      if(!FLStateValid(p)||MathAbs(p.start-cf_initial_cash)>1e-7||p.seq<=cf_books[model].seq){FileClose(f);CFFault("invalid or duplicate experiment sequence");return false;}
      cf_books[model]=p;
   }
   FileClose(f);return true;
}
bool CFInitialize()
{
   if(!Identity()||!Owner()||!IsConnected()||!APFinitePositive(AccountBalance()))return false;
   cf_signature=CFParams();string prefix="AAF13.48530368.";
   string campaign_file=cf_root+"campaign.csv";
   if(FileIsExist(campaign_file))
   {
      int meta=FileOpen(campaign_file,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){CFFault("cannot read campaign identity");return false;}
      string protocol=FileReadString(meta);string signature=FileReadString(meta);
      cf_campaign=StringToInteger(FileReadString(meta));cf_started=(datetime)StringToInteger(FileReadString(meta));cf_initial_cash=StringToDouble(FileReadString(meta));FileClose(meta);
      if(protocol!=CF_PROTOCOL||signature!=cf_signature){CFFault("campaign parameters differ; do not reset evidence");return false;}
   }
   else
   {
      cf_campaign=(long)TimeLocal();cf_started=TimeCurrent();cf_initial_cash=AccountBalance();
      int meta=FileOpen(campaign_file,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){CFFault("cannot persist campaign identity");return false;}
      uint written=FileWrite(meta,CF_PROTOCOL,cf_signature,cf_campaign,(long)cf_started,CFNum(cf_initial_cash));FileFlush(meta);FileClose(meta);
      if(written==0){CFFault("campaign identity write failed");return false;}
   }
   if(cf_campaign<=0||cf_started<=0||!APFinitePositive(cf_initial_cash)){CFFault("invalid campaign identity");return false;}
   GlobalVariableSet(prefix+"campaign",(double)cf_campaign);GlobalVariableSet(prefix+"started",(double)cf_started);GlobalVariablesFlush();
   for(int i=0;i<6;i++)FLInit(cf_books[i],cf_initial_cash);
   if(!CFRestore()||!CFRestoreCalendar())return false;
   for(int i=0;i<6;i++)if(cf_books[i].seq==0)
   {FLBook next=cf_books[i];if(!CFSave(i,next,"INITIAL"))return false;cf_books[i]=next;}
   cf_initialized=true;return true;
}
bool CFPlan(const int model,const int index,const Spec &s,FLBook &p)
{
   string symbol=symbols[index];datetime bar=iTime(symbol,PERIOD_M5,0);
   if(bar<=cf_started||!APEntryWindow(bar,TimeCurrent(),EntryWindowSeconds)){cf_reasons[model]="等新M5收盘";return false;}
   if(bar==(index==0?p.bar_gold:p.bar_silver)){cf_reasons[model]="本根已记录";return false;}
   if(iBars(symbol,PERIOD_M5)<101||iBars(symbol,PERIOD_H1)<101||iBars(symbol,PERIOD_M15)<101)
   {cf_reasons[model]="历史数据不足";return false;}
   for(int j=0;j<5;j++)if(iTime(symbol,PERIOD_M5,j)-iTime(symbol,PERIOD_M5,j+1)!=300)
   {cf_reasons[model]="K线不连续";return false;}
   datetime h1_end=iTime(symbol,PERIOD_H1,1)+3600,m15_end=iTime(symbol,PERIOD_M15,1)+900;
   if(h1_end>TimeCurrent()||TimeCurrent()-h1_end>=3600||m15_end>TimeCurrent()||TimeCurrent()-m15_end>=900)
   {cf_reasons[model]="方向数据未就绪";return false;}
   p.h1_close=iClose(symbol,PERIOD_H1,1);p.h1_ema=iMA(symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_close=iClose(symbol,PERIOD_M15,1);p.m15_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_previous_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,2);
   int side=FLDirection(model%3,APBias(p.h1_close,p.h1_ema),FLFastBias(p.m15_close,p.m15_ema,p.m15_previous_ema));
   p.m5_close=iClose(symbol,PERIOD_M5,1);p.m5_ema=iMA(symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE,1);
   if(side==0||!APMomentum(side,iOpen(symbol,PERIOD_M5,1),p.m5_close,iClose(symbol,PERIOD_M5,2),p.m5_ema))
   {cf_reasons[model]="方向或动量未满足";return false;}
   p.m5_atr=iATR(symbol,PERIOD_M5,14,1);double structure=RecentStructure(symbol,side);
   if(!APFinitePositive(p.m5_atr)||!APFinitePositive(structure)||MathAbs(s.bid-p.m5_close)>APDriftLimit(p.m5_atr,s.tick,EntryDriftATR))
   {cf_reasons[model]="结构或追价限制";return false;}
   double fill=side==1?s.ask:s.bid;
   double sl=APCostAwareInitialStop(APStop(structure,p.m5_atr,side,s.spread,s.tick,s.digits),fill,s.spread,MaxSpreadFraction,s.tick,s.digits,side);
   double distance=side*(fill-sl),budget=CFBudget(p.cash);
   if(!APFinitePositive(distance)||s.spread>MaxSpreadFraction*distance){cf_reasons[model]="止损或成本限制";return false;}
   double entry_reserve=APEntryReserve(SlippagePoints,s.point)*(model>=3?2:1);
   double lots=APLots(budget,distance,s.slip+entry_reserve,s.tick,s.value,s.minimum,s.step,MathMin(s.maximum,MaximumLots),CFFee(model));
   if(lots<=0){cf_reasons[model]="最小手数超预算";return false;}
   double tp=APPrice(fill+side*2*distance,s.tick,s.digits,side==1),minimum=(MarketInfo(symbol,MODE_STOPLEVEL)+1)*s.point;
   if((side==1&&(s.bid-sl<minimum||tp-s.bid<minimum))||(side==-1&&(sl-s.ask<minimum||s.ask-tp<minimum)))
   {cf_reasons[model]="服务器距离限制";return false;}
   double margin=MarketInfo(symbol,MODE_MARGINREQUIRED)*lots;
   if(!APFinitePositive(margin)||margin>=p.cash||MarketInfo(symbol,MODE_TRADEALLOWED)==0)
   {cf_reasons[model]="虚拟保证金或交易时段限制";return false;}
   p.active=true;p.index=index;p.side=side;p.opened=TimeCurrent();p.fill=fill;p.sl=sl;p.initial_sl=sl;p.tp=tp;
   p.lots=lots;p.units=lots*s.value/s.tick;p.slip=s.slip;p.fee=CFFee(model)*lots;
   p.r=(distance+s.slip)*p.units+p.fee;p.peak=0;p.worst=-s.spread*p.units-p.fee;p.spread=s.spread;
   if(index==0)p.bar_gold=bar;else p.bar_silver=bar;
   cf_reasons[model]="虚拟持仓观察";return FLStateValid(p);
}
string CFExitName(const int why){return why==FL_STOP?"STOP":why==FL_TARGET?"TARGET":why==FL_GIVEBACK?"GIVEBACK":why==FL_TIME?"TIME":"NONE";}
void CFManageBook(const int model)
{
   if(!cf_books[model].active)return;
   FLBook next=cf_books[model];Spec s;if(!CFReadSpec(next.index,model,s)){cf_reasons[model]="持仓等新鲜报价";return;}
   FLMark(next,s.bid,s.ask);int why=APProtectedExit(next,s.bid,s.ask,TimeCurrent(),MaximumHoldMinutes);
   if(why!=FL_NONE)
   {
      double exit=FLExitPrice(next,s.bid,s.ask,why),extra=(next.spread+next.slip)*next.units;
      double net=FLFinalize(next,exit,TimeCurrent());
      if(CFSave(model,next,"CLOSE",net,net-extra,exit,CFExitName(why)))cf_books[model]=next;
      cf_reasons[model]="虚拟平仓后冷却";return;
   }
   double minimum=(MathMax(MarketInfo(symbols[next.index],MODE_STOPLEVEL),MarketInfo(symbols[next.index],MODE_FREEZELEVEL))+1)*s.point;
   bool tightened=APProtectedTighten(next,s.bid,s.ask,s.tick,s.digits,minimum);
   if(tightened&&!CFSave(model,next,"BE"))return;
   cf_books[model]=next;cf_reasons[model]="虚拟持仓观察";
}

void CFCalendarSnapshot()
{
   datetime bar=iTime("XAUUSD",PERIOD_M5,0);if(bar<=cf_started||bar<=cf_calendar)return;
   double equity[6]={0,0,0,0,0,0};bool complete=true;
   for(int i=0;i<6;i++)
   {
      equity[i]=cf_books[i].cash;
      if(cf_books[i].active)
      {
         Spec s;if(!CFReadSpec(cf_books[i].index,i,s)){complete=false;continue;}
         FLBook p=cf_books[i];equity[i]+=FLMark(p,s.bid,s.ask)-p.slip*p.units;
      }
   }
   // The ledger checkpoints persist cf_calendar indirectly via a separate append-only calendar.
   int f=FileOpen(CFPath("calendar.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){CFFault("cannot write aligned calendar");return;}
   if(FileSize(f)==0)FileWrite(f,"campaign","bar_server","sample_server","sample_local","complete","h1_equity","m15_equity","agree_equity","h1_cost2_equity","m15_cost2_equity","agree_cost2_equity");
   FileSeek(f,0,SEEK_END);uint written=FileWrite(f,cf_campaign,(long)bar,(long)TimeCurrent(),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),complete?1:0,
      CFNum(equity[0]),CFNum(equity[1]),CFNum(equity[2]),CFNum(equity[3]),CFNum(equity[4]),CFNum(equity[5]));
   FileFlush(f);FileClose(f);if(written==0){CFFault("aligned calendar write failed");return;}cf_calendar=bar;
}
bool CFRestoreCalendar()
{
   if(!FileIsExist(CFPath("calendar.csv")))return true;
   int f=FileOpen(CFPath("calendar.csv"),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){CFFault("cannot restore aligned calendar");return false;}
   bool header=true;datetime last=0;
   while(!FileIsEnding(f))
   {
      string row[];int count=0;
      while(!FileIsEnding(f)){ArrayResize(row,count+1);row[count++]=FileReadString(f);if(FileIsLineEnding(f))break;}
      if(count==1&&row[0]=="")continue;
      if(count!=11){FileClose(f);CFFault("incomplete aligned calendar row");return false;}
      if(header){header=false;if(row[0]!="campaign"||row[10]!="agree_cost2_equity"){FileClose(f);CFFault("calendar schema mismatch");return false;}continue;}
      for(int k=0;k<11;k++)if(k!=3&&!FLNumberToken(row[k])){FileClose(f);CFFault("invalid calendar number");return false;}
      datetime bar=(datetime)StringToInteger(row[1]);
      if(StringToInteger(row[0])!=cf_campaign||bar<=last){FileClose(f);CFFault("calendar identity or ordering mismatch");return false;}
      last=bar;
   }
   FileClose(f);cf_calendar=last;return true;
}

string CFHealthJson()
{
   return "{\"initialized\":"+(cf_initialized?"true":"false")+",\"fault\":"+(cf_fault?"true":"false")+
      ",\"error\":\""+Escape(cf_error)+"\",\"campaign\":"+IntegerToString(cf_campaign)+",\"model_count\":6,\"automatic_promotion\":false}";
}
void CFStatus()
{
   string json="{\"version\":\"0.13\",\"protocol\":\""+CF_PROTOCOL+"\",\"campaign\":"+IntegerToString(cf_campaign)+
      ",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+"\",\"campaign_start_server\":\""+TimeToString(cf_started,TIME_DATE|TIME_SECONDS)+
      "\",\"fault\":"+(cf_fault?"true":"false")+",\"error\":\""+Escape(cf_error)+"\",\"actual_order_operations\":0,\"automatic_promotion\":false,\"profitability_validated\":false,"+
      "\"practice_risk_capital_usd\":"+CFNum(PracticeCapitalUSD)+",\"exit_policy\":\"v09_early_protection\",\"models\":[";
   for(int i=0;i<6;i++)
   {
      FLBook p=cf_books[i];if(i>0)json+=",";
      json+="{\"name\":\""+CFName(i)+"\",\"reason\":\""+Escape(cf_reasons[i])+"\",\"active_virtual\":"+(p.active?"true":"false")+
         ",\"closed_count\":"+IntegerToString(p.n)+",\"wins\":"+IntegerToString(p.wins)+",\"cash\":"+CFNum(p.cash)+",\"starting_cash\":"+CFNum(p.start)+
         ",\"net_usd\":"+CFNum(p.cash-p.start)+",\"gross_gains\":"+CFNum(p.gains)+",\"gross_losses\":"+CFNum(p.losses)+
         ",\"max_observed_mark_drawdown\":"+CFNum(p.max_drawdown)+",\"next_flat_risk_budget_usd\":"+CFNum(CFBudget(p.cash))+
         ",\"cost_multiplier\":"+IntegerToString(i>=3?2:1)+"}";
   }
   json+="],\"comparison_scope\":\"whole independent one-position virtual portfolios including entry admission, cooldown and exit timing\","+
      "\"fill_model\":\"observed quote entry, sampled stop gaps and adverse exit slip; no queue, partial fills, swaps or broker rejections\","+
      "\"stress_model\":\"2x spread symmetrically widened at same midpoint; 2x estimated fee and slip reserve; affects admission, marking, stops and sizing\","+
      "\"statistical_claim\":\"none; same-day few-trade rankings are descriptive only\"}";
   if(!WriteSnapshot(cf_root+"status.json",json))Print("Aligned snapshot unavailable; check freshness.");
}
string CFDisplay(){return !EnableForwardResearch?"研究对照关闭":cf_fault?"研究记录异常；原交易规则继续":cf_initialized?"研究：方向与单双仓对照；结果待验证":"研究：等待连接与初始化";}
void CFShutdown()
{

   if(!cf_initialized||cf_fault||!Identity()||!Owner())return;
   for(int m=0;m<6&&!cf_fault;m++)
   {FLBook next=cf_books[m];if(CFSave(m,next,"SHUTDOWN"))cf_books[m]=next;}
}
void AlignedCycle13()
{
   if(!EnableForwardResearch||!Identity()||!Owner()||!IsConnected())return;
   if(TimeLocal()==cf_last_cycle)return;cf_last_cycle=TimeLocal();
   if(!cf_initialized&&!cf_fault)CFInitialize();
   if(cf_initialized&&!cf_fault)
   {
      if(cf_signature!=CFParams())CFFault("parameters changed; start a new registered campaign");
      else
      {
         for(int i=0;i<2;i++)if(iBars(symbols[i],PERIOD_M15)<101){MqlRates rates[];CopyRates(symbols[i],PERIOD_M15,0,120,rates);}
         for(int m=0;m<6&&!cf_fault;m++)
         {
            bool was_active=cf_books[m].active;CFManageBook(m);
            if(was_active||cf_books[m].active||!AutoEntries||Paused()||!MutationAllowed()||AccountLeverage()!=500||!APCooldownReady(TimeCurrent(),cf_books[m].last_close,CooldownMinutes))continue;
            for(int s=0;s<2;s++)
            {
               Spec spec;if(!CFReadSpec(s,m,spec))continue;FLBook next=cf_books[m];
               if(CFPlan(m,s,spec,next)){if(CFSave(m,next,"OPEN"))cf_books[m]=next;break;}
            }
         }
         if(!cf_fault&&TimeLocal()-cf_checkpoint>=15)
         {
            for(int m=0;m<6&&!cf_fault;m++)if(cf_books[m].active)
            {FLBook next=cf_books[m];if(CFSave(m,next,"CHECKPOINT"))cf_books[m]=next;}
            cf_checkpoint=TimeLocal();
         }
         if(!cf_fault)CFCalendarSnapshot();
      }
   }
   if(TimeLocal()-cf_last_status>=5){CFStatus();cf_last_status=TimeLocal();}

}
#endif
