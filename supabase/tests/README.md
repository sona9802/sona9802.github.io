# Database policy tests

Run the local database policy suite after starting Supabase:

```bash
npm run supabase:start
npm run supabase:reset
npm run test:db
```

`database/phase2_rls.test.sql` covers anonymous denial, member self-access,
cross-member denial, department representative boundaries, suspended-account
denial, invitation acceptance, consent defaults, audit creation, and RSVP
summary reconciliation. All fixtures are synthetic and transactional.
