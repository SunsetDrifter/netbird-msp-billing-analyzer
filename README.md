# NetBird MSP Billing Analyzer

Command-line tool for NetBird Managed Service Providers to analyze billing usage and plans across all managed tenants.

## Features

- Analyze registered users vs billable users across all MSP tenants
- Display billing plan for each tenant (Team, Business)
- Estimate per-tenant and portfolio invoices with the MSP partner discount applied
- Surface MSP master subscription, latest closed invoices, and current open cycle anchor
- Detect tenant/master currency mismatches before they reach billing
- Generate human-readable text, structured JSON, and self-attributing CSV outputs
- Secure API token handling via environment variables

## Quick Start

### Installation

**One-line install (recommended):**
```bash
curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/install.sh | bash
```

**Options:**
- `--user` - Install to user directory (no sudo required)
- `--help` - Show all installation options
- `--uninstall` - Remove installation

**Features:** ✅ Auto-installs dependencies ✅ Works on macOS/Linux ✅ Manages PATH automatically

### Setup API Token

1. **Get your NetBird API token:**
   - Log into your NetBird MSP dashboard
   - Go to Team → Service Users → Create Service User → Create Access Token
   - Generate a new API token with **Admin permissions**

2. **Set the token:**
   ```bash
   export NETBIRD_API_TOKEN="your_token_here"
   ```

### Usage

```bash
# Run the analyzer
netbird-msp-analyzer

# Or with inline token
NETBIRD_API_TOKEN="your_token_here" netbird-msp-analyzer
```

## Output Files

By default the script generates three timestamped reports — `.txt`, `.json`, and `.csv`. Use `--json-only`, `--text-only`, or `--no-csv` to suppress any of them.

### 1. Text Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.txt`)
- Human-readable format with MSP-account banner, per-tenant breakdown, and invoice estimates
- Currency-mismatch warning surfaced inline if any tenant diverges from the master
- Executive summary with discount tier and per-currency totals

### 2. JSON Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.json`)
- `schema_version` at the root for forward-compat
- `msp_account` block (master subscription, latest invoices, current open period anchor)
- `tenant_details[]` with subscription, metrics, billing usage, registered users, and pricing
- `executive_summary` with totals, discount, and `currency_consistency` block

### 3. CSV Summary (`netbird_comprehensive_YYYYMMDD_HHMMSS.csv`)
- One row per tenant; every row carries `snapshot_taken_at`, `msp_account_id`, and `current_open_period_started_at` so concatenated snapshots stay self-attributing
- All money in integer cents (`per_user_list_price_cents`, `gross_estimate_cents`, `discount_amount_cents`, `net_estimate_cents`)
- Explicit `priceable` and `subscription_active` boolean columns (typed bools via `@csv`, no NULL inference)
- Stripe `price_id` and `provider` columns for direct join with your billing system

### Sample JSON Structure

```json
{
  "schema_version": 1,
  "report_metadata": {
    "generated_at": "2026-05-05T18:40:17Z",
    "billing_cycle_note": "NetBird MSP issues two invoices each cycle: type=\"account\" (master) and type=\"tenants\" (consolidated). See msp_account.billing_periods.",
    "version": "v0.11.0"
  },
  "msp_account": {
    "id": "...",
    "name": "...",
    "subscription": {
      "plan_tier_id": "business",
      "per_user_list_price_cents": 1200,
      "price_id": "price_1OrdvHKina3I2KUbPXVVGkRt",
      "provider": "stripe"
    },
    "billing_periods": {
      "latest_account_invoice": {"id": "in_...", "period_start": "...", "period_end": "..."},
      "latest_tenants_invoice": {"id": "in_...", "period_start": "...", "period_end": "..."},
      "current_open_period_started_at": "<latest_tenants_invoice.period_end>"
    }
  },
  "executive_summary": {
    "total_tenants": 4,
    "total_registered_users": 150,
    "total_billable_users": 120,
    "msp_discount_pct": 30,
    "tenants_priced": 4,
    "tenants_skipped_unpriced": 0,
    "currency_consistency": {
      "master_currency": "usd",
      "is_consistent": true,
      "divergent_tenants": []
    },
    "totals_by_currency": {
      "usd": {
        "gross_estimate_cents": 144000,
        "discount_amount_cents": 43200,
        "net_estimate_cents": 100800
      }
    }
  },
  "tenant_details": [{
    "tenant_info": {"id": "...", "name": "...", "billing_plan": "Team", "billing_plan_id": "team"},
    "subscription": {
      "plan_tier_id": "team",
      "currency": "usd",
      "per_user_list_price_cents": 600,
      "price_id": "price_1SZc3pKina3I2KUblUEXpQS7",
      "provider": "stripe",
      "active": true,
      "updated_at": "..."
    },
    "metrics": {"registered_active_users": 12, "billable_active_users": 10},
    "pricing": {
      "priceable": true,
      "currency": "usd",
      "per_user_list_price_cents": 600,
      "billable_users": 10,
      "gross_estimate_cents": 6000,
      "discount_pct": 30,
      "discount_amount_cents": 1800,
      "net_estimate_cents": 4200
    }
  }]
}
```

### Designed for Billing Integrations

- **All monetary values are integer cents** (e.g. `600` = $6.00). Stripe-style — no floating-point precision loss.
- **`schema_version`** at the JSON root lets consumers gate against future shape changes.
- **MSP master subscription is fully isolated from tenant totals.** NetBird issues two separate invoices to MSPs (one for the master account, one consolidated for tenants), so this analyzer keeps them apart: `tenant_details[]`, `executive_summary.total_*`, `executive_summary.totals_by_currency`, the invoice-estimates table, and every CSV row are tenant-only. The master account is exposed *only* under the top-level `msp_account` block.
- **The report is a point-in-time snapshot**, not an invoice. NetBird issues two invoices per cycle to MSPs: one for the master account (`type: "account"`) and one consolidated invoice covering all tenants (`type: "tenants"`). The latest closed invoice of each type is exposed under `msp_account.billing_periods`.
- **Current open cycle** for the consolidated tenant invoice starts at `msp_account.billing_periods.current_open_period_started_at` (= the latest closed tenant invoice's `period_end`). NetBird does not expose the *end* of the open period; use Stripe (via `msp_account.subscription.price_id`) for authoritative `current_period_end`.
- **`subscription.price_id`** is the upstream Stripe price ID — use this as the SKU when mapping to your billing system. Each tenant has its own `subscription.price_id` and the master account has one too (under `msp_account.subscription.price_id`).
- **CSV rows are self-attributing**: every row carries `snapshot_taken_at`, `msp_account_id`, and `current_open_period_started_at`, so concatenated snapshots don't lose context.
- **Per-tenant `pricing` and portfolio `executive_summary.totals_by_currency` use identical field names** (`gross_estimate_cents` / `discount_amount_cents` / `net_estimate_cents`) so a single parser handles both.

## Understanding the Analysis

### Key Metrics

- **Registered Users**: Active, unblocked users in NetBird
- **Billable Users**: Users who connected during the current billing cycle
- **Billing Plan**: Current subscription tier (Team, Business)

### Interpreting Results

- Compare registered vs billable users to understand actual usage
- Review billing plans across tenants for consistency
- Identify users who haven't logged in recently

### Invoice Estimates

The report includes an `INVOICE ESTIMATES` section that turns billable user counts into a dollar/euro estimate using each tenant's actual list price (read live from `integrations/billing/subscription.price`) plus the MSP partner discount.

**MSP partner discount** — applied to every priceable tenant based on the **total** active users across the entire MSP portfolio (not per-tenant):

| Total active users | Discount |
| --- | --- |
| 0–99 | 20% |
| 100–499 | 30% |
| 500+ | 35% |

**Currency** is read live per-subscription (master + per-tenant) from the API — no hardcoded assumption. Symbols (`$` / `€` / `£`) and per-currency subtotals are driven by that field. Mixed-currency portfolios get separate per-currency subtotals (no FX conversion).

**Currency consistency check** — the consolidated tenant invoice rolls up under a single currency, so the analyzer compares each tenant's currency against the MSP master subscription's currency. Any divergence is flagged inline in the text report (`⚠️ CURRENCY MISMATCH DETECTED`) and exposed in `executive_summary.currency_consistency` for automated alerting.

**Enterprise tenants** and tenants where the API doesn't return a price are reported as `N/A` and excluded from totals.

Estimates are pre-tax — actual invoices may differ due to negotiated terms, coupons, mid-cycle changes, or proration. All times are UTC.

## Troubleshooting

### Common Issues

1. **"jq not found"**: Install jq with `brew install jq` (macOS) or your system's package manager
2. **"Token not set"**: Ensure your `.env` file exists and contains `NETBIRD_API_TOKEN=your_token`
3. **"Failed to fetch tenants"**: Check token permissions and NetBird API access
4. **"Plan detection failed"**: Verify token has billing subscription access permissions
5. **HTTP errors**: Verify your API token is valid and has necessary permissions

## Security Considerations

- Never expose your API token in logs, scripts, or version control
- Rotate API tokens regularly according to your security policies

## License

This tool is provided as-is for NetBird MSP customers. Ensure compliance with your NetBird service agreement.

## Manual Installation

<details>
<summary>Click to expand manual installation instructions</summary>

### Prerequisites
- Bash, curl, jq
- NetBird MSP account with API access

### Steps
1. Download: `curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/analyzer.sh -o netbird-msp-analyzer`
2. Make executable: `chmod +x netbird-msp-analyzer`
3. Optionally move to PATH: `sudo mv netbird-msp-analyzer /usr/local/bin/`
4. Set API token: `export NETBIRD_API_TOKEN="your_token"`

</details>

## Support

- **NetBird API issues**: Contact NetBird support
- **Tool issues**: Check the troubleshooting section
