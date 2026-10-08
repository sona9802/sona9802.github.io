# ADR 0001: Zero-cost managed platform

- **Status:** Accepted
- **Date:** 2026-10-07
- **Owner:** Ashok Loganathan, Interim Product and Technical Owner

## Decision

Use React, TypeScript, and Vite; host the static frontend on GitHub Pages; use GitHub Actions for validation and deployment; and use Supabase for PostgreSQL, authentication, storage, and narrowly scoped server functions.

Develop and validate database migrations locally. Use one Supabase Free project for the cloud presentation and production modes until the organizer group decides otherwise.

## Consequences

- Initial infrastructure has no recurring charge while it remains within free-tier limits.
- The project site uses the `/sct-98-02-reunion/` base path and hash routing when application routes are introduced.
- Private data never belongs in GitHub.
- Presentation seed data must be removed before real alumni data is accepted.
