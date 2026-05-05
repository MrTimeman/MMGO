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
