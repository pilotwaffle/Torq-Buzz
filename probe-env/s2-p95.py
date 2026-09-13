import re,sys,math,collections
f=sys.argv[1]; sent={}; lat=collections.defaultdict(list)
for l in open(f,encoding='utf-8'):
    m=re.search(r'\[agent-controls\] sent kind=(\w+) id=(\S+).* ms=(\d+)',l)
    if m: sent[m[2]]=(m[1],int(m[3]))
    m=re.search(r'\[agent-controls\] ack id=(\S+) status=(\S+) branch=(\S+) ms=(\d+)',l)
    if m and m[1] in sent: k,t=sent[m[1]]; lat[k].append((int(m[4])-t,m[2],m[3]))
for k,v in lat.items():
    ms=sorted(x[0] for x in v); n=len(ms); p95=ms[math.ceil(.95*n)-1]
    st=collections.Counter(x[1] for x in v); br=collections.Counter(x[2] for x in v)
    print(f'{k:7s} n={n:2d} p50={ms[n//2]:5d} p95={p95:5d} max={ms[-1]:5d}  status={dict(st)} branch={dict(br)}')
print('sent without ack:', {k:sum(1 for i,(kk,_) in sent.items() if kk==k)-len(v) for k,v in lat.items()})
