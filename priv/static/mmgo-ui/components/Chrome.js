// Shared chrome: top bar, bottom nav, game-time, parchment panels

const SCHOOL_GLYPH = {
  fire:   '◬',
  water:  '◉',
  earth:  '⬢',
  air:    '≋',
  chaos:  '✧',
  order:  '✦',
  life:   '❋',
  death:  '☗',
};
const SCHOOL_NAME_RU = {
  fire:'Огонь', water:'Вода', earth:'Земля', air:'Воздух',
  chaos:'Хаос', order:'Порядок', life:'Жизнь', death:'Смерть',
};
const SCHOOL_COLOR = {
  fire:'var(--s-fire)', water:'var(--s-water)', earth:'var(--s-earth)', air:'var(--s-air)',
  chaos:'var(--s-chaos)', order:'var(--s-order)', life:'var(--s-life)', death:'var(--s-death)',
};

// Telegram-style mini-app header (sits inside iOS device)
function MiniAppHeader({title, subtitle, left, right}){
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:10,
      padding:'8px 14px',
      borderBottom:'1px solid rgba(60,35,10,0.25)',
      background:'linear-gradient(180deg, rgba(255,245,220,0.55), rgba(255,245,220,0.0))',
      position:'relative', zIndex:5,
    }}>
      <div style={{width:30,display:'flex',justifyContent:'flex-start'}}>{left}</div>
      <div style={{flex:1, textAlign:'center'}}>
        <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:17, lineHeight:1, letterSpacing:'.01em', color:'var(--ink)'}}>{title}</div>
        {subtitle && <div style={{fontFamily:'var(--serif)', fontSize:11, color:'var(--ink-faint)', marginTop:2, fontStyle:'italic'}}>{subtitle}</div>}
      </div>
      <div style={{width:30,display:'flex',justifyContent:'flex-end'}}>{right}</div>
    </div>
  );
}

function HeaderBack({onClick}){
  return (
    <button onClick={onClick} aria-label="Назад" style={{
      border:'none', background:'none', padding:4, cursor:'pointer', color:'var(--ink-soft)',
      display:'flex', alignItems:'center',
    }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M15 6l-6 6 6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
    </button>
  );
}

function HeaderMenu({onClick}){
  return (
    <button onClick={onClick} aria-label="Меню" style={{
      border:'none', background:'none', padding:4, cursor:'pointer', color:'var(--ink-soft)',
      display:'flex', alignItems:'center',
    }}>
      <svg width="20" height="20" viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/></svg>
    </button>
  );
}

// Bottom nav — the five big zones
function BottomNav({current, onGo}){
  const items = [
    {k:'map',     label:'Карта',    icon: (a)=> <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke={a} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M9 3L3 5v16l6-2 6 2 6-2V3l-6 2-6-2z"/><path d="M9 3v16M15 5v16"/></svg>},
    {k:'base',    label:'База',     icon: (a)=> <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke={a} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M9 20v-6h6v6"/></svg>},
    {k:'spell',   label:'Круг',     icon: (a)=> <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke={a} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3v18M5.6 5.6l12.8 12.8M18.4 5.6L5.6 18.4"/></svg>},
    {k:'grimoire',label:'Гримуар',  icon: (a)=> <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke={a} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M4 4h12a3 3 0 013 3v13H7a3 3 0 01-3-3V4z"/><path d="M4 17a3 3 0 013-3h12"/><path d="M8 8h6M8 11h5"/></svg>},
    {k:'academy', label:'Академия', icon: (a)=> <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke={a} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M2 9l10-5 10 5-10 5L2 9z"/><path d="M6 11v5c2 1.5 4 2 6 2s4-.5 6-2v-5"/><path d="M22 9v5"/></svg>},
  ];
  return (
    <div style={{
      borderTop:'1px solid rgba(60,35,10,0.28)',
      background:'linear-gradient(180deg, rgba(255,245,220,0.0), rgba(60,35,10,0.06))',
      display:'grid', gridTemplateColumns:'repeat(5,1fr)',
      padding:'6px 4px 4px',
      position:'relative', zIndex:5,
    }}>
      {items.map(it => {
        const active = current===it.k;
        const color = active ? 'var(--wax)' : 'var(--ink-faint)';
        return (
          <button key={it.k} onClick={()=>onGo(it.k)} style={{
            border:'none', background:'none', cursor:'pointer',
            display:'flex', flexDirection:'column', alignItems:'center', gap:3,
            padding:'4px 0', color,
            fontFamily:'var(--display)', fontSize:10, fontWeight:600, letterSpacing:'.04em', textTransform:'uppercase',
          }}>
            {it.icon(color)}
            <span>{it.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// Game-time / weather pill
function GameTimePill({day, month, year, night, season='Лето'}){
  const monthNames = ['Жнивень','Светень','Мглистый','Трявень','Солнцестоя','Лозоплёт','Горница','Листобой','Вересень','Мрачень','Медвень','Заморозь','Стужень'];
  return (
    <div style={{
      display:'inline-flex', alignItems:'center', gap:8,
      background:'linear-gradient(180deg, oklch(0.93 0.04 80), oklch(0.88 0.05 76))',
      border:'1px solid rgba(60,35,10,0.3)',
      borderRadius:999, padding:'4px 10px 4px 8px',
      fontFamily:'var(--serif)', fontSize:11, color:'var(--ink)',
      boxShadow:'inset 0 1px 0 rgba(255,245,220,0.6), 0 1px 2px rgba(0,0,0,0.08)',
    }}>
      <span style={{fontFamily:'var(--rune)', fontSize:14, color: night?'var(--magic)':'var(--wax)'}}>
        {night ? '☾' : '☀'}
      </span>
      <span style={{fontFamily:'var(--mono)', fontSize:10, letterSpacing:'.04em'}}>
        {day} {monthNames[month-1]} · {year} г.
      </span>
      <span style={{fontStyle:'italic', color:'var(--ink-faint)', borderLeft:'1px solid rgba(60,35,10,0.25)', paddingLeft:7, fontSize:10}}>{season}</span>
    </div>
  );
}

// Ornamental heading
function Ornament({children, centered=true, tiny=false}){
  return (
    <div style={{
      textAlign: centered?'center':'left',
      fontFamily:'var(--display)', fontWeight:600,
      fontSize: tiny?13:18, letterSpacing:'.04em',
      color:'var(--ink)',
      textTransform: tiny?'uppercase':'none',
      display:'flex', alignItems:'center', gap:10, justifyContent:centered?'center':'flex-start',
    }}>
      <span style={{flex:centered?1:0, height:1, background:'linear-gradient(90deg, transparent, rgba(60,35,10,0.4))', minWidth: centered?20:0}}/>
      <span>{children}</span>
      <span style={{flex:1, height:1, background:'linear-gradient(90deg, rgba(60,35,10,0.4), transparent)'}}/>
    </div>
  );
}

// Small info chip
function Chip({children, color='ink', style={}}){
  const map = {
    ink:    {bg:'rgba(60,35,10,0.08)', fg:'var(--ink)', bd:'rgba(60,35,10,0.3)'},
    magic:  {bg:'oklch(0.9 0.06 295 / 0.35)', fg:'oklch(0.35 0.15 295)', bd:'oklch(0.55 0.17 295 / 0.5)'},
    wax:    {bg:'oklch(0.88 0.08 30 / 0.35)', fg:'var(--wax-deep)', bd:'rgba(120,50,20,0.45)'},
    verdigris:{bg:'oklch(0.88 0.05 170 / 0.35)', fg:'oklch(0.35 0.08 170)', bd:'oklch(0.5 0.06 170 / 0.5)'},
  };
  const m = map[color] || map.ink;
  return (
    <span style={{
      display:'inline-flex', alignItems:'center', gap:4,
      padding:'2px 7px', borderRadius:999,
      background:m.bg, color:m.fg, border:`1px solid ${m.bd}`,
      fontFamily:'var(--mono)', fontSize:10, letterSpacing:'.04em',
      ...style,
    }}>{children}</span>
  );
}

Object.assign(window, {
  MiniAppHeader, HeaderBack, HeaderMenu, BottomNav, GameTimePill, Ornament, Chip,
  SCHOOL_GLYPH, SCHOOL_NAME_RU, SCHOOL_COLOR,
});
