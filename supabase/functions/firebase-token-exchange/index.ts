// firebase-token-exchange: a Firebase ID token in, a Supabase access token
// out. See handler.ts.
//
//   POST /functions/v1/firebase-token-exchange
//   apikey: <the project's anon or publishable key>
//   {"idToken": "<Firebase ID token>"}
//
//   200 {"access_token", "token_type": "bearer", "expires_in", "expires_at"}
//   400 no token · 401 not a valid token · 500 secrets missing
//
// verify_jwt is off for this function (supabase/config.toml): the caller
// has no Supabase token yet. That is what it came for.

import "@supabase/functions-js/edge-runtime.d.ts";
import { configFromEnv, createHandler } from "./handler.ts";

const config = await configFromEnv((name) => Deno.env.get(name));
Deno.serve(createHandler(config));
