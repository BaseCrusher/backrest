# OIDC Backend Wiring — Plan

## Decisions (locked)
- Session token delivery: **httpOnly cookie** (`backrest-session`), Secure + SameSite=Lax.
- Libraries: `github.com/coreos/go-oidc/v3` + `golang.org/x/oauth2`.
- Flow: OIDC Authorization Code. OIDC used only to establish identity at login; afterward
  backrest mints its **own** HS256 session JWT (signed with existing `jwt-secret`,
  `subject=email`). Middleware stays uniform across drivers.

## Current state (verified)
- `proto/v1/config.proto`: `OidcConfig` + `Auth.oidc` defined. Generated. DONE
- `internal/config/validate.go`: `validateOidc()` done. DONE
- `internal/config/authdriver.go`: `AuthDriverOf`, constants (disabled/local/oidc). DONE
- `webui/.../SettingsModal.tsx`: OIDC config form started. DONE
- Local auth: `auth.Authenticator` (auth.go) — `Login` (bcrypt) -> `CreateJWT` (HS256, subj=username, 7d).
  Middleware `RequireAuthentication` (middleware.go): Basic -> Bearer header -> `VerifyJWT`
  (looks up subject in `auth.GetUsers()`).
- Routing: `cmd/backrest/backrest.go` `newRootMux` — unauthed mux (Authentication RPC, sync, download)
  vs authed mux (Backrest API, metrics) gated by `RequireAuthentication`.
- Frontend: `client.ts` Bearer-from-localStorage. `App.tsx` shows `LoginModal` on `Code.Unauthenticated`.
- No oidc/oauth2 deps in go.mod yet.

## Backend tasks

### 1. Dependencies
- [ ] `go get github.com/coreos/go-oidc/v3 golang.org/x/oauth2`; tidy.

### 2. internal/auth/oidc.go — provider manager
- [ ] `OIDCProvider` wrapping `*oidc.Provider`, `oauth2.Config`, `*oidc.IDTokenVerifier`,
      allowedEmails/allowedDomains, scopes.
- [ ] Constructor builds from `*v1.OidcConfig` via `oidc.NewProvider(ctx, issuer)` (network/discovery).
      Default scopes [openid, email, profile] when empty.
- [ ] Manager caches provider, rebuilds when oidc config changes (keyed by config hash); mutex-guarded.
      Lazy build on first use so startup doesn't block on IdP reachability.
- [ ] `AuthCodeURL(state, nonce, redirectURL)`; `Exchange(ctx, code, nonce, redirectURL) -> (Identity, error)`
      = exchange code -> verify ID token -> verify nonce -> extract email/email_verified/name
      -> enforce allowed_emails / allowed_domains.
- [ ] Pure helper `emailAllowed(email, allowedEmails, allowedDomains)` (unit-testable).

### 3. internal/auth/oidchandler.go — HTTP redirect handlers (NOT connectrpc)
- [ ] `GET /auth/oidc/login`: random state+nonce -> set short-lived httpOnly cookies -> 302 to AuthCodeURL.
      Derive redirect_url from request (X-Forwarded-Proto/r.TLS + r.Host + /auth/oidc/callback)
      when config redirect_url empty.
- [ ] `GET /auth/oidc/callback`: validate state cookie vs query, Exchange, mint session JWT
      (CreateJWTForSubject(email)), set `backrest-session` cookie (httpOnly, Secure when TLS, SameSite=Lax,
      expiry = JWT expiry), 302 to `/`. On error -> 302 to /?authError=... .
- [ ] `GET /auth/oidc/logout`: clear cookie, 302 to /.

### 4. internal/auth/auth.go
- [ ] Add `CreateJWTForSubject(subject string)` (refactor `CreateJWT` to use it).
- [ ] `VerifyJWT`: branch on `config.AuthDriverOf(auth)`. For oidc: validate signature+expiry only,
      return synthetic `*v1.User{Name: subject}` (no config-user lookup). Local: unchanged.

### 5. internal/auth/middleware.go
- [ ] After Bearer-header miss, try `backrest-session` cookie -> `VerifyJWT`. Order: Basic -> Bearer -> cookie.

### 6. cmd/backrest/backrest.go
- [ ] Build OIDC manager from `configMgr`; pass into `newServer`/`newRootMux`.
- [ ] Mount /auth/oidc/login, /auth/oidc/callback, /auth/oidc/logout on unauthedMux.
- [ ] Dev CORS middleware: switch from `*` to reflected origin + `Access-Control-Allow-Credentials: true`
      (required for cookie). Only affects dev builds.

### 7. Public auth-driver endpoint (frontend needs driver pre-auth)
- [ ] `proto/v1/authentication.proto`: add `rpc GetAuthInfo(Empty) returns (AuthInfo)`;
      `AuthInfo { string auth_driver; bool oidc_enabled; string oidc_button_text; }`. Unauthenticated.
- [ ] Regenerate (buf generate) -> go + ts.
- [ ] Implement in `authenticationhandler.go` (read configMgr, return driver). Inject configMgr into handler.

## Frontend tasks

### 8. webui/src/api/client.ts
- [ ] Add `credentials: "include"` to fetch (cookie cross-origin in dev, same-origin in prod).

### 9. webui/src/features/auth/ + App.tsx
- [ ] On `Code.Unauthenticated`: call getAuthInfo(); if driver oidc -> **immediately** redirect
      `window.location = backendUrl + "/auth/oidc/login"` (NO intermediate SSO screen/button),
      else existing LoginModal.
- [ ] Guard against redirect loop: if landing with `?authError=...`, show error instead of re-redirecting.
- [ ] Logout clears localStorage token + navigates /auth/oidc/logout when oidc.

## Verification
- [ ] `go build ./...`, `go test ./internal/auth/... ./internal/config/...`.
- [ ] Unit: emailAllowed, redirect_url derivation, VerifyJWT oidc branch.
- [ ] Manual: dummy IdP (Dex/Keycloak or Google) — full login->cookie->authed request->logout.
- [ ] Regression: local + disabled drivers unchanged.

## Open questions / risks
- IdP reachability at startup -> lazy provider build (don't crash if IdP down).
- redirect_url must exactly match IdP registration; document derivation.
- PKCE: add S256 challenge (cheap, recommended) even with client_secret? Default: yes.

## Review (implemented)
DONE — all tasks complete. Backend `go build ./...` exit 0, `go test ./internal/auth/... ./internal/config/...` ok,
webui `tsc --noEmit` clean.

Files added:
- `internal/auth/oidc.go` — OIDCManager: lazy discovery cached by sha256(oidc config), AuthCodeURL +
  Exchange (PKCE S256, nonce verify, email/domain allow-list), pure `emailAllowed`.
- `internal/auth/oidchandler.go` — /auth/oidc/{login,callback,logout}. State+nonce+PKCE-verifier in
  short-lived httpOnly cookies (path /auth/oidc, SameSite=Lax). Callback mints session JWT -> sets
  `backrest-session` httpOnly cookie -> 302 /. Failures -> 302 /?authError=. redirectURL derived from
  request (X-Forwarded-Proto/r.TLS + Host) when config blank.
- `internal/auth/oidc_test.go` — emailAllowed table + VerifyJWT oidc-subject test.

Files changed:
- `auth.go`: CreateJWTForSubject; VerifyJWT accepts signed subject (email) for oidc driver (no user lookup).
- `middleware.go`: SessionCookieName const; cookie fallback after Bearer header (Basic->Bearer->cookie).
- `authentication.proto` + regen: GetAuthInfo RPC + AuthInfo{auth_driver, oidc_login_url}.
- `authenticationhandler.go`: GetAuthInfo impl; handler now holds config.ConfigStore.
- `backrest.go`: build OIDCManager/Handler, mount on unauthedMux, pass configMgr to auth handler;
  dev CORS reflects Origin + Allow-Credentials (needed for cookie).
- webui `client.ts`: credentials:"include". `App.tsx`: on Unauthenticated -> getAuthInfo; oidc ->
  immediate redirect to provider (authError guard prevents loop); logout hits /auth/oidc/logout for oidc.

Known limitations / follow-ups:
- Dev cross-origin (vite :5173 + backend): SameSite=Lax cookie won't ride cross-site XHR, and callback
  302s to backend origin not vite. OIDC best tested against a same-origin build. Local-auth (Bearer) dev
  flow unaffected.
- email_verified extracted but NOT enforced. Add a config toggle if required.
- No manual end-to-end run against a real IdP yet (needs Dex/Keycloak/Google credentials).
