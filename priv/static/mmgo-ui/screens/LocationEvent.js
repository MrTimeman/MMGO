// Location text-event — arriving at a city/tower/etc.

const LOCATION_DATA = {
  capital: {
    title:'Столица',
    subtitle:'Главный город княжества',
    hero:'Городские врата',
    text:[
      'Стражники в кольчугах лениво переглядываются. От кузницы тянет углём и пóтом, с рыночной площади — жареной рыбой и пряной мятой. Над башенками ратуши кружат голуби.',
      'К вам подходит мальчишка-посыльный: «Сударь, там на доске объявлений — письмо с вашим именем. И печать красная».',
    ],
    actions:[
      {k:'academy',  label:'В Академию',         hint:'учебные залы'},
      {k:'market',   label:'На рынок',           hint:'лавки и торговцы'},
      {k:'tavern',   label:'В таверну «Три пера»', hint:'новости и наём'},
      {k:'letter',   label:'Вскрыть письмо',     hint:'печать красного воска', accent:true},
      {k:'leave',    label:'Уйти обратно на карту'},
    ],
  },
  tower:{
    title:'Башня',
    subtitle:'Единственное место, где работает магия',
    hero:'У подножия',
    text:[
      'Воздух здесь звенит, как струна слабо натянутого лука. Камень у входа тёплый — местами теплее ладони. На ступенях мелком начерчена фигурка, похожая на восьмилучевой компас; одна из её граней затёрта.',
      'Внутри слышно, как кто-то сосредоточенно что-то бормочет по-латыни. Голоса сразу трёх.',
    ],
    actions:[
      {k:'party',  label:'Собрать / найти отряд'},
      {k:'dungeon',label:'Войти в подземелье', hint:'готовьтесь тщательно', accent:true},
      {k:'library',label:'Библиотека Башни'},
      {k:'leave',  label:'Обратно на карту'},
    ],
  },
  farmstead:{
    title:'Хутор',
    subtitle:'Ваша база',
    hero:'Дом',
    text:[
      'Скрипит калитка. Пёс без одного уха привычно не гавкает. На крыльце — чей-то оставленный вчера свёрток; запах трав подсказывает, что это, скорее всего, от аптекаря.',
    ],
    actions:[
      {k:'base',  label:'Войти в дом', accent:true},
      {k:'forge', label:'В мастерскую'},
      {k:'garden',label:'Огород и запасы'},
      {k:'leave', label:'Обратно на карту'},
    ],
  },
};

function LocationEvent({poiId, onLeave, onGo}){
  const data = LOCATION_DATA[poiId] || {
    title:'Место', subtitle:'', hero:'', text:['Здесь пока тихо.'],
    actions:[{k:'leave', label:'Обратно на карту'}],
  };
  return (
    <div style={{position:'relative', flex:1, overflow:'hidden'}}>
      <div className="parchment"/>
      <div className="mmgo-scroll" style={{position:'relative', height:'100%', overflow:'auto', padding:'14px 16px 20px'}}>
        {/* Hero strip — a pseudo-illustration band */}
        <div style={{
          height:100, borderRadius:10, marginBottom:14,
          background:`
            linear-gradient(180deg, rgba(40,22,8,0.35), rgba(40,22,8,0.1)),
            repeating-linear-gradient(45deg, oklch(0.78 0.06 60), oklch(0.78 0.06 60) 6px, oklch(0.73 0.07 58) 6px, oklch(0.73 0.07 58) 12px)
          `,
          border:'1px solid rgba(60,35,10,0.45)',
          position:'relative', overflow:'hidden',
          boxShadow:'inset 0 0 20px rgba(60,35,10,0.35)',
        }}>
          <div style={{
            position:'absolute', inset:0, display:'flex', alignItems:'flex-end', padding:'8px 12px',
            color:'#f5ead3', fontFamily:'var(--display)', fontSize:14, letterSpacing:'.08em',
            textTransform:'uppercase', textShadow:'0 1px 2px rgba(0,0,0,0.6)',
          }}>{data.hero}</div>
          {/* corner ornaments */}
          {['0 0', '100% 0', '0 100%', '100% 100%'].map((pos,i)=>(
            <div key={i} style={{
              position:'absolute', width:14, height:14,
              left: pos.split(' ')[0]==='100%'?'auto':4, right: pos.split(' ')[0]==='100%'?4:'auto',
              top:  pos.split(' ')[1]==='100%'?'auto':4, bottom:pos.split(' ')[1]==='100%'?4:'auto',
              border:'1.5px solid rgba(245,234,211,0.65)',
              borderRight: i%2===1?'none':undefined,
              borderBottom: i>=2?'none':undefined,
              borderLeft: i%2===0?undefined:'none',
              borderTop: i<2?undefined:'none',
            }}/>
          ))}
        </div>

        <Ornament>{data.title}</Ornament>
        {data.subtitle && (
          <div style={{textAlign:'center', fontFamily:'var(--serif)', fontStyle:'italic', color:'var(--ink-faint)', fontSize:12, marginTop:2, marginBottom:14}}>
            {data.subtitle}
          </div>
        )}

        {/* Body text with drop cap */}
        <div style={{fontFamily:'var(--serif)', fontSize:14, lineHeight:1.6, color:'var(--ink)', textAlign:'justify'}}>
          {data.text.map((para,i)=>(
            <p key={i} style={{margin:'0 0 10px'}}>
              {i===0 ? (
                <><span style={{
                  float:'left', fontFamily:'var(--display)', fontWeight:700,
                  fontSize:40, lineHeight:.85, marginRight:6, marginTop:3,
                  color:'var(--wax)',
                }}>{para.charAt(0)}</span>{para.slice(1)}</>
              ) : para}
            </p>
          ))}
        </div>

        <div className="hrule" style={{margin:'18px 0 12px'}}/>

        <div style={{display:'flex', flexDirection:'column', gap:8}}>
          {data.actions.map(a=>(
            <button key={a.k}
              className={`inkbtn${a.accent?' primary':''}`}
              onClick={()=>{
                if(a.k==='leave') onLeave();
                else onGo && onGo(a.k);
              }}
              style={{
                textAlign:'left', display:'flex', alignItems:'center', justifyContent:'space-between',
                fontSize:14,
              }}>
              <span>{a.label}</span>
              {a.hint && <span style={{
                fontFamily:'var(--serif)', fontStyle:'italic', fontWeight:400, fontSize:11,
                color: a.accent?'rgba(245,234,211,0.8)':'var(--ink-faint)',
              }}>{a.hint}</span>}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { LocationEvent, LOCATION_DATA });
