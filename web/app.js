'use strict';

const $ = (s) => document.querySelector(s);
const root = document.body;
const canvas = $('#particles');
const ctx = canvas.getContext('2d', { alpha:true });
const workspace = $('#workspace');
const views = ['dashboard-view','variants-view','memories-view','screen-view'];
let activeMode = 'orb';
let currentTheme = 'nebula';
let designOriginalTheme = 'nebula';
let designOriginalSpec = null;
let activeGeneratedSpec = null;
let designApplying = false;
let designBusy = false;
let recognizing = false;
let wantMic = false;
let recognition = null;
let micRetry = null;
let activeStream = null;
let visionBusy = false;
let visionGeneration = 0;
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
  // A preview is never committed just by navigating away.
  if (activeMode === 'variants' && mode !== 'variants' && !designApplying) {
    restoreOriginalDesign();
  }
  if (mode !== 'screen' && activeStream) stopScreen();
  if (mode !== 'orb') summon();
  if (mode === 'variants' && activeMode !== 'variants') {
    designOriginalTheme = currentTheme;
    designOriginalSpec = activeGeneratedSpec ? {...activeGeneratedSpec} : null;
    updateVariantSelection();
  }
  activeMode = mode;
  const dashboard = mode !== 'orb';
  workspace.hidden = !dashboard;
  workspace.style.display = dashboard ? '' : 'none';
  root.classList.toggle('dashboard-open',dashboard);
  root.classList.toggle('design-mode', mode === 'variants');
  $('#state-label').textContent = dashboard ? 'PRESENCE / ENGAGED' : 'AWAITING YOUR VOICE';
  $('#hero-title').textContent = dashboard ? '항상 여기 있습니다.' : '부르면, 연결됩니다.';
  $('#workspace-title').textContent = mode === 'variants' ? '디자인 연구실' : mode === 'memories' ? '저장한 기억' : mode === 'screen' ? '화면 미리보기' : '작업 공간';
  // Keep the smaller index element when changing headings.
  const index = document.createElement('span');
  index.className = 'heading-index';
  index.textContent = mode === 'variants' ? '02 — DESIGN' : '01 — OVERVIEW';
  $('#workspace-title').appendChild(index);
  if (mode === 'dashboard') void refreshDashboardData();
  if (mode==='variants') showView('variants-view');
  else if (mode==='memories') {showView('memories-view');loadMemories();}
  else if (mode==='screen') showView('screen-view');
  else showView('dashboard-view');
}
function showMessage(txt, level = 'info') {
  const kind = level === 'info' && /^(오류|실패|연결 실패|화면 분석 불가|시안 생성 실패)/.test(String(txt))
    ? 'error' : level;
  window.JarvisTerminal?.push(txt, kind);
}
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
  try {
    const r=await fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})});
    const data=await r.json();
    if (!r.ok) throw new Error(data.error || '요청에 실패했습니다.');
    // Successful commands are already recorded once as durable *metadata* by
    // the local engine. Do not echo a second log line or private recall content.
    if (data.action === 'unsupported') {
      showMessage('이 명령은 아직 지원하지 않습니다. 아무 작업도 실행하지 않았습니다.', 'warning');
    }
    void refreshDashboardData();
    if (data.action === 'wake') summon();
    setMode(data.mode);
    speak(data.spoken);
    if (data.action === 'design_options' && typeof data.design_prompt === 'string') {
      await generateRequestedDesigns(data.design_prompt, 'rules');
    }
  } catch (err) {showMessage(`오류: ${err.message}`);}
}
$('#command-form').addEventListener('submit',e=>{e.preventDefault();issue($('#command-input').value);});
$('#close-workspace').addEventListener('click',()=>setMode('orb'));
$('#show-variants').addEventListener('click',()=>setMode('variants'));
$('#board-redesign').addEventListener('click',()=>setMode('variants'));
$('#demo-wake').addEventListener('click',()=>issue('자비스?'));
$('#demo-dashboard').addEventListener('click',()=>issue('자비스, 대시보드 띄워'));
$('#show-memory').addEventListener('click',()=>setMode('memories'));
$('#open-screen').addEventListener('click',()=>setMode('screen'));
$('#back-from-memory').addEventListener('click',()=>setMode('dashboard'));
$('#back-from-screen').addEventListener('click',()=>{stopScreen();setMode('dashboard');});

const themeLabels = Object.freeze({
  ambient: 'Ambient',
  nebula: 'Nebula',
  studio: 'Studio',
  polar: 'Polar'
});
const themeNames = Object.keys(themeLabels);

function setTheme(theme) {
  if (!Object.hasOwn(themeLabels, theme)) return;
  clearGeneratedStyles();
  currentTheme = theme;
  for (const name of themeNames) root.classList.remove('theme-' + name);
  root.classList.add('theme-' + theme);
  updateVariantSelection();
}

function updateVariantSelection() {
  for (const button of document.querySelectorAll('.variant')) {
    const selected = button.dataset.theme
      ? button.dataset.theme === currentTheme
      : Boolean(activeGeneratedSpec && button.dataset.generatedId === activeGeneratedSpec.id);
    button.setAttribute('aria-pressed', String(selected));
  }
  const info = $('#design-status');
  if (info) {
    info.textContent = activeDesignLabel() +
      ' 미리보기 중 · 화면 디자인만 달라집니다. 이전에 적용한 시안은 ' +
      (designOriginalSpec?.title || themeLabels[designOriginalTheme] || '이전 설정') + '입니다.';
  }
}

for (const button of document.querySelectorAll('.variant')) {
  button.addEventListener('click', () => setTheme(button.dataset.theme));
}
$('#apply-design').addEventListener('click', () => {
  designOriginalTheme = currentTheme;
  designOriginalSpec = activeGeneratedSpec ? {...activeGeneratedSpec} : null;
  showMessage(activeDesignLabel() + ' 디자인을 이 화면에 적용했습니다. 서버와 Mac 설정은 변경되지 않았습니다.');
  designApplying = true;
  setMode('dashboard');
  designApplying = false;
});
$('#cancel-design').addEventListener('click', () => {
  restoreOriginalDesign();
  showMessage('이전에 적용했던 디자인으로 돌아왔습니다.');
  designApplying = true;
  setMode('dashboard');
  designApplying = false;
});
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
    showMessage('화면 미리보기 시작 · 공유한 화면은 로컬에만 표시합니다.', 'action');
  }catch(err){showMessage(err.name==='NotAllowedError'?'화면 공유가 취소되었거나 허용되지 않았습니다.':`화면 공유 오류: ${err.message}`);}
}
function stopScreen() {
  if(activeStream)activeStream.getTracks().forEach(track=>track.stop());
  activeStream=null;
  $('#screen-video').srcObject=null;
  $('#screen-overlay').style.display='';
  visionGeneration++;
  $('#vision-consent').checked = false;
  $('#vision-result').textContent = '아직 분석한 화면이 없습니다.';
  $('#vision-status').textContent = '공유가 종료되었습니다. 별도 API 호출이 자동으로 시작되지 않습니다.';
}
$('#start-share').addEventListener('click',shareScreen);
$('#stop-share').addEventListener('click',()=>{stopScreen();showMessage('화면 공유를 종료했습니다.');});

/* A single explicit click sends one downscaled JPEG only if remote vision is
   configured and the user confirms this specific request. No background stream. */
async function analyzeSharedScreenOnce() {
  const status = $('#vision-status');
  const output = $('#vision-result');
  const button = $('#analyze-screen');
  if (visionBusy) return;
  const question = $('#vision-question').value.trim();
  if (!activeStream || activeStream.getVideoTracks().every(t=>t.readyState!=='live')) {
    status.textContent = '먼저 화면 공유를 선택해 주세요.';
    return;
  }
  if (!$('#vision-consent').checked) {
    status.textContent = '이번 화면 한 장의 외부 전송 동의가 필요합니다.';
    return;
  }
  if (question.length < 3 || question.length > 450) {
    status.textContent = '질문은 3~450자로 입력해 주세요.';
    return;
  }

  visionBusy = true;
  button.disabled = true;
  const capturedGeneration = visionGeneration;
  try {
    const configResponse = await fetch('/api/status',{cache:'no-store'});
    if (!configResponse.ok) throw new Error('로컬 자비스 서버에 연결할 수 없습니다.');
    const config = await configResponse.json();
    if (!config.vision?.remote_configured) {
      throw new Error('외부 AI 화면 분석이 꺼져 있습니다. 별도 API 키와 허용 설정이 필요합니다.');
    }
    if (config.vision.remaining <= 0) {
      throw new Error('이 실행 세션의 화면 분석 한도에 도달했습니다.');
    }
    const video = $('#screen-video');
    if (capturedGeneration !== visionGeneration || video.readyState < 2 ||
        !video.videoWidth || !video.videoHeight) {
      throw new Error('화면을 캡처할 수 없습니다. 잠시 후 다시 시도해 주세요.');
    }
    const scale = Math.min(1, 1200 / Math.max(video.videoWidth,video.videoHeight));
    const frame = document.createElement('canvas');
    frame.width = Math.max(1,Math.round(video.videoWidth*scale));
    frame.height = Math.max(1,Math.round(video.videoHeight*scale));
    frame.getContext('2d').drawImage(video,0,0,frame.width,frame.height);
    const image = frame.toDataURL('image/jpeg',0.63);
    frame.width = 0;frame.height = 0;
    if (image.length > 1_380_000) {
      throw new Error('화면 이미지가 너무 큽니다. 작은 창을 선택해 주세요.');
    }
    status.textContent = '동의한 화면 한 장을 분석하도록 전송했습니다…';
    const response = await fetch('/api/vision/analyze', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({question,image,consent:true})
    });
    const answer = await response.json();
    if (!response.ok) throw new Error(answer.error || '화면 분석에 실패했습니다.');
    if (capturedGeneration !== visionGeneration) return;
    output.textContent = answer.text || '분석 결과를 표시할 수 없습니다.';
    status.textContent = 'AI 분석 완료 · 화면 한 장만 전달 · 앱 조작 없음';
    showMessage('승인한 화면 한 장의 AI 분석 완료 · 앱 조작 없음', 'action');
  } catch (err) {
    if (capturedGeneration === visionGeneration) {
      status.textContent = '화면 분석 불가: ' + err.message;
      showMessage('화면 분석 불가: ' + err.message, 'error');
      output.textContent = '실제 AI 분석이 완료되지 않았습니다.';
    }
  } finally {
    $('#vision-consent').checked = false;
    visionBusy = false;
    button.disabled = false;
  }
}
$('#analyze-screen').addEventListener('click',()=>{void analyzeSharedScreenOnce();});


const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
function micButtonState() {
  $('#voice-toggle').classList.toggle('active',wantMic);
  $('#voice-toggle').setAttribute('aria-pressed',String(wantMic));
  $('#voice-toggle').title=wantMic?'마이크 끄기':'마이크 켜기';
  $('#mic-status').textContent=wantMic?'MIC / ACTIVE':'MIC / OFF';
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
  if (reply.action === 'unsupported') {
    showMessage('지원하지 않는 명령입니다. 아무 작업도 실행하지 않았습니다.', 'warning');
  }
  void refreshDashboardData();
  if (reply.action === 'wake') summon();
  setMode(reply.mode);
  if (reply.action === 'design_options' && typeof reply.design_prompt === 'string') {
    void generateRequestedDesigns(reply.design_prompt, 'rules');
  }
};


/* Live localhost-backed operational facts. Never show invented counters. */
const capabilityLabels = Object.freeze({
  text_commands: '로컬 명령',
  memory: '개인 기억',
  browser_voice: '브라우저 음성',
  browser_screen_preview: '화면 공유 미리보기',
  vision_understanding: 'AI 화면 이해',
  llm_reasoning: 'AI 판단',
  mac_control: 'Mac 자동 조작',
  cloud: '클라우드',
  iphone: 'iPhone 연결',
  autonomous_tasks: '자율 업무'
});
const capabilityStates = Object.freeze({
  connected: ['연결됨','good'],
  browser_dependent: ['브라우저에 따라 다름','neutral'],
  permission_required: ['권한 필요','neutral'],
  not_connected: ['미연결','muted']
});
function fillDashboard(container, list, build) {
  container.replaceChildren();
  for (const item of list) container.appendChild(build(item));
}
async function refreshDashboardData() {
  if (document.visibilityState !== 'visible') return;
  const core = $('#core-status');
  try {
    const [statusRes,activityRes] = await Promise.all([
      fetch('/api/status', {cache:'no-store'}),
      fetch('/api/activity', {cache:'no-store'})
    ]);
    if (!statusRes.ok || !activityRes.ok) throw new Error('local API not ready');
    const status = await statusRes.json();
    const activity = await activityRes.json();
    const caps = status.capabilities || {};
    core.textContent = '연결됨';
    $('#connection-label').textContent = 'LOCAL CONNECTED';
    $('#online-dot').classList.remove('offline');
    window.JarvisTerminal?.setConnection('connected');
    $('#memory-count').textContent = Number.isInteger(status.memory_count)
      ? status.memory_count.toLocaleString('ko-KR') : '—';
    window.JarvisTerminal?.syncActivity(activity.items);
    const capEntries = Object.entries(capabilityLabels).map(([key,label]) => ({
      label, state: Array.isArray(capabilityStates[caps[key]])
        ? capabilityStates[caps[key]] : ['확인 필요','muted']
    }));
    fillDashboard($('#live-capabilities'), capEntries.slice(0,8), ({label,state}) => {
      const line = document.createElement('div'); line.className = 'capability-line';
      const a = document.createElement('span'); a.textContent = label;
      const b = document.createElement('span'); b.textContent = state[0]; b.className = state[1];
      line.append(a,b);
      return line;
    });
  } catch {
    core.textContent = '연결 불가';
    $('#connection-label').textContent = 'LOCAL DISCONNECTED';
    $('#online-dot').classList.add('offline');
    $('#memory-count').textContent = '—';
    window.JarvisTerminal?.setConnection('disconnected');
    const caps = $('#live-capabilities'); caps.replaceChildren();
    const item = document.createElement('p');item.className='activity-empty';
    item.textContent = '로컬 서버를 연결한 뒤 사용할 수 있습니다.';
    caps.appendChild(item);
  }
}
setInterval(() => {
  if (document.visibilityState === 'visible') void refreshDashboardData();
}, 15000);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') void refreshDashboardData();
});
window.addEventListener('error', (event) => {
  window.JarvisTerminal?.push('브라우저 스크립트 오류: ' + (event.message || '알 수 없음'), 'error');
});
window.addEventListener('unhandledrejection', () => {
  window.JarvisTerminal?.push('브라우저에서 처리되지 않은 비동기 오류가 발생했습니다.', 'error');
});
void refreshDashboardData();


/* Prompt-to-design workflow: the browser renders only validated design tokens.
   No HTML/CSS returned by a model is executed. */
const generatedClasses = [
  'theme-generated','generated-layout-balanced','generated-layout-focus','generated-layout-panorama',
  'generated-density-airy','generated-density-normal','generated-density-compact',
  'generated-orb-soft','generated-orb-thin','generated-orb-radiant'
];
const safeHex = /^#[0-9a-fA-F]{6}$/;
function validGeneratedSpec(spec) {
  return spec && typeof spec === 'object' && ['ai','rules'].includes(spec.source) &&
    typeof spec.id === 'string' && /^((rules|ai)-[1-4])$/.test(spec.id) &&
    typeof spec.title === 'string' && spec.title.length <= 28 &&
    ['balanced','focus','panorama'].includes(spec.layout) &&
    ['airy','normal','compact'].includes(spec.density) &&
    ['soft','thin','radiant'].includes(spec.orb) &&
    ['background','accent','surface','foreground'].every(k => safeHex.test(spec[k]));
}
function clearGeneratedStyles() {
  for (const name of generatedClasses) root.classList.remove(name);
  for (const key of ['bg','accent','surface','text']) root.style.removeProperty('--gen-' + key);
  activeGeneratedSpec = null;
}
function activeDesignLabel() {
  return activeGeneratedSpec?.title || themeLabels[currentTheme] || '디자인';
}
function setGeneratedDesign(spec) {
  if (!validGeneratedSpec(spec)) {
    showMessage('디자인 데이터가 유효하지 않아 적용하지 않았습니다.');
    return;
  }
  for (const name of themeNames) root.classList.remove('theme-' + name);
  clearGeneratedStyles();
  root.classList.add('theme-generated', 'generated-layout-' + spec.layout,
    'generated-density-' + spec.density, 'generated-orb-' + spec.orb);
  const vars = {bg: spec.background, accent: spec.accent, surface: spec.surface, text: spec.foreground};
  for (const [key,value] of Object.entries(vars)) root.style.setProperty('--gen-' + key, value);
  currentTheme = 'generated';
  activeGeneratedSpec = {...spec};
  updateVariantSelection();
}
function restoreOriginalDesign() {
  if (designOriginalSpec) setGeneratedDesign(designOriginalSpec);
  else setTheme(designOriginalTheme);
}
function showGeneratedGallery(show) {
  const preset = $('#preset-variant-list');
  const generated = $('#generated-variant-list');
  preset.hidden = show;
  generated.hidden = !show;
  preset.style.display = show ? 'none' : '';
  generated.style.display = show ? '' : 'none';
}
function renderGeneratedProposals(data) {
  if (!data || !Array.isArray(data.proposals) ||
      data.proposals.length !== 4 || !data.proposals.every(validGeneratedSpec)) {
    throw new Error('디자인 네 개를 안전하게 확인할 수 없습니다.');
  }
  const grid = $('#generated-variant-list');
  grid.replaceChildren();
  for (const spec of data.proposals) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'variant generated-variant';
    btn.dataset.generatedId = spec.id;
    btn.setAttribute('aria-pressed', 'false');
    btn.setAttribute('aria-label', spec.title + ' 생성 시안 미리보기');

    const shot = document.createElement('span'); shot.className = 'study-shot generated-study-shot';
    shot.style.setProperty('--study-bg', spec.background);
    shot.style.setProperty('--study-surface', spec.surface);
    shot.style.setProperty('--study-accent', spec.accent);
    const orb = document.createElement('i');orb.className = 'generated-study-orb';
    const panel = document.createElement('b');panel.className = 'generated-study-panel';
    const gridLines = document.createElement('small');gridLines.className = 'generated-study-lines';
    shot.append(orb,panel,gridLines);
    const info = document.createElement('span');info.className='study-info';
    const number = document.createElement('span');number.className='study-index';
    number.textContent = (spec.id.split('-')[1] || '?').padStart(2,'0') + ' /';
    const title = document.createElement('strong');title.textContent = spec.title;
    const desc = document.createElement('small');desc.textContent = spec.description;
    info.append(number,title,desc);
    btn.append(shot,info);
    btn.addEventListener('click', () => setGeneratedDesign(spec));
    grid.appendChild(btn);
  }
  showGeneratedGallery(true);
  $('#design-origin').textContent = (data.provider === 'ai' ? 'AI MODEL' : 'LOCAL RULES') +
    ' / 요청에 따라 새로 구성한 4개 시안';
  updateVariantSelection();
}
async function generateRequestedDesigns(prompt, provider) {
  if (designBusy) return;
  const phrase = String(prompt || '').trim();
  if (phrase.length < 3 || phrase.length > 320) {
    $('#design-request-status').textContent = '요청은 3~320자로 입력해 주세요.';
    return;
  }
  const consent = provider === 'ai' && $('#design-consent').checked;
  if (provider === 'ai' && !consent) {
    $('#design-request-status').textContent = '외부 AI에 보낼 내용을 확인하고 동의해 주세요.';
    $('#design-request').open = true;
    return;
  }
  designBusy = true;
  $('#design-generate').disabled = true;
  $('#design-request').open = true;
  $('#design-prompt').value = phrase;
  $('#design-request-status').textContent = provider === 'ai'
    ? '외부 AI에서 디자인 설정을 요청하고 있습니다…'
    : '기기에 있는 규칙으로 디자인 설정을 구성하고 있습니다…';
  try {
    const response = await fetch('/api/design/suggest', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({prompt:phrase,provider,consent})
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || '디자인 요청에 실패했습니다.');
    renderGeneratedProposals(data);
    $('#design-request-status').textContent = data.message;
    $('#design-request').open = false; // Reveal all four studies; keep the edit form easy to reopen.
    showMessage(data.message);
  } catch (error) {
    $('#design-request-status').textContent = '시안 생성 실패: ' + error.message;
    showMessage('시안 생성 실패: ' + error.message);
  } finally {
    designBusy = false;
    $('#design-generate').disabled = false;
  }
}
$('#design-request-form').addEventListener('submit', event => {
  event.preventDefault();
  void generateRequestedDesigns($('#design-prompt').value, $('#design-provider').value);
});
$('#design-provider').addEventListener('change', () => {
  const ai = $('#design-provider').value === 'ai';
  $('#design-consent-label').hidden = !ai;
  $('#design-consent-label').style.display = ai ? 'flex' : 'none';
  $('#design-consent').checked = false;
  $('#design-request-status').textContent = ai
    ? '실제 외부 모델 호출에는 설정된 API 키·유료 이용 요금·매 요청 동의가 필요합니다.'
    : '무료 로컬 방식입니다. AI 모델이 생성한 결과라고 표시하지 않습니다.';
});
