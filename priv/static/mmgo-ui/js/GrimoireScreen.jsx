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
