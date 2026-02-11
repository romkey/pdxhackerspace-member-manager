# Membership Status State Machine

This document describes how membership status, dues status, and member activity changes in the MemberManager application.

## Overview

The system tracks three key member state fields:

- **`membership_status`** — Overall membership classification (paying, guest, banned, deceased, sponsored, applicant, cancelled, unknown)
- **`dues_status`** — Payment currency (current, lapsed, inactive, unknown)
- **`active`** — Boolean flag indicating if member can access resources

These fields are updated automatically through payment linking, manual admin actions, and scheduled jobs.

---

## Core Fields

### User Model Schema

```ruby
# Status fields
membership_status    # string, default: 'unknown'
dues_status          # string, default: 'unknown'
active               # boolean, default: false, null: false
payment_type         # string, default: 'unknown'

# Payment tracking
last_payment_date               # date
membership_start_date           # date
membership_ended_date           # date
recharge_most_recent_payment_date  # datetime
paypal_account_id               # string
recharge_customer_id            # string
```

### Allowed Values

**membership_status enum:**
- `paying` — Actively paying member
- `guest` — Guest access
- `banned` — Access denied
- `deceased` — Member passed away
- `sponsored` — Sponsored membership (free)
- `applicant` — Pending membership application
- `cancelled` — Cancelled membership
- `unknown` — Default/unclear status

**dues_status values:**
- `current` — Dues paid and current
- `lapsed` — Previously current, now overdue
- `inactive` — No active payment history
- `unknown` — Default/unclear status

**payment_type values:**
- `paypal` — Pays via PayPal
- `recharge` — Pays via Recharge
- `kofi` — Pays via Ko-Fi
- `cash` — Pays cash (manual)
- `sponsored` — Sponsored (no payment)
- `inactive` — No payment
- `unknown` — Default/unclear type

---

## Automatic State Transitions

### The 32-Day Rule

The most important state transition rule is the **32-day cutoff**. When a payment is linked and it occurred within the last 32 days:

```ruby
active = true
membership_status = 'paying'
dues_status = 'current'
membership_ended_date = nil  # cleared if present
```

This rule applies to:
- PayPal payment linking
- Recharge payment linking
- Ko-Fi payment linking
- Manual dues marking
- Payment sync rake tasks

### Payment Older Than 32 Days

If the payment is older than 32 days:
- Status fields are **not** automatically updated to current
- The payment is recorded and tracked
- `dues_status` may be set to `lapsed` (if currently `current`)

### Deceased Members

Via `before_save` callback `deactivate_if_deceased`:

```ruby
if membership_status == 'deceased'
  active = false
  payment_type = 'inactive'
end
```

This ensures deceased members are always inactive.

### Sponsored Members

Sponsored members are always considered current:
```ruby
dues_status = 'current'  # enforced in various places
```

---

## Payment Linking Workflow

### PayPal Payment Linking

When a `PaypalPayment` is linked to a user (via `user_id` being set):

1. **Trigger:** `after_save :notify_user_of_link, if: :user_id_changed_to_present?`
2. **Calls:** `user.on_paypal_payment_linked(payment)`
3. **Updates:**
   ```ruby
   paypal_account_id = payment.payer_id
   payment_type = 'paypal'
   # Merge email if different
   # Apply payment updates (32-day rule)
   # Link all other PayPal payments with same payer_id
   ```

### Recharge Payment Linking

When a `RechargePayment` is linked to a user:

1. **Trigger:** `after_save :notify_user_of_link, if: :user_id_changed_to_present?`
2. **Calls:** `user.on_recharge_payment_linked(payment)`
3. **Updates:**
   ```ruby
   recharge_customer_id = payment.customer_id
   payment_type = 'recharge'
   recharge_most_recent_payment_date = payment.processed_at
   # Merge email if different
   # Apply payment updates (32-day rule)
   # Link all other Recharge payments with same customer_id
   ```

### Ko-Fi Payment Linking

When a Ko-Fi payment is manually linked:

```ruby
payment_type = 'kofi'
# If payment within 32 days:
active = true
membership_status = 'paying'
dues_status = 'current'
```

### Payment Matching Logic

Payments are matched to users in order of preference:

**PayPal:**
1. `paypal_account_id` matches `payer_id`
2. Email matches (primary or extra_emails)
3. Full name matches

**Recharge:**
1. `recharge_customer_id` matches `customer_id`
2. Email matches (primary or extra_emails)
3. Full name matches

---

## Scheduled Jobs

### Daily Payment Synchronization

**Time:** 6:00 AM daily (configured in `config/initializers/sidekiq.rb`)

**Jobs:**
- `Paypal::PaymentSyncJob` — Fetches new PayPal transactions, matches to users, triggers linking callbacks
- `Recharge::PaymentSyncJob` — Fetches new Recharge charges (SUCCESS status only), matches to users, triggers linking callbacks

**Effect:**
- New payments are linked automatically
- User statuses update via payment linking callbacks (32-day rule applies)

---

## Rake Tasks

### `payments:link`

Bulk links existing unlinked payments to users.

**Process:**
1. Build lookup tables for PayPal (`payer_id` → `user_id`) and Recharge (`customer_id` → `user_id`)
2. Link PayPal payments (by ID, email, or name)
3. Link Recharge payments (by ID, email, or name)
4. Update user statuses based on payment dates:
   - If payment within 32 days: `active = true`, `membership_status = 'paying'`, `dues_status = 'current'`
   - If payment older than 32 days: `dues_status = 'lapsed'` (if currently `current`)
5. Set `payment_type` based on most recent payment source
6. Update membership dates:
   - `membership_start_date` = 1 month after earliest payment
   - `membership_ended_date` = 1 month after last payment (only if > 32 days ago)
7. Match membership plans from PayPal transaction subjects

**Usage:**
```bash
rails payments:link
rails payments:link_stats  # dry run
```

### `payments:link_orphans`

Links payments where one payment from a customer is linked but others aren't (same `payer_id` or `customer_id`).

### `membership:recalculate_status`

Resets and recalculates all user statuses based on:
- Payments
- Sheet entries
- Current membership settings

---

## Manual Admin Actions

### Users Controller

**Activate/Deactivate:**
```ruby
# POST /users/:id/activate
user.update!(active: true)

# POST /users/:id/deactivate
user.update!(active: false)
```

**Ban:**
```ruby
# POST /users/:id/ban
user.update!(
  membership_status: 'banned',
  active: false
)
```

**Mark Deceased:**
```ruby
# POST /users/:id/mark_deceased
user.update!(
  membership_status: 'deceased',
  active: false
)
# Callback also sets payment_type = 'inactive'
```

**Update (Admin only):**
- Can set any `membership_status`, `payment_type`, `active` value
- Can change `membership_plan_id`

### Reports Controller (Bulk Actions)

Supports bulk status updates on multiple users:

- **activate** / **deactivate** — Sets `active` flag
- **ban** — Sets `membership_status = 'banned'`, `active = false`
- **deceased** — Sets `membership_status = 'deceased'`, `active = false`, `payment_type = 'inactive'`
- **paying** — Sets `membership_status = 'paying'`
- **sponsored** — Sets `membership_status = 'sponsored'` or `payment_type = 'sponsored'`
- **guest** — Sets `membership_status = 'guest'` or `payment_type = 'guest'`
- **cash** / **paypal** / **recharge** — Sets `payment_type`

### Manual Payment Plans: Mark Dues Received

**Location:** Membership Plans > Manual Payment Plan Members

**Effect:**
```ruby
dues_status = 'current'
last_payment_date = Date.current
active = true
membership_status = 'paying'
# Journal entry created
```

**Availability:**
- Only for users on manual payment plans
- Button enabled when:
  - Next payment date ≤ 7 days away, OR
  - Next payment date is overdue, OR
  - Next payment date is nil

---

## Next Payment Date Calculation

The system calculates when the next payment is expected based on:

```ruby
most_recent_payment = [
  last_payment_date,
  recharge_most_recent_payment_date,
  max(paypal_payments.transaction_time),
  max(recharge_payments.processed_at)
].compact.max

case membership_plan.billing_frequency
when 'monthly'
  most_recent_payment + 1.month
when 'yearly'
  most_recent_payment + 1.year
when 'one-time'
  nil  # one-time payments don't renew
end
```

Used for:
- Displaying "Renews on [date]" on member profiles
- Determining if dues marking button should be enabled
- Reactivation grace period calculations

---

## Reactivation Grace Period

**Setting:** `MembershipSetting.reactivation_grace_period_months` (default: varies by installation)

**Purpose:** Determines if a lapsed member can reactivate without re-orientation.

**Methods:**
```ruby
# Check if last payment is within grace period
user.within_reactivation_grace_period?
  # true if last_payment >= grace_months.months.ago

# Check if past grace period (needs re-orientation)
user.past_reactivation_grace_period?
  # true if dues_status == 'lapsed' AND last_payment < grace_months.months.ago

# When grace period expires
user.reactivation_expires_on
  # last_payment + grace_months.months
```

---

## Google Sheets Sync

**Controller:** `SheetEntriesController#sync_all`

Syncs user data from a Google Sheet (legacy system):

**Updates:**
- `active` — Sets to false if sheet entry status contains "inactive"
- `payment_type` — Extracted from sheet entry status
- `membership_status` — Sets to 'sponsored' if payment_type is sponsored and status is 'unknown'
- Creates new users with appropriate statuses based on sheet data

**Frequency:** Manual (triggered by admin via "Sync from Sheet" button)

---

## Login Behavior

When a user logs in via OAuth:

```ruby
# app/controllers/sessions_controller.rb:302
user.update!(active: true)
```

This ensures users can access the system after authentication.

---

## State Transition Summary

### Automatic Transitions

| Trigger | Effect |
|---------|--------|
| Payment within 32 days linked | `active = true`, `membership_status = 'paying'`, `dues_status = 'current'` |
| Payment > 32 days linked | `dues_status = 'lapsed'` (if currently `current`) |
| `membership_status = 'deceased'` saved | `active = false`, `payment_type = 'inactive'` |
| User logs in | `active = true` |
| Daily PayPal/Recharge sync | Links new payments → triggers payment callbacks |

### Manual Transitions (Admin)

| Action | Effect |
|--------|--------|
| Activate | `active = true` |
| Deactivate | `active = false` |
| Ban | `membership_status = 'banned'`, `active = false` |
| Mark Deceased | `membership_status = 'deceased'`, `active = false`, `payment_type = 'inactive'` |
| Mark Dues Received (Manual Plans) | `active = true`, `membership_status = 'paying'`, `dues_status = 'current'`, `last_payment_date = today` |
| Edit User (Admin) | Any field can be set to any valid value |
| Bulk Update (Reports) | Various status changes depending on action |

---

## Edge Cases and Special Behaviors

### Sponsored Members
- Always `dues_status = 'current'`
- `payment_type = 'sponsored'`
- No payment tracking needed

### Deceased Members
- `before_save` callback enforces `active = false` and `payment_type = 'inactive'`
- Cannot be overridden unless `membership_status` is changed first

### Multiple Payment Sources
- `payment_type` set to most recent payment source
- All payment dates are tracked independently
- `last_payment_date` is the maximum of all sources

### Membership Dates
- `membership_start_date` — 1 month after earliest payment (set by `payments:link` task)
- `membership_ended_date` — 1 month after last payment, only if last payment > 32 days ago
- Used for display ("Member since...") not for access control

### Plan Matching
- PayPal payments match plans via `paypal_transaction_subject`
- When matched, `membership_plan_id` may be set automatically
- Plan determines billing frequency for next payment calculation

---

## Data Flow Diagram

```
Payment Source (PayPal/Recharge/Ko-Fi)
    ↓
Payment Synchronizer (Daily 6am or Manual)
    ↓
Payment Matching (ID → Email → Name)
    ↓
Payment Linked (user_id set)
    ↓
Payment Callback (on_paypal_payment_linked / on_recharge_payment_linked)
    ↓
apply_payment_updates(payment_date)
    ↓
32-Day Check:
    If payment ≤ 32 days ago:
        ✓ active = true
        ✓ membership_status = 'paying'
        ✓ dues_status = 'current'
        ✓ membership_ended_date = nil
    If payment > 32 days ago:
        ✓ dues_status = 'lapsed' (if currently 'current')
        ✓ No other changes
```

---

## Testing Scenarios

### Scenario 1: New Member Signs Up via PayPal

1. Member pays via PayPal
2. Daily sync job fetches transaction
3. Payment matched by email
4. PayPal payment linked → `user.on_paypal_payment_linked(payment)`
5. Payment is within 32 days → all statuses set to active/current/paying
6. Membership plan matched from transaction subject
7. Next payment date calculated

**Expected State:**
```ruby
active: true
membership_status: 'paying'
dues_status: 'current'
payment_type: 'paypal'
last_payment_date: (payment date)
```

### Scenario 2: Member's Payment Lapses

1. Member's last payment was 35 days ago
2. Rake task `payments:link` runs (or manual update)
3. Payment is > 32 days old → `dues_status` set to 'lapsed'
4. `membership_ended_date` set to 1 month after last payment

**Expected State:**
```ruby
active: (unchanged)
membership_status: (unchanged)
dues_status: 'lapsed'
membership_ended_date: last_payment_date + 1.month
```

### Scenario 3: Manual Payment Plan Member Pays Cash

1. Admin navigates to "Manual Payment Plan Members"
2. Member's next payment due date is approaching
3. Admin clicks "Mark Dues Received"
4. Journal entry created

**Expected State:**
```ruby
active: true
membership_status: 'paying'
dues_status: 'current'
last_payment_date: (today)
```

---

## Related Code Locations

- **User Model:** `app/models/user.rb`
- **Payment Models:** `app/models/paypal_payment.rb`, `app/models/recharge_payment.rb`, `app/models/kofi_payment.rb`
- **Synchronizers:** `app/services/paypal/payment_synchronizer.rb`, `app/services/recharge/payment_synchronizer.rb`
- **Controllers:** `app/controllers/users_controller.rb`, `app/controllers/reports_controller.rb`, `app/controllers/membership_plans_controller.rb`
- **Rake Tasks:** `lib/tasks/link_payments.rake`, `lib/tasks/membership.rake`
- **Scheduled Jobs:** `config/initializers/sidekiq.rb`
