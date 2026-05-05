// Dungeon — top-down tile/room map. Visually a hand-inked dungeon plan on parchment.
// Same visual language as world map, but smaller scale, room-based, with a fog of war.

const ROOMS = [
  // x,y in % of viewport. type: entrance | room | shrine | treasure | boss
  {id:'r0', x:50, y:88, type:'entrance', label:'Вход'},
  {id:'r1', x:50, y:72, type:'room',     label:'Передняя'},
  {id:'r2', x:30, y:60, type:'room',     label:'Кладовая'},
  {id:'r3', x:70, y:60, type:'shrine',   label:'Алтарь'},
  {id:'r4', x:50, y:48, type:'room',     label:'Перекрёсток'},
  {id:'r5', x:22, y:34, type:'treasure', label:'Сундук'},
  {id:'r6', x:78, y:32, type:'room',     label:'Колодец'},
  {id:'r7', x:50, y:22, type:'boss',     label:'Зал Стража'},
];

const CORRIDORS = [
  ['r0','r1'], ['r1','r2'], ['r1','r3'], ['r1','r4'],
  ['r4','r5'], ['r4','r6'], ['r4','r7'],
];

function Dungeon({onLeave, onCombat}){
  const [pos, setPos] = React.useState('r0');
  const [seen, setSeen] = React.useState(new Set(['r0','r1']));

  function move(roomId){
    if(roomId===pos) return;
    // only allow if connected
    const ok = CORRIDORS.some(([a,b])=> (a===pos && b===roomId)||(b===pos && a===roomId));
    if(!ok) return;
    setPos(roomId);
    setSeen(s => new Set([...s, roomId]));
  }

  const here = ROOMS.find(r=>r.id===pos);

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', display:'flex', flexDirection:'column'}}>
      {/* Dungeon parchment background — darker, water-stained */}
      <div style={{
        position:'absolute', inset:0,
        background:`
          radial-gradient(ellipse at 30% 20%, oklch(0.62 0.06 60 / 0.6), transparent 40%),
          radial-gradient(ellipse at 70% 80%, oklch(0.55 0.08 35 / 0.5), transparent 50%),
          linear-gradient(180deg, oklch(0.74 0.05 65), oklch(0.66 0.06 60))
        `,
      }}/>
      <div className="parchment" style={{opacity:0.7}}/>

      {/* The dungeon plan itself */}
      <div style={{position:'relative', flex:1, overflow:'hidden'}}>
        <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{
          position:'absolute', inset:0, width:'100%', height:'100%',
        }}>
          {/* Corridors */}
          {CORRIDORS.map(([a,b],i)=>{
            const ra = ROOMS.find(r=>r.id===a);
            const rb = ROOMS.find(r=>r.id===b);
            const known = seen.has(a) && seen.has(b);
            return (
              <line key={i}
                x1={ra.x} y1={ra.y} x2={rb.x} y2={rb.y}
                stroke={known?'oklch(0.30 0.04 40)':'rgba(60,35,10,0.18)'}
                strokeWidth="0.7"
                strokeDasharray={known?'':'1.5 1.2'}
                vectorEffect="non-scaling-stroke"
              />
            );
          })}
        </svg>

        {/* Rooms */}
        {ROOMS.map(r=>{
          const isHere = r.id===pos;
          const known = seen.has(r.id);
          const reachable = CORRIDORS.some(([a,b])=> (a===pos && b===r.id)||(b===pos && a===r.id));
          if(!known && !reachable) return null;
          return (
            <button key={r.id}
              onClick={()=>move(r.id)}
              disabled={!reachable && !isHere}
              style={{
                position:'absolute', left:`${r.x}%`, top:`${r.y}%`,
                transform:'translate(-50%,-50%)',
                width:42, height:32, padding:0,
                background:'transparent', border:'none', cursor:reachable?'pointer':'default',
              }}>
              <RoomGlyph type={r.type} state={isHere?'here':known?'seen':'reachable'}/>
              {(known || isHere) && (
                <div style={{
                  position:'absolute', top:'100%', left:'50%', transform:'translateX(-50%)',
                  fontFamily:'var(--display)', fontSize:9, fontWeight:600,
                  color: isHere ? 'var(--wax)' : 'var(--ink)',
                  textShadow:'0 0 3px rgba(245,234,211,0.9)',
                  whiteSpace:'nowrap', marginTop:2,
                  pointerEvents:'none',
                }}>{r.label}</div>
              )}
            </button>
          );
        })}

        {/* Compass / scale ornament — bottom corner */}
        <div style={{
          position:'absolute', bottom:8, left:8,
          fontFamily:'var(--rune)', fontSize:10, color:'var(--ink-soft)',
          opacity:0.7,
        }}>
          ◬ Подземелье Башни — ярус I
        </div>
      </div>

      {/* Bottom panel — current room + actions */}
      <div style={{
        position:'relative',
        borderTop:'1px solid rgba(60,35,10,0.45)',
        background:'var(--vellum)',
        padding:'10px 12px',
      }}>
        <div style={{display:'flex', alignItems:'baseline', gap:8, marginBottom:8}}>
          <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:14}}>{here.label}</div>
          <div style={{fontFamily:'var(--mono)', fontSize:9, color:'var(--ink-faint)', textTransform:'uppercase', letterSpacing:'.06em'}}>
            {ROOM_DESC[here.type]?.tag}
          </div>
        </div>
        <div style={{fontFamily:'var(--serif)', fontStyle:'italic', fontSize:12, color:'var(--ink-soft)', lineHeight:1.45}}>
          {ROOM_DESC[here.type]?.text}
        </div>

        <div style={{display:'flex', gap:6, marginTop:10}}>
          {here.type==='boss' && (
            <button className="inkbtn primary" onClick={onCombat} style={{flex:1}}>
              Бой со Стражем
            </button>
          )}
          {here.type==='treasure' && (
            <button className="inkbtn primary" style={{flex:1}}>Открыть сундук</button>
          )}
          {here.type==='shrine' && (
            <button className="inkbtn" style={{flex:1}}>Помолиться (+1 ⚡)</button>
          )}
          {here.type==='room' && (
            <button className="inkbtn" style={{flex:1}}>Обыскать комнату</button>
          )}
          {here.type==='entrance' && (
            <button className="inkbtn ghost" onClick={onLeave} style={{flex:1}}>← Выйти из подземелья</button>
          )}
          {here.type!=='entrance' && (
            <button className="inkbtn ghost" onClick={()=>setPos('r0')}>в начало</button>
          )}
        </div>
      </div>
    </div>
  );
}

const ROOM_DESC = {
  entrance: {tag:'вход',     text:'Каменная арка, мхом по углам. Снаружи светит солнце; внутри — холод и эхо.'},
  room:     {tag:'комната',  text:'Пустое помещение. По стенам — следы старого пожара.'},
  shrine:   {tag:'алтарь',   text:'Каменный алтарь. На нём догорает чья-то свеча. Магия здесь сильнее.'},
  treasure: {tag:'сокровищница', text:'Окованный медью сундук. Замок цел, но на петлях — свежие царапины.'},
  boss:     {tag:'опасно',   text:'В дальнем углу что-то крупное переводит дыхание. Воздух гудит низко.'},
};

function RoomGlyph({type, state}){
  // state: here | seen | reachable
  const fill = type==='boss'    ? 'oklch(0.55 0.18 28)'
            : type==='treasure' ? 'oklch(0.65 0.13 80)'
            : type==='shrine'   ? 'oklch(0.55 0.16 295)'
            : type==='entrance' ? 'oklch(0.50 0.10 165)'
            : 'oklch(0.92 0.04 80)';
  const stroke = state==='here' ? 'var(--wax)' : 'var(--ink)';
  const sw = state==='here' ? 1.6 : 0.9;
  const opacity = state==='reachable' ? 0.55 : 1;
  return (
    <svg width="42" height="32" viewBox="-21 -16 42 32" style={{opacity, overflow:'visible'}}>
      {/* shadow */}
      <rect x="-13" y="-9" width="26" height="18" rx="2" fill="rgba(0,0,0,0.3)" transform="translate(1, 1)"/>
      {/* room rect */}
      <rect x="-13" y="-9" width="26" height="18" rx="2" fill={fill} stroke={stroke} strokeWidth={sw}/>
      {type==='boss' && (
        <text x="0" y="3" textAnchor="middle" fontSize="10" fontFamily="var(--rune)" fill="oklch(0.25 0.08 28)" fontWeight="700">⚔</text>
      )}
      {type==='treasure' && (
        <text x="0" y="3" textAnchor="middle" fontSize="10" fontFamily="var(--rune)" fill="oklch(0.30 0.08 60)" fontWeight="700">⛁</text>
      )}
      {type==='shrine' && (
        <text x="0" y="3" textAnchor="middle" fontSize="10" fontFamily="var(--rune)" fill="oklch(0.30 0.10 295)" fontWeight="700">✦</text>
      )}
      {type==='entrance' && (
        <text x="0" y="3" textAnchor="middle" fontSize="10" fontFamily="var(--rune)" fill="oklch(0.25 0.10 165)" fontWeight="700">↟</text>
      )}
      {state==='here' && (
        <circle r="2.5" cx="0" cy="0" fill="var(--wax)" stroke="oklch(0.25 0.10 27)" strokeWidth="0.6" style={{animation:'pulse-magic 1.6s ease-in-out infinite'}}/>
      )}
    </svg>
  );
}

Object.assign(window, { Dungeon });
