# NetBird MSP Billing Analyzer

Command-line tool for NetBird Managed Service Providers to analyze billing usage and plans across all managed tenants.

## Features

- Analyze registered users vs billable users across all MSP tenants
- Display billing plan for each tenant (Team, Business)
- Generate human-readable text reports and structured JSON output
- Detailed user information including roles and last login times
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

## Manual Installation

<details>
<summary>Click to expand manual installation instructions</summary>

### Prerequisites
- Bash, curl, jq
- NetBird MSP account with API access

### Steps
1. Download: `curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/netbird-msp-comprehensive.sh -o netbird-msp-analyzer`
2. Make executable: `chmod +x netbird-msp-analyzer`
3. Optionally move to PATH: `sudo mv netbird-msp-analyzer /usr/local/bin/`
4. Set API token: `export NETBIRD_API_TOKEN="your_token"`

</details>

## Support

- **NetBird API issues**: Contact NetBird support
- **Tool issues**: Check the troubleshooting section
