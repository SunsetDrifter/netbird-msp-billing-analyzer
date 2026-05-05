#!/bin/bash

# NetBird MSP Comprehensive Billing Usage Report
# Uses NetBird's billing API to show actual billable vs registered users
# Provides detailed analysis with JSON output for MSP management

set -uo pipefail

readonly VERSION="v0.10.0"
readonly API_BASE="https://api.netbird.io/api"
readonly SCRIPT_NAME="$(basename "$0")"

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

# Detect tenant billing plan from the subscription endpoint.
# Echoes a capitalized plan name; "Unknown" on failure.
detect_billing_plan() {
    local tenant_id="$1"
    local body
    body=$(make_api_call "integrations/billing/subscription?account=${tenant_id}" "Billing subscription for $tenant_id")
    if [ $? -ne 0 ] || [ -z "$body" ]; then
        echo "Unknown"
        return 1
    fi

    local plan_tier
    plan_tier=$(echo "$body" | jq -r '.plan_tier // empty' 2>/dev/null)
    if [ -z "$plan_tier" ] || [ "$plan_tier" = "null" ]; then
        echo "Unknown"
        return 1
    fi

    case "$plan_tier" in
        team)       echo "Team" ;;
        business)   echo "Business" ;;
        enterprise) echo "Enterprise" ;;
        *)          echo "${plan_tier^}" ;;
    esac
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
    tenant_plan=$(detect_billing_plan "$tenant_id")
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
        --arg plan "$tenant_plan" \
        --argjson reg "$registered_count" \
        --argjson bill "$billable_count" \
        --argjson usage "$billing_details" \
        --argjson users "$user_details" \
        '{
            tenant_info: {id: $id, name: $name, domain: $domain, status: $status, billing_plan: $plan},
            metrics: {registered_active_users: $reg, billable_active_users: $bill},
            billing_usage: $usage,
            registered_users: $users
        }')
    all_tenant_details+=("$tenant_data")
done

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "🎯 COMPREHENSIVE SUMMARY"
output "========================"
output "Total Tenants Analyzed:     $tenant_count"
output "Total Registered Users:     $total_registered"
output "Total Billable Users:       $total_billable"
output ""

if [ "${#all_tenant_details[@]}" -gt 0 ]; then
    tenants_array=$(printf '%s\n' "${all_tenant_details[@]}" | jq -s '.')
else
    tenants_array='[]'
fi

if [ -n "$json_output_file" ]; then
    log_progress "Generating detailed JSON report..."

    jq -n \
        --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg version "$VERSION" \
        --arg api_endpoint "$API_BASE" \
        --argjson tenant_count "$tenant_count" \
        --argjson total_registered "$total_registered" \
        --argjson total_billable "$total_billable" \
        --argjson tenants "$tenants_array" \
        '{
            report_metadata: {
                generated_at: $generated_at,
                report_type: "comprehensive_billing_analysis",
                api_endpoint: $api_endpoint,
                version: $version,
                description: "Comprehensive analysis comparing registered users vs billable users using NetBird'"'"'s official billing API"
            },
            executive_summary: {
                total_tenants: $tenant_count,
                total_registered_users: $total_registered,
                total_billable_users: $total_billable
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
        echo "tenant_id,tenant_name,domain,status,billing_plan,registered_users,billable_users,active_peers,total_users,total_peers"
        echo "$tenants_array" | jq -r '.[] | [
            .tenant_info.id,
            .tenant_info.name,
            .tenant_info.domain,
            .tenant_info.status,
            .tenant_info.billing_plan,
            .metrics.registered_active_users,
            .metrics.billable_active_users,
            (.billing_usage.active_peers // 0),
            (.billing_usage.total_users // 0),
            (.billing_usage.total_peers // 0)
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
