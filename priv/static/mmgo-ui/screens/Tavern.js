// Tavern — hire crew (tool/alch), drink, listen for rumours.
// Implements the GDD's "tool"-class (warrior/scout) and "alch"-class (alchemist/healer)
// who travel with the caster, plus a rumour board.

const HIREABLES = [
  {
    id:'torvald', name:'Торвальд', role:'Воин (tool)',
    cost:18, day:'нанят на день',
    skills:['меч-щит','подавление','инициатива'],
    short:'Бывший дружинник. Молчалив. Не любит магов, но идёт за деньги.',
    school:'tool',
  },
  {
    id:'lien', name:'Льенн', role:'Алхимик (alch)',
    cost:22, day:'на день',
    skills:['зелья','лечение','травы'],
    short:'Студентка с факультета алхимии. Подрабатывает между лекциями.',
    school:'alch',
  },
  {
    id:'gris', name:'Грис', role:'Лучник (tool)',
    cost:14, day:'на день',
    skills:['лук','следы','бесшумность'],
    short:'Охотник из Малых Вод. Знает все тропы возле озера.',
    school:'tool',
  },
  {
    id:'morv', name:'Морв', role:'Ремонтник (tool)',
    cost:12, day:'на день',
    skills:['ловушки','замки','верёвки'],
    short:'Глуховатый, но руки — золото. Берёт авансом.',
    school:'tool',
  },
];

const RUMOURS = [
  {tag:'башня', text:'Говорят, на нижнем ярусе подземелья снова шумит.', hot:true},
  {tag:'рынок', text:'Купцы из Верхнего Предела привезли соль вдвое дешевле обычного.'},
  {tag:'двор',  text:'Княжеский писарь ищет сведущего в латыни. Платит исправно.'},
  {tag:'хутор', text:'У Жёлтых Полей третий день подряд кто-то портит изгородь.'},
];

function Tavern({onLeave, party=[], setParty}){
  const [tab, setTab] = React.useState('hire');
  const localParty = party && party.length ? party : ['torvald','lien'];
  const partySet = new Set(localParty);

  function toggleHire(id){
    const next = partySet.has(id)
      ? localParty.filter(x=>x!==id)
      : (localParty.length<3 ? [...localParty, id] : localParty);
    setParty && setParty(next);
  }

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>

      {/* Header — wood panel header */}
      <div style={{
        position:'relative',
        padding:'12px 14px 10px',
        background:'linear-gradient(180deg, oklch(0.42 0.07 35), oklch(0.34 0.07 33))',
        borderBottom:'1px solid rgba(0,0,0,0.45)',
        boxShadow:'inset 0 -2px 0 rgba(0,0,0,0.3)',
        color:'#f5ead3',
      }}>
        <div style={{
          fontFamily:'var(--script)', fontSize:18, lineHeight:1,
          color:'var(--gilt)', letterSpacing:'.04em', textAlign:'center',
        }}>«Три пера»</div>
        <div style={{
          fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11,
          color:'rgba(245,234,211,0.7)', textAlign:'center', marginTop:2,
        }}>таверна и заезжий дом</div>
      </div>

      <div style={{
        display:'flex', borderBottom:'1px solid rgba(60,35,10,0.3)',
        background:'var(--vellum-2)',
      }}>
        {[['hire','Доска найма'],['rumours','Слухи'],['drink','Заказать']].map(([k,l])=>(
          <button key={k} onClick={()=>setTab(k)} style={{
            flex:1, padding:'8px 4px', cursor:'pointer',
            background: tab===k?'var(--vellum)':'transparent',
            border:'none',
            borderBottom: tab===k?'2px solid var(--wax)':'2px solid transparent',
            fontFamily:'var(--display)', fontWeight: tab===k?700:500, fontSize:12,
            color: tab===k?'var(--ink)':'var(--ink-soft)',
            letterSpacing:'.04em',
          }}>{l}</button>
        ))}
      </div>

      <div className="mmgo-scroll" style={{position:'relative', flex:1, overflow:'auto', padding:'10px 12px 0'}}>
        {tab==='hire' && (
          <div>
            <div style={{
              fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-faint)',
              textTransform:'uppercase', letterSpacing:'.08em', marginBottom:6,
              display:'flex', justifyContent:'space-between',
            }}>
              <span>Доска найма</span>
              <span>в отряде {localParty.length}/3</span>
            </div>
            <div style={{
              padding:8, borderRadius:6,
              background:'linear-gradient(180deg, oklch(0.45 0.05 38), oklch(0.36 0.05 36))',
              border:'2px solid oklch(0.22 0.03 36)',
              boxShadow:'inset 0 0 8px rgba(0,0,0,0.35)',
              display:'flex', flexDirection:'column', gap:8,
            }}>
              {HIREABLES.map((h,i)=>{
                const hired = partySet.has(h.id);
                return (
                  <div key={h.id} style={{
                    padding:'10px 12px',
                    background:'oklch(0.95 0.03 82)',
                    border:'1px solid rgba(60,35,10,0.3)',
                    borderRadius:2,
                    transform: `rotate(${(i%2===0?-0.6:0.5)}deg)`,
                    boxShadow:'0 2px 5px rgba(0,0,0,0.35)',
                    position:'relative',
                  }}>
                    {/* tack */}
                    <div style={{
                      position:'absolute', top:-5, left:'50%', transform:'translateX(-50%)',
                      width:8, height:8, borderRadius:'50%',
                      background:'radial-gradient(circle at 35% 30%, oklch(0.7 0.15 25), oklch(0.45 0.15 25))',
                      boxShadow:'0 1px 2px rgba(0,0,0,0.5)',
                    }}/>
                    <div style={{display:'flex', justifyContent:'space-between', alignItems:'baseline', gap:8}}>
                      <div>
                        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:14, color:'var(--ink)'}}>{h.name}</div>
                        <div style={{fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)', marginTop:1}}>{h.role}</div>
                      </div>
                      <div style={{textAlign:'right'}}>
                        <div style={{fontFamily:'var(--mono)', fontSize:13, color:'var(--ink)'}}>{h.cost}<span style={{color:'var(--gilt)', marginLeft:2}}>🜚</span></div>
                        <div style={{fontSize:9, color:'var(--ink-faint)'}}>{h.day}</div>
                      </div>
                    </div>
                    <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)', marginTop:6}}>
                      «{h.short}»
                    </div>
                    <div style={{display:'flex', gap:4, flexWrap:'wrap', marginTop:8}}>
                      {h.skills.map(s=>(
                        <span key={s} style={{
                          fontFamily:'var(--mono)', fontSize:9,
                          padding:'1px 6px', borderRadius:3,
                          background:'oklch(0.9 0.03 80)',
                          border:'1px solid rgba(60,35,10,0.25)',
                          color:'var(--ink-soft)',
                        }}>{s}</span>
                      ))}
                    </div>
                    <button onClick={()=>toggleHire(h.id)}
                      className={`inkbtn${hired?' primary':''}`}
                      style={{marginTop:10, width:'100%', padding:'6px', fontSize:11}}>
                      {hired?'✓ уже в отряде — отказать':'нанять'}
                    </button>
                  </div>
                );
              })}
            </div>
            <div style={{marginTop:10, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-faint)', textAlign:'center'}}>
              Tool — за оружие. Alch — за зелья. Caster — это вы.
            </div>
          </div>
        )}

        {tab==='rumours' && (
          <div>
            <Ornament tiny>Слухи дня</Ornament>
            <div style={{marginTop:8, display:'flex', flexDirection:'column', gap:8}}>
              {RUMOURS.map((r,i)=>(
                <div key={i} style={{
                  padding:'10px 12px',
                  background:'var(--vellum)',
                  border:`1px solid ${r.hot?'var(--wax)':'rgba(60,35,10,0.3)'}`,
                  borderLeft:`3px solid ${r.hot?'var(--wax)':'var(--ink-soft)'}`,
                  borderRadius:6,
                  position:'relative',
                }}>
                  <div style={{display:'flex', gap:8, alignItems:'baseline'}}>
                    <span style={{
                      fontFamily:'var(--mono)', fontSize:9,
                      padding:'1px 6px', borderRadius:2,
                      background:'rgba(60,35,10,0.08)', color:'var(--ink-soft)',
                      textTransform:'uppercase', letterSpacing:'.05em',
                    }}>{r.tag}</span>
                    {r.hot && <span style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--wax)'}}>● горячее</span>}
                  </div>
                  <div style={{fontFamily:'var(--serif)', fontSize:13, marginTop:4, color:'var(--ink)'}}>{r.text}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {tab==='drink' && (
          <div>
            <Ornament tiny>Меню</Ornament>
            <div style={{marginTop:8, padding:14, background:'var(--vellum)', border:'1px solid rgba(60,35,10,0.3)', borderRadius:8}}>
              <ul style={{listStyle:'none', padding:0, margin:0, fontFamily:'var(--serif)', fontSize:13}}>
                {[
                  ['Эль тёмный, кружка',     2],
                  ['Вино из Малых Вод',      6],
                  ['Похлёбка с олениной',    4],
                  ['Жаркое + хлеб + сыр',    9],
                  ['Постель до утра',       10],
                ].map(([n,p])=>(
                  <li key={n} style={{display:'flex', justifyContent:'space-between', padding:'6px 0', borderBottom:'1px dotted rgba(60,35,10,0.25)'}}>
                    <span>{n}</span>
                    <span style={{fontFamily:'var(--mono)', color:'var(--ink-soft)'}}>{p} <span style={{color:'var(--gilt)'}}>🜚</span></span>
                  </li>
                ))}
              </ul>
              <button className="inkbtn primary" style={{width:'100%', marginTop:10}}>Заказать всё (31🜚)</button>
            </div>
            <div style={{marginTop:10, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-faint)', textAlign:'center'}}>
              Тёплая еда возвращает 1 ⚡ и сбрасывает усталость до утра.
            </div>
          </div>
        )}
      </div>

      <div style={{
        borderTop:'1px solid rgba(60,35,10,0.4)',
        padding:'10px 12px',
        display:'flex', alignItems:'center', justifyContent:'space-between',
        background:'var(--vellum-2)',
      }}>
        <div style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--ink-soft)'}}>
          отряд: {localParty.map(id=>HIREABLES.find(h=>h.id===id)?.name.split(' ')[0]).join(' · ')}
        </div>
        <button className="inkbtn ghost" onClick={onLeave}>Выйти</button>
      </div>
    </div>
  );
}

Object.assign(window, { Tavern, HIREABLES });
