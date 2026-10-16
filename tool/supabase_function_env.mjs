// Writes supabase/functions/.env: the local secrets firebase-token-exchange
// needs (supabase/functions/firebase-token-exchange/handler.ts).
//
//   npx supabase start
//   node tool/supabase_function_env.mjs
//   npx supabase stop && npx supabase start     (the functions read .env at start)
//
// LOCAL ONLY. The signing key it writes is the local stack's own JWT secret,
// and it trusts the Firebase Auth emulator's unsigned tokens. The file is
// git-ignored. A hosted project gets its secrets from `supabase secrets
// set` instead; see supabase/README.md.

import { execSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const target = join(root, 'supabase', 'functions', '.env');

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
  console.error(String(error.stderr ?? error.message).trim());
  process.exit(1);
}

const host = status.API_URL ? new URL(status.API_URL).hostname : '';
if (host !== '127.0.0.1' && host !== 'localhost') {
  console.error(`Refusing: ${status.API_URL ?? 'no API_URL'} is not the local stack.`);
  process.exit(1);
}
if (!status.JWT_SECRET) {
  console.error('`supabase status -o env` gave no JWT_SECRET.');
  process.exit(1);
}

// The Firebase project the app signs in to; the Auth emulator uses the same id.
const firebaserc = JSON.parse(readFileSync(join(root, '.firebaserc'), 'utf8'));
const projectId = firebaserc.projects?.default;
if (!projectId) {
  console.error('.firebaserc names no default project.');
  process.exit(1);
}

const signingKey = {
  kty: 'oct',
  k: Buffer.from(status.JWT_SECRET).toString('base64url'),
};

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
