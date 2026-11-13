// Run from any directory: node tests/run.js
'use strict';
const { readdirSync } = require('node:fs');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');

const root = resolve(__dirname, '..');
const definitions = readdirSync(resolve(root, 'achievements'), { withFileTypes: true })
    .filter((file) => file.isFile() && file.name.endsWith('.lua'))
    .map((file) => 'achievements/' + file.name);

for (const [command, args] of [
    ['lua', ['tests/server_spec.lua', ...definitions]],
    ['lua', ['tests/client_spec.lua']],
    [process.execPath, ['--check', 'ui/app.js']],
]) {
    const result = spawnSync(command, args, { cwd: root, stdio: 'inherit' });
    if (result.error) console.error(result.error.message);
    if (result.status !== 0) process.exit(result.status || 1);
}
