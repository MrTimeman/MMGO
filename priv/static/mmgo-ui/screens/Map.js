// World map — POIs, player token, animated travel, day/night

// Coordinates are % relative to the 2000×2000 source map.png
const POIS = [
  {id:'tower',       name:'Башня',          type:'tower',  x:44.5, y:21.0, desc:'Единственное место, где работает магия. Вход в подземелье.'},
  {id:'capital',     name:'Столица',        type:'city',   x:46.0, y:46.5, desc:'Столичный город княжества. Академия, рынок, таверны.'},
  {id:'east-town',   name:'Верхний Предел', type:'city',   x:77.0, y:25.5, desc:'Северный торговый город на границе.'},
  {id:'kamen',       name:'Камни',          type:'ruin',   x:88.0, y:37.0, desc:'Каменный круг в предгорьях.'},
  {id:'lake-village',name:'Малые Воды',     type:'village',x:55.5, y:61.0, desc:'Деревня у озера.'},
  {id:'windmill',    name:'Мельница',       type:'village',x:69.5, y:49.5, desc:'Мельница и хутор мельника.'},
  {id:'east-farms',  name:'Жёлтые Поля',    type:'village',x:83.5, y:55.0, desc:'Житница княжества — сельскохозяйственные артели.'},
  {id:'hermitage',   name:'Скит',           type:'ruin',   x:21.5, y:40.5, desc:'Заброшенная хижина в горах.'},
  {id:'farmstead',   name:'Хутор',          type:'camp',   x:48.0, y:89.0, desc:'Ваша база — маленький хутор на юге.'},
];

// Roads trace the actual dotted paths on map.png. Each is a list of control points
// for a catmull-rom-ish curve: [ [x,y], [x,y], ... ] — these bend where the real road bends.
const ROAD_PATHS = [
  { a:'capital',     b:'tower',        pts:[[46.0,46.5],[46.5,40],[46.8,32],[45.2,25],[44.5,21.0]] },
  { a:'capital',     b:'lake-village', pts:[[46.0,46.5],[48,51],[51,56],[55.5,61.0]] },
  { a:'lake-village',b:'farmstead',    pts:[[55.5,61.0],[53,71],[50,80],[48.0,89.0]] },
  { a:'capital',     b:'east-town',    pts:[[46.0,46.5],[52,42],[60,36],[68,30],[77.0,25.5]] },
  { a:'east-town',   b:'kamen',        pts:[[77.0,25.5],[81,30],[85,34],[88.0,37.0]] },
  { a:'capital',     b:'windmill',     pts:[[46.0,46.5],[55,47],[62,48.5],[69.5,49.5]] },
  { a:'windmill',    b:'east-farms',   pts:[[69.5,49.5],[75,51],[79,53],[83.5,55.0]] },
  { a:'lake-village',b:'windmill',     pts:[[55.5,61.0],[61,56],[65,53],[69.5,49.5]] },
  { a:'tower',       b:'hermitage',    pts:[[44.5,21.0],[38,27],[32,32],[26,37],[21.5,40.5]], dashed:'cult' }, // cult dashed route
];

function poi(id){ return POIS.find(p=>p.id===id); }

// Build a smooth SVG path from points using quadratic midpoints
function smoothPath(pts){
  if(pts.length<2) return '';
  let d = `M ${pts[0][0]} ${pts[0][1]}`;
  for(let i=1;i<pts.length-1;i++){
    const xc = (pts[i][0] + pts[i+1][0])/2;
    const yc = (pts[i][1] + pts[i+1][1])/2;
    d += ` Q ${pts[i][0]} ${pts[i][1]} ${xc} ${yc}`;
  }
  d += ` T ${pts[pts.length-1][0]} ${pts[pts.length-1][1]}`;
  return d;
}

// Sample a point along a polyline at t ∈ [0,1]
function samplePath(pts, t){
  if(pts.length<2) return {x:pts[0][0], y:pts[0][1]};
  // total length
  let lens=[]; let total=0;
  for(let i=0;i<pts.length-1;i++){
    const dx=pts[i+1][0]-pts[i][0], dy=pts[i+1][1]-pts[i][1];
    const L=Math.hypot(dx,dy); lens.push(L); total+=L;
  }
  const target = t*total;
  let acc=0;
  for(let i=0;i<lens.length;i++){
    if(acc+lens[i]>=target){
      const localT = (target-acc)/lens[i];
      return {
        x: pts[i][0]+(pts[i+1][0]-pts[i][0])*localT,
        y: pts[i][1]+(pts[i+1][1]-pts[i][1])*localT,
      };
    }
    acc+=lens[i];
  }
  return {x:pts[pts.length-1][0], y:pts[pts.length-1][1]};
}

// Icon for POI type — more map-sticker feel (pin + glyph)
function POIGlyph({type, size=20, active, night}){
  const s = size;
  const colors = {
    tower:  {bg:'oklch(0.55 0.14 28)',  ring:'oklch(0.35 0.12 28)'},
    city:   {bg:'oklch(0.50 0.08 260)', ring:'oklch(0.25 0.06 260)'},
    village:{bg:'oklch(0.68 0.12 62)',  ring:'oklch(0.40 0.08 60)'},
    ruin:   {bg:'oklch(0.55 0.02 280)', ring:'oklch(0.30 0.02 280)'},
    camp:   {bg:'oklch(0.48 0.13 135)', ring:'oklch(0.30 0.10 135)'},
  };
  const c = colors[type] || colors.camp;
  const icon = {tower:'♜', city:'♛', village:'⌂', ruin:'◘', camp:'▲'}[type] || '●';
  return (
    <div style={{
      width:s, height:s, borderRadius:'50%',
      display:'flex', alignItems:'center', justifyContent:'center',
      background:`radial-gradient(circle at 35% 30%, oklch(from ${c.bg} calc(l+.15) c h), ${c.bg})`,
      color:'#f5ead3',
      border:`2px solid ${active?'var(--wax)':c.ring}`,
      boxShadow: active
        ? '0 0 0 3px rgba(180,60,20,0.35), 0 3px 6px rgba(0,0,0,0.5)'
        : '0 2px 4px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,245,220,0.35)',
      transform: active?'scale(1.15)':'scale(1)',
      transition:'transform .15s ease',
    }}>
      <span style={{fontSize: s*0.55, fontWeight:700, lineHeight:1, filter:'drop-shadow(0 1px 0 rgba(0,0,0,0.3))'}}>{icon}</span>
    </div>
  );
}

function MapScreen({night, onEnter, gameTime, setGameTime}){
  const [pos, setPos] = React.useState({x: poi('farmstead').x, y: poi('farmstead').y});
  const [currentPoi, setCurrentPoi] = React.useState('farmstead');
  const [selected, setSelected] = React.useState(null);
  const [travelling, setTravelling] = React.useState(null);
  const [arrivalPrompt, setArrivalPrompt] = React.useState(null);
  const [scrollRef, setScrollRef] = React.useState(null);

  // Build adjacency from ROAD_PATHS
  const adj = React.useMemo(()=>{
    const m = {};
    ROAD_PATHS.forEach(r=>{
      (m[r.a] = m[r.a] || []).push({to:r.b, road:r});
      (m[r.b] = m[r.b] || []).push({to:r.a, road:r});
    });
    return m;
  },[]);

  // BFS shortest path (in nodes) between two POIs
  function findPath(from, to){
    if(from===to) return {nodes:[from], roads:[]};
    const q=[{nodes:[from], roads:[]}]; const seen=new Set([from]);
    while(q.length){
      const p = q.shift();
      const tail = p.nodes[p.nodes.length-1];
      for(const n of (adj[tail]||[])){
        if(seen.has(n.to)) continue;
        if(n.to===to) return {nodes:[...p.nodes, n.to], roads:[...p.roads, n.road]};
        seen.add(n.to); q.push({nodes:[...p.nodes, n.to], roads:[...p.roads, n.road]});
      }
    }
    return null;
  }

  // Animate travel — glide along stitched road control points
  React.useEffect(()=>{
    if(!travelling) return;
    let raf;
    let last = performance.now();
    const STEP_MS = 1800; // per road segment
    const tick = (now)=>{
      const dt = now - last; last = now;
      setTravelling(cur=>{
        if(!cur) return cur;
        const segs = cur.roads.length;
        if(segs===0) return null;
        const next = cur.t + dt / (STEP_MS * segs);
        if(next >= 1){
          const arrId = cur.nodes[cur.nodes.length-1];
          const arr = poi(arrId);
          setPos({x:arr.x, y:arr.y});
          setCurrentPoi(arrId);
          setArrivalPrompt(arrId);
          setSelected(null);
          setGameTime(gt => ({...gt, day: gt.day + segs*2}));
          return null;
        }
        // Which road segment?
        const segIdx = Math.min(Math.floor(next*segs), segs-1);
        const localT = next*segs - segIdx;
        const road = cur.roads[segIdx];
        // If we're traversing road backwards, flip sampling
        const forward = road.a === cur.nodes[segIdx];
        const tt = forward ? localT : (1-localT);
        const p = samplePath(road.pts, tt);
        setPos({x:p.x, y:p.y});
        return {...cur, t: next};
      });
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return ()=> cancelAnimationFrame(raf);
  },[travelling && travelling.nodes.join('-')]);

  // Pan so the player token stays near centre when travelling
  React.useEffect(()=>{
    if(!scrollRef) return;
    // Centre initial pos
    const box = scrollRef.getBoundingClientRect();
    const mapW = scrollRef.scrollWidth;
    const mapH = scrollRef.scrollHeight;
    const tx = (pos.x/100)*mapW - box.width/2;
    const ty = (pos.y/100)*mapH - box.height/2;
    scrollRef.scrollTo({left: Math.max(0,tx), top: Math.max(0,ty), behavior: travelling?'smooth':'instant'});
  }, [pos.x, pos.y, scrollRef, travelling]);

  const target = selected ? poi(selected) : null;
  const computed = selected ? findPath(currentPoi, selected) : null;

  // Highlight path as single smooth SVG path
  const highlightD = computed ? computed.roads.map(r=>{
    // direction?
    // We'll just concat control points; duplicates at joins are fine.
    return smoothPath(r.pts);
  }).join(' ') : null;

  return (
    <div style={{position:'relative', flex:1, overflow:'hidden', background:'#1a1410'}}>
      {/* Scroll container — map is larger than viewport for exploration */}
      <div ref={setScrollRef} style={{
        position:'absolute', inset:0, overflow:'auto',
      }} className="mmgo-scroll">
        <div style={{
          position:'relative',
          width: '200%', height: 0, paddingBottom: '200%',
        }}>
          {/* The map itself */}
          <img src={window.__MAP_URL || "map.png"} alt="" draggable="false" style={{
            position:'absolute', inset:0, width:'100%', height:'100%',
            filter: night
              ? 'brightness(.62) contrast(1.08) saturate(.85) hue-rotate(-8deg)'
              : 'contrast(1.03) saturate(1.08) brightness(1.02)',
            transition:'filter 1.2s ease',
            userSelect:'none',
          }}/>
          {/* subtle night gradient */}
          {night && (
            <div style={{
              position:'absolute', inset:0,
              background:'radial-gradient(120% 90% at 50% 30%, rgba(40,40,80,0) 40%, rgba(25,25,55,0.4) 75%, rgba(15,15,35,0.55) 100%)',
              pointerEvents:'none',
            }}/>
          )}

          {/* Roads layer — highlighted route on top */}
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{
            position:'absolute', inset:0, width:'100%', height:'100%', pointerEvents:'none',
          }}>
            {/* Already-visible dotted paths are on the bitmap, we just glow the chosen one */}
            {highlightD && (
              <>
                <path d={highlightD} fill="none"
                  stroke="rgba(255,220,120,0.5)" strokeWidth="0.9"
                  strokeLinecap="round" strokeLinejoin="round"
                  style={{filter:'drop-shadow(0 0 1.5px rgba(255,220,120,0.6))'}}
                />
                <path d={highlightD} fill="none"
                  stroke="var(--wax)" strokeWidth="0.5"
                  strokeDasharray="1 .9" strokeLinecap="round" strokeLinejoin="round"
                  style={{animation:'flicker 2s infinite'}}
                />
              </>
            )}
          </svg>

          {/* POI markers — positioned absolutely within the 200% canvas */}
          {POIS.map(p=>(
            <button key={p.id} onClick={()=> {
              if(p.id===currentPoi){ setArrivalPrompt(p.id); return; }
              setSelected(p.id);
            }} style={{
              position:'absolute', left:`${p.x}%`, top:`${p.y}%`,
              transform:'translate(-50%,-100%)',
              background:'none', border:'none', cursor:'pointer', padding:0,
              display:'flex', flexDirection:'column', alignItems:'center', gap:2,
              zIndex: 2,
            }}>
              <POIGlyph type={p.type}
                size={p.type==='tower'?30:p.type==='city'?28:p.type==='camp'?24:22}
                active={selected===p.id || currentPoi===p.id}
                night={night}
              />
              <span style={{
                fontFamily:'var(--display)',
                fontSize: p.type==='tower'||p.type==='city' ? 11 : 10,
                fontWeight:700,
                color: 'oklch(0.22 0.04 40)', /* dark ink */
                background: 'linear-gradient(180deg, oklch(0.94 0.035 82), oklch(0.88 0.055 78))',
                padding:'2px 8px',
                borderRadius:3,
                border:'1px solid oklch(0.48 0.06 50)',
                letterSpacing:'.04em', whiteSpace:'nowrap',
                marginTop: 3,
                boxShadow:'0 2px 3px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,245,220,0.6)',
                position:'relative',
              }}>{p.name}</span>
            </button>
          ))}

          {/* Player token */}
          <div style={{
            position:'absolute', left:`${pos.x}%`, top:`${pos.y}%`,
            transform:'translate(-50%,-50%)',
            pointerEvents:'none', zIndex:3,
          }}>
            {/* glow */}
            <div style={{
              position:'absolute', inset:-16, borderRadius:'50%',
              background:'radial-gradient(circle, rgba(255,210,130,0.55), transparent 65%)',
              animation:'pulse 2.2s ease-in-out infinite',
            }}/>
            <div style={{
              width:22, height:22, borderRadius:'50%',
              background:'radial-gradient(circle at 35% 30%, #fff5d0, #f5c26a 50%, var(--wax) 90%)',
              border:'2.5px solid #f5ead3',
              boxShadow:'0 0 0 2px rgba(180,60,20,0.55), 0 2px 6px rgba(0,0,0,0.5)',
              animation:'drift 2.5s ease-in-out infinite',
              position:'relative',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>
              <span style={{color:'var(--wax-deep)', fontFamily:'var(--rune)', fontSize:11, fontWeight:900, lineHeight:1}}>✦</span>
            </div>
          </div>
        </div>
      </div>

      {/* Compass (fixed) */}
      <div style={{
        position:'absolute', top:10, right:10, zIndex:4,
        width:52, height:52, borderRadius:'50%',
        background:'radial-gradient(circle, oklch(0.92 0.04 82 / 0.92), oklch(0.78 0.08 72 / 0.92))',
        border:'1.5px solid rgba(60,35,10,0.55)',
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow:'0 2px 8px rgba(0,0,0,0.45)',
      }}>
        <svg viewBox="-20 -20 40 40" width="40" height="40">
          <circle r="17" fill="none" stroke="#3a1f0a" strokeWidth=".4" strokeOpacity=".5"/>
          <polygon points="0,-14 2.8,0 0,2 -2.8,0" fill="var(--wax)"/>
          <polygon points="0,14 2.8,0 0,-2 -2.8,0" fill="#3a1f0a"/>
          <text x="0" y="-7" textAnchor="middle" fontSize="5.5" fontFamily="var(--rune)" fontWeight="700" fill="#3a1f0a">N</text>
        </svg>
      </div>

      {/* Traveller readout */}
      {travelling && (
        <div style={{
          position:'absolute', top:10, left:10, zIndex:4,
          background:'rgba(20,15,10,0.85)', color:'#f5ead3',
          padding:'6px 10px', borderRadius:8,
          border:'1px solid rgba(247,233,194,0.3)',
          fontFamily:'var(--mono)', fontSize:10, letterSpacing:'.04em',
          display:'flex', alignItems:'center', gap:8,
          backdropFilter:'blur(4px)',
        }}>
          <span style={{width:6, height:6, borderRadius:'50%', background:'var(--magic-soft)',
            boxShadow:'0 0 6px var(--magic)', animation:'pulse 1s infinite'}}/>
          В пути · {poi(travelling.nodes[0]).name} → {poi(travelling.nodes[travelling.nodes.length-1]).name}
        </div>
      )}

      {/* Travel confirm sheet */}
      {selected && !travelling && !arrivalPrompt && (
        <div style={{
          position:'absolute', left:10, right:10, bottom:10, zIndex:10,
          background:'var(--vellum)',
          border:'1px solid rgba(60,35,10,0.45)', borderRadius:14,
          padding:'12px 14px 14px',
          boxShadow:'0 10px 20px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,245,220,0.7)',
        }} className="vignette">
          <div style={{display:'flex', alignItems:'center', gap:10}}>
            <POIGlyph type={target.type} size={30} active/>
            <div style={{flex:1}}>
              <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:17}}>{target.name}</div>
              <div style={{fontSize:11, fontStyle:'italic', color:'var(--ink-soft)', marginTop:2}}>{target.desc}</div>
            </div>
            <button onClick={()=>setSelected(null)} style={{border:'none', background:'none', fontSize:18, color:'var(--ink-faint)', cursor:'pointer'}}>✕</button>
          </div>
          <div style={{
            display:'flex', gap:8, marginTop:10, flexWrap:'wrap',
            fontFamily:'var(--mono)', fontSize:10, color:'var(--ink-soft)',
          }}>
            <Chip color="ink">⏱ {computed ? computed.roads.length*2 : '—'} дн.</Chip>
            <Chip color="ink">🍞 {computed ? computed.roads.length*2 : '—'}</Chip>
            <Chip color="wax">Опасность: низкая</Chip>
          </div>
          <div style={{display:'flex', gap:8, marginTop:12}}>
            <button className="inkbtn ghost" onClick={()=>setSelected(null)} style={{flex:1}}>Отмена</button>
            <button className="inkbtn primary" disabled={!computed} onClick={()=>{
              if(!computed) return;
              setTravelling({nodes:computed.nodes, roads:computed.roads, t:0});
              setSelected(null);
            }} style={{flex:2}}>Выступить в путь</button>
          </div>
        </div>
      )}

      {/* Arrival prompt */}
      {arrivalPrompt && !travelling && (
        <div style={{
          position:'absolute', left:10, right:10, bottom:10, zIndex:10,
          background:'var(--vellum)',
          border:'1px solid rgba(60,35,10,0.45)', borderRadius:14,
          padding:'12px 14px 14px',
          boxShadow:'0 10px 20px rgba(0,0,0,0.5), inset 0 1px 0 rgba(255,245,220,0.7)',
        }} className="vignette">
          <Ornament tiny>Вы на месте</Ornament>
          <div style={{marginTop:8, display:'flex', alignItems:'center', gap:10}}>
            <POIGlyph type={poi(arrivalPrompt).type} size={30} active/>
            <div style={{flex:1}}>
              <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:17}}>{poi(arrivalPrompt).name}</div>
              <div style={{fontSize:11, fontStyle:'italic', color:'var(--ink-soft)', marginTop:2}}>{poi(arrivalPrompt).desc}</div>
            </div>
          </div>
          <div style={{display:'flex', gap:8, marginTop:12}}>
            <button className="inkbtn ghost" onClick={()=>setArrivalPrompt(null)} style={{flex:1}}>Остаться на карте</button>
            <button className="inkbtn primary" onClick={()=>{ setArrivalPrompt(null); onEnter(arrivalPrompt); }} style={{flex:2}}>Войти</button>
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { MapScreen, POIS });
