const allowed = [
  ['instagram', u => u.hostname === 'www.instagram.com' && u.pathname.replace(/\/$/, '') === '/dechive.wiki'],
  ['threads', u => (u.hostname === 'www.threads.com' || u.hostname === 'threads.com') && u.pathname.replace(/\/$/, '') === '/@dechive.wiki'],
  ['facebook', u => u.hostname === 'www.facebook.com' && u.pathname === '/profile.php' && u.searchParams.get('id') === '1433547446509432'],
  ['youtube', u => u.hostname === 'www.youtube.com' && /^\/channel\/UC[A-Za-z0-9_-]{10,60}\/?$/.test(u.pathname)],
];
export function safeChannel(raw) {
  try {
    const u = new URL(raw);
    if (u.protocol !== 'https:' || u.username || u.password) return null;
    return allowed.find(([, test]) => test(u))?.[0] || null;
  } catch { return null; }
}
export function summarizePages(toolResult) {
  const text = (toolResult.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n');
  const out = new Set();
  // Never log or return unrelated tab URLs, titles, or tool output.
  for (const line of text.split('\n')) {
    const match = line.match(/^\s*\d+:\s+(https:\/\/\S+)/);
    if (!match) continue;
    const channel = safeChannel(match[1]);
    if (channel) out.add(channel);
  }
  return [...out].sort();
}
