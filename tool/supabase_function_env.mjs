// Writes the secrets firebase-token-exchange needs
// (supabase/functions/firebase-token-exchange/handler.ts).
//
// The local stack:
//
//   npx supabase start
//   node tool/supabase_function_env.mjs
//   npx supabase stop && npx supabase start     (the functions read .env at start)
//
//   writes supabase/functions/.env: the local stack's own JWT secret as the
//   signing key, and trust in the Firebase Auth emulator's unsigned tokens.
//
// The hosted project (docs/manual_deploy.md, "Going live"):
//
//   node tool/supabase_function_env.mjs --hosted supabase/signing_keys.json
//   npx supabase secrets set --env-file supabase/functions/.env.hosted
//   then delete supabase/functions/.env.hosted
//
//   writes supabase/functions/.env.hosted: the imported ES256 key, and no
//   emulator trust. A file rather than a command-line argument: Windows
//   PowerShell strips the quotes out of JSON passed to a program.
//
// Both files are git-ignored.

import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function stop(message) {
  console.error(message);
  process.exit(1);
}

// The Firebase project the app signs in to; the Auth emulator uses the same id.
const firebaserc = JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8'));
const projectId = firebaserc.projects?.default;
if (!projectId) stop('.firebaserc names no default project.');

const hosted = process.argv.indexOf('--hosted');
if (hosted >= 0) {
  const keyFile = process.argv[hosted + 1];
  if (!keyFile) stop('Name the key file: --hosted supabase/signing_keys.json');
  let key;
  try {
    // Out-File writes a byte-order mark; JSON does not allow one.
    const parsed = JSON.parse(readFileSync(keyFile, 'utf8').replace(/^﻿/, ''));
    key = Array.isArray(parsed) ? parsed[0] : parsed;
  } catch (error) {
    stop(`${keyFile} is not a JSON Web Key: ${error.message}`);
  }
  if (key?.kty !== 'EC' || !key.d || !key.kid) {
    stop(`${keyFile} is not the private ES256 key \`supabase gen signing-key --algorithm ES256\` prints.`);
  }
  const target = join(root, 'supabase', 'functions', '.env.hosted');
  writeFileSync(
    target,
    [
      '# The hosted project\'s secrets for supabase/functions. Written by',
      '# tool/supabase_function_env.mjs --hosted. Git-ignored. Delete it once',
      '# `supabase secrets set --env-file` has sent it.',
      `FIREBASE_PROJECT_ID=${projectId}`,
      `TOKEN_SIGNING_KEY=${JSON.stringify(key)}`,
      '',
    ].join('\n'),
  );
  console.log(`Wrote ${target}`);
  console.log('Send it:   npx supabase secrets set --env-file supabase/functions/.env.hosted');
  console.log('Then delete it.');
  process.exit(0);
}

let status = {};
try {
  const out = execSync('npx supabase status -o env', {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  for (const line of out.split(/\r?\n/)) {
    const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim());
    if (match) status[match[1]] = match[2];
  }
} catch (error) {
  console.error('Could not read the local stack. Start it first:  npx supabase start');
  stop(String(error.stderr ?? error.message).trim());
}

const host = status.API_URL ? new URL(status.API_URL).hostname : '';
if (host !== '127.0.0.1' && host !== 'localhost') {
  stop(`Refusing: ${status.API_URL ?? 'no API_URL'} is not the local stack.`);
}
if (!status.JWT_SECRET) stop('`supabase status -o env` gave no JWT_SECRET.');

const signingKey = {
  kty: 'oct',
  k: Buffer.from(status.JWT_SECRET).toString('base64url'),
};

const target = join(root, 'supabase', 'functions', '.env');
writeFileSync(
  target,
  [
    '# Local secrets for supabase/functions. Written by tool/supabase_function_env.mjs.',
    '# Git-ignored. Never copy these to a hosted project.',
    `FIREBASE_PROJECT_ID=${projectId}`,
    `TOKEN_SIGNING_KEY=${JSON.stringify(signingKey)}`,
    'ALLOW_EMULATOR_TOKENS=true',
    '',
  ].join('\n'),
);

console.log(`Wrote ${target}`);
console.log('Restart the stack so the functions read it:  npx supabase stop && npx supabase start');
