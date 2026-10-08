# Deployment runbook

## Local validation

1. Install Node.js 20 and Docker Desktop.
2. Run `npm ci`.
3. Run `npm run supabase:start` when database work is required.
4. Run `npm run lint`, `npm test`, and `npm run build`.
5. Inspect `dist/` and confirm it contains no secrets or personal data.

## GitHub Pages

Merges and pushes to `main` trigger both validation and Pages deployment. The workflow builds with `/sct-98-02-reunion/` as the base path and publishes the `dist` artifact.

After deployment, verify HTTPS, the page title, event dates, mobile layout, and browser console.

## Secrets

Only browser-safe Supabase URL and anonymous-key values may be exposed to Vite. Never place a service-role key in a `VITE_` variable.
