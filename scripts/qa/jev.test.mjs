import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, fixtures, fixtureContract, prepareCorpus, budget, summary } from './jev.mjs';
import { main, parseArgs } from '../test.mjs';

const pin = JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts/qa/jev-pin.json')));
function nativeEvidence() {
  return { complete: true, fixtureSHA256: pin.fixture_sha256, cases: fixtures().map((f) => ({
    id: f.id, candidateCount: 1, outcome: 'used_on_device_model',
    segments: f.kept_indices.map((i) => structuredClone(f.segments[i]))
  })) };
}

test('reviewed synthetic corpus produces native cases and paired controls only', () => {
  const corpus = prepareCorpus(nativeEvidence());
  assert.equal(corpus.length, 33);
  assert.equal(corpus.filter((c) => c.expected).length, 22);
  assert.ok(corpus.every((c) => !c.deterministicFailures.length));
  assert.equal(budget(corpus).questions, 35);
});

test('changed fixtures require an explicit review of their allowlist hash', () => {
  assert.throws(() => fixtures(Buffer.from('[]')), /corpus changed/);
});

test('regression suite is independently pinned and cannot be confused with baseline evidence', () => {
  const rows = fixtures(undefined, 'regressions');
  assert.equal(rows.length, 20);
  assert.throws(() => fixtures(Buffer.from('[]'), 'regressions'));
  assert.throws(() => fixtureContract('../private'));
  assert.throws(() => parseArgs(['--suite=../private']));
  assert.throws(() => parseArgs(['--offline', '--suite=regressions']));
  const evidence = { complete: true, suite: 'regressions', fixtureSHA256: fixtureContract('regressions').hash,
    cases: rows.map(f => ({ id: f.id, candidateCount: 0, outcome: 'not_needed', segments: f.segments })) };
  const corpus = prepareCorpus(evidence, rows, 'regressions');
  assert.equal(corpus.length, 60);
  assert.equal(budget(corpus).questions, 66);
  assert.throws(() => prepareCorpus(evidence));
  evidence.suite = 'baseline';
  assert.throws(() => prepareCorpus(evidence, rows, 'regressions'));
});

test('all provenance and output checks run before an evaluator can authenticate', () => {
  const mutations = [
    (e) => { e.complete = false; },
    (e) => { e.fixtureSHA256 = 'wrong'; },
    (e) => { e.cases.pop(); },
    (e) => { e.cases[0].id = e.cases[1].id; },
    (e) => { e.cases[0].candidateCount = -1; },
    (e) => { e.cases[0].segments[0].text += ' PRIVATE_CONTENT'; },
    (e) => { e.cases[0].segments[0].speaker = 'private-name'; },
    (e) => { e.cases[0].segments[0].start_ms++; },
    (e) => { e.cases[0].segments.push(e.cases[0].segments[0]); },
    (e) => { e.cases[0].segments[0].text = ''; },
    (e) => { e.cases[0].segments[0].text = 'left. the to box blue the move please Um,'; }
  ];
  for (const mutate of mutations) {
    const evidence = nativeEvidence();
    mutate(evidence);
    assert.throws(() => prepareCorpus(evidence));
  }
});

test('outgoing candidates are rebuilt from fixture tokens without extra native metadata', () => {
  const evidence = nativeEvidence();
  evidence.privatePath = '/private/LOCAL_ONLY';
  evidence.environment = { variant: 'general', appleModel: { name: 'LOCAL_ONLY' } };
  evidence.cases[0].segments[0].privateMetadata = 'LOCAL_ONLY';
  evidence.cases[0].segments[0].text = 'please move the blue box to the left.';
  const corpus = prepareCorpus(evidence);
  assert.ok(!JSON.stringify(corpus).includes('LOCAL_ONLY'));
  assert.match(corpus[0].candidate, /please move the blue box/);
});

test('native fallback, protected speech changes and retained echoes cannot be hidden by Jev', () => {
  const evidence = nativeEvidence();
  evidence.cases[0].outcome = 'model_not_ready';
  evidence.cases.find((c) => c.id === 'numeric-repeat').segments[0].text = 'The code is 5 2 and costs 20 dollars.';
  evidence.cases.find((c) => c.id === 'aligned-echo').segments = fixtures().find((f) => f.id === 'aligned-echo').segments;
  const corpus = prepareCorpus(evidence);
  assert.equal(corpus.filter((c) => c.deterministicFailures.length).length, 3);
  const report = passingReport(corpus);
  assert.equal(summary(report, corpus).combinedPass, false);
  assert.equal(summary(report, corpus).native.fail, 3);
});

function passingReport(corpus) {
  return { complete: true, cases: corpus.map((c) => ({ id: c.id, result: { findings: Object.fromEntries(Object.keys(c.requirements).map((key) => [key, { decision: c.expected || 'pass' }])) } })) };
}

test('incomplete reports, borderline findings, and confident control mistakes prevent a combined pass', () => {
  const corpus = prepareCorpus(nativeEvidence());
  const report = passingReport(corpus);
  assert.equal(summary(report, corpus).combinedPass, true);
  report.complete = false;
  assert.equal(summary(report, corpus).combinedPass, false);
  report.complete = true;
  report.cases[0].result.findings.meaning.decision = 'review';
  report.cases[2].result.findings.meaning.decision = 'pass';
  const result = summary(report, corpus);
  assert.equal(result.native.review, 1);
  assert.equal(result.controls.falsePass, 1);
  assert.equal(result.combinedPass, false);
});

test('spending and question budgets fail before live calls', () => {
  const corpus = prepareCorpus(nativeEvidence());
  for (const limit of [0, -1, 2, NaN, Infinity, 0.001]) assert.throws(() => budget(corpus, limit));
  assert.throws(() => budget(Array(101).fill(corpus[1]), 1));
});

test('default workflow includes Jev, and custom transcript/evidence paths are not accepted', () => {
  assert.deepEqual(parseArgs([]), { offline: false, dryRun: false, qualityOnly: false, suite: 'baseline', appleVariant: 'production', maxEstimatedUsd: 0.25 });
  for (const args of [['--offline', '--dry-run'], ['--offline', '--quality-only'], ['--fixtures=private.json'], ['--evidence-dir=private'], ['--max-estimated-usd=NaN']]) assert.throws(() => parseArgs(args));
});

test('offline mode uses the existing validation entrypoint and never invokes inference', async () => {
  const calls = [];
  const result = await main(['--offline'], {
    run: async (...args) => { calls.push(args); return 0; },
    evaluate: async () => { throw new Error('Unexpected evaluator'); }
  });
  assert.equal(result, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], './scripts/ci/validate.sh');
  assert.equal(calls[0][2].RECORD_JEV_OUTPUT, undefined);
  assert.equal(calls[0][2].CLOUDFLARE_API_TOKEN, undefined);
  assert.equal(calls[0][2].CLOUDFLARE_ACCOUNT_ID, undefined);
});

test('Cloudflare credentials are not inherited by validation or native test processes', async () => {
  const before = process.env.CLOUDFLARE_API_TOKEN;
  process.env.CLOUDFLARE_API_TOKEN = 'synthetic-token';
  let output;
  try {
    await main([], {
      run: async (_command, _args, env) => {
        assert.equal(env.CLOUDFLARE_API_TOKEN, undefined);
        if (env.RECORD_JEV_OUTPUT) output = path.dirname(env.RECORD_JEV_OUTPUT);
        return 0;
      },
      evaluate: async () => { assert.equal(process.env.CLOUDFLARE_API_TOKEN, 'synthetic-token'); return 0; }
    });
  } finally {
    if (before === undefined) delete process.env.CLOUDFLARE_API_TOKEN;
    else process.env.CLOUDFLARE_API_TOKEN = before;
    if (output) fs.rmSync(output, { recursive: true });
  }
});

test('deterministic failures stop the workflow without asking Jev to override them', async () => {
  assert.equal(await main([], { run: async () => 1, evaluate: async () => { throw new Error('Unexpected evaluator'); } }), 1);
});

test('Apple variants are explicit and ambient probe settings cannot alter validation', async () => {
  assert.equal(parseArgs([]).appleVariant, 'production');
  for (const value of ['baseline', 'general', 'general-boolean', 'general-sentence']) {
    assert.equal(parseArgs([`--apple-variant=${value}`]).appleVariant, value);
  }
  assert.throws(() => parseArgs(['--apple-variant=private-transcript']));
  assert.throws(() => parseArgs(['--offline', '--apple-variant=general']));
  const before = process.env.RECORD_JEV_VARIANT;
  process.env.RECORD_JEV_VARIANT = 'general-boolean';
  let output;
  try {
    await main(['--apple-variant=general'], {
      run: async (command, _args, env) => {
        assert.equal(env.RECORD_JEV_VARIANT, command === 'swift' ? 'general' : undefined);
        if (env.RECORD_JEV_OUTPUT) output = path.dirname(env.RECORD_JEV_OUTPUT);
        return 0;
      },
      evaluate: async () => 0
    });
    assert.equal(JSON.parse(fs.readFileSync(path.join(output, 'workflow.json'))).appleVariant, 'general');
  } finally {
    if (before === undefined) delete process.env.RECORD_JEV_VARIANT;
    else process.env.RECORD_JEV_VARIANT = before;
    if (output) fs.rmSync(output, { recursive: true });
  }
});

test('default and dry-run workflow propagate incomplete native evidence and quality findings', async () => {
  for (const [args, nativeExit, evaluationExit, expected] of [[[], 0, 1, 1], [['--dry-run'], 0, 0, 0], [[], 2, 0, 2]]) {
    let output;
    let evaluated = false;
    const calls = [];
    try {
      const result = await main(args, {
        run: async (command, argv, env) => {
          calls.push(command);
          if (command === 'swift') { output = path.dirname(env.RECORD_JEV_OUTPUT); return nativeExit; }
          return 0;
        },
        evaluate: async (_output, options) => { evaluated = true; assert.equal(options.dryRun, args.includes('--dry-run')); return evaluationExit; }
      });
      assert.equal(result, expected);
      assert.deepEqual(calls, ['./scripts/ci/validate.sh', 'swift']);
      assert.equal(evaluated, nativeExit === 0);
      const workflow = JSON.parse(fs.readFileSync(path.join(output, 'workflow.json')));
      assert.equal(workflow.releaseAccepted, false);
    } finally { if (output) fs.rmSync(output, { recursive: true }); }
  }
});
