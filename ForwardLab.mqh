#ifndef CODEX_FORWARD_LAB
#define CODEX_FORWARD_LAB
#include <Codex/ForwardCore.mqh>
// Prospective virtual books only. No OrderSend, OrderModify or OrderClose calls.
const string FL_PROTOCOL="FWD06.R1";
const int FL_COLUMNS=53;
FLBook fl_books[3];long fl_campaign=0;
datetime fl_started=0,fl_last_cycle=0,fl_last_status=0,fl_checkpoint=0,fl_calendar=0;
bool fl_initialized=false,fl_fault=false;
string fl_signature="",fl_error="",fl_reasons[3]={"待初始化","待初始化","待初始化"};
string FLName(const int model){return model==0?"H1_BASE":model==1?"M15_FAST":"H1_M15_AGREE";}
string FLPath(const string suffix){return "DemoAutopilot\\lab-v06-"+IntegerToString(fl_campaign)+"-"+suffix;}
string FLParams()
{
   return FL_PROTOCOL+"|login=48530368|server=FPMarketsLtd-Demo2|practice_capital="+DoubleToString(PracticeCapitalUSD,8)+"|risk="+DoubleToString(RiskPercent,8)+"|lots="+DoubleToString(MaximumLots,8)+
      "|hold="+IntegerToString(MaximumHoldMinutes)+"|cool="+IntegerToString(CooldownMinutes)+
      "|fee="+DoubleToString(RoundTripFeePerLotUSD,8)+"|window="+IntegerToString(EntryWindowSeconds)+
      "|spread="+DoubleToString(MaxSpreadFraction,8)+"|drift="+DoubleToString(EntryDriftATR,8);
}
string FF(const double value){return DoubleToString(value,12);}
void FLFault(const string why){fl_fault=true;fl_error=why;Print("ForwardLab paused: ",why);}
bool FLSave(const int model,FLBook &p,const string action,const double net=0,const double stress=0,const double exit=0,const string why="")
{
   if(!FLStateValid(p)){FLFault("invalid experiment state");return false;}
   int f=FileOpen(FLPath("ledger.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){FLFault("cannot write experiment ledger");return false;}
   if(FileSize(f)==0)FileWrite(f,"protocol","campaign","seq","local_time","server_time","action","model","active","symbol_index","side",
      "opened_epoch","fill","sl","tp","lots","units","reserved_r","exit_slip","fee","peak","worst","last_close_epoch","cash",
      "closed_count","wins","gains","losses","stress_sum","max_drawdown","high_water","log_e_010","log_e_025","log_e_050","r_sum","score_sum",
      "gold_bar_epoch","silver_bar_epoch","initial_sl","event_net","event_stress_net","exit_price","exit_reason","m5_close","m5_ema20","m5_atr14",
      "h1_close","h1_ema50","m15_close","m15_ema20","m15_previous_ema20","entry_spread","parameter_signature","starting_cash");
   p.seq++;FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,FL_PROTOCOL,fl_campaign,p.seq,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      action,model,p.active?1:0,p.index,p.side,(long)p.opened,FF(p.fill),FF(p.sl),FF(p.tp),FF(p.lots),FF(p.units),FF(p.r),FF(p.slip),FF(p.fee),FF(p.peak),FF(p.worst),
      (long)p.last_close,FF(p.cash),p.n,p.wins,FF(p.gains),FF(p.losses),FF(p.stress_sum),FF(p.max_drawdown),FF(p.high_water),FF(p.log0),FF(p.log1),FF(p.log2),
      FF(p.r_sum),FF(p.score_sum),(long)p.bar_gold,(long)p.bar_silver,FF(p.initial_sl),FF(net),FF(stress),FF(exit),why,FF(p.m5_close),FF(p.m5_ema),FF(p.m5_atr),
      FF(p.h1_close),FF(p.h1_ema),FF(p.m15_close),FF(p.m15_ema),FF(p.m15_previous_ema),FF(p.spread),fl_signature,FF(p.start));
   FileFlush(f);FileClose(f);if(written==0){FLFault("experiment write returned zero");return false;}return true;
}
bool FLRestore()
{
   if(!FileIsExist(FLPath("ledger.csv")))return true;
   int f=FileOpen(FLPath("ledger.csv"),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){FLFault("cannot read experiment ledger");return false;}
   bool header=true;
   while(!FileIsEnding(f))
   {
      string row[];int count=0;
      while(!FileIsEnding(f)){ArrayResize(row,count+1);row[count++]=FileReadString(f);if(FileIsLineEnding(f))break;}
      if(count==1&&row[0]=="")continue;
      if(count!=FL_COLUMNS){FileClose(f);FLFault("incomplete ledger row; inspect before recovery");return false;}
      if(header){header=false;if(row[0]!="protocol"||row[52]!="starting_cash"){FileClose(f);FLFault("ledger schema mismatch");return false;}continue;}
      for(int k=1;k<FL_COLUMNS;k++)
      {
         if(k==3||k==4||k==5||k==41||k==51)continue;
         if(!FLNumberToken(row[k])){FileClose(f);FLFault("malformed numeric ledger field");return false;}
      }
      if(row[0]!=FL_PROTOCOL||StringToInteger(row[1])!=fl_campaign||row[51]!=fl_signature)
      {FileClose(f);FLFault("changed protocol or parameters; new campaign required");return false;}
      int model=(int)StringToInteger(row[6]);if(model<0||model>2){FileClose(f);FLFault("invalid model");return false;}
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
      if(!FLStateValid(p)||p.seq<=fl_books[model].seq){FileClose(f);FLFault("invalid or duplicate experiment sequence");return false;}
      fl_books[model]=p;
   }
   FileClose(f);return true;
}
bool FLInitialize()
{
   if(!Identity()||!Owner()||!IsConnected()||!APFinitePositive(AccountBalance()))return false;
   fl_signature=FLParams();string prefix="APL06.48530368.";
   string campaign_file="DemoAutopilot\\lab-v06-campaign.csv";
   if(FileIsExist(campaign_file))
   {
      int meta=FileOpen(campaign_file,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){FLFault("cannot read campaign identity");return false;}
      string protocol=FileReadString(meta);string signature=FileReadString(meta);
      fl_campaign=StringToInteger(FileReadString(meta));fl_started=(datetime)StringToInteger(FileReadString(meta));FileClose(meta);
      if(protocol!=FL_PROTOCOL||signature!=fl_signature){FLFault("campaign parameters differ; do not reset evidence");return false;}
   }
   else
   {
      fl_campaign=(long)TimeLocal();fl_started=TimeCurrent();
      int meta=FileOpen(campaign_file,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){FLFault("cannot persist campaign identity");return false;}
      uint written=FileWrite(meta,FL_PROTOCOL,fl_signature,fl_campaign,(long)fl_started);FileFlush(meta);FileClose(meta);
      if(written==0){FLFault("campaign identity write failed");return false;}
   }
   if(fl_campaign<=0||fl_started<=0){FLFault("invalid campaign identity");return false;}
   GlobalVariableSet(prefix+"campaign",(double)fl_campaign);GlobalVariableSet(prefix+"started",(double)fl_started);GlobalVariablesFlush();
   for(int i=0;i<3;i++)FLInit(fl_books[i],MathMin(PracticeCapitalUSD,AccountBalance()));
   if(!FLRestore())return false;
   for(int i=0;i<3;i++)if(fl_books[i].seq==0)
   {FLBook next=fl_books[i];if(!FLSave(i,next,"INITIAL"))return false;fl_books[i]=next;}
   fl_initialized=true;return true;
}
bool FLPlan(const int model,const int index,const Spec &s,FLBook &p)
{
   string symbol=symbols[index];datetime bar=iTime(symbol,PERIOD_M5,0);
   if(bar<=fl_started||!APEntryWindow(bar,TimeCurrent(),EntryWindowSeconds)){fl_reasons[model]="等新M5收盘";return false;}
   if(bar==(index==0?p.bar_gold:p.bar_silver)){fl_reasons[model]="本根已记录";return false;}
   if(iBars(symbol,PERIOD_M5)<101||iBars(symbol,PERIOD_H1)<101||iBars(symbol,PERIOD_M15)<101)
   {fl_reasons[model]="历史数据不足";return false;}
   for(int j=0;j<5;j++)if(iTime(symbol,PERIOD_M5,j)-iTime(symbol,PERIOD_M5,j+1)!=300)
   {fl_reasons[model]="K线不连续";return false;}
   datetime h1_end=iTime(symbol,PERIOD_H1,1)+3600,m15_end=iTime(symbol,PERIOD_M15,1)+900;
   if(h1_end>TimeCurrent()||TimeCurrent()-h1_end>=3600||m15_end>TimeCurrent()||TimeCurrent()-m15_end>=900)
   {fl_reasons[model]="方向数据未就绪";return false;}
   p.h1_close=iClose(symbol,PERIOD_H1,1);p.h1_ema=iMA(symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_close=iClose(symbol,PERIOD_M15,1);p.m15_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_previous_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,2);
   int side=FLDirection(model,APBias(p.h1_close,p.h1_ema),FLFastBias(p.m15_close,p.m15_ema,p.m15_previous_ema));
   p.m5_close=iClose(symbol,PERIOD_M5,1);p.m5_ema=iMA(symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE,1);
   if(side==0||!APMomentum(side,iOpen(symbol,PERIOD_M5,1),p.m5_close,iClose(symbol,PERIOD_M5,2),p.m5_ema))
   {fl_reasons[model]="方向或动量未满足";return false;}
   p.m5_atr=iATR(symbol,PERIOD_M5,14,1);double structure=RecentStructure(symbol,side);
   if(!APFinitePositive(p.m5_atr)||!APFinitePositive(structure)||MathAbs(s.bid-p.m5_close)>APDriftLimit(p.m5_atr,s.tick,EntryDriftATR))
   {fl_reasons[model]="结构或追价限制";return false;}
   double fill=side==1?s.ask:s.bid;
   double sl=APCostAwareInitialStop(APStop(structure,p.m5_atr,side,s.spread,s.tick,s.digits),fill,s.spread,MaxSpreadFraction,s.tick,s.digits,side);
   double distance=side*(fill-sl),budget=p.cash*RiskPercent/100;
   if(!APFinitePositive(distance)||s.spread>MaxSpreadFraction*distance){fl_reasons[model]="止损或成本限制";return false;}
   double lots=APLots(budget,distance,s.slip,s.tick,s.value,s.minimum,s.step,MathMin(s.maximum,MaximumLots),RoundTripFeePerLotUSD);
   if(lots<=0){fl_reasons[model]="最小手数超预算";return false;}
   double tp=APPrice(fill+side*2*distance,s.tick,s.digits,side==1),minimum=(MarketInfo(symbol,MODE_STOPLEVEL)+1)*s.point;
   if((side==1&&(s.bid-sl<minimum||tp-s.bid<minimum))||(side==-1&&(sl-s.ask<minimum||s.ask-tp<minimum)))
   {fl_reasons[model]="服务器距离限制";return false;}
   double margin=MarketInfo(symbol,MODE_MARGINREQUIRED)*lots;
   if(!APFinitePositive(margin)||margin>=p.cash||MarketInfo(symbol,MODE_TRADEALLOWED)==0)
   {fl_reasons[model]="虚拟保证金或交易时段限制";return false;}
   p.active=true;p.index=index;p.side=side;p.opened=TimeCurrent();p.fill=fill;p.sl=sl;p.initial_sl=sl;p.tp=tp;
   p.lots=lots;p.units=lots*s.value/s.tick;p.slip=s.slip;p.fee=RoundTripFeePerLotUSD*lots;
   p.r=(distance+s.slip)*p.units+p.fee;p.peak=0;p.worst=-s.spread*p.units-p.fee;p.spread=s.spread;
   if(index==0)p.bar_gold=bar;else p.bar_silver=bar;
   fl_reasons[model]="虚拟持仓观察";return FLStateValid(p);
}
string FLExitName(const int why){return why==FL_STOP?"STOP":why==FL_TARGET?"TARGET":why==FL_GIVEBACK?"GIVEBACK":why==FL_TIME?"TIME":"NONE";}
void FLManageBook(const int model)
{
   if(!fl_books[model].active)return;
   FLBook next=fl_books[model];Spec s;if(!ReadSpec(next.index,s)){fl_reasons[model]="持仓等新鲜报价";return;}
   FLMark(next,s.bid,s.ask);int why=FLExitChoice(next,s.bid,s.ask,TimeCurrent(),MaximumHoldMinutes);
   if(why!=FL_NONE)
   {
      double exit=FLExitPrice(next,s.bid,s.ask,why),extra=(next.spread+next.slip)*next.units;
      double net=FLFinalize(next,exit,TimeCurrent());
      if(FLSave(model,next,"CLOSE",net,net-extra,exit,FLExitName(why)))fl_books[model]=next;
      fl_reasons[model]="虚拟平仓后冷却";return;
   }
   double minimum=(MathMax(MarketInfo(symbols[next.index],MODE_STOPLEVEL),MarketInfo(symbols[next.index],MODE_FREEZELEVEL))+1)*s.point;
   bool tightened=FLTighten(next,s.bid,s.ask,s.tick,s.digits,minimum);
   if(tightened&&!FLSave(model,next,"BE"))return;
   fl_books[model]=next;fl_reasons[model]="虚拟持仓观察";
}
void FLCalendarSnapshot()
{
   datetime bar=iTime("XAUUSD",PERIOD_M5,0);if(bar<=fl_started||bar==fl_calendar)return;
   double equity[3]={0,0,0},stress[3]={0,0,0};bool complete=true;
   for(int i=0;i<3;i++)
   {
      equity[i]=fl_books[i].cash;stress[i]=fl_books[i].start+fl_books[i].stress_sum;
      if(fl_books[i].active)
      {
         Spec s;if(!ReadSpec(fl_books[i].index,s)){complete=false;continue;}
         FLBook p=fl_books[i];double floating=FLMark(p,s.bid,s.ask)-p.slip*p.units;
         equity[i]+=floating;stress[i]+=floating-(p.spread+p.slip)*p.units;
      }
   }
   int f=FileOpen(FLPath("calendar.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){FLFault("cannot write calendar comparison");return;}
   if(FileSize(f)==0)FileWrite(f,"campaign","bar_server","sample_server","sample_local","complete","h1_equity","m15_equity","agree_equity",
      "h1_stress_equity","m15_stress_equity","agree_stress_equity");
   FileSeek(f,0,SEEK_END);uint written=FileWrite(f,fl_campaign,(long)bar,(long)TimeCurrent(),TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),complete?1:0,
      FF(equity[0]),FF(equity[1]),FF(equity[2]),FF(stress[0]),FF(stress[1]),FF(stress[2]));
   FileFlush(f);FileClose(f);if(written==0){FLFault("calendar write failed");return;}fl_calendar=bar;
}
void FLStatus()
{
   string json="{\"version\":\"0.7\",\"protocol\":\""+FL_PROTOCOL+"\",\"campaign\":"+IntegerToString(fl_campaign)+
      ",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+"\",\"campaign_start_server\":\""+TimeToString(fl_started,TIME_DATE|TIME_SECONDS)+
      "\",\"fault\":"+(fl_fault?"true":"false")+",\"error\":\""+Escape(fl_error)+"\",\"actual_order_operations\":0,\"automatic_promotion\":false,"+
      "\"fill_model\":\"observed Bid/Ask entry; adverse exit slip reserve; TP capped at limit; stops fill at sampled quote after gaps; no queue or broker rejection model\","+
      "\"evidence_target\":\"conditional mean of bounded score R/(1+abs(R)); NOT raw dollar profit or strategy superiority\","+
      "\"family_threshold\":60,\"bayesian_assumption\":\"stationary independent Bernoulli win indicators; descriptive only; not verified\",\"models\":[";
   for(int i=0;i<3;i++)
   {
      FLBook p=fl_books[i];double log_e=FLLogMixture(p.log0,p.log1,p.log2);if(i>0)json+=",";
      double win_lower=0,win_upper=1;RSWinCS(p.wins,p.n,100,win_lower,win_upper);
      json+="{\"name\":\""+FLName(i)+"\",\"reason\":\""+Escape(fl_reasons[i])+"\",\"active_virtual\":"+(p.active?"true":"false")+
         ",\"closed_count\":"+IntegerToString(p.n)+",\"wins\":"+IntegerToString(p.wins)+",\"cash\":"+FF(p.cash)+",\"starting_cash\":"+FF(p.start)+
         ",\"net_usd\":"+FF(p.cash-p.start)+",\"stress_net_usd\":"+FF(p.stress_sum)+",\"gross_gains\":"+FF(p.gains)+",\"gross_losses\":"+FF(p.losses)+
         ",\"max_observed_mark_drawdown\":"+FF(p.max_drawdown)+",\"beta11_win_posterior_mean\":"+FF(FLPosteriorMean(p.wins,p.n))+
         ",\"win_rate_confidence_sequence_99\":["+FF(win_lower)+","+FF(win_upper)+"],\"win_cs_assumption\":\"constant conditional Bernoulli win probability; not verified; separate diagnostic family\""+
         ",\"log_e_mixture\":"+FF(log_e)+",\"e_mixture\":"+(log_e<690?FF(MathExp(log_e)):"null")+
         ",\"review_hint\":"+(p.n>=50&&p.cash>p.start&&p.stress_sum>0&&log_e>=MathLog(60)?"true":"false")+"}";
   }
   if(!WriteSnapshot("DemoAutopilot\\research-status.json",json+"]}"))Print("Research snapshot not published; check freshness.");
}
string FLDisplay(){return !EnableForwardResearch?"研究对照关闭":fl_fault?"研究记录异常；原交易规则继续":fl_initialized?"研究：方向与单双仓对照；结果待验证":"研究：等待连接与初始化";}
void FLShutdown()
{
   PLShutdown();
   if(!fl_initialized||fl_fault||!Identity()||!Owner())return;
   for(int m=0;m<3&&!fl_fault;m++)
   {FLBook next=fl_books[m];if(FLSave(m,next,"SHUTDOWN"))fl_books[m]=next;}
}
void LabCycle()
{
   if(!EnableForwardResearch||!Identity()||!Owner()||!IsConnected())return;
   if(TimeLocal()==fl_last_cycle)return;fl_last_cycle=TimeLocal();
   if(!fl_initialized&&!fl_fault)FLInitialize();
   if(fl_initialized&&!fl_fault)
   {
      if(fl_signature!=FLParams())FLFault("parameters changed; start a new registered campaign");
      else
      {
         for(int i=0;i<2;i++)if(iBars(symbols[i],PERIOD_M15)<101){MqlRates rates[];CopyRates(symbols[i],PERIOD_M15,0,120,rates);}
         for(int m=0;m<3&&!fl_fault;m++)
         {
            bool was_active=fl_books[m].active;FLManageBook(m);
            if(was_active||fl_books[m].active||!AutoEntries||Paused()||!APCooldownReady(TimeCurrent(),fl_books[m].last_close,CooldownMinutes))continue;
            for(int s=0;s<2;s++)
            {
               Spec spec;if(!ReadSpec(s,spec))continue;FLBook next=fl_books[m];
               if(FLPlan(m,s,spec,next)){if(FLSave(m,next,"OPEN"))fl_books[m]=next;break;}
            }
         }
         if(!fl_fault&&TimeLocal()-fl_checkpoint>=15)
         {
            for(int m=0;m<3&&!fl_fault;m++)if(fl_books[m].active)
            {FLBook next=fl_books[m];if(FLSave(m,next,"CHECKPOINT"))fl_books[m]=next;}
            fl_checkpoint=TimeLocal();
         }
         if(!fl_fault)FLCalendarSnapshot();
      }
   }
   if(TimeLocal()-fl_last_status>=5){FLStatus();fl_last_status=TimeLocal();}
   PortfolioCycle();
}
#endif
