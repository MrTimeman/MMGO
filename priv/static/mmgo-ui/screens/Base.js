// Base — skeuomorphic shelves: chest, shelves of grimoires, workbench, spell circle entry

function Base({onGo, onLeave}){
  // wire chest -> inventory
  const goInv = ()=> onGo && onGo('inventory');
  return (
    <div style={{position:'relative', flex:1, overflow:'hidden'}}>
      <div className="parchment"/>
      <div className="mmgo-scroll" style={{position:'relative', height:'100%', overflow:'auto', padding:'14px 14px 20px'}}>
        <Ornament>Дом на хуторе</Ornament>
        <div style={{textAlign:'center', fontStyle:'italic', color:'var(--ink-faint)', fontSize:11, marginTop:2, marginBottom:12}}>
          У вас 3 дн. припасов · вес 8/20
        </div>

        {/* Workbench */}
        <Tile onClick={()=>onGo('spell')} icon={<CircleIcon/>} title="Круг призыва" sub="Создание заклинаний" accent/>
        <Tile onClick={()=>onGo('grimoire')} icon={<BookIcon/>} title="Полки с гримуарами" sub="3 книги · 24 заклинания"/>
        <Tile onClick={goInv} icon={<ChestIcon/>} title="Сундук" sub="42 предмета · 8/20 кг"/>
        <Tile onClick={()=>{}} icon={<AlembicIcon/>} title="Алхимический стол" sub="Варка · зельеварение"/>
        <Tile onClick={()=>{}} icon={<ForgeIcon/>} title="Мастерская" sub="Починка · ремёсла"/>
        <Tile onClick={()=>{}} icon={<BedIcon/>} title="Кровать" sub="Отдохнуть до рассвета"/>

        <div className="hrule" style={{margin:'18px 4px 12px'}}/>
        <button className="inkbtn ghost" onClick={onLeave} style={{width:'100%'}}>Выйти во двор</button>
      </div>
    </div>
  );
}

function Tile({onClick, icon, title, sub, accent}){
  return (
    <button onClick={onClick} style={{
      display:'flex', alignItems:'center', gap:12,
      width:'100%', padding:'10px 12px', marginBottom:10,
      background: accent
        ? 'linear-gradient(180deg, oklch(0.9 0.05 295 / 0.35), oklch(0.82 0.06 290 / 0.5))'
        : 'linear-gradient(180deg, oklch(0.92 0.03 80), oklch(0.86 0.04 76))',
      border:`1px solid ${accent?'oklch(0.55 0.17 295 / 0.55)':'rgba(60,35,10,0.35)'}`,
      borderRadius:12, cursor:'pointer', textAlign:'left',
      boxShadow:'inset 0 1px 0 rgba(255,245,220,0.6), 0 2px 4px rgba(40,25,10,0.1)',
    }}>
      <div style={{
        width:48, height:48, borderRadius:10,
        background:'linear-gradient(180deg, oklch(0.82 0.05 78), oklch(0.72 0.06 72))',
        border:'1px solid rgba(60,35,10,0.45)',
        boxShadow:'inset 0 0 8px rgba(60,35,10,0.22), inset 0 1px 0 rgba(255,245,220,0.5)',
        display:'flex', alignItems:'center', justifyContent:'center',
        color:'var(--ink)', flexShrink:0,
      }}>{icon}</div>
      <div style={{flex:1}}>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:16, color:'var(--ink)'}}>{title}</div>
        <div style={{fontFamily:'var(--serif)', fontSize:11, fontStyle:'italic', color:'var(--ink-soft)', marginTop:2}}>{sub}</div>
      </div>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none"><path d="M9 6l6 6-6 6" stroke="var(--ink-faint)" strokeWidth="2" strokeLinecap="round"/></svg>
    </button>
  );
}

// Tiny skeuomorphic icons
function CircleIcon(){
  return (
    <svg width="28" height="28" viewBox="-14 -14 28 28">
      <circle r="12" fill="none" stroke="var(--magic)" strokeWidth="1"/>
      <circle r="9" fill="none" stroke="var(--ink)" strokeWidth=".8" strokeDasharray="1 1"/>
      <circle r="5" fill="none" stroke="var(--ink)" strokeWidth=".8"/>
      <polygon points="0,-4 3.8,2 -3.8,2" fill="none" stroke="var(--wax)" strokeWidth=".8"/>
    </svg>
  );
}
function BookIcon(){
  return (
    <svg width="28" height="28" viewBox="0 0 28 28">
      <rect x="4" y="5" width="8" height="18" fill="var(--s-fire)" stroke="var(--ink)" strokeWidth="1" opacity=".9"/>
      <rect x="13" y="3" width="7" height="20" fill="var(--s-water)" stroke="var(--ink)" strokeWidth="1" opacity=".9"/>
      <rect x="21" y="6" width="4" height="17" fill="var(--s-life)" stroke="var(--ink)" strokeWidth="1" opacity=".9"/>
      <line x1="6" y1="9" x2="10" y2="9" stroke="var(--gilt)" strokeWidth=".8"/>
      <line x1="15" y1="7" x2="18" y2="7" stroke="var(--gilt)" strokeWidth=".8"/>
    </svg>
  );
}
function ChestIcon(){
  return (
    <svg width="28" height="28" viewBox="0 0 28 28">
      <rect x="3" y="9" width="22" height="14" fill="var(--sepia)" stroke="var(--ink)" strokeWidth="1"/>
      <path d="M3 9 Q14 4 25 9" fill="none" stroke="var(--ink)" strokeWidth="1"/>
      <line x1="3" y1="15" x2="25" y2="15" stroke="var(--gilt)" strokeWidth="1"/>
      <rect x="12" y="13" width="4" height="5" fill="var(--gilt)" stroke="var(--ink)" strokeWidth=".7"/>
    </svg>
  );
}
function AlembicIcon(){
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" stroke="var(--ink)" strokeWidth="1">
      <path d="M11 3h6v6l4 12a3 3 0 01-3 4H10a3 3 0 01-3-4l4-12V3z"/>
      <path d="M10 17h8" />
      <path d="M12 19 Q14 22 16 19" stroke="var(--s-water)"/>
    </svg>
  );
}
function ForgeIcon(){
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" stroke="var(--ink)" strokeWidth="1">
      <path d="M5 22h18"/>
      <path d="M8 22V13l-3-3 5-5 12 12-3 3h-9"/>
      <circle cx="18" cy="19" r="1.5" fill="var(--s-fire)" stroke="none"/>
    </svg>
  );
}
function BedIcon(){
  return (
    <svg width="28" height="28" viewBox="0 0 28 28" fill="none" stroke="var(--ink)" strokeWidth="1">
      <path d="M3 20V8"/><path d="M25 20V14"/>
      <path d="M3 14h22"/><path d="M3 20h22"/>
      <rect x="6" y="10" width="7" height="4" rx="1" fill="var(--vellum-shade)"/>
    </svg>
  );
}

Object.assign(window, { Base });
