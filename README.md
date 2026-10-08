# SCT 1998–2002 Silver Jubilee Reunion Portal

Portal for the Sona College of Technology 1998–2002 batch reunion, July 16–18, 2027.

## Phase 0 status

- React, TypeScript, and Vite application
- Automated lint, test, and production build
- GitHub Pages deployment workflow
- Supabase local configuration and first migration
- Supabase Free cloud project in South Asia (Mumbai), linked to the local CLI
- Initial architecture, privacy, deployment, rollback, and incident documentation
- No private alumni data

## Local setup

```bash
npm ci
cp .env.example .env.local
npm run dev
```

Run quality checks:

```bash
npm run lint
npm test
npm run build
```

Start the local backend after Docker Desktop is running:

```bash
npm run supabase:start
npm run supabase:reset
```

Never commit `.env.local`, Supabase service-role keys, personal data, photographs, or exports.

## Deployed services

- Portal: <https://sona9802.github.io/>
- Repository: <https://github.com/sona9802/sona9802.github.io>
- Supabase project reference: `bjoimszikocvkxjgieuc`
