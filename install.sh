#!/bin/bash

# NetBird MSP Billing Analyzer - Installation Script
# Downloads and installs the latest release of the NetBird MSP Billing Analyzer
# Compatible with macOS and Linux systems

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly REPO_OWNER="SunsetDrifter"
readonly REPO_NAME="netbird-msp-billing-analyzer"
readonly SCRIPT_NAME="netbird-msp-comprehensive.sh"
readonly BINARY_NAME="netbird-msp-analyzer"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
INSTALL_DIR=""
USER_INSTALL=false
QUIET=false
FORCE=false
VERSION=""

# Print functions with color support
print_info() {
    if [[ "$QUIET" != true ]]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Show help information
show_help() {
    cat << EOF
NetBird MSP Billing Analyzer - Installation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --version       Install specific version (e.g., v0.9.0)
    -u, --user          Install to user directory (~/.local/bin)
    -q, --quiet         Suppress non-error output
    -f, --force         Force reinstall if already installed
    --uninstall         Uninstall the tool

EXAMPLES:
    $0                      # Install latest version system-wide
    $0 --user               # Install to user directory
    $0 --version v0.9.0     # Install specific version
    $0 --uninstall          # Remove installation

REQUIREMENTS:
    - curl
    - jq
    - bash (version 4.0+)

EOF
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64)     echo "amd64" ;;
        arm64)      echo "arm64" ;;
        aarch64)    echo "arm64" ;;
        *)          echo "unknown" ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check and install dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required commands
    if ! command_exists curl; then
        missing_deps+=("curl")
    fi
    
    if ! command_exists jq; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        print_success "All required dependencies are installed"
        return 0
    fi
    
    print_warning "Missing dependencies: ${missing_deps[*]}"
    
    # Try to install missing dependencies
    local os=$(detect_os)
    case "$os" in
        macos)
            install_deps_macos "${missing_deps[@]}"
            ;;
        linux)
            install_deps_linux "${missing_deps[@]}"
            ;;
        *)
            print_error "Unsupported operating system: $os"
            print_error "Please install manually: ${missing_deps[*]}"
            return 1
            ;;
    esac
}

# Install dependencies on macOS
install_deps_macos() {
    local deps=("$@")
    
    if command_exists brew; then
        print_info "Installing dependencies using Homebrew..."
        for dep in "${deps[@]}"; do
            print_info "Installing $dep..."
            brew install "$dep"
        done
    else
        print_error "Homebrew not found. Please install missing dependencies manually:"
        for dep in "${deps[@]}"; do
            case "$dep" in
                jq)
                    echo "  jq: brew install jq  or  https://stedolan.github.io/jq/download/"
                    ;;
                curl)
                    echo "  curl: should be pre-installed on macOS"
                    ;;
            esac
        done
        return 1
    fi
}

# Install dependencies on Linux
install_deps_linux() {
    local deps=("$@")
    
    # Detect package manager
    if command_exists apt-get; then
        print_info "Installing dependencies using apt..."
        sudo apt-get update
        for dep in "${deps[@]}"; do
            sudo apt-get install -y "$dep"
        done
    elif command_exists yum; then
        print_info "Installing dependencies using yum..."
        for dep in "${deps[@]}"; do
            sudo yum install -y "$dep"
        done
    elif command_exists dnf; then
        print_info "Installing dependencies using dnf..."
        for dep in "${deps[@]}"; do
            sudo dnf install -y "$dep"
        done
    elif command_exists zypper; then
        print_info "Installing dependencies using zypper..."
        for dep in "${deps[@]}"; do
            sudo zypper install -y "$dep"
        done
    else
        print_error "No supported package manager found. Please install manually: ${deps[*]}"
        return 1
    fi
}

# Get latest release version from GitHub API
get_latest_version() {
    local api_url="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
    
    if [[ "$QUIET" != true ]]; then
        print_info "Checking for latest release..."
    fi
    
    local response
    if ! response=$(curl -sf "$api_url" 2>/dev/null); then
        print_error "Failed to fetch release information from GitHub"
        print_error "Please check your internet connection and try again"
        return 1
    fi
    
    local version
    if ! version=$(echo "$response" | jq -r '.tag_name' 2>/dev/null); then
        print_error "Failed to parse release information"
        return 1
    fi
    
    if [[ "$version" == "null" ]]; then
        print_error "No releases found for $REPO_OWNER/$REPO_NAME"
        return 1
    fi
    
    echo "$version"
}

# Download and install the script
download_and_install() {
    local version="$1"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Set up cleanup trap
    trap "rm -rf '$temp_dir'" EXIT
    
    if [[ "$QUIET" != true ]]; then
        print_info "Downloading NetBird MSP Billing Analyzer $version..."
    fi
    
    # Download the main script
    local download_url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$version/$SCRIPT_NAME"
    local temp_script="$temp_dir/$SCRIPT_NAME"
    
    if ! curl -sfL "$download_url" -o "$temp_script"; then
        print_error "Failed to download $SCRIPT_NAME from $download_url"
        return 1
    fi
    
    # Download .env.example
    local env_example_url="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$version/.env.example"
    local temp_env_example="$temp_dir/.env.example"
    
    if ! curl -sfL "$env_example_url" -o "$temp_env_example"; then
        print_warning "Failed to download .env.example (non-critical)"
    fi
    
    # Verify the script is valid bash
    if ! bash -n "$temp_script"; then
        print_error "Downloaded script has syntax errors"
        return 1
    fi
    
    # Install the script
    local target_script="$INSTALL_DIR/$BINARY_NAME"
    
    if [[ "$QUIET" != true ]]; then
        print_info "Installing to $target_script..."
    fi
    
    # Create installation directory if it doesn't exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
    fi
    
    # Copy and set permissions
    cp "$temp_script" "$target_script"
    chmod 755 "$target_script"
    
    # Install .env.example if available and not already present
    if [[ -f "$temp_env_example" ]]; then
        local target_env_example="$INSTALL_DIR/.env.example"
        if [[ ! -f "$target_env_example" ]]; then
            cp "$temp_env_example" "$target_env_example"
            print_success "Installed .env.example to $target_env_example"
        fi
    fi
    
    print_success "NetBird MSP Billing Analyzer installed successfully!"
}

# Set installation directory based on privileges and user preference
set_install_dir() {
    if [[ "$USER_INSTALL" == true ]]; then
        INSTALL_DIR="$HOME/.local/bin"
        print_info "Installing to user directory: $INSTALL_DIR"
    elif [[ $EUID -eq 0 ]]; then
        INSTALL_DIR="/usr/local/bin"
        print_info "Installing system-wide to: $INSTALL_DIR"
    else
        # Check if we can write to /usr/local/bin
        if [[ -w "/usr/local/bin" ]]; then
            INSTALL_DIR="/usr/local/bin"
            print_info "Installing system-wide to: $INSTALL_DIR"
        else
            print_warning "Cannot write to /usr/local/bin without sudo"
            print_info "Installing to user directory: $HOME/.local/bin"
            INSTALL_DIR="$HOME/.local/bin"
            USER_INSTALL=true
        fi
    fi
}

# Check if already installed
check_existing_installation() {
    local binary_path="$INSTALL_DIR/$BINARY_NAME"
    
    if [[ -f "$binary_path" ]]; then
        if [[ "$FORCE" != true ]]; then
            print_warning "NetBird MSP Billing Analyzer is already installed at $binary_path"
            echo "Use --force to reinstall or --uninstall to remove"
            return 1
        else
            print_info "Forcing reinstallation (--force specified)"
        fi
    fi
    
    return 0
}

# Update PATH if necessary
update_path() {
    if [[ "$USER_INSTALL" != true ]]; then
        # System install, PATH should already include /usr/local/bin
        return 0
    fi
    
    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        print_success "$HOME/.local/bin is already in PATH"
        return 0
    fi
    
    print_info "Adding $HOME/.local/bin to PATH..."
    
    # Determine shell RC file
    local rc_file=""
    case "$SHELL" in
        */bash)
            rc_file="$HOME/.bashrc"
            [[ -f "$HOME/.bash_profile" ]] && rc_file="$HOME/.bash_profile"
            ;;
        */zsh)
            rc_file="$HOME/.zshrc"
            ;;
        */fish)
            rc_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            print_warning "Unknown shell: $SHELL"
            print_info "Please add $HOME/.local/bin to your PATH manually"
            return 0
            ;;
    esac
    
    if [[ -f "$rc_file" ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
        print_success "Added $HOME/.local/bin to PATH in $rc_file"
        print_info "Please restart your shell or run: source $rc_file"
    else
        print_warning "Shell RC file not found: $rc_file"
        print_info "Please add $HOME/.local/bin to your PATH manually"
    fi
}

# Uninstall function
uninstall() {
    local found=false
    
    # Check both possible locations
    for dir in "/usr/local/bin" "$HOME/.local/bin"; do
        local binary_path="$dir/$BINARY_NAME"
        if [[ -f "$binary_path" ]]; then
            print_info "Removing $binary_path..."
            rm -f "$binary_path"
            found=true
        fi
        
        local env_example="$dir/.env.example"
        if [[ -f "$env_example" ]]; then
            print_info "Removing $env_example..."
            rm -f "$env_example"
        fi
    done
    
    if [[ "$found" == true ]]; then
        print_success "NetBird MSP Billing Analyzer uninstalled successfully"
    else
        print_warning "NetBird MSP Billing Analyzer installation not found"
    fi
}

# Show post-installation instructions
show_post_install() {
    echo
    print_success "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Set up your API token:"
    if [[ -f "$INSTALL_DIR/.env.example" ]]; then
        echo "   cp $INSTALL_DIR/.env.example ~/.netbird-msp.env"
        echo "   # Edit ~/.netbird-msp.env and add your NETBIRD_API_TOKEN"
    else
        echo "   export NETBIRD_API_TOKEN='your_token_here'"
    fi
    echo
    echo "2. Run the analyzer:"
    echo "   $BINARY_NAME"
    echo
    echo "3. Get help:"
    echo "   $BINARY_NAME --help"
    echo
    
    if [[ "$USER_INSTALL" == true ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        print_warning "Note: $HOME/.local/bin may not be in your PATH"
        print_info "You may need to restart your shell or run the full path: $INSTALL_DIR/$BINARY_NAME"
    fi
}

# Main installation function
main() {
    print_info "NetBird MSP Billing Analyzer - Installation Script"
    print_info "GitHub: https://github.com/$REPO_OWNER/$REPO_NAME"
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -u|--user)
                USER_INSTALL=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --uninstall)
                uninstall
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check operating system compatibility
    local os=$(detect_os)
    if [[ "$os" == "unknown" ]]; then
        print_error "Unsupported operating system: $(uname -s)"
        print_error "This installer supports macOS and Linux only"
        exit 1
    fi
    
    print_success "Detected OS: $os"
    
    # Check dependencies
    check_dependencies
    
    # Set installation directory
    set_install_dir
    
    # Check for existing installation
    check_existing_installation
    
    # Get version to install
    if [[ -z "$VERSION" ]]; then
        VERSION=$(get_latest_version)
    fi
    
    if [[ "$QUIET" != true ]]; then
        print_info "Installing version: $VERSION"
    fi
    
    # Download and install
    download_and_install "$VERSION"
    
    # Update PATH if needed
    update_path
    
    # Show post-installation instructions
    show_post_install
}

# Run main function
main "$@"
