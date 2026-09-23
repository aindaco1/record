// Developer-only adapter. No product target imports this file.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

export class EvaluationError extends Error {}

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const POLICY = { minimumMargin: 0.10, models: ['jev-1.13.0'] };
export const INPUT_RATE = 0.042; // USD/million input tokens, TypeSafe, 2026-09-23; estimate only.
export const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const readJSON = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const pin = readJSON(path.join(ROOT, 'scripts/qa/jev-pin.json'));

export function configuration() {
  const file = path.join(ROOT, '.record-development.json');
  return fs.existsSync(file) ? readJSON(file) : {};
}

export async function sharedEvaluator(config = configuration()) {
  const root = process.env.RECORD_TEST_CORE_ROOT || config.test_core_root || path.join(ROOT, 'shared/dust-wave-platform');
  if (!root || !path.isAbsolute(root)) throw new EvaluationError('Configure an absolute RECORD_TEST_CORE_ROOT; see docs/testing/jev.md');
  const revision = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  if (revision !== pin.revision) throw new EvaluationError('Shared Jev revision does not match the reviewed pin');
  for (const [file, expected] of Object.entries(pin.files)) {
    if (sha256(fs.readFileSync(path.join(root, file))) !== expected) throw new EvaluationError('Shared Jev source differs from the reviewed pin');
  }
  return import(pathToFileURL(path.join(root, 'packages/test-core/src/jev.js')).href);
}

export function fixtureContract(suite = 'baseline') {
  if (suite === 'baseline') return { file: 'scripts/qa/fixtures/transcript-cleanup.json', hash: pin.fixture_sha256 };
  if (suite === 'regressions') return { file: 'scripts/qa/fixtures/transcript-cleanup-regressions.json', hash: pin.regression_fixture_sha256 };
  throw new EvaluationError('Unknown synthetic suite');
}

export function fixtures(bytes, suite = 'baseline') {
  const contract = fixtureContract(suite);
  bytes ??= fs.readFileSync(path.join(ROOT, contract.file));
  if (sha256(bytes) !== contract.hash) throw new EvaluationError('Synthetic corpus changed; review and update its hash before evaluation');
  return JSON.parse(bytes);
}

const rendered = (segments) => segments.map((s) => `${s.speaker} [${s.start_ms}-${s.end_ms} ms]: ${s.text}`).join('\n');

// Reconstruct outgoing text using only allowlisted fixture tokens. Never send raw
// saved evidence, paths, runtime metadata, unknown words, or custom input files.
function publicSegments(fixture, segments) {
  if (!Array.isArray(segments) || !segments.length) throw new EvaluationError('Native output has no segments');
  const indices = [];
  const safe = segments.map((segment) => {
    const index = fixture.segments.findIndex((s) => s.speaker === segment.speaker && s.start_ms === segment.start_ms && s.end_ms === segment.end_ms);
    if (index < 0 || indices.includes(index) || typeof segment.text !== 'string') throw new EvaluationError('Native output has unknown or duplicate segment metadata');
    indices.push(index);
    const source = fixture.segments[index];
    const tokens = source.text.split(/\s+/);
    const selected = segment.text.trim().split(/\s+/);
    let cursor = 0;
    const safeTokens = selected.map((token) => {
      while (cursor < tokens.length && tokens[cursor] !== token) cursor++;
      if (cursor === tokens.length) throw new EvaluationError('Native output contains text outside the synthetic source');
      return tokens[cursor++];
    });
    return { ...source, text: safeTokens.join(' ') };
  });
  const failures = [];
  if (JSON.stringify(indices) !== JSON.stringify(fixture.kept_indices)) failures.push('Unexpected echo removal, retained echo, or reordered segments');
  for (const index of fixture.preserve_indices) {
    if (safe[indices.indexOf(index)]?.text !== fixture.segments[index].text) failures.push('Protected numeric, overlapping, or echo-control speech changed');
  }
  return { safe, failures };
}

export function prepareCorpus(evidence, publicFixtures = fixtures(), suite = 'baseline') {
  if (!evidence || (evidence.suite || 'baseline') !== suite || evidence.complete !== true || evidence.fixtureSHA256 !== fixtureContract(suite).hash ||
      !Array.isArray(evidence.cases) || evidence.cases.length !== publicFixtures.length ||
      new Set(evidence.cases.map((c) => c.id)).size !== publicFixtures.length) throw new EvaluationError('Incomplete native evidence or synthetic corpus hash mismatch');
  const rows = [];
  for (const fixture of publicFixtures) {
    const result = evidence.cases.find((c) => c.id === fixture.id);
    if (!result || !Number.isSafeInteger(result.candidateCount) || result.candidateCount < 0) throw new EvaluationError('Missing native case or candidate count');
    const { safe, failures } = publicSegments(fixture, result.segments);
    if (result.outcome !== (result.candidateCount ? 'used_on_device_model' : 'not_needed')) failures.push('Native Apple adviser did not complete');
    rows.push({ id: fixture.id, candidate: rendered(safe), reference: rendered(fixture.segments), requirements: fixture.requirements, deterministicFailures: failures });
    for (const expected of ['pass', 'fail']) {
      rows.push({ id: `${fixture.id}-control-${expected}`, candidate: fixture.control[`${expected}_candidate`],
        requirements: { meaning: fixture.control.requirement }, expected, deterministicFailures: [] });
    }
  }
  return rows;
}

export function budget(corpus, limit = 0.25) {
  const questions = corpus.reduce((n, c) => n + Object.keys(c.requirements).length, 0);
  const reservedEstimateUsd = questions * 32_000 * INPUT_RATE / 1_000_000;
  if (!Number.isFinite(limit) || limit <= 0 || limit > 1 || questions > 100 || reservedEstimateUsd > limit) throw new EvaluationError('Question or estimated spending limit exceeded');
  return { questions, reservedEstimateUsd, maximumEstimatedUsd: limit, inputUsdPerMillion: INPUT_RATE };
}

function decisionFor(item, result) {
  const findings = result?.findings || {};
  const decisions = Object.keys(item.requirements).map((key) => findings[key]?.decision);
  if (decisions.some((decision) => !['pass', 'fail', 'review'].includes(decision))) return 'unevaluated';
  return decisions.includes('fail') ? 'fail' : decisions.includes('review') ? 'review' : 'pass';
}

export function summary(report, corpus) {
  const counts = { native: { pass: 0, fail: 0, review: 0, unevaluated: 0 }, controls: { correct: 0, falsePass: 0, falseFailure: 0, review: 0, unevaluated: 0 } };
  const blockers = new Set();
  if (!report.complete) blockers.add('evaluation_incomplete');
  for (const item of corpus) {
    const decision = decisionFor(item, report.cases.find((c) => c.id === item.id)?.result);
    if (decision === 'unevaluated') blockers.add('evaluation_incomplete');
    if (item.expected) {
      counts.controls[decision === 'unevaluated' || decision === 'review' ? decision : decision === item.expected ? 'correct' : decision === 'pass' ? 'falsePass' : 'falseFailure']++;
      if (decision !== item.expected && decision !== 'unevaluated') blockers.add('judge_controls');
    } else {
      counts.native[item.deterministicFailures.length ? 'fail' : decision]++;
      if (item.deterministicFailures.length) blockers.add('product_exact_native');
      if (decision === 'fail' || decision === 'review') blockers.add('product_jev');
    }
  }
  const productPass = counts.native.pass === corpus.filter((c) => !c.expected).length;
  const controlsPass = counts.controls.correct === corpus.filter((c) => c.expected).length;
  return { ...counts, productPass, controlsPass, blockingReasons: [...blockers], combinedPass: report.complete && productPass && controlsPass };
}

function credentials(config) {
  const accountId = process.env.CLOUDFLARE_ACCOUNT_ID || config.cloudflare_account_id;
  if (!/^[a-fA-F0-9]{32}$/.test(accountId || '')) throw new EvaluationError('Set CLOUDFLARE_ACCOUNT_ID or local cloudflare_account_id');
  let token = process.env.CLOUDFLARE_API_TOKEN;
  if (!token) {
    try {
      const auth = JSON.parse(execFileSync('npx', ['--no-install', 'wrangler@4.136.2', 'auth', 'token', '--json'], { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 45_000 }));
      token = auth.token || auth.access_token;
    } catch { throw new EvaluationError('Existing Wrangler authentication unavailable; no credential output shown'); }
  }
  if (typeof token !== 'string' || !token.trim()) throw new EvaluationError('Cloudflare token unavailable');
  return { accountId, token };
}

export function review(report, corpus) {
  const { native, controls, productPass, controlsPass, blockingReasons } = report.summary;
  const lines = ['# Record transcript cleanup evaluation', '', `Complete: ${report.complete}. Combined pass: ${report.summary.combinedPass}. Network attempts: ${report.networkAttempts}.`, '',
    `Product cases (exact/native checks and Jev): ${native.pass}/${corpus.filter((c) => !c.expected).length} passing.`,
    `Judge controls: ${controls.correct}/${corpus.filter((c) => c.expected).length} correct; ${controls.falsePass} false passes, ${controls.falseFailure} false failures, ${controls.review} reviews, ${controls.unevaluated} unevaluated.`, '',
    ...(blockingReasons.length ? [`Blocking reasons: ${blockingReasons.join(', ')}.`, ''] : []),
    ...(report.complete && productPass && !controlsPass ? ['All product cases passed in this run. Judge controls block the combined pass; their deliberately good/bad examples are not Record outputs.', ''] : []),
    'The probability margin is provisional. Controls are engineering labels, not independent calibration. This is not capture, ASR, hardware or release acceptance.', ''];
  for (const item of corpus) {
    const result = report.cases.find((c) => c.id === item.id);
    const flagged = Object.keys(item.requirements).filter((key) => result?.result?.findings?.[key]?.decision !== (item.expected || 'pass'));
    if (!flagged.length && !item.deterministicFailures.length) continue;
    lines.push(`## ${item.expected ? 'Judge control' : 'Product output'}: ${item.id}`, '', ...item.deterministicFailures.map((f) => `- Exact/native failure: ${f}`),
      ...flagged.map((key) => {
        const finding = result?.result?.findings?.[key];
        return `- ${key}: expected ${item.expected || 'pass'}; Jev ${finding?.decision || 'unevaluated'}. ${item.requirements[key]}` +
          (finding ? ` Probabilities: ${JSON.stringify(finding.probabilities)}; margin: ${finding.margin}.` : ' Jev result unavailable.');
      }), '', ...item.candidate.split('\n').map((line) => `> ${line}`), '');
  }
  return lines.join('\n');
}

export async function evaluate(output, { dryRun = false, maxEstimatedUsd = 0.25, suite = 'baseline' } = {}) {
  const evidence = readJSON(path.join(output, 'native.json'));
  const corpus = prepareCorpus(evidence, fixtures(undefined, suite), suite);
  const spending = budget(corpus, maxEstimatedUsd);
  const config = configuration();
  const shared = await sharedEvaluator(config);
  // Validate all request payloads before credential discovery, including controls.
  for (const row of corpus) shared.createJevRequest(row.candidate, row.requirements, { reference: row.reference });
  const sourceFiles = ['scripts/qa/jev.mjs', 'scripts/qa/jev-pin.json', fixtureContract(suite).file, 'Tests/RecordTests/TranscriptJevProbeTests.swift',
    'Tests/RecordTests/TranscriptAdviserExperiment.swift', 'Sources/RecordCore/TranscriptRefinement.swift', 'Sources/RecordCore/TranscriptEchoSuppressor.swift', 'Sources/Record/Transcription/FoundationModelTranscriptAdviser.swift', 'Sources/Record/Transcription/TranscriptionCoordinator.swift',
    'shared/dust-wave-platform/native/Sources/DustWaveAppleIntelligence/AppleGeneration.swift'];
  const metadata = { createdAt: new Date().toISOString(), suite, sharedRevision: pin.revision, policyCalibrated: false, ...spending,
    sourceHashes: Object.fromEntries(sourceFiles.map((f) => [f, sha256(fs.readFileSync(path.join(ROOT, f)))])),
    corpusSha256: sha256(JSON.stringify(corpus)), nativeEnvironment: evidence.environment || null };
  fs.writeFileSync(path.join(output, 'corpus.json'), JSON.stringify(corpus, null, 2) + '\n', { flag: 'wx' });
  const onProgress = async (report) => {
    const saved = { ...report, ...metadata, summary: summary(report, corpus) };
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(saved, null, 2) + '\n');
    fs.writeFileSync(path.join(output, 'review.md'), review(saved, corpus));
  };
  let report = await shared.evaluateJevCases(corpus, { policy: POLICY, maxQuestions: 100, onProgress });
  if (!dryRun) {
    let auth;
    try { auth = credentials(config); } catch {
      report.error = 'Cloudflare authentication unavailable; see developer setup. No requests sent.';
      await onProgress(report);
      return 2;
    }
    report = await shared.evaluateJevCases(corpus, { policy: POLICY, maxQuestions: 100, onProgress, call: (payload) => shared.callCloudflareJev(payload, auth) });
  }
  const result = summary(report, corpus);
  console.log(JSON.stringify({ output, complete: report.complete, networkAttempts: report.networkAttempts, ...spending, ...result }, null, 2));
  return dryRun ? (corpus.some((c) => c.deterministicFailures.length) ? 1 : 0) : !report.complete ? 2 : result.combinedPass ? 0 : 1;
}
