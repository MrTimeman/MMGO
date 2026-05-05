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
