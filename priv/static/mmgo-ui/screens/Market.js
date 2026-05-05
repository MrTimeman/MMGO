// Market — capital city market: stalls with goods, haggle hint, currency display.
// Kept deliberately simple: a parchment ledger of stalls, each with 2-4 items.

const STALLS = [
  {
    id:'herbs', name:'Травник',
    keeper:'тётка Мираб', tagline:'Травы, корни, толчёные кости',
    items:[
      {name:'Полынь, пучок',          price:3,  unit:'шт', tag:'алх.'},
      {name:'Мандрагора (мал.)',      price:38, unit:'шт', tag:'редк.', short:true},
      {name:'Соль смешанная',         price:6,  unit:'мерка'},
      {name:'Слюна болотника',        price:24, unit:'флакон', tag:'алх.'},
    ],
  },
  {
    id:'paper', name:'Писчая лавка',
    keeper:'мастер Эль', tagline:'Бумага, перья, чернила',
    items:[
      {name:'Пергамент, лист',        price:8,  unit:'шт'},
      {name:'Чернила красные',        price:14, unit:'флакон'},
      {name:'Перо вороны',            price:2,  unit:'шт'},
      {name:'Перо феникса',           price:240,unit:'шт', tag:'редк.', short:true},
    ],
  },
  {
    id:'smith', name:'Кузня',
    keeper:'кузнец Бран', tagline:'Железо, наконечники, простые ремонты',
    items:[
      {name:'Кинжал',                 price:42, unit:'шт'},
      {name:'Замок дверной',          price:18, unit:'шт'},
      {name:'Починка доспеха',        price:25, unit:'усл.'},
    ],
  },
  {
    id:'food', name:'Хлебная',
    keeper:'старуха Лой', tagline:'Хлеб, сыр, сушёное мясо',
    items:[
      {name:'Хлеб ржаной',            price:2,  unit:'шт'},
      {name:'Сыр овечий',             price:7,  unit:'кусок'},
      {name:'Сушёное мясо',           price:11, unit:'связка'},
      {name:'Дорожные припасы (3 дн)',price:15, unit:'набор', tag:'дорога'},
    ],
  },
];

function Market({onLeave}){
  const [stallId, setStallId] = React.useState('herbs');
  const [coins, setCoins] = React.useState(128);
  const [bag, setBag] = React.useState({}); // name -> qty (just for the demo)
  const stall = STALLS.find(s=>s.id===stallId);

  function buy(item){
    if(coins < item.price) return;
    setCoins(c => c - item.price);
    setBag(b => ({...b, [item.name]: (b[item.name]||0)+1}));
  }

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>

      <div style={{position:'relative', padding:'10px 12px 4px'}}>
        <Ornament tiny>Рыночная площадь</Ornament>
      </div>

      {/* Stall picker */}
      <div style={{
        position:'relative',
        padding:'6px 10px',
        display:'flex', gap:6, overflowX:'auto',
      }}>
        {STALLS.map(s=>(
          <button key={s.id} onClick={()=>setStallId(s.id)} style={{
            flexShrink:0, padding:'6px 12px', borderRadius:6,
            background: stallId===s.id ? 'var(--vellum)' : 'transparent',
            border: `1px solid ${stallId===s.id ? 'var(--ink)' : 'rgba(60,35,10,0.3)'}`,
            cursor:'pointer',
            fontFamily:'var(--display)', fontWeight: stallId===s.id?700:500, fontSize:12,
            color: stallId===s.id ? 'var(--ink)' : 'var(--ink-soft)',
          }}>{s.name}</button>
        ))}
      </div>

      {/* Stall body */}
      <div className="mmgo-scroll" style={{
        position:'relative', flex:1, overflow:'auto', padding:'4px 12px 10px',
      }}>
        <div style={{
          padding:'12px 14px',
          background:'var(--vellum)', border:'1px solid rgba(60,35,10,0.4)',
          borderRadius:10,
          boxShadow:'inset 0 0 24px rgba(60,35,10,0.1), 0 2px 4px rgba(40,25,10,0.15)',
        }}>
          <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', gap:8}}>
            <div>
              <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:18}}>{stall.name}</div>
              <div style={{fontFamily:'var(--script)', fontSize:14, color:'var(--ink-soft)'}}>{stall.keeper}</div>
            </div>
            <Chip color="ink">тариф средний</Chip>
          </div>
          <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-faint)', marginTop:4}}>
            «{stall.tagline}»
          </div>

          <div className="hrule" style={{margin:'12px 0'}}/>

          <ul style={{listStyle:'none', padding:0, margin:0}}>
            {stall.items.map(it=>(
              <li key={it.name} style={{
                display:'grid', gridTemplateColumns:'1fr auto auto', gap:10,
                alignItems:'center', padding:'8px 0',
                borderBottom:'1px dotted rgba(60,35,10,0.25)',
              }}>
                <div>
                  <div style={{fontFamily:'var(--serif)', fontSize:13, color:'var(--ink)'}}>
                    {it.name}
                    {it.tag && <span style={{
                      fontFamily:'var(--mono)', fontSize:9, marginLeft:6,
                      color:'var(--wax)', textTransform:'uppercase', letterSpacing:'.05em',
                    }}>· {it.tag}</span>}
                    {it.short && <span style={{
                      fontFamily:'var(--script)', fontSize:11, marginLeft:6, color:'var(--ink-faint)',
                    }}>(спрашивайте)</span>}
                  </div>
                  {bag[it.name] && (
                    <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--verdigris)', marginTop:1}}>
                      ✓ куплено · {bag[it.name]} {it.unit}
                    </div>
                  )}
                </div>
                <div style={{
                  fontFamily:'var(--mono)', fontSize:12,
                  color: coins<it.price?'var(--ink-faint)':'var(--ink)',
                  textAlign:'right',
                }}>
                  {it.price}<span style={{color:'var(--gilt)', marginLeft:2}}>🜚</span>
                  <div style={{fontSize:9, color:'var(--ink-faint)'}}>/ {it.unit}</div>
                </div>
                <button onClick={()=>buy(it)} disabled={coins<it.price}
                  className="inkbtn"
                  style={{padding:'5px 10px', fontSize:11}}>
                  купить
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div style={{marginTop:10, fontFamily:'var(--serif)', fontStyle:'italic', fontSize:11, color:'var(--ink-faint)', textAlign:'center'}}>
          На рынке полдень. Запах рыбы и пряностей.
        </div>
      </div>

      {/* Footer ribbon — coins, leave */}
      <div style={{
        borderTop:'1px solid rgba(60,35,10,0.45)',
        padding:'10px 12px',
        display:'flex', alignItems:'center', justifyContent:'space-between',
        background:'var(--vellum-2)',
      }}>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:14}}>
          У вас: <span style={{color:'var(--gilt)'}}>{coins}</span>
          <span style={{fontFamily:'var(--mono)', fontSize:12, color:'var(--ink-soft)', marginLeft:2}}>🜚</span>
        </div>
        <button className="inkbtn ghost" onClick={onLeave}>Уйти с рынка</button>
      </div>
    </div>
  );
}

Object.assign(window, { Market });
