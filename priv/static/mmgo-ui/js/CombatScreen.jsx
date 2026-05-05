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
