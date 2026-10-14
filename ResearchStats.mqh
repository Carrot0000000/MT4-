#ifndef CODEX_RESEARCH_STATS
#define CODEX_RESEARCH_STATS
// Pure diagnostics; does not alter the broker's order sizing or execution.
double RSLogBernoulliBeta(const int wins,const int count)
{
   if(count<0||wins<0||wins>count)return 1e100;
   double result=-MathLog(count+1.0);int smaller=(int)MathMin(wins,count-wins);
   for(int k=1;k<=smaller;k++)result-=MathLog((count-k+1.0)/k);
   return result;
}
double RSLogWinEvidence(const double p,const int wins,const int count,const double norm)
{
   if(p<=0)return wins>0?1e100:norm;
   if(p>=1)return count>wins?1e100:norm;
   return norm-wins*MathLog(p)-(count-wins)*MathLog(1-p);
}
void RSWinCS(const int wins,const int count,const double threshold,double &lower,double &upper)
{
   lower=0;upper=1;if(count==0)return;
   if(count<0||wins<0||wins>count||threshold<=1){lower=-1;upper=-1;return;}
   double norm=RSLogBernoulliBeta(wins,count),boundary=MathLog(threshold),mle=wins/(double)count;
   if(wins>0)
   {
      double lo=0,hi=mle;
      for(int i=0;i<64;i++){double mid=(lo+hi)/2;if(RSLogWinEvidence(mid,wins,count,norm)>boundary)lo=mid;else hi=mid;}
      lower=(lo+hi)/2;
   }
   if(wins<count)
   {
      double lo=mle,hi=1;
      for(int i=0;i<64;i++){double mid=(lo+hi)/2;if(RSLogWinEvidence(mid,wins,count,norm)>boundary)hi=mid;else lo=mid;}
      upper=(lo+hi)/2;
   }
}
double RSBrier(const double p,const bool won){return (p-(won?1.0:0.0))*(p-(won?1.0:0.0));}
double RSLogLoss(const double p,const bool won){return p>0&&p<1?-(won?MathLog(p):MathLog(1-p)):-1;}
double PLFreeBudget(const double cash,const double equity,const double percent,const double reserved)
{
   if(!APFinitePositive(cash)||!APFinitePositive(equity)||!APFinitePositive(percent)||percent>1||
      !MathIsValidNumber(reserved)||reserved<0)return 0;
   return MathMax(0,MathMin(cash,equity)*percent/100-reserved);
}
string RSPermissionText(const bool global_allowed,const bool program_allowed,const bool server_allowed,const bool busy)
{
   if(!global_allowed)return "MT4全局自动交易关闭";
   if(!program_allowed)return "当前程序交易权限关闭";
   if(!server_allowed)return "服务器交易权限关闭";
   if(busy)return "交易通道忙，等待重试";
   return "交易权限暂不可用";
}
#endif
