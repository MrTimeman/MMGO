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
