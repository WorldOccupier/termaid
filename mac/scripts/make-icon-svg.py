import sys,os
os.chdir(sys.argv[1])
sq="M285 100H739C841 100 924 183 924 285V739C924 841 841 924 739 924H285C183 924 100 841 100 739V285C100 183 183 100 285 100Z"
A="rgba(255,255,255,.75)"
SHAPES={'top':'<rect x="35" y="16.5" width="30" height="15" rx="3.5" {a}/>',
 'dia':'<path d="M50 39L62 51L50 63L38 51Z" {a}/>',
 'l':'<rect x="15" y="62" width="26" height="14" rx="7" {a}/>',
 'r':'<rect x="59" y="62" width="26" height="14" rx="7" {a}/>'}
ARROWS=f'''<path d="M50 31.5L50 34.6" stroke="{A}" stroke-width="3"/><path d="M46.6 34.6L53.4 34.6L50 38.8Z" fill="{A}"/><path d="M42.3 54.7L38.9 58.7" stroke="{A}" stroke-width="3"/><path d="M41.2 60.6L36.6 56.8L36 62Z" fill="{A}"/><path d="M57.7 54.7L61.1 58.7" stroke="{A}" stroke-width="3"/><path d="M58.8 60.6L63.4 56.8L64 62Z" fill="{A}"/>'''
def stops(cols):
    n=len(cols)-1; return "".join(f'<stop offset="{i/n:.3f}" stop-color="{c}"/>' for i,c in enumerate(cols))
FILL_OP=1
def candy(fills, warm, shadow):
    """fills: dict shape->(gradient cols, x1,y1,x2,y2 userspace) or one shared"""
    d='<defs>'
    for k,(cols,co) in fills.items():
        d+=f'<linearGradient id="f_{k}" gradientUnits="userSpaceOnUse" x1="{co[0]}" y1="{co[1]}" x2="{co[2]}" y2="{co[3]}">{stops(cols)}</linearGradient>'
    # per-shape (bbox) dimensional overlays
    d+=('<linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".08"/>'
        '<stop offset=".45" stop-color="#fff" stop-opacity="0"/><stop offset=".7" stop-color="#000" stop-opacity="0"/>'
        '<stop offset="1" stop-color="#052e16" stop-opacity=".22"/></linearGradient>'
        f'<radialGradient id="warm" cx=".82" cy=".85" r=".55"><stop offset="0" stop-color="{warm}" stop-opacity=".75"/><stop offset="1" stop-color="{warm}" stop-opacity="0"/></radialGradient>'
        '<radialGradient id="spec" cx=".3" cy=".22" r=".42"><stop offset="0" stop-color="#fff" stop-opacity=".2"/><stop offset=".35" stop-color="#fff" stop-opacity=".07"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
        '</defs>')
    b=''
    for k,s in SHAPES.items():
        fk=k if k in fills else 'all'
        b+=s.format(a=f'fill="{shadow}" transform="translate(0 1.4)"')
        b+=s.format(a=f'fill="url(#f_{fk})" fill-opacity="{FILL_OP}"')
        b+=s.format(a='fill="url(#spec)"')
        b+=s.format(a='fill="none" stroke="#fff" stroke-opacity=".12" stroke-width=".6"')
    return d, b
def icon(fn,bg,glow1,glow2,fills,warm="#FDBA74",shadow="rgba(0,0,0,.28)",outline="rgba(255,255,255,.75)"):
    defs=(f'<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">{stops(bg)}</linearGradient>'
          f'<radialGradient id="g1" cx="0.15" cy="0.1" r="0.82"><stop offset="0" stop-color="{glow1[0]}" stop-opacity="{glow1[1]}"/><stop offset="1" stop-color="{glow1[0]}" stop-opacity="0"/></radialGradient>'
          f'<radialGradient id="g2" cx="0.95" cy="0.95" r="0.6"><stop offset="0" stop-color="{glow2[0]}" stop-opacity="{glow2[1]}"/><stop offset="1" stop-color="{glow2[0]}" stop-opacity="0"/></radialGradient>'
          '<radialGradient id="b1" cx="0.95" cy="0.05" r="0.55"><stop offset="0" stop-color="#38BDF8" stop-opacity=".55"/><stop offset="1" stop-color="#38BDF8" stop-opacity="0"/></radialGradient><radialGradient id="b2" cx="0.05" cy="0.95" r="0.55"><stop offset="0" stop-color="#38BDF8" stop-opacity=".55"/><stop offset="1" stop-color="#38BDF8" stop-opacity="0"/></radialGradient>')
    cd,cb=candy(fills,warm,shadow)
    svg=(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{defs}</defs>'
         f'<path d="{sq}" fill="url(#bg)"/><path d="{sq}" fill="url(#g1)"/><path d="{sq}" fill="url(#g2)"/>'
         f'<path d="{sq}" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="6"/>'
         f'<g transform="translate(102 102) scale(8.2)">{cd}'
         f'<g transform="translate(50 50) scale(1.06) translate(-50 -46.25)">{ARROWS}{cb}</g></g></svg>')
    open(fn,"w").write(svg)
G=(["#166534","#14532D"],("#A3E635",.57),("#065F46",.65))
DIAG=(28,16,72,84)
G3=(["#25A85A","#1A8A48"],("#C2F56A",.7),("#C2F56A",.7))
FILL_OP=.6
W=["#FFFFFF","#FFFFFF"]
V=[
("w1","White · 40%",G3,{'all':(W,DIAG)},"#FFFFFF","White, slightly see-through, low shine."),
]
for fn,name,(bg,g1,g2),fills,warm,_ in V: icon(fn+".svg",bg,g1,g2,fills,warm,shadow="rgba(0,0,0,0)")
nb=[("#3b82f6","#1d4ed8"),("#1f1f23","#000"),("#0ea5e9","#0369a1"),("#e5e7eb","#9ca3af")]
def tile(c1,c2): return f'<div style="width:64px;height:64px;border-radius:15px;background:linear-gradient({c1},{c2});margin:0 4px"></div>'
def dock(fn,bg): return f'<div style="display:flex;align-items:center;background:{bg};padding:10px 14px;border-radius:20px">{tile(*nb[0])}{tile(*nb[1])}<img src="{fn}" width=80 style="margin:-8px">{tile(*nb[2])}{tile(*nb[3])}</div>'
rows="".join(f'''<div class=row><div class=lbl>{fn}<br><b>{n}</b><small>{feel}</small></div><img src="{fn}.svg" width=220><img src="{fn}.svg" width=32>
<div>{dock(fn+".svg","rgba(40,40,46,.92)")}<div style="height:10px"></div>{dock(fn+".svg","rgba(235,235,240,.92)")}</div></div>''' for fn,n,_,_,_,feel in V)
open("sheet.html","w").write(f'''<html><style>body{{background:linear-gradient(135deg,#334155,#64748b);color:#fff;font-family:Avenir Next;padding:24px}}
.row{{display:flex;gap:24px;align-items:center;margin:18px 0}}.lbl{{width:200px;font-size:14px;opacity:.9}}.lbl b{{font-size:18px;display:block}}small{{display:block;margin-top:4px;opacity:.8}}</style>
<body><h2>termaid · mascot-style glossy candy flowcharts</h2><p>Large, at 32 px, and in dark and light Docks.</p>{rows}</body></html>''')
