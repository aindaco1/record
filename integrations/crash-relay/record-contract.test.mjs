import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validateRecordReport, recordFingerprint, recordRelayReport } from './record-contract.mjs';
const sample = () => JSON.parse(readFileSync(new URL('../../Tests/Fixtures/record-diagnostic.json', import.meta.url)));
test('shared Swift fixture is accepted and stays in the Record repository projection', () => {
  const r = sample(); assert.equal(validateRecordReport(r), r);
  const projected = recordRelayReport(r);
  assert.equal(projected.app.identifier, 'com.aindaco.record');
  assert.deepEqual(projected.report.context.recordDiagnostics, r);
  assert.equal(projected.report.stack, '');
});
test('rejects private fields, invalid enums and inconsistent crash summaries', () => {
  for (const mutate of [r=>r.path='/Users/private', r=>r.state.events=['private'], r=>r.state.activity='secret',
    r=>r.state.events=Array(21).fill('launch'), r=>r.application.build='private', r=>r.state.transcriptCleanup=1,
    r=>r.crash={}, r=>r.kind='native_crash', r=>r.application.architecture='private']) {
    const r=sample(); mutate(r); assert.throws(()=>validateRecordReport(r));
  }
});
test('grouping ignores IDs and uses incident build rather than current settings for crashes', async () => {
  const r=sample(), other=sample(); other.id=crypto.randomUUID();
  assert.equal(await recordFingerprint(r),await recordFingerprint(other));
  r.kind='native_crash'; r.crash={exception:'EXC_CRASH',signal:'SIGABRT',image:'record',imageOffset:8,
    version:r.application.version,build:r.application.build,operatingSystem:r.application.operatingSystem};
  const copy=structuredClone(r); copy.state.activity='paused';
  assert.equal(await recordFingerprint(r),await recordFingerprint(copy));
  copy.crash.build='123'; assert.throws(()=>validateRecordReport(copy));
});
