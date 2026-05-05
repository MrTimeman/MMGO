
// ═══ js/shared.jsx ═══
// shared.jsx — theme, constants, shared components

const THEME = {
  bg: '#0d0a07',
  surface: '#1c1610',
  surface2: '#252018',
  border: 'rgba(200,164,74,0.22)',
  gold: '#c8a44a',
  goldBright: '#e8c46a',
  goldDim: '#7a6030',
  cream: '#e8d5b0',
  creamDim: '#a89070',
  creamFaint: '#6a5840',
  red: '#e04020',
  blue: '#2060d0',
};

const SCHOOLS = {
  fire:  { ru: 'Огонь',    color: '#e05030', glyph: '🜂', opposite: 'water' },
  water: { ru: 'Вода',     color: '#3070d0', glyph: '🜄', opposite: 'fire'  },
  air:   { ru: 'Воздух',   color: '#40b8e0', glyph: '🜁', opposite: 'earth' },
  earth: { ru: 'Земля',    color: '#60902a', glyph: '🜃', opposite: 'air'   },
  chaos: { ru: 'Хаос',     color: '#9030b0', glyph: '⊗',  opposite: 'order' },
  order: { ru: 'Порядок',  color: '#90a8c0', glyph: '⊕',  opposite: 'chaos' },
  life:  { ru: 'Жизнь',    color: '#40a060', glyph: '✦',  opposite: 'death' },
  death: { ru: 'Смерть',   color: '#604080', glyph: '☽',  opposite: 'life'  },
};

const SLOTS = [
  { id: 'actio',   ru: 'Действие', hint: 'Что делает заклинание' },
  { id: 'forma',   ru: 'Форма',    hint: 'Геометрия эффекта' },
  { id: 'vis',     ru: 'Сила',     hint: 'Интенсивность' },
  { id: 'tempus',  ru: 'Время',    hint: 'Длительность' },
  { id: 'mutatio', ru: 'Мутация',  hint: 'Вторичный эффект' },
  { id: 'pretium', ru: 'Цена',     hint: 'Доп. стоимость' },
];

const MOCK_PLAYER = {
  name: 'Арвен',
  level: 12,
  class: 'wizard',
  schools: ['fire', 'chaos'],
  hp: 74, maxHp: 90,
  fatigue: 35, maxFatigue: 100,
  gold: 1240,
  location: 'capital',
  xp: 18400, xpNext: 22000,
};

const MOCK_SPELLS = [
  { id: 's1', name: 'Ictus Ignis',     nameRu: 'Удар Пламени',       school: 'fire',  words: ['ictus'] },
  { id: 's2', name: 'Radius Flamma',   nameRu: 'Луч Огня',           school: 'fire',  words: ['radius','flamma','magnus'] },
  { id: 's3', name: 'Captio Nexus',    nameRu: 'Захват Хаоса',       school: 'chaos', words: ['captio','nexus','mediocris','sustineo'] },
  { id: 's4', name: 'Scutum Pyre',     nameRu: 'Щит Пламени',        school: 'fire',  words: ['scutum','sphaera','levis'] },
  { id: 's5', name: 'Dissipatio',      nameRu: 'Рассеяние',          school: 'chaos', words: ['dissipatio','conus','magnus','momentum'] },
  { id: 's6', name: 'Ictus Chaos',     nameRu: 'Удар Хаоса',         school: 'chaos', words: ['ictus'] },
  { id: 's7', name: 'Murus Ignis',     nameRu: 'Стена Огня',         school: 'fire',  words: ['murus','ignis','magnus','sustineo','motus'] },
  { id: 's8', name: 'Vocatio Flamma',  nameRu: 'Призыв Пламени',     school: 'fire',  words: ['vocatio','sphaera','enormis','tardus','dissipatio','focus'] },
  { id: 's9', name: 'Caecus Tenebra',  nameRu: 'Слепая Тьма',        school: 'chaos', words: ['caecus','tenebra','levis'] },
  { id: 's10',name: 'Sanatio Brevis',  nameRu: 'Малое Исцеление',    school: 'life',  words: ['sanatio','momentum'] },
];

const MOCK_GRIMOIRES = [
  { id: 'g1', name: 'Малый Красный',   color: '#a02818', capacity: 8,  spells: ['s1','s2','s3','s4'] },
  { id: 'g2', name: 'Гримуар Хаоса',   color: '#6020a0', capacity: 12, spells: ['s3','s5','s6','s7','s8'] },
  { id: 'g3', name: 'Боевой',          color: '#2a3a18', capacity: 5,  spells: ['s1','s5'] },
];

// ── Shared Components ─────────────────────────────────────────────

function Panel({ children, style }) {
  return (
    <div style={{
      background: 'linear-gradient(155deg, #2e2418 0%, #1c1610 55%, #241e12 100%)',
      border: '1px solid rgba(200,164,74,0.22)',
      borderRadius: 12,
      ...style,
    }}>
      {children}
    </div>
  );
}

function GoldButton({ children, onClick, style, small, danger, disabled }) {
  const [hover, setHover] = React.useState(false);
  return (
    <button
      onClick={disabled ? undefined : onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        background: disabled ? 'transparent' : hover
          ? (danger ? 'rgba(200,50,30,0.2)' : 'rgba(200,164,74,0.15)')
          : 'transparent',
        border: `1px solid ${disabled ? 'rgba(100,80,50,0.3)' : danger
          ? (hover ? '#e04030' : 'rgba(200,60,40,0.5)')
          : (hover ? '#c8a44a' : 'rgba(200,164,74,0.4)')}`,
        borderRadius: 8,
        color: disabled ? '#4a3a28' : danger ? '#e08070' : '#c8a44a',
        fontFamily: 'Cinzel, serif',
        fontSize: small ? 11 : 13,
        padding: small ? '5px 12px' : '8px 20px',
        cursor: disabled ? 'default' : 'pointer',
        transition: 'all 0.18s',
        letterSpacing: '0.05em',
        ...style,
      }}
    >
      {children}
    </button>
  );
}

function HPBar({ value, max, color = '#c8a44a', label }) {
  const pct = Math.max(0, Math.min(100, (value / max) * 100));
  return (
    <div style={{ width: '100%' }}>
      {label && (
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
          <span style={{ fontSize: 10, color: '#6a5840', fontFamily: 'Cinzel', letterSpacing: '0.04em' }}>{label}</span>
          <span style={{ fontSize: 10, color: '#6a5840' }}>{value}/{max}</span>
        </div>
      )}
      <div style={{ height: 5, background: 'rgba(255,255,255,0.07)', borderRadius: 3, overflow: 'hidden' }}>
        <div style={{ height: '100%', width: `${pct}%`, background: color, borderRadius: 3, transition: 'width 0.5s ease', boxShadow: `0 0 6px ${color}60` }} />
      </div>
    </div>
  );
}

function SchoolTag({ school, small }) {
  const s = SCHOOLS[school];
  if (!s) return null;
  return (
    <span style={{
      display: 'inline-block',
      padding: small ? '1px 6px' : '2px 9px',
      borderRadius: 4,
      border: `1px solid ${s.color}44`,
      background: `${s.color}1a`,
      color: s.color,
      fontSize: small ? 10 : 11,
      fontFamily: 'Cinzel, serif',
    }}>{s.glyph} {s.ru}</span>
  );
}

const NAV_ITEMS = [
  { id: 'map',     icon: '◎', ru: 'Карта'    },
  { id: 'combat',  icon: '⚔', ru: 'Бой'      },
  { id: 'magic',   icon: '✦', ru: 'Магия'    },
  { id: 'base',    icon: '⌂', ru: 'База'     },
  { id: 'academy', icon: '✒', ru: 'Академия' },
];

function BottomNav({ active, onChange }) {
  return (
    <div style={{
      position: 'absolute',
      bottom: 0, left: 0, right: 0,
      height: 70,
      background: 'linear-gradient(0deg, #0d0a07 0%, #16120e 100%)',
      borderTop: '1px solid rgba(200,164,74,0.15)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-around',
      paddingBottom: 8,
      zIndex: 50,
    }}>
      {NAV_ITEMS.map(item => {
        const isActive = item.id === active;
        return (
          <button key={item.id} onClick={() => onChange(item.id)} style={{
            background: 'none', border: 'none', cursor: 'pointer',
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            padding: '6px 10px',
          }}>
            <span style={{ fontSize: 18, color: isActive ? '#c8a44a' : '#3a2a18', transition: 'color 0.2s' }}>
              {item.icon}
            </span>
            <span style={{ fontSize: 9, color: isActive ? '#c8a44a' : '#3a2a18', fontFamily: 'Cinzel', letterSpacing: '0.04em', transition: 'color 0.2s' }}>
              {item.ru}
            </span>
            {isActive && (
              <div style={{ width: 3, height: 3, borderRadius: '50%', background: '#c8a44a' }} />
            )}
          </button>
        );
      })}
    </div>
  );
}

function TelegramHeader({ title, subtitle, onBack, right }) {
  return (
    <div style={{
      position: 'absolute',
      top: 0, left: 0, right: 0,
      height: 56,
      paddingTop: 10,
      background: 'linear-gradient(180deg, rgba(13,10,7,0.98) 0%, rgba(13,10,7,0.92) 100%)',
      borderBottom: '1px solid rgba(200,164,74,0.12)',
      display: 'flex',
      alignItems: 'center',
      paddingLeft: onBack ? 6 : 16,
      paddingRight: 16,
      gap: 6,
      zIndex: 40,
      backdropFilter: 'blur(8px)',
    }}>
      {onBack && (
        <button onClick={onBack} style={{
          background: 'none', border: 'none', color: '#c8a44a', cursor: 'pointer',
          fontSize: 22, padding: '0 6px', lineHeight: 1, flexShrink: 0,
        }}>‹</button>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: 'Cinzel, serif', fontSize: 14, color: '#e8d5b0', letterSpacing: '0.06em', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {title}
        </div>
        {subtitle && (
          <div style={{ fontSize: 10, color: '#4a3a28', marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {subtitle}
          </div>
        )}
      </div>
      {right && <div style={{ flexShrink: 0 }}>{right}</div>}
    </div>
  );
}

Object.assign(window, {
  THEME, SCHOOLS, SLOTS,
  MOCK_PLAYER, MOCK_SPELLS, MOCK_GRIMOIRES,
  Panel, GoldButton, HPBar, SchoolTag,
  BottomNav, TelegramHeader, NAV_ITEMS,
});


// ═══ js/MapScreen.jsx ═══
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


// ═══ js/LocationScreen.jsx ═══
// LocationScreen.jsx — text event screen for arriving at locations

const LOCATION_DATA = {
  capital: {
    title: 'Столица',
    ambience: 'Безопасная зона',
    safe: true,
    desc: 'Шум торговых улиц, запах хлеба и магических реагентов. Высокие башни замка отбрасывают длинные тени на булыжные мостовые.',
    actions: [
      { id: 'market',  icon: '⚖',  label: 'Рынок',         desc: 'Купить и продать товары', nav: 'base' },
      { id: 'academy', icon: '✒',  label: 'Академия',       desc: 'Обучение, клубы, исследования', nav: 'academy' },
      { id: 'tavern',  icon: '🍺', label: 'Таверна',         desc: 'Отдохнуть, найти группу', sub: 'tavern' },
      { id: 'housing', icon: '⌂',  label: 'Жильё',          desc: 'Купить или арендовать базу', nav: 'base' },
      { id: 'cult',    icon: '⊗',  label: '???',             desc: 'Подозрительный переулок...', sub: 'cult' },
    ],
  },
  tower: {
    title: 'Башня',
    ambience: 'Зона магии · Опасно · PvP',
    safe: false,
    desc: 'Магические потоки ощущаются кожей. Воздух гудит. Башня уходит в небо, её верхушка теряется в облаках. У подножия — тяжёлая дверь в Подземелье.',
    actions: [
      { id: 'dungeon', icon: '▼',  label: 'Войти в Подземелье', desc: 'Уровень 1 · Требует группу', nav: 'combat' },
      { id: 'spells',  icon: '✦',  label: 'Сотворить заклинание', desc: 'Здесь работает магия', nav: 'magic' },
      { id: 'party',   icon: '⚔',  label: 'Найти группу',       desc: 'Игроки у входа', sub: 'party' },
      { id: 'library', icon: '📜', label: 'Библиотека Башни',    desc: 'Фрагменты редких заклятий', sub: 'lib' },
    ],
  },
  kergard: {
    title: 'Кергард',
    ambience: 'Безопасная зона',
    safe: true,
    desc: 'Небольшой городок на перекрёстке. Торговцы с востока и запада, шум постоялых дворов.',
    actions: [
      { id: 'market', icon: '⚖',  label: 'Рынок',           desc: 'Местные товары и реагенты' },
      { id: 'inn',    icon: '🍺', label: 'Постоялый двор',  desc: 'Отдохнуть, узнать слухи', sub: 'inn' },
    ],
  },
  southtown: {
    title: 'Нижний Брод',
    ambience: 'Опасная зона · PvP включён',
    safe: false,
    desc: 'Запах болота и горелого дерева. У таверны стоят мрачные фигуры. Здесь не задают лишних вопросов.',
    actions: [
      { id: 'black', icon: '⊗',  label: 'Чёрный рынок',    desc: 'Без налогов. Без гарантий.', sub: 'black' },
      { id: 'leave', icon: '←',  label: 'Уйти',             desc: 'Поскорее' },
    ],
  },
  almar: {
    title: 'Альмар',
    ambience: 'Безопасная зона',
    safe: true,
    desc: 'Богатый восточный город. Купеческие гильдии, экзотические реагенты, алхимические лавки.',
    actions: [
      { id: 'market', icon: '⚖', label: 'Восточный рынок', desc: 'Редкие ингредиенты и гримуары' },
      { id: 'guild',  icon: '★', label: 'Гильдия',          desc: 'Заказы и репутация', sub: 'guild' },
    ],
  },
  village1: {
    title: 'Привратная',
    ambience: 'Безопасная зона',
    safe: true,
    desc: 'Тихая деревушка. Пахнет хлевом и дымом. Жители косятся с любопытством.',
    actions: [
      { id: 'rest', icon: '💤', label: 'Отдохнуть', desc: 'Восстановить HP', effect: 'rest' },
    ],
  },
};

const SUB_EVENTS = {
  tavern: {
    title: 'Таверна «Золотая Кружка»',
    desc: 'Гул разговоров, дым очага. За столами сидят искатели приключений. Бармен молча протирает стаканы.',
    actions: [
      { id: 'board',   icon: '📋', label: 'Доска объявлений о группах', desc: '3 активных поиска' },
      { id: 'rest',    icon: '💤', label: 'Отдохнуть',                  desc: 'Восстановить HP и усталость', effect: 'rest' },
      { id: 'gossip',  icon: '👂', label: 'Послушать слухи',            desc: '+1–2 случайных события', effect: 'gossip' },
      { id: 'back',    icon: '←',  label: 'Выйти',                                                        back: true },
    ],
  },
  cult: {
    title: 'Тёмный переулок',
    desc: 'В тени вы замечаете алхимический символ, нацарапанный на камне. Рядом — неприметная дверь в стене.',
    actions: [
      { id: 'knock',  icon: '👊', label: 'Постучать',  desc: 'Рискнуть', effect: 'cult_knock' },
      { id: 'back',   icon: '←',  label: 'Уйти',                          back: true },
    ],
  },
  party: {
    title: 'Поиск группы',
    desc: 'У входа в Подземелье ждут несколько игроков. Все смотрят на вас с оценкой.',
    actions: [
      { id: 'j1',   icon: '⚔', label: 'Арвен (Маг огня, ур.14) — ищет группу',   desc: 'Специализация: Огонь + Жизнь' },
      { id: 'j2',   icon: '🛡', label: 'Кейн (Оружейник, ур.11) — ищет мага',     desc: 'Ветеран подземелий' },
      { id: 'j3',   icon: '⚗', label: 'Лейра (Алхимик, ур.9) — в составе группы', desc: '4/6 мест занято' },
      { id: 'back', icon: '←',  label: 'Назад', back: true },
    ],
  },
  lib: {
    title: 'Библиотека Башни',
    desc: 'Стеллажи уходят в темноту. Пахнет пылью и озоном. Здесь хранятся фрагменты заклятий из прошлых веков.',
    actions: [
      { id: 'browse', icon: '📖', label: 'Просмотреть фрагменты',  desc: '~2 игр. дня · Может дать новое заклинание' },
      { id: 'donate', icon: '↑',  label: 'Пожертвовать заклинание', desc: '+50 XP · Заклинание в публичную БД' },
      { id: 'back',   icon: '←',  label: 'Назад', back: true },
    ],
  },
  inn: {
    title: 'Постоялый двор',
    desc: 'Тихо потрескивает очаг. Пара торговцев шёпотом спорят о ценах.',
    actions: [
      { id: 'rest',   icon: '💤', label: 'Переночевать',        desc: 'Полное восстановление · 8 монет', effect: 'rest' },
      { id: 'gossip', icon: '👂', label: 'Услышать слухи',      desc: 'Бесплатно', effect: 'gossip' },
      { id: 'back',   icon: '←',  label: 'Назад', back: true },
    ],
  },
  black: {
    title: 'Чёрный рынок',
    desc: 'Покупатели и продавцы говорят вполголоса. Никаких квитанций. Никаких гарантий. Но и никаких налогов.',
    actions: [
      { id: 'browse', icon: '⚖', label: 'Просмотреть товары', desc: 'Риск мошенничества' },
      { id: 'sell',   icon: '↑',  label: 'Продать без налогов', desc: '+15% к цене' },
      { id: 'back',   icon: '←',  label: 'Покинуть', back: true },
    ],
  },
  guild: {
    title: 'Купеческая Гильдия',
    desc: 'Мраморные колонны, позолоченные таблички. Клерки перебирают пергаменты.',
    actions: [
      { id: 'orders', icon: '📋', label: 'Доска заказов',     desc: '5 активных контрактов' },
      { id: 'rep',    icon: '★',  label: 'Моя репутация',     desc: 'Неизвестен · 0 выполнено' },
      { id: 'back',   icon: '←',  label: 'Назад', back: true },
    ],
  },
};

const EFFECT_MESSAGES = {
  rest:       'Вы отдохнули. HP и усталость восстановлены.',
  gossip:     '«Говорят, на третьем уровне видели кое-что новое...»',
  cult_knock: 'Дверь медленно открывается. За ней — лестница вниз и запах воска.',
};

function LocationScreen({ locationId, onNav, onBack }) {
  const [sub, setSub] = React.useState(null);
  const [toast, setToast] = React.useState(null);

  const locData = LOCATION_DATA[locationId];
  if (!locData) return null;

  const ev = sub ? SUB_EVENTS[sub] : locData;

  const showToast = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3000);
  };

  const handleAction = (action) => {
    if (action.back)   { setSub(null); return; }
    if (action.nav)    { onNav(action.nav); return; }
    if (action.sub)    { setSub(action.sub); return; }
    if (action.effect) { showToast(EFFECT_MESSAGES[action.effect] || '...'); return; }
    showToast('Эта возможность появится позже.');
  };

  const dangerBanner = !locData.safe;

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader
        title={ev.title}
        onBack={sub ? () => setSub(null) : onBack}
      />

      {/* Ambience strip */}
      {!sub && (
        <div style={{
          marginTop: 56,
          padding: '5px 16px',
          background: dangerBanner ? 'rgba(160,30,10,0.18)' : 'rgba(50,130,50,0.12)',
          borderBottom: `1px solid ${dangerBanner ? 'rgba(200,60,40,0.3)' : 'rgba(60,180,60,0.2)'}`,
          fontSize: 10,
          color: dangerBanner ? '#c06050' : '#60a060',
          fontFamily: 'Cinzel, serif',
          letterSpacing: '0.06em',
        }}>
          {locData.ambience}
        </div>
      )}

      <div style={{ flex: 1, overflow: 'auto', padding: '14px 16px', paddingTop: sub ? 70 : 8, paddingBottom: 20 }}>
        {/* Description */}
        <div style={{
          background: 'linear-gradient(155deg, #2e2418, #1c1610)',
          border: '1px solid rgba(200,164,74,0.18)',
          borderRadius: 12,
          padding: '14px 16px',
          marginBottom: 14,
          fontSize: 13,
          lineHeight: 1.65,
          color: '#b8a880',
          fontStyle: 'italic',
        }}>
          {ev.desc}
        </div>

        {/* Actions */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {ev.actions.map(action => (
            <button
              key={action.id}
              onClick={() => handleAction(action)}
              style={{
                background: 'linear-gradient(100deg, rgba(42,32,20,0.85), rgba(28,22,14,0.85))',
                border: '1px solid rgba(200,164,74,0.18)',
                borderRadius: 11,
                padding: '11px 15px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 13,
                textAlign: 'left',
                transition: 'border-color 0.15s, background 0.15s',
              }}
              onMouseEnter={e => {
                e.currentTarget.style.borderColor = 'rgba(200,164,74,0.42)';
                e.currentTarget.style.background = 'linear-gradient(100deg, rgba(52,40,24,0.95), rgba(38,28,16,0.95))';
              }}
              onMouseLeave={e => {
                e.currentTarget.style.borderColor = 'rgba(200,164,74,0.18)';
                e.currentTarget.style.background = 'linear-gradient(100deg, rgba(42,32,20,0.85), rgba(28,22,14,0.85))';
              }}
            >
              <span style={{ fontSize: 21, width: 28, textAlign: 'center', flexShrink: 0 }}>{action.icon}</span>
              <div>
                <div style={{ fontFamily: 'Cinzel, serif', fontSize: 13, color: '#e8d5b0' }}>{action.label}</div>
                {action.desc && (
                  <div style={{ fontSize: 11, color: '#5a4a30', marginTop: 2 }}>{action.desc}</div>
                )}
              </div>
              <span style={{ marginLeft: 'auto', fontSize: 16, color: 'rgba(200,164,74,0.25)' }}>›</span>
            </button>
          ))}
        </div>
      </div>

      {/* Toast */}
      {toast && (
        <div style={{
          position: 'absolute',
          bottom: 24,
          left: 16, right: 16,
          background: 'rgba(13,10,7,0.96)',
          border: '1px solid rgba(200,164,74,0.4)',
          borderRadius: 10,
          padding: '11px 16px',
          fontSize: 13,
          color: '#c8a44a',
          textAlign: 'center',
          lineHeight: 1.4,
          zIndex: 100,
        }}>
          {toast}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { LocationScreen });


// ═══ js/SpellScreen.jsx ═══
// SpellScreen.jsx — spell creation with rotating circle

// ── Rotating Circle Component ────────────────────────────────────

function SpellCircle({ school, words, activeSlot, onSlotClick }) {
  const schoolData = SCHOOLS[school] || SCHOOLS.fire;
  const CX = 150, CY = 152, R = 104;
  const W = 300, H = 304;

  const slotMeta = SLOTS.map((slot, i) => {
    const deg = -90 + i * 60;
    const rad = deg * Math.PI / 180;
    return { ...slot, x: CX + R * Math.cos(rad), y: CY + R * Math.sin(rad) };
  });

  return (
    <div style={{ position: 'relative', width: W, height: H }}>
      <svg width={W} height={H} style={{ position: 'absolute', top: 0, left: 0, overflow: 'visible' }}>
        <defs>
          <filter id="glow">
            <feGaussianBlur stdDeviation="2.5" result="blur" />
            <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
          <radialGradient id="centerGrad" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor={schoolData.color} stopOpacity="0.18" />
            <stop offset="100%" stopColor={schoolData.color} stopOpacity="0" />
          </radialGradient>
        </defs>

        {/* Outer glow fill */}
        <circle cx={CX} cy={CY} r={R + 18} fill="url(#centerGrad)" />

        {/* Outer rotating ring */}
        <g style={{ transformOrigin: `${CX}px ${CY}px` }} className="ring-cw">
          <circle cx={CX} cy={CY} r={R + 18} fill="none"
            stroke={`${schoolData.color}28`} strokeWidth="1.2" />
          <circle cx={CX} cy={CY} r={R + 20} fill="none"
            stroke="rgba(200,164,74,0.12)" strokeWidth="0.6"
            strokeDasharray="3 4.5" />
          {[0,30,60,90,120,150,180,210,240,270,300,330].map(deg => {
            const a = deg * Math.PI / 180;
            return (
              <circle key={deg}
                cx={CX + (R+18) * Math.cos(a)}
                cy={CY + (R+18) * Math.sin(a)}
                r="0.9" fill={`${schoolData.color}55`} />
            );
          })}
        </g>

        {/* Main circle */}
        <circle cx={CX} cy={CY} r={R} fill="none"
          stroke={`${schoolData.color}35`} strokeWidth="1.5" />

        {/* Connector lines */}
        {slotMeta.map((s, i) => (
          <line key={i}
            x1={CX} y1={CY} x2={s.x} y2={s.y}
            stroke={words[i] ? `${schoolData.color}60` : 'rgba(200,164,74,0.09)'}
            strokeWidth={words[i] ? 1 : 0.5}
            strokeDasharray={words[i] ? 'none' : '2.5 3'}
          />
        ))}

        {/* Inner counter-rotating ring */}
        <g style={{ transformOrigin: `${CX}px ${CY}px` }} className="ring-ccw">
          <circle cx={CX} cy={CY} r="42" fill="none"
            stroke={`${schoolData.color}22`} strokeWidth="0.8"
            strokeDasharray="2 5" />
        </g>

        {/* Inner fill */}
        <circle cx={CX} cy={CY} r="36"
          fill={`${schoolData.color}12`}
          stroke={`${schoolData.color}35`} strokeWidth="1" />

        {/* School glyph */}
        <text x={CX} y={CY + 10} textAnchor="middle"
          fontSize="26" fill={schoolData.color}
          fontFamily="serif" filter="url(#glow)" opacity="0.92">
          {schoolData.glyph}
        </text>
        <text x={CX} y={CY + 25} textAnchor="middle"
          fontSize="7.5" fill={`${schoolData.color}80`}
          fontFamily="Cinzel, serif" letterSpacing="0.12em">
          {schoolData.ru.toUpperCase()}
        </text>

        {/* Filled-word arcs between slots */}
        {words.filter(Boolean).length > 1 && slotMeta.map((s, i) => {
          if (!words[i] || !words[(i+1)%6]) return null;
          const next = slotMeta[(i+1)%6];
          return (
            <line key={`arc-${i}`}
              x1={s.x} y1={s.y} x2={next.x} y2={next.y}
              stroke={`${schoolData.color}20`} strokeWidth="0.5" />
          );
        })}
      </svg>

      {/* Slot buttons — absolutely positioned */}
      {slotMeta.map((slot, i) => {
        const filled = !!words[i];
        const active = activeSlot === i;
        return (
          <div key={i}
            onClick={() => onSlotClick(i)}
            style={{
              position: 'absolute',
              left: slot.x - 28,
              top: slot.y - 23,
              width: 56,
              height: 46,
              background: active
                ? `${schoolData.color}2e`
                : filled ? `${schoolData.color}18` : 'rgba(22,18,12,0.92)',
              border: `1px solid ${active ? schoolData.color : filled ? `${schoolData.color}55` : 'rgba(200,164,74,0.18)'}`,
              borderRadius: 9,
              cursor: 'pointer',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 2,
              transition: 'all 0.2s',
              boxShadow: active ? `0 0 14px ${schoolData.color}40` : 'none',
            }}
          >
            <div style={{
              fontSize: 8,
              color: active ? schoolData.color : filled ? `${schoolData.color}aa` : 'rgba(200,164,74,0.38)',
              fontFamily: 'Cinzel, serif',
              letterSpacing: '0.04em',
              textTransform: 'uppercase',
            }}>
              {slot.ru}
            </div>
            {filled ? (
              <div style={{
                fontSize: 9.5,
                color: schoolData.color,
                fontStyle: 'italic',
                maxWidth: 52,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                textAlign: 'center',
              }}>
                {words[i]}
              </div>
            ) : (
              <div style={{ fontSize: 14, color: 'rgba(200,164,74,0.2)', lineHeight: 1 }}>+</div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Main Spell Screen ─────────────────────────────────────────────

function SpellScreen() {
  const [school, setSchool] = React.useState('fire');
  const [baseSpellId, setBaseSpellId] = React.useState('s1');
  const [words, setWords] = React.useState(['', '', '', '', '', '']);
  const [activeSlot, setActiveSlot] = React.useState(0);
  const [inputVal, setInputVal] = React.useState('');
  const [preview, setPreview] = React.useState(null);
  const [loading, setLoading] = React.useState(false);
  const [showGrimoire, setShowGrimoire] = React.useState(false);
  const inputRef = React.useRef(null);

  const schoolData = SCHOOLS[school];
  const filledCount = words.filter(Boolean).length;

  const handleSlotClick = (i) => {
    setActiveSlot(i);
    setInputVal(words[i] || '');
    setTimeout(() => inputRef.current?.focus(), 80);
  };

  const commitWord = () => {
    const val = inputVal.trim();
    if (!val) return;
    const next = [...words];
    next[activeSlot] = val;
    setWords(next);
    setInputVal('');
    // advance to next empty slot
    for (let i = activeSlot + 1; i < 6; i++) {
      if (!next[i]) { setActiveSlot(i); return; }
    }
  };

  const clearSlot = (i) => {
    const next = [...words];
    next[i] = '';
    setWords(next);
  };

  const handleCast = async () => {
    if (filledCount === 0) return;
    setLoading(true);
    setPreview(null);

    const base = MOCK_SPELLS.find(s => s.id === baseSpellId);
    const incantation = words.filter(Boolean).join(' ');
    const slotDesc = SLOTS.map((s, i) => words[i] ? `${s.ru}: ${words[i]}` : null).filter(Boolean).join(', ');

    const prompt = `Ты — оракул в тёмном фэнтези MMO. Игрок создаёт заклинание.
Школа: ${schoolData.ru}
Базовое: ${base?.nameRu || 'без основы'} (${base?.name || ''})
Инкантация: ${incantation}
Параметры: ${slotDesc}

Придумай заклинание на основе этих параметров. Ответь JSON:
{"nameRu":"Название на русском","nameLatin":"Название на латыни","effect":"Описание эффекта 2-3 предложения по-русски, в стиле тёмного фэнтези","fatigue":N,"cooldown":N}
Усталость 10-60, cooldown 0-3. Только JSON.`;

    try {
      const text = await window.claude.complete(prompt);
      const json = JSON.parse(text.match(/\{[\s\S]*?\}/)?.[0] || '{}');
      setPreview(json);
    } catch {
      setPreview({
        nameRu: `${schoolData.ru}: ${words[0] || 'Удар'}`,
        nameLatin: incantation,
        effect: 'Магическая энергия сгустилась и устремилась к цели, оставив след из мерцающих искр.',
        fatigue: 15 + filledCount * 5,
        cooldown: Math.floor(filledCount / 2),
      });
    }
    setLoading(false);
  };

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader
        title="Создание заклинания"
        subtitle={`${schoolData.ru} · ${filledCount}/6 слов`}
        right={
          <button onClick={() => setShowGrimoire(!showGrimoire)} style={{
            background: 'none', border: '1px solid rgba(200,164,74,0.3)', borderRadius: 6,
            color: '#c8a44a', fontSize: 10, fontFamily: 'Cinzel', padding: '3px 8px', cursor: 'pointer',
          }}>📖 Гримуар</button>
        }
      />

      <div style={{ flex: 1, overflow: 'auto', paddingTop: 56, paddingBottom: 20 }}>
        {/* School selector */}
        <div style={{ padding: '10px 14px 6px', display: 'flex', gap: 5, flexWrap: 'wrap' }}>
          {Object.entries(SCHOOLS).map(([key, s]) => (
            <button key={key} onClick={() => setSchool(key)} style={{
              background: school === key ? `${s.color}2a` : 'transparent',
              border: `1px solid ${school === key ? s.color : `${s.color}38`}`,
              borderRadius: 6, padding: '3px 8px', cursor: 'pointer',
              fontSize: 10.5, color: school === key ? s.color : `${s.color}70`,
              fontFamily: 'Cinzel', transition: 'all 0.18s',
            }}>
              {s.glyph} {s.ru}
            </button>
          ))}
        </div>

        {/* Base spell */}
        <div style={{ padding: '4px 14px 10px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ fontSize: 10, color: '#3a2a18', fontFamily: 'Cinzel', whiteSpace: 'nowrap' }}>ОСНОВА:</div>
          <select value={baseSpellId} onChange={e => setBaseSpellId(e.target.value)} style={{
            flex: 1, background: '#1c1610', border: '1px solid rgba(200,164,74,0.25)',
            borderRadius: 6, color: '#c8b890', padding: '5px 8px',
            fontSize: 12, fontFamily: 'Vollkorn, Georgia, serif', outline: 'none',
          }}>
            {MOCK_SPELLS.map(s => (
              <option key={s.id} value={s.id}>{s.nameRu}</option>
            ))}
          </select>
        </div>

        {/* The circle */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '0 0 4px' }}>
          <SpellCircle
            school={school}
            words={words}
            activeSlot={activeSlot}
            onSlotClick={handleSlotClick}
          />
        </div>

        {/* Input for active slot */}
        <div style={{ padding: '2px 16px 10px' }}>
          <div style={{ fontSize: 10, color: '#5a4a30', marginBottom: 5, fontFamily: 'Cinzel', letterSpacing: '0.04em', display: 'flex', justifyContent: 'space-between' }}>
            <span>{SLOTS[activeSlot].ru.toUpperCase()} — {SLOTS[activeSlot].hint}</span>
            {words[activeSlot] && (
              <button onClick={() => clearSlot(activeSlot)} style={{
                background: 'none', border: 'none', color: '#a05040', cursor: 'pointer', fontSize: 10, fontFamily: 'Cinzel',
              }}>очистить</button>
            )}
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <input
              ref={inputRef}
              value={inputVal}
              onChange={e => setInputVal(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && commitWord()}
              placeholder={`${SLOTS[activeSlot].id}...`}
              style={{
                flex: 1,
                background: 'rgba(22,18,12,0.95)',
                border: `1px solid ${schoolData.color}44`,
                borderRadius: 8,
                padding: '8px 12px',
                color: '#e8d5b0',
                fontSize: 14,
                fontStyle: 'italic',
                outline: 'none',
              }}
            />
            <GoldButton onClick={commitWord}>→</GoldButton>
          </div>
        </div>

        {/* Cast */}
        <div style={{ padding: '0 16px 14px', textAlign: 'center' }}>
          <GoldButton
            onClick={handleCast}
            disabled={filledCount === 0 || loading}
            style={{ padding: '9px 44px', fontSize: 13 }}
          >
            {loading ? 'Оракул отвечает...' : 'Сотворить заклинание'}
          </GoldButton>
        </div>

        {/* Preview */}
        {preview && (
          <div style={{ margin: '0 16px 20px' }}>
            <Panel style={{ padding: '14px 16px', borderColor: `${schoolData.color}44` }}>
              <div style={{ fontFamily: 'Cinzel', fontSize: 15, color: schoolData.color, marginBottom: 2 }}>
                {preview.nameRu}
              </div>
              <div style={{ fontSize: 11, color: '#4a3a28', fontStyle: 'italic', marginBottom: 10 }}>
                {preview.nameLatin}
              </div>
              <div style={{ fontSize: 13, color: '#c8b890', lineHeight: 1.65, marginBottom: 12 }}>
                {preview.effect}
              </div>
              <div style={{ display: 'flex', gap: 16, marginBottom: 12 }}>
                <div style={{ fontSize: 11, color: '#6a5840' }}>
                  <span style={{ color: '#4a3a28', fontFamily: 'Cinzel' }}>УСТАЛОСТЬ</span><br />{preview.fatigue}
                </div>
                <div style={{ fontSize: 11, color: '#6a5840' }}>
                  <span style={{ color: '#4a3a28', fontFamily: 'Cinzel' }}>ОТКАТ</span><br />{preview.cooldown} ход.
                </div>
              </div>
              <div style={{ display: 'flex', gap: 8 }}>
                <GoldButton small onClick={() => { setWords(['','','','','','']); setPreview(null); setActiveSlot(0); }} style={{ flex: 1 }}>
                  Новое
                </GoldButton>
                <GoldButton small style={{ flex: 2 }}>
                  Сохранить в библиотеку ✦
                </GoldButton>
              </div>
            </Panel>
          </div>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { SpellScreen });


// ═══ js/GrimoireScreen.jsx ═══
// GrimoireScreen.jsx — shelves + spell loadout

function BookSpine({ grimoire, selected, onClick }) {
  const [hover, setHover] = React.useState(false);
  const lifted = selected || hover;
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        flex: 1,
        height: lifted ? 78 : 68,
        cursor: 'pointer',
        transition: 'height 0.18s ease, box-shadow 0.18s',
        position: 'relative',
        alignSelf: 'flex-end',
      }}
    >
      {/* Book body */}
      <div style={{
        position: 'absolute',
        inset: 0,
        background: `linear-gradient(90deg, ${grimoire.color}cc 0%, ${grimoire.color}ff 30%, ${grimoire.color}ee 70%, ${grimoire.color}aa 100%)`,
        borderRadius: '2px 2px 0 0',
        border: `1px solid ${selected ? '#e8c46a' : grimoire.color + 'cc'}`,
        borderBottom: 'none',
        boxShadow: selected
          ? `0 -6px 18px ${grimoire.color}70, inset 1px 0 0 rgba(255,255,255,0.12)`
          : `2px -2px 8px rgba(0,0,0,0.5), inset 1px 0 0 rgba(255,255,255,0.08)`,
        overflow: 'hidden',
      }}>
        {/* Spine lines */}
        <div style={{ position: 'absolute', top: 8, left: 3, right: 3, height: 1, background: 'rgba(255,255,255,0.18)' }} />
        <div style={{ position: 'absolute', top: 12, left: 3, right: 3, height: 1, background: 'rgba(255,255,255,0.09)' }} />
        <div style={{ position: 'absolute', bottom: 10, left: 3, right: 3, height: 1, background: 'rgba(255,255,255,0.13)' }} />

        {/* Title — vertical */}
        <div style={{
          position: 'absolute',
          inset: '16px 0 14px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          overflow: 'hidden',
        }}>
          <div style={{
            writingMode: 'vertical-rl',
            textOrientation: 'mixed',
            transform: 'rotate(180deg)',
            fontSize: 8.5,
            color: 'rgba(255,255,255,0.82)',
            fontFamily: 'Cinzel, serif',
            letterSpacing: '0.05em',
            maxHeight: 44,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}>
            {grimoire.name}
          </div>
        </div>

        {/* Capacity pip at bottom */}
        <div style={{
          position: 'absolute',
          bottom: 4,
          left: '50%',
          transform: 'translateX(-50%)',
          fontSize: 7.5,
          color: 'rgba(255,255,255,0.6)',
          fontFamily: 'Cinzel',
        }}>
          {grimoire.spells.length}/{grimoire.capacity}
        </div>
      </div>
    </div>
  );
}

function Shelf({ books, allGrimoires, selectedId, onSelect }) {
  return (
    <div style={{ marginBottom: 5 }}>
      <div style={{
        display: 'flex',
        alignItems: 'flex-end',
        gap: 5,
        padding: '6px 10px 0',
        minHeight: 84,
      }}>
        {books.map(g => (
          <BookSpine
            key={g.id}
            grimoire={g}
            selected={selectedId === g.id}
            onClick={() => onSelect(g.id)}
          />
        ))}
        {/* Empty slots */}
        {Array.from({ length: Math.max(0, 4 - books.length) }).map((_, i) => (
          <div key={`empty-${i}`} style={{ flex: 1, height: 42, alignSelf: 'flex-end' }} />
        ))}
      </div>
      {/* Shelf board */}
      <div style={{
        height: 11,
        background: 'linear-gradient(180deg, #6a4020 0%, #3e2210 60%, #2a1608 100%)',
        borderTop: '1px solid #8a5828',
        borderRadius: '1px 1px 3px 3px',
        boxShadow: '0 5px 12px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06)',
        marginLeft: 4,
        marginRight: 4,
      }} />
    </div>
  );
}

// Index-card layout for many grimoires
function CardLayout({ grimoires, selectedId, onSelect }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 7, padding: '0 16px' }}>
      {grimoires.map(g => (
        <button key={g.id} onClick={() => onSelect(g.id)} style={{
          background: selectedId === g.id ? `${g.color}28` : 'rgba(28,22,14,0.8)',
          border: `1px solid ${selectedId === g.id ? g.color : g.color + '40'}`,
          borderRadius: 9, padding: '10px 13px', cursor: 'pointer', textAlign: 'left',
          display: 'flex', alignItems: 'center', gap: 12, transition: 'all 0.15s',
        }}>
          <div style={{
            width: 28, height: 38, background: g.color,
            borderRadius: 2, flexShrink: 0,
            boxShadow: `0 2px 8px ${g.color}60`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 14,
          }}>📖</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#e8d5b0' }}>{g.name}</div>
            <div style={{ fontSize: 10, color: '#5a4a30', marginTop: 2 }}>{g.spells.length}/{g.capacity} заклинаний</div>
          </div>
          {selectedId === g.id && <span style={{ color: '#c8a44a', fontSize: 14 }}>›</span>}
        </button>
      ))}
    </div>
  );
}

function GrimoireScreen({ layout = 'shelves' }) {
  const [grimoires, setGrimoires] = React.useState(MOCK_GRIMOIRES);
  const [selectedId, setSelectedId] = React.useState('g1');
  const [spellLib] = React.useState(MOCK_SPELLS);

  const grim = grimoires.find(g => g.id === selectedId);
  const grimoireSpells = grim ? spellLib.filter(s => grim.spells.includes(s.id)) : [];
  const librarySpells = spellLib.filter(s => !grim?.spells.includes(s.id));
  const isFull = grim && grim.spells.length >= grim.capacity;

  const addSpell = (spellId) => {
    if (!grim || isFull || grim.spells.includes(spellId)) return;
    setGrimoires(gs => gs.map(g => g.id === grim.id ? { ...g, spells: [...g.spells, spellId] } : g));
  };

  const removeSpell = (spellId) => {
    setGrimoires(gs => gs.map(g => g.id === grim.id ? { ...g, spells: g.spells.filter(id => id !== spellId) } : g));
  };

  const useCards = grimoires.length > 6 || layout === 'cards';

  // Chunk grimoires into shelves of 4
  const shelves = [];
  const perShelf = 4;
  for (let i = 0; i < grimoires.length; i += perShelf) {
    shelves.push(grimoires.slice(i, i + perShelf));
  }

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader
        title="Гримуары"
        subtitle={grim ? `${grim.name} · ${grim.spells.length}/${grim.capacity}` : ''}
      />

      <div style={{ flex: 1, overflow: 'auto', paddingTop: 56, paddingBottom: 20 }}>
        {/* Shelves or cards */}
        <div style={{
          padding: useCards ? '12px 0 4px' : '14px 12px 4px',
          background: useCards ? 'transparent' : 'linear-gradient(180deg, #1a1208 0%, #100e08 100%)',
          borderBottom: '1px solid rgba(200,164,74,0.08)',
        }}>
          {useCards ? (
            <CardLayout grimoires={grimoires} selectedId={selectedId} onSelect={setSelectedId} />
          ) : (
            shelves.map((row, i) => (
              <Shelf key={i} books={row} allGrimoires={grimoires} selectedId={selectedId} onSelect={setSelectedId} />
            ))
          )}
        </div>

        {/* Detail panel */}
        {grim && (
          <div style={{ padding: '14px 16px' }}>
            {/* Capacity bar */}
            <div style={{ marginBottom: 14 }}>
              <HPBar
                value={grim.spells.length}
                max={grim.capacity}
                color={grim.color}
                label="Заполненность"
              />
              {isFull && (
                <div style={{ fontSize: 10, color: '#a06030', marginTop: 5, fontFamily: 'Cinzel' }}>
                  ГРИМУАР ЗАПОЛНЕН — нужен новый
                </div>
              )}
            </div>

            {/* Spells in grimoire */}
            {grimoireSpells.length > 0 && (
              <>
                <div style={{ fontSize: 10, color: '#3a2a18', fontFamily: 'Cinzel', letterSpacing: '0.06em', marginBottom: 7 }}>
                  СОДЕРЖИМОЕ
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginBottom: 16 }}>
                  {grimoireSpells.map(spell => {
                    const sc = SCHOOLS[spell.school];
                    return (
                      <div key={spell.id} style={{
                        background: `${sc?.color}14`,
                        border: `1px solid ${sc?.color}38`,
                        borderRadius: 9, padding: '8px 12px',
                        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                      }}>
                        <div>
                          <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#e8d5b0' }}>{spell.nameRu}</div>
                          <div style={{ display: 'flex', gap: 6, marginTop: 3, alignItems: 'center' }}>
                            <SchoolTag school={spell.school} small />
                            <span style={{ fontSize: 10, color: '#3a2a18', fontStyle: 'italic' }}>{spell.name}</span>
                          </div>
                        </div>
                        <button onClick={() => removeSpell(spell.id)} style={{
                          background: 'none',
                          border: '1px solid rgba(200,60,40,0.35)',
                          borderRadius: 5, color: '#a05040', fontSize: 11,
                          cursor: 'pointer', padding: '3px 7px',
                          fontFamily: 'Cinzel',
                        }}>✕</button>
                      </div>
                    );
                  })}
                </div>
              </>
            )}
            {grimoireSpells.length === 0 && (
              <div style={{ fontSize: 12, color: '#2a1a10', textAlign: 'center', padding: '16px 0 20px', fontStyle: 'italic' }}>
                Гримуар пуст
              </div>
            )}

            {/* Library */}
            {librarySpells.length > 0 && (
              <>
                <div style={{ fontSize: 10, color: '#3a2a18', fontFamily: 'Cinzel', letterSpacing: '0.06em', marginBottom: 7 }}>
                  БИБЛИОТЕКА — нажмите чтобы добавить
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {librarySpells.map(spell => {
                    const sc = SCHOOLS[spell.school];
                    return (
                      <button key={spell.id}
                        onClick={() => addSpell(spell.id)}
                        disabled={isFull}
                        style={{
                          background: 'rgba(22,18,12,0.6)',
                          border: '1px solid rgba(200,164,74,0.13)',
                          borderRadius: 9, padding: '8px 12px',
                          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                          cursor: isFull ? 'not-allowed' : 'pointer',
                          opacity: isFull ? 0.38 : 1,
                          textAlign: 'left',
                          transition: 'border-color 0.15s',
                        }}
                        onMouseEnter={e => { if (!isFull) e.currentTarget.style.borderColor = 'rgba(200,164,74,0.35)'; }}
                        onMouseLeave={e => { e.currentTarget.style.borderColor = 'rgba(200,164,74,0.13)'; }}
                      >
                        <div>
                          <div style={{ fontFamily: 'Cinzel', fontSize: 12.5, color: '#b8a878' }}>{spell.nameRu}</div>
                          <SchoolTag school={spell.school} small />
                        </div>
                        <span style={{ fontSize: 18, color: 'rgba(200,164,74,0.25)', marginLeft: 8 }}>+</span>
                      </button>
                    );
                  })}
                </div>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

Object.assign(window, { GrimoireScreen });


// ═══ js/CombatScreen.jsx ═══
// CombatScreen.jsx — battle screen, caster POV

const STATE_META = {
  burning:      { ru: 'Горит',        color: '#e05030' },
  frozen:       { ru: 'Заморожен',    color: '#60c0e0' },
  shielded:     { ru: 'Щит',          color: '#90a8c0' },
  trapped:      { ru: 'Захвачен',     color: '#9030b0' },
  blinded:      { ru: 'Ослеплён',     color: '#a09020' },
  silenced:     { ru: 'Немой',        color: '#604080' },
  empowered:    { ru: 'Усилен',       color: '#c8a44a' },
  staggered:    { ru: 'Оглушён',      color: '#806040' },
  regenerating: { ru: 'Регенер.',     color: '#40a060' },
  exposed:      { ru: 'Открыт',       color: '#e08040' },
  channeling:   { ru: 'Канал.',       color: '#4080c0' },
};

const INIT_BATTLE = {
  enemy: { name: 'Теневой Стражник', level: 14, hp: 110, maxHp: 110, school: 'death', states: ['shielded', 'empowered'] },
  party: { hp: 74, maxHp: 90 },
  turn: 1,
  log: [
    { turn: 0, text: 'Теневой Стражник материализовался из темноты. Его форма нестабильна — края размыты, словно он не до конца существует в этом мире.', type: 'narrative' },
    { turn: 1, text: 'Ход 1. Выберите базовое заклинание и произнесите инкантацию.', type: 'system' },
  ],
};

const ACTIVE_GRIMOIRE = MOCK_GRIMOIRES[1]; // chaos grimoire

function StatePill({ stateId }) {
  const meta = STATE_META[stateId];
  if (!meta) return null;
  return (
    <span style={{
      padding: '2px 7px', borderRadius: 5,
      background: `${meta.color}1e`, border: `1px solid ${meta.color}50`,
      color: meta.color, fontSize: 9.5, fontFamily: 'Cinzel',
    }}>{meta.ru}</span>
  );
}

function CombatScreen() {
  const [battle, setBattle] = React.useState(INIT_BATTLE);
  const [selectedBase, setSelectedBase] = React.useState('s3');
  const [incantation, setIncantation] = React.useState('');
  const [phase, setPhase] = React.useState('input'); // input | resolving | resolved
  const logRef = React.useRef(null);
  const inputRef = React.useRef(null);

  const grimoireSpells = MOCK_SPELLS.filter(s => ACTIVE_GRIMOIRE.spells.includes(s.id));

  React.useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight;
    }
  }, [battle.log]);

  const pushLog = (entries) => {
    setBattle(b => ({ ...b, log: [...b.log, ...entries] }));
  };

  const handleDeclare = async () => {
    const trimmed = incantation.trim();
    if (!trimmed || phase !== 'input') return;
    setPhase('resolving');

    const base = MOCK_SPELLS.find(s => s.id === selectedBase);
    const school = SCHOOLS[MOCK_PLAYER.schools[0]];
    const enemy = battle.enemy;

    const prompt = `Ты — боевой оракул в тёмном фэнтези MMO MMGO. Разреши ход.
Заклинание игрока: «${trimmed}»
Базовое: ${base?.nameRu} (${base?.name})
Школа: ${school.ru}
Враг: ${enemy.name}, HP: ${enemy.hp}/${enemy.maxHp}
Состояния врага: ${enemy.states.join(', ') || 'нет'}
HP отряда: ${battle.party.hp}/${battle.party.maxHp}

Опиши результат хода (3–4 предложения, по-русски, атмосферно и конкретно).
Укажи: что произошло, ущерб/эффект, изменение состояния врага.
Ответь только JSON: {"narrative":"...","damage":N,"newState":"STATE_ID или null","consumed":"shielded или null","enemyHpLeft":N}
Возможные состояния: ${Object.keys(STATE_META).join(', ')}. Только JSON.`;

    let result;
    try {
      const text = await window.claude.complete(prompt);
      result = JSON.parse(text.match(/\{[\s\S]*?\}/)?.[0] || '{}');
    } catch {
      const dmg = 12 + Math.floor(Math.random() * 15);
      result = {
        narrative: `Инкантация «${trimmed}» сорвалась с губ. Вспышка ${school.ru.toLowerCase()} энергии устремилась к ${enemy.name}. Удар пробил щит, нанеся ${dmg} урона. Противник качнулся, но устоял.`,
        damage: dmg,
        newState: null,
        consumed: enemy.states.includes('shielded') ? 'shielded' : null,
        enemyHpLeft: Math.max(0, enemy.hp - dmg),
      };
    }

    let newStates = [...enemy.states];
    if (result.consumed) newStates = newStates.filter(s => s !== result.consumed);
    if (result.newState && result.newState !== 'null' && result.newState !== null) {
      if (!newStates.includes(result.newState)) newStates.push(result.newState);
    }

    const newEnemyHp = result.enemyHpLeft ?? Math.max(0, enemy.hp - (result.damage || 10));

    const newLog = [
      { turn: battle.turn, text: `⚡ «${trimmed}»`, type: 'player_action' },
      { turn: battle.turn, text: result.narrative, type: 'player' },
    ];

    setBattle(b => ({
      ...b,
      enemy: { ...b.enemy, hp: newEnemyHp, states: newStates },
      log: [...b.log, ...newLog],
    }));

    if (newEnemyHp <= 0) {
      setBattle(b => ({
        ...b,
        log: [...b.log, ...newLog, { turn: b.turn, text: '✦ Враг повержен. Победа.', type: 'system' }],
      }));
      setPhase('resolved');
      return;
    }

    setPhase('resolved');
  };

  const continueRound = () => {
    const dmg = 7 + Math.floor(Math.random() * 14);
    const enemyLines = [
      `${battle.enemy.name} нанёс ответный удар тьмой. Холод пробрал насквозь — отряд теряет ${dmg} HP.`,
      `Тёмный клинок мелькнул быстрее, чем глаз успел проследить. Минус ${dmg} HP. Воздух стал гуще.`,
      `Стражник накопил силу и выпустил тёмный импульс. Отряд отброшен, ${dmg} HP потеряно.`,
    ];
    const line = enemyLines[Math.floor(Math.random() * enemyLines.length)];

    setBattle(b => ({
      ...b,
      party: { ...b.party, hp: Math.max(0, b.party.hp - dmg) },
      turn: b.turn + 1,
      log: [
        ...b.log,
        { turn: b.turn, text: line, type: 'enemy' },
        { turn: b.turn + 1, text: `Ход ${b.turn + 1}.`, type: 'system' },
      ],
    }));
    setIncantation('');
    setPhase('input');
    setTimeout(() => inputRef.current?.focus(), 80);
  };

  const LOG_COLORS = {
    narrative:     '#7a6a4a',
    player:        '#c8a44a',
    player_action: '#6a8850',
    enemy:         '#a05040',
    system:        '#3a5070',
  };

  const partyHpPct = battle.party.hp / battle.party.maxHp;
  const partyHpColor = partyHpPct > 0.5 ? '#60a060' : partyHpPct > 0.25 ? '#c8a44a' : '#e04030';
  const enemyHpPct = battle.enemy.hp / battle.enemy.maxHp;
  const enemyColor = SCHOOLS[battle.enemy.school]?.color || '#c8a44a';

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader
        title={`Бой · Ход ${battle.turn}`}
        subtitle="Подземелье, Уровень 2"
      />

      <div style={{ paddingTop: 56, flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>

        {/* Enemy panel */}
        <div style={{
          padding: '10px 16px 12px',
          background: 'linear-gradient(180deg, rgba(40,10,5,0.6) 0%, transparent 100%)',
          borderBottom: '1px solid rgba(200,164,74,0.1)',
          flexShrink: 0,
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
            <div>
              <div style={{ fontFamily: 'Cinzel', fontSize: 15, color: '#e8d5b0' }}>{battle.enemy.name}</div>
              <div style={{ fontSize: 10, color: '#5a4a30', marginTop: 1 }}>
                Ур. {battle.enemy.level} · {SCHOOLS[battle.enemy.school]?.ru}
              </div>
            </div>
            <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', justifyContent: 'flex-end', maxWidth: 160 }}>
              {battle.enemy.states.map(s => <StatePill key={s} stateId={s} />)}
            </div>
          </div>
          <HPBar value={battle.enemy.hp} max={battle.enemy.maxHp} color={enemyColor} label="HP противника" />
        </div>

        {/* Battle log */}
        <div ref={logRef} style={{ flex: 1, overflow: 'auto', padding: '10px 16px', display: 'flex', flexDirection: 'column', gap: 7 }}>
          {battle.log.map((entry, i) => (
            <div key={i} style={{
              fontSize: entry.type === 'player_action' ? 12 : 13,
              lineHeight: 1.6,
              color: LOG_COLORS[entry.type] || '#7a6a4a',
              fontStyle: entry.type === 'narrative' ? 'italic' : 'normal',
              paddingLeft: entry.type === 'player_action' ? 0 : 0,
              borderLeft: entry.type === 'player' ? '2px solid rgba(200,164,74,0.25)' :
                          entry.type === 'enemy' ? '2px solid rgba(180,60,40,0.3)' : 'none',
              paddingLeft: (entry.type === 'player' || entry.type === 'enemy') ? 8 : 0,
            }}>
              {entry.text}
            </div>
          ))}
          {phase === 'resolving' && (
            <div style={{ fontSize: 12, color: '#4a6080', fontStyle: 'italic' }}>
              Магия формируется...
            </div>
          )}
        </div>

        {/* Party HP */}
        <div style={{ padding: '8px 16px', borderTop: '1px solid rgba(200,164,74,0.08)', flexShrink: 0 }}>
          <HPBar value={battle.party.hp} max={battle.party.maxHp} color={partyHpColor} label="HP отряда" />
        </div>

        {/* Action area */}
        <div style={{ padding: '8px 14px 14px', borderTop: '1px solid rgba(200,164,74,0.08)', flexShrink: 0 }}>
          {/* Grimoire scroll */}
          <div style={{ display: 'flex', gap: 5, marginBottom: 8, overflowX: 'auto', paddingBottom: 2 }}>
            {grimoireSpells.map(spell => {
              const sc = SCHOOLS[spell.school];
              const active = selectedBase === spell.id;
              return (
                <button key={spell.id} onClick={() => setSelectedBase(spell.id)} style={{
                  background: active ? `${sc?.color}2a` : 'rgba(22,18,12,0.8)',
                  border: `1px solid ${active ? sc?.color : 'rgba(200,164,74,0.15)'}`,
                  borderRadius: 7, padding: '5px 9px', cursor: 'pointer',
                  whiteSpace: 'nowrap', flexShrink: 0,
                  transition: 'all 0.15s',
                }}>
                  <div style={{ fontSize: 10, fontFamily: 'Cinzel', color: active ? sc?.color : '#5a4a30' }}>
                    {spell.nameRu}
                  </div>
                </button>
              );
            })}
          </div>

          {phase === 'input' && (
            <div style={{ display: 'flex', gap: 8 }}>
              <input
                ref={inputRef}
                value={incantation}
                onChange={e => setIncantation(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleDeclare()}
                placeholder="Ictus ignis magnus..."
                style={{
                  flex: 1, background: 'rgba(22,18,12,0.95)',
                  border: '1px solid rgba(200,164,74,0.28)', borderRadius: 8,
                  padding: '8px 12px', color: '#e8d5b0',
                  fontSize: 14, fontStyle: 'italic', outline: 'none',
                }}
              />
              <GoldButton onClick={handleDeclare}>Бросить</GoldButton>
            </div>
          )}

          {phase === 'resolving' && (
            <div style={{ textAlign: 'center', padding: '10px 0', color: '#4a6080', fontFamily: 'Cinzel', fontSize: 12 }}>
              ⟳ Оракул разрешает...
            </div>
          )}

          {phase === 'resolved' && battle.enemy.hp > 0 && (
            <div style={{ display: 'flex', justifyContent: 'center' }}>
              <GoldButton onClick={continueRound}>Следующий ход →</GoldButton>
            </div>
          )}
          {phase === 'resolved' && battle.enemy.hp <= 0 && (
            <div style={{ textAlign: 'center', padding: '8px 0' }}>
              <div style={{ fontFamily: 'Cinzel', color: '#c8a44a', fontSize: 14, marginBottom: 8 }}>Победа</div>
              <GoldButton onClick={() => { setBattle(INIT_BATTLE); setPhase('input'); setIncantation(''); }}>
                Новый бой
              </GoldButton>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { CombatScreen });


// ═══ js/BaseScreen.jsx ═══
// BaseScreen.jsx — inventory, stats, storage, workshop

const INVENTORY_ITEMS = [
  { id: 'i1', ru: 'Руна огня',          icon: '🜂', school: 'fire',  count: 3,  weight: 0.1, type: 'material' },
  { id: 'i2', ru: 'Зелье восстановл.',  icon: '⚗',  color: '#a060e0', count: 2, weight: 0.3, type: 'potion' },
  { id: 'i3', ru: 'Осколок кристалла', icon: '◆',  color: '#60c0e0', count: 7,  weight: 0.2, type: 'material' },
  { id: 'i4', ru: 'Провиант',           icon: '🌾', color: '#c0a040', count: 12, weight: 0.5, type: 'food' },
  { id: 'i5', ru: 'Малый Красный',      icon: '📖', color: '#b03820', count: 1,  weight: 1.2, type: 'grimoire' },
  { id: 'i6', ru: 'Огненная соль',      icon: '🜂', school: 'fire',  count: 4,  weight: 0.1, type: 'ingredient' },
  { id: 'i7', ru: 'Прах Хаоса',         icon: '⊗',  school: 'chaos', count: 2,  weight: 0.2, type: 'ingredient' },
];

function InventoryGrid({ items }) {
  const [selected, setSelected] = React.useState(null);
  const totalWeight = items.reduce((s, i) => s + i.weight * i.count, 0);
  const maxWeight = 30;
  const sel = selected ? items.find(i => i.id === selected) : null;

  return (
    <div>
      {/* Weight bar */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
        <div style={{ fontSize: 10, color: '#4a3a28', fontFamily: 'Cinzel' }}>
          НАГРУЗКА: {totalWeight.toFixed(1)} / {maxWeight} кг
        </div>
        <div style={{ width: 90, height: 4, background: 'rgba(255,255,255,0.07)', borderRadius: 2, overflow: 'hidden' }}>
          <div style={{
            height: '100%',
            width: `${Math.min(100, (totalWeight / maxWeight) * 100)}%`,
            background: totalWeight > maxWeight * 0.8 ? '#e04030' : '#c8a44a',
            borderRadius: 2, transition: 'width 0.4s',
          }} />
        </div>
      </div>

      {/* Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 7, marginBottom: 14 }}>
        {items.map(item => {
          const sc = item.school ? SCHOOLS[item.school] : null;
          const isSel = selected === item.id;
          return (
            <div key={item.id}
              onClick={() => setSelected(s => s === item.id ? null : item.id)}
              style={{
                background: isSel
                  ? 'linear-gradient(155deg, #3a2c1c, #262010)'
                  : 'linear-gradient(155deg, #2a2018, #1c1610)',
                border: `1px solid ${isSel ? 'rgba(200,164,74,0.5)' : 'rgba(200,164,74,0.17)'}`,
                borderRadius: 10,
                padding: '10px 6px 7px',
                textAlign: 'center',
                cursor: 'pointer',
                position: 'relative',
                transition: 'all 0.15s',
              }}
            >
              <div style={{ fontSize: 22, marginBottom: 4, color: sc ? sc.color : item.color || '#c8b890' }}>
                {item.icon}
              </div>
              <div style={{ fontSize: 9, color: '#b8a878', fontFamily: 'Cinzel', lineHeight: 1.3, minHeight: 22 }}>
                {item.ru}
              </div>
              <div style={{
                position: 'absolute', top: 4, right: 5,
                background: 'rgba(200,164,74,0.18)', borderRadius: '50%',
                width: 17, height: 17,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 9.5, color: '#c8a44a', fontFamily: 'Cinzel',
              }}>{item.count}</div>
            </div>
          );
        })}
        {/* Empty slots */}
        {Array.from({ length: Math.max(0, 12 - items.length) }).map((_, i) => (
          <div key={`e${i}`} style={{
            background: 'rgba(18,14,10,0.4)',
            border: '1px dashed rgba(200,164,74,0.08)',
            borderRadius: 10, height: 72,
          }} />
        ))}
      </div>

      {/* Item detail */}
      {sel && (
        <Panel style={{ padding: '11px 13px', marginBottom: 4 }}>
          <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#e8d5b0', marginBottom: 4 }}>{sel.ru}</div>
          <div style={{ display: 'flex', gap: 14 }}>
            <div style={{ fontSize: 11, color: '#5a4a30' }}>Вес: {sel.weight} кг/шт</div>
            <div style={{ fontSize: 11, color: '#5a4a30' }}>Тип: {sel.type}</div>
          </div>
          {sel.school && <div style={{ marginTop: 6 }}><SchoolTag school={sel.school} small /></div>}
        </Panel>
      )}
    </div>
  );
}

function StorageShelf() {
  const rows = [
    [{ label: 'Руны ×3', color: '#e05030' }, { label: 'Зелья ×4', color: '#a060e0' }, null, null],
    [null, null, null, null],
    [null, null, null, null],
  ];
  return (
    <div>
      <div style={{ fontSize: 11, color: '#4a3a28', fontFamily: 'Cinzel', marginBottom: 12 }}>
        Хранилище защищено. Можно хранить до 200 кг.
      </div>
      {rows.map((row, ri) => (
        <div key={ri} style={{ marginBottom: 5 }}>
          <div style={{
            display: 'flex', gap: 6, padding: '6px 8px 0',
            background: 'rgba(22,16,8,0.5)', borderRadius: '4px 4px 0 0',
            minHeight: 56,
          }}>
            {row.map((cell, ci) => (
              <div key={ci} style={{
                flex: 1, height: 44,
                background: cell ? 'rgba(42,30,18,0.8)' : 'rgba(28,20,12,0.3)',
                border: cell ? '1px solid rgba(200,164,74,0.2)' : '1px dashed rgba(200,164,74,0.08)',
                borderRadius: 5,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                {cell && (
                  <div style={{ fontSize: 11, color: cell.color || '#6a5840', fontFamily: 'Cinzel', textAlign: 'center' }}>
                    {cell.label}
                  </div>
                )}
              </div>
            ))}
          </div>
          <div style={{ height: 9, background: 'linear-gradient(180deg,#6a4020,#3e2010)', borderRadius: '0 0 2px 2px', boxShadow: '0 4px 10px rgba(0,0,0,0.5)' }} />
        </div>
      ))}
    </div>
  );
}

function BaseScreen() {
  const [tab, setTab] = React.useState('inventory');

  const tabs = [
    { id: 'inventory', label: 'Инвентарь' },
    { id: 'stats',     label: 'Статус' },
    { id: 'storage',   label: 'Хранилище' },
    { id: 'craft',     label: 'Мастерская' },
  ];

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader title="База" subtitle={`${MOCK_PLAYER.name} · Ур. ${MOCK_PLAYER.level}`} />

      <div style={{ paddingTop: 56, flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {/* Tabs */}
        <div style={{ display: 'flex', borderBottom: '1px solid rgba(200,164,74,0.12)', paddingLeft: 8, paddingRight: 8, flexShrink: 0 }}>
          {tabs.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, background: 'none', border: 'none',
              borderBottom: tab === t.id ? '2px solid #c8a44a' : '2px solid transparent',
              padding: '9px 2px', cursor: 'pointer',
              fontSize: 10.5, fontFamily: 'Cinzel',
              color: tab === t.id ? '#c8a44a' : '#3a2a18',
              transition: 'color 0.15s', letterSpacing: '0.03em',
            }}>{t.label}</button>
          ))}
        </div>

        <div style={{ flex: 1, overflow: 'auto', padding: '14px 16px', paddingBottom: 20 }}>
          {tab === 'inventory' && <InventoryGrid items={INVENTORY_ITEMS} />}

          {tab === 'stats' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
              {/* Avatar row */}
              <div style={{ textAlign: 'center', paddingBottom: 4 }}>
                <div style={{
                  width: 64, height: 64, borderRadius: '50%', margin: '0 auto 10px',
                  background: 'linear-gradient(135deg, #e05030 0%, #9030b0 100%)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 28, border: '2px solid rgba(200,164,74,0.3)',
                  boxShadow: '0 0 20px rgba(200,164,74,0.15)',
                }}>✦</div>
                <div style={{ fontFamily: 'Cinzel', fontSize: 18, color: '#e8d5b0' }}>{MOCK_PLAYER.name}</div>
                <div style={{ fontSize: 11, color: '#5a4a30', marginTop: 3 }}>Маг · Уровень {MOCK_PLAYER.level}</div>
                <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginTop: 8 }}>
                  {MOCK_PLAYER.schools.map(s => <SchoolTag key={s} school={s} />)}
                </div>
              </div>

              <Panel style={{ padding: 14 }}>
                <HPBar value={MOCK_PLAYER.hp} max={MOCK_PLAYER.maxHp} color="#60a060" label="Здоровье" />
                <div style={{ marginTop: 12 }}>
                  <HPBar value={MOCK_PLAYER.fatigue} max={MOCK_PLAYER.maxFatigue} color="#c8a44a" label="Усталость" />
                </div>
                <div style={{ marginTop: 12 }}>
                  <HPBar value={MOCK_PLAYER.xp - 14000} max={MOCK_PLAYER.xpNext - 14000} color="#4080c0" label="Опыт" />
                </div>
              </Panel>

              <Panel style={{ padding: 14 }}>
                <div style={{ display: 'flex', justifyContent: 'space-around' }}>
                  {[
                    { label: 'Монет', value: MOCK_PLAYER.gold },
                    { label: 'Заклинаний', value: MOCK_SPELLS.length },
                    { label: 'Гримуаров', value: MOCK_GRIMOIRES.length },
                  ].map(stat => (
                    <div key={stat.label} style={{ textAlign: 'center' }}>
                      <div style={{ fontFamily: 'Cinzel', fontSize: 20, color: '#c8a44a' }}>{stat.value}</div>
                      <div style={{ fontSize: 9.5, color: '#3a2a18', marginTop: 2 }}>{stat.label.toUpperCase()}</div>
                    </div>
                  ))}
                </div>
              </Panel>
            </div>
          )}

          {tab === 'storage' && <StorageShelf />}

          {tab === 'craft' && (
            <div>
              <Panel style={{ padding: '14px 16px', marginBottom: 14 }}>
                <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#c8a44a', marginBottom: 6 }}>Алхимическая мастерская</div>
                <div style={{ fontSize: 12, color: '#7a6a4a', lineHeight: 1.6 }}>
                  Для доступа необходимо завершить трек Алхимии в Академии (Бакалавр).
                </div>
              </Panel>
              <Panel style={{ padding: '14px 16px' }}>
                <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#c8a44a', marginBottom: 6 }}>Мастерская инструментов</div>
                <div style={{ fontSize: 12, color: '#7a6a4a', lineHeight: 1.6 }}>
                  Для доступа необходимо завершить трек Мастерства в Академии.
                </div>
              </Panel>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { BaseScreen });


// ═══ js/AcademyScreen.jsx ═══
// AcademyScreen.jsx — academy, schedule, clubs, research

const COURSES = [
  { id: 'c1', name: 'Теория Огня II',        teacher: 'Проф. Мирдор',  track: 'Волшебство', progress: 0.62, timeLeft: '2д 6ч',   status: 'active' },
  { id: 'c2', name: 'Латынь и Инкантации',   teacher: 'Проф. Велла',   track: 'Общие',      progress: 0.40, timeLeft: '4д 0ч',   status: 'active' },
  { id: 'c3', name: 'Практика Хаоса I',      teacher: 'Проф. Мирдор',  track: 'Волшебство', progress: 0.00, timeLeft: '8д',      status: 'upcoming' },
  { id: 'c4', name: 'История Принципата',    teacher: 'Проф. Данн',    track: 'Общие',      progress: 1.00, timeLeft: 'Завершён', status: 'done' },
];

const CLUBS_DATA = [
  { id: 'cl1', name: 'Клуб Дуэлистов',            desc: 'Практические PvP-тренировки. Низкие ставки.', members: 12, joined: true,  icon: '⚔' },
  { id: 'cl2', name: 'Экспедиционное общество',    desc: 'Планирование вылазок. Поиск группы.',         members: 8,  joined: false, icon: '◎' },
  { id: 'cl3', name: 'Алхимический кружок',        desc: 'Совместное создание зелий и ингредиентов.',   members: 6,  joined: false, icon: '⚗' },
  { id: 'cl4', name: 'Исследовательская гр. Хаос', desc: 'Изучение природы и предела школы Хаоса.',     members: 4,  joined: true,  icon: '⊗' },
  { id: 'cl5', name: 'Торговая гильдия (студ.)',   desc: 'Обмен реагентами и заклинаниями.',            members: 19, joined: false, icon: '⚖' },
];

const RESEARCH_ITEMS = [
  { id: 'r1', title: 'Комбинация Огонь + Хаос',   desc: 'Изучить взаимодействие двух ваших школ', progress: 0.3,  xp: 400,  difficulty: 'Низкая' },
  { id: 'r2', title: 'Новая формула инкантации',  desc: 'Создать оригинальное заклинание для БД',  progress: 0,    xp: 800,  difficulty: 'Средняя' },
  { id: 'r3', title: 'Диссертация: Природа Хаоса',desc: 'Финальная работа. Открывает должность Профессора', progress: 0, xp: 5000, difficulty: 'Высокая' },
];

const TRACK_STAGES = ['Базовое', 'Бакалавр', 'Магистр', 'Аспирант', 'Доктор'];

function CourseCard({ course }) {
  const active = course.status === 'active';
  const done   = course.status === 'done';
  return (
    <div style={{
      background: 'linear-gradient(155deg, #2e2418, #1c1610)',
      border: `1px solid ${active ? 'rgba(200,164,74,0.32)' : done ? 'rgba(60,160,60,0.25)' : 'rgba(200,164,74,0.12)'}`,
      borderLeft: `3px solid ${active ? '#c8a44a' : done ? '#60a060' : 'rgba(200,164,74,0.2)'}`,
      borderRadius: 11, padding: '11px 13px',
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: active ? 10 : 0 }}>
        <div style={{ flex: 1, paddingRight: 8 }}>
          <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: done ? '#60a060' : '#e8d5b0', marginBottom: 2 }}>
            {done && '✓ '}{course.name}
          </div>
          <div style={{ fontSize: 10, color: '#4a3a28' }}>
            {course.teacher} · {course.track}
          </div>
        </div>
        <div style={{
          padding: '2px 8px', borderRadius: 6, fontSize: 9.5, fontFamily: 'Cinzel', flexShrink: 0,
          background: active ? 'rgba(200,164,74,0.13)' : done ? 'rgba(60,160,60,0.12)' : 'rgba(50,60,80,0.3)',
          color: active ? '#c8a44a' : done ? '#60a060' : '#4a6080',
          border: `1px solid ${active ? 'rgba(200,164,74,0.28)' : done ? 'rgba(60,160,60,0.3)' : 'rgba(50,60,80,0.35)'}`,
        }}>
          {course.timeLeft}
        </div>
      </div>
      {active && (
        <div style={{ height: 3, background: 'rgba(255,255,255,0.07)', borderRadius: 2, overflow: 'hidden' }}>
          <div style={{ height: '100%', width: `${course.progress * 100}%`, background: '#c8a44a', borderRadius: 2, boxShadow: '0 0 6px #c8a44a60' }} />
        </div>
      )}
    </div>
  );
}

function AcademyScreen() {
  const [tab, setTab] = React.useState('schedule');
  const [clubs, setClubs] = React.useState(CLUBS_DATA);
  const [toast, setToast] = React.useState(null);

  const toggleClub = (id) => {
    setClubs(cs => cs.map(c => c.id === id ? { ...c, joined: !c.joined } : c));
  };

  const showToast = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(null), 2500);
  };

  const tabs = [
    { id: 'schedule',  label: 'Расписание' },
    { id: 'clubs',     label: 'Клубы' },
    { id: 'research',  label: 'Исследования' },
  ];

  return (
    <div style={{ position: 'absolute', inset: 0, background: '#0d0a07', display: 'flex', flexDirection: 'column' }}>
      <TelegramHeader title="Академия" subtitle="Трек: Волшебство · Бакалавр II" />

      <div style={{ paddingTop: 56, flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>

        {/* Track progress bar */}
        <div style={{
          padding: '10px 16px',
          borderBottom: '1px solid rgba(200,164,74,0.1)',
          flexShrink: 0,
        }}>
          <div style={{ fontSize: 9.5, color: '#3a2a18', fontFamily: 'Cinzel', letterSpacing: '0.06em', marginBottom: 6 }}>
            АКАДЕМИЧЕСКИЙ ПУТЬ
          </div>
          <div style={{ display: 'flex', gap: 3 }}>
            {TRACK_STAGES.map((stage, i) => {
              const filled = i <= 1;
              const current = i === 1;
              return (
                <div key={i} style={{ flex: 1, position: 'relative' }}>
                  <div style={{
                    height: 5, borderRadius: 2,
                    background: filled ? (current ? '#c8a44a' : '#8a6830') : 'rgba(255,255,255,0.07)',
                    boxShadow: current ? '0 0 8px #c8a44a60' : 'none',
                  }} />
                  <div style={{
                    fontSize: 8, color: filled ? '#c8a44a' : '#2a1a10',
                    textAlign: 'center', marginTop: 3, fontFamily: 'Cinzel', letterSpacing: '0.02em',
                  }}>
                    {stage}
                  </div>
                </div>
              );
            })}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4 }}>
            <div style={{ fontSize: 9.5, color: '#5a4a30' }}>2-й год обучения</div>
            <div style={{ fontSize: 9.5, color: '#c8a44a' }}>+240 XP сегодня</div>
          </div>
        </div>

        {/* Tabs */}
        <div style={{ display: 'flex', borderBottom: '1px solid rgba(200,164,74,0.12)', paddingLeft: 8, paddingRight: 8, flexShrink: 0 }}>
          {tabs.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)} style={{
              flex: 1, background: 'none', border: 'none',
              borderBottom: tab === t.id ? '2px solid #c8a44a' : '2px solid transparent',
              padding: '9px 2px', cursor: 'pointer',
              fontSize: 10.5, fontFamily: 'Cinzel',
              color: tab === t.id ? '#c8a44a' : '#3a2a18',
              transition: 'color 0.15s', letterSpacing: '0.03em',
            }}>{t.label}</button>
          ))}
        </div>

        <div style={{ flex: 1, overflow: 'auto', padding: '14px 16px', paddingBottom: 20 }}>

          {tab === 'schedule' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
              {COURSES.map(c => <CourseCard key={c.id} course={c} />)}
              <GoldButton
                style={{ width: '100%', padding: '10px', marginTop: 4 }}
                onClick={() => showToast('Запись на новые курсы откроется через 1 игр. день.')}
              >
                Записаться на новый курс
              </GoldButton>
            </div>
          )}

          {tab === 'clubs' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
              {clubs.map(club => (
                <div key={club.id} style={{
                  background: 'linear-gradient(155deg, #2e2418, #1c1610)',
                  border: `1px solid ${club.joined ? 'rgba(200,164,74,0.35)' : 'rgba(200,164,74,0.13)'}`,
                  borderRadius: 11, padding: '11px 13px',
                }}>
                  <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 8 }}>
                    <div style={{
                      width: 36, height: 36, borderRadius: 8, flexShrink: 0,
                      background: club.joined ? 'rgba(200,164,74,0.18)' : 'rgba(42,32,20,0.6)',
                      border: `1px solid ${club.joined ? 'rgba(200,164,74,0.4)' : 'rgba(200,164,74,0.15)'}`,
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      fontSize: 18, color: club.joined ? '#c8a44a' : '#3a2a18',
                    }}>
                      {club.icon}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#e8d5b0', marginBottom: 3 }}>
                        {club.name}
                      </div>
                      <div style={{ fontSize: 11, color: '#5a4a30', lineHeight: 1.5 }}>{club.desc}</div>
                      <div style={{ fontSize: 9.5, color: '#2a1a10', marginTop: 4 }}>{club.members} участников</div>
                    </div>
                  </div>
                  <GoldButton
                    small
                    danger={club.joined}
                    onClick={() => toggleClub(club.id)}
                    style={{ marginLeft: 46 }}
                  >
                    {club.joined ? 'Покинуть' : 'Вступить'}
                  </GoldButton>
                </div>
              ))}
            </div>
          )}

          {tab === 'research' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
              <Panel style={{ padding: '11px 13px', marginBottom: 4 }}>
                <div style={{ fontSize: 12, color: '#8a7a5a', lineHeight: 1.65, fontStyle: 'italic' }}>
                  Академический путь открыт после бакалавриата. Исследования создают новые заклинания для публичной базы данных.
                </div>
              </Panel>
              {RESEARCH_ITEMS.map(item => (
                <div key={item.id} style={{
                  background: 'linear-gradient(155deg, #2e2418, #1c1610)',
                  border: '1px solid rgba(200,164,74,0.18)',
                  borderRadius: 11, padding: '11px 13px',
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: item.progress > 0 ? 10 : 0 }}>
                    <div style={{ flex: 1, paddingRight: 8 }}>
                      <div style={{ fontFamily: 'Cinzel', fontSize: 13, color: '#e8d5b0', marginBottom: 2 }}>
                        {item.title}
                      </div>
                      <div style={{ fontSize: 11, color: '#5a4a30', lineHeight: 1.5, marginBottom: 4 }}>{item.desc}</div>
                      <div style={{ display: 'flex', gap: 10 }}>
                        <span style={{ fontSize: 10, color: '#4a6080' }}>+{item.xp} XP</span>
                        <span style={{ fontSize: 10, color: item.difficulty === 'Высокая' ? '#c06050' : item.difficulty === 'Средняя' ? '#c8a44a' : '#60a060' }}>
                          {item.difficulty}
                        </span>
                      </div>
                    </div>
                    <GoldButton small disabled={item.difficulty === 'Высокая'} onClick={() => showToast('Исследование начато.')}>
                      {item.progress > 0 ? 'Продолжить' : 'Начать'}
                    </GoldButton>
                  </div>
                  {item.progress > 0 && (
                    <div style={{ height: 3, background: 'rgba(255,255,255,0.07)', borderRadius: 2, overflow: 'hidden' }}>
                      <div style={{ height: '100%', width: `${item.progress * 100}%`, background: '#c8a44a', borderRadius: 2 }} />
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {toast && (
        <div style={{
          position: 'absolute', bottom: 20, left: 16, right: 16,
          background: 'rgba(13,10,7,0.97)', border: '1px solid rgba(200,164,74,0.38)',
          borderRadius: 10, padding: '11px 16px',
          fontSize: 12, color: '#c8a44a', textAlign: 'center', zIndex: 100,
        }}>
          {toast}
        </div>
      )}
    </div>
  );
}

Object.assign(window, { AcademyScreen });


// ═══ js/App.jsx ═══
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

