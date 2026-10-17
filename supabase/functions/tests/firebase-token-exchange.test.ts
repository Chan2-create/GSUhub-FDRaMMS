// Tests for supabase/functions/firebase-token-exchange/handler.ts.
//
//   deno test --config supabase/functions/firebase-token-exchange/deno.json \
//     supabase/functions/tests/
//
// Offline: Google's keys are replaced by a key pair made here, so these
// run without a network or a running stack.

import {
  assert,
  assertEquals,
  assertMatch,
  assertStringIncludes,
} from "jsr:@std/assert@1.0.13";
import {
  createLocalJWKSet,
  exportJWK,
  generateKeyPair,
  type JWTPayload,
  jwtVerify,
  SignJWT,
} from "jose";
import {
  type ConfigError,
  configFromEnv,
  createHandler,
  type ExchangeConfig,
} from "../firebase-token-exchange/handler.ts";

const project = "gsuhub-dorsu";
const now = 1_800_000_000;
const localSecret = "a-test-signing-secret-of-at-least-32-characters";
const octKey = JSON.stringify({
  kty: "oct",
  k: btoa(localSecret).replace(/=+$/, "").replace(/\+/g, "-").replace(
    /\//g,
    "_",
  ),
});

// Stands in for Google's signing keys.
const google = await generateKeyPair("RS256");
const googleJwk = {
  ...(await exportJWK(google.publicKey)),
  kid: "google-1",
  alg: "RS256",
};
const firebaseKeys = createLocalJWKSet({ keys: [googleJwk] });

// A key Google never published.
const stranger = await generateKeyPair("RS256");

function claims(overrides: JWTPayload = {}): JWTPayload {
  return {
    iss: `https://securetoken.google.com/${project}`,
    aud: project,
    sub: "seed-faculty-0001",
    email: "faculty@dorsu.edu.ph",
    iat: now - 60,
    auth_time: now - 600,
    exp: now + 3000,
    ...overrides,
  };
}

function firebaseToken(
  overrides: JWTPayload = {},
  key = google.privateKey,
  kid = "google-1",
) {
  return new SignJWT(claims(overrides))
    .setProtectedHeader({ alg: "RS256", kid, typ: "JWT" })
    .sign(key);
}

/// An Auth emulator token: unsigned, alg "none", empty signature.
function emulatorToken(overrides: JWTPayload = {}) {
  const part = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/=+$/, "").replace(/\+/g, "-").replace(
      /\//g,
      "_",
    );
  return `${part({ alg: "none", typ: "JWT" })}.${part(claims(overrides))}.`;
}

async function setup(env: Record<string, string> = {}) {
  return await configFromEnv(
    (name) =>
      ({
        FIREBASE_PROJECT_ID: project,
        TOKEN_SIGNING_KEY: octKey,
        SUPABASE_URL: "http://kong:8000",
        ...env,
      })[name],
    { firebaseKeys, now: () => now },
  );
}

async function exchange(
  config: ExchangeConfig | ConfigError,
  body: unknown,
  method = "POST",
) {
  const response = await createHandler(config)(
    new Request("http://localhost/functions/v1/firebase-token-exchange", {
      method,
      headers: { "Content-Type": "application/json" },
      body: method === "POST"
        ? (typeof body === "string" ? body : JSON.stringify(body))
        : undefined,
    }),
  );
  return {
    status: response.status,
    body: response.status === 204 ? null : await response.json(),
    headers: response.headers,
  };
}

const secretKey = new TextEncoder().encode(localSecret);

Deno.test("a valid Firebase token is traded for a Supabase token for the same uid", async () => {
  const { status, body } = await exchange(await setup(), {
    idToken: await firebaseToken(),
  });
  assertEquals(status, 200);
  assertEquals(body.token_type, "bearer");
  const { payload, protectedHeader } = await jwtVerify(
    body.access_token,
    secretKey,
    {
      audience: "authenticated",
      currentDate: new Date(now * 1000),
    },
  );
  assertEquals(protectedHeader.alg, "HS256");
  assertEquals(payload.sub, "seed-faculty-0001");
  assertEquals(payload.role, "authenticated");
  assertEquals(payload.email, "faculty@dorsu.edu.ph");
  assertEquals(payload.iat, now);
});

Deno.test("a Firebase token with no email gives a token with none", async () => {
  const { status, body } = await exchange(await setup(), {
    idToken: await firebaseToken({ email: undefined }),
  });
  assertEquals(status, 200);
  const { payload } = await jwtVerify(body.access_token, secretKey, {
    currentDate: new Date(now * 1000),
  });
  assertEquals("email" in payload, false);
});

Deno.test("the Supabase token never outlives the Firebase token", async () => {
  const { body } = await exchange(await setup(), {
    idToken: await firebaseToken({ exp: now + 300 }),
  });
  assertEquals(body.expires_at, now + 300);
  assertEquals(body.expires_in, 300);
});

Deno.test("and never lives longer than an hour", async () => {
  const { body } = await exchange(await setup(), {
    idToken: await firebaseToken({ exp: now + 7200 }),
  });
  assertEquals(body.expires_at, now + 3600);
});

for (
  const [why, token, message] of [
    [
      "another project's token",
      () => firebaseToken({ aud: "someone-else" }),
      "another project",
    ],
    [
      "a token from another issuer",
      () =>
        firebaseToken({ iss: "https://securetoken.google.com/someone-else" }),
      "another project",
    ],
    ["an expired token", () => firebaseToken({ exp: now - 120 }), "expired"],
    [
      "a token signed by a key Google never published",
      () => firebaseToken({}, stranger.privateKey),
      "signature",
    ],
    [
      "a token signed by an unknown key id",
      () => firebaseToken({}, stranger.privateKey, "google-2"),
      "signature",
    ],
    [
      "a token issued in the future",
      () => firebaseToken({ iat: now + 600 }),
      "future",
    ],
    [
      "a token that names no user",
      () => firebaseToken({ sub: "" }),
      "names no user",
    ],
    [
      "an emulator token, where the emulator is not trusted",
      () => Promise.resolve(emulatorToken()),
      "Emulator tokens",
    ],
    [
      "something that is not a token",
      () => Promise.resolve("not-a-token"),
      "Not a token",
    ],
  ] as const
) {
  Deno.test(`refuses ${why}`, async () => {
    const { status, body } = await exchange(await setup(), {
      idToken: await token(),
    });
    assertEquals(status, 401);
    assertEquals(body.error, "invalid_token");
    assertStringIncludes(body.message, message);
  });
}

Deno.test("accepts an emulator token on the local stack when allowed", async () => {
  const config = await setup({ ALLOW_EMULATOR_TOKENS: "true" });
  const { status, body } = await exchange(config, { idToken: emulatorToken() });
  assertEquals(status, 200);
  const { payload } = await jwtVerify(body.access_token, secretKey, {
    currentDate: new Date(now * 1000),
  });
  assertEquals(payload.sub, "seed-faculty-0001");
});

Deno.test("even then, refuses an emulator token for another project, or an expired one", async () => {
  const config = await setup({ ALLOW_EMULATOR_TOKENS: "true" });
  assertEquals(
    (await exchange(config, {
      idToken: emulatorToken({ aud: "someone-else" }),
    })).status,
    401,
  );
  assertEquals(
    (await exchange(config, { idToken: emulatorToken({ exp: now - 120 }) }))
      .status,
    401,
  );
});

Deno.test("will not trust the emulator on a hosted project", async () => {
  const config = await setup({
    ALLOW_EMULATOR_TOKENS: "true",
    SUPABASE_URL: "https://abcdefgh.supabase.co",
  });
  assert("configError" in config);
  const { status, body } = await exchange(config, { idToken: emulatorToken() });
  assertEquals(status, 500);
  assertEquals(body.error, "misconfigured");
  // A real token is refused too: a misconfigured exchange answers nobody.
  assertEquals(
    (await exchange(config, { idToken: await firebaseToken() })).status,
    500,
  );
});

for (
  const [why, env, message] of [
    [
      "the Firebase project is not set",
      { FIREBASE_PROJECT_ID: "" },
      "FIREBASE_PROJECT_ID",
    ],
    [
      "there is no signing key",
      { TOKEN_SIGNING_KEY: "" },
      "TOKEN_SIGNING_KEY is not set",
    ],
    [
      "the signing key is not JSON",
      { TOKEN_SIGNING_KEY: "secret" },
      "not a JSON Web Key",
    ],
    ["the signing key is a public key", {
      TOKEN_SIGNING_KEY: JSON.stringify({
        kty: "EC",
        crv: "P-256",
        x: "x",
        y: "y",
        kid: "k",
      }),
    }, "private key"],
  ] as const
) {
  Deno.test(`does not start when ${why}`, async () => {
    const config = await setup(env);
    assert("configError" in config);
    assertStringIncludes(config.configError, message);
  });
}

Deno.test("signs with an imported ES256 key, naming it by kid", async () => {
  const signing = await generateKeyPair("ES256", { extractable: true });
  const jwk = { ...(await exportJWK(signing.privateKey)), kid: "gsuhub-2026" };
  const config = await setup({ TOKEN_SIGNING_KEY: JSON.stringify(jwk) });
  const { status, body } = await exchange(config, {
    idToken: await firebaseToken(),
  });
  assertEquals(status, 200);
  const { payload, protectedHeader } = await jwtVerify(
    body.access_token,
    signing.publicKey,
    {
      currentDate: new Date(now * 1000),
    },
  );
  assertEquals(protectedHeader, {
    alg: "ES256",
    typ: "JWT",
    kid: "gsuhub-2026",
  });
  assertEquals(payload.sub, "seed-faculty-0001");
});

Deno.test("an ES256 key without a kid is refused: Supabase could not find its public half", async () => {
  const signing = await generateKeyPair("ES256", { extractable: true });
  const config = await setup({
    TOKEN_SIGNING_KEY: JSON.stringify(await exportJWK(signing.privateKey)),
  });
  assert("configError" in config);
  assertStringIncludes(config.configError, "kid");
});

Deno.test("asks for a token when none is sent", async () => {
  const config = await setup();
  for (const body of [{}, { idToken: "" }, { idToken: 42 }, "not json"]) {
    const { status, body: answer } = await exchange(config, body);
    assertEquals(status, 400);
    assertMatch(answer.message, /idToken/);
  }
});

Deno.test("answers the browser's preflight, and only POST otherwise", async () => {
  const config = await setup();
  const preflight = await exchange(config, null, "OPTIONS");
  assertEquals(preflight.status, 204);
  assertEquals(preflight.headers.get("Access-Control-Allow-Origin"), "*");
  assertStringIncludes(
    preflight.headers.get("Access-Control-Allow-Headers") ?? "",
    "apikey",
  );
  assertEquals((await exchange(config, null, "GET")).status, 405);
});
