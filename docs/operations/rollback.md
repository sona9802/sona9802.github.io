# Rollback runbook

1. Identify the last successful commit and Pages workflow run.
2. Revert the faulty change through a reviewed forward commit.
3. Let the Pages workflow deploy the restored build.
4. Verify the public URL on phone and desktop.
5. Record the incident and corrective action in the decision log or an issue.

For database changes, prefer an additive corrective migration. Never delete or reverse production data automatically.
