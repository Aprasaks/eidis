'use strict';

const $ = (s) => document.querySelector(s);
const root = document.body;
const canvas = $('#particles');
const ctx = canvas.getContext('2d', { alpha:true });
const workspace = $('#workspace');
const views = ['dashboard-view','variants-view','memories-view','screen-view'];
let activeMode = 'orb';
let currentTheme = 'nebula';
let recognizing = false;
let wantMic = false;
let recognition = null;
let micRetry = null;
let activeStream = null;
let respondTimer = null;
let summonAt = null;
let voiceWakeUntil = 0;
let pauseForSpeech = false;
let particles = [];
let width = 0;
let height = 0;
let sizeRatio = 1;

function resizeCanvas() {
  width = window.innerWidth; height = window.innerHeight;
  sizeRatio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(width * sizeRatio);
  canvas.height = Math.round(height * sizeRatio);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(sizeRatio, 0, 0, sizeRatio, 0, 0);
  if (!particles.length) {
    particles = Array.from({length: Math.min(380, Math.max(150, Math.round(width * height / 3300)))}, (_,i) => ({
      phase:Math.random()*Math.PI*2, angle:Math.random()*Math.PI*2, r: Math.random(), speed:.36+Math.random()*.9,
      x:Math.random()*width, y:Math.random()*height, size:.38+Math.random()*.75, noise:Math.random()*3, i
    }));
  }
}
window.addEventListener('resize', resizeCanvas);
resizeCanvas();

function drawFrame(ms) {
  const t = ms/1000;
  ctx.clearRect(0,0,width,height);
  const dashboard = root.classList.contains('dashboard-open');
  const r = $('#ring-visual').getBoundingClientRect();
  const cx = r.left + r.width/2;
  const cy = r.top + r.height/2;
  const R = Math.min(r.width,r.height)*.41;
  const progress = summonAt === null ? 0 : Math.max(0,Math.min(1,(ms-summonAt)/2100));
  const gather = 1-Math.pow(1-progress,3);
  const glow = recognizing ? 1.25 : 1;
  const galaxy = dashboard && currentTheme !== 'ambient';
  for (const p of particles) {
    const outer = p.i % 5 === 0;
    const spread = outer ? 1 : 0;
    const a = p.angle + Math.sin(t*.14+p.phase)*.06;
    const ripple = 1 + .045*Math.sin(t*.93 + a*7+p.phase) + .016*Math.sin(t*2.2 + a*11+p.noise);
    const targetX = cx + Math.cos(a) * (R * ripple + (p.r-.5)*(outer?72:12));
    const targetY = cy + Math.sin(a) * (R*ripple*.97 + (p.r-.5)*(outer?72:12));
    const x = (p.x+(targetX-p.x)*gather) + Math.sin(t*p.speed*.44+p.phase)*3;
    const y = (p.y+(targetY-p.y)*gather) + Math.cos(t*p.speed*.45+p.phase)*3;
    const r = p.size*(outer? .7:1.0)*glow;
    ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);
    ctx.fillStyle=`rgba(169,223,239,${(outer?.15:.37+.3*Math.sin(t*.45+p.phase)**2)*(.1+.9*gather)})`;
    ctx.fill();
  }
  if (galaxy) {
    for (let i=0; i<100; i++) {
      const seed = i*17.43;
      const x = ((Math.sin(seed*12.3)*17421)%1 + 1)%1*width;
      const y = ((Math.sin(seed*3.14)*19451)%1 + 1)%1*height;
      ctx.fillStyle=`rgba(173,198,235,${.06+.11*Math.sin(t*.37+seed)**2})`;
      ctx.beginPath();ctx.arc(x,y,i%11===0?1.1:.55,0,Math.PI*2);ctx.fill();
    }
  }
  requestAnimationFrame(drawFrame);
}
requestAnimationFrame(drawFrame);

function showView(id) {
  views.forEach(k => {document.getElementById(k).hidden = k !== id;});
  // hidden attributes are required to beat display:grid in CSS
  views.forEach(k=>document.getElementById(k).style.display=k === id?'':'none');
}
function summon() {
  if (summonAt === null) {summonAt = performance.now();root.classList.add('awakened');}
}
function setMode(mode) {
  if (mode !== 'screen' && activeStream) stopScreen();
  if (mode !== 'orb') summon();
  activeMode = mode;
  const dashboard = mode !== 'orb';
  workspace.hidden = !dashboard;
  workspace.style.display = dashboard ? '' : 'none';
  root.classList.toggle('dashboard-open',dashboard);
  $('#state-label').textContent = dashboard ? 'CONNECTED · WORKSPACE ACTIVE' : 'READY WHEN YOU ARE';
  $('#hero-title').textContent = dashboard ? '듣고 있습니다.' : '부르면, 연결됩니다.';
  if (mode==='variants') showView('variants-view');
  else if (mode==='memories') {showView('memories-view');loadMemories();}
  else if (mode==='screen') showView('screen-view');
  else showView('dashboard-view');
}
function showMessage(txt) {$('#last-response').textContent = txt;}
function speak(txt) {
  if (!('speechSynthesis' in window)) return;
  window.speechSynthesis.cancel();
  pauseForSpeech=true;
  if (recognition && wantMic) {try{recognition.stop();}catch(_e){}}
  const msg = new SpeechSynthesisUtterance(txt);
  msg.lang = 'ko-KR'; msg.rate=.94; msg.pitch=.94;
  const voices = window.speechSynthesis.getVoices();
  const korean = voices.find(v=>v.lang.toLowerCase().startsWith('ko'));
  if (korean) msg.voice=korean;
  msg.onstart=()=>root.classList.add('state-speaking');
  const resume=()=>{root.classList.remove('state-speaking');pauseForSpeech=false;if(wantMic&&!recognizing)restartMic(350);};
  msg.onend=resume;
  msg.onerror=resume;
  window.speechSynthesis.speak(msg);
}
async function issue(text) {
  text=text.trim();if(!text)return;
  $('#command-input').value='';
  showMessage('처리 중…');
  try {
    const r=await fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
    const data=await r.json();
    if (!r.ok) throw new Error(data.error || '요청에 실패했습니다.');
    showMessage(data.text);
    if (data.action === 'wake') summon();
    setMode(data.mode);
    speak(data.spoken);
  } catch (err) {showMessage(`오류: ${err.message}`);}
}
$('#command-form').addEventListener('submit',e=>{e.preventDefault();issue($('#command-input').value);});
$('#close-workspace').addEventListener('click',()=>setMode('orb'));
$('#show-variants').addEventListener('click',()=>setMode('variants'));
$('#show-memory').addEventListener('click',()=>setMode('memories'));
$('#open-screen').addEventListener('click',()=>setMode('screen'));
$('#back-to-dash').addEventListener('click',()=>setMode('dashboard'));
$('#back-from-memory').addEventListener('click',()=>setMode('dashboard'));
$('#back-from-screen').addEventListener('click',()=>{stopScreen();setMode('dashboard');});

for (const button of document.querySelectorAll('.variant')) {
  button.addEventListener('click',()=>{
    const theme=button.dataset.theme;
    currentTheme=theme;
    root.classList.remove('theme-ambient','theme-nebula','theme-studio');
    root.classList.add(`theme-${theme}`);
    const themes={ambient:'Ambient',nebula:'Nebula',studio:'Studio'};
    showMessage(`${themes[theme]} 스타일을 선택했습니다. 이 화면 안에서만 임시 적용됩니다.`);
    setMode('dashboard');
  });
}
root.classList.add('theme-nebula');

async function loadMemories() {
  const box=$('#memories-list');
  box.replaceChildren();
  try {
    const r=await fetch('/api/memories'); const data=await r.json();
    if(!data.items.length){box.textContent='아직 저장된 기억이 없습니다. “기억해: ...”라고 입력해 보세요.';return;}
    for(const m of data.items){
      const row=document.createElement('div');row.className='memory-row';
      const body=document.createElement('div');body.textContent=m.content;
      const time=document.createElement('time');time.textContent=m.created_at.replace('T',' ').slice(0,16)+' UTC';
      row.append(body,time);box.appendChild(row);
    }
  } catch(err){box.textContent='기억을 불러오지 못했습니다.';}
}

async function shareScreen() {
  if (!navigator.mediaDevices?.getDisplayMedia) {
    showMessage('이 브라우저는 화면 공유 기능을 지원하지 않습니다.');return;
  }
  try {
    stopScreen();
    activeStream=await navigator.mediaDevices.getDisplayMedia({video:{frameRate:5},audio:false});
    const v=$('#screen-video');v.srcObject=activeStream;
    $('#screen-overlay').style.display='none';
    for(const track of activeStream.getVideoTracks()) track.addEventListener('ended',()=>stopScreen());
    showMessage('선택한 화면의 로컬 미리보기를 표시합니다. 서버로 전송하지 않습니다.');
  }catch(err){showMessage(err.name==='NotAllowedError'?'화면 공유가 취소되었거나 허용되지 않았습니다.':`화면 공유 오류: ${err.message}`);}
}
function stopScreen() {
  if(activeStream)activeStream.getTracks().forEach(track=>track.stop());
  activeStream=null;
  $('#screen-video').srcObject=null;
  $('#screen-overlay').style.display='';
}
$('#start-share').addEventListener('click',shareScreen);
$('#stop-share').addEventListener('click',()=>{stopScreen();showMessage('화면 공유를 종료했습니다.');});

const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
function micButtonState() {
  $('#voice-toggle').classList.toggle('active',wantMic);
  $('#voice-toggle').setAttribute('aria-pressed',String(wantMic));
  $('#voice-toggle').title=wantMic?'마이크 끄기':'마이크 켜기';
  $('#mic-status').textContent=wantMic?'MIC ON · 브라우저 음성 인식 작동 중':'MIC OFF · 브라우저 음성 기능은 환경에 따라 다릅니다.';
  root.classList.toggle('state-listening',wantMic);
}
function restartMic(delay=650) {
  clearTimeout(micRetry);
  micRetry=setTimeout(()=>{
    if (!wantMic || pauseForSpeech || document.visibilityState !== 'visible' || recognizing) return;
    try{recognition.start();recognizing=true;}catch(_e){disableMic('마이크를 다시 시작하지 못했습니다.');}
  }, delay);
}
function disableMic(msg) {
  wantMic=false;
  clearTimeout(micRetry);
  if(recognition){try{recognition.stop();}catch(_e){}}
  micButtonState();
  if(msg)showMessage(msg);
}
if (Recognition) {
  recognition=new Recognition();
  recognition.lang='ko-KR';
  recognition.interimResults=false;
  recognition.continuous=true;
  recognition.onresult=(ev)=>{
    for(let i=ev.resultIndex;i<ev.results.length;i++){
      const result=ev.results[i];
      if(result.isFinal){
        const said=result[0].transcript.trim();
        if (!said) continue;
        if (/^(자비스|jarvis)(?:[\s?!.,，？]|$)/i.test(said)) {voiceWakeUntil=Date.now()+12000;issue(said);}
        else if (Date.now()<voiceWakeUntil) {voiceWakeUntil=0;issue(said);}
        else showMessage('먼저 “자비스”라고 불러 주세요. 음성은 명시적 호출 후에만 명령으로 처리합니다.');
      }
    }
  };
  recognition.onerror=(ev)=>{
    if(ev.error==='not-allowed'||ev.error==='service-not-allowed')disableMic('마이크 사용 권한이 거부되었습니다. 브라우저 권한을 확인해 주세요.');
    else if(ev.error!=='no-speech'&&ev.error!=='aborted')showMessage(`음성 인식 문제: ${ev.error}`);
  };
  recognition.onend=()=>{
    recognizing=false;
    if(wantMic && !pauseForSpeech && document.visibilityState==='visible') restartMic();
  };
}
$('#voice-toggle').addEventListener('click',()=>{
  if(!Recognition){showMessage('이 브라우저에서는 음성 인식이 제공되지 않습니다. 크롬의 지원 여부를 확인하거나 텍스트를 입력해 주세요.');return;}
  if(wantMic){disableMic('마이크를 껐습니다.');return;}
  wantMic=true;micButtonState();
  try{recognition.start();recognizing=true;showMessage('마이크가 켜졌습니다. “자비스”라고 말해 보세요.');}
  catch(err){disableMic(`마이크를 시작하지 못했습니다: ${err.message}`);}
});
document.addEventListener('visibilitychange',()=>{
  if(document.visibilityState==='hidden'){
    disableMic();stopScreen();
  }
});
window.addEventListener('beforeunload',()=>{disableMic();stopScreen();window.speechSynthesis?.cancel();});
setMode('orb');

// Native SwiftUI bridge. This only reflects a reply already verified by the localhost server.
// It does not execute arbitrary JavaScript or commands passed from a remote page.
window.jarvisNativeResult = (reply) => {
  if (!reply || typeof reply !== 'object') return;
  const validModes = new Set(['orb','dashboard','variants','memories','screen']);
  if (!validModes.has(reply.mode) || typeof reply.text !== 'string') return;
  showMessage(reply.text);
  if (reply.action === 'wake') summon();
  setMode(reply.mode);
};
