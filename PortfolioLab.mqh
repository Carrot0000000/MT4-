
#ifndef CODEX_PORTFOLIO_LAB
#define CODEX_PORTFOLIO_LAB
// Entirely virtual; server order controller retains its one-position limit.
const string PL_PROTOCOL="DUAL07.R1";
const int PL_COLUMNS=53;
FLBook pl_books[3];long pl_campaign=0;
datetime pl_started=0,pl_last_cycle=0,pl_last_status=0,pl_checkpoint=0,pl_calendar=0;
bool pl_initialized=false,pl_fault=false;
string pl_signature="",pl_error="",pl_reasons[3]={"待初始化","待初始化","待初始化"};
string PLPath(const string suffix){return "DemoAutopilot\\dual-v07-"+IntegerToString(pl_campaign)+"-"+suffix;}
string PLParams(){return PL_PROTOCOL+"|shared_total_risk|max_two|h1|"+FLParams();}
void PLFault(const string why){pl_fault=true;pl_error=why;Print("PortfolioLab paused: ",why);}
bool PLSave(const int model,FLBook &p,const string action,const double net=0,const double stress=0,const double exit=0,const string why="")
{
   if(!FLStateValid(p)){PLFault("invalid experiment state");return false;}
   int f=FileOpen(PLPath("ledger.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){PLFault("cannot write experiment ledger");return false;}
   if(FileSize(f)==0)FileWrite(f,"protocol","campaign","seq","local_time","server_time","action","model","active","symbol_index","side",
      "opened_epoch","fill","sl","tp","lots","units","reserved_r","exit_slip","fee","peak","worst","last_close_epoch","cash",
      "closed_count","wins","gains","losses","stress_sum","max_drawdown","high_water","log_e_010","log_e_025","log_e_050","r_sum","score_sum",
      "gold_bar_epoch","silver_bar_epoch","initial_sl","event_net","event_stress_net","exit_price","exit_reason","m5_close","m5_ema20","m5_atr14",
      "h1_close","h1_ema50","m15_close","m15_ema20","m15_previous_ema20","entry_spread","parameter_signature","starting_cash");
   p.seq++;FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,PL_PROTOCOL,pl_campaign,p.seq,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      action,model,p.active?1:0,p.index,p.side,(long)p.opened,FF(p.fill),FF(p.sl),FF(p.tp),FF(p.lots),FF(p.units),FF(p.r),FF(p.slip),FF(p.fee),FF(p.peak),FF(p.worst),
      (long)p.last_close,FF(p.cash),p.n,p.wins,FF(p.gains),FF(p.losses),FF(p.stress_sum),FF(p.max_drawdown),FF(p.high_water),FF(p.log0),FF(p.log1),FF(p.log2),
      FF(p.r_sum),FF(p.score_sum),(long)p.bar_gold,(long)p.bar_silver,FF(p.initial_sl),FF(net),FF(stress),FF(exit),why,FF(p.m5_close),FF(p.m5_ema),FF(p.m5_atr),
      FF(p.h1_close),FF(p.h1_ema),FF(p.m15_close),FF(p.m15_ema),FF(p.m15_previous_ema),FF(p.spread),pl_signature,FF(p.start));
   FileFlush(f);FileClose(f);if(written==0){PLFault("experiment write returned zero");return false;}return true;
}

bool PLRestore()
{
   if(!FileIsExist(PLPath("ledger.csv")))return true;
   int f=FileOpen(PLPath("ledger.csv"),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){PLFault("cannot read experiment ledger");return false;}
   bool header=true;
   while(!FileIsEnding(f))
   {
      string row[];int count=0;
      while(!FileIsEnding(f)){ArrayResize(row,count+1);row[count++]=FileReadString(f);if(FileIsLineEnding(f))break;}
      if(count==1&&row[0]=="")continue;
      if(count!=PL_COLUMNS){FileClose(f);PLFault("incomplete ledger row; inspect before recovery");return false;}
      if(header){header=false;if(row[0]!="protocol"||row[52]!="starting_cash"){FileClose(f);PLFault("ledger schema mismatch");return false;}continue;}
      for(int k=1;k<PL_COLUMNS;k++)
      {
         if(k==3||k==4||k==5||k==41||k==51)continue;
         if(!FLNumberToken(row[k])){FileClose(f);PLFault("malformed numeric ledger field");return false;}
      }
      if(row[0]!=PL_PROTOCOL||StringToInteger(row[1])!=pl_campaign||row[51]!=pl_signature)
      {FileClose(f);PLFault("changed protocol or parameters; new campaign required");return false;}
      int model=(int)StringToInteger(row[6]);if(model<0||model>2){FileClose(f);PLFault("invalid model");return false;}
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
      if(!FLStateValid(p)||p.seq<=pl_books[model].seq){FileClose(f);PLFault("invalid or duplicate experiment sequence");return false;}
      pl_books[model]=p;
   }
   FileClose(f);return true;
}

bool PLInitialize()
{
   if(!Identity()||!Owner()||!IsConnected()||!APFinitePositive(AccountBalance()))return false;
   pl_signature=PLParams();string prefix="PPL07.48530368.";
   string campaign_file="DemoAutopilot\\dual-v07-campaign.csv";
   if(FileIsExist(campaign_file))
   {
      int meta=FileOpen(campaign_file,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){PLFault("cannot read campaign identity");return false;}
      string protocol=FileReadString(meta);string signature=FileReadString(meta);
      pl_campaign=StringToInteger(FileReadString(meta));pl_started=(datetime)StringToInteger(FileReadString(meta));FileClose(meta);
      if(protocol!=PL_PROTOCOL||signature!=pl_signature){PLFault("campaign parameters differ; do not reset evidence");return false;}
   }
   else
   {
      pl_campaign=(long)TimeLocal();pl_started=TimeCurrent();
      int meta=FileOpen(campaign_file,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(meta==INVALID_HANDLE){PLFault("cannot persist campaign identity");return false;}
      uint written=FileWrite(meta,PL_PROTOCOL,pl_signature,pl_campaign,(long)pl_started);FileFlush(meta);FileClose(meta);
      if(written==0){PLFault("campaign identity write failed");return false;}
   }
   if(pl_campaign<=0||pl_started<=0){PLFault("invalid campaign identity");return false;}
   GlobalVariableSet(prefix+"campaign",(double)pl_campaign);GlobalVariableSet(prefix+"started",(double)pl_started);GlobalVariablesFlush();
   for(int i=0;i<3;i++)FLInit(pl_books[i],MathMin(PracticeCapitalUSD,AccountBalance()));
   if(!PLRestore())return false;
   for(int i=0;i<3;i++)if(pl_books[i].seq==0)
   {FLBook next=pl_books[i];if(!PLSave(i,next,"INITIAL"))return false;pl_books[i]=next;}
   pl_initialized=true;return true;
}

bool PLPlan(const int model,const int index,const Spec &s,FLBook &p,const double remaining)
{
   string symbol=symbols[index];datetime bar=iTime(symbol,PERIOD_M5,0);
   if(bar<=pl_started||!APEntryWindow(bar,TimeCurrent(),EntryWindowSeconds)){pl_reasons[model]="等新M5收盘";return false;}
   if(bar==(index==0?p.bar_gold:p.bar_silver)){pl_reasons[model]="本根已记录";return false;}
   if(iBars(symbol,PERIOD_M5)<101||iBars(symbol,PERIOD_H1)<101||iBars(symbol,PERIOD_M15)<101)
   {pl_reasons[model]="历史数据不足";return false;}
   for(int j=0;j<5;j++)if(iTime(symbol,PERIOD_M5,j)-iTime(symbol,PERIOD_M5,j+1)!=300)
   {pl_reasons[model]="K线不连续";return false;}
   datetime h1_end=iTime(symbol,PERIOD_H1,1)+3600,m15_end=iTime(symbol,PERIOD_M15,1)+900;
   if(h1_end>TimeCurrent()||TimeCurrent()-h1_end>=3600||m15_end>TimeCurrent()||TimeCurrent()-m15_end>=900)
   {pl_reasons[model]="方向数据未就绪";return false;}
   p.h1_close=iClose(symbol,PERIOD_H1,1);p.h1_ema=iMA(symbol,PERIOD_H1,50,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_close=iClose(symbol,PERIOD_M15,1);p.m15_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,1);
   p.m15_previous_ema=iMA(symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE,2);
   int side=FLDirection(0,APBias(p.h1_close,p.h1_ema),FLFastBias(p.m15_close,p.m15_ema,p.m15_previous_ema));
   p.m5_close=iClose(symbol,PERIOD_M5,1);p.m5_ema=iMA(symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE,1);
   if(side==0||!APMomentum(side,iOpen(symbol,PERIOD_M5,1),p.m5_close,iClose(symbol,PERIOD_M5,2),p.m5_ema))
   {pl_reasons[model]="方向或动量未满足";return false;}
   p.m5_atr=iATR(symbol,PERIOD_M5,14,1);double structure=RecentStructure(symbol,side);
   if(!APFinitePositive(p.m5_atr)||!APFinitePositive(structure)||MathAbs(s.bid-p.m5_close)>APDriftLimit(p.m5_atr,s.tick,EntryDriftATR))
   {pl_reasons[model]="结构或追价限制";return false;}
   double fill=side==1?s.ask:s.bid;
   double sl=APCostAwareInitialStop(APStop(structure,p.m5_atr,side,s.spread,s.tick,s.digits),fill,s.spread,MaxSpreadFraction,s.tick,s.digits,side);
   double distance=side*(fill-sl),budget=MathMin(p.cash*RiskPercent/100,remaining);
   if(!APFinitePositive(distance)||s.spread>MaxSpreadFraction*distance){pl_reasons[model]="止损或成本限制";return false;}
   double lots=APLots(budget,distance,s.slip,s.tick,s.value,s.minimum,s.step,MathMin(s.maximum,MaximumLots),RoundTripFeePerLotUSD);
   if(lots<=0){pl_reasons[model]="最小手数超预算";return false;}
   double tp=APPrice(fill+side*2*distance,s.tick,s.digits,side==1),minimum=(MarketInfo(symbol,MODE_STOPLEVEL)+1)*s.point;
   if((side==1&&(s.bid-sl<minimum||tp-s.bid<minimum))||(side==-1&&(sl-s.ask<minimum||s.ask-tp<minimum)))
   {pl_reasons[model]="服务器距离限制";return false;}
   double margin=MarketInfo(symbol,MODE_MARGINREQUIRED)*lots;
   if(!APFinitePositive(margin)||margin>=p.cash||MarketInfo(symbol,MODE_TRADEALLOWED)==0)
   {pl_reasons[model]="虚拟保证金或交易时段限制";return false;}
   p.active=true;p.index=index;p.side=side;p.opened=TimeCurrent();p.fill=fill;p.sl=sl;p.initial_sl=sl;p.tp=tp;
   p.lots=lots;p.units=lots*s.value/s.tick;p.slip=s.slip;p.fee=RoundTripFeePerLotUSD*lots;
   p.r=(distance+s.slip)*p.units+p.fee;p.peak=0;p.worst=-s.spread*p.units-p.fee;p.spread=s.spread;
   if(index==0)p.bar_gold=bar;else p.bar_silver=bar;
   pl_reasons[model]="虚拟持仓观察";return FLStateValid(p);
}
double PLDualCash(){return pl_books[0].start+(pl_books[0].cash-pl_books[0].start)+(pl_books[1].cash-pl_books[1].start);}
bool PLMarkPortfolio(const bool dual,double &equity,double &reserved,double &margin)
{
   equity=dual?PLDualCash():pl_books[2].cash;reserved=0;margin=0;
   for(int i=dual?0:2;i<(dual?2:3);i++)if(pl_books[i].active)
   {
      FLBook p=pl_books[i];Spec s;if(!ReadSpec(p.index,s))return false;
      equity+=APNet(p.side,p.fill,p.side==1?s.bid:s.ask,p.units,p.fee)-p.slip*p.units;
      reserved+=p.r;margin+=MarketInfo(symbols[p.index],MODE_MARGINREQUIRED)*p.lots;
   }
   return MathIsValidNumber(equity)&&MathIsValidNumber(reserved)&&MathIsValidNumber(margin);
}
void PLManage(const int slot)
{
   if(!pl_books[slot].active)return;
   FLBook next=pl_books[slot];Spec s;if(!ReadSpec(next.index,s))return;
   FLMark(next,s.bid,s.ask);int why=FLExitChoice(next,s.bid,s.ask,TimeCurrent(),MaximumHoldMinutes);
   if(why!=FL_NONE)
   {
      double exit=FLExitPrice(next,s.bid,s.ask,why),extra=(next.spread+next.slip)*next.units;
      double net=FLFinalize(next,exit,TimeCurrent());
      if(PLSave(slot,next,"CLOSE",net,net-extra,exit,FLExitName(why)))pl_books[slot]=next;
      return;
   }
   double minimum=(MathMax(MarketInfo(symbols[next.index],MODE_STOPLEVEL),MarketInfo(symbols[next.index],MODE_FREEZELEVEL))+1)*s.point;
   bool tightened=FLTighten(next,s.bid,s.ask,s.tick,s.digits,minimum);
   if(tightened&&!PLSave(slot,next,"BE"))return;
   pl_books[slot]=next;
}
bool PLTry(const int slot,const int index,const double cash,const double equity,const double reserved,const double margin_used)
{
   double remaining=PLFreeBudget(cash,equity,RiskPercent,reserved);if(remaining<=0)return false;
   Spec s;if(!ReadSpec(index,s))return false;
   FLBook next=pl_books[slot];double slot_cash=next.cash;next.cash=cash;
   bool okay=PLPlan(slot,index,s,next,remaining);next.cash=slot_cash;
   if(!okay||next.r>remaining+1e-7)return false;
   double new_margin=MarketInfo(symbols[index],MODE_MARGINREQUIRED)*next.lots;
   if(!APFinitePositive(new_margin)||margin_used+new_margin>=equity)return false;
   string context="cash="+FF(cash)+"|equity="+FF(equity)+"|reserved_before="+FF(reserved)+"|remaining="+FF(remaining);
   if(!PLSave(slot,next,"OPEN",0,0,0,context))return false;
   pl_books[slot]=next;return true;
}
void PLPublish()
{
   double dual_eq=0,used=0,margin=0,single_eq=0,single_used=0,single_margin=0;
   bool fresh=PLMarkPortfolio(true,dual_eq,used,margin),single_fresh=PLMarkPortfolio(false,single_eq,single_used,single_margin);
   int positions=(pl_books[0].active?1:0)+(pl_books[1].active?1:0);
   double cash=PLDualCash(),stress=pl_books[0].stress_sum+pl_books[1].stress_sum;
   string json="{\"version\":\"0.7\",\"protocol\":\"DUAL07.R1\",\"campaign\":"+IntegerToString(pl_campaign)+
      ",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+"\",\"fault\":"+(pl_fault?"true":"false")+
      ",\"error\":\""+Escape(pl_error)+"\",\"actual_order_operations\":0,\"automatic_promotion\":false,"+
      "\"maximum_virtual_positions\":2,\"total_reserved_risk_percent\":"+FF(RiskPercent)+
      ",\"dual_active\":"+IntegerToString(positions)+",\"dual_closed\":"+IntegerToString(pl_books[0].n+pl_books[1].n)+
      ",\"dual_cash\":"+FF(cash)+",\"dual_net\":"+FF(cash-pl_books[0].start)+",\"dual_stress_net\":"+FF(stress)+
      ",\"dual_equity\":"+(fresh?FF(dual_eq):"null")+",\"dual_reserved_risk\":"+(fresh?FF(used):"null")+
      ",\"single_active\":"+(pl_books[2].active?"true":"false")+",\"single_closed\":"+IntegerToString(pl_books[2].n)+
      ",\"single_net\":"+FF(pl_books[2].cash-pl_books[2].start)+",\"single_stress_net\":"+FF(pl_books[2].stress_sum)+
      ",\"single_equity\":"+(single_fresh?FF(single_eq):"null")+"}";
   if(!WriteSnapshot("DemoAutopilot\\portfolio-status.json",json))Print("Portfolio snapshot publish failed; inspect freshness.");
   datetime bar=iTime("XAUUSD",PERIOD_M5,0);
   if(bar<=pl_started||bar==pl_calendar)return;
   int f=FileOpen(PLPath("calendar.csv"),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){PLFault("calendar unavailable");return;}
   if(FileSize(f)==0)FileWrite(f,"campaign","bar_server","sample_local","complete","dual_equity","single_equity","dual_active","dual_reserved_risk");
   FileSeek(f,0,SEEK_END);FileWrite(f,pl_campaign,(long)bar,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),fresh&&single_fresh?1:0,
      FF(dual_eq),FF(single_eq),positions,FF(used));FileFlush(f);FileClose(f);pl_calendar=bar;
}
void PLShutdown()
{
   if(!pl_initialized||pl_fault||!Identity()||!Owner())return;
   for(int i=0;i<3&&!pl_fault;i++){FLBook next=pl_books[i];if(PLSave(i,next,"SHUTDOWN"))pl_books[i]=next;}
}
void PortfolioCycle()
{
   if(!EnableForwardResearch||!Identity()||!Owner()||!IsConnected()||TimeLocal()==pl_last_cycle)return;
   pl_last_cycle=TimeLocal();if(!pl_initialized&&!pl_fault)PLInitialize();
   if(pl_initialized&&!pl_fault)
   {
      if(pl_signature!=PLParams())PLFault("portfolio parameters changed; registered campaign required");
      else
      {
         bool was_dual=pl_books[0].active||pl_books[1].active,was_single=pl_books[2].active;
         int before=(pl_books[0].active?1:0)+(pl_books[1].active?1:0);
         for(int i=0;i<3&&!pl_fault;i++)PLManage(i);
         int after=(pl_books[0].active?1:0)+(pl_books[1].active?1:0);
         if(!Paused()&&AutoEntries&&!pl_fault)
         {
            datetime last=(datetime)MathMax(pl_books[0].last_close,pl_books[1].last_close);
            if(before==after&&APCooldownReady(TimeCurrent(),last,CooldownMinutes))
            {
               for(int slot=0;slot<2&&!pl_fault;slot++)if(!pl_books[slot].active)
               {
                  double equity=0,used=0,margin=0;
                  if(PLMarkPortfolio(true,equity,used,margin))PLTry(slot,slot,PLDualCash(),equity,used,margin);
               }
            }
            if(!was_single&&!pl_books[2].active&&APCooldownReady(TimeCurrent(),pl_books[2].last_close,CooldownMinutes))
            {
               for(int symbol=0;symbol<2;symbol++)if(PLTry(2,symbol,pl_books[2].cash,pl_books[2].cash,0,0))break;
            }
         }
         if(TimeLocal()-pl_checkpoint>=15)
         {
            for(int i=0;i<3&&!pl_fault;i++)if(pl_books[i].active){FLBook next=pl_books[i];if(PLSave(i,next,"CHECKPOINT"))pl_books[i]=next;}
            pl_checkpoint=TimeLocal();
         }
      }
   }
   if(TimeLocal()-pl_last_status>=5){PLPublish();pl_last_status=TimeLocal();}
}
#endif
