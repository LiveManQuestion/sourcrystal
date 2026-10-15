# usage: setmap.py SYM IN.sav OUT.sav GROUP NUMBER  (patches main + backup save, fixes checksums)
import re,sys
sym,src,dst,g,n=sys.argv[1],sys.argv[2],sys.argv[3],int(sys.argv[4]),int(sys.argv[5])
s={}
for l in open(sym):
    m=re.match(r'([0-9a-f]+):([0-9a-f]+) (\S+)',l)
    if m: s[m[3]]=(int(m[1],16),int(m[2],16))
def off(name): b,a=s[name]; return b*0x2000+a-0xa000
d=bytearray(open(src,'rb').read()[:0x8000])
gd=s['wGameData'][1]
for start,end,ck in [('sGameData','sGameDataEnd','sChecksum'),('sBackupGameData','sBackupGameDataEnd','sBackupChecksum')]:
    base=off(start)
    old=sum(d[base:off(end)])&0xffff; stored=d[off(ck)]|d[off(ck)+1]<<8
    print(start,'checksum ok' if old==stored else 'checksum BAD', hex(stored))
    d[base+s['wMapGroup'][1]-gd]=g; d[base+s['wMapNumber'][1]-gd]=n
    c=sum(d[base:off(end)])&0xffff; d[off(ck)]=c&0xff; d[off(ck)+1]=c>>8
open(dst,'wb').write(d)
