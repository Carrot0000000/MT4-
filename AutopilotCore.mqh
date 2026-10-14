#ifndef CODEX_DEMO_AUTOPILOT_CORE
#define CODEX_DEMO_AUTOPILOT_CORE
// Pure calculations shared by the EA and the no-order self-test script.
bool APIdentity(const long account_mode,const long login,const string server,const bool testing)
{ return !testing && account_mode==ACCOUNT_TRADE_MODE_DEMO && login==48530368 && server=="FPMarketsLtd-Demo2"; }
// A large broker demo balance must not silently raise the agreed practice risk.
double APPracticeBudget(const double balance,const double equity,const double capital,const double percent)
{
   if(!MathIsValidNumber(balance)||!MathIsValidNumber(equity)||!MathIsValidNumber(capital)||
      !MathIsValidNumber(percent)||balance<=0||equity<=0||capital<=0||capital>500||percent<=0||percent>3)return 0;
   return MathMin(capital,MathMin(balance,equity))*percent/100;
}
bool APFinitePositive(const double x){ return MathIsValidNumber(x) && x>0; }
double APPrice(const double value,const double tick,const int digits,const bool round_up)
{
   if(!APFinitePositive(value)||!APFinitePositive(tick))return 0;
   double units=value/tick;
   return NormalizeDouble((round_up?MathCeil(units-1e-8):MathFloor(units+1e-8))*tick,digits);
}
double APLots(const double budget,const double distance,const double slip,const double tick,
              const double tick_value,const double minimum,const double step,const double maximum,const double fee)
{
   if(!APFinitePositive(budget)||!APFinitePositive(distance)||!APFinitePositive(tick)||
      !APFinitePositive(tick_value)||!APFinitePositive(minimum)||!APFinitePositive(step)||
      !APFinitePositive(maximum)||!MathIsValidNumber(slip)||slip<0||!MathIsValidNumber(fee)||fee<0)return 0;
   double loss_per_lot=(distance+slip)/tick*tick_value+fee;
   double raw=MathMin(maximum,budget/loss_per_lot);
   if(raw<minimum-1e-10)return 0;
   double result=NormalizeDouble(minimum+MathFloor((raw-minimum)/step+1e-9)*step,8);
   // A floating point epsilon must never produce an above-budget position.
   if(result*loss_per_lot>budget+1e-7)result=NormalizeDouble(result-step,8);
   return result>=minimum-1e-10?result:0;
}
double APStop(const double structure,const double atr,const int side,const double spread,
              const double tick,const int digits)
{
   if(!APFinitePositive(structure)||!APFinitePositive(atr)||(side!=1&&side!=-1)||spread<0)return 0;
   return APPrice(structure-side*0.2*atr+(side==-1?spread:0),tick,digits,side==-1);
}
double APBreakEven(const double fill,const double units,const double cost,const double slip,
                   const double tick,const int digits,const int side)
{
   if(!APFinitePositive(fill)||!APFinitePositive(units)||cost<0||slip<0||(side!=1&&side!=-1))return 0;
   return APPrice(fill+side*(cost/units+slip+tick),tick,digits,side==1);
}
double APNet(const int side,const double entry,const double exit,const double units,const double cost)
{ return side*(exit-entry)*units-cost; }
bool APGiveback(const double peak,const double current,const double initial_r)
{ return APFinitePositive(initial_r) && peak>=1.5*initial_r && current<=peak-0.5*initial_r; }

// Closing acknowledgement must update the gate before any new signal is considered.
bool APCooldownReady(const datetime now,const datetime last_close,const int minutes)
{return now>0&&last_close>=0&&minutes>=0&&(last_close==0||(now>=last_close&&now-last_close>=minutes*60));}
bool APEntryCycleReady(const bool closed_in_cycle,const bool reconciled,const datetime now,
                      const datetime last_close,const int minutes)
{return !closed_in_cycle&&reconciled&&APCooldownReady(now,last_close,minutes);}
int APRetrySeconds(const int error)
{
   if(error==135||error==138)return 1;
   if(error==136)return 3;
   if(error==128||error==6)return 10;
   return 5;
}
enum APExitCode
{AP_EXIT_NONE=0,AP_EXIT_USER=1,AP_EXIT_PROTECTION=2,AP_EXIT_RISK=3,AP_EXIT_GIVEBACK=4,AP_EXIT_TIME=5,AP_EXIT_FILL=6};
int APStickyExit(const int current,const int requested)
{return current>0?current:requested;}
string APExitText(const int code)
{
   switch(code)
   {
      case AP_EXIT_USER:return "USER_FLATTEN_AND_PAUSE";
      case AP_EXIT_PROTECTION:return "MISSING_SERVER_PROTECTION";
      case AP_EXIT_RISK:return "STOP_RISK_EXPANDED";
      case AP_EXIT_GIVEBACK:return "PROFIT_GIVEBACK_0.5R_AFTER_1.5R";
      case AP_EXIT_TIME:return "TIME_EXIT";
      case AP_EXIT_FILL:return "FILLED_RISK_OR_PROTECTION_MISMATCH";
   }
   return "SERVER_OR_EXTERNAL_EXIT_NOT_CLASSIFIED";
}
enum APCheckCode
{
   AP_NO_CHECK=0,AP_QUOTE=1,AP_HISTORY=2,AP_H1_STALE=3,AP_GAP=4,AP_DIRECTION=5,
   AP_TRIGGER=6,AP_STRUCTURE=7,AP_DRIFT=8,AP_STOP=9,AP_SPREAD=10,AP_BUDGET=11,
   AP_STOP_LEVEL=12,AP_MARGIN=13,AP_PERMISSION=14,AP_SEND_ERROR=15,AP_FILLED=16
};
string APCheckText(const int code)
{
   switch(code)
   {
      case AP_QUOTE:return "等待新鲜报价";
      case AP_HISTORY:return "历史数据不足";
      case AP_H1_STALE:return "H1数据过期或未完成";
      case AP_GAP:return "休市后K线不连续";
      case AP_DIRECTION:return "没有明确的H1方向";
      case AP_TRIGGER:return "M5动量未与H1同向";
      case AP_STRUCTURE:return "没有已确认结构";
      case AP_DRIFT:return "价格走远，不追单";
      case AP_STOP:return "止损方向无效";
      case AP_SPREAD:return "点差相对止损过大";
      case AP_BUDGET:return "最小手数超风险预算";
      case AP_STOP_LEVEL:return "服务器止损距离限制";
      case AP_MARGIN:return "保证金或品种权限不足";
      case AP_PERMISSION:return "账户持仓或权限拦截";
      case AP_SEND_ERROR:return "入场失败，已记录";
      case AP_FILLED:return "已成交，实时管理";
   }
   return "尚无入场检查记录";
}
bool APEntryWindow(const datetime bar,const datetime server_now,const int window_seconds=60)
{return bar>0&&window_seconds>0&&server_now>=bar&&server_now-bar<=window_seconds;}
bool APRecordChanged(const datetime old_bar,const int old_code,const datetime new_bar,const int new_code)
{return new_bar>0&&new_code>0&&(old_bar!=new_bar||old_code!=new_code);}
double APMinimumRiskForSpread(const double spread,const double allowed_fraction,const double slip,
                            const double tick,const double tick_value,const double minimum,const double fee)
{
   if(!MathIsValidNumber(spread)||spread<0||!APFinitePositive(allowed_fraction)||
      !MathIsValidNumber(slip)||slip<0||!APFinitePositive(tick)||!APFinitePositive(tick_value)||
      !APFinitePositive(minimum)||!MathIsValidNumber(fee)||fee<0)return -1;
   return ((spread/allowed_fraction+slip)/tick*tick_value+fee)*minimum;
}
int APBias(const double close,const double ema)
{
   if(!APFinitePositive(close)||!APFinitePositive(ema))return 0;
   if(close>ema)return 1;
   if(close<ema)return -1;
   return 0;
}
bool APMomentum(const int side,const double open,const double close,const double previous_close,const double ema)
{
   if(!APFinitePositive(open)||!APFinitePositive(close)||!APFinitePositive(previous_close)||!APFinitePositive(ema))return false;
   return side==1?(close>open&&close>previous_close&&close>ema):
          side==-1?(close<open&&close<previous_close&&close<ema):false;
}
double APRangeExtreme(const double first,const double second,const double third,const int side)
{
   if(!APFinitePositive(first)||!APFinitePositive(second)||!APFinitePositive(third))return 0;
   if(side==1)return MathMin(first,MathMin(second,third));
   if(side==-1)return MathMax(first,MathMax(second,third));
   return 0;
}
double APDriftLimit(const double atr,const double tick,const double fraction)
{
   if(!APFinitePositive(atr)||!APFinitePositive(tick)||!APFinitePositive(fraction))return 0;
   return MathMax(atr*fraction,tick*2);
}
double APCostAwareInitialStop(const double structural_stop,const double fill,const double spread,
                            const double fraction,const double tick,const int digits,const int side)
{
   if(!APFinitePositive(structural_stop)||!APFinitePositive(fill)||!MathIsValidNumber(spread)||spread<0||
      !APFinitePositive(fraction)||!APFinitePositive(tick)||(side!=1&&side!=-1))return 0;
   double minimum_distance=spread/fraction+tick;
   // Extend an INITIAL stop outward when necessary for costs, then size it. Never widen an existing order's stop.
   double stop=side==1?MathMin(structural_stop,fill-minimum_distance):MathMax(structural_stop,fill+minimum_distance);
   return APPrice(stop,tick,digits,side==-1);
}
#endif
