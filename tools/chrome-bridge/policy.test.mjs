import assert from 'node:assert/strict';
import {safeChannel, summarizePages} from './policy.mjs';
assert.equal(safeChannel('https://www.instagram.com/dechive.wiki/'), 'instagram');
assert.equal(safeChannel('https://www.threads.com/@dechive.wiki'), 'threads');
assert.equal(safeChannel('https://www.facebook.com/profile.php?id=1433547446509432'), 'facebook');
assert.equal(safeChannel('https://www.youtube.com/channel/UC12345678901234567'), 'youtube');
for (const url of ['https://evil.example/login','http://www.instagram.com/dechive.wiki/',
 'https://www.instagram.com/accounts/login/','https://www.instagram.com/another/',
 'https://www.facebook.com/profile.php?id=another', 'file:///Users/test/private',
 'https://www.youtube.com/@someoneelse','javascript:alert(1)']) {
 assert.equal(safeChannel(url), null,url);
}
const data={content:[{type:'text',text:'## Pages\n0: https://www.instagram.com/dechive.wiki/\n1: https://mail.google.com/mail/u/0/\n2: https://www.threads.com/@dechive.wiki\n3: https://www.facebook.com/profile.php?id=1433547446509432'}]};
assert.deepEqual(summarizePages(data),['facebook','instagram','threads']);
assert.equal(JSON.stringify(summarizePages(data)).includes('google.com'),false);
console.log('CHROME_BRIDGE_POLICY_12_CHECKS_PASS');
