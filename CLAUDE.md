# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## Project

Dashboard UI for the Stellar Disbursement Platform (SDP), used to bulk-disburse payments to
recipients over the Stellar network. Pairs with the
[SDP backend](https://github.com/stellar/stellar-disbursement-platform-backend).

## Commands

```bash
yarn start            # dev server (vite), regenerates src/generated/gitInfo.ts first
yarn build             # production build (also regenerates gitInfo.ts)
yarn preview           # preview a production build locally
npx eslint --fix .     # lint (also run automatically on staged files pre-commit)
tsc --noEmit           # typecheck (also run automatically pre-commit)
```

There is no test suite/runner configured (`@testing-library/*` deps and `src/setupTests.ts` exist
but are unused — no `jest`/`vitest` config or test script). CI (`.github/workflows/test-build.yml`)
only runs `yarn install && yarn build`. Don't assume a `yarn test` command exists.

Husky's pre-commit hook runs `pretty-quick --staged`, `lint-staged` (eslint `--fix --max-warnings 0`
on staged `ts`/`tsx`), and `tsc --noEmit` concurrently — a commit fails if any of these fail.

## Environment configuration

Runtime config can come from two sources, both read in `src/constants/envVariables.ts`,
`process.env` taking precedence:

- `window._env_`, populated at container start from `public/settings/env-config.js` (not checked in
  — see `ckl/sdp-dashboard/01-env-config.sh` for how it's generated at deploy time).
- `process.env.REACT_APP_*` (Vite `define`s these at build time from a root `.env` file — see
  `vite.config.ts`).

All env vars must be declared in the `Window["_env_"]` type and destructured from
`generateEnvConfig()` in `envVariables.ts` — this is the single source of truth for what config the
app reads. See README.md for the full variable list and semantics.

## Architecture

### Two competing data-fetching layers

The codebase is mid-migration from Redux Thunks to React Query; both exist side by side and new code
should generally prefer the newer pattern:

- **Legacy**: `src/store/ducks/*` — Redux Toolkit slices with `createAsyncThunk`s that call
  functions in `src/api/*`, dispatched from components and read back via `useRedux(...)`
  (`src/hooks/useRedux.ts`, a thin `useSelector` + `pick` wrapper). Global reducers are wired in
  `src/store/index.ts`. On session expiry, `RESET_STORE_ACTION_TYPE` resets all state except
  `userAccount.isSessionExpired`.
- **Current**: `src/apiQueries/*` — one `useQuery`/`useMutation` hook per endpoint (e.g.
  `useStatementExport.ts`), calling the same kind of fetch helpers directly rather than going
  through Redux. Prefer this pattern for new endpoints/features.

Both layers funnel HTTP calls through `src/helpers/fetchApi.ts`, which: attaches the bearer token
from `localStorageSessionToken`, injects the `SDP-Tenant-Name` header (multi-tenant backend),
silently refreshes the token when it has <5 min left, and dispatches a `SESSION_EXPIRED_EVENT` on a
401 — handled globally by `SessionTokenRefresher`/`UserSession` components rather than per-call. New
API calls should reuse `fetchApi` (or
`fetchStellarApi`/`normalizeApiError`/`normalizeStellarApiError` for Horizon-facing calls) rather
than calling `fetch` directly.

### Routing & access control

`src/App.tsx` declares every route directly (no route config table beyond the `Routes` enum in
`src/constants/settings.ts`). Every authenticated page is wrapped in `PrivateRoute`
(`src/components/PrivateRoute.tsx`), which redirects unauthenticated/session-expired users to `/`
and, when given `acceptedRoles`, redirects users without a matching `userAccount.role` to
`/unauthorized`. `UserRole` is one of
`owner | financial_controller | developer | business | initiator | approver` (`src/types`,
`USER_ROLES_ARRAY` in `src/constants/settings.ts`). When adding a route, follow the existing
per-route pattern: pick the narrowest `acceptedRoles` set that matches similar existing routes, and
wrap the page in `InnerPage` (`isNarrow`/`isCardLayout` variants control layout width/style).

Pages that need a per-organization enable/disable check (like Reports) follow the `ReportsPageGate`
pattern in `App.tsx`: read the flag from `useAppConfig()` (`src/hooks/useAppConfig.ts`, backed by
`GET /app-config`) before wrapping in `PrivateRoute`, falling back to `NotFound` when the feature is
off for that org, rather than only hiding the nav entry. The org-level toggle itself lives in
Settings (`SettingsEnableReporting`), backed by `reporting_enabled` on the organization record
(`useUpdateOrgReportingEnabled` does `PATCH /organization`).

### Component conventions

Non-trivial components live in their own folder (`src/components/Foo/{index.tsx,styles.scss}`);
simple ones are a single `Foo.tsx`. Path alias `@/*` maps to `src/*` (configured in both
`tsconfig.json` and `vite.config.ts`) — always import via `@/...`, not relative paths across
directories. Import order is enforced by ESLint (`import/order`): builtin → external → internal
(`@/...`) → parent/sibling/index, alphabetized within each group, blank line between groups.

Styling is Sass (`.scss`) plus `@stellar/design-system` components; global styles are in
`src/styles/styles.scss`.

### Multi-tenant awareness

The app is tenant-aware throughout: `getSdpTenantName()` resolves the active tenant (from state,
subdomain, or override) and is sent as `SDP-Tenant-Name` on every authenticated request;
`SINGLE_TENANT_MODE` and `DISABLE_TENANT_PREFIL_FROM_DOMAIN` env vars change how the tenant is
resolved at sign-in. Keep this in mind when touching auth/session or API-call code — a
hardcoded/skipped tenant header will break multi-tenant deployments.
