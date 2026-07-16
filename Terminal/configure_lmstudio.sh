#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  OpenCode + LM Studio + GLM-4.7-Flash Setup ${NC}"
echo -e "${GREEN}============================================${NC}\n"

# Default LM Studio configuration
LMSTUDIO_HOST="${LMSTUDIO_HOST:-localhost}"
LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"
LMSTUDIO_API_URL="http://${LMSTUDIO_HOST}:${LMSTUDIO_PORT}/v1"

# GLM-4.7-Flash model identifier (as shown in LM Studio)
# Common identifiers: glm-4.7-flash, zai-org/glm-4.7-flash
GLM_MODEL="${GLM_MODEL:-glm-4.7-flash}"

# OpenCode configuration paths
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/config.json"
OPENCODE_MCP_CONFIG="$OPENCODE_CONFIG_DIR/mcp.json"

echo -e "${BLUE}Configuration:${NC}"
echo -e "  LM Studio API URL: ${CYAN}${LMSTUDIO_API_URL}${NC}"
echo -e "  Model: ${CYAN}${GLM_MODEL}${NC}"
echo -e "  Config Directory: ${CYAN}${OPENCODE_CONFIG_DIR}${NC}\n"

# Check if LM Studio is running
echo -e "${BLUE}Checking LM Studio availability...${NC}"
if curl -s --connect-timeout 5 "${LMSTUDIO_API_URL}/models" > /dev/null 2>&1; then
    echo -e "${GREEN}OK LM Studio is running at ${LMSTUDIO_API_URL}${NC}\n"

    # List available models
    echo -e "${BLUE}Available models in LM Studio:${NC}"
    MODELS=$(curl -s "${LMSTUDIO_API_URL}/models" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "Unable to fetch models")
    if [ -n "$MODELS" ]; then
        echo "$MODELS" | while read -r model; do
            if [[ "$model" == *"glm"* ]] || [[ "$model" == *"GLM"* ]]; then
                echo -e "  ${GREEN}-> $model (GLM model detected)${NC}"
            else
                echo "  - $model"
            fi
        done
    else
        echo -e "  ${YELLOW}No models loaded. Please load GLM-4.7-Flash in LM Studio.${NC}"
    fi
    echo
else
    echo -e "${YELLOW}Warning: LM Studio is not running or not accessible at ${LMSTUDIO_API_URL}${NC}"
    echo -e "${YELLOW}Please ensure LM Studio is running with a local server enabled.${NC}\n"

    echo -e "${BLUE}LM Studio Setup Instructions:${NC}"
    echo "  1. Download LM Studio from https://lmstudio.ai/"
    echo "  2. Install and launch LM Studio"
    echo "  3. Download GLM-4.7-Flash model:"
    echo "     - Search for 'zai-org/glm-4.7-flash' or 'glm-4.7-flash'"
    echo "     - Download the GGUF quantized version (Q4_K_M or Q5_K_M recommended)"
    echo "  4. Load the model in LM Studio"
    echo "  5. Start the local server (default: localhost:1234)"
    echo "  6. Re-run this script"
    echo

    read -p "$(echo -e "${YELLOW}Continue with configuration anyway? [y/N]: ${NC}")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted.${NC}"
        exit 1
    fi
fi

# Create config directory if it doesn't exist
mkdir -p "$OPENCODE_CONFIG_DIR"

# Clean existing config for a fresh install
if [ -f "$OPENCODE_CONFIG_FILE" ]; then
    echo -e "${YELLOW}Clearing existing config: $OPENCODE_CONFIG_FILE${NC}"
    rm -f "$OPENCODE_CONFIG_FILE"
fi

# Prompt for custom model name
echo -e "${BLUE}Model Configuration:${NC}"
read -rp "$(echo -e "${YELLOW}Enter GLM model identifier [${GLM_MODEL}]: ${NC}")" MODEL_INPUT
if [ -n "$MODEL_INPUT" ]; then
    GLM_MODEL="$MODEL_INPUT"
fi

# Prompt for custom port
read -rp "$(echo -e "${YELLOW}Enter LM Studio port [${LMSTUDIO_PORT}]: ${NC}")" PORT_INPUT
if [ -n "$PORT_INPUT" ]; then
    LMSTUDIO_PORT="$PORT_INPUT"
    LMSTUDIO_API_URL="http://${LMSTUDIO_HOST}:${LMSTUDIO_PORT}/v1"
fi

echo

# Create OpenCode configuration
echo -e "${BLUE}Creating OpenCode configuration...${NC}"

cat > "$OPENCODE_CONFIG_FILE" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "lmstudio/${GLM_MODEL}",
  "small_model": "lmstudio/${GLM_MODEL}",
  "theme": "opencode",
  "autoupdate": true,
  "provider": {
    "lmstudio": {
      "api": "${LMSTUDIO_API_URL}",
      "models": {
        "${GLM_MODEL}": {
          "name": "GLM-4.7-Flash",
          "cost": {
            "input": 0,
            "output": 0
          },
          "limit": {
            "context": 131072,
            "output": 4096
          }
        }
      },
      "options": {
        "apiKey": "lm-studio",
        "timeout": 300000
      }
    },
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}",
        "timeout": 600000
      }
    }
  },
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "webfetch": "ask"
  },
  "tools": {
    "bash": true,
    "read": true,
    "write": true,
    "edit": true,
    "glob": true,
    "grep": true
  }
}
EOF

echo -e "${GREEN}OK OpenCode configuration created: ${OPENCODE_CONFIG_FILE}${NC}\n"

# Create shell aliases for easy switching
SHELL_RC="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

echo -e "${BLUE}Adding shell aliases...${NC}"

# Check if aliases already exist
if ! grep -q "# OpenCode LM Studio aliases" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'EOF'

# OpenCode LM Studio aliases
alias opencode-glm='opencode --model lmstudio/glm-4.7-flash'
alias opencode-claude='opencode --model anthropic/claude-sonnet-4-6'
alias lmstudio-status='curl -s http://localhost:1234/v1/models | jq .'
EOF
    echo -e "${GREEN}OK Shell aliases added to ${SHELL_RC}${NC}"
else
    echo -e "${YELLOW}Shell aliases already exist in ${SHELL_RC}${NC}"
fi

echo

# Create a quick-start script
QUICKSTART_SCRIPT="$OPENCODE_CONFIG_DIR/start-lmstudio-opencode.sh"
cat > "$QUICKSTART_SCRIPT" << 'EOF'
#!/bin/bash
# Quick-start script for OpenCode with LM Studio

LMSTUDIO_PORT="${LMSTUDIO_PORT:-1234}"

echo "Checking LM Studio..."
if ! curl -s --connect-timeout 3 "http://localhost:${LMSTUDIO_PORT}/v1/models" > /dev/null 2>&1; then
    echo "Error: LM Studio is not running on port ${LMSTUDIO_PORT}"
    echo "Please start LM Studio and load a model first."
    exit 1
fi

echo "LM Studio is ready. Starting OpenCode..."
exec opencode "$@"
EOF
chmod +x "$QUICKSTART_SCRIPT"
echo -e "${GREEN}OK Quick-start script created: ${QUICKSTART_SCRIPT}${NC}"

# Summary
echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}  Configuration Complete!                   ${NC}"
echo -e "${GREEN}============================================${NC}\n"

echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  Provider: LM Studio (OpenAI-compatible)"
echo "  Model: ${GLM_MODEL}"
echo "  API URL: ${LMSTUDIO_API_URL}"
echo "  Config: ${OPENCODE_CONFIG_FILE}"
echo "  MCP Config: ${OPENCODE_MCP_CONFIG}"

echo -e "\n${YELLOW}GLM-4.7-Flash Model Setup:${NC}"
echo "  1. Open LM Studio"
echo "  2. Go to 'Discover' or 'Search'"
echo "  3. Search for: zai-org/glm-4.7-flash"
echo "  4. Download a quantized version (recommended: Q4_K_M or Q5_K_M)"
echo "  5. Load the model"
echo "  6. Start the local server (Settings -> Local Server -> Start)"

echo -e "\n${YELLOW}Usage:${NC}"
echo "  # Start OpenCode with GLM-4.7-Flash"
echo "  opencode-glm"
echo ""
echo "  # Or use the quick-start script"
echo "  ~/.config/opencode/start-lmstudio-opencode.sh"
echo ""
echo "  # Switch to Claude (requires ANTHROPIC_API_KEY)"
echo "  opencode-claude"
echo ""
echo "  # Check LM Studio status"
echo "  lmstudio-status"

echo -e "\n${YELLOW}Environment Variables:${NC}"
echo "  LMSTUDIO_HOST - LM Studio host (default: localhost)"
echo "  LMSTUDIO_PORT - LM Studio port (default: 1234)"
echo "  GLM_MODEL     - Model identifier (default: glm-4.7-flash)"

echo -e "\n${BLUE}Note: Restart your terminal or run 'source ${SHELL_RC}' to use aliases.${NC}"

echo -e "\n${GREEN}Done!${NC}"
