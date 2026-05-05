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
