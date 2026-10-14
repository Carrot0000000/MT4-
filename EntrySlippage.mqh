#ifndef CODEX_ENTRY_SLIPPAGE_V012
#define CODEX_ENTRY_SLIPPAGE_V012
// Reserve opening deviation separately from the existing exit deviation.
double APEntryReserve(const int points,const double point)
{return points>=0&&APFinitePositive(point)?points*point:-1;}
#endif
