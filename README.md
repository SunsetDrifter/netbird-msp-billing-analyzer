# NetBird MSP Billing Analyzer

Command-line tool for NetBird Managed Service Providers to analyze billing usage and plans across all managed tenants.

## Features

- Analyze registered users vs billable users across all MSP tenants
- Display billing plan for each tenant (Team, Business)
- Generate human-readable text reports and structured JSON output
- Detailed user information including roles and last login times
- Secure API token handling via environment variables

## Installation

### Easy Installation (Recommended)

We provide an automated installation script that handles everything for you:

#### One-Line Installation

```bash
curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/install.sh | bash
```

#### Manual Installation Script

```bash
# Download the installer
curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/install.sh -o install.sh

# Make it executable
chmod +x install.sh

# Run with options
./install.sh --help
```

#### Installation Options

**System-wide Installation (Default)**
```bash
# Install to /usr/local/bin (may require sudo)
./install.sh
```

**User Installation**
```bash
# Install to ~/.local/bin (no sudo required)
./install.sh --user
```

**Version-specific Installation**
```bash
# Install a specific version
./install.sh --version v0.9.0
```

**Force Reinstall**
```bash
# Reinstall even if already installed
./install.sh --force
```

#### What the Installer Does

✅ **Automatic dependency installation** - Installs `jq` if missing  
✅ **Multiple OS support** - Works on macOS and Linux  
✅ **Package manager detection** - Uses Homebrew, apt, yum, dnf, or zypper  
✅ **PATH management** - Automatically adds to PATH if needed  
✅ **Safe installation** - Never overwrites without permission  
✅ **Easy uninstall** - Clean removal with `./install.sh --uninstall`

#### Uninstallation

```bash
# Remove the installation
./install.sh --uninstall
```

### Manual Setup (Alternative)

If you prefer to install manually or the automated installer doesn't work for your system:

#### Prerequisites

- Bash shell (macOS, Linux, or WSL on Windows)
- curl (for API requests)
- jq (for JSON processing) - Install with `brew install jq` on macOS
- NetBird MSP Account with API access
- NetBird API Token with permissions for:
  - MSP tenant access
  - Billing usage and subscription data access
  - User information access across managed tenants

#### Manual Setup Instructions

1. Download the script:
   ```bash
   curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/netbird-msp-comprehensive.sh -o netbird-msp-analyzer
   ```

2. Make it executable:
   ```bash
   chmod +x netbird-msp-analyzer
   ```

3. Move to a directory in your PATH (optional):
   ```bash
   sudo mv netbird-msp-analyzer /usr/local/bin/
   # or for user installation:
   mkdir -p ~/.local/bin && mv netbird-msp-analyzer ~/.local/bin/
   ```

4. Copy the environment template:
   ```bash
   curl -sSL https://raw.githubusercontent.com/SunsetDrifter/netbird-msp-billing-analyzer/main/.env.example -o .env.example
   cp .env.example .env
   ```

5. Edit the `.env` file with your NetBird API token:
   ```bash
   NETBIRD_API_TOKEN=your_actual_netbird_api_token_here
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

After installation, you can run the analyzer using the installed command:

```bash
# Run the analysis (if installed via installer)
netbird-msp-analyzer

# Or run with explicit environment variable
NETBIRD_API_TOKEN="your_token_here" netbird-msp-analyzer

# If running the script directly (manual setup)
./netbird-msp-comprehensive.sh
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
