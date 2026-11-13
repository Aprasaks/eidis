'use strict';
/* JARVIS CONSOLE v1.0
   A single *local* chronological view. Server entries are metadata only, never
   raw user prompts, voice transcripts, file contents, or screen captures.
   This does not collect operating-system terminal or background process logs. */
(() => {
  const feed = document.getElementById('terminal-feed');
  const panel = document.getElementById('system-terminal');
  const toggle = document.getElementById('terminal-toggle');
  const content = document.getElementById('terminal-content');
  const count = document.getElementById('terminal-count');
  const connection = document.getElementById('terminal-connection');
  const maximum = 160;
  const entries = [];
  const seenServerIDs = new Set();
  let filter = 'all';
  let connected = null;
  let expanded = false;

  const names = Object.freeze({
    wake: '음성/텍스트 호출 인식',
    open_dashboard: '작업 공간 열기',
    close_workspace: '작업 공간 닫기',
    design_options: '디자인 시안 열기',
    design_suggestions: '디자인 설정 생성',
    remember: '기억 저장 완료',
    recall: '저장한 기억 조회',
    screen: '화면 기능 열기',
    status: '로컬 상태 확인',
    unsupported: '지원하지 않는 명령',
  });

  function humanTime(value) {
    const t = value instanceof Date ? value : new Date(value);
    if (!Number.isFinite(t.getTime())) return '--:--:--';
    return t.toLocaleTimeString('ko-KR', {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    });
  }

  function clean(value) {
    return String(value ?? '')
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim().slice(0, 260);
  }

  function render() {
    const nearBottom = feed.scrollTop + feed.clientHeight >= feed.scrollHeight - 55;
    const matching = entries.filter(entry => filter === 'all' ||
      (filter === 'action' && entry.level === 'action') ||
      (filter === 'error' && entry.level === 'error'));
    const fragment = document.createDocumentFragment();

    if (!matching.length) {
      const empty = document.createElement('div');
      empty.className = 'terminal-empty';
      empty.textContent = filter === 'error' ? '오류 없음'
        : filter === 'action' ? '실행 기록 없음'
        : '› _';
      fragment.appendChild(empty);
    }

    for (const entry of matching) {
      const line = document.createElement('div');
      line.className = 'terminal-line terminal-' + entry.level;
      line.dataset.source = entry.source;
      const stamp = document.createElement('time');
      stamp.className = 'terminal-time';
      stamp.textContent = humanTime(entry.time);
      const kind = document.createElement('span');
      kind.className = 'terminal-kind';
      kind.textContent = ({action:'RUN',error:'ERR',warning:'WARN',info:'INFO'})[entry.level] || 'INFO';
      const message = document.createElement('span');
      message.className = 'terminal-message';
      message.textContent = entry.message;
      line.append(stamp, kind, message);
      fragment.appendChild(line);
    }

    feed.replaceChildren(fragment);
    count.textContent = entries.length + ' EVENTS';
    if (nearBottom) feed.scrollTop = feed.scrollHeight;
  }

  function push(message, level = 'info', {source='session', time=new Date()} = {}) {
    const cleanMessage = clean(message);
    if (!cleanMessage) return;
    const safeLevel = ['info','action','warning','error'].includes(level) ? level : 'info';
    entries.push({level:safeLevel,message:cleanMessage,source,time});
    if (entries.length > maximum) entries.splice(0, entries.length - maximum);
    render();
  }

  function syncActivity(items) {
    if (!Array.isArray(items)) return;
    const ordered = items.filter(item => Number.isInteger(item?.id) && item.id > 0)
      .sort((a,b) => a.id - b.id);
    for (const item of ordered) {
      if (seenServerIDs.has(item.id)) continue;
      seenServerIDs.add(item.id);
      const message = Object.hasOwn(names,item.category) ? names[item.category]
        : '기타 로컬 기록 (' + clean(item.category).slice(0,35) + ')';
      const level = item.category === 'unsupported' ? 'warning' : 'action';
      push(message, level, {source:'local',time:item.created_at});
    }
    if (seenServerIDs.size > 700) {
      const old = [...seenServerIDs].slice(0,seenServerIDs.size - 350);
      for (const key of old) seenServerIDs.delete(key);
    }
  }

  function setConnection(state) {
    if (state !== 'connected' && state !== 'disconnected') return;
    connection.textContent = state === 'connected' ? 'LOCAL / CONNECTED' : 'LOCAL / OFFLINE';
    connection.classList.toggle('offline', state !== 'connected');
    if (connected === state) return;
    connected = state;
    push(state === 'connected' ? '로컬 자비스 서버 연결 확인' : '로컬 자비스 서버에 연결할 수 없습니다.',
      state === 'connected' ? 'info' : 'error');
  }

  function setExpanded(value) {
    expanded = Boolean(value);
    // Both modes show real logs; expanded mode reveals inspection tools.
    document.body.classList.toggle('terminal-expanded', expanded);
    panel.classList.toggle('expanded', expanded);
    content.hidden = false;
    toggle.setAttribute('aria-expanded', String(expanded));
    toggle.textContent = expanded ? '↙' : '⤢';
    toggle.title = expanded ? '작은 기록 창으로' : '작업 기록 크게 보기';
    toggle.setAttribute('aria-label', toggle.title);
    if (expanded) requestAnimationFrame(() => { feed.scrollTop = feed.scrollHeight; });
  }

  toggle.addEventListener('click', () => setExpanded(!expanded));
  for (const button of document.querySelectorAll('[data-terminal-filter]')) {
    button.addEventListener('click', () => {
      filter = button.dataset.terminalFilter;
      for (const item of document.querySelectorAll('[data-terminal-filter]')) {
        const selected = item.dataset.terminalFilter === filter;
        item.classList.toggle('selected', selected);
        item.setAttribute('aria-pressed',String(selected));
      }
      render();
      feed.scrollTop = feed.scrollHeight;
    });
  }
  document.getElementById('terminal-clear').addEventListener('click', () => {
    entries.length = 0;
    // Server history remains intact; IDs stay marked as already seen.
    render();
  });

  setExpanded(expanded);
  window.JarvisTerminal = Object.freeze({push,syncActivity,setConnection,setExpanded});
})();