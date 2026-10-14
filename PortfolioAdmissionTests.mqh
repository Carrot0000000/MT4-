
bool fixture_quotes=true,fixture_save=true;double fixture_risk=1.3,fixture_margin=100;int fixture_writes=0;
bool FixtureQuotes(const int index,Spec &s){return fixture_quotes;}
bool FixturePlan(const int model,const int index,const Spec &s,FLBook &p,const double remaining)
{p.r=fixture_risk;p.lots=.01;p.active=true;p.index=index;return true;}
double FixtureMargin(const string symbol,const int type){return fixture_margin;}
bool FixtureSave(const int slot,FLBook &p,const string action,const double net=0,const double stress=0,const double exit=0,const string why="")
{fixture_writes++;return fixture_save;}
bool FixtureAdmission(const int slot,const int index,const double cash,const double equity,const double reserved,const double margin_used)
{
   double remaining=PLFreeBudget(cash,equity,RiskPercent,reserved);if(remaining<=0)return false;
   Spec s;if(!FixtureQuotes(index,s))return false;
   FLBook next=pl_books[slot];double slot_cash=next.cash;next.cash=cash;
   bool okay=FixturePlan(slot,index,s,next,remaining);next.cash=slot_cash;
   if(!okay||next.r>remaining+1e-7)return false;
   double new_margin=FixtureMargin(symbols[index],MODE_MARGINREQUIRED)*next.lots;
   if(!APFinitePositive(new_margin)||margin_used+new_margin>=equity)return false;
   string context="cash="+FF(cash)+"|equity="+FF(equity)+"|reserved_before="+FF(reserved)+"|remaining="+FF(remaining);
   if(!FixtureSave(slot,next,"OPEN",0,0,0,context))return false;
   pl_books[slot]=next;return true;
}
void RunPortfolioAdmissionTests()
{
   for(int i=0;i<3;i++)FLInit(pl_books[i],500);
   fixture_quotes=true;fixture_save=true;fixture_margin=100;fixture_writes=0;fixture_risk=1.3;
   FC(!FixtureAdmission(1,1,500,500,3.8,0)&&fixture_writes==0,"production admission rejects sum risk beyond one percent");
   FC(FixtureAdmission(1,1,500,500,3.7,0)&&fixture_writes==1,"production admission accepts exact remaining risk");
   FC(!FixtureAdmission(1,1,500,490,3.7,0),"production admission checks equity not cash alone");
   fixture_quotes=false;FC(!FixtureAdmission(0,0,500,500,0,0),"stale quote blocks portfolio admission");fixture_quotes=true;
   fixture_margin=100000;FC(!FixtureAdmission(0,0,500,500,0,0),"aggregate virtual margin blocks excess use");fixture_margin=100;
   fixture_save=false;FC(!FixtureAdmission(0,0,500,500,0,0),"unrecorded admission not committed");fixture_save=true;
   FC(!FixtureAdmission(0,0,500,500,5,0),"full existing risk budget cannot be reused");
}
