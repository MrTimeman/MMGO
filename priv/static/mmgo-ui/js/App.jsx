// App.jsx — root component, routing, game clock, tweaks

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "mapNight": false,
  "grimoireLayout": "shelves"
}/*EDITMODE-END*/;

function App() {
  const [screen, setScreen] = React.useState('map');
  const [subScreen, setSubScreen] = React.useState(null);
  const [tweaks, setTweaks] = React.useState(TWEAK_DEFAULTS);
  const [showTweaks, setShowTweaks] = React.useState(false);
  const [player, setPlayer] = React.useState(MOCK_PLAYER);

  // Game clock — 1 real second ≈ 1 game day (demo speed; real is ~4 min)
  const [gameTime, setGameTime] = React.useState({ day: 14, month: 3, year: 7 });
  React.useEffect(() => {
    const id = setInterval(() => {
      setGameTime(t => {
        let { day, month, year } = t;
        day++;
        if (day > 28) { day = 1; month++; }
        if (month > 13) { month = 1; year++; }
        return { day, month, year };
      });
    }, 4000);
    return () => clearInterval(id);
  }, []);

  // Tweaks bridge
  React.useEffect(() => {
    const handler = (e) => {
      if (e.data?.type === '__activate_edit_mode')   setShowTweaks(true);
      if (e.data?.type === '__deactivate_edit_mode') setShowTweaks(false);
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  const updateTweak = (key, value) => {
    const next = { ...tweaks, [key]: value };
    setTweaks(next);
    window.parent.postMessage({ type: '__edit_mode_set_keys', edits: next }, '*');
  };

  const navigate = (to) => {
    setSubScreen(null);
    setScreen(to);
  };

  const handleArrive = (locId) => {
    setPlayer(p => ({ ...p, location: locId }));
    setSubScreen({ type: 'location', id: locId });
  };

  const handleLocationTap = (locId) => {
    setSubScreen({ type: 'location', id: locId });
  };

  const renderScreen = () => {
    if (subScreen?.type === 'location') {
      return (
        <LocationScreen
          locationId={subScreen.id}
          onNav={navigate}
          onBack={() => setSubScreen(null)}
        />
      );
    }
    switch (screen) {
      case 'map':
        return (
          <MapScreen
            player={player}
            setPlayer={setPlayer}
            gameTime={gameTime}
            isNight={tweaks.mapNight}
            onArrive={handleArrive}
            onLocationTap={handleLocationTap}
          />
        );
      case 'combat':   return <CombatScreen />;
      case 'magic':    return <SpellScreen />;
      case 'grimoire': return <GrimoireScreen layout={tweaks.grimoireLayout} />;
      case 'base':     return <BaseScreen />;
      case 'academy':  return <AcademyScreen />;
      default:         return null;
    }
  };

  return (
    <div style={{ width: '100%', height: '100%', position: 'relative', background: '#0d0a07', overflow: 'hidden' }}>
      {renderScreen()}

      {/* Bottom nav — hidden on location sub-screens */}
      {!subScreen && (
        <BottomNav active={screen} onChange={navigate} />
      )}

      {/* Tweaks panel */}
      {showTweaks && (
        <div style={{
          position: 'absolute',
          bottom: !subScreen ? 82 : 16,
          right: 12,
          background: 'linear-gradient(155deg, #2e2418, #1c1610)',
          border: '1px solid rgba(200,164,74,0.42)',
          borderRadius: 12,
          padding: '14px 15px',
          width: 196,
          zIndex: 200,
          boxShadow: '0 8px 32px rgba(0,0,0,0.7)',
        }}>
          <div style={{ fontFamily: 'Cinzel', fontSize: 12, color: '#c8a44a', marginBottom: 12, letterSpacing: '0.06em' }}>
            TWEAKS
          </div>

          {/* Map day/night */}
          <div style={{ marginBottom: 12 }}>
            <div style={{ fontSize: 10, color: '#4a3a28', fontFamily: 'Cinzel', marginBottom: 6, letterSpacing: '0.04em' }}>КАРТА</div>
            <button onClick={() => updateTweak('mapNight', !tweaks.mapNight)} style={{
              width: '100%',
              background: tweaks.mapNight ? 'rgba(40,50,100,0.4)' : 'rgba(200,164,74,0.12)',
              border: `1px solid ${tweaks.mapNight ? 'rgba(80,100,200,0.45)' : 'rgba(200,164,74,0.28)'}`,
              borderRadius: 7, padding: '6px 10px', cursor: 'pointer',
              fontSize: 11, color: '#c8b890', fontFamily: 'Vollkorn, serif',
              textAlign: 'left', display: 'flex', alignItems: 'center', gap: 7,
            }}>
              <span style={{ fontSize: 14 }}>{tweaks.mapNight ? '🌙' : '☀️'}</span>
              {tweaks.mapNight ? 'Ночь' : 'День'} — переключить
            </button>
          </div>

          {/* Grimoire layout */}
          <div>
            <div style={{ fontSize: 10, color: '#4a3a28', fontFamily: 'Cinzel', marginBottom: 6, letterSpacing: '0.04em' }}>ГРИМУАРЫ</div>
            {[
              { id: 'shelves', label: '📚 Полки' },
              { id: 'cards',   label: '🗂 Карточки' },
            ].map(opt => (
              <button key={opt.id} onClick={() => updateTweak('grimoireLayout', opt.id)} style={{
                display: 'block', width: '100%', marginBottom: 4,
                background: tweaks.grimoireLayout === opt.id ? 'rgba(200,164,74,0.18)' : 'transparent',
                border: `1px solid ${tweaks.grimoireLayout === opt.id ? 'rgba(200,164,74,0.45)' : 'rgba(200,164,74,0.14)'}`,
                borderRadius: 7, padding: '5px 9px', cursor: 'pointer',
                fontSize: 11, color: tweaks.grimoireLayout === opt.id ? '#c8a44a' : '#5a4a30',
                textAlign: 'left', fontFamily: 'Vollkorn, serif',
              }}>
                {opt.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
