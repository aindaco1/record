#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { ROOT, evaluate, EvaluationError } from './qa/jev.mjs';

export function parseArgs(args) {
  const options = { offline: false, dryRun: false, qualityOnly: false, suite: 'baseline', appleVariant: 'production', maxEstimatedUsd: 0.25 };
  for (const arg of args) {
    if (arg === '--offline') options.offline = true;
    else if (arg === '--dry-run') options.dryRun = true;
    else if (arg === '--quality-only') options.qualityOnly = true;
    else if (arg.startsWith('--suite=')) options.suite = arg.slice('--suite='.length);
    else if (arg.startsWith('--apple-variant=')) options.appleVariant = arg.slice('--apple-variant='.length);
    else if (arg.startsWith('--max-estimated-usd=')) options.maxEstimatedUsd = Number(arg.split('=')[1]);
    else throw new Error('Unknown development test argument');
  }
  if ((options.offline && (options.dryRun || options.qualityOnly || options.appleVariant !== 'production')) ||
      !['production', 'baseline', 'general', 'general-boolean', 'general-sentence'].includes(options.appleVariant) ||
      !['baseline', 'regressions'].includes(options.suite) || (options.offline && options.suite !== 'baseline') ||
      !Number.isFinite(options.maxEstimatedUsd) || options.maxEstimatedUsd <= 0 || options.maxEstimatedUsd > 1) throw new Error('Invalid development test options');
  return options;
}

// Kill the whole test process group on timeout, including native model probes.
function run(command, args, env = process.env, timeout = 30 * 60_000) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd: ROOT, env, stdio: 'inherit', detached: true });
    const timer = setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL'); } catch {} }, timeout);
    child.on('error', () => { clearTimeout(timer); resolve(2); });
    child.on('exit', (code) => { clearTimeout(timer); resolve(code ?? 2); });
  });
}

export async function main(args = process.argv.slice(2), dependencies = { run, evaluate }) {
  if (args.includes('--help')) {
    console.log('node scripts/test.mjs [--offline | --dry-run] [--quality-only] [--suite=baseline|regressions] [--apple-variant=production|baseline|general|general-boolean|general-sentence] [--max-estimated-usd=0.25]\nDefault: deterministic validation, native synthetic cleanup, live Jev. --offline omits both inference stages. --quality-only runs only the native/Jev stages. Apple variants are developer experiments; they do not configure the app. Suites are pinned synthetic corpora, never arbitrary files.');
    return 0;
  }
  const options = parseArgs(args);
  // Ambient variables must not turn ordinary validation into a native probe.
  const env = { ...process.env };
  delete env.RECORD_JEV_OUTPUT;
  delete env.RECORD_JEV_VARIANT;
  delete env.RECORD_JEV_SUITE;
  delete env.CLOUDFLARE_API_TOKEN;
  delete env.CLOUDFLARE_ACCOUNT_ID;
  if (!options.qualityOnly) {
    const code = await dependencies.run('./scripts/ci/validate.sh', ['--full'], env);
    if (code !== 0) return code;
  }
  if (options.offline) {
    console.log('Offline subset passed. Native Apple cleanup and Jev were not evaluated.');
    return 0;
  }
  const output = path.join(ROOT, '.build/jev', new Date().toISOString().replace(/[:.]/g, '-') + '-' + crypto.randomBytes(4).toString('hex'));
  fs.mkdirSync(output, { recursive: true });
  console.log(`Synthetic test evidence: ${output}`);
  const workflow = { complete: false, suite: options.suite, appleVariant: options.appleVariant, nativeExitCode: null, evaluationExitCode: null, releaseAccepted: false };
  const save = () => fs.writeFileSync(path.join(output, 'workflow.json'), JSON.stringify(workflow, null, 2) + '\n');
  save();
  workflow.nativeExitCode = await dependencies.run('swift', ['test', '--build-system', process.env.RECORD_SWIFT_BUILD_SYSTEM || 'swiftbuild', '--filter', 'TranscriptJevProbeTests/testPublicSyntheticCleanup'], { ...env, RECORD_JEV_OUTPUT: path.join(output, 'native.json'), RECORD_JEV_VARIANT: options.appleVariant, RECORD_JEV_SUITE: options.suite }, 10 * 60_000);
  save();
  if (workflow.nativeExitCode !== 0) return 2;
  try {
    workflow.evaluationExitCode = await dependencies.evaluate(output, options);
    workflow.complete = workflow.evaluationExitCode !== 2 && !options.dryRun;
    save();
    return workflow.evaluationExitCode;
  } catch (error) {
    workflow.error = error instanceof EvaluationError ? error.message : 'Evaluation preparation failed; check the pinned synthetic corpus, native output and shared dependency setup.';
    save();
    console.error(workflow.error);
    return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then((code) => { process.exitCode = code; }).catch(() => { console.error('Invalid development test invocation; use --help.'); process.exitCode = 2; });
}
