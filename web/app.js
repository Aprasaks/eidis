'use strict';

const $ = (s) => document.querySelector(s);
const root = document.body;
const canvas = $('#particles');
const ctx = canvas.getContext('2d', { alpha:true });
const workspace = $('#workspace');
const views = ['dashboard-view','projects-view','variants-view','memories-view','screen-view'];
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
let conversationID = null;
let chatBusy = false;
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
  $('#state-label').textContent = dashboard ? '작업 공간 열림' : '대기 중';
  $('#hero-title').textContent = '무엇을 도와드릴까요?';
  $('#workspace-title').textContent = mode === 'variants' ? '디자인 연구실' : mode === 'projects' ? '프로젝트' : mode === 'memories' ? '저장한 기억' : mode === 'screen' ? '화면 미리보기' : '작업 공간';
  if (mode === 'dashboard') void refreshDashboardData();
  if (mode==='variants') showView('variants-view');
  else if (mode==='projects') {showView('projects-view'); void loadProjects();}
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
function displayAssistantReply(message) {
  const panel = $('#assistant-reply');
  $('#assistant-reply-text').textContent = String(message || '').slice(0,3200);
  panel.hidden = false;
}
function hideAssistantReply() {
  $('#assistant-reply').hidden = true;
  $('#assistant-reply-text').textContent = '';
}
$('#assistant-reply-dismiss').addEventListener('click',hideAssistantReply);

async function issue(text) {
  text = String(text || '').trim();
  if (!text || chatBusy) return;
  chatBusy = true;
  $('#command-input').value = '';
  const remote = $('#brain-remote-consent').checked;
  $('#brain-remote-consent').checked = false; // consent is strictly per turn
  try {
    const response = await fetch('/api/chat', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        text, conversation_id:conversationID, remote_consent:remote,
      })
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || '요청에 실패했습니다.');
    if (typeof data.conversation_id === 'string') conversationID = data.conversation_id;

    // Actual conversational answers are displayed as answers, not repeated in logs.
    // No raw conversation text is copied to the terminal.
    if (['chat_context','chat_local_status','chat_reply','chat_unavailable',
         'memory_search','chat_reset','project_overview','tool_github_checked',
         'tool_github_failed','tool_setup_required','tool_target_ambiguous'].includes(data.action)) {
      displayAssistantReply(data.text);
    } else {
      hideAssistantReply();
    }
    void refreshDashboardData();
    if (data.action === 'wake') summon();
    setMode(data.mode);
    if (data.mode === 'projects' && ['project_overview','tool_github_checked',
         'tool_github_failed','tool_setup_required','tool_target_ambiguous'].includes(data.action)) {
      projectMessage(data.text, data.action === 'tool_github_failed');
    }
    speak(data.spoken);
    if (data.action === 'design_options' && typeof data.design_prompt === 'string') {
      await generateRequestedDesigns(data.design_prompt,'rules');
    }
  } catch (error) {
    // Errors appear in the shared terminal; never log the raw question.
    showMessage('대화 처리 오류: ' + error.message, 'error');
    displayAssistantReply('요청을 완료하지 못했습니다. 구석의 작업 기록에서 오류를 확인해 주세요.');
  } finally {
    chatBusy = false;
  }
}
$('#command-form').addEventListener('submit',e=>{e.preventDefault();issue($('#command-input').value);});
$('#close-workspace').addEventListener('click',()=>setMode('orb'));
$('#show-variants').addEventListener('click',()=>setMode('variants'));
$('#demo-wake').addEventListener('click',()=>issue('자비스?'));
$('#demo-dashboard').addEventListener('click',()=>issue('자비스, 대시보드 띄워'));
$('#show-memory').addEventListener('click',()=>setMode('memories'));
$('#show-projects').addEventListener('click',()=>setMode('projects'));
$('#back-from-projects').addEventListener('click',()=>setMode('dashboard'));
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
  const validModes = new Set(['orb','dashboard','projects','variants','memories','screen']);
  if (!validModes.has(reply.mode) || typeof reply.text !== 'string') return;
  if (['chat_context','chat_local_status','chat_reply','chat_unavailable',
       'memory_search','chat_reset','project_overview','tool_github_checked',
         'tool_github_failed','tool_setup_required','tool_target_ambiguous'].includes(reply.action)) {
    displayAssistantReply(reply.text);
  } else {
    hideAssistantReply();
  }
  if (reply.action === 'unsupported') {
    showMessage('지원하지 않는 명령입니다. 아무 작업도 실행하지 않았습니다.', 'warning');
  }
  void refreshDashboardData();
  if (reply.action === 'wake') summon();
  setMode(reply.mode);
  if (reply.mode === 'projects' && ['project_overview','tool_github_checked',
       'tool_github_failed','tool_setup_required','tool_target_ambiguous'].includes(reply.action)) {
    projectMessage(reply.text, reply.action === 'tool_github_failed');
  }
  if (reply.action === 'design_options' && typeof reply.design_prompt === 'string') {
    void generateRequestedDesigns(reply.design_prompt, 'rules');
  }
};


/* Live localhost-backed operational facts. Never show invented counters. */
/* The base screen has no visible connection/capability cards.
   We only poll real local activity into the tiny terminal. */
async function refreshDashboardData() {
  if (document.visibilityState !== 'visible') return;
  try {
    const [statusRes, activityRes] = await Promise.all([
      fetch('/api/status', {cache: 'no-store'}),
      fetch('/api/activity', {cache: 'no-store'}),
    ]);
    if (!statusRes.ok || !activityRes.ok) throw new Error('local service unavailable');
    const events = await activityRes.json();
    const brainConsent = $('#brain-consent-wrap');
    const ready = Boolean((await statusRes.json()).brain?.remote_configured);
    brainConsent.hidden = !ready;
    if (!ready) $('#brain-remote-consent').checked = false;
    window.JarvisTerminal?.setConnection('connected');
    window.JarvisTerminal?.syncActivity(events.items);
  } catch {
    $('#brain-consent-wrap').hidden = true;
    $('#brain-remote-consent').checked = false;
    window.JarvisTerminal?.setConnection('disconnected');
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


/* Projects are explicitly user-managed local records. Read-only GitHub checks
   require clicking a project-specific button; no implicit remote requests. */
const projectStatusLabels = Object.freeze({
  todo:'예정', doing:'진행', blocked:'막힘', done:'완료'
});
function pText(tag, text, cls='') {
  const el=document.createElement(tag);
  if (cls) el.className=cls;
  el.textContent=String(text ?? '');
  return el;
}
async function projectRequest(path, payload) {
  const response=await fetch(path,{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify(payload)
  });
  const data=await response.json();
  if (!response.ok) throw new Error(data.error || '로컬 기록 요청 실패');
  return data;
}
function projectMessage(message, isError=false) {
  const el=$('#projects-message');
  el.textContent=String(message);
  el.classList.toggle('error',isError);
}
async function loadProjects() {
  try {
    const r=await fetch('/api/projects',{cache:'no-store'});
    if (!r.ok) throw new Error('프로젝트 기록을 읽을 수 없습니다.');
    const data=await r.json();
    renderProjects(data.items || []);
  } catch(error) {
    projectMessage(error.message,true);
  }
}
function renderProjects(projects) {
  const target=$('#project-list');target.replaceChildren();
  if (!projects.length) {
    target.append(pText('p','아직 등록한 프로젝트가 없습니다. 직접 기록할 때부터 상태가 관리됩니다.','projects-empty'));
    return;
  }
  for (const project of projects) {
    const card=document.createElement('article');card.className='project-entry';
    const head=document.createElement('div');head.className='project-head';
    const title=pText('h4',project.name);
    const provenance=pText('small','사용자 기록 · '+project.updated_at.slice(0,16));
    head.append(title,provenance);card.append(head);
    if (project.goal) card.append(pText('p',project.goal,'project-goal'));
    const tasks=project.task_counts||{};
    card.append(pText('p',
      '예정 '+(tasks.todo||0)+' · 진행 '+(tasks.doing||0)+
      ' · 막힘 '+(tasks.blocked||0)+' · 완료 '+(tasks.done||0),
      'project-counts'));
    const list=document.createElement('div');list.className='project-tasks';
    for (const task of project.tasks||[]) {
      const row=document.createElement('div');row.className='project-task';
      row.append(pText('span',task.title,'project-task-name'));
      const select=document.createElement('select');
      select.setAttribute('aria-label',task.title+' 상태 변경');
      for (const [key,label] of Object.entries(projectStatusLabels)) {
        const opt=document.createElement('option');opt.value=key;opt.textContent=label;
        select.append(opt);
      }
      select.value=task.status;
      select.addEventListener('change',async()=>{
        const previous=task.status;select.disabled=true;
        try {
          await projectRequest('/api/projects/status',{
            project_id:project.id,task_id:task.id,status:select.value
          });
          projectMessage('작업 상태를 직접 기록했습니다. GitHub 검증과는 별개입니다.');
          await loadProjects();
        } catch(error) {
          select.value=previous;projectMessage(error.message,true);
        } finally {select.disabled=false;}
      });
      row.append(select);list.append(row);
    }
    card.append(list);
    const add=document.createElement('form');add.className='project-task-add';
    const name=document.createElement('input');name.required=true;name.maxLength=200;
    name.placeholder='다음 작업 입력';name.setAttribute('aria-label',project.name+' 새 작업');
    const submit=document.createElement('button');submit.type='submit';
    submit.className='line-btn';submit.textContent='+ 작업';
    add.append(name,submit);
    add.addEventListener('submit',async event=>{
      event.preventDefault();
      if (!name.value.trim()) return;
      submit.disabled=true;
      try {
        await projectRequest('/api/projects/task',{project_id:project.id,title:name.value.trim()});
        projectMessage('새 작업을 예정 상태로 저장했습니다.');
        await loadProjects();
      } catch(error){projectMessage(error.message,true);}
      finally {submit.disabled=false;}
    });
    card.append(add);
    const evidence=document.createElement('div');evidence.className='project-evidence';
    const last=project.last_check;
    if (last) {
      const shortHash=last.head_sha.slice(0,8);
      evidence.append(pText('p','GitHub 직접 확인 · '+last.checked_at+' · '+
        last.branch+' @ '+shortHash,'project-checked'));
      evidence.append(pText('p','Workflow '+last.workflow_state+' / '+last.workflow_conclusion+
        ' · 이 결과만으로 작업 완료를 판정하지 않습니다.','project-check-result'));
      if (last.workflow_url && /^https:\/\/github\.com\//.test(last.workflow_url)) {
        const link=document.createElement('a');
        link.href=last.workflow_url;link.target='_blank';link.rel='noopener noreferrer';
        link.textContent='확인한 Workflow 열기';evidence.append(link);
      }
    } else {
      evidence.append(pText('p',project.repo_full_name
        ? 'GitHub 아직 확인하지 않음'
        : '연결된 외부 확인 기록 없음','project-unchecked'));
    }
    if (project.repo_full_name) {
      const check=document.createElement('button');check.type='button';
      check.textContent='GitHub 공개 저장소 직접 확인';check.className='project-check-btn';
      check.addEventListener('click',async()=>{
        check.disabled=true;
        projectMessage('사용자가 요청한 GitHub 공개 API 확인 중…');
        try {
          await projectRequest('/api/projects/github/check',{project_id:project.id});
          projectMessage('GitHub의 현재 커밋과 Workflow 결과를 구분하여 기록했습니다.');
          await loadProjects();
        } catch(error){projectMessage('GitHub 확인 실패: '+error.message,true);}
        finally {check.disabled=false;}
      });
      evidence.append(check);
    }
    card.append(evidence);target.append(card);
  }
}
$('#new-project-form').addEventListener('submit',async event=>{
  event.preventDefault();
  const form=event.currentTarget;
  const button=form.querySelector('button[type=submit]');
  button.disabled=true;
  try {
    const data=await projectRequest('/api/projects',{
      name:$('#new-project-name').value.trim(),
      goal:$('#new-project-goal').value.trim(),
      repo:$('#new-project-repo').value.trim()
    });
    form.reset();$('#new-project-details').open=false;
    projectMessage(data.project.name+' 프로젝트를 등록했습니다. 상태는 아직 사용자가 기록한 내용입니다.');
    await loadProjects();
  } catch(error){projectMessage(error.message,true);}
  finally {button.disabled=false;}
});
