#!/bin/bash

# NetBird MSP Comprehensive Billing Usage Report
# Uses NetBird's billing API to show actual billable vs registered users
# Provides detailed analysis with JSON output for MSP management

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    # Export variables from .env file, ignoring comments and empty lines
    set -a
    source <(grep -E "^[A-Za-z_][A-Za-z0-9_]*=" .env)
    set +a
fi

# Validate required environment variables
if [ -z "${NETBIRD_API_TOKEN}" ]; then
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

# Use the environment variable for the token
TOKEN="${NETBIRD_API_TOKEN}"
API_BASE="https://api.netbird.io/api"

# Initialize output files
timestamp=$(date +"%Y%m%d_%H%M%S")
text_output_file="netbird_comprehensive_${timestamp}.txt"
json_output_file="netbird_comprehensive_${timestamp}.json"
summary_output_file="netbird_summary_${timestamp}.json"

# Function to output to both console and file
output() {
    echo "$1" | tee -a "$text_output_file"
}

# Function to make API call with error handling
make_api_call() {
    local endpoint="$1"
    local description="$2"
    
    local response=$(curl -s -w "\n%{http_code}" -X GET "${API_BASE}/${endpoint}" \
         -H 'Accept: application/json' \
         -H "Authorization: Token ${TOKEN}")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" != "200" ]; then
        echo "❌ $description failed (HTTP $http_code)" >&2
        return 1
    fi
    
    echo "$body"
}

output "═══════════════════════════════════════════════════════════"
output "          NETBIRD MSP COMPREHENSIVE BILLING REPORT"
output "═══════════════════════════════════════════════════════════"
output "Generated: $(date)"
output ""
output "📊 COMPREHENSIVE ANALYSIS:"
output "• Registered Users = Active & unblocked users in NetBird"
output "• Billable Users   = Users who connected in current billing cycle"
output "• Difference       = Users registered but not connecting (cost savings)"
output "• This uses NetBird's official billing API for accurate data"
output ""

# Check dependencies
if ! command -v jq &> /dev/null; then
    output "❌ ERROR: jq is required. Install with: brew install jq"
    exit 1
fi

# Get MSP tenants
echo "Fetching MSP tenants..."
tenants_response=$(make_api_call "integrations/msp/tenants" "MSP tenants fetch")

if [ $? -ne 0 ] || [ -z "$tenants_response" ]; then
    output "❌ Failed to fetch tenants. Check your token permissions."
    exit 1
fi

tenant_count=$(echo "$tenants_response" | jq 'length')
output "Found $tenant_count tenant(s)"
output ""

# Initialize totals and data arrays
total_registered=0
total_billable=0
all_tenant_details=()

output "DETAILED TENANT ANALYSIS"
output "========================"

# Process each tenant
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
    
    if [ "$tenant_status" != "active" ]; then
        output "⚠️  Skipping inactive tenant"
        continue
    fi
    
    # Get registered users count and details
    echo "  → Fetching registered users..."
    users_response=$(make_api_call "users?service_user=false&account=${tenant_id}" "Users for $tenant_name")
    
    registered_count=0
    user_details="[]"
    if [ $? -eq 0 ] && [ -n "$users_response" ]; then
        # Count and extract active, unblocked users
        user_details=$(echo "$users_response" | jq '[.[] | select(.status == "active" and .is_blocked == false)]' 2>/dev/null || echo "[]")
        registered_count=$(echo "$user_details" | jq 'length' 2>/dev/null || echo "0")
        
        # Ensure numeric
        if ! [[ "$registered_count" =~ ^[0-9]+$ ]]; then registered_count=0; fi
    else
        output "⚠️  Failed to fetch registered users"
    fi
    
    # Get billable users count from billing API
    echo "  → Fetching billing usage..."
    billing_response=$(make_api_call "integrations/billing/usage?account=${tenant_id}" "Billing usage for $tenant_name")
    
    billable_count=0
    billing_details="{}"
    if [ $? -eq 0 ] && [ -n "$billing_response" ]; then
        billable_count=$(echo "$billing_response" | jq -r '.active_users // 0' 2>/dev/null || echo "0")
        billing_details="$billing_response"
        
        # Ensure numeric
        if ! [[ "$billable_count" =~ ^[0-9]+$ ]]; then billable_count=0; fi
    else
        output "⚠️  Failed to fetch billing usage"
        billing_details='{"active_users": 0, "active_peers": 0, "total_users": 0, "total_peers": 0}'
    fi
    
    # Calculate difference and savings
    difference=$((registered_count - billable_count))
    savings_percent=0
    efficiency_percent=0
    
    if [ "$registered_count" -gt 0 ]; then
        savings_percent=$(( (difference * 100) / registered_count ))
        efficiency_percent=$(( (billable_count * 100) / registered_count ))
    fi
    
    # Update totals
    total_registered=$((total_registered + registered_count))
    total_billable=$((total_billable + billable_count))
    
    # Display results
    output ""
    output "📈 BILLING ANALYSIS:"
    output "   Registered Users: $registered_count"
    output "   Billable Users:   $billable_count"
    output "   Difference:       $difference"
    
    if [ "$difference" -lt 0 ]; then
        output "   ⚠️  Unusual: More billable than registered users"
    fi
    
    # Show billing details
    if [ "$billing_details" != "{}" ]; then
        active_peers=$(echo "$billing_details" | jq -r '.active_peers // 0')
        total_users=$(echo "$billing_details" | jq -r '.total_users // 0') 
        total_peers=$(echo "$billing_details" | jq -r '.total_peers // 0')
        
        output ""
        output "📊 BILLING USAGE BREAKDOWN:"
        output "   Active Peers:     $active_peers"
        output "   Total Users:      $total_users" 
        output "   Total Peers:      $total_peers"
    fi
    
    # Show user details if we have registered users
    if [ "$registered_count" -gt 0 ] && [ "$user_details" != "[]" ]; then
        output ""
        output "👥 REGISTERED USER DETAILS:"
        
        # Display user table with billing status
        billing_status="Not Billable"
        if [ "$billable_count" -gt 0 ]; then
            billing_status="Billable"
        fi
        
        echo "$user_details" | jq -r --arg billing_status "$billing_status" '
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
        ' 2>/dev/null | column -t -s $'\t' | sed 's/^/   /' | tee -a "$text_output_file"
        
        # Role distribution
        output ""
        output "📋 Role Distribution:"
        echo "$user_details" | jq -r 'group_by(.role // "user") | map("   • \(length) \(.[0].role // "user")") | .[]' 2>/dev/null | tee -a "$text_output_file"
    fi
    
    # Store tenant data for JSON output
    tenant_data=$(cat << EOF
{
    "tenant_info": {
        "id": "$tenant_id",
        "name": "$tenant_name", 
        "domain": "$tenant_domain",
        "status": "$tenant_status"
    },
    "metrics": {
        "registered_active_users": $registered_count,
        "billable_active_users": $billable_count,
        "non_billable_users": $difference
    },
    "billing_usage": $billing_details,
    "registered_users": $user_details
}
EOF
)
    
    all_tenant_details+=("$tenant_data")
done

# Overall Summary
total_difference=$((total_registered - total_billable))
total_savings_percent=0
total_efficiency_percent=0

if [ "$total_registered" -gt 0 ]; then
    total_savings_percent=$(( (total_difference * 100) / total_registered ))
    total_efficiency_percent=$(( (total_billable * 100) / total_registered ))
fi

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "🎯 COMPREHENSIVE SUMMARY"
output "========================"
output "Total Tenants Analyzed:     $tenant_count"
output "Total Registered Users:     $total_registered"
output "Total Billable Users:       $total_billable"
output "Total Non-Billable Users:   $total_difference"
output ""

# Additional status info if needed
if [ "$total_difference" -gt 0 ]; then
    output "⚠️  $total_difference users registered but not billable"
elif [ "$total_difference" -eq 0 ]; then
    output "✅ All registered users are billable"
else
    output "⚠️  More billable than registered users (unusual)"
fi

# Generate comprehensive JSON report
echo "Generating detailed JSON reports..."

# Main comprehensive report
comprehensive_report=$(cat << EOF
{
    "report_metadata": {
        "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "report_type": "comprehensive_billing_analysis",
        "api_endpoint": "https://api.netbird.io/api",
        "version": "2.0",
        "description": "Comprehensive analysis comparing registered users vs billable users using NetBird's official billing API"
    },
    "executive_summary": {
        "total_tenants": $tenant_count,
        "total_registered_users": $total_registered,
        "total_billable_users": $total_billable,
        "total_non_billable_users": $total_difference
    },
    "tenant_details": [
        $(IFS=,; echo "${all_tenant_details[*]}")
    ]
}
EOF
)

echo "$comprehensive_report" > "$json_output_file"

# Quick summary report
summary_report=$(cat << EOF
{
    "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "report_type": "billing_summary",
    "totals": {
        "tenant_count": $tenant_count,
        "total_registered_users": $total_registered,
        "total_billable_users": $total_billable,
        "total_non_billable_users": $total_difference
    }
}
EOF
)

echo "$summary_report" > "$summary_output_file"

output ""
output "═══════════════════════════════════════════════════════════"
output ""
output "📁 GENERATED FILES"
output "=================="
output "• Comprehensive Report: $text_output_file"
output "• Detailed JSON Data:   $json_output_file"
output "• Executive Summary:    $summary_output_file"

# Show JSON preview
echo ""
echo "📊 Executive Summary Preview (console only):"
echo "============================================"
echo "$comprehensive_report" | jq '.executive_summary' 2>/dev/null || echo "JSON preview unavailable"

output ""
output "═══════════════════════════════════════════════════════════"
output "Comprehensive analysis complete at $(date)"
output "═══════════════════════════════════════════════════════════"

echo ""
echo "✅ Comprehensive NetBird billing analysis complete!"
echo "📄 Reports saved to:"
echo "   • $text_output_file"
echo "   • $json_output_file"
echo "   • $summary_output_file"
