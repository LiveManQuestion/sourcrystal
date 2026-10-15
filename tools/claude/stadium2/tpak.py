# usage: tpak.py LOG [SYM] - lists the GB ROM and SRAM ranges Stadium 2 read and
# wrote, from a `run.sh ... --verbose` log (lab.sh logs to OUTDIR/PREFIX.log).
import re,sys,bisect
win=0; rombank=1; rambank=0; ev=[]
for l in open(sys.argv[1]):
    m=re.match(r'Core: tpak (write gb|write|read cart): ([0-9a-f]{4})(?: <- ([0-9a-f]{2}))?',l)
    if not m: continue
    kind,a,v=m[1],int(m[2],16),m[3] and int(m[3],16)
    if kind=='write' and 0xa000<=a<0xb000: win=v; continue
    if kind=='write': continue
    gb=win*0x4000+(a-0xc000)
    if kind=='write gb':
        if 0x2000<=gb<0x4000: rombank=v or 1
        elif 0x4000<=gb<0x6000: rambank=v
        elif 0xa000<=gb<0xc000: ev.append(('W',rambank,gb))
        continue
    if gb<0x4000: ev.append(('R','rom',gb))
    elif gb<0x8000: ev.append(('R','rom',rombank*0x4000+gb-0x4000))
    elif 0xa000<=gb<0xc000: ev.append(('R',rambank,gb))
# collapse consecutive 32-byte blocks
out=[]
for k,b,a in ev:
    if out and out[-1][0]==k and out[-1][1]==b and out[-1][3]==a: out[-1][3]=a+32 if k=='R' else a+1
    else: out.append([k,b,a,a+32 if k=='R' else a+1])
syms=[]
if len(sys.argv)>2:
    for l in open(sys.argv[2]):
        m=re.match(r'([0-9a-f]+):([0-9a-f]+) (\S+)',l)
        if m and m[3][0]=='s' and '.' not in m[3]: syms.append((int(m[1],16),int(m[2],16),m[3]))
    syms.sort()
def name(b,a):
    if b=='rom' or not syms: return ''
    i=bisect.bisect_right(syms,(b,a,'~'))-1
    return syms[i][2]+('+%x'%(a-syms[i][1]) if a!=syms[i][1] else '') if i>=0 and syms[i][0]==b else ''
for k,b,s,e in out:
    if b=='rom': print(k,'ROM %02x:%04x-%04x'%(s//0x4000, s%0x4000+(0x4000 if s>=0x4000 else 0), (e-1)%0x4000+(0x4000 if s>=0x4000 else 0)))
    else: print(k,'SRAM %d:%04x-%04x'%(b,s,e-1), name(b,s),'..',name(b,e-1))
