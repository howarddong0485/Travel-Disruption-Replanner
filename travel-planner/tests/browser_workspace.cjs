const {randomUUID} = require('node:crypto');

// In UI tests the API fixture client and the browser represent the same visitor.
async function browserWorkspace(page, key = randomUUID()) {
  await page.addInitScript(value => localStorage.setItem('jacroam.private-workspace.v1', value), key);
  return key;
}

module.exports = {browserWorkspace};
