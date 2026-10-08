# Incident-response runbook

## Immediate response

1. Disable the affected feature or deployment.
2. Revoke a suspected credential in GitHub or Supabase.
3. Preserve relevant audit and workflow logs without copying private data into issues.
4. Determine whether private information was accessed or exposed.
5. Notify the Interim Product Owner.

## Recovery

Restore the last known-good frontend, correct permissions with a forward migration, test one allowed and one denied operation, and document the outcome before reopening the feature.

## Current contact

Ashok Loganathan is the interim incident contact until a second maintainer is appointed.
