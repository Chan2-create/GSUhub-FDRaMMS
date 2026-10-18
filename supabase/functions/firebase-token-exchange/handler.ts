// Trades a Firebase ID token for a short-lived Supabase access token.
//
// GSUhub signs people in with Firebase Auth and keeps its data in Supabase.
// Postgres learns who is calling from this token: `sub` is the Firebase
// uid, and row level security reads the role and account status from the
// `users` row with that id (supabase/migrations/*_access_helpers.sql). So
// this function only proves identity. It grants nothing: a deactivated
// account still gets a token, and the token opens nothing.
//
// Secrets (`supabase secrets set`, or supabase/functions/.env locally):
//
//   FIREBASE_PROJECT_ID    the Firebase project whose tokens are accepted
//   TOKEN_SIGNING_KEY      the private JSON Web Key the tokens are signed
//                          with. Hosted: an ES256 key made with
//                          `supabase gen signing-key --algorithm ES256` and
//                          imported as the project's signing key (same
//                          `kid`). Local: the stack's JWT secret as an `oct`
//                          key; tool/supabase_function_env.mjs writes it.
//   ALLOW_EMULATOR_TOKENS  "true" accepts the Firebase Auth emulator's
//                          unsigned tokens. Local only: refused outright on
//                          a hosted project.

import {
  createRemoteJWKSet,
  decodeJwt,
  decodeProtectedHeader,
  importJWK,
  type JWK,
  type JWTPayload,
  jwtVerify,
  type JWTVerifyGetKey,
  SignJWT,
} from "jose";

/// Google's public keys for Firebase ID tokens.
const firebaseKeysUrl = new URL(
  "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
);

/// The longest a Supabase token lives, in seconds. Never longer than the
/// Firebase token it was traded for, either.
const maxLifetime = 3600;

/// Clock skew tolerated between Google's clock and ours, in seconds.
const clockSkew = 30;

export interface ExchangeConfig {
  firebaseProjectId: string;
  signingKey: CryptoKey | Uint8Array;
  signingAlgorithm: string;
  signingKeyId?: string;
  allowEmulatorTokens: boolean;
  firebaseKeys: JWTVerifyGetKey;
  /// Seconds since the epoch; replaceable in tests.
  now: () => number;
}

/// Why the function cannot run: answered to every request, so a missing
/// secret is loud instead of looking like a bad token.
export interface ConfigError {
  configError: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const refuse = (status: number, error: string, message: string) =>
  json(status, { error, message });

/// Reads the configuration from the function's environment.
export async function configFromEnv(
  env: (name: string) => string | undefined,
  overrides: Partial<Pick<ExchangeConfig, "firebaseKeys" | "now">> = {},
): Promise<ExchangeConfig | ConfigError> {
  const firebaseProjectId = env("FIREBASE_PROJECT_ID")?.trim();
  if (!firebaseProjectId) {
    return { configError: "FIREBASE_PROJECT_ID is not set." };
  }

  const allowEmulatorTokens = env("ALLOW_EMULATOR_TOKENS") === "true";
  if (allowEmulatorTokens && isHosted(env("SUPABASE_URL"))) {
    return {
      configError:
        "ALLOW_EMULATOR_TOKENS is set on a hosted project. It is for the " +
        "local stack only; remove the secret.",
    };
  }

  const rawKey = env("TOKEN_SIGNING_KEY");
  if (!rawKey) return { configError: "TOKEN_SIGNING_KEY is not set." };
  let jwk: JWK;
  try {
    const parsed = JSON.parse(rawKey);
    // A keys file (signing_keys.json) holds a list; the key is its first.
    jwk = Array.isArray(parsed) ? parsed[0] : parsed;
    if (!jwk || typeof jwk !== "object") throw new Error();
  } catch {
    return { configError: "TOKEN_SIGNING_KEY is not a JSON Web Key." };
  }
  const algorithm = signingAlgorithmFor(jwk);
  if (typeof algorithm !== "string") return algorithm;
  if (jwk.kty !== "oct" && !jwk.kid) {
    return {
      configError:
        "TOKEN_SIGNING_KEY needs a `kid`: Supabase finds the matching " +
        "public key by it.",
    };
  }

  let signingKey: CryptoKey | Uint8Array;
  try {
    // Only the key itself: `supabase gen signing-key` also prints usage
    // hints (key_ops ["sign", "verify"]), and Web Crypto refuses "verify"
    // on a private key. This key only ever signs.
    const { key_ops: _ops, use: _use, ext: _ext, ...material } = jwk;
    signingKey = await importJWK(material, algorithm);
  } catch (error) {
    return { configError: `TOKEN_SIGNING_KEY could not be read: ${error}` };
  }

  return {
    firebaseProjectId,
    signingKey,
    signingAlgorithm: algorithm,
    signingKeyId: jwk.kid,
    allowEmulatorTokens,
    firebaseKeys: overrides.firebaseKeys ?? createRemoteJWKSet(firebaseKeysUrl),
    now: overrides.now ?? (() => Math.floor(Date.now() / 1000)),
  };
}

function isHosted(supabaseUrl: string | undefined): boolean {
  if (!supabaseUrl) return false;
  try {
    return new URL(supabaseUrl).hostname.endsWith(".supabase.co");
  } catch {
    return false;
  }
}

function signingAlgorithmFor(jwk: JWK): string | ConfigError {
  switch (jwk.kty) {
    case "oct":
      if (!jwk.k) break;
      return "HS256";
    case "EC":
      if (jwk.crv !== "P-256" || !jwk.d) break;
      return "ES256";
    case "RSA":
      if (!jwk.d) break;
      return "RS256";
  }
  return {
    configError:
      "TOKEN_SIGNING_KEY must be a private key: an `oct` secret, an EC " +
      "P-256 key or an RSA key.",
  };
}

/// Thrown for a token that is not a valid Firebase ID token for this
/// project. Its message goes back to the caller.
class InvalidToken extends Error {}

async function verifyFirebaseToken(
  token: string,
  config: ExchangeConfig,
): Promise<JWTPayload & { sub: string; exp: number }> {
  const issuer = `https://securetoken.google.com/${config.firebaseProjectId}`;
  const audience = config.firebaseProjectId;
  const now = config.now();

  let alg: string | undefined;
  try {
    alg = decodeProtectedHeader(token).alg;
  } catch {
    throw new InvalidToken("Not a token.");
  }

  let payload: JWTPayload;
  if (alg === "none") {
    // The Auth emulator signs nothing; its tokens are trusted only where
    // the emulator is the sign-in service, which is the local stack.
    if (!config.allowEmulatorTokens) {
      throw new InvalidToken("Emulator tokens are not accepted here.");
    }
    try {
      payload = decodeJwt(token);
    } catch {
      throw new InvalidToken("Not a token.");
    }
    if (payload.iss !== issuer || payload.aud !== audience) {
      throw new InvalidToken("The token is for another project.");
    }
    if (typeof payload.exp !== "number" || payload.exp <= now - clockSkew) {
      throw new InvalidToken("The token has expired.");
    }
  } else {
    try {
      ({ payload } = await jwtVerify(token, config.firebaseKeys, {
        issuer,
        audience,
        algorithms: ["RS256"],
        currentDate: new Date(now * 1000),
        clockTolerance: clockSkew,
        requiredClaims: ["exp", "iat", "sub"],
      }));
    } catch (error) {
      const code = (error as { code?: string }).code;
      throw new InvalidToken(
        code === "ERR_JWT_EXPIRED"
          ? "The token has expired."
          : code === "ERR_JWT_CLAIM_VALIDATION_FAILED"
          ? "The token is for another project."
          : "The token's signature does not check out.",
      );
    }
  }

  // Firebase's own rules for an ID token, beyond the signature.
  if (
    typeof payload.sub !== "string" || payload.sub.length === 0 ||
    payload.sub.length > 128
  ) {
    throw new InvalidToken("The token names no user.");
  }
  if (typeof payload.iat === "number" && payload.iat > now + clockSkew) {
    throw new InvalidToken("The token was issued in the future.");
  }
  const authTime = (payload as { auth_time?: unknown }).auth_time;
  if (typeof authTime === "number" && authTime > now + clockSkew) {
    throw new InvalidToken("The sign-in happened in the future.");
  }
  return payload as JWTPayload & { sub: string; exp: number };
}

export function createHandler(
  config: ExchangeConfig | ConfigError,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return refuse(405, "method_not_allowed", "Use POST.");
    }
    if ("configError" in config) {
      console.error(`firebase-token-exchange: ${config.configError}`);
      return refuse(500, "misconfigured", "The token exchange is not set up.");
    }

    let idToken: unknown;
    try {
      ({ idToken } = await request.json());
    } catch {
      return refuse(
        400,
        "invalid_request",
        'Send {"idToken": "<Firebase ID token>"}.',
      );
    }
    if (typeof idToken !== "string" || idToken.length === 0) {
      return refuse(
        400,
        "invalid_request",
        'Send {"idToken": "<Firebase ID token>"}.',
      );
    }

    let firebase: JWTPayload & { sub: string; exp: number };
    try {
      firebase = await verifyFirebaseToken(idToken, config);
    } catch (error) {
      if (error instanceof InvalidToken) {
        return refuse(401, "invalid_token", error.message);
      }
      // Google's keys could not be fetched, or something else broke.
      console.error("firebase-token-exchange: verification failed", error);
      return refuse(
        503,
        "unavailable",
        "Could not check the token. Try again.",
      );
    }

    const now = config.now();
    const expiresAt = Math.min(firebase.exp, now + maxLifetime);
    // The email Firebase verified the person signed in with: signing up
    // files the profile under it (public.register_self), so nobody can
    // claim another's address.
    const email = typeof firebase.email === "string"
      ? firebase.email
      : undefined;
    const accessToken = await new SignJWT({
      role: "authenticated",
      ...(email ? { email } : {}),
    })
      .setProtectedHeader({
        alg: config.signingAlgorithm,
        typ: "JWT",
        ...(config.signingKeyId ? { kid: config.signingKeyId } : {}),
      })
      .setSubject(firebase.sub)
      .setAudience("authenticated")
      .setIssuedAt(now)
      .setExpirationTime(expiresAt)
      .sign(config.signingKey);

    return json(200, {
      access_token: accessToken,
      token_type: "bearer",
      expires_in: Math.max(0, expiresAt - now),
      expires_at: expiresAt,
    });
  };
}
