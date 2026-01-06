---
order: 653
title: PlanetScale
top_section: Juntos
category: juntos/databases
hide_in_toc: true
---

PlanetScale is serverless MySQL with a Git-like branching workflow. Great for teams that need MySQL compatibility.

{% toc %}

## Overview

| Feature | Value |
|---------|-------|
| Database | MySQL 8.0 |
| Protocol | HTTP |
| Free Tier | 5 GB storage, 1B row reads/mo |
| Best For | MySQL apps, branching workflow |

## Quick Start

### 1. Create Account

Sign up at [planetscale.com](https://planetscale.com) (GitHub login available).

### 2. Install CLI (Optional)

```bash
# macOS
brew install planetscale/tap/pscale

# Linux
curl -sSfL https://get.planetscale.com/download | bash
```

### 3. Create Database

**Via Dashboard:**
1. Click **New database**
2. Choose a region
3. Name your database

**Via CLI:**
```bash
pscale auth login
pscale database create myapp --region us-east
```

### 4. Create Branch Password

1. Go to **Branches** → **main**
2. Click **Connect**
3. Select **Node.js** → **@planetscale/database**
4. Copy the connection string

### 5. Configure Juntos

Add to `.env.local`:

```bash
PLANETSCALE_URL=mysql://username:password@aws.connect.psdb.cloud/myapp?ssl={"rejectUnauthorized":true}
```

### 6. Deploy

```bash
bin/juntos db:prepare -d planetscale
bin/juntos deploy -d planetscale
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PLANETSCALE_URL` | Yes | Connection string from dashboard |

## Branching Workflow

PlanetScale's killer feature is database branching—like Git for your schema.

### Create a Branch

```bash
# Via CLI
pscale branch create myapp add-users

# Or via dashboard
```

### Make Schema Changes

Connect to your branch and run migrations:

```bash
# Point to development branch
PLANETSCALE_URL=mysql://...@add-users.aws.connect.psdb.cloud/myapp

bin/juntos db:migrate -d planetscale
```

### Create Deploy Request

```bash
pscale deploy-request create myapp add-users
```

### Review and Merge

1. Review the schema diff in dashboard
2. Approve the deploy request
3. PlanetScale applies changes to main without downtime

## Safe Migrations

PlanetScale uses Vitess for online schema changes. Large tables can be altered without locking:

```ruby
# This won't lock the users table
add_column :users, :avatar_url, :string
```

### Deploy Requests

For production changes, use deploy requests instead of direct migrations:

1. Create branch: `pscale branch create myapp feature`
2. Run migrations on branch
3. Create deploy request
4. Review schema diff
5. Merge when ready

## Foreign Key Considerations

PlanetScale doesn't enforce foreign keys at the database level (Vitess limitation). Instead:

- Use application-level validations
- The schema still documents relationships
- Referential integrity is your responsibility

```ruby
# Foreign keys are documented but not enforced
class Comment < ApplicationRecord
  belongs_to :post
  validates :post, presence: true  # Application-level enforcement
end
```

## Connection String Format

PlanetScale provides different connection formats. Use the `@planetscale/database` format for serverless:

```
mysql://username:password@aws.connect.psdb.cloud/database?ssl={"rejectUnauthorized":true}
```

**Important:** The SSL parameter is required for secure connections.

## Regions

Choose a region close to your deployment:

| Region | Location |
|--------|----------|
| `us-east` | N. Virginia |
| `us-west` | Oregon |
| `eu-west` | Ireland |
| `ap-south` | Mumbai |
| `ap-southeast` | Singapore |
| `ap-northeast` | Tokyo |

## Troubleshooting

### Access denied

1. Verify your password hasn't expired
2. Create a new password in the dashboard
3. Update `.env.local`

### Foreign key errors

PlanetScale doesn't support foreign key constraints. Remove `foreign_key: true` from migrations:

```ruby
# Instead of:
add_reference :comments, :post, foreign_key: true

# Use:
add_reference :comments, :post
```

### Connection timeout

PlanetScale connections may timeout after 5 minutes of inactivity. The adapter handles reconnection automatically.

## Insights

PlanetScale provides query insights in the dashboard:

- Slow queries
- Query patterns
- Index recommendations

Use these to optimize your application.

## Pricing

| Tier | Storage | Row Reads | Row Writes | Price |
|------|---------|-----------|------------|-------|
| Hobby | 5 GB | 1B/mo | 10M/mo | $0 |
| Scaler | 10 GB | 100B/mo | 50M/mo | $29/mo |

The free tier is suitable for small to medium applications.

## Resources

- [PlanetScale Documentation](https://docs.planetscale.com)
- [PlanetScale CLI Reference](https://docs.planetscale.com/reference/planetscale-cli)
- [Branching Overview](https://docs.planetscale.com/concepts/branching)
