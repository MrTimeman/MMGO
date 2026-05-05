// Grimoire — physical books of varying sizes, each holding a set of spells.
// Shelves view: books on wooden shelves, spines vary in height/width/colour.
// Catalog view: the flat index of every spell you know, filterable.

// Spells in your personal library (what you've learned)
const DEMO_SPELLS = [
  {id:'s1',  name:'Ignis Parvus',     ru:'Малый огонь',    school:'fire', tier:1},
  {id:'s2',  name:'Ignis Magna',      ru:'Великое пламя',  school:'fire', tier:3},
  {id:'s3',  name:'Ignis Conus',      ru:'Конус огня',     school:'fire', tier:2},
  {id:'s4',  name:'Aqua Scutum',      ru:'Водный щит',     school:'water', tier:2},
  {id:'s5',  name:'Aqua Nexus',       ru:'Водная связь',   school:'water', tier:2},
  {id:'s6',  name:'Aqua Glacies',     ru:'Лёд',            school:'water', tier:3},
  {id:'s7',  name:'Terra Mure',       ru:'Стена земли',    school:'earth', tier:2},
  {id:'s8',  name:'Terra Vocatio',    ru:'Зов камня',      school:'earth', tier:3},
  {id:'s9',  name:'Aer Velox',        ru:'Быстрый ветер',  school:'air',   tier:1},
  {id:'s10', name:'Aer Conus',        ru:'Конус ветра',    school:'air',   tier:2},
  {id:'s11', name:'Vita Sanatio',     ru:'Исцеление',      school:'life',  tier:2},
  {id:'s12', name:'Vita Vinculum',    ru:'Узы жизни',      school:'life',  tier:3},
  {id:'s13', name:'Mors Tactus',      ru:'Касание смерти', school:'death', tier:3},
  {id:'s14', name:'Ordo Catena',      ru:'Цепь порядка',   school:'order', tier:3},
  {id:'s15', name:'Chaos Scintilla',  ru:'Искра хаоса',    school:'chaos', tier:1},
];

// Your books — physical grimoires. Each has a size (pages), a binding style,
// and a list of spell IDs it contains. Smaller books = travel grimoires.
const BOOKS = [
  {
    id:'b1', name:'Пламенник', ru:'The Fire-Book',
    size:'small', binding:'leather', tint:'fire',
    spellIds:['s1','s3'],
    notes:'Дорожная книжица огненных формул. Потёртые страницы.',
  },
  {
    id:'b2', name:'Codex Aquarum', ru:'Кодекс вод',
    size:'large', binding:'leather-gilt', tint:'water',
    spellIds:['s4','s5','s6'],
    notes:'Академический фолиант. Подарок деда. Инициалы золотом.',
  },
  {
    id:'b3', name:'Вётви', ru:'Vine-book',
    size:'medium', binding:'cloth', tint:'life',
    spellIds:['s11','s12'],
    notes:'Тонкая тетрадь в льняном переплёте.',
  },
  {
    id:'b4', name:'Terra Magna', ru:'Великая земля',
    size:'xl', binding:'wood', tint:'earth',
    spellIds:['s7','s8'],
    notes:'Массивный том в досках. Весит как кирпич.',
  },
  {
    id:'b5', name:'Дневник', ru:'Journal',
    size:'small', binding:'cloth', tint:'mixed',
    spellIds:['s9','s10','s15'],
    notes:'Ваши собственные записи. Эксперименты.',
  },
  {
    id:'b6', name:'Opus Mortis', ru:'Труды смерти',
    size:'medium', binding:'leather', tint:'death',
    spellIds:['s13','s14'],
    notes:'Приобретено на чёрном рынке. Без имени автора.',
  },
];

function Grimoire({layout='shelves', onLeave, onLayoutChange}){
  const [activeBook, setActiveBook] = React.useState(null); // book id when opened
  const [query, setQuery] = React.useState('');
  const [filterSchool, setFilterSchool] = React.useState(null);
  // Currently-carried books (to take into a dungeon)
  const [carried, setCarried] = React.useState(['b1','b3']);

  function toggleCarry(id){
    setCarried(c => c.includes(id) ? c.filter(x=>x!==id) : (c.length<3 ? [...c, id] : c));
  }

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>
      <div style={{position:'relative', padding:'8px 12px 4px'}}>
        <div style={{display:'flex', justifyContent:'center', gap:4}}>
          <button className={`inkbtn${layout==='shelves'?' primary':''}`}
            style={{padding:'5px 12px', fontSize:11}}
            onClick={()=>onLayoutChange('shelves')}>Полки (книги)</button>
          <button className={`inkbtn${layout==='catalog'?' primary':''}`}
            style={{padding:'5px 12px', fontSize:11}}
            onClick={()=>onLayoutChange('catalog')}>Каталог (заклинания)</button>
        </div>
      </div>

      <div className="mmgo-scroll" style={{position:'relative', flex:1, overflow:'auto', padding:'4px 12px 10px'}}>
        {layout==='shelves'
          ? <ShelvesView books={BOOKS} onOpen={setActiveBook} carried={carried} onToggleCarry={toggleCarry}/>
          : <CatalogView spells={DEMO_SPELLS} books={BOOKS} query={query} setQuery={setQuery}
              filterSchool={filterSchool} setFilterSchool={setFilterSchool}/>}
      </div>

      {/* Bottom ribbon — carried books summary */}
      <CarryRibbon carried={carried} books={BOOKS} onLeave={onLeave}/>

      {/* Book detail overlay */}
      {activeBook && (
        <BookDetail book={BOOKS.find(b=>b.id===activeBook)}
          spells={DEMO_SPELLS}
          onClose={()=>setActiveBook(null)}
          carried={carried} onToggleCarry={toggleCarry}/>
      )}
    </div>
  );
}

// ─── Shelves: wood shelves, variable-size book spines ───
function ShelvesView({books, onOpen, carried, onToggleCarry}){
  // Split books into shelves — try to balance widths (sum of widths ~ shelf capacity)
  const SHELF_CAP = 280; // arbitrary width units
  const shelves = [];
  let cur = []; let curW = 0;
  for(const b of books){
    const w = BOOK_WIDTH(b);
    if(curW + w > SHELF_CAP && cur.length){ shelves.push(cur); cur=[]; curW=0; }
    cur.push(b); curW+=w;
  }
  if(cur.length) shelves.push(cur);

  return (
    <div style={{display:'flex', flexDirection:'column', gap:0, marginTop:6}}>
      {shelves.map((row,si)=>(
        <div key={si}>
          <div style={{
            display:'flex', alignItems:'flex-end', gap:3,
            padding:'6px 6px 2px', minHeight:140,
            background:'linear-gradient(180deg, rgba(40,25,10,0) 0%, rgba(40,25,10,0.06) 100%)',
          }}>
            {row.map(b => <BookSpine key={b.id} book={b} onOpen={onOpen} carried={carried.includes(b.id)} onToggleCarry={onToggleCarry}/>)}
          </div>
          {/* wooden shelf */}
          <div className="wood" style={{
            height:12, borderRadius:2,
            boxShadow:'0 3px 3px rgba(0,0,0,0.3), inset 0 -2px 0 rgba(0,0,0,0.22), inset 0 1px 0 rgba(255,220,170,0.18)',
            marginBottom: 4,
          }}/>
        </div>
      ))}
    </div>
  );
}

// A book's visual width based on thickness (spellIds count) & size class
function BOOK_WIDTH(b){
  const byPages = 14 + b.spellIds.length * 4.5;
  const mult = {small:.85, medium:1.0, large:1.25, xl:1.6}[b.size] || 1.0;
  return byPages * mult;
}
function BOOK_HEIGHT(b){
  const base = {small:82, medium:100, large:120, xl:140}[b.size] || 100;
  return base;
}

function BookSpine({book, onOpen, carried, onToggleCarry}){
  const h = BOOK_HEIGHT(book);
  const w = BOOK_WIDTH(book);
  const TINT = book.tint==='mixed' ? 'oklch(0.40 0.08 60)' : `var(--s-${book.tint})`;
  const DARK = book.tint==='mixed' ? 'oklch(0.25 0.06 60)' : `oklch(from var(--s-${book.tint}) calc(l*.55) c h)`;
  const BINDING = {
    'leather':     `linear-gradient(180deg, ${TINT}, ${DARK})`,
    'leather-gilt':`linear-gradient(180deg, ${TINT}, ${DARK}), repeating-linear-gradient(90deg, transparent 0 4px, rgba(255,220,150,0.15) 4px 5px)`,
    'cloth':       `linear-gradient(180deg, ${TINT}, ${DARK}), repeating-linear-gradient(90deg, rgba(0,0,0,0.06) 0 1px, transparent 1px 3px)`,
    'wood':        `linear-gradient(180deg, oklch(0.45 0.06 45), oklch(0.28 0.05 42))`,
  }[book.binding];

  return (
    <div onClick={()=>onOpen(book.id)}
      onContextMenu={(e)=>{ e.preventDefault(); onToggleCarry(book.id); }}
      style={{
        width:w, height:h, minWidth: 16, flexShrink:0,
        background: BINDING,
        border:'1px solid rgba(0,0,0,0.5)', borderRadius:'2px 2.5px 1.5px 1.5px',
        position:'relative', cursor:'pointer',
        boxShadow:`inset 1.5px 0 0 rgba(255,255,255,${book.binding==='wood'?0.15:0.22}),
          inset -1.5px 0 0 rgba(0,0,0,0.35),
          0 2px 3px rgba(0,0,0,${carried?0.5:0.35})`,
        overflow:'hidden',
        display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center',
        transform: carried ? 'translateY(-4px)' : 'none',
        transition:'transform .2s ease',
      }}
      title={`${book.name} — ${book.ru} (${book.spellIds.length} закл.)`}
    >
      {/* gilt bands */}
      {book.binding!=='cloth' && (
        <>
          <div style={{position:'absolute', top:10, left:0, right:0, height:1.5, background:'var(--gilt)', opacity:.8, boxShadow:'0 1px 0 rgba(0,0,0,0.3)'}}/>
          <div style={{position:'absolute', top:18, left:0, right:0, height:0.5, background:'var(--gilt)', opacity:.5}}/>
          <div style={{position:'absolute', bottom:10, left:0, right:0, height:1.5, background:'var(--gilt)', opacity:.8, boxShadow:'0 -1px 0 rgba(0,0,0,0.3)'}}/>
        </>
      )}
      {/* spine rune */}
      {w > 22 && (
        <div style={{
          position:'absolute', top:26, left:'50%', transform:'translateX(-50%)',
          fontFamily:'var(--rune)', fontSize:14,
          color: book.binding==='wood' ? 'var(--gilt)' : 'var(--gilt)',
          filter:'drop-shadow(0 1px 0 rgba(0,0,0,0.4))',
        }}>{book.tint==='mixed' ? '✶' : SCHOOL_GLYPH[book.tint]}</div>
      )}
      {/* label — vertical */}
      <div style={{
        writingMode:'vertical-rl', transform:'rotate(180deg)',
        fontFamily:'var(--display)',
        fontSize: w > 26 ? 10 : 8,
        fontWeight:700,
        color: book.binding==='wood' ? 'var(--gilt)' : '#f5ead3',
        textShadow:'0 1px 0 rgba(0,0,0,0.5)',
        letterSpacing:'.12em', padding:'38px 0 26px',
        whiteSpace:'nowrap', textAlign:'center',
        maxHeight:'100%', overflow:'hidden',
      }}>{book.name}</div>
      {/* spell count pip at bottom */}
      <div style={{
        position:'absolute', bottom:2, left:'50%', transform:'translateX(-50%)',
        fontFamily:'var(--mono)', fontSize:7, color:'var(--gilt)', opacity:.8,
        letterSpacing:'.05em',
      }}>·{book.spellIds.length}·</div>
      {/* carried indicator — bookmark ribbon */}
      {carried && (
        <div style={{
          position:'absolute', top:-2, right:3, width:4, height:16,
          background:'var(--wax)', borderRadius:'0 0 2px 2px',
          boxShadow:'0 1px 2px rgba(0,0,0,0.5)',
        }}/>
      )}
    </div>
  );
}

// ─── Book detail overlay (opens into a spread) ───
function BookDetail({book, spells, onClose, carried, onToggleCarry}){
  const bookSpells = book.spellIds.map(id => spells.find(s=>s.id===id));
  const isCarried = carried.includes(book.id);
  return (
    <div style={{
      position:'absolute', inset:0, zIndex:20,
      background:'rgba(20,15,10,0.65)',
      display:'flex', flexDirection:'column',
      padding:'14px 10px',
    }} onClick={onClose}>
      <div onClick={(e)=>e.stopPropagation()} style={{
        flex:1, overflow:'auto',
        background:`linear-gradient(180deg, oklch(from var(--s-${book.tint==='mixed'?'fire':book.tint}) 0.35 c h), oklch(from var(--s-${book.tint==='mixed'?'fire':book.tint}) 0.22 c h))`,
        borderRadius:8,
        padding: 4,
        boxShadow:'0 16px 40px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,220,150,0.2)',
      }}>
        <div style={{
          background:'linear-gradient(180deg, oklch(0.94 0.03 82), oklch(0.88 0.04 78))',
          borderRadius:4,
          padding:'14px 16px',
          minHeight:'100%',
          position:'relative',
          boxShadow:'inset 0 0 30px rgba(60,35,10,0.15)',
        }} className="mmgo-scroll">
          {/* close */}
          <button onClick={onClose} style={{
            position:'absolute', top:6, right:8, zIndex:2,
            border:'none', background:'rgba(60,35,10,0.1)', color:'var(--ink-soft)',
            borderRadius:'50%', width:26, height:26, fontSize:14, cursor:'pointer',
          }}>✕</button>

          {/* Title */}
          <div style={{textAlign:'center', paddingTop:6, paddingBottom:4}}>
            <div style={{
              fontFamily:'var(--rune)', fontSize:18,
              color:`var(--s-${book.tint==='mixed'?'chaos':book.tint})`,
              letterSpacing:'.1em',
            }}>{book.tint==='mixed' ? '✶' : SCHOOL_GLYPH[book.tint]}</div>
            <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:22, marginTop:4, color:'var(--ink)'}}>{book.name}</div>
            <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, color:'var(--ink-soft)', marginTop:2}}>— {book.ru} —</div>
          </div>

          <div className="hrule" style={{margin:'12px 0 10px'}}/>

          <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, color:'var(--ink-soft)', textAlign:'center', marginBottom:14}}>
            «{book.notes}»
          </div>

          {/* Table of contents */}
          <div style={{
            fontFamily:'var(--display)', fontSize:11, fontWeight:700,
            letterSpacing:'.08em', textTransform:'uppercase',
            color:'var(--ink-faint)', marginBottom:6,
          }}>Содержание</div>
          <ol style={{listStyle:'none', padding:0, margin:0}}>
            {bookSpells.map((s,i)=>(
              <li key={s.id} style={{
                display:'flex', alignItems:'baseline', gap:6,
                padding:'6px 2px', borderBottom:'1px dotted rgba(60,35,10,0.22)',
                fontFamily:'var(--serif)', fontSize:13,
              }}>
                <span style={{fontFamily:'var(--rune)', fontSize:14, color:`var(--s-${s.school})`, width:14, textAlign:'center'}}>{SCHOOL_GLYPH[s.school]}</span>
                <span style={{fontFamily:'var(--display)', fontWeight:600, color:'var(--ink)'}}>{s.name}</span>
                <span style={{flex:1, borderBottom:'1px dotted rgba(60,35,10,0.3)', margin:'0 4px', transform:'translateY(-3px)'}}/>
                <span style={{color:'var(--ink-faint)', fontStyle:'italic', fontSize:11}}>{s.ru}</span>
                <span style={{color:'var(--ink-faint)', fontFamily:'var(--mono)', fontSize:10}}>с.{(i+1)*7}</span>
              </li>
            ))}
          </ol>

          <div style={{display:'flex', gap:8, marginTop:14}}>
            <Chip color="ink">Объём: {book.size}</Chip>
            <Chip color="ink">Переплёт: {book.binding}</Chip>
            <Chip color="magic">{book.spellIds.length} заклин.</Chip>
          </div>

          <div style={{display:'flex', gap:8, marginTop:14}}>
            <button className="inkbtn ghost" style={{flex:1}} onClick={onClose}>Закрыть</button>
            <button className={`inkbtn${isCarried?' primary':''}`} style={{flex:1}} onClick={()=>onToggleCarry(book.id)}>
              {isCarried ? 'Убрать из сумки' : 'Взять с собой'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Catalog view: index of every spell you know ───
function CatalogView({spells, books, query, setQuery, filterSchool, setFilterSchool}){
  const schools = ['fire','water','earth','air','life','death','order','chaos'];
  let filtered = spells;
  if(query) filtered = filtered.filter(s =>
    s.name.toLowerCase().includes(query.toLowerCase()) ||
    s.ru.toLowerCase().includes(query.toLowerCase())
  );
  if(filterSchool) filtered = filtered.filter(s => s.school===filterSchool);

  // Which book(s) contain this spell?
  function inBooks(sid){
    return books.filter(b => b.spellIds.includes(sid));
  }

  return (
    <div style={{marginTop:4}}>
      {/* Filter bar */}
      <div style={{display:'flex', gap:4, marginBottom:8, alignItems:'center'}}>
        <input value={query} onChange={e=>setQuery(e.target.value)}
          placeholder="поиск по названию…"
          style={{
            flex:1, padding:'5px 9px',
            border:'1px solid rgba(60,35,10,0.35)', borderRadius:6,
            background:'oklch(0.96 0.02 82)',
            fontFamily:'var(--serif)', fontSize:12, color:'var(--ink)',
          }}/>
      </div>
      <div style={{display:'flex', flexWrap:'wrap', gap:3, marginBottom:8, justifyContent:'center'}}>
        <button onClick={()=>setFilterSchool(null)} style={{
          padding:'3px 9px', borderRadius:999,
          border:`1px solid ${!filterSchool?'var(--ink)':'rgba(60,35,10,0.25)'}`,
          background: !filterSchool?'var(--vellum-shade)':'transparent',
          fontFamily:'var(--mono)', fontSize:10, cursor:'pointer', color:'var(--ink)',
        }}>все</button>
        {schools.map(k=>(
          <button key={k} onClick={()=>setFilterSchool(filterSchool===k?null:k)} style={{
            padding:'3px 8px', borderRadius:999,
            border:`1px solid ${filterSchool===k?`var(--s-${k})`:'rgba(60,35,10,0.25)'}`,
            background: filterSchool===k?`oklch(from var(--s-${k}) 0.92 c h / 0.4)`:'transparent',
            fontFamily:'var(--rune)', fontSize:12, cursor:'pointer',
            color:`var(--s-${k})`,
            display:'inline-flex', alignItems:'center', gap:3,
          }}>{SCHOOL_GLYPH[k]} <span style={{fontFamily:'var(--mono)', fontSize:9}}>{SCHOOL_NAME_RU[k]}</span></button>
        ))}
      </div>

      {/* index-card drawer */}
      <div style={{
        padding:8, borderRadius:6,
        background:'linear-gradient(180deg, oklch(0.52 0.06 46), oklch(0.42 0.07 44))',
        border:'1px solid rgba(0,0,0,0.45)',
        boxShadow:'inset 0 1px 0 rgba(255,220,170,0.18), inset 0 -2px 4px rgba(0,0,0,0.35)',
      }}>
        <div style={{
          background:'oklch(0.93 0.02 82)', borderRadius:3,
          border:'1px solid rgba(60,35,10,0.35)',
          boxShadow:'inset 0 0 0 2px rgba(255,245,220,0.4), 0 1px 2px rgba(0,0,0,0.3)',
          padding:'5px 4px', display:'flex', flexDirection:'column', gap:3,
          maxHeight:'100%',
        }}>
          {filtered.length === 0 && (
            <div style={{padding:'16px 8px', textAlign:'center', fontStyle:'italic', color:'var(--ink-faint)', fontSize:11}}>
              Ни одно заклинание не подходит.
            </div>
          )}
          {filtered.map(s=>{
            const inb = inBooks(s.id);
            return (
              <div key={s.id}
                style={{
                  display:'grid', gridTemplateColumns:'18px 1fr auto',
                  gap:8, alignItems:'center',
                  padding:'5px 8px',
                  background:'oklch(0.96 0.02 82)',
                  borderLeft:`3px solid var(--s-${s.school})`,
                  borderRadius:2,
                  fontFamily:'var(--mono)', fontSize:11,
                  color:'var(--ink)',
                  boxShadow:'0 1px 0 rgba(60,35,10,0.08)',
                }}
              >
                <span style={{fontFamily:'var(--rune)', color:`var(--s-${s.school})`, fontSize:13, textAlign:'center'}}>{SCHOOL_GLYPH[s.school]}</span>
                <div style={{display:'flex', flexDirection:'column', gap:1, minWidth:0}}>
                  <span style={{fontFamily:'var(--display)', fontWeight:600, fontSize:11.5, color:'var(--ink)'}}>{s.name}</span>
                  <span style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:10, color:'var(--ink-faint)'}}>{s.ru} · тир {s.tier}</span>
                </div>
                <div style={{display:'flex', flexDirection:'column', gap:2, alignItems:'flex-end'}}>
                  {inb.map(b => (
                    <span key={b.id} style={{
                      fontFamily:'var(--serif)', fontSize:9, fontStyle:'italic',
                      color:'var(--ink-faint)',
                    }}>↦ {b.name}</span>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <div style={{
        marginTop:8, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:10,
        color:'var(--ink-faint)', textAlign:'center',
      }}>Каталог заклинаний — всё, что вы знаете. Сами книги смотрите на полках.</div>
    </div>
  );
}

// ─── Carry ribbon: what goes with you ───
function CarryRibbon({carried, books, onLeave}){
  const list = carried.map(id => books.find(b=>b.id===id)).filter(Boolean);
  const weight = list.reduce((a,b)=> a + {small:.6, medium:1.2, large:1.8, xl:2.8}[b.size], 0);
  return (
    <div style={{
      borderTop:'1px solid rgba(60,35,10,0.45)',
      padding:'10px 12px 10px',
      background:'linear-gradient(180deg, oklch(0.35 0.07 35), oklch(0.28 0.07 33))',
      color:'#f5ead3',
    }}>
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:6}}>
        <div style={{
          fontFamily:'var(--display)', fontWeight:700, fontSize:12,
          letterSpacing:'.08em', textTransform:'uppercase', color:'var(--gilt)',
        }}>В сумке</div>
        <span style={{fontFamily:'var(--mono)', fontSize:10, color:'rgba(245,234,211,0.75)'}}>
          {list.length}/3 · {weight.toFixed(1)} кг
        </span>
      </div>
      <div style={{
        display:'flex', gap:4, minHeight:54,
        padding:6, border:'1.5px dashed rgba(245,234,211,0.3)',
        borderRadius:4, background:'rgba(0,0,0,0.25)',
        alignItems:'flex-end',
      }}>
        {list.length===0 && (
          <div style={{width:'100%', textAlign:'center', color:'rgba(245,234,211,0.4)', fontFamily:'var(--serif)', fontSize:11, fontStyle:'italic', alignSelf:'center'}}>
            Нет взятых книг. Правый клик на корешке — взять; левый — открыть.
          </div>
        )}
        {list.map(b=>{
          const TINT = b.tint==='mixed' ? 'oklch(0.40 0.08 60)' : `var(--s-${b.tint})`;
          const DARK = b.tint==='mixed' ? 'oklch(0.25 0.06 60)' : `oklch(from var(--s-${b.tint}) calc(l*.55) c h)`;
          const w = BOOK_WIDTH(b)*.85, h = Math.min(BOOK_HEIGHT(b)*.5, 48);
          return (
            <div key={b.id} style={{
              width:w, height:h,
              background:`linear-gradient(180deg, ${TINT}, ${DARK})`,
              border:'1px solid rgba(0,0,0,0.45)',
              borderRadius:'2px 2.5px 1.5px 1.5px',
              position:'relative',
              boxShadow:'inset 1px 0 0 rgba(255,255,255,0.2), inset -1px 0 0 rgba(0,0,0,0.35), 0 1px 2px rgba(0,0,0,0.4)',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>
              <div style={{
                writingMode:'vertical-rl', transform:'rotate(180deg)',
                fontFamily:'var(--display)', fontWeight:700, fontSize:8,
                color:'#f5ead3', letterSpacing:'.1em',
                whiteSpace:'nowrap',
              }}>{b.name}</div>
            </div>
          );
        })}
      </div>
      <div style={{display:'flex', gap:8, marginTop:8}}>
        <button className="inkbtn ghost" style={{flex:1, color:'#f5ead3', borderColor:'rgba(245,234,211,0.35)'}} onClick={onLeave}>Закрыть</button>
      </div>
    </div>
  );
}

Object.assign(window, { Grimoire });
