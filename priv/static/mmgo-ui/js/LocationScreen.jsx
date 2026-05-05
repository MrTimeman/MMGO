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
