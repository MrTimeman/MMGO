// Combat — caster POV, simultaneous turn, grimoire + incantation

const ENEMIES = [
  {id:'e1', name:'Гоблин-вор',  hp:28, maxHp:28, states:['exposed']},
  {id:'e2', name:'Пещерный жнец', hp:55, maxHp:55, states:['shielded']},
];

const ALLIES = [
  {id:'a1', name:'Вы',        role:'Маг',    hp:null, class:'caster'},
  {id:'a2', name:'Торвальд',  role:'Воин',   hp:null, class:'tool'},
  {id:'a3', name:'Льенн',     role:'Алхимик',hp:null, class:'alch'},
];

const COMBAT_SPELLS = [
  {id:'c1', name:'Ignis Parvus', ru:'Малый огонь', school:'fire'},
  {id:'c2', name:'Aqua Scutum',  ru:'Водный щит', school:'water'},
  {id:'c3', name:'Terra Mure',   ru:'Стена земли', school:'earth'},
];

function Combat({onLeave}){
  const [partyHp, setPartyHp] = React.useState(72);
  const [enemyHp, setEnemyHp] = React.useState(83);
  const [partyMax] = React.useState(100);
  const [enemyMax] = React.useState(100);
  const [turn, setTurn] = React.useState(3);
  const [timer, setTimer] = React.useState(42);
  const [base, setBase] = React.useState('c1');
  const [incant, setIncant] = React.useState('Conus Magnus');
  // Target is derived from the spell + circumstances, NOT picked:
  //   - attack spells → the most threatening enemy marked by the party
  //   - defence spells → whoever's in trouble
  //   - utility → environment / situation
  // Player can influence via incantation ("...in scutum Torvaldis").
  const auto = (()=>{
    const spell = COMBAT_SPELLS.find(s=>s.id===base);
    if(!spell) return {kind:'none', label:'—'};
    if(spell.school==='fire' || spell.school==='air') {
      const focus = ENEMIES.find(e=>e.states.includes('exposed')) || ENEMIES[0];
      return {kind:'enemy', label:focus.name, reason:'самый открытый противник'};
    }
    if(spell.school==='water') {
      const ally = ALLIES[0]; // you
      return {kind:'ally', label:ally.name, reason:'ближайший союзник'};
    }
    if(spell.school==='earth') {
      return {kind:'area', label:'стена между отрядом и врагами', reason:'разделить поле боя'};
    }
    return {kind:'self', label:'Вы', reason:'на себя'};
  })();
  const [log, setLog] = React.useState([
    {t:'system', text:'Ход 2. Торвальд бьёт мечом: Жнец оглушён на 1 ход.'},
    {t:'narr',   text:'Пещера пахнет серой. Где-то сзади капает вода — ровно, как метроном.'},
  ]);
  const [resolving, setResolving] = React.useState(false);

  // timer tick
  React.useEffect(()=>{
    const id = setInterval(()=>setTimer(t=> t>0 ? t-1 : 0), 1000);
    return ()=>clearInterval(id);
  },[turn]);

  function submit(){
    setResolving(true);
    setLog(l=>[...l,
      {t:'action', text:`Вы: ${COMBAT_SPELLS.find(s=>s.id===base).name} + «${incant}» → ${auto.label}`},
    ]);
    setTimeout(()=>{
      setLog(l=>[...l,
        {t:'narr', text:'Ваш огонь сворачивается в узкий конус и обжигает жнецу плечо; его щит слетает с щелчком, как отстёгнутая застёжка. Торвальд, не мешкая, режет по открытой спине.'},
        {t:'system', text:'Жнец: burning (3 т), shielded снят. Урон 18.'},
      ]);
      setEnemyHp(h=>Math.max(0, h-18));
      setTurn(t=>t+1);
      setTimer(45);
      setResolving(false);
    }, 1400);
  }

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>

      <div style={{position:'relative', padding:'8px 12px 4px'}}>
        <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', gap:8, marginBottom:4}}>
          <Chip color="wax">Ход {turn}</Chip>
          <div style={{fontFamily:'var(--mono)', fontSize:11, color: timer<15?'var(--wax)':'var(--ink-soft)'}}>
            ⏳ {Math.floor(timer/60)}:{String(timer%60).padStart(2,'0')}
          </div>
          <Chip color="ink">Дуэль · 3v2</Chip>
        </div>
        <HpBars pHp={partyHp} pMax={partyMax} eHp={enemyHp} eMax={enemyMax}/>
      </div>

      {/* Field */}
      <div style={{position:'relative', padding:'4px 12px 0'}}>
        <div style={{
          padding:8, borderRadius:8,
          background:'rgba(60,35,10,0.05)', border:'1px dashed rgba(60,35,10,0.3)',
        }}>
          <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--ink-faint)', textTransform:'uppercase', letterSpacing:'.08em', marginBottom:4}}>Противники</div>
          <div style={{display:'flex', gap:6}}>
            {ENEMIES.map(e=>{
              const isFocus = auto.kind==='enemy' && auto.label===e.name;
              return (
                <div key={e.id} style={{
                  flex:1, padding:'6px 8px',
                  background: isFocus ? 'oklch(0.88 0.08 30 / 0.5)':'oklch(0.94 0.03 80)',
                  border:`1px solid ${isFocus?'var(--wax)':'rgba(60,35,10,0.3)'}`,
                  borderRadius:6, position:'relative',
                }}>
                  <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:12}}>{e.name}</div>
                  <div style={{display:'flex', gap:3, marginTop:3, flexWrap:'wrap'}}>
                    {e.states.map(s=><Chip key={s} color="magic" style={{fontSize:8, padding:'1px 5px'}}>{s}</Chip>)}
                  </div>
                  {isFocus && (
                    <div style={{
                      position:'absolute', top:-6, right:-4,
                      fontFamily:'var(--rune)', fontSize:14, color:'var(--wax)',
                      filter:'drop-shadow(0 0 3px var(--wax-soft))',
                    }}>✦</div>
                  )}
                </div>
              );
            })}
          </div>

          <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--ink-faint)', textTransform:'uppercase', letterSpacing:'.08em', margin:'8px 0 4px'}}>Отряд</div>
          <div style={{display:'flex', gap:6}}>
            {ALLIES.map(a=>(
              <div key={a.id} style={{
                flex:1, padding:'5px 7px',
                background:'oklch(0.94 0.03 80)',
                border:`1px solid ${a.id==='a1'?'var(--magic)':'rgba(60,35,10,0.25)'}`,
                borderRadius:6,
              }}>
                <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:11}}>{a.name}</div>
                <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--ink-faint)'}}>{a.role}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Log */}
      <div className="mmgo-scroll" style={{
        position:'relative', flex:1, overflow:'auto', padding:'8px 12px',
        margin:'8px 12px 0', borderRadius:8,
        background:'oklch(0.97 0.015 82)', border:'1px solid rgba(60,35,10,0.25)',
        boxShadow:'inset 0 2px 4px rgba(60,35,10,0.1)',
      }}>
        {log.map((l,i)=>(
          <div key={i} style={{
            fontSize: l.t==='narr'?13:11,
            lineHeight:1.45, marginBottom:6,
            fontFamily: l.t==='narr'?'var(--serif)':'var(--mono)',
            fontStyle: l.t==='narr'?'italic':'normal',
            color: l.t==='system'?'var(--ink-faint)':(l.t==='action'?'var(--magic)':'var(--ink)'),
          }}>
            {l.t==='system'&&'▸ '}{l.t==='action'&&'❯ '}{l.text}
          </div>
        ))}
      </div>

      {/* Caster action panel */}
      <div style={{position:'relative', padding:'10px 12px 12px'}}>
        <div style={{display:'flex', gap:6, marginBottom:6, overflowX:'auto', paddingBottom:2}}>
          {COMBAT_SPELLS.map(s=>(
            <button key={s.id} onClick={()=>setBase(s.id)} style={{
              padding:'6px 10px', flexShrink:0,
              background: base===s.id?`oklch(from var(--s-${s.school}) 0.9 calc(c*.5) h)`:'oklch(0.94 0.03 80)',
              border:`1px solid ${base===s.id?`var(--s-${s.school})`:'rgba(60,35,10,0.3)'}`,
              borderRadius:6, cursor:'pointer', textAlign:'left',
              fontFamily:'var(--display)', fontSize:11, fontWeight:700,
            }}>
              <span style={{fontFamily:'var(--rune)', color:`var(--s-${s.school})`, marginRight:4}}>{SCHOOL_GLYPH[s.school]}</span>
              {s.name}
            </button>
          ))}
        </div>
        <div style={{
          display:'flex', alignItems:'center', gap:6,
          padding:'3px 8px', marginBottom:4,
          background:'rgba(60,35,10,0.05)',
          border:'1px dashed rgba(60,35,10,0.3)',
          borderRadius:6,
          fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)',
        }}>
          <span style={{fontFamily:'var(--rune)', fontSize:12, color:'var(--wax)'}}>❯</span>
          <span>цель определится сама: <strong style={{color:'var(--ink)', fontStyle:'normal', fontFamily:'var(--display)', fontWeight:700}}>{auto.label}</strong> <span style={{color:'var(--ink-faint)'}}>— {auto.reason}</span></span>
        </div>
        <div style={{
          display:'flex', gap:6, alignItems:'center',
          padding:'4px 4px 4px 10px',
          background:'oklch(0.97 0.015 82)',
          border:'1px solid rgba(60,35,10,0.35)',
          borderRadius:10,
        }}>
          <span style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--magic)'}}>✦</span>
          <input value={incant} onChange={e=>setIncant(e.target.value)}
            placeholder="Latin incantation…"
            style={{
              flex:1, border:'none', background:'transparent', outline:'none',
              fontFamily:'var(--mono)', fontSize:13, color:'var(--ink)',
            }}/>
          <button className="inkbtn primary" onClick={submit} disabled={resolving || !incant.trim()}
            style={{padding:'6px 12px', fontSize:12}}>
            {resolving?'…':'Произнести'}
          </button>
        </div>
        <div style={{display:'flex', gap:6, marginTop:6, justifyContent:'center'}}>
          <button className="inkbtn ghost" style={{padding:'4px 10px', fontSize:10}}>Готовый план</button>
          <button className="inkbtn ghost" style={{padding:'4px 10px', fontSize:10}}>Пропустить</button>
          <button className="inkbtn ghost" style={{padding:'4px 10px', fontSize:10}} onClick={onLeave}>Бежать</button>
        </div>
      </div>
    </div>
  );
}

function HpBars({pHp, pMax, eHp, eMax}){
  return (
    <div style={{display:'flex', flexDirection:'column', gap:4, fontFamily:'var(--mono)', fontSize:10}}>
      <Bar label="Отряд" val={pHp} max={pMax} color="var(--verdigris)"/>
      <Bar label="Враги" val={eHp} max={eMax} color="var(--wax)"/>
    </div>
  );
}
function Bar({label, val, max, color}){
  return (
    <div style={{display:'flex', alignItems:'center', gap:6}}>
      <span style={{width:40, color:'var(--ink-soft)', textTransform:'uppercase', letterSpacing:'.06em', fontSize:9}}>{label}</span>
      <div style={{
        flex:1, height:10, borderRadius:3,
        background:'rgba(60,35,10,0.12)',
        border:'1px solid rgba(60,35,10,0.3)',
        position:'relative', overflow:'hidden',
      }}>
        <div style={{
          width:`${(val/max)*100}%`, height:'100%',
          background:`linear-gradient(180deg, ${color}, oklch(from ${color} calc(l*.7) c h))`,
          transition:'width .4s ease',
        }}/>
      </div>
      <span style={{width:46, textAlign:'right'}}>{val}/{max}</span>
    </div>
  );
}

Object.assign(window, { Combat });
