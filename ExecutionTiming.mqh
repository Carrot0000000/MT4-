#ifndef CODEX_EXECUTION_TIMING_V010
#define CODEX_EXECUTION_TIMING_V010
// Only order-modification-specific failures may let a close bypass modify backoff.
// Busy/timeout/connection/rate-limit/unknown errors retain shared channel backoff.
bool APModifyBlocksClose(const int error)
{ return error!=0 && error!=1 && error!=130 && error!=145; }
datetime APActionReadyAt(const datetime own,const datetime channel,const datetime legacy)
{ return (datetime)MathMax((double)own,MathMax((double)channel,(double)legacy)); }
int APSecondsLeft(const datetime deadline,const datetime now)
{ return (int)MathMax(0,(double)(deadline-now)); }
int APHoldSecondsLeft(const datetime opened,const datetime now,const int minutes)
{ return minutes<=0?-1:APSecondsLeft(opened+minutes*60,now); }
#endif
