"""Compare section sizes between two .map files.
usage: space.py OLD.map NEW.map [rows]  (positive = bytes saved)"""
import re,sys
def sections(path):
    secs={}; bank=None
    for l in open(path):
        m=re.match(r'^(ROM0|ROMX) bank #(\d+)',l)
        if m: bank=int(m.group(2)) if m.group(1)=='ROMX' else 0
        elif re.match(r'^\S',l): bank=None
        m=re.match(r'\s+SECTION: \$(\w+)-\$(\w+) \(\$(\w+) bytes?\) \["(.*)"\]',l)
        if m and bank is not None: secs[m.group(4)]=(bank,int(m.group(3),16))
    return secs
a=sections(sys.argv[1]); b=sections(sys.argv[2])
tot=0; rows=[]
for k in a:
    if k in b and a[k][1]!=b[k][1]:
        rows.append((a[k][1]-b[k][1],k,a[k][0],a[k][1],b[k][1])); tot+=a[k][1]-b[k][1]
rows.sort(reverse=True)
for r in rows[:int(sys.argv[3]) if len(sys.argv)>3 else 25]: print(f"{r[0]:6d}  bank {r[2]:3d}  {r[3]:5x}->{r[4]:5x}  {r[1]}")
print("total saved:",tot)
