import { copyFile } from 'node:fs/promises';
import path from 'node:path';
const relay = process.argv[2];
if (!relay) throw new Error('Pass the existing crash-relay directory.');
for (const name of ['record-contract.mjs', 'record-aggregation.js']) {
  await copyFile(new URL(`../integrations/crash-relay/${name}`, import.meta.url), path.join(relay, 'src', name));
}
