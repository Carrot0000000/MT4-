#ifndef CODEX_FORWARD_CORE
#define CODEX_FORWARD_CORE
// Pure forward experiment calculations. No terminal order operations.
struct FLBook
{
   bool active;int index,side,n,wins;long seq;
   datetime opened,last_close,bar_gold,bar_silver;
   double start,cash,fill,sl,tp,lots,units,r,slip,fee,peak,worst,spread,initial_sl;
   double gains,losses,stress_sum,high_water,max_drawdown,log0,log1,log2,r_sum,score_sum;
   double m5_close,m5_ema,m5_atr,h1_close,h1_ema,m15_close,m15_ema,m15_previous_ema;
};
enum FLExit {FL_NONE=0,FL_STOP=1,FL_TARGET=2,FL_GIVEBACK=3,FL_TIME=4};
int FLFastBias(const double close,const double ema,const double previous_ema)
{
   if(!APFinitePositive(close)||!APFinitePositive(ema)||!APFinitePositive(previous_ema))return 0;
   if(close>ema&&ema>previous_ema)return 1;
   if(close<ema&&ema<previous_ema)return -1;
   return 0;
}
int FLDirection(const int model,const int h1,const int m15)
{return model==0?h1:model==1?m15:model==2&&h1==m15?h1:0;}
double FLScore(const double net_r)
{return MathIsValidNumber(net_r)?net_r/(1+MathAbs(net_r)):0;}
double FLLogMixture(const double a,const double b,const double c)
{
   double top=MathMax(a,MathMax(b,c));
   return top+MathLog((MathExp(a-top)+MathExp(b-top)+MathExp(c-top))/3);
}
double FLPosteriorMean(const int wins,const int count)
{return count>=0&&wins>=0&&wins<=count?(wins+1.0)/(count+2.0):-1;}
void FLInit(FLBook &p,const double balance)
{ZeroMemory(p);p.start=balance;p.cash=balance;p.high_water=balance;}
double FLMark(FLBook &p,const double bid,const double ask)
{
   double price=p.side==1?bid:ask;
   double net=APNet(p.side,p.fill,price,p.units,p.fee);
   p.peak=MathMax(p.peak,net);p.worst=MathMin(p.worst,net);
   double equity=p.cash+net-p.slip*p.units;
   p.high_water=MathMax(p.high_water,equity);p.max_drawdown=MathMax(p.max_drawdown,p.high_water-equity);
   return net;
}
int FLExitChoice(const FLBook &p,const double bid,const double ask,const datetime now,const int hold_minutes)
{
   double price=p.side==1?bid:ask;
   if((p.side==1&&price<=p.sl)||(p.side==-1&&price>=p.sl))return FL_STOP;
   if((p.side==1&&price>=p.tp)||(p.side==-1&&price<=p.tp))return FL_TARGET;
   double net=APNet(p.side,p.fill,price,p.units,p.fee);
   if(APGiveback(p.peak,net,p.r))return FL_GIVEBACK;
   if(hold_minutes>0&&now>=p.opened&&now-p.opened>=hold_minutes*60)return FL_TIME;
   return FL_NONE;
}
double FLExitPrice(const FLBook &p,const double bid,const double ask,const int why)
{
   // TP is capped at its resting limit. Stop gaps use the sampled quote, never an invented SL fill.
   if(why==FL_TARGET)return p.tp;
   return (p.side==1?bid:ask)-p.side*p.slip;
}
bool FLTighten(FLBook &p,const double bid,const double ask,const double tick,const int digits,const double minimum_distance)
{
   double net=APNet(p.side,p.fill,p.side==1?bid:ask,p.units,p.fee);
   if(net<p.r)return false;
   double target=APBreakEven(p.fill,p.units,p.fee,p.slip,tick,digits,p.side);
   if(!APFinitePositive(target)||!MathIsValidNumber(minimum_distance)||minimum_distance<0)return false;
   if((p.side==1&&(target<=p.sl+tick*.5||target>=bid-minimum_distance))||
      (p.side==-1&&(target>=p.sl-tick*.5||target<=ask+minimum_distance)))return false;
   p.sl=target;return true;
}
double FLFinalize(FLBook &p,const double exit,const datetime now)
{
   double net=APNet(p.side,p.fill,exit,p.units,p.fee);
   double net_r=net/p.r,score=FLScore(net_r);
   p.cash+=net;p.n++;if(net>0){p.wins++;p.gains+=net;}else p.losses-=net;
   p.stress_sum+=net-(p.spread+p.slip)*p.units;
   p.r_sum+=net_r;p.score_sum+=score;
   // Fixed, preregistered mixture; lambda is not tuned after seeing returns.
   p.log0+=MathLog(1+.10*score);p.log1+=MathLog(1+.25*score);p.log2+=MathLog(1+.50*score);
   p.high_water=MathMax(p.high_water,p.cash);p.max_drawdown=MathMax(p.max_drawdown,p.high_water-p.cash);
   p.active=false;p.last_close=now;return net;
}
bool FLStateValid(const FLBook &p)
{
   double numbers[32];
   numbers[0]=p.start;numbers[1]=p.cash;numbers[2]=p.fill;numbers[3]=p.sl;numbers[4]=p.tp;numbers[5]=p.lots;numbers[6]=p.units;numbers[7]=p.r;
   numbers[8]=p.slip;numbers[9]=p.fee;numbers[10]=p.peak;numbers[11]=p.worst;numbers[12]=p.spread;numbers[13]=p.initial_sl;
   numbers[14]=p.gains;numbers[15]=p.losses;numbers[16]=p.stress_sum;numbers[17]=p.high_water;numbers[18]=p.max_drawdown;
   numbers[19]=p.log0;numbers[20]=p.log1;numbers[21]=p.log2;numbers[22]=p.r_sum;numbers[23]=p.score_sum;
   numbers[24]=p.m5_close;numbers[25]=p.m5_ema;numbers[26]=p.m5_atr;numbers[27]=p.h1_close;numbers[28]=p.h1_ema;
   numbers[29]=p.m15_close;numbers[30]=p.m15_ema;numbers[31]=p.m15_previous_ema;
   for(int i=0;i<ArraySize(numbers);i++)if(!MathIsValidNumber(numbers[i]))return false;
   if(!APFinitePositive(p.start)||!MathIsValidNumber(p.cash)||p.n<0||p.wins<0||p.wins>p.n||p.seq<0||
      !MathIsValidNumber(p.log0)||!MathIsValidNumber(p.log1)||!MathIsValidNumber(p.log2)||
      !MathIsValidNumber(p.gains)||!MathIsValidNumber(p.losses)||p.gains<0||p.losses<0)return false;
   if(!p.active)return true;
   return p.index>=0&&p.index<2&&(p.side==1||p.side==-1)&&p.opened>0&&APFinitePositive(p.fill)&&
      APFinitePositive(p.sl)&&APFinitePositive(p.tp)&&APFinitePositive(p.lots)&&APFinitePositive(p.units)&&
      APFinitePositive(p.r)&&p.slip>=0&&p.fee>=0;
}
bool FLNumberToken(const string text)
{
   int digits=0,dots=0;
   for(int i=0;i<StringLen(text);i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(c>=48&&c<=57){digits++;continue;}
      if(c==45&&i==0)continue;
      if(c==46&&++dots==1)continue;
      return false;
   }
   return digits>0;
}
#endif
