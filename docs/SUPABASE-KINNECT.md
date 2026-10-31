# Supabase Kinnect

Verified dashboard: project fetzoqpdxoaxfqqrcfci, Healthy, Free/Nano, Singapore.
Data API disabled on project creation. Session pooler details read from Connect UI:

- Host aws-0-ap-southeast-1.pooler.supabase.com
- Port 5432; database postgres
- Provisioning user postgres.fetzoqpdxoaxfqqrcfci

Run Cau-hinh-PostgreSQL.cmd locally to enter the existing database password with hidden input. The script creates cloud-db.env with a private user ACL, refuses overwriting, and percent-encodes password characters. This is a provisioning connection, not the final least-privilege application role. Do not put it into APKs or ZIPs. TLS verifies server identity; a missing CA must be resolved with the trusted project certificate, never rejectUnauthorized=false.

Latest division: PostgreSQL accounts/profile/session/wallet, D1 chat. The current SQLite backend does not load cloud-db.env. PostgreSQL adapter, schema/data migration, dedicated app-role permissions and live connection verification remain unfinished. No production cutover was performed.
