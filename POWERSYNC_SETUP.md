# PowerSync Setup Guide

## Supabase Configuration

### 1. Create Replication User (Optional but Recommended)

Run in Supabase SQL Editor:

```sql
-- Create a dedicated user for PowerSync with replication privileges
CREATE USER powersync_user WITH REPLICATION PASSWORD 'PowerSync2025!';

-- Grant necessary permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_user;
GRANT USAGE ON SCHEMA public TO powersync_user;

-- Ensure future tables are also accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_user;
```

### 2. Create Publication (Required)

Run in Supabase SQL Editor:

```sql
-- Create the publication that PowerSync needs for replication
CREATE PUBLICATION powersync FOR TABLE
    roster_entries,
    group_images,
    sports_jobs;
```

### 3. Connection String

Use the Direct connection string from Supabase (port 5432, not the pooler):

```
postgresql://postgres:YOUR_DATABASE_PASSWORD@db.YOUR_PROJECT_REF.supabase.co:5432/postgres
```

Or with the dedicated replication user:

```
postgresql://powersync_user:PowerSync2025!@db.YOUR_PROJECT_REF.supabase.co:5432/postgres
```

## PowerSync Dashboard

1. Sign up at [powersync.com](https://www.powersync.com)
2. Create a new instance
3. Paste the connection string
4. Define sync rules (see below)

## Adding Tables to Publication

If you add new tables that need syncing, run:

```sql
ALTER PUBLICATION powersync ADD TABLE new_table_name;
```

## Troubleshooting

| Error | Solution |
|-------|----------|
| `Publication 'powersync' not found` | Run the CREATE PUBLICATION command above |
| `Password authentication failed` | Verify you're using the database password (not Supabase account password) |
| `Connection refused` | Make sure you're using port 5432 (Direct connection), not 6543 (Pooler) |
