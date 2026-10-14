#ifndef CODEX_EXIT_COMPARISON_V09
#define CODEX_EXIT_COMPARISON_V09
// Paired exit comparison on future accepted entries. Zero terminal order APIs.
const string EP_PROTOCOL="EXIT09.R1";
const int EP_SLOTS=8,EP_COLUMNS=29;
string ep_root="DemoAutopilot\\exit-v09-",ep_signature="",ep_error="";
FLBook ep_books[16];int ep_tickets[8];bool ep_completed[8];
double ep_nets[16],ep_baseline=0,ep_trial=0;
int ep_pairs=0;long ep_seq=0,ep_campaign=0;
bool ep_initialized=false,ep_fault=false;
datetime ep_last_cycle=0,ep_checkpoint=0,ep_status_time=0;
string EPN(const double value){return DoubleToString(value,12);}
string EPPath(){return ep_root+IntegerToString(ep_campaign)+"-ledger.csv";}
string EPParams()
{
   return EP_PROTOCOL+"|demo=48530368|be=.6R|trail1=.75R|trail1.5=.5R|hold="+IntegerToString(MaximumHoldMinutes)+
      "|fee="+EPN(RoundTripFeePerLotUSD)+"|capital="+EPN(PracticeCapitalUSD)+"|paired_actual_entries|no_auto_promotion";
}
void EPFault(const string message){ep_fault=true;ep_error=message;Print("Exit comparison stopped: ",message);}
bool EPSave(const int slot,const int model,const string action,const double net=0,const double exit=0,const string why="")
{
   int at=slot*2+model;FLBook p=ep_books[at];
   if(!FLStateValid(p)){EPFault("invalid paired state");return false;}
   int f=FileOpen(EPPath(),FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){EPFault("ledger unavailable");return false;}
   if(FileSize(f)==0)FileWrite(f,"protocol","seq","slot","ticket","model","action","local_time","server_time","active","index","side","opened",
      "fill","sl","tp","units","lots","r","slip","fee","peak","spread","initial_sl","event_net","exit_price","exit_reason","last_close","start","signature");
   FileSeek(f,0,SEEK_END);ep_seq++;
   uint written=FileWrite(f,EP_PROTOCOL,ep_seq,slot,ep_tickets[slot],model,action,TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),p.active?1:0,p.index,p.side,(long)p.opened,EPN(p.fill),EPN(p.sl),EPN(p.tp),
      EPN(p.units),EPN(p.lots),EPN(p.r),EPN(p.slip),EPN(p.fee),EPN(p.peak),EPN(p.spread),EPN(p.initial_sl),EPN(net),EPN(exit),why,
      (long)p.last_close,EPN(p.start),ep_signature);
   FileFlush(f);FileClose(f);if(written==0){EPFault("ledger write failed");return false;}return true;
}
void EPComplete(const int slot)
{
   if(ep_tickets[slot]<=0||ep_completed[slot]||ep_books[2*slot].active||ep_books[2*slot+1].active)return;
   if(EPSave(slot,1,"PAIR_DONE",ep_nets[2*slot+1]-ep_nets[2*slot],0,"paired_difference"))
   {ep_completed[slot]=true;ep_pairs++;ep_baseline+=ep_nets[2*slot];ep_trial+=ep_nets[2*slot+1];}
}
bool EPRestore()
{
   if(!FileIsExist(EPPath()))return true;
   int f=FileOpen(EPPath(),FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){EPFault("ledger restore unavailable");return false;}
   bool header=true;
   while(!FileIsEnding(f))
   {
      string row[];int count=0;
      while(!FileIsEnding(f)){ArrayResize(row,count+1);row[count++]=FileReadString(f);if(FileIsLineEnding(f))break;}
      if(count==1&&row[0]=="")continue;
      if(count!=EP_COLUMNS){FileClose(f);EPFault("incomplete paired ledger row");return false;}
      if(header){header=false;if(row[0]!="protocol"||row[28]!="signature"){FileClose(f);EPFault("schema mismatch");return false;}continue;}
      for(int n=1;n<EP_COLUMNS;n++)if(n!=5&&n!=6&&n!=7&&n!=25&&n!=28&&!FLNumberToken(row[n]))
      {FileClose(f);EPFault("invalid numeric field");return false;}
      int slot=(int)StringToInteger(row[2]),model=(int)StringToInteger(row[4]),ticket=(int)StringToInteger(row[3]);
      long seq=StringToInteger(row[1]);
      if(row[0]!=EP_PROTOCOL||row[28]!=ep_signature||slot<0||slot>=EP_SLOTS||model<0||model>1||ticket<=0||seq<=ep_seq)
      {FileClose(f);EPFault("identity or sequence mismatch");return false;}
      ep_seq=seq;
      if(ep_tickets[slot]!=ticket)
      {
         if(ep_tickets[slot]>0&&!ep_completed[slot]){FileClose(f);EPFault("unfinished pair overwritten");return false;}
         ep_tickets[slot]=ticket;ep_completed[slot]=false;
         for(int j=0;j<2;j++){FLInit(ep_books[slot*2+j],PracticeCapitalUSD);ep_nets[slot*2+j]=0;}
      }
      FLBook p;FLInit(p,StringToDouble(row[27]));
      p.active=StringToInteger(row[8])==1;p.index=(int)StringToInteger(row[9]);p.side=(int)StringToInteger(row[10]);
      p.opened=(datetime)StringToInteger(row[11]);p.fill=StringToDouble(row[12]);p.sl=StringToDouble(row[13]);p.tp=StringToDouble(row[14]);
      p.units=StringToDouble(row[15]);p.lots=StringToDouble(row[16]);p.r=StringToDouble(row[17]);p.slip=StringToDouble(row[18]);
      p.fee=StringToDouble(row[19]);p.peak=StringToDouble(row[20]);p.spread=StringToDouble(row[21]);p.initial_sl=StringToDouble(row[22]);
      p.last_close=(datetime)StringToInteger(row[26]);
      if(!FLStateValid(p)){FileClose(f);EPFault("invalid restored book");return false;}
      ep_books[slot*2+model]=p;
      if(row[5]=="CLOSE")ep_nets[slot*2+model]=StringToDouble(row[23]);
      if(row[5]=="PAIR_DONE")
      {
         if(ep_completed[slot]||ep_books[slot*2].active||ep_books[slot*2+1].active)
         {FileClose(f);EPFault("invalid or duplicate paired completion");return false;}
         ep_completed[slot]=true;ep_pairs++;ep_baseline+=ep_nets[slot*2];ep_trial+=ep_nets[slot*2+1];
      }
   }
   FileClose(f);return true;
}
bool EPInitialize()
{
   if(!Identity()||!Owner()||!IsConnected())return false;
   ep_signature=EPParams();string meta=ep_root+"campaign.csv";
   if(FileIsExist(meta))
   {
      int f=FileOpen(meta,FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(f==INVALID_HANDLE){EPFault("campaign read failed");return false;}
      string protocol=FileReadString(f),signature=FileReadString(f);ep_campaign=StringToInteger(FileReadString(f));FileClose(f);
      if(protocol!=EP_PROTOCOL||signature!=ep_signature||ep_campaign<=0){EPFault("campaign changed; keep prior evidence");return false;}
   }
   else
   {
      ep_campaign=(long)TimeLocal();int f=FileOpen(meta,FILE_WRITE|FILE_CSV|FILE_ANSI,',',CP_UTF8);
      if(f==INVALID_HANDLE){EPFault("campaign write failed");return false;}
      uint written=FileWrite(f,EP_PROTOCOL,ep_signature,ep_campaign);FileFlush(f);FileClose(f);
      if(written==0){EPFault("empty campaign record");return false;}
   }
   if(!EPRestore())return false;
   // An interrupted OPEN must not silently turn a two-arm pair into a one-arm experiment.
   for(int i=0;i<EP_SLOTS;i++)if(ep_tickets[i]>0&&!ep_completed[i]&&
      (!APFinitePositive(ep_books[2*i].r)||!APFinitePositive(ep_books[2*i+1].r)))
   {EPFault("incomplete pair initialization");return false;}
   ep_initialized=true;return true;
}
void EPStart(const int ticket,const int index,const Spec &s)
{
   if(!EnableForwardResearch||!Identity()||!Owner()||ep_fault)return;
   if(!ep_initialized&&!EPInitialize())return;
   for(int seen=0;seen<EP_SLOTS;seen++)if(ep_tickets[seen]==ticket)return;
   int slot=-1;for(int i=0;i<EP_SLOTS;i++)if(ep_tickets[i]==0||ep_completed[i]){slot=i;break;}
   if(slot<0){EPFault("paired capacity exhausted; no silent sample dropping");return;}
   if(!OrderSelect(ticket,SELECT_BY_TICKET)||!IsOwnedSelected()||OrderCloseTime()!=0)return;
   FLBook p;FLInit(p,PracticeCapitalUSD);p.active=true;p.index=index;p.side=OrderType()==OP_BUY?1:-1;
   p.opened=OrderOpenTime();p.fill=OrderOpenPrice();p.sl=OrderStopLoss();p.initial_sl=p.sl;p.tp=OrderTakeProfit();
   p.lots=OrderLots();p.units=p.lots*s.value/s.tick;p.r=GlobalVariableGet(K("initial_R",ticket));
   p.slip=s.slip;p.fee=APConservativeCost(p.lots,RoundTripFeePerLotUSD,OrderCommission(),OrderSwap());p.spread=s.spread;
   if(!FLStateValid(p)||p.fee<0){EPFault("invalid accepted entry clone");return;}
   ep_tickets[slot]=ticket;ep_completed[slot]=false;
   for(int m=0;m<2;m++){ep_books[2*slot+m]=p;ep_nets[2*slot+m]=0;if(!EPSave(slot,m,"OPEN"))return;}
}
void EPManage(const int slot,const int model,const Spec &s)
{
   int at=slot*2+model;if(!ep_books[at].active)return;
   FLBook p=ep_books[at];FLMark(p,s.bid,s.ask);
   int why=model==0?FLExitChoice(p,s.bid,s.ask,TimeCurrent(),MaximumHoldMinutes):APProtectedExit(p,s.bid,s.ask,TimeCurrent(),MaximumHoldMinutes);
   if(why!=FL_NONE)
   {
      double exit=FLExitPrice(p,s.bid,s.ask,why),net=FLFinalize(p,exit,TimeCurrent());ep_books[at]=p;ep_nets[at]=net;
      EPSave(slot,model,"CLOSE",net,exit,why==FL_STOP?"STOP":why==FL_TARGET?"TARGET":why==FL_GIVEBACK?"GIVEBACK":"TIME");return;
   }
   double minimum=(MathMax(MarketInfo(symbols[p.index],MODE_STOPLEVEL),MarketInfo(symbols[p.index],MODE_FREEZELEVEL))+1)*s.point;
   bool tightened=model==0?FLTighten(p,s.bid,s.ask,s.tick,s.digits,minimum):APProtectedTighten(p,s.bid,s.ask,s.tick,s.digits,minimum);
   ep_books[at]=p;if(tightened)EPSave(slot,model,"TIGHTEN");
}
void EPStatus()
{
   int active=0;for(int i=0;i<EP_SLOTS;i++)if(ep_tickets[i]>0&&!ep_completed[i])active++;
   string json="{\"version\":\"0.9\",\"protocol\":\""+EP_PROTOCOL+"\",\"local_time\":\""+TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS)+
      "\",\"campaign\":"+IntegerToString(ep_campaign)+",\"fault\":"+(ep_fault?"true":"false")+",\"error\":\""+Escape(ep_error)+
      "\",\"actual_order_operations\":0,\"automatic_promotion\":false,\"profitability_validated\":false,\"paired_closed_count\":"+IntegerToString(ep_pairs)+
      ",\"active_pairs\":"+IntegerToString(active)+",\"baseline_net_usd\":"+EPN(ep_baseline)+",\"early_protection_net_usd\":"+EPN(ep_trial)+
      ",\"paired_difference_usd\":"+EPN(ep_trial-ep_baseline)+
      ",\"scope\":\"exit-only comparison on identical future accepted broker entries; excludes missed-entry and portfolio feedback\","+
      "\"fill_model\":\"sampled Bid/Ask; adverse exit slip; TP capped at limit; no broker queue/rejection model; no profit guarantee\"}";
   WriteSnapshot(ep_root+"status.json",json);
}
void EPCycle()
{
   if(!EnableForwardResearch||!Identity()||!Owner()||!IsConnected()||TimeLocal()==ep_last_cycle)return;
   ep_last_cycle=TimeLocal();if(!ep_initialized&&!ep_fault)EPInitialize();
   if(ep_initialized&&!ep_fault)
   {
      if(ep_signature!=EPParams())EPFault("policy parameters changed");
      else for(int i=0;i<EP_SLOTS&&!ep_fault;i++)if(ep_tickets[i]>0&&!ep_completed[i])
      {
         Spec s;int at=ep_books[2*i].index;if(ReadSpec(at,s)){for(int m=0;m<2&&!ep_fault;m++)EPManage(i,m,s);if(!ep_fault)EPComplete(i);}
      }
      if(!ep_fault&&TimeLocal()-ep_checkpoint>=15)
      {for(int i=0;i<EP_SLOTS&&!ep_fault;i++)if(ep_tickets[i]>0&&!ep_completed[i])for(int m=0;m<2;m++)EPSave(i,m,"CHECKPOINT");ep_checkpoint=TimeLocal();}
   }
   if(TimeLocal()-ep_status_time>=5){EPStatus();ep_status_time=TimeLocal();}
}
void EPShutdown()
{
   if(!ep_initialized||ep_fault||!Identity()||!Owner())return;
   for(int i=0;i<EP_SLOTS&&!ep_fault;i++)if(ep_tickets[i]>0&&!ep_completed[i])for(int m=0;m<2;m++)EPSave(i,m,"SHUTDOWN");
}
#endif
