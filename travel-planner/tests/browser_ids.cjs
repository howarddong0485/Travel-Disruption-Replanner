/** Build travel first, then run: node tests/browser_ids.cjs */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');

const compiled = path.join(__dirname, '..', '.jac', 'client', 'travel', 'compiled');
const prelude = fs.readFileSync(path.join(compiled, 'jac_prelude.js'), 'utf8')
  .replace(/export \{ _jac \};/, '');
const helper = fs.readFileSync(path.join(compiled, 'browser_ids.js'), 'utf8')
  .replace(/import \{ _jac \} from "@jac\/prelude";/, '')
  .replace(/export \{request_id\};/, '');
const requestId = vm.runInNewContext(prelude + '\n' + helper + '\nrequest_id;');
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

assert.equal(requestId({crypto: {randomUUID: () => 'native-id'}}), 'native-id');
assert.equal(requestId({Uint8Array, crypto: {getRandomValues: values => values.fill(0)}}),
  '00000000-0000-4000-8000-000000000000');
const browserWithoutRandomUUID = {
  Uint8Array,
  crypto: {getRandomValues: values => webcrypto.getRandomValues(values)},
};
const ids = Array.from({length: 1000}, () => requestId(browserWithoutRandomUUID));
assert(ids.every(id => uuid.test(id)));
assert.equal(new Set(ids).size, ids.length);
assert.throws(() => requestId({}), /cannot generate a request ID/);
console.log('PASS: native UUID, HTTP fallback, UUID format, uniqueness, and unsupported browser error');
