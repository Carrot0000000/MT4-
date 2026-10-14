#ifndef CODEX_SNAPSHOT_WRITER
#define CODEX_SNAPSHOT_WRITER
// Publish a completed file. Readers validate contents and freshness too.
// FileMove is not claimed to offer transactional crash guarantees.
bool WriteSnapshot(const string path,const string payload)
{
   string temporary=path+".writing";
   int f=FileOpen(temporary,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,',',CP_UTF8);
   if(f==INVALID_HANDLE)return false;
   uint written=FileWriteString(f,payload);FileFlush(f);FileClose(f);
   if(written==0)return false;
   return FileMove(temporary,0,path,FILE_REWRITE);
}
#endif
