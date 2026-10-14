#ifndef CODEX_PROFIT_PROTECTION_V09
#define CODEX_PROFIT_PROTECTION_V09
// Fixed demo-trial policy, not fitted to the recent two outcomes.
double APProtectedNet(const double peak,const double r)
{
   if(!MathIsValidNumber(peak)||!APFinitePositive(r)||peak<0.6*r)return -1;
   if(peak>=1.5*r)return MathMax(0,peak-0.5*r);
   if(peak>=r)return MathMax(0,peak-0.75*r);
   return 0;
}
bool APProtectedGiveback(const double peak,const double net,const double r)
{
   return MathIsValidNumber(net)&&APFinitePositive(r)&&peak>=r&&net<=APProtectedNet(peak,r);
}
double APProtectedStop(const double fill,const double units,const double cost,const double slip,
                       const double tick,const int digits,const int side,const double peak,const double r)
{
   double retained=APProtectedNet(peak,r);
   if(retained<0||!APFinitePositive(fill)||!APFinitePositive(units)||
      !MathIsValidNumber(cost)||cost<0||!MathIsValidNumber(slip)||slip<0||!APFinitePositive(tick)||
      (side!=1&&side!=-1))return 0;
   return APPrice(fill+side*((cost+retained)/units+slip+tick),tick,digits,side==1);
}
bool APProtectedTighten(FLBook &p,const double bid,const double ask,const double tick,const int digits,const double minimum_distance)
{
   double target=APProtectedStop(p.fill,p.units,p.fee,p.slip,tick,digits,p.side,p.peak,p.r);
   if(!APFinitePositive(target)||!MathIsValidNumber(minimum_distance)||minimum_distance<0)return false;
   if((p.side==1&&(target<=p.sl+tick*.5||target>=bid-minimum_distance))||
      (p.side==-1&&(target>=p.sl-tick*.5||target<=ask+minimum_distance)))return false;
   p.sl=target;return true;
}
int APProtectedExit(const FLBook &p,const double bid,const double ask,const datetime now,const int hold_minutes)
{
   double price=p.side==1?bid:ask;
   if((p.side==1&&price<=p.sl)||(p.side==-1&&price>=p.sl))return FL_STOP;
   if((p.side==1&&price>=p.tp)||(p.side==-1&&price<=p.tp))return FL_TARGET;
   if(APProtectedGiveback(p.peak,APNet(p.side,p.fill,price,p.units,p.fee),p.r))return FL_GIVEBACK;
   if(hold_minutes>0&&now>=p.opened&&now-p.opened>=hold_minutes*60)return FL_TIME;
   return FL_NONE;
}
#endif
