// MapScreen.jsx — living world map with travel, clock, day/night

const LOCATIONS = {
  capital:   { id: 'capital',   ru: 'Столица',       x: 40.5, y: 46.5, type: 'city',  safe: true,  desc: 'Главный город принципата. Академия, рынок и таверна.' },
  tower:     { id: 'tower',     ru: 'Башня',          x: 33.5, y: 19.5, type: 'tower', safe: false, desc: 'Единственное место, где работает магия. Вход в Подземелье.' },
  kergard:   { id: 'kergard',   ru: 'Кергард',        x: 55.5, y: 47.0, type: 'town',  safe: true,  desc: 'Торговый городок на восточной дороге.' },
  southtown: { id: 'southtown', ru: 'Нижний Брод',    x: 48.0, y: 59.5, type: 'town',  safe: false, desc: 'Перекрёсток с сомнительной репутацией.' },
  almar:     { id: 'almar',     ru: 'Альмар',         x: 68.0, y: 27.5, type: 'city',  safe: true,  desc: 'Богатый восточный город. Редкие реагенты.' },
  village1:  { id: 'village1',  ru: 'Привратная',     x: 44.0, y: 73.0, type: 'village', safe: true, desc: 'Малая деревушка.' },
};

const ROAD_SEGMENTS = [
  ['capital', 'tower'],
  ['capital', 'kergard'],
  ['capital', 'southtown'],
  ['kergard', 'almar'],
  ['southtown', 'kergard'],
  ['capital', 'village1'],
];

const TRAVEL_DAYS = {
  'capital-tower': 8, 'capital-kergard': 3, 'capital-southtown': 4,
  'kergard-almar': 5, 'southtown-kergard': 3, 'capital-village1': 5,
};

function getTravelDays(a, b) {
  return TRAVEL_DAYS[`${a}-${b}`] || TRAVEL_DAYS[`${b}-${a}`] || 6;
}

const MONTH_NAMES = ['Тирень','Дуэль','Вессель','Альтаир','Майрен','Сурт','Форос','Ундель','Клейн','Октра','Ноябрь','Декрас','Этмар'];
const SEASONS = ['Зима','Весна','Лето','Осень'];
const SEASON_ICONS = ['❄','🌱','☀','🍂'];

function MapScreen({ player, setPlayer, gameTime, isNight, onLocationTap }) {
  const [selected, setSelected] = React.useState(null);
  const [traveling, setTraveling] = React.useState(false);
  const [travelTarget, setTravelTarget] = React.useState(null);
  const [travelProg, setTravelProg] = React.useState(0);
  const animRef = React.useRef(null);

  const curLoc = LOCATIONS[player.location];
  const tgtLoc = travelTarget ? LOCATIONS[travelTarget] : null;

  const tokenX = traveling && tgtLoc
    ? curLoc.x + (tgtLoc.x - curLoc.x) * travelProg
    : curLoc.x;
  const tokenY = traveling && tgtLoc
    ? curLoc.y + (tgtLoc.y - curLoc.y) * travelProg
    : curLoc.y;

  const startTravel = (destId) => {
    if (traveling) return;
    setTraveling(true);
    setTravelTarget(destId);
    setTravelProg(0);
    setSelected(null);
    let start = null;
    const dur = 3200;
    const tick = (ts) => {
      if (!start) start = ts;
      const p = Math.min(1, (ts - start) / dur);
      setTravelProg(p);
      if (p < 1) {
        animRef.current = requestAnimationFrame(tick);
      } else {
        setTraveling(false);
        setTravelTarget(null);
        setPlayer(pl => ({ ...pl, location: destId }));
        if (onLocationTap) onLocationTap(destId);
      }
    };
    animRef.current = requestAnimationFrame(tick);
  };

  React.useEffect(() => () => animRef.current && cancelAnimationFrame(animRef.current), []);

  const seasonIdx = Math.floor(((gameTime.month - 1) % 12) / 3);
  const monthName = MONTH_NAMES[(gameTime.month - 1) % 13];

  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: '#0d0a07' }}>
      {/* Map image */}
      <img src="map.png" alt="map" style={{
        position: 'absolute', top: 0, left: 0,
        width: '100%', height: 'calc(100% - 70px)',
        objectFit: 'cover', objectPosition: '50% 40%',
        filter: isNight
          ? 'brightness(0.35) saturate(0.5) hue-rotate(210deg)'
          : 'brightness(0.82) saturate(0.85)',
        transition: 'filter 2s ease',
      }} />

      {/* Night radial vignette */}
      {isNight && (
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'radial-gradient(ellipse at 50% 50%, transparent 20%, rgba(0,5,30,0.55) 100%)',
        }} />
      )}

      {/* SVG overlay */}
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="xMidYMid slice"
        style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: 'calc(100% - 70px)', overflow: 'visible' }}
      >
        {/* Road lines */}
        {ROAD_SEGMENTS.map(([a, b]) => {
          const la = LOCATIONS[a], lb = LOCATIONS[b];
          return (
            <line key={`${a}-${b}`}
              x1={la.x} y1={la.y} x2={lb.x} y2={lb.y}
              stroke="rgba(200,164,74,0.12)" strokeWidth="0.35" strokeDasharray="1.5,1.2"
            />
          );
        })}

        {/* Travel line progress */}
        {traveling && tgtLoc && (
          <line
            x1={curLoc.x} y1={curLoc.y}
            x2={tokenX} y2={tokenY}
            stroke="#c8a44a" strokeWidth="0.5" strokeDasharray="0.8,0.8" opacity="0.7"
          />
        )}

        {/* Location markers */}
        {Object.values(LOCATIONS).map(loc => {
          const isHere = loc.id === player.location && !traveling;
          const isSel = selected === loc.id;
          const r = loc.type === 'city' ? 2 : loc.type === 'tower' ? 1.7 : loc.type === 'village' ? 1 : 1.4;
          const fill = isSel ? '#e8c46a' : isHere ? '#e8d5b0' : loc.safe ? '#60a040' : '#d04030';
          return (
            <g key={loc.id}
              style={{ cursor: loc.id !== player.location ? 'pointer' : 'default' }}
              onClick={() => { if (!traveling && loc.id !== player.location) setSelected(s => s === loc.id ? null : loc.id); }}
            >
              {isHere && (
                <circle cx={loc.x} cy={loc.y} r="3.5" fill="none" stroke="#c8a44a" strokeWidth="0.3" opacity="0.35">
                  <animate attributeName="r" values="2.5;4.5;2.5" dur="2.5s" repeatCount="indefinite" />
                  <animate attributeName="opacity" values="0.4;0;0.4" dur="2.5s" repeatCount="indefinite" />
                </circle>
              )}
              <circle cx={loc.x} cy={loc.y} r={r}
                fill={fill} stroke="#0d0a07" strokeWidth="0.5"
                opacity={traveling && travelTarget === loc.id ? 0.5 : 1}
              />
              {loc.type === 'tower' && (
                <polygon
                  points={`${loc.x},${loc.y - r - 1.2} ${loc.x - 0.8},${loc.y - r + 0.3} ${loc.x + 0.8},${loc.y - r + 0.3}`}
                  fill={fill} opacity={0.8}
                />
              )}
              <text x={loc.x} y={loc.y - r - 1.5}
                textAnchor="middle" fontSize="2.6"
                fontFamily="Cinzel, serif"
                fill={isSel ? '#e8c46a' : '#e8d5b0'}
                style={{ paintOrder: 'stroke', stroke: '#0d0a07', strokeWidth: 0.8 }}
              >{loc.ru}</text>
            </g>
          );
        })}

        {/* Player token */}
        <g>
          <circle cx={tokenX} cy={tokenY} r={traveling ? 1.6 : 1.3}
            fill="#c8a44a"
            style={{ filter: 'drop-shadow(0 0 2px #c8a44a)' }}
          >
            {traveling && <animate attributeName="r" values="1.2;1.9;1.2" dur="0.8s" repeatCount="indefinite" />}
          </circle>
          <circle cx={tokenX} cy={tokenY} r="2.4"
            fill="none" stroke="#c8a44a" strokeWidth="0.3" opacity="0.35" />
        </g>
      </svg>

      {/* Top bar */}
      <TelegramHeader
        title="MMGO"
        subtitle="Министерство Магии Онлайн"
        right={
          <div style={{ fontSize: 10, color: '#6a5840', textAlign: 'right', lineHeight: 1.5 }}>
            <div style={{ color: '#c8a44a', fontFamily: 'Cinzel' }}>{monthName} {gameTime.day}</div>
            <div>{SEASON_ICONS[seasonIdx]} {SEASONS[seasonIdx]} · Год {gameTime.year}</div>
          </div>
        }
      />

      {/* Bottom info panel */}
      <div style={{ position: 'absolute', bottom: 76, left: 12, right: 12 }}>
        {selected && !traveling && (
          <Panel style={{ padding: '13px 15px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 10 }}>
              <div>
                <div style={{ fontFamily: 'Cinzel', fontSize: 15, color: '#e8d5b0', marginBottom: 2 }}>
                  {LOCATIONS[selected].ru}
                </div>
                <div style={{ fontSize: 12, color: '#8a7a5a', lineHeight: 1.5 }}>
                  {LOCATIONS[selected].desc}
                </div>
                <div style={{ fontSize: 11, color: LOCATIONS[selected].safe ? '#60a040' : '#d04030', marginTop: 6, fontFamily: 'Cinzel' }}>
                  {LOCATIONS[selected].safe ? '◉ Безопасная зона' : '◈ Опасная зона · PvP'}
                </div>
              </div>
              <button onClick={() => setSelected(null)}
                style={{ background: 'none', border: 'none', color: '#3a2a18', cursor: 'pointer', fontSize: 20, lineHeight: 1, padding: '0 0 0 8px' }}>×</button>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: 11, color: '#4a3a28' }}>
                ~{getTravelDays(player.location, selected)} игр. дн.
              </div>
              <GoldButton onClick={() => startTravel(selected)}>Отправиться →</GoldButton>
            </div>
          </Panel>
        )}

        {traveling && tgtLoc && (
          <Panel style={{ padding: '11px 15px' }}>
            <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#c8a44a', marginBottom: 8 }}>
              В пути → {tgtLoc.ru}
            </div>
            <div style={{ height: 4, background: 'rgba(255,255,255,0.07)', borderRadius: 2, overflow: 'hidden' }}>
              <div style={{ height: '100%', width: `${travelProg * 100}%`, background: '#c8a44a', borderRadius: 2, transition: 'width 0.1s', boxShadow: '0 0 8px #c8a44a60' }} />
            </div>
          </Panel>
        )}

        {!selected && !traveling && (
          <Panel style={{ padding: '10px 15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ fontSize: 10, color: '#3a2a18', fontFamily: 'Cinzel', letterSpacing: '0.08em' }}>ВЫ ЗДЕСЬ</div>
              <div style={{ fontSize: 15, color: '#e8d5b0', fontFamily: 'Cinzel', marginTop: 2 }}>{curLoc.ru}</div>
            </div>
            <GoldButton small onClick={() => onLocationTap && onLocationTap(player.location)}>
              Действия
            </GoldButton>
          </Panel>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { MapScreen, LOCATIONS, getTravelDays });
