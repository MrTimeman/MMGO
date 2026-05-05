// Spell Creation Circle — rotating summoning circle with 6 glyph slots + Latin input + AI mocked preview

const SLOTS = [
  {k:'actio',   ru:'Действие',   hint:'что делает', example:['Ictus','Captio','Scutum','Sanatio','Vocatio']},
  {k:'forma',   ru:'Форма',      hint:'геометрия',  example:['Radius','Sphaera','Murus','Conus','Nexus']},
  {k:'vis',     ru:'Сила',       hint:'интенсивность', example:['Levis','Mediocris','Magnus','Enormis']},
  {k:'tempus',  ru:'Время',      hint:'длительность',  example:['Momentum','Sustineo','Tardus']},
  {k:'mutatio', ru:'Мутация',    hint:'комбо-эффект',  example:['Motus','Glacies','Dissipatio']},
  {k:'pretium', ru:'Цена',       hint:'доп. цена',     example:['Sanguis','Mora','Focus']},
];

const SCHOOLS = ['fire','water','earth','air','chaos','order','life','death'];

const BASE_SPELLS = [
  {id:'ignis-parvus', name:'Ignis Parvus',   school:'fire', gloss:'малое пламя'},
  {id:'aqua-scutum',  name:'Aqua Scutum',    school:'water',gloss:'водяной щит'},
  {id:'terra-mure',   name:'Terra Mure',     school:'earth',gloss:'стена земли'},
  {id:'aer-velox',    name:'Aer Velox',      school:'air',  gloss:'стремительный ветер'},
];

function SpellCircle({onLeave}){
  const [school, setSchool] = React.useState('fire');
  const [base, setBase] = React.useState('ignis-parvus');
  const [words, setWords] = React.useState(['','','','','','']);
  const [focused, setFocused] = React.useState(0);
  const [casting, setCasting] = React.useState(false);
  const [result, setResult] = React.useState(null);

  const filled = words.filter(Boolean).length;
  const activation = filled / 6; // 0..1 — drives glow intensity
  const fullyPrimed = filled >= 3;
  const baseSpell = BASE_SPELLS.find(s=>s.id===base);

  function cast(){
    setCasting(true);
    setResult(null);
    setTimeout(()=>{
      setCasting(false);
      setResult(mockAI(school, baseSpell, words));
    }, 1400);
  }

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden'}}>
      <div className="parchment"/>
      <div className="mmgo-scroll" style={{position:'relative', height:'100%', overflow:'auto', padding:'12px 12px 16px'}}>
        <Ornament>Круг призыва</Ornament>
        <div style={{textAlign:'center', fontStyle:'italic', color:'var(--ink-faint)', fontSize:11, marginTop:2, marginBottom:10}}>
          «Слова — это сосуды. Сосуды держат намерение».
        </div>

        {/* Circle */}
        <div style={{
          position:'relative', width:'100%', aspectRatio:'1/1',
          margin:'0 auto', maxWidth:320,
          filter: casting ? `drop-shadow(0 0 14px var(--s-${school}))` : activation>0 ? `drop-shadow(0 0 ${4+activation*10}px var(--s-${school}))` : 'none',
          transition:'filter .8s ease',
        }}>
          {/* activation glow — pulses more as more slots fill */}
          {activation>0 && (
            <div style={{
              position:'absolute', inset:'10%', borderRadius:'50%',
              background:`radial-gradient(circle, oklch(from var(--s-${school}) 0.7 c h / ${0.06+activation*0.18}) 10%, transparent 65%)`,
              animation: fullyPrimed?'pulse-magic 2.4s ease-in-out infinite':'none',
              pointerEvents:'none',
            }}/>
          )}
          {/* rotating outer ring — speeds up with activation */}
          <div style={{position:'absolute', inset:6, animation:`spin-slow ${Math.max(12, 90 - activation*70)}s linear infinite`}}>
            <svg viewBox="-100 -100 200 200" width="100%" height="100%">
              <circle r="95" fill="none" stroke={`var(--s-${school})`} strokeOpacity={0.2+activation*0.3} strokeWidth=".6"/>
              {[...Array(48)].map((_,i)=>(
                <line key={i} x1={Math.cos(i*Math.PI*2/48)*88} y1={Math.sin(i*Math.PI*2/48)*88}
                  x2={Math.cos(i*Math.PI*2/48)*95} y2={Math.sin(i*Math.PI*2/48)*95}
                  stroke="var(--ink)" strokeOpacity={0.25+activation*0.4} strokeWidth=".4"/>
              ))}
            </svg>
          </div>
          {/* middle ring — counter rotating */}
          <div style={{position:'absolute', inset:24, animation:'spin-rev 60s linear infinite'}}>
            <svg viewBox="-100 -100 200 200" width="100%" height="100%">
              <circle r="85" fill="none" stroke={`var(--s-${school})`} strokeOpacity=".6" strokeWidth="1" strokeDasharray="4 2"/>
              {SCHOOLS.map((s,i)=>{
                const a = i*Math.PI*2/8 - Math.PI/2;
                return (
                  <text key={s} x={Math.cos(a)*75} y={Math.sin(a)*75+4}
                    textAnchor="middle" fontFamily="var(--rune)" fontSize="11"
                    fill={`var(--s-${s})`} opacity={s===school?1:.3}
                    style={{cursor:'pointer'}}>{SCHOOL_GLYPH[s]}</text>
                );
              })}
            </svg>
          </div>

          {/* inner triangle */}
          <div style={{position:'absolute', inset:0, animation: casting?'pulse-magic 1.2s ease-in-out infinite':'none'}}>
            <svg viewBox="-100 -100 200 200" width="100%" height="100%">
              {/* inscribed lines between filled slots */}
              {(() => {
                const filledIdx = words.map((w,i)=> w ? i : -1).filter(i=>i>=0);
                if(filledIdx.length < 2) return null;
                const slotPos = (i) => {
                  const a = i*Math.PI*2/6 - Math.PI/2;
                  return [Math.cos(a)*44, Math.sin(a)*44];
                };
                const lines = [];
                for(let i=0;i<filledIdx.length;i++){
                  for(let j=i+1;j<filledIdx.length;j++){
                    const [x1,y1] = slotPos(filledIdx[i]);
                    const [x2,y2] = slotPos(filledIdx[j]);
                    lines.push(<line key={`${i}-${j}`} x1={x1} y1={y1} x2={x2} y2={y2}
                      stroke={`var(--s-${school})`} strokeOpacity=".55" strokeWidth=".5"
                      strokeLinecap="round"
                      style={{filter:`drop-shadow(0 0 2px var(--s-${school}))`, animation:'flicker 2.5s infinite'}}/>);
                  }
                }
                return lines;
              })()}
              <polygon points={`0,-40 ${40*Math.cos(Math.PI/6)},${40*Math.sin(Math.PI/6)} ${-40*Math.cos(Math.PI/6)},${40*Math.sin(Math.PI/6)}`}
                fill="none" stroke={`var(--s-${school})`} strokeWidth="1" strokeOpacity={0.3+activation*0.4}/>
              <circle r="20" fill={`var(--s-${school})`} fillOpacity={0.05+activation*0.15} stroke={`var(--s-${school})`} strokeWidth="1" strokeOpacity={0.4+activation*0.5}/>
              <text x="0" y="6" textAnchor="middle" fontFamily="var(--rune)" fontSize="22"
                fill={`var(--s-${school})`}
                style={{filter: fullyPrimed?`drop-shadow(0 0 3px var(--s-${school}))`:'none'}}
              >
                {SCHOOL_GLYPH[school]}
              </text>
            </svg>
          </div>

          {/* 6 slots around the rim */}
          {SLOTS.map((s,i)=>{
            const angle = i*Math.PI*2/6 - Math.PI/2;
            const r = 44; // percent from center
            const left = 50 + Math.cos(angle)*r;
            const top  = 50 + Math.sin(angle)*r;
            const active = focused===i;
            const filled = !!words[i];
            return (
              <button key={s.k} onClick={()=>setFocused(i)} style={{
                position:'absolute', left:`${left}%`, top:`${top}%`, transform:'translate(-50%,-50%)',
                width:56, height:56, borderRadius:'50%',
                background: filled
                  ? `radial-gradient(circle at 35% 30%, oklch(0.9 0.08 295), oklch(0.78 0.12 295))`
                  : `radial-gradient(circle at 35% 30%, oklch(0.92 0.02 80), oklch(0.84 0.03 76))`,
                border:`1.5px solid ${active?'var(--wax)':filled?'var(--magic)':'rgba(60,35,10,0.5)'}`,
                boxShadow: active
                  ? '0 0 0 3px oklch(0.55 0.14 27 / 0.3), inset 0 1px 0 rgba(255,245,220,0.6), 0 2px 4px rgba(0,0,0,0.2)'
                  : 'inset 0 1px 0 rgba(255,245,220,0.6), 0 2px 4px rgba(0,0,0,0.15)',
                display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center',
                cursor:'pointer', padding:0,
                transition:'all .15s ease',
              }}>
                <div style={{fontFamily:'var(--mono)', fontSize:8, letterSpacing:'.05em', color:'var(--ink-faint)', textTransform:'uppercase'}}>{s.ru}</div>
                <div style={{
                  fontFamily:'var(--rune)', fontSize: words[i]?11:18, color: filled?'var(--magic)':'rgba(60,35,10,0.35)',
                  marginTop:1, lineHeight:1,
                }}>{words[i] || (i+1)}</div>
              </button>
            );
          })}
        </div>

        {/* School picker */}
        <div style={{display:'flex', justifyContent:'center', gap:6, marginTop:8, flexWrap:'wrap'}}>
          {SCHOOLS.slice(0,4).concat(SCHOOLS.slice(4)).map(s=>(
            <button key={s} onClick={()=>setSchool(s)} style={{
              width:30, height:30, borderRadius:'50%',
              background: school===s? `var(--s-${s})` : 'oklch(0.92 0.02 80)',
              color: school===s? '#f5ead3' : `var(--s-${s})`,
              border:`1px solid ${school===s?'transparent':'rgba(60,35,10,0.35)'}`,
              fontFamily:'var(--rune)', fontSize:14,
              cursor:'pointer',
              boxShadow: school===s?`0 0 8px var(--s-${s})`:'inset 0 1px 0 rgba(255,245,220,0.5)',
            }}>{SCHOOL_GLYPH[s]}</button>
          ))}
        </div>

        {/* Focused slot editor */}
        <div style={{
          marginTop:12, padding:'10px 12px',
          background:'var(--vellum-2)', border:'1px solid rgba(60,35,10,0.3)',
          borderRadius:10,
        }}>
          <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', gap:8}}>
            <span style={{fontFamily:'var(--display)', fontWeight:700, fontSize:14}}>Слог {focused+1}. {SLOTS[focused].ru}</span>
            <span style={{fontSize:10, color:'var(--ink-faint)', fontStyle:'italic'}}>{SLOTS[focused].hint}</span>
          </div>
          <input
            value={words[focused]}
            onChange={e=>{
              const nw=[...words]; nw[focused]=e.target.value; setWords(nw);
            }}
            placeholder={SLOTS[focused].example[0]}
            style={{
              width:'100%', marginTop:6, padding:'6px 8px',
              border:'1px solid rgba(60,35,10,0.35)', borderRadius:6,
              background:'oklch(0.96 0.02 82)', fontFamily:'var(--mono)', fontSize:13,
              color:'var(--ink)',
            }}
          />
          <div style={{display:'flex', gap:5, marginTop:6, flexWrap:'wrap'}}>
            {SLOTS[focused].example.map(w=>(
              <button key={w} onClick={()=>{
                const nw=[...words]; nw[focused]=w; setWords(nw);
              }} style={{
                fontFamily:'var(--mono)', fontSize:10, padding:'3px 7px',
                border:'1px solid rgba(60,35,10,0.3)', background:'transparent',
                borderRadius:999, cursor:'pointer', color:'var(--ink-soft)',
              }}>{w}</button>
            ))}
          </div>
        </div>

        {/* Base + formula */}
        <div style={{marginTop:10, padding:'10px 12px', background:'var(--vellum-2)', border:'1px solid rgba(60,35,10,0.3)', borderRadius:10}}>
          <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:13, marginBottom:6}}>База</div>
          <select value={base} onChange={e=>setBase(e.target.value)} style={{
            width:'100%', padding:'6px 8px', fontFamily:'var(--mono)', fontSize:12,
            border:'1px solid rgba(60,35,10,0.35)', borderRadius:6, background:'oklch(0.96 0.02 82)',
          }}>
            {BASE_SPELLS.map(s=>(
              <option key={s.id} value={s.id}>{s.name} — {s.gloss}</option>
            ))}
          </select>
          <div style={{marginTop:10, fontFamily:'var(--mono)', fontSize:12, color:'var(--magic)', textAlign:'center', minHeight:20}}>
            {words.filter(Boolean).join(' ') || <span style={{color:'var(--ink-faint)', fontStyle:'italic'}}>введите слова…</span>}
          </div>
        </div>

        <div style={{display:'flex', gap:6, marginTop:10, justifyContent:'space-between', alignItems:'center', fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)'}}>
          <Chip color="ink">Слогов {filled}/6</Chip>
          <Chip color="wax">Усталость ~{4+filled*2}</Chip>
          <Chip color="magic">{SCHOOL_NAME_RU[school]}</Chip>
        </div>

        <div style={{display:'flex', gap:8, marginTop:12}}>
          <button className="inkbtn ghost" style={{flex:1}} onClick={onLeave}>Выйти</button>
          <button className="inkbtn primary" style={{flex:2}} disabled={!words.some(Boolean) || casting} onClick={cast}>
            {casting ? 'Оракул думает…' : 'Пропеть инкантацию'}
          </button>
        </div>

        {result && <AIResultCard result={result} school={school}/>}
      </div>
    </div>
  );
}

function AIResultCard({result, school}){
  return (
    <div style={{
      marginTop:12, padding:'12px 14px',
      background:'linear-gradient(180deg, oklch(0.94 0.04 82), oklch(0.88 0.06 78))',
      border:'1px solid rgba(60,35,10,0.45)', borderRadius:12,
      boxShadow:'inset 0 1px 0 rgba(255,245,220,0.6), 0 4px 8px rgba(40,25,10,0.18)',
      position:'relative',
    }}>
      <div style={{position:'absolute', top:-10, right:12}}>
        <div className="wax-seal" style={{width:34, height:34, fontSize:14}}>{SCHOOL_GLYPH[school]}</div>
      </div>
      <Ornament tiny>Оракул отвечает</Ornament>
      <div style={{marginTop:8, fontFamily:'var(--display)', fontWeight:700, fontSize:17, color:'var(--ink)'}}>{result.name_ru}</div>
      <div style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--magic)', marginTop:2}}>{result.formula}</div>
      <p style={{fontFamily:'var(--serif)', fontSize:13, lineHeight:1.5, marginTop:10, color:'var(--ink)', textAlign:'justify'}}>
        «{result.narrative}»
      </p>
      <div style={{display:'flex', gap:6, marginTop:8, flexWrap:'wrap'}}>
        {result.states.map((s,i)=>(
          <Chip key={i} color="magic">{s.label} · {s.dur}т</Chip>
        ))}
        <Chip color="wax">Усталость {result.fatigue}</Chip>
        <Chip color="ink">Перезарядка {result.cd}т</Chip>
      </div>
    </div>
  );
}

function mockAI(school, base, words){
  const formula = words.filter(Boolean).join(' ');
  const has = (w)=> words.some(x=>x.toLowerCase().includes(w.toLowerCase()));
  const states = [];
  if(school==='fire') states.push({label:'burning',dur:3});
  if(school==='water'|| has('aqua')) states.push({label:'frozen', dur:2});
  if(has('scutum')) states.push({label:'shielded', dur:3});
  if(has('sphaera')|| has('murus')) states.push({label:'trapped', dur:2});
  if(has('magnus')|| has('enormis')) states.push({label:'exposed', dur:2});
  if(!states.length) states.push({label:'impact', dur:0});

  const narrations = {
    fire:'Воздух между вами вздрагивает — и в ладони распускается жаркий огненный цветок. Он устремляется вперёд, оставляя за собой запах калёного металла и тлеющую дорожку на земле.',
    water:'Ледяной пар клубится над землёй и схлопывается в круг. В нём на мгновение замирает сама тишина — а затем всё вокруг покрывается тонкой изморозью.',
    earth:'Земля глухо вздыхает и поднимается стеной. Камни срастаются с глухим щелчком, и на мгновение кажется, что вы слышите в них голос.',
    air:'Порыв ветра сворачивается в спираль и с тонким свистом уходит вверх, унося за собой пыль и последний звук вашего голоса.',
    chaos:'Пространство будто шаг назад сделало. Линии потекли, цвета сбились. Невозможно сказать, что именно произошло, — но что-то определённо да.',
    order:'Над кругом выстраивается бледная решётка. Она ровная, как страница устава, и столь же неумолима.',
    life:'Зелёный свет проливается сквозь пальцы, как тёплое молоко. Раны затягиваются, и становится слышно, как бьётся сердце.',
    death:'Холод пробирает до костей — и не ваших. Что-то в цели начинает медленно истлевать изнутри.',
  };

  return {
    name_ru: {
      fire:'Малое Пламя, Направленное',
      water:'Ледяной Круг',
      earth:'Стена Тверди',
      air:'Шквал',
      chaos:'Смятение',
      order:'Решётка Устава',
      life:'Дыхание Жизни',
      death:'Хладный Коготь',
    }[school],
    formula: `${base.name} + ${formula}`,
    narrative: narrations[school],
    states,
    fatigue: 4 + words.filter(Boolean).length*2,
    cd: 2 + words.filter(Boolean).length,
  };
}

Object.assign(window, { SpellCircle });
