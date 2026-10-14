#ifndef CODEX_BUDGET_ADMISSION_V08
#define CODEX_BUDGET_ADMISSION_V08
// Necessary conditions only: passing this preflight is not an entry signal.
enum APAdmissionCheckCode { AP_COST_BUDGET=17, AP_MINIMUM_VOLUME=18, AP_SPEC_INVALID=19 };

double APAdmissionRiskFloor(const double spread,const double fraction,const double slip,
                           const double tick,const double value,const double minimum,const double fee,
                           const double stop_points,const double point)
{
   double base=APMinimumRiskForSpread(spread,fraction,slip,tick,value,minimum,fee);
   if(base<0||!MathIsValidNumber(stop_points)||stop_points<0||!APFinitePositive(point))return -1;
   // Entry is at Ask for buys / Bid for sells; server SL distance uses the opposite quote.
   // Match the existing one-point server buffer and one-tick cost-aware stop buffer.
   double distance=MathMax(spread/fraction+tick,spread+(stop_points+1)*point);
   return ((distance+slip)/tick*value+fee)*minimum;
}
int APAdmissionCode(const double floor_risk,const double budget,const double minimum,const double maximum)
{
   if(!APFinitePositive(floor_risk)||!APFinitePositive(budget)||
      !APFinitePositive(minimum)||!APFinitePositive(maximum))return AP_SPEC_INVALID;
   if(minimum>maximum+1e-10)return AP_MINIMUM_VOLUME;
   if(floor_risk>budget+1e-7)return AP_COST_BUDGET;
   return 0;
}
double APConservativeCost(const double lots,const double fee_per_lot,const double commission,const double swap)
{
   if(!APFinitePositive(lots)||!MathIsValidNumber(fee_per_lot)||fee_per_lot<0||
      !MathIsValidNumber(commission)||!MathIsValidNumber(swap))return -1;
   // Reserve the whole estimated round trip even if only opening commission is posted.
   return MathMax(lots*fee_per_lot,MathMax(0,-commission))+MathMax(0,-swap);
}
string AP08CheckText(const int code)
{
   if(code==AP_COST_BUDGET)return "当前最小单成本超预算";
   if(code==AP_MINIMUM_VOLUME)return "最小手数超过手数上限";
   if(code==AP_SPEC_INVALID)return "等待有效合约与预算数据";
   return APCheckText(code);
}
int APNextBarSeconds(const datetime bar,const datetime now,const int period_seconds)
{
   if(bar<=0||period_seconds<=0||now<bar||now>=bar+period_seconds)return -1;
   return (int)(bar+period_seconds-now);
}
#endif
