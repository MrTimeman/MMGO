// MMGO — main router + Telegram mini-app shell inside iOS device frame

const { useState, useEffect } = React;

function App(){
  // Persist current screen in localStorage
  const [screen, setScreen] = useState(()=> localStorage.getItem('mmgo.screen') || 'map');
  const [currentPoi, setCurrentPoi] = useState(()=> localStorage.getItem('mmgo.poi') || 'farmstead');
  const [gameTime, setGameTime] = useState({day:14, month:7, year:1247, season:'Лето'});

  // Tweaks
  const TWEAKS = /*EDITMODE-BEGIN*/{
    "night": false,
    "grimoireLayout": "shelves"
  }/*EDITMODE-END*/;
  const [tweaks, setTweaks] = useState(TWEAKS);
  const [tweaksOpen, setTweaksOpen] = useState(false);

  useEffect(()=>{ localStorage.setItem('mmgo.screen', screen); },[screen]);
  useEffect(()=>{ localStorage.setItem('mmgo.poi', currentPoi); },[currentPoi]);

  // Edit-mode bridge
  useEffect(()=>{
    const handler = (e)=>{
      if(!e.data || typeof e.data!=='object') return;
      if(e.data.type==='__activate_edit_mode') setTweaksOpen(true);
      if(e.data.type==='__deactivate_edit_mode') setTweaksOpen(false);
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({type:'__edit_mode_available'}, '*');
    return ()=> window.removeEventListener('message', handler);
  },[]);

  function setTweak(k, v){
    const edits = {[k]: v};
    setTweaks(prev=>({...prev, ...edits}));
    window.parent.postMessage({type:'__edit_mode_set_keys', edits}, '*');
  }

  // Persisted party (the GDD's tool/alch crew of up to 3)
  const [party, setParty] = useState(()=> {
    try { return JSON.parse(localStorage.getItem('mmgo.party')||'["torvald","lien"]'); }
    catch(e){ return ['torvald','lien']; }
  });
  useEffect(()=>{ localStorage.setItem('mmgo.party', JSON.stringify(party)); },[party]);

  const title = {
    map:'Карта княжества',
    location:'Прибытие',
    base:'Хутор',
    spell:'Круг призыва',
    grimoire:'Гримуары',
    combat:'Бой',
    academy:'Академия',
    market:'Рынок',
    tavern:'Таверна',
    dungeon:'Подземелье',
    inventory:'Опись',
  }[screen];

  const subtitle = {
    map:'ручная съёмка · 1247 г.',
    location:'вы здесь',
    base:'ваш дом',
    spell:'Латынь и намерение',
    grimoire:'полки и каталог',
    combat:'одновременные ходы',
    academy:'осенний триместр',
    market:'столица · полдень',
    tavern:'«Три пера»',
    dungeon:'ярус I',
    inventory:'сундук и карманы',
  }[screen];

  function go(s){ setScreen(s); }
  function enterLocation(poiId){
    setCurrentPoi(poiId);
    setScreen('location');
  }

  // Screen content
  let body;
  if(screen==='map')      body = <MapScreen night={tweaks.night} onEnter={enterLocation} gameTime={gameTime} setGameTime={setGameTime}/>;
  else if(screen==='location') body = <LocationEvent poiId={currentPoi} onLeave={()=>setScreen('map')} onGo={(k)=>{
      if(k==='base')        setScreen('base');
      else if(k==='dungeon') setScreen('dungeon');
      else if(k==='party' || k==='tavern') setScreen('tavern');
      else if(k==='market') setScreen('market');
      else if(k==='academy') setScreen('academy');
      else if(k==='library') setScreen('grimoire');
      else if(k==='letter')  setScreen('base'); // placeholder
      else setScreen('base');
    }}/>;
  else if(screen==='base')    body = <Base onGo={go} onLeave={()=>setScreen('location')}/>;
  else if(screen==='spell')   body = <SpellCircle onLeave={()=>setScreen('base')}/>;
  else if(screen==='grimoire')body = <Grimoire layout={tweaks.grimoireLayout} onLayoutChange={(l)=>setTweak('grimoireLayout',l)} onLeave={()=>setScreen('base')}/>;
  else if(screen==='combat')  body = <Combat onLeave={()=>setScreen('dungeon')}/>;
  else if(screen==='academy') body = <Academy onLeave={()=>setScreen('location')}/>;
  else if(screen==='market')  body = <Market onLeave={()=>setScreen('location')}/>;
  else if(screen==='tavern')  body = <Tavern onLeave={()=>setScreen('location')} party={party} setParty={setParty}/>;
  else if(screen==='dungeon') body = <Dungeon onLeave={()=>setScreen('location')} onCombat={()=>setScreen('combat')}/>;
  else if(screen==='inventory')body = <Inventory onLeave={()=>setScreen('base')}/>;

  // Hide bottom nav on immersive screens
  const showNav = !['combat','location','dungeon'].includes(screen);

  return (
    <div style={{display:'flex', gap:24, alignItems:'center'}}>
      <IOSDevice width={402} height={874} dark={tweaks.night}>
        <div style={{
          height:'100%', display:'flex', flexDirection:'column',
          background: tweaks.night ? 'oklch(0.16 0.03 258)' : 'oklch(0.94 0.022 82)',
        }}
          data-screen-label={`${({map:'01 ',location:'02 ',base:'03 ',spell:'04 ',grimoire:'05 ',combat:'06 ',academy:'07 ',market:'08 ',tavern:'09 ',dungeon:'10 ',inventory:'11 '})[screen]||''}${title}`}
        >
          <MiniAppHeader
            title={title}
            subtitle={subtitle}
            left={screen!=='map' ? <HeaderBack onClick={()=>setScreen('map')}/> : null}
            right={
              <div style={{display:'flex', alignItems:'center', gap:4}}>
                <HeaderMenu/>
              </div>
            }
          />
          <div style={{padding:'6px 10px 0', display:'flex', justifyContent:'center', gap:6}}>
            <GameTimePill day={gameTime.day} month={gameTime.month} year={gameTime.year} season={gameTime.season} night={tweaks.night}/>
            <Chip color="verdigris">⚡ 14 / 20</Chip>
            <Chip color="wax">🜚 128</Chip>
          </div>
          <div style={{flex:1, display:'flex', flexDirection:'column', marginTop:8, minHeight:0}}>
            {body}
          </div>
          {/* bottom nav removed — navigate via map */}
        </div>
      </IOSDevice>

      {tweaksOpen && (
        <div style={{
          width:260, padding:16, borderRadius:14,
          background:'rgba(30,25,20,0.92)', color:'#f5ead3',
          border:'1px solid rgba(245,234,211,0.2)',
          fontFamily:'var(--serif)',
          boxShadow:'0 10px 30px rgba(0,0,0,0.5)',
          backdropFilter:'blur(6px)',
        }}>
          <div style={{fontFamily:'var(--display)', fontWeight:700, fontSize:17, letterSpacing:'.03em', marginBottom:10}}>Tweaks</div>
          <label style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'8px 0', borderTop:'1px solid rgba(245,234,211,0.15)'}}>
            <span>Ночь на карте</span>
            <input type="checkbox" checked={tweaks.night} onChange={e=>setTweak('night', e.target.checked)}/>
          </label>
          <div style={{padding:'8px 0', borderTop:'1px solid rgba(245,234,211,0.15)'}}>
            <div style={{marginBottom:6, fontSize:12, color:'rgba(245,234,211,0.7)'}}>Вид гримуаров</div>
            <div style={{display:'flex', gap:6}}>
              {['shelves','catalog'].map(l=>(
                <button key={l} onClick={()=>setTweak('grimoireLayout',l)}
                  style={{
                    flex:1, padding:'6px 8px', borderRadius:6,
                    background: tweaks.grimoireLayout===l ? 'var(--wax)' : 'rgba(245,234,211,0.1)',
                    color: tweaks.grimoireLayout===l?'#fff':'rgba(245,234,211,0.8)',
                    border:'1px solid rgba(245,234,211,0.25)',
                    fontFamily:'var(--display)', fontSize:12, cursor:'pointer',
                  }}>{l==='shelves'?'Полки':'Каталог'}</button>
              ))}
            </div>
          </div>
          <div style={{marginTop:10, paddingTop:8, borderTop:'1px solid rgba(245,234,211,0.15)', fontSize:11, fontStyle:'italic', color:'rgba(245,234,211,0.55)'}}>
            Быстрая навигация для проверки дизайна:
          </div>
          <div style={{display:'grid', gridTemplateColumns:'1fr 1fr', gap:4, marginTop:6}}>
            {[
              ['map','Карта'],['location','Событие'],['base','База'],
              ['spell','Круг'],['grimoire','Гримуар'],['combat','Бой'],
              ['academy','Академия'],['market','Рынок'],['tavern','Таверна'],
              ['dungeon','Данж'],['inventory','Опись'],
            ].map(([k,l])=>(
              <button key={k} onClick={()=>setScreen(k)} style={{
                padding:'6px 4px', borderRadius:6,
                background: screen===k?'var(--wax)':'rgba(245,234,211,0.07)',
                color: screen===k?'#fff':'rgba(245,234,211,0.85)',
                border:'1px solid rgba(245,234,211,0.18)',
                fontFamily:'var(--serif)', fontSize:11, cursor:'pointer',
              }}>{l}</button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);

// app runs at bottom
