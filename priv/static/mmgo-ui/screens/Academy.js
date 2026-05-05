// Academy — a university vibe: cloister courtyard, timetable, clubs board
// Tries to mimic the real university experience: clock, schedule, buildings,
// notice board with clubs, a ribbon with your current term.

const BUILDINGS = [
  {k:'wizardry', name:'Факультет Чародейства', sub:'Две школы на выбор', glyph:'✦', tint:'var(--magic)', rooms:['Аудитория 3 — Латынь и Инкантации','Лаб. №1 — Малый огонь','Кабинет декана']},
  {k:'alchemy',  name:'Факультет Алхимии',     sub:'Варка, травы, перегонка', glyph:'⚗', tint:'oklch(0.5 0.12 145)', rooms:['Лаб. №2 — Перегонка','Теплица','Зал дегустаций']},
  {k:'mastery',  name:'Факультет Мастерства',  sub:'Оружие, доспех, ловушки', glyph:'⚒', tint:'oklch(0.48 0.09 55)', rooms:['Кузница','Полигон','Оружейная']},
  {k:'academia', name:'Коллегия Исследований', sub:'Аспирантура и диссертации', glyph:'☉', tint:'oklch(0.5 0.08 82)', rooms:['Библиотека','Архив','Кабинет профессора']},
];

const TIMETABLE = [
  {day:'Пн', slot:'I',  subj:'Латынь и инкантации',    where:'ауд. 3',   prof:'маг. Лиен Тар'},
  {day:'Пн', slot:'II', subj:'Теория элементов',       where:'ауд. 5',   prof:'маг. Гэвин'},
  {day:'Вт', slot:'I',  subj:'Практика: Малый огонь',  where:'лаб. №1',  prof:'маг. Ортис',  done:true},
  {day:'Вт', slot:'II', subj:'Этика боевой магии',     where:'ауд. 2',   prof:'маг. Морвиль'},
  {day:'Ср', slot:'I',  subj:'Травник и реагенты',     where:'теплица',  prof:'мастер Кайе'},
  {day:'Чт', slot:'I',  subj:'Дуэльный клуб',          where:'полигон',  prof:'капитан Борн', club:true},
  {day:'Пт', slot:'I',  subj:'История княжества',      where:'ауд. 1',   prof:'проф. Веттен'},
];

const CLUBS = [
  {name:'Дуэльный клуб',    members:24, tag:'спорт', note:'еженед. спарринги', hot:true},
  {name:'Круг переводов',   members:11, tag:'яз.',   note:'читаем «De Elementis»'},
  {name:'Экспедиционный',   members:18, tag:'иссл.', note:'идёт запись в поход'},
  {name:'Общество трав',    members: 9, tag:'алх.',  note:'обмен семенами'},
];

function Academy({onLeave}){
  const [tab, setTab] = React.useState('courtyard');

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>

      {/* Academy crest strip */}
      <div style={{position:'relative', padding:'10px 14px 4px'}}>
        <div style={{display:'flex', alignItems:'center', gap:10}}>
          <div style={{
            width:44, height:44, borderRadius:'50%',
            background:'radial-gradient(circle at 35% 30%, oklch(0.9 0.05 82), oklch(0.72 0.09 78))',
            border:'1.5px solid rgba(60,35,10,0.55)',
            display:'flex', alignItems:'center', justifyContent:'center',
            boxShadow:'inset 0 1px 0 rgba(255,245,220,0.6), 0 2px 4px rgba(40,25,10,0.2)',
            fontFamily:'var(--rune)', fontSize:22, color:'var(--wax-deep)',
          }}>✦</div>
          <div style={{flex:1}}>
            <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:17, letterSpacing:'.02em'}}>Княжеская Академия</div>
            <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-faint)'}}>
              Scientia ante potentiam — знание прежде силы
            </div>
          </div>
          <button onClick={onLeave} className="inkbtn ghost" style={{padding:'4px 10px', fontSize:10}}>Выйти</button>
        </div>
      </div>

      {/* Tabs */}
      <div style={{position:'relative', padding:'6px 12px 0', display:'flex', gap:4, borderBottom:'1px solid rgba(60,35,10,0.25)'}}>
        {[
          ['courtyard','Двор'],
          ['schedule','Расписание'],
          ['clubs','Клубы'],
          ['enroll','Зачисление'],
        ].map(([k,label])=>(
          <button key={k} onClick={()=>setTab(k)} style={{
            flex:1, padding:'6px 4px', cursor:'pointer',
            background: tab===k?'var(--vellum)':'transparent',
            border:'1px solid rgba(60,35,10,0.3)',
            borderBottom: tab===k?'1px solid var(--vellum)':'1px solid transparent',
            borderRadius:'6px 6px 0 0',
            fontFamily:'var(--display)', fontWeight: tab===k?700:500, fontSize:11,
            color: tab===k?'var(--ink)':'var(--ink-faint)',
            marginBottom:-1,
            letterSpacing:'.04em',
          }}>{label}</button>
        ))}
      </div>

      <div className="mmgo-scroll" style={{position:'relative', flex:1, overflow:'auto', padding:'10px 12px 14px'}}>
        {tab==='courtyard' && <Courtyard/>}
        {tab==='schedule' && <Schedule/>}
        {tab==='clubs' && <ClubsBoard/>}
        {tab==='enroll' && <Enrollment/>}
      </div>
    </div>
  );
}

// ─── Courtyard: engraved view of the academy building ───
function Courtyard(){
  return (
    <div>
      <AcademyVignette/>

      <div style={{marginTop:12, fontFamily:'var(--serif)', fontSize:12, fontStyle:'italic', color:'var(--ink-soft)', textAlign:'center'}}>
        Из окон факультета алхимии тянет лавандой и серой одновременно.
      </div>

      <div className="hrule" style={{margin:'14px 0'}}/>

      {/* Building list */}
      <div style={{display:'flex', flexDirection:'column', gap:8}}>
        {BUILDINGS.map(b=>(
          <button key={b.k} className="inkbtn" style={{
            padding:'10px 12px', textAlign:'left',
            display:'flex', alignItems:'center', gap:10,
          }}>
            <div style={{
              width:38, height:38, borderRadius:8,
              background:`radial-gradient(circle at 35% 30%, oklch(from ${b.tint} calc(l+.3) c h), ${b.tint})`,
              display:'flex', alignItems:'center', justifyContent:'center',
              color:'#f5ead3', fontFamily:'var(--rune)', fontSize:20,
              border:'1px solid rgba(0,0,0,0.3)',
              boxShadow:'inset 0 1px 0 rgba(255,245,220,0.3), 0 1px 2px rgba(0,0,0,0.2)',
              flexShrink:0,
            }}>{b.glyph}</div>
            <div style={{flex:1}}>
              <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:14, color:'var(--ink)'}}>{b.name}</div>
              <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)'}}>{b.sub}</div>
            </div>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M9 6l6 6-6 6" stroke="var(--ink-faint)" strokeWidth="2" strokeLinecap="round"/></svg>
          </button>
        ))}
      </div>
    </div>
  );
}

// Ink-etching of the academy building — parchment plate, not a "top-down"
function AcademyVignette(){
  return (
    <div style={{
      position:'relative',
      padding:'14px 10px 10px',
      background:'linear-gradient(180deg, oklch(0.93 0.025 82), oklch(0.87 0.04 78))',
      border:'1px solid rgba(60,35,10,0.4)',
      borderRadius:8,
      boxShadow:'inset 0 0 30px rgba(60,35,10,0.14), 0 2px 6px rgba(60,35,10,0.15)',
      overflow:'hidden',
    }} className="vignette">
      {/* paper fibres */}
      <div aria-hidden="true" style={{
        position:'absolute', inset:0, pointerEvents:'none', opacity:.18,
        background:'radial-gradient(circle at 20% 10%, rgba(60,35,10,0.3), transparent 40%), radial-gradient(circle at 80% 85%, rgba(60,35,10,0.25), transparent 40%)',
      }}/>
      <div style={{
        fontFamily:'var(--display)', fontWeight:700, fontSize:10, letterSpacing:'.18em',
        textAlign:'center', textTransform:'uppercase', color:'var(--ink-faint)',
      }}>— Plate I —</div>
      <div style={{
        fontFamily:'var(--script)', fontSize:18, textAlign:'center', color:'var(--ink-soft)',
        lineHeight:1,
      }}>Academia Principis</div>

      <svg viewBox="0 0 400 220" style={{width:'100%', height:'auto', display:'block', marginTop:6}}>
        <defs>
          <pattern id="hatch" patternUnits="userSpaceOnUse" width="3" height="3" patternTransform="rotate(45)">
            <line x1="0" y1="0" x2="0" y2="3" stroke="#3a2515" strokeWidth=".4" strokeOpacity=".55"/>
          </pattern>
          <pattern id="hatch2" patternUnits="userSpaceOnUse" width="2.2" height="2.2" patternTransform="rotate(-45)">
            <line x1="0" y1="0" x2="0" y2="2.2" stroke="#3a2515" strokeWidth=".35" strokeOpacity=".4"/>
          </pattern>
          <linearGradient id="skygrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"  stopColor="#d9c89c"/>
            <stop offset="100%" stopColor="#e8d7a8"/>
          </linearGradient>
        </defs>

        {/* sky panel */}
        <rect x="8" y="10" width="384" height="150" fill="url(#skygrad)" stroke="#3a2515" strokeWidth=".6"/>
        {/* distant hills */}
        <path d="M8,130 Q 60,108 110,120 T 210,118 T 310,116 T 392,126 L 392,160 L 8,160 Z" fill="url(#hatch2)" stroke="#3a2515" strokeWidth=".5" strokeOpacity=".6"/>
        {/* sun disc */}
        <circle cx="330" cy="48" r="14" fill="none" stroke="#3a2515" strokeWidth=".6"/>
        {[...Array(16)].map((_,i)=>{
          const a=i*Math.PI*2/16, x1=330+Math.cos(a)*16, y1=48+Math.sin(a)*16, x2=330+Math.cos(a)*22, y2=48+Math.sin(a)*22;
          return <line key={i} x1={x1} y1={y1} x2={x2} y2={y2} stroke="#3a2515" strokeWidth=".4"/>;
        })}
        {/* flock */}
        <path d="M90,60 q4,-4 8,0 q4,-4 8,0" fill="none" stroke="#3a2515" strokeWidth=".5"/>
        <path d="M120,48 q3,-3 6,0 q3,-3 6,0" fill="none" stroke="#3a2515" strokeWidth=".4"/>

        {/* ground line */}
        <line x1="8" y1="160" x2="392" y2="160" stroke="#3a2515" strokeWidth=".8"/>

        {/* Main central building — great hall */}
        {/* base */}
        <rect x="140" y="92" width="120" height="68" fill="#e8d7a8" stroke="#3a2515" strokeWidth=".9"/>
        {/* stonework hatching */}
        <rect x="140" y="130" width="120" height="30" fill="url(#hatch)" opacity=".4"/>
        {/* pediment */}
        <polygon points="130,92 200,58 270,92" fill="#d9c89c" stroke="#3a2515" strokeWidth=".9"/>
        <polygon points="148,92 200,68 252,92" fill="none" stroke="#3a2515" strokeWidth=".4"/>
        {/* rose window */}
        <circle cx="200" cy="82" r="6" fill="none" stroke="#3a2515" strokeWidth=".5"/>
        {[...Array(8)].map((_,i)=>{
          const a=i*Math.PI/4, x=200+Math.cos(a)*6, y=82+Math.sin(a)*6;
          return <line key={i} x1="200" y1="82" x2={x} y2={y} stroke="#3a2515" strokeWidth=".3"/>;
        })}
        {/* columns */}
        {[158,178,200,222,242].map((x,i)=>(
          <g key={i}>
            <line x1={x} y1="100" x2={x} y2="146" stroke="#3a2515" strokeWidth=".6"/>
            <rect x={x-3} y="97" width="6" height="4" fill="none" stroke="#3a2515" strokeWidth=".5"/>
            <rect x={x-3.5} y="146" width="7" height="4" fill="none" stroke="#3a2515" strokeWidth=".5"/>
          </g>
        ))}
        {/* main doorway */}
        <path d="M194,160 L194,142 Q194,134 200,134 Q206,134 206,142 L206,160 Z" fill="#3a2515" fillOpacity=".85" stroke="#3a2515" strokeWidth=".5"/>
        <line x1="200" y1="160" x2="200" y2="134" stroke="#d9c89c" strokeOpacity=".4" strokeWidth=".3"/>
        {/* steps */}
        <rect x="178" y="157" width="44" height="3" fill="none" stroke="#3a2515" strokeWidth=".3"/>
        <rect x="174" y="160" width="52" height="0" stroke="#3a2515" strokeWidth=".3"/>
        <line x1="172" y1="160" x2="228" y2="160" stroke="#3a2515" strokeWidth=".4"/>

        {/* Left wing — Alchemy (short, squat, with a chimney plume) */}
        <rect x="60" y="110" width="70" height="50" fill="#e8d7a8" stroke="#3a2515" strokeWidth=".8"/>
        <polygon points="56,110 95,86 134,110" fill="#d9c89c" stroke="#3a2515" strokeWidth=".8"/>
        <rect x="60" y="140" width="70" height="20" fill="url(#hatch)" opacity=".35"/>
        {/* windows */}
        {[74,90,106,120].map((x,i)=>(
          <rect key={i} x={x-3} y="120" width="6" height="10" fill="#3a2515" fillOpacity=".8"/>
        ))}
        {/* door */}
        <path d="M90,160 L90,148 Q90,144 95,144 Q100,144 100,148 L100,160 Z" fill="#3a2515" fillOpacity=".8"/>
        {/* chimney + smoke */}
        <rect x="104" y="80" width="6" height="14" fill="#e8d7a8" stroke="#3a2515" strokeWidth=".5"/>
        <path d="M107,80 Q 100,70 108,60 Q 102,50 112,42 Q 106,32 118,26" fill="none" stroke="#3a2515" strokeWidth=".5" strokeOpacity=".7"/>
        <path d="M107,80 Q 114,68 106,58 Q 116,50 110,40" fill="none" stroke="#3a2515" strokeWidth=".4" strokeOpacity=".5"/>

        {/* Right wing — Mastery (forge, anvil cue) */}
        <rect x="270" y="114" width="70" height="46" fill="#e8d7a8" stroke="#3a2515" strokeWidth=".8"/>
        <polygon points="266,114 305,92 344,114" fill="#d9c89c" stroke="#3a2515" strokeWidth=".8"/>
        <rect x="270" y="142" width="70" height="18" fill="url(#hatch)" opacity=".35"/>
        {/* big forge arch */}
        <path d="M282,160 L282,140 Q282,130 292,130 Q302,130 302,140 L302,160 Z" fill="#3a2515" fillOpacity=".9"/>
        {/* sparks */}
        {[{x:292,y:128},{x:288,y:124},{x:296,y:126},{x:294,y:120}].map((s,i)=>(
          <g key={i}>
            <line x1={s.x-1.5} y1={s.y} x2={s.x+1.5} y2={s.y} stroke="#3a2515" strokeWidth=".5"/>
            <line x1={s.x} y1={s.y-1.5} x2={s.x} y2={s.y+1.5} stroke="#3a2515" strokeWidth=".5"/>
          </g>
        ))}
        <rect x="318" y="130" width="6" height="6" fill="#3a2515" fillOpacity=".7"/>
        <rect x="308" y="130" width="6" height="6" fill="#3a2515" fillOpacity=".7"/>

        {/* Tall tower — Research Collegium, behind centre */}
        <rect x="193" y="20" width="14" height="72" fill="#e8d7a8" stroke="#3a2515" strokeWidth=".8"/>
        <polygon points="189,20 200,4 211,20" fill="#3a2515" fillOpacity=".85" stroke="#3a2515" strokeWidth=".6"/>
        <line x1="200" y1="4" x2="200" y2="-2" stroke="#3a2515" strokeWidth=".5"/>
        <circle cx="200" cy="-3" r="1.2" fill="#3a2515"/>
        {/* tower windows */}
        {[32,48,64,80].map((y,i)=>(
          <rect key={i} x="197" y={y} width="6" height="6" fill="#3a2515" fillOpacity=".85"/>
        ))}
        {/* telescope / observer marks */}
        <line x1="205" y1="30" x2="214" y2="24" stroke="#3a2515" strokeWidth=".6"/>

        {/* Foreground: cobbled plaza */}
        <path d="M8,160 L60,200 L340,200 L392,160 Z" fill="#e0cd98" stroke="#3a2515" strokeWidth=".6"/>
        <path d="M8,160 L60,200 L340,200 L392,160 Z" fill="url(#hatch2)" opacity=".4"/>
        {/* plaza ink lines */}
        {[170,188,200,212,230].map((x,i)=>(
          <line key={i} x1={x} y1="162" x2={x-(x-200)*0.7} y2="200" stroke="#3a2515" strokeWidth=".3" strokeOpacity=".5"/>
        ))}
        <line x1="8" y1="180" x2="392" y2="180" stroke="#3a2515" strokeWidth=".3" strokeOpacity=".45" strokeDasharray="2 2"/>

        {/* Tiny scholar figures */}
        <ScholarFigure x={170} y={196}/>
        <ScholarFigure x={186} y={194} mirror/>
        <ScholarFigure x={240} y={196}/>
        <ScholarFigure x={108} y={192}/>
        <ScholarFigure x={304} y={194} mirror/>

        {/* tiny trees flanking */}
        <TinyTree x={32}  y={160}/>
        <TinyTree x={368} y={160}/>

        {/* corner flourishes */}
        <path d="M10,10 Q 16,16 22,10" fill="none" stroke="#3a2515" strokeWidth=".5"/>
        <path d="M378,10 Q 384,16 390,10" fill="none" stroke="#3a2515" strokeWidth=".5"/>
        <path d="M10,210 Q 16,204 22,210" fill="none" stroke="#3a2515" strokeWidth=".5"/>
        <path d="M378,210 Q 384,204 390,210" fill="none" stroke="#3a2515" strokeWidth=".5"/>
      </svg>

      <div style={{
        fontFamily:'var(--script)', fontSize:14, textAlign:'center',
        color:'var(--ink-soft)', marginTop:2,
      }}>Вид с южных ворот, в час ранней лекции</div>
    </div>
  );
}

function ScholarFigure({x, y, mirror}){
  return (
    <g transform={`translate(${x},${y})${mirror?' scale(-1,1)':''}`}>
      {/* hood */}
      <path d="M0,-10 Q -3,-4 -3,0 L 3,0 Q 3,-4 0,-10 Z" fill="#3a2515" fillOpacity=".9"/>
      {/* robe */}
      <path d="M-4,0 L 4,0 L 5,6 L -5,6 Z" fill="#3a2515" fillOpacity=".75" stroke="#3a2515" strokeWidth=".3"/>
      <line x1="-3" y1="2" x2="-4" y2="6" stroke="#3a2515" strokeWidth=".3"/>
    </g>
  );
}

function TinyTree({x, y}){
  return (
    <g transform={`translate(${x},${y})`}>
      <line x1="0" y1="0" x2="0" y2="-18" stroke="#3a2515" strokeWidth=".5"/>
      <path d="M-8,-10 Q 0,-24 8,-10 Q 4,-8 0,-10 Q -4,-8 -8,-10 Z" fill="#d9c89c" stroke="#3a2515" strokeWidth=".5"/>
      <path d="M-8,-10 Q 0,-24 8,-10" fill="url(#hatch)" opacity=".5"/>
    </g>
  );
}

// ─── Schedule ───
function Schedule(){
  return (
    <div>
      <Ornament tiny>Расписание · Осенний триместр</Ornament>
      <div style={{
        marginTop:10, border:'1px solid rgba(60,35,10,0.35)', borderRadius:8,
        overflow:'hidden',
        background:'oklch(0.96 0.02 82)',
      }}>
        {TIMETABLE.map((r,i)=>(
          <div key={i} style={{
            display:'grid', gridTemplateColumns:'28px 24px 1fr auto',
            gap:8, alignItems:'center',
            padding:'8px 10px',
            borderBottom: i<TIMETABLE.length-1?'1px dashed rgba(60,35,10,0.2)':'none',
            background: r.done?'oklch(0.94 0.03 140 / 0.3)':r.club?'oklch(0.94 0.05 30 / 0.3)':'transparent',
          }}>
            <span style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--ink-soft)', fontWeight:700}}>{r.day}</span>
            <span style={{
              fontFamily:'var(--rune)', fontSize:14,
              color: r.club?'var(--wax)':'var(--ink-faint)',
              textAlign:'center',
            }}>{r.slot}</span>
            <div>
              <div style={{fontFamily:'var(--display)', fontWeight:600, fontSize:13, color:'var(--ink)', textDecoration:r.done?'line-through':'none'}}>
                {r.subj}
              </div>
              <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:10, color:'var(--ink-faint)'}}>
                {r.where} · {r.prof}
              </div>
            </div>
            {r.done && <Chip color="verdigris">сдано</Chip>}
            {r.club && <Chip color="wax">клуб</Chip>}
          </div>
        ))}
      </div>

      <div style={{marginTop:12, display:'flex', gap:8, justifyContent:'space-between', alignItems:'center', fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)'}}>
        <Chip color="ink">Сессия через 18 дн.</Chip>
        <Chip color="verdigris">Средний балл 4.2</Chip>
        <Chip color="magic">3/7 сдано</Chip>
      </div>
    </div>
  );
}

// ─── Clubs bulletin board ───
function ClubsBoard(){
  return (
    <div>
      <Ornament tiny>Доска объявлений</Ornament>
      <div style={{
        marginTop:10, padding:10, borderRadius:8,
        background:'linear-gradient(180deg, oklch(0.45 0.05 38), oklch(0.36 0.05 36))',
        border:'2px solid oklch(0.22 0.03 36)',
        boxShadow:'inset 0 0 8px rgba(0,0,0,0.35), 0 2px 4px rgba(0,0,0,0.3)',
        display:'grid', gridTemplateColumns:'1fr 1fr', gap:8,
      }}>
        {CLUBS.map((c,i)=>(
          <div key={i} style={{
            padding:'10px 9px',
            background: 'oklch(0.96 0.03 82)',
            border:'1px solid rgba(60,35,10,0.3)',
            borderRadius:2,
            transform: `rotate(${(i%2===0?-1:1)*1.2}deg)`,
            boxShadow:'0 2px 6px rgba(0,0,0,0.35)',
            position:'relative',
          }}>
            {/* thumbtack */}
            <div style={{
              position:'absolute', top:-5, left:'50%', transform:'translateX(-50%)',
              width:10, height:10, borderRadius:'50%',
              background:'radial-gradient(circle at 35% 30%, oklch(0.7 0.15 25), oklch(0.45 0.15 25))',
              boxShadow:'0 1px 2px rgba(0,0,0,0.5)',
            }}/>
            <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:13, color:'var(--ink)'}}>{c.name}</div>
            <div style={{fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)', marginTop:3}}>
              {c.members} чел. · {c.tag}
            </div>
            <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink)', marginTop:6}}>
              {c.note}
            </div>
            {c.hot && (
              <div style={{
                position:'absolute', top:-8, right:-6,
                fontFamily:'var(--script)', fontSize:16, color:'var(--wax)',
                transform:'rotate(10deg)',
              }}>идёт набор!</div>
            )}
          </div>
        ))}
      </div>

      <div style={{marginTop:10, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)', textAlign:'center'}}>
        В клубе находят тех, с кем потом идут в подземелье.
      </div>
    </div>
  );
}

// ─── Enrollment / progression ───
function Enrollment(){
  return (
    <div>
      <Ornament tiny>Ваш путь</Ornament>
      <div style={{
        marginTop:10, padding:'12px 14px',
        background:'var(--vellum-2)', border:'1px solid rgba(60,35,10,0.35)', borderRadius:10,
      }}>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:15}}>Факультет Чародейства</div>
        <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)', marginTop:2}}>
          2-й курс бакалавриата · 1 семестр
        </div>

        {/* Schools chosen */}
        <div style={{marginTop:10, display:'flex', gap:6}}>
          <SchoolPick k="fire" chosen/>
          <SchoolPick k="water" chosen/>
          <SchoolPick k="earth"/>
          <SchoolPick k="air"/>
          <SchoolPick k="chaos"/>
          <SchoolPick k="order"/>
          <SchoolPick k="life"/>
          <SchoolPick k="death"/>
        </div>
        <div style={{marginTop:6, fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-faint)'}}>
          Огонь и Вода — выбрано. Смена возможна, одна школа может остаться.
        </div>
      </div>

      {/* Progress ribbon */}
      <div style={{marginTop:12, padding:'10px 12px', border:'1px solid rgba(60,35,10,0.3)', borderRadius:10, background:'var(--vellum-2)'}}>
        <div style={{display:'flex', justifyContent:'space-between', fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)', marginBottom:4}}>
          <span>Базовое обр.</span><span>Бакалавриат</span><span>Магистратура</span><span>Аспирантура</span>
        </div>
        <div style={{height:10, borderRadius:3, background:'rgba(60,35,10,0.12)', border:'1px solid rgba(60,35,10,0.3)', overflow:'hidden', position:'relative'}}>
          <div style={{width:'34%', height:'100%', background:'linear-gradient(180deg, var(--gilt), oklch(0.55 0.12 60))'}}/>
          <div style={{position:'absolute', left:'34%', top:-2, bottom:-2, width:2, background:'var(--wax)', boxShadow:'0 0 4px var(--wax)'}}/>
        </div>
        <div style={{marginTop:6, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-soft)'}}>
          «На защиту дипломной работы нужно ещё 2 года игрового времени».
        </div>
      </div>

      {/* Grant */}
      <div style={{marginTop:12, padding:'10px 12px', border:'1px solid rgba(60,35,10,0.3)', borderRadius:10, background:'oklch(0.94 0.05 140 / 0.35)', position:'relative'}}>
        <div style={{position:'absolute', top:-8, right:-6}}>
          <div className="wax-seal" style={{width:32, height:32, fontSize:13}}>✦</div>
        </div>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:13}}>Стипендия от благотворительного фонда</div>
        <div style={{fontFamily:'var(--serif)', fontSize:12, marginTop:4, color:'var(--ink-soft)'}}>
          Ваша успеваемость позволяет сохранять грант. Оплата обучения: <span style={{fontFamily:'var(--mono)', color:'var(--verdigris)'}}>0 монет</span>.
        </div>
      </div>
    </div>
  );
}

function SchoolPick({k, chosen}){
  return (
    <div style={{
      flex:1, aspectRatio:'1', borderRadius:'50%',
      background: chosen ? `radial-gradient(circle at 35% 30%, oklch(from var(--s-${k}) calc(l+.2) c h), var(--s-${k}))` : 'oklch(0.92 0.02 80)',
      border: `1.5px solid ${chosen?'transparent':'rgba(60,35,10,0.35)'}`,
      color: chosen?'#f5ead3':`var(--s-${k})`,
      display:'flex', alignItems:'center', justifyContent:'center',
      fontFamily:'var(--rune)', fontSize:14,
      boxShadow: chosen?`0 0 8px var(--s-${k})`:'inset 0 1px 0 rgba(255,245,220,0.5)',
      position:'relative',
    }} title={SCHOOL_NAME_RU[k]}>
      {SCHOOL_GLYPH[k]}
    </div>
  );
}

Object.assign(window, { Academy });
