// Inventory — chest contents + carried-on-person split.
// Parchment ledger of items, sortable by category, with weight/coin readout.

const ITEMS = [
  // chest items
  {id:'i1',  loc:'chest', cat:'weapon',   name:'Меч стальной',          qty:1, weight:1.4, val:42, tag:''},
  {id:'i2',  loc:'chest', cat:'armor',    name:'Кольчуга',              qty:1, weight:6.0, val:120, tag:''},
  {id:'i3',  loc:'chest', cat:'reagent',  name:'Ртуть, флакон',         qty:3, weight:0.2, val:18, tag:'алх.'},
  {id:'i4',  loc:'chest', cat:'reagent',  name:'Корень мандрагоры',     qty:2, weight:0.05, val:38, tag:'редк.'},
  {id:'i5',  loc:'chest', cat:'reagent',  name:'Соль смешанная',        qty:8, weight:0.1, val:6, tag:''},
  {id:'i6',  loc:'chest', cat:'paper',    name:'Пергамент, лист',       qty:24, weight:0.02, val:8, tag:''},
  {id:'i7',  loc:'chest', cat:'paper',    name:'Чернила красные',       qty:4, weight:0.15, val:14, tag:''},
  {id:'i8',  loc:'chest', cat:'tool',     name:'Отмычки (3 шт)',        qty:1, weight:0.1, val:30, tag:''},
  {id:'i9',  loc:'chest', cat:'misc',     name:'Письмо с печатью',      qty:1, weight:0.01, val:0, tag:'квест'},
  {id:'i10', loc:'chest', cat:'misc',     name:'Серебряный кулон',      qty:1, weight:0.05, val:80, tag:''},

  // carried items
  {id:'c1',  loc:'carry', cat:'reagent',  name:'Полынь, пучок',         qty:5, weight:0.05, val:3, tag:''},
  {id:'c2',  loc:'carry', cat:'paper',    name:'Походный гримуар',      qty:1, weight:0.4, val:0, tag:'актив.'},
  {id:'c3',  loc:'carry', cat:'tool',     name:'Кинжал',                qty:1, weight:0.4, val:18, tag:''},
  {id:'c4',  loc:'carry', cat:'food',     name:'Дорожные припасы',      qty:3, weight:0.3, val:5, tag:'дн.'},
  {id:'c5',  loc:'carry', cat:'food',     name:'Фляга с водой',         qty:1, weight:0.5, val:2, tag:''},
];

const CATS = [
  {k:'all',     label:'Все'},
  {k:'reagent', label:'Реагенты'},
  {k:'paper',   label:'Бумага'},
  {k:'weapon',  label:'Оружие'},
  {k:'armor',   label:'Доспехи'},
  {k:'tool',    label:'Снаряжение'},
  {k:'food',    label:'Еда'},
  {k:'misc',    label:'Прочее'},
];

const CAT_ICON = {
  reagent:'⚗', paper:'✎', weapon:'⚔', armor:'⛨', tool:'🜔', food:'⌬', misc:'❖',
};

function Inventory({onLeave}){
  const [tab, setTab] = React.useState('chest'); // chest | carry
  const [cat, setCat] = React.useState('all');
  const [items] = React.useState(ITEMS); // immutable for the demo

  const visible = items.filter(i=>i.loc===tab && (cat==='all' || i.cat===cat));
  const totalWeight = items.filter(i=>i.loc==='carry').reduce((s,i)=>s+i.qty*i.weight,0);
  const carryCap = 20;
  const totalValue = items.filter(i=>i.loc===tab).reduce((s,i)=>s+i.qty*i.val,0);

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      <div className="parchment"/>

      <div style={{position:'relative', padding:'10px 14px 6px', textAlign:'center'}}>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:16, letterSpacing:'.04em'}}>Опись</div>
        <div style={{fontFamily:'var(--script)', fontSize:13, color:'var(--ink-soft)', marginTop:-2}}>
          {tab==='chest'?'сундук в доме':'при себе'}
        </div>
      </div>

      <div style={{
        position:'relative',
        display:'flex', padding:'4px 12px', gap:6,
        borderBottom:'1px solid rgba(60,35,10,0.3)',
      }}>
        {[['chest','Сундук'],['carry','При себе']].map(([k,l])=>(
          <button key={k} onClick={()=>setTab(k)} style={{
            flex:1, padding:'8px', cursor:'pointer',
            background: tab===k?'var(--vellum)':'transparent',
            border:`1px solid ${tab===k?'var(--ink)':'rgba(60,35,10,0.25)'}`,
            borderRadius:'6px 6px 0 0',
            borderBottom:tab===k?'1px solid var(--vellum)':'1px solid rgba(60,35,10,0.3)',
            marginBottom:-1,
            fontFamily:'var(--display)', fontWeight: tab===k?700:500, fontSize:13,
            color: tab===k?'var(--ink)':'var(--ink-soft)',
          }}>{l}</button>
        ))}
      </div>

      {/* Category strip */}
      <div style={{
        position:'relative', padding:'6px 10px',
        display:'flex', gap:4, overflowX:'auto',
        borderBottom:'1px solid rgba(60,35,10,0.2)',
      }}>
        {CATS.map(c=>(
          <button key={c.k} onClick={()=>setCat(c.k)} style={{
            flexShrink:0, padding:'4px 10px', borderRadius:4,
            background: cat===c.k ? 'rgba(60,35,10,0.15)':'transparent',
            border:'1px solid transparent',
            fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)',
            textTransform:'uppercase', letterSpacing:'.06em',
            cursor:'pointer',
            fontWeight: cat===c.k?700:500,
          }}>{c.label}</button>
        ))}
      </div>

      {/* Items list */}
      <div className="mmgo-scroll" style={{position:'relative', flex:1, overflow:'auto'}}>
        {visible.length===0 && (
          <div style={{textAlign:'center', padding:40, fontFamily:'var(--serif)', fontStyle:'italic', color:'var(--ink-faint)', fontSize:12}}>
            пусто
          </div>
        )}
        <ul style={{listStyle:'none', margin:0, padding:'4px 0'}}>
          {visible.map(it=>(
            <li key={it.id} style={{
              display:'grid',
              gridTemplateColumns:'24px 1fr auto auto',
              alignItems:'center', gap:10,
              padding:'9px 14px',
              borderBottom:'1px dotted rgba(60,35,10,0.2)',
              cursor:'pointer',
            }}>
              <div style={{
                width:24, height:24, display:'flex', alignItems:'center', justifyContent:'center',
                fontSize:14, color:'var(--ink-soft)',
              }}>{CAT_ICON[it.cat]}</div>
              <div>
                <div style={{fontFamily:'var(--serif)', fontSize:13, color:'var(--ink)'}}>
                  {it.name}
                  {it.qty>1 && <span style={{fontFamily:'var(--mono)', color:'var(--ink-soft)', marginLeft:6}}>× {it.qty}</span>}
                </div>
                {it.tag && (
                  <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--wax)', textTransform:'uppercase', letterSpacing:'.05em', marginTop:1}}>
                    {it.tag}
                  </div>
                )}
              </div>
              <div style={{fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-faint)', textAlign:'right'}}>
                {(it.qty*it.weight).toFixed(2)} кг
              </div>
              <div style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--ink-soft)', textAlign:'right', minWidth:40}}>
                {it.val>0? <>{it.val*it.qty}<span style={{color:'var(--gilt)', marginLeft:1}}>🜚</span></> : '—'}
              </div>
            </li>
          ))}
        </ul>
      </div>

      {/* Footer ribbon */}
      <div style={{
        borderTop:'1px solid rgba(60,35,10,0.45)',
        background:'var(--vellum-2)',
        padding:'8px 14px',
        display:'flex', alignItems:'center', justifyContent:'space-between',
      }}>
        <div style={{fontFamily:'var(--mono)', fontSize:11, color:'var(--ink)'}}>
          вес: <b>{totalWeight.toFixed(1)}</b> / {carryCap} кг
          <span style={{color:'var(--ink-soft)', marginLeft:8}}>· оценка: {totalValue}🜚</span>
        </div>
        <button className="inkbtn ghost" onClick={onLeave} style={{padding:'5px 10px', fontSize:11}}>Закрыть</button>
      </div>
    </div>
  );
}

Object.assign(window, { Inventory });
