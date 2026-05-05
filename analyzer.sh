#!/bin/bash

# NetBird MSP Comprehensive Billing Usage Report
# Uses NetBird's billing API to show actual billable vs registered users
# Provides detailed analysis with JSON output for MSP management

set -uo pipefail

readonly VERSION="v0.11.0"
readonly API_BASE="https://api.netbird.io/api"
readonly SCRIPT_NAME="$(basename "$0")"

# MSP partner discount tier from total portfolio active users (>= thresholds)
msp_discount_pct() {
    local total="$1"
    if   [ "$total" -ge 500 ]; then echo 35
    elif [ "$total" -ge 100 ]; then echo 30
    else                            echo 20
    fi
}

# Map raw plan_tier API key to a human label
plan_label() {
    case "$1" in
        team)       echo "Team" ;;
        business)   echo "Business" ;;
        enterprise) echo "Enterprise" ;;
        "")         echo "Unknown" ;;
        *)          echo "${1^}" ;;
    esac
}

# CLI options (set by parse_args)
output_dir=""
tenant_filter=""
json_only=false
text_only=false
csv_enabled=false
quiet=false

show_help() {
    cat << EOF
NetBird MSP Billing Analyzer ${VERSION}

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help              Show this help and exit
    -V, --version           Print version and exit
    -o, --output-dir DIR    Write reports to DIR (created if missing)
                            Default: current directory
    -t, --tenant ID         Run only against the given tenant ID
    --json-only             Skip writing the .txt report
    --text-only             Skip writing the .json report
    --csv                   Also write a .csv summary (one row per tenant)
    -q, --quiet             Suppress progress messages

ENVIRONMENT:
    NETBIRD_API_TOKEN       Required. NetBird MSP API token.
                            Loaded from .env in CWD if present.

OUTPUT:
    netbird_comprehensive_<timestamp>.txt   Human-readable report
    netbird_comprehensive_<timestamp>.json  Structured data
    netbird_comprehensive_<timestamp>.csv   One row per tenant (with --csv)

EOF
}

show_version() {
    echo "$VERSION"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -o|--output-dir)
                if [ $# -lt 2 ]; then
                    echo "❌ ERROR: $1 requires a directory argument" >&2
                    exit 2
                fi
                output_dir="$2"
                shift 2
                ;;
            -t|--tenant)
                if [ $# -lt 2 ]; then
                    echo "❌ ERROR: $1 requires a tenant ID argument" >&2
                    exit 2
                fi
                tenant_filter="$2"
                shift 2
                ;;
            --json-only)
                json_only=true
                shift
                ;;
            --text-only)
                text_only=true
                shift
                ;;
            --csv)
                csv_enabled=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            *)
                echo "❌ ERROR: Unknown option: $1" >&2
                echo "Run '$SCRIPT_NAME --help' for usage." >&2
                exit 2
                ;;
        esac
    done

    if [ "$json_only" = true ] && [ "$text_only" = true ]; then
        echo "❌ ERROR: --json-only and --text-only are mutually exclusive" >&2
        exit 2
    fi
}

log_progress() {
    if [ "$quiet" != true ]; then
        echo "$1"
    fi
}

# Output to console and (unless --json-only) the text report file
output() {
    echo "$1"
    if [ "$json_only" != true ] && [ -n "$text_output_file" ]; then
        echo "$1" >> "$text_output_file"
    fi
}

# Make a GET against the NetBird API. Echoes body on HTTP 200, returns nonzero otherwise.
make_api_call() {
    local endpoint="$1"
    local description="$2"

    local response
    response=$(curl -s -w "\n%{http_code}" -X GET "${API_BASE}/${endpoint}" \
         -H 'Accept: application/json' \
         -H "Authorization: Token ${TOKEN}" \
         --max-time 30 --connect-timeout 10)
    local curl_exit_code=$?

    if [ $curl_exit_code -ne 0 ]; then
        echo "❌ $description failed (curl error $curl_exit_code)" >&2
        return 1
    fi

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ -z "$http_code" ] || ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
        echo "❌ $description failed (invalid HTTP response)" >&2
        echo "Response: $response" >&2
        return 1
    fi

    if [ "$http_code" != "200" ]; then
        echo "❌ $description failed (HTTP $http_code)" >&2
        if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
            echo "   The API token is invalid, expired, or lacks the required permissions." >&2
            echo "   Generate a new Service User token with admin permissions in the NetBird dashboard." >&2
        fi
        echo "Response body: $body" >&2
        return 1
    fi

    echo "$body"
}

# Fetch tenant subscription from the billing endpoint. Echoes a normalized
# JSON object on stdout. On failure, echoes a fallback object with plan_tier_id=""
# (which the caller treats as Unknown) and returns nonzero.
#
# Output shape:
#   {
#     "plan_tier_id": "team",      // raw API key, "" on failure
#     "plan_tier": "Team",         // human label
#     "currency": "usd",           // lowercase ISO code, defaults to "usd"
#     "per_user_list_price_cents": 600,   // per-user list price in minor units (0 if absent)
#     "price_id": "price_abc",     // upstream price ID (Stripe), "" if absent
#     "provider": "stripe",        // upstream provider, "" if absent
#     "updated_at": "...",         // ISO-8601 UTC, "" if absent
#     "active": true               // subscription status; null if absent
#   }
fetch_subscription() {
    local tenant_id="$1"
    local endpoint="integrations/billing/subscription"
    local label="MSP master subscription"
    if [ -n "$tenant_id" ]; then
        endpoint="${endpoint}?account=${tenant_id}"
        label="Billing subscription for $tenant_id"
    fi
    local body
    body=$(make_api_call "$endpoint" "$label")
    local rc=$?

    if [ $rc -ne 0 ] || [ -z "$body" ]; then
        jq -n '{plan_tier_id: "", plan_tier: "Unknown", currency: "usd", per_user_list_price_cents: 0, price_id: "", provider: "", updated_at: "", active: null}'
        return 1
    fi

    # Normalize. plan_label() runs on the shell side because it's a shell helper.
    local plan_tier_id
    plan_tier_id=$(echo "$body" | jq -r '.plan_tier // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ "$plan_tier_id" = "null" ] && plan_tier_id=""
    local label
    label=$(plan_label "$plan_tier_id")

    echo "$body" | jq --arg label "$label" --arg tier_id "$plan_tier_id" '
        {
            plan_tier_id: $tier_id,
            plan_tier: $label,
            currency: ((.currency // "usd") | ascii_downcase),
            per_user_list_price_cents: (.price // 0),
            price_id: (.price_id // ""),
            provider: (.provider // ""),
            updated_at: (.updated_at // ""),
            active: (.active // null)
        }
    '

    if [ -z "$plan_tier_id" ]; then
        return 1
    fi
    return 0
}

parse_args "$@"

# Resolve output directory
if [ -n "$output_dir" ]; then
    mkdir -p "$output_dir" || {
        echo "❌ ERROR: Failed to create output directory: $output_dir" >&2
        exit 1
    }
fi

# Load .env if present
if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

if [ -z "${NETBIRD_API_TOKEN:-}" ]; then
    echo "❌ ERROR: NETBIRD_API_TOKEN environment variable is not set." >&2
    echo "" >&2
    echo "Setup Instructions:" >&2
    echo "1. Copy .env.example to .env: cp .env.example .env" >&2
    echo "2. Edit .env and set your NetBird API token" >&2
    echo "3. Alternatively, export the variable: export NETBIRD_API_TOKEN=your_token" >&2
    echo "" >&2
    echo "For more information, see README.md" >&2
    exit 1
fi

TOKEN="${NETBIRD_API_TOKEN}"

if ! command -v jq &> /dev/null; then
    echo "❌ ERROR: jq is required. Install with: brew install jq (macOS) or your system's package manager." >&2
    exit 1
fi

# Validate token + fetch tenants up-front (before printing the report banner so
# auth errors don't leave a half-rendered header).
log_progress "Validating API token..."
tenants_response=$(make_api_call "integrations/msp/tenants" "MSP tenants fetch")
if [ $? -ne 0 ] || [ -z "$tenants_response" ]; then
    echo "❌ ERROR: Failed to validate token / fetch tenants. See above for details." >&2
    exit 1
fi

# Apply --tenant filter if provided
if [ -n "$tenant_filter" ]; then
    tenants_response=$(echo "$tenants_response" | jq --arg id "$tenant_filter" '[.[] | select(.id == $id)]')
    tenant_count=$(echo "$tenants_response" | jq 'length')
    if [ "$tenant_count" -eq 0 ]; then
        echo "❌ ERROR: Tenant ID '$tenant_filter' not found in MSP account" >&2
        exit 1
    fi
else
    tenant_count=$(echo "$tenants_response" | jq 'length')
fi

# Sort by name (case-insensitive) for stable, scannable output
tenants_response=$(echo "$tenants_response" | jq 'sort_by(.name | ascii_downcase)')

# Fetch MSP-level context: account info, MSP metadata, master subscription, and
# invoice history. Each call is best-effort — on failure we proceed with blanks.
log_progress "Fetching MSP account context..."

msp_accounts_response=$(make_api_call "accounts" "MSP accounts list")
[ $? -ne 0 ] && msp_accounts_response=""
msp_info_response=$(make_api_call "integrations/msp" "MSP info")
[ $? -ne 0 ] && msp_info_response=""
msp_subscription_json=$(fetch_subscription "")
msp_invoices_response=$(make_api_call "integrations/billing/invoices" "MSP invoices")
[ $? -ne 0 ] && msp_invoices_response=""

if [ -n "$msp_accounts_response" ] && echo "$msp_accounts_response" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    msp_account_id=$(echo "$msp_accounts_response" | jq -r '.[0].id // ""')
    msp_account_created_at=$(echo "$msp_accounts_response" | jq -r '.[0].created_at // ""')
    msp_account_domain=$(echo "$msp_accounts_response" | jq -r '.[0].domain // ""')
else
    msp_account_id=""
    msp_account_created_at=""
    msp_account_domain=""
fi

if [ -n "$msp_info_response" ]; then
    msp_name=$(echo "$msp_info_response" | jq -r '.name // ""')
    msp_activated_at=$(echo "$msp_info_response" | jq -r '.activated_at // ""')
    msp_parent_owner_email=$(echo "$msp_info_response" | jq -r '.parent_owner_email // ""')
else
    msp_name=""
    msp_activated_at=""
    msp_parent_owner_email=""
fi

if [ -n "$msp_invoices_response" ]; then
    latest_account_invoice=$(echo "$msp_invoices_response" | jq '[.[] | select(.type == "account")] | sort_by(.period_end) | last // null')
    latest_tenants_invoice=$(echo "$msp_invoices_response" | jq '[.[] | select(.type == "tenants")] | sort_by(.period_end) | last // null')
else
    latest_account_invoice="null"
    latest_tenants_invoice="null"
fi

current_open_period_started_at=$(echo "$latest_tenants_invoice" | jq -r 'if . == null then "" else (.period_end // "") end')

msp_account_json=$(jq -n \
    --arg id "$msp_account_id" \
    --arg name "$msp_name" \
    --arg domain "$msp_account_domain" \
    --arg created_at "$msp_account_created_at" \
    --arg activated_at "$msp_activated_at" \
    --arg owner_email "$msp_parent_owner_email" \
    --argjson subscription "$msp_subscription_json" \
    --argjson latest_account_invoice "$latest_account_invoice" \
    --argjson latest_tenants_invoice "$latest_tenants_invoice" \
    --arg current_open "$current_open_period_started_at" \
    '{
        id: $id,
        name: $name,
        domain: $domain,
        created_at: $created_at,
        activated_at: $activated_at,
        parent_owner_email: $owner_email,
        subscription: $subscription,
        billing_periods: {
            latest_account_invoice: $latest_account_invoice,
            latest_tenants_invoice: $latest_tenants_invoice,
            current_open_period_started_at: (if $current_open == "" then null else $current_open end),
            note: "NetBird does not expose the open period end. Join subscription.price_id with your Stripe data for authoritative current_period_start/end."
        }
    }')

# Output paths
timestamp=$(date +"%Y%m%d_%H%M%S")
prefix="${output_dir:-.}/netbird_comprehensive_${timestamp}"
text_output_file=""
json_output_file=""
csv_output_file=""
[ "$json_only" != true ] && text_output_file="${prefix}.txt"
[ "$text_only" != true ] && json_output_file="${prefix}.json"
[ "$csv_enabled" = true ] && csv_output_file="${prefix}.csv"

output "═══════════════════════════════════════════════════════════"
output "          NETBIRD MSP COMPREHENSIVE BILLING REPORT"
output "═══════════════════════════════════════════════════════════"
output "Generated: $(date)"
output ""

if [ -n "$msp_name" ] || [ -n "$msp_account_id" ]; then
    output "🏢 MSP Account: ${msp_name:-Unknown}${msp_account_domain:+ (${msp_account_domain})}"
    [ -n "$msp_account_id" ] && output "🆔 Account ID:  $msp_account_id"
    if [ -n "$current_open_period_started_at" ]; then
        output "📅 Current open consolidated tenant cycle started: $current_open_period_started_at (UTC)"
        output "   (Cycle end is not exposed by NetBird's API — join price_id with Stripe for the exact bound.)"
    fi
    output ""
fi

output "📊 COMPREHENSIVE ANALYSIS:"
output "• Registered Users = Active & unblocked users in NetBird"
output "• Billable Users   = Users who connected in current billing cycle"
output "• This uses NetBird's official billing API for accurate data"
output ""

output "Found $tenant_count tenant(s)"
output ""

total_registered=0
total_billable=0
all_tenant_details=()

output "DETAILED TENANT ANALYSIS"
output "========================"

for i in $(seq 0 $((tenant_count - 1))); do
    tenant_info=$(echo "$tenants_response" | jq -r ".[$i]")
    tenant_id=$(echo "$tenant_info" | jq -r '.id')
    tenant_name=$(echo "$tenant_info" | jq -r '.name')
    tenant_domain=$(echo "$tenant_info" | jq -r '.domain')
    tenant_status=$(echo "$tenant_info" | jq -r '.status')

    output ""
    output "─────────────────────────────────────────────"
    output "🏢 Tenant: $tenant_name"
    output "🌐 Domain: $tenant_domain"
    output "🆔 ID: $tenant_id"
    output "📊 Status: $tenant_status"

    log_progress "  → Detecting billing plan..."
    subscription_json=$(fetch_subscription "$tenant_id")
    tenant_plan=$(echo "$subscription_json" | jq -r '.plan_tier')
    tenant_plan_id=$(echo "$subscription_json" | jq -r '.plan_tier_id')
    tenant_currency=$(echo "$subscription_json" | jq -r '.currency')
    tenant_price_cents=$(echo "$subscription_json" | jq -r '.per_user_list_price_cents')
    if [ "$tenant_plan" = "Unknown" ]; then
        output "🧾 Billing Plan: Unknown"
        output "   ⚠️  Plan detection failed; proceeding without plan info"
    else
        output "🧾 Billing Plan: $tenant_plan"
    fi

    if [ "$tenant_status" != "active" ]; then
        output "⚠️  Skipping inactive tenant"
        continue
    fi

    log_progress "  → Fetching registered users..."
    users_response=$(make_api_call "users?service_user=false&account=${tenant_id}" "Users for $tenant_name")
    registered_count=0
    user_details="[]"
    if [ $? -eq 0 ] && [ -n "$users_response" ]; then
        user_details=$(echo "$users_response" | jq '[.[] | select(.status == "active" and .is_blocked == false)]' 2>/dev/null || echo "[]")
        registered_count=$(echo "$user_details" | jq 'length' 2>/dev/null || echo "0")
        if ! [[ "$registered_count" =~ ^[0-9]+$ ]]; then registered_count=0; fi
    else
        output "⚠️  Failed to fetch registered users"
    fi

    log_progress "  → Fetching billing usage..."
    billing_response=$(make_api_call "integrations/billing/usage?account=${tenant_id}" "Billing usage for $tenant_name")
    billable_count=0
    billing_details='{"active_users": 0, "active_peers": 0, "total_users": 0, "total_peers": 0}'
    if [ $? -eq 0 ] && [ -n "$billing_response" ]; then
        billable_count=$(echo "$billing_response" | jq -r '.active_users // 0' 2>/dev/null || echo "0")
        billing_details="$billing_response"
        if ! [[ "$billable_count" =~ ^[0-9]+$ ]]; then billable_count=0; fi
    else
        output "⚠️  Failed to fetch billing usage"
    fi

    total_registered=$((total_registered + registered_count))
    total_billable=$((total_billable + billable_count))

    # Priceable = API gave us a non-zero list price for this subscription.
    # Enterprise/Unknown/missing price all fall through to N/A.
    if [ "$tenant_price_cents" -gt 0 ] && [ "$tenant_plan" != "Enterprise" ] && [ "$tenant_plan" != "Unknown" ]; then
        gross_estimate_cents=$((tenant_price_cents * billable_count))
        priceable=true
    else
        gross_estimate_cents=0
        priceable=false
    fi

    output ""
    output "📈 BILLING ANALYSIS:"
    output "   Registered Users: $registered_count"
    output "   Billable Users:   $billable_count"

    if [ $((registered_count - billable_count)) -lt 0 ]; then
        output "   ⚠️  Unusual: More billable than registered users"
    fi

    active_peers=$(echo "$billing_details" | jq -r '.active_peers // 0')
    total_users=$(echo "$billing_details" | jq -r '.total_users // 0')
    total_peers=$(echo "$billing_details" | jq -r '.total_peers // 0')

    output ""
    output "📊 BILLING USAGE BREAKDOWN:"
    output "   Active Peers:     $active_peers"
    output "   Total Users:      $total_users"
    output "   Total Peers:      $total_peers"

    if [ "$registered_count" -gt 0 ] && [ "$user_details" != "[]" ]; then
        output ""
        output "👥 REGISTERED USER DETAILS:"

        billing_status="Not Billable"
        if [ "$billable_count" -gt 0 ]; then
            billing_status="Billable"
        fi

        user_table=$(echo "$user_details" | jq -r --arg billing_status "$billing_status" '
            if length > 0 then
                ["Name", "Email", "Role", "Last Login", "Billing Status"] as $headers |
                $headers, (["----", "-----", "----", "----------", "--------------"]) ,
                (.[] | [
                    (.name // "N/A"),
                    .email,
                    (.role // "user"),
                    (if .last_login == "0001-01-01T00:00:00Z" or .last_login == null then "Never" else .last_login end),
                    $billing_status
                ]) | @tsv
            else
                "No active users found"
            end
        ' 2>/dev/null | column -t -s $'\t' | sed 's/^/   /')

        echo "$user_table"
        if [ "$json_only" != true ] && [ -n "$text_output_file" ]; then
            echo "$user_table" >> "$text_output_file"
        fi

        output ""
        output "📋 Role Distribution:"
        roles=$(echo "$user_details" | jq -r 'group_by(.role // "user") | map("   • \(length) \(.[0].role // "user")\(if length == 1 then "" else "s" end)") | .[]' 2>/dev/null)
        echo "$roles"
        if [ "$json_only" != true ] && [ -n "$text_output_file" ]; then
            echo "$roles" >> "$text_output_file"
        fi
    fi

    tenant_data=$(jq -n \
        --arg id "$tenant_id" \
        --arg name "$tenant_name" \
        --arg domain "$tenant_domain" \
        --arg status "$tenant_status" \
        --argjson reg "$registered_count" \
        --argjson bill "$billable_count" \
        --argjson usage "$billing_details" \
        --argjson users "$user_details" \
        --argjson sub "$subscription_json" \
        --argjson gross_cents "$gross_estimate_cents" \
        --argjson priceable "$priceable" \
        '{
            tenant_info: {
                id: $id,
                name: $name,
                domain: $domain,
                status: $status,
                billing_plan: $sub.plan_tier,
                billing_plan_id: $sub.plan_tier_id
            },
            subscription: {
                plan_tier_id: $sub.plan_tier_id,
                plan_tier: $sub.plan_tier,
                currency: $sub.currency,
                per_user_list_price_cents: $sub.per_user_list_price_cents,
                price_id: $sub.price_id,
                provider: $sub.provider,
                active: $sub.active,
                updated_at: $sub.updated_at
            },
            metrics: {registered_active_users: $reg, billable_active_users: $bill},
            billing_usage: $usage,
            registered_users: $users,
            pricing: {
                priceable: $priceable,
                currency: $sub.currency,
                per_user_list_price_cents: (if $priceable then $sub.per_user_list_price_cents else null end),
                billable_users: $bill,
                gross_estimate_cents: (if $priceable then $gross_cents else null end)
            }
        }')
    all_tenant_details+=("$tenant_data")
done

# Build tenants array, then enrich each tenant's pricing block with the
# portfolio-wide MSP discount.
if [ "${#all_tenant_details[@]}" -gt 0 ]; then
    tenants_array=$(printf '%s\n' "${all_tenant_details[@]}" | jq -s '.')
else
    tenants_array='[]'
fi

discount_pct=$(msp_discount_pct "$total_billable")
if   [ "$discount_pct" = "35" ]; then discount_basis_label=">= 500 active users"
elif [ "$discount_pct" = "30" ]; then discount_basis_label=">= 100 active users"
else                                  discount_basis_label="< 100 active users"
fi

# Snapshot timestamp. NetBird's MSP billing cycle is per-tenant and anchored on
# the subscription creation date, which the API does not expose. So we don't
# fabricate a "report period" — consumers should join price_id with their own
# Stripe data to determine cycle bounds for each tenant.
report_generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Apply portfolio discount in cents (integer math; round to nearest cent)
tenants_array=$(echo "$tenants_array" | jq --argjson dp "$discount_pct" '
    map(.pricing |= (
        if .priceable then
            ((.gross_estimate_cents * $dp / 100) | round) as $disc |
            . + {
                discount_pct: $dp,
                discount_amount_cents: $disc,
                net_estimate_cents: (.gross_estimate_cents - $disc)
            }
        else
            . + {discount_pct: null, discount_amount_cents: null, net_estimate_cents: null}
        end
    ))
')

totals_by_currency=$(echo "$tenants_array" | jq '
    [.[] | select(.pricing.priceable)]
    | group_by(.pricing.currency)
    | map({
        currency: .[0].pricing.currency,
        gross_estimate_cents: ([.[].pricing.gross_estimate_cents] | add),
        discount_amount_cents: ([.[].pricing.discount_amount_cents] | add),
        net_estimate_cents: ([.[].pricing.net_estimate_cents] | add)
      })
')

priced_count=$(echo "$tenants_array" | jq '[.[] | select(.pricing.priceable)] | length')
unpriced_count=$(echo "$tenants_array" | jq '[.[] | select(.pricing.priceable | not)] | length')

# jq prelude: currency symbol + cents-to-display formatting ("DDD.CC")
JQ_FMT='
def sym($c): if $c=="usd" then "$" elif $c=="eur" then "€" elif $c=="gbp" then "£" else ($c | ascii_upcase + " ") end;
def cents_str: (. // 0 | round) as $c | ($c / 100 | floor | tostring) + "." + (("00" + ($c % 100 | tostring))[-2:]);
'

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "💰 INVOICE ESTIMATES"
output "===================="
output "Snapshot taken:    ${report_generated_at} (UTC)"
output "MSP discount tier: ${discount_pct}%  (total active users: $total_billable)"
output "Note: NetBird MSP cycles are anchored on each tenant's subscription"
output "      creation date — not the calendar month. Join with your Stripe"
output "      data (use the price_id field) to determine cycle membership."
output ""

invoice_table=$(echo "$tenants_array" | jq -r "$JQ_FMT"'
    ["Tenant","Plan","Active","Rate","Gross","Net"],
    ["------","----","------","----","-----","---"],
    (.[] | [
        .tenant_info.name,
        .tenant_info.billing_plan,
        (.metrics.billable_active_users | tostring),
        (if .pricing.priceable then sym(.pricing.currency) + (.pricing.per_user_list_price_cents | cents_str) else "N/A" end),
        (if .pricing.priceable then sym(.pricing.currency) + (.pricing.gross_estimate_cents | cents_str) else "N/A" end),
        (if .pricing.priceable then sym(.pricing.currency) + (.pricing.net_estimate_cents | cents_str) else "N/A" end)
    ]) | @tsv
' | column -t -s $'\t' | sed 's/^/   /')

echo "$invoice_table"
if [ "$json_only" != true ] && [ -n "$text_output_file" ]; then
    echo "$invoice_table" >> "$text_output_file"
fi

# Per-currency totals (only show currencies actually present in the portfolio)
currency_totals_lines=$(echo "$totals_by_currency" | jq -r --argjson dp "$discount_pct" "$JQ_FMT"'
    .[] | "   \(.currency | ascii_upcase): gross \(sym(.currency))\(.gross_estimate_cents | cents_str), discount -\(sym(.currency))\(.discount_amount_cents | cents_str) (\($dp)%), net \(sym(.currency))\(.net_estimate_cents | cents_str)"
')

if [ -n "$currency_totals_lines" ]; then
    output ""
    output "Currency totals:"
    while IFS= read -r line; do
        output "$line"
    done <<< "$currency_totals_lines"
fi

# Compact totals strings for the executive summary
gross_summary=$(echo "$totals_by_currency" | jq -r "$JQ_FMT"'
    if length == 0 then "N/A"
    else [.[] | sym(.currency) + (.gross_estimate_cents | cents_str)] | join(" / ")
    end
')
net_summary=$(echo "$totals_by_currency" | jq -r "$JQ_FMT"'
    if length == 0 then "N/A"
    else [.[] | sym(.currency) + (.net_estimate_cents | cents_str)] | join(" / ")
    end
')

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "🎯 COMPREHENSIVE SUMMARY"
output "========================"
output "Total Tenants Analyzed:     $tenant_count"
output "Total Registered Users:     $total_registered"
output "Total Billable Users:       $total_billable"
output ""
output "MSP Discount Tier:                ${discount_pct}% (${discount_basis_label})"
output "Tenants Priced / Skipped:         ${priced_count} priced, ${unpriced_count} skipped"
output "Total Estimated Invoice (gross):  ${gross_summary}"
output "Total Estimated Invoice (net):    ${net_summary}"
output ""

if [ -n "$json_output_file" ]; then
    log_progress "Generating detailed JSON report..."

    jq -n \
        --arg generated_at "$report_generated_at" \
        --arg version "$VERSION" \
        --arg api_endpoint "$API_BASE" \
        --argjson tenant_count "$tenant_count" \
        --argjson total_registered "$total_registered" \
        --argjson total_billable "$total_billable" \
        --argjson tenants "$tenants_array" \
        --argjson discount_pct "$discount_pct" \
        --argjson totals_by_currency "$totals_by_currency" \
        --argjson priced_count "$priced_count" \
        --argjson unpriced_count "$unpriced_count" \
        --argjson msp_account "$msp_account_json" \
        '{
            schema_version: 1,
            report_metadata: {
                generated_at: $generated_at,
                billing_cycle_note: "NetBird MSP issues two invoices each cycle: one for the master account (type=\"account\") and one consolidated invoice covering all tenants (type=\"tenants\"). Tenant subscriptions follow the consolidated tenant cycle; see msp_account.billing_periods for the latest closed cycle and the start of the current open cycle.",
                report_type: "comprehensive_billing_analysis",
                api_endpoint: $api_endpoint,
                version: $version,
                description: "Snapshot of current-cycle billable users per tenant, with portfolio MSP discount applied"
            },
            msp_account: $msp_account,
            executive_summary: {
                total_tenants: $tenant_count,
                total_registered_users: $total_registered,
                total_billable_users: $total_billable,
                msp_discount_pct: $discount_pct,
                msp_discount_basis_users: $total_billable,
                tenants_priced: $priced_count,
                tenants_skipped_unpriced: $unpriced_count,
                totals_by_currency: ($totals_by_currency | map({(.currency): {gross_estimate_cents: .gross_estimate_cents, discount_amount_cents: .discount_amount_cents, net_estimate_cents: .net_estimate_cents}}) | add // {})
            },
            tenant_details: $tenants
        }' > "$json_output_file"

    if ! jq empty "$json_output_file" 2>/dev/null; then
        echo "⚠️  Generated JSON failed validation: $json_output_file" >&2
    fi
fi

if [ -n "$csv_output_file" ]; then
    log_progress "Generating CSV summary..."

    {
        echo "snapshot_taken_at,msp_account_id,current_open_period_started_at,tenant_id,tenant_name,domain,status,billing_plan,billing_plan_id,price_id,provider,subscription_updated_at,registered_users,billable_users,active_peers,total_users,total_peers,currency,per_user_list_price_cents,gross_estimate_cents,discount_pct,discount_amount_cents,net_estimate_cents"
        echo "$tenants_array" | jq -r \
            --arg generated_at "$report_generated_at" \
            --arg msp_account_id "$msp_account_id" \
            --arg current_open "$current_open_period_started_at" \
            '.[] | [
                $generated_at,
                $msp_account_id,
                $current_open,
                .tenant_info.id,
                .tenant_info.name,
                .tenant_info.domain,
                .tenant_info.status,
                .tenant_info.billing_plan,
                .tenant_info.billing_plan_id,
                .subscription.price_id,
                .subscription.provider,
                .subscription.updated_at,
                .metrics.registered_active_users,
                .metrics.billable_active_users,
                (.billing_usage.active_peers // 0),
                (.billing_usage.total_users // 0),
                (.billing_usage.total_peers // 0),
                (if .pricing.priceable then .pricing.currency else "" end),
                (if .pricing.priceable then .pricing.per_user_list_price_cents else "" end),
                (if .pricing.priceable then .pricing.gross_estimate_cents else "" end),
                (if .pricing.priceable then .pricing.discount_pct else "" end),
                (if .pricing.priceable then .pricing.discount_amount_cents else "" end),
                (if .pricing.priceable then .pricing.net_estimate_cents else "" end)
            ] | @csv'
    } > "$csv_output_file"
fi

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "📁 GENERATED FILES"
output "=================="
[ -n "$text_output_file" ] && output "• Comprehensive Report: $text_output_file"
[ -n "$json_output_file" ] && output "• Detailed JSON Data:   $json_output_file"
[ -n "$csv_output_file" ]  && output "• CSV Summary:          $csv_output_file"

if [ -n "$json_output_file" ] && [ "$quiet" != true ]; then
    echo ""
    echo "📊 Executive Summary Preview (console only):"
    echo "============================================"
    jq '.executive_summary' "$json_output_file" 2>/dev/null || echo "JSON preview unavailable"
fi

output ""
output "═══════════════════════════════════════════════════════════"
output "Comprehensive analysis complete at $(date)"
output "═══════════════════════════════════════════════════════════"

log_progress ""
log_progress "✅ Comprehensive NetBird billing analysis complete!"
if [ -n "$text_output_file" ] || [ -n "$json_output_file" ] || [ -n "$csv_output_file" ]; then
    log_progress "📄 Reports saved to:"
    [ -n "$text_output_file" ] && log_progress "   • $text_output_file"
    [ -n "$json_output_file" ] && log_progress "   • $json_output_file"
    [ -n "$csv_output_file" ]  && log_progress "   • $csv_output_file"
fi
