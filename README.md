# NetBird MSP Billing Analyzer

Command-line tool for NetBird Managed Service Providers to analyze billing usage and plans across all managed tenants.

## Features

- Analyze registered users vs billable users across all MSP tenants
- Display billing plan for each tenant (Team, Business)
- Generate human-readable text reports and structured JSON output
- Detailed user information including roles and last login times
- Secure API token handling via environment variables

## Prerequisites

- Bash shell (macOS, Linux, or WSL on Windows)
- curl (for API requests)
- jq (for JSON processing) - Install with `brew install jq` on macOS
- NetBird MSP Account with API access
- NetBird API Token with permissions for:
  - MSP tenant access
  - Billing usage and subscription data access
  - User information access across managed tenants

## Setup Instructions

1. Copy the environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit the `.env` file with your NetBird API token:
   ```bash
   NETBIRD_API_TOKEN=your_actual_netbird_api_token_here
   ```

3. Make the script executable:
   ```bash
   chmod +x netbird-msp-comprehensive.sh
   ```

## NetBird API Token Setup

1. Log into your NetBird MSP dashboard
2. Navigate to Team → Service Users → Create Service User → Create Access Token
3. Generate a new API token with Admin permissions
4. Save the token securely

### Required API Endpoints

Your API token must have access to:
- `GET /api/integrations/msp/tenants` - List all MSP tenants
- `GET /api/integrations/billing/usage` - Read billing usage per tenant
- `GET /api/integrations/billing/subscription` - Read billing plan per tenant
- `GET /api/users` - Read user information per tenant

## Usage

```bash
# Run the analysis
./netbird-msp-comprehensive.sh

# Or run with explicit environment variable
NETBIRD_API_TOKEN="your_token_here" ./netbird-msp-comprehensive.sh
```

## Output Files

The script generates two types of reports with timestamps:

### 1. Text Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.txt`)
- Human-readable format with detailed analysis
- Tenant-by-tenant breakdown including billing plans
- User details and role distribution
- Executive summary

### 2. JSON Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.json`)
- Structured data for all tenants
- Individual user records
- Billing usage breakdown
- Tenant billing plans

### Sample JSON Structure

```json
{
  "executive_summary": {
    "total_tenants": 4,
    "total_registered_users": 150,
    "total_billable_users": 120
  },
  "tenant_details": [{
    "tenant_info": {
      "id": "tenant_id",
      "name": "Tenant Name",
      "billing_plan": "Team"
    }
  }]
}
```

## Understanding the Analysis

### Key Metrics

- **Registered Users**: Active, unblocked users in NetBird
- **Billable Users**: Users who connected during the current billing cycle
- **Billing Plan**: Current subscription tier (Team, Business)

### Interpreting Results

- Compare registered vs billable users to understand actual usage
- Review billing plans across tenants for consistency
- Identify users who haven't logged in recently

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

## Support

- **NetBird API issues**: Contact NetBird support
- **Tool issues**: Check the troubleshooting section
