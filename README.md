# NetBird MSP Comprehensive Billing Analysis

A comprehensive command-line tool for NetBird Managed Service Providers (MSP) to analyze billing usage across all managed tenants. This tool provides detailed comparisons between registered users and billable users, helping MSPs understand their actual costs versus registered user counts.

## 📊 Features

- **Comprehensive Billing Analysis**: Compare registered users vs billable users across all MSP tenants
- **Multi-Tenant Support**: Analyze all tenants in your MSP account simultaneously
- **Detailed User Information**: View user details, roles, and last login times
- **Multiple Output Formats**: 
  - Human-readable text reports with timestamps
  - Structured JSON data for automated processing
  - Executive summary JSON for quick insights
- **Security-First**: Uses environment variables to protect API tokens
- **Error Handling**: Robust error handling with clear diagnostic messages
- **Official NetBird API**: Uses NetBird's official billing API for accurate data

## 🔧 Prerequisites

Before using this tool, ensure you have:

- **Bash shell** (macOS, Linux, or WSL on Windows)
- **curl** (for API requests)
- **jq** (for JSON processing) - Install with `brew install jq` on macOS
- **NetBird MSP Account** with appropriate API access
- **NetBird API Token** with the following permissions:
  - MSP tenant access
  - Billing usage data access
  - User information access across all managed tenants

## ⚙️ Setup Instructions

### 1. Clone and Configure

```bash
# Clone or download this repository
git clone <your-repo-url>
cd netbird-msp-comprehensive

# Copy the environment template
cp .env.example .env

# Edit the .env file with your actual API token
nano .env  # or use your preferred editor
```

### 2. Configure Your API Token

Edit the `.env` file and replace the placeholder with your actual NetBird API token:

```bash
# NetBird API Token for MSP billing access
NETBIRD_API_TOKEN=your_actual_netbird_api_token_here
```

### 3. Make the Script Executable

```bash
chmod +x netbird-msp-comprehensive.sh
```

## 🔑 NetBird API Token Setup

### Obtaining Your API Token

1. **Log into NetBird Dashboard**: Access your NetBird MSP dashboard
2. **Navigate to API Settings**: Go to Settings → API or Integration settings
3. **Generate New Token**: Create a new API token with the following permissions:
   - **MSP Management**: Access to tenant information
   - **Billing Access**: Read billing usage data
   - **User Management**: Read user information across tenants
4. **Copy the Token**: Save the generated token securely

### Required Permissions

Your API token must have access to:
- `GET /api/integrations/msp/tenants` - List all MSP tenants
- `GET /api/integrations/billing/usage` - Read billing usage per tenant
- `GET /api/users` - Read user information per tenant

### Security Best Practices

- **Never commit** your `.env` file to version control
- **Store tokens securely** using environment variables or secure vaults
- **Rotate tokens regularly** according to your security policy
- **Use least-privilege access** - only grant necessary permissions

## 🚀 Usage

### Basic Usage

```bash
# Run the analysis
./netbird-msp-comprehensive.sh
```

### Advanced Usage

```bash
# Run with explicit environment variable (bypasses .env file)
NETBIRD_API_TOKEN=\"your_token_here\" ./netbird-msp-comprehensive.sh

# Check dependencies before running
command -v jq >/dev/null 2>&1 || echo \"jq not found - install with: brew install jq\"
```

## 📁 Output Files

The script generates three types of reports with timestamps:

### 1. Comprehensive Text Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.txt`)
- Human-readable format with detailed analysis
- Tenant-by-tenant breakdown
- User details and role distribution
- Executive summary

### 2. Detailed JSON Report (`netbird_comprehensive_YYYYMMDD_HHMMSS.json`)
- Complete structured data for all tenants
- Individual user records
- Billing usage breakdown
- Metadata and timestamps

### Sample Output Structure

```json
{
  \"executive_summary\": {
    \"total_tenants\": 5,
    \"total_registered_users\": 150,
    \"total_billable_users\": 120,
    \"total_non_billable_users\": 30
  }
}
```

## 📊 Understanding the Analysis

### Key Metrics Explained

- **Registered Users**: Active, unblocked users in NetBird (potential cost)
- **Billable Users**: Users who actually connected during the current billing cycle (actual cost)

### Interpreting Results

- **Positive difference**: You have registered users not actively connecting (potential cost savings)
- **Zero difference**: All registered users are billable (optimal usage)
- **Negative difference**: More billable than registered users (requires investigation)

## 🛠️ Troubleshooting

### Common Issues

1. **\"jq not found\"**: Install jq with `brew install jq` (macOS) or your system's package manager
2. **\"Token not set\"**: Ensure your `.env` file exists and contains `NETBIRD_API_TOKEN=your_token`
3. **\"Failed to fetch tenants\"**: Check token permissions and NetBird API access
4. **HTTP errors**: Verify your API token is valid and has necessary permissions

### Debug Mode

Add debug output to troubleshoot API issues:

```bash
# Enable debug mode (shows curl commands)
set -x
./netbird-msp-comprehensive.sh
set +x
```

## 🤝 Support

For issues related to:
- **NetBird API**: Contact NetBird support
- **This Tool**: Check the troubleshooting section or create an issue in this repository
