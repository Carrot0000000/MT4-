#ifndef CODEX_EXECUTION_QUALITY_V011
#define CODEX_EXECUTION_QUALITY_V011
// Observations only: never calls a terminal order API or changes a risk threshold.
string eq_path="DemoAutopilot\\execution-v011.csv";
bool eq_fault=false;
int eq_calls=0,eq_failures=0,eq_fills=0;
double eq_ms_sum=0,eq_ms_max=0,eq_last_ms=0,eq_adverse_sum=0,eq_adverse_max=0;
uint eq_cycle_last_ms=0,eq_cycle_max_ms=0;
double EQAdversePrice(const bool entry,const int side,const double requested,const double actual)
{
   if((side!=1&&side!=-1)||!APFinitePositive(requested)||!APFinitePositive(actual))return EMPTY_VALUE;
   return side*(entry?actual-requested:requested-actual);
}
double EQPingMs()
{long us=TerminalInfoInteger(TERMINAL_PING_LAST);return us>0?us/1000.0:-1;}
void EQRecord(const bool entry,const string symbol,const int ticket,const int side,const double lots,
              const double requested,const double actual,const bool accepted,const int error,
              const uint elapsed_ms,const double spread,const double units)
{
   if(!Identity()||!Owner())return;
   eq_calls++;if(!accepted)eq_failures++;
   eq_last_ms=(double)elapsed_ms;eq_ms_sum+=eq_last_ms;eq_ms_max=MathMax(eq_ms_max,eq_last_ms);
   double adverse=EQAdversePrice(entry,side,requested,actual);
   bool known=accepted&&adverse!=EMPTY_VALUE&&APFinitePositive(units);
   if(known){eq_fills++;eq_adverse_sum+=adverse*units;eq_adverse_max=MathMax(eq_adverse_max,MathMax(0,adverse*units));}
   int f=FileOpen(eq_path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE){if(!eq_fault)Print("Execution quality log unavailable; trade management continues.");eq_fault=true;return;}
   if(FileSize(f)==0)FileWrite(f,"protocol","local_time","server_time","action","symbol","ticket","side","lots","requested_price","actual_price","accepted","error","call_elapsed_ms","terminal_ping_ms","spread_price","adverse_price","adverse_usd");
   FileSeek(f,0,SEEK_END);
   uint written=FileWrite(f,"EXEC11.R1",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      entry?"OPEN":"CLOSE",symbol,ticket,side,DoubleToString(lots,8),DoubleToString(requested,8),known?DoubleToString(actual,8):"unknown",accepted?1:0,error,
      (long)elapsed_ms,EQPingMs()>0?DoubleToString(EQPingMs(),3):"unknown",DoubleToString(spread,8),
      known?DoubleToString(adverse,8):"unknown",known?DoubleToString(adverse*units,8):"unknown");
   FileFlush(f);FileClose(f);if(written==0)eq_fault=true;
}
string EQJson()
{
   return "{\"scope\":\"since_current_EA_initialization; append-only log preserves earlier samples\",\"log_fault\":"+(eq_fault?"true":"false")+
      ",\"order_calls\":"+IntegerToString(eq_calls)+",\"failed_calls\":"+IntegerToString(eq_failures)+",\"confirmed_fill_samples\":"+IntegerToString(eq_fills)+
      ",\"terminal_ping_ms\":"+(EQPingMs()>0?DoubleToString(EQPingMs(),3):"null")+
      ",\"last_call_ms\":"+(eq_calls>0?DoubleToString(eq_last_ms,1):"null")+
      ",\"mean_call_ms\":"+(eq_calls>0?DoubleToString(eq_ms_sum/eq_calls,1):"null")+
      ",\"max_call_ms\":"+(eq_calls>0?DoubleToString(eq_ms_max,1):"null")+
      ",\"signed_adverse_slippage_usd\":"+(eq_fills>0?DoubleToString(eq_adverse_sum,4):"null")+
      ",\"max_adverse_fill_usd\":"+(eq_fills>0?DoubleToString(eq_adverse_max,4):"null")+
      ",\"previous_cycle_ms\":"+IntegerToString(eq_cycle_last_ms)+",\"max_cycle_ms\":"+IntegerToString(eq_cycle_max_ms)+
      ",\"note\":\"ping is terminal-to-server round trip; call duration includes terminal and broker; neither guarantees future execution speed\"}";
}
#endif
