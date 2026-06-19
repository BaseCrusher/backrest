# Add `auth_driver` (string), deprecate `disabled`, NO migration

## Final decisions
- `auth_driver` string: `"disabled"` | `"local"` | `"oidc"`.
- `disabled` bool kept, marked DEPRECATED. NO migration.
- Precedence (effective driver):
  - auth==nil → disabled
  - auth.disabled==true → disabled (deprecated wins)
  - auth_driver=="" → local (preserve existing enabled installs)
  - else → auth_driver
- NewDefaultConfig sets auth_driver="disabled" (fresh = off, as before).
- users valid ONLY when effective driver=="local".
- OIDC settings fields deferred.

## Steps
- [ ] proto: mark `disabled` deprecated=true; add `string auth_driver = 3`.
- [ ] regen (USER): cd proto && buf generate.
- [ ] internal/config/authdriver.go: consts + AuthDriverOf() + AuthDisabled().
- [ ] validate.go validateAuth: switch on AuthDriverOf; local needs users; users only if local; oidc TODO; unknown→err.
- [ ] config.go NewDefaultConfig: Auth{AuthDriver: AuthDriverDisabled}.
- [ ] auth.go Login/VerifyJWT: rename local config→cfg; use config.AuthDisabled.
- [ ] middleware.go: import config; rename local config→cfg; config.AuthDisabled.
- [ ] webui configutil.ts, App.tsx:927, SettingsModal.tsx: driver selector + gating.
- [ ] verify: go build/test + webui build.

## Review
- All proto/Go/frontend edits done. NO migration (deprecated `disabled` precedence handles old configs).
- Regen requires nix/direnv shell (protoc-gen-es from flake). buf+go plugins installed via go install; protoc-gen-es only in nix shell.
- DONE + VERIFIED: regen confirmed (AuthDriver in gen go+ts).
  - go build config+auth: exit 0; go vet clean; go test config/migrations/auth: ok; tsc --noEmit: exit 0.
  - cmd/... build fails only on webui/dist embed (needs frontend build); pnpm check fails on pnpm install gate — both pre-existing env, not auth code.
- NOT covered by tests yet: new AuthDriverOf precedence + validateAuth driver rules (optional follow-up).
