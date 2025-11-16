# MemberManager

MemberManager is a Rails application that keeps a local roster synchronized with an Authentik group. Users authenticate via Authentik (OpenID Connect), and the application periodically (or on-demand) refreshes the local database using the Authentik API.

## Requirements

- Ruby 3.3.10 (see `.ruby-version`)
- Rails 7.1.6
- PostgreSQL 16+
- Node.js (only for asset builds when running locally)
- Yarn

You can also run everything via Docker/Docker Compose (see below).

## Getting Started

```bash
bundle install
bin/rails db:prepare
bin/dev # starts Rails + CSS watcher
```

### Environment Variables

Set these variables in your shell, `.env`, or Docker Compose environment:

| Variable | Description |
| --- | --- |
| `APP_BASE_URL` | Public URL of the app (used by OmniAuth), e.g. `http://localhost:3000` |
| `AUTHENTIK_ISSUER` | Issuer URL from the Authentik application (ends with `/application/o/<slug>/`) |
| `AUTHENTIK_CLIENT_ID` / `AUTHENTIK_CLIENT_SECRET` | OAuth credentials from Authentik |
| `AUTHENTIK_REDIRECT_URI` | Callback URL registered in Authentik (default `http://localhost:3000/auth/authentik/callback`) |
| `AUTHENTIK_API_BASE_URL` | Base URL for Authentik's API (defaults to the issuer) |
| `AUTHENTIK_API_TOKEN` | Token with permission to read group membership |
| `AUTHENTIK_GROUP_ID` | UUID/slug of the Authentik group to sync |
| `AUTHENTIK_GROUP_PAGE_SIZE` | Optional page size override when fetching group members (default 200) |
| `SLACK_API_TOKEN` | Slack Bot/User OAuth token with at least `users:read` scope |
| `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DB_PORT` | Database connection settings |
| `DATABASE_URL` | Optional full PostgreSQL URL (overrides the individual DB vars) |
| `LOCAL_AUTH_ENABLED` | Set to `true` to enable local (database) accounts |
| `LOCAL_AUTH_EMAIL`, `LOCAL_AUTH_PASSWORD`, `LOCAL_AUTH_FULL_NAME` | (Optional) Default credentials to seed a test admin account |
| `GOOGLE_SHEETS_CREDENTIALS` | JSON for a Google service account with Sheets read access |
| `GOOGLE_SHEETS_ID` | Spreadsheet ID of the roster workbook |
| `PAYPAL_CLIENT_ID` / `PAYPAL_CLIENT_SECRET` | PayPal REST credentials for the reporting API |
| `PAYPAL_API_BASE_URL` | Optional override (defaults to `https://api-m.paypal.com`) |
| `PAYPAL_TRANSACTIONS_LOOKBACK_DAYS` | Days of history to pull during sync (default 30) |
| `RECHARGE_API_KEY` | Recharge API access token |
| `RECHARGE_API_BASE_URL` | Optional override (defaults to `https://api.rechargeapps.com`) |
| `RECHARGE_TRANSACTIONS_LOOKBACK_DAYS` | Days of Recharge history to pull during sync (default 30) |

## Docker & Compose

Build and run the stack with:

```bash
docker compose up --build
```

This starts a Postgres container (`db`) and a Rails container (`web`). The current workspace is mounted into the `web` container for live development.

## Authentik Integration

- OpenID Connect login is configured via OmniAuth (`/auth/authentik`).
- User sessions are persisted in the local database. The first successful login will create/refresh the corresponding `User` record.
- To synchronize an Authentik group into the database, use:
  - The **Sync now** button on the Users page.
  - `rails authentik:sync_users`
  - `Authentik::GroupSyncJob.perform_later`

The sync job fetches all members of the configured group, updates existing users, creates new ones, and deactivates local users no longer in Authentik.
Member records also capture the raw Authentik `attributes` payload in a searchable `authentik_attributes` JSON column (GIN indexed). Query helper example:

```ruby
User.with_attribute(:department, "Engineering")
```

## Slack Integration

Set `SLACK_API_TOKEN` (bot or user token with `users:read`) to enable Slack syncing. Then run:

```bash
rails slack:sync_users
```

This job calls `users.list`, follows pagination cursors, and mirrors each member into the `slack_users` table (including admin flags, time zone, profile info, and a searchable `raw_attributes` JSONB column backed by a GIN index). Example query:

```ruby
SlackUser.active.with_attribute(:department, "IT")
```

## RFID Sign-In

When Authentik users include an `rfid` attribute (populated via the group sync), the login page exposes a **Sign in via RFID** form. Scanning/entering a value that matches `authentik_attributes["rfid"]` on an active user signs that person in immediately—handy for badge readers or kiosk setups.

## Google Sheet Intake

Provide `GOOGLE_SHEETS_CREDENTIALS` (the full JSON for a service account key) and `GOOGLE_SHEETS_ID` (from the sheet URL). Then run:

```bash
rails google_sheets:sync
```

The sync job pulls both the **Member List** and **Access** tabs, normalizes their columns, and merges them into the `sheet_entries` table. Member/Access rows are matched by email (falling back to name) so that access permissions end up on the same record. Each row's original data is retained in `SheetEntry#raw_attributes` for advanced filtering or auditing. Browse the current import inside the app under **Sheet Entries** (navbar) for a searchable list plus detailed drill-down.

## PayPal Payments

Provide `PAYPAL_CLIENT_ID` / `PAYPAL_CLIENT_SECRET` (and optionally override `PAYPAL_API_BASE_URL`). Then run:

```bash
rails paypal:sync_payments
```

The sync job calls PayPal’s Transaction Reporting API for the configured lookback window, stores each payment in the `paypal_payments` table (including raw JSON), and exposes them under **PayPal Payments** in the UI with quick totals, detail pages, and a “Sync now” button. Payments automatically link to Authentik users and Sheet entries when the payer email matches, so each profile page now shows its payment history as well.

## Recharge Payments

Set `RECHARGE_API_KEY` (and optionally override the base URL/lookback days) to enable Recharge syncing, then run:

```bash
rails recharge:sync_payments
```

The sync job pulls recent charges from Recharge, records them in `recharge_payments`, and surfaces them inside the app under **Recharge Payments** plus in each Authentik/Sheet profile’s payment history (alongside PayPal results).

### Local Test Accounts

Local accounts are intended for development or emergency access when Authentik is unavailable:

1. Set `LOCAL_AUTH_ENABLED=true` in your environment.
2. (Optional) Provide `LOCAL_AUTH_EMAIL` / `LOCAL_AUTH_PASSWORD` / `LOCAL_AUTH_FULL_NAME` so `bin/rails db:seed` can create a bootstrap admin.
3. Visit `/login` and use the **Sign in locally** form. Successful local logins still create a matching `User` record so the rest of the app behaves the same way.

## Tests

```bash
bin/rails test
```

## Next Steps

- Configure a scheduler (cron/ActiveJob) to run `Authentik::GroupSyncJob` periodically.
- Deploy using the provided Dockerfile or your preferred Rails hosting platform.
