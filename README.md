# SCT 1998–2002 Silver Jubilee Reunion Portal

Portal for the Sona College of Technology 1998–2002 batch reunion, July 16–18, 2027.

## Phase 1 status

- Branded public reunion portal with confirmed dates and venue
- Reunion objectives and high-level three-day program
- Introductions to all seven working committees
- Public organizer announcements and volunteer calls to action
- Public contact instructions and provisional privacy notice
- Responsive layout and accessibility baseline
- Automated lint, six tests, production build, CI, and GitHub Pages deployment
- Supabase local and cloud foundation retained for later secure phases
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
