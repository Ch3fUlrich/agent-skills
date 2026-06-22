#!/bin/bash

# Parse arguments
EXPOSE_INTERNET=true
for arg in "$@"; do
    if [ "$arg" == "--no-internet" ]; then
        EXPOSE_INTERNET=false
    fi
done

echo -e "\e[36m=============================================\e[0m"
echo -e "\e[36m Antigravity Remote UI Session Setup (Linux)\e[0m"
echo -e "\e[36m=============================================\e[0m"

# 1. Check for Node.js and npm
if ! command -v npm &> /dev/null; then
    echo -e "\e[33mNode.js (npm) is not installed. Attempting to install automatically...\e[0m"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y nodejs npm
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y nodejs npm
    elif command -v pacman &> /dev/null; then
        sudo pacman -S nodejs npm
    else
        echo -e "\e[31mCould not detect package manager. Please install Node.js manually.\e[0m"
        exit 1
    fi
fi

# 1.5 Setup and Load Environment Variables (.env)
echo -e "\n\e[33mChecking environment configuration...\e[0m"
ENV_PATH="./.env"

if [ ! -f "$ENV_PATH" ]; then
    echo -e "\e[36mNo .env file found. Let's set up your APP_PASSWORD for Omni Remote Chat.\e[0m"
    read -p "Enter a passcode (leave blank to use the default 'antigravity'): " newPassword
    if [ -z "$newPassword" ]; then
        newPassword="antigravity"
    fi
    echo "APP_PASSWORD=$newPassword" > "$ENV_PATH"
    echo -e "\e[32mCreated .env file with your configured APP_PASSWORD.\e[0m"
fi

echo "Loading .env file into session..."
export $(grep -v '^#' "$ENV_PATH" | xargs)

# 2. Check Antigravity process and its command line
echo -e "\n\e[33mChecking Antigravity configuration...\e[0m"
HAS_DEBUG_PORT=false
EXE_PATH=""
FOUND_PORT=""
IS_RUNNING=false

# Find running antigravity processes
while read -r pid cmd; do
    if [ -n "$pid" ]; then
        IS_RUNNING=true
        EXE_PATH=$(readlink -f /proc/$pid/exe 2>/dev/null || echo "$cmd")
        if [[ "$cmd" =~ --remote-debugging-port=([0-9]+) ]]; then
            HAS_DEBUG_PORT=true
            FOUND_PORT="${BASH_REMATCH[1]}"
        fi
    fi
done <<< "$(ps -eo pid,cmd | grep -i '[a]ntigravity' | head -n 1)"

if [ "$IS_RUNNING" = true ]; then
    echo -e "\e[32mAntigravity is running.\e[0m"
    if [ "$HAS_DEBUG_PORT" = true ]; then
        echo -e "\e[32mRemote debugging is enabled on port $FOUND_PORT.\e[0m"
    fi
else
    echo -e "\e[33mAntigravity is NOT currently running.\e[0m"
fi

if [ -z "$EXE_PATH" ]; then
    if command -v antigravity &> /dev/null; then
        EXE_PATH="antigravity"
    else
        # Try common paths like AppImage or flatpak (fallback)
        EXE_PATH="antigravity"
    fi
fi

if [ "$HAS_DEBUG_PORT" = false ]; then
    echo -e "\n\e[31m[Action Required] Antigravity needs to be restarted with remote debugging enabled (--remote-debugging-port=7800).\e[0m"
    echo -e "\e[33mIf you have unsaved work, please save it now.\e[0m"
    read -p "Do you want to automatically restart Antigravity now? (y/n) " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Restarting Antigravity..."
        pkill -i antigravity
        sleep 2
        # Launch in background, detaching from terminal
        nohup "$EXE_PATH" --remote-debugging-port=7800 > /dev/null 2>&1 &
        echo -e "\e[32mAntigravity restarted successfully.\e[0m"
        sleep 5
    else
        exit 1
    fi
fi

# 3. Ensure local dependencies are installed and patched
echo -e "\n\e[33mPreparing Omni Remote Chat...\e[0m"
if [ ! -d "./node_modules/omni-antigravity-remote-chat" ]; then
    echo "Installing omni-antigravity-remote-chat locally..."
    npm install omni-antigravity-remote-chat --no-save > /dev/null
fi

echo "Applying compatibility patches for Antigravity Web UI..."
CONN_PATH="./node_modules/omni-antigravity-remote-chat/src/cdp/connection.js"
if [ -f "$CONN_PATH" ]; then
    sed -i "s/t.url?.includes('workbench.html') || (t.title && t.title.includes('workbench'))/t.type === 'page'/g" "$CONN_PATH"
    sed -i "s/t.url?.includes('workbench.html') && !t.url?.includes('jetski')/t.type === 'page'/g" "$CONN_PATH"
fi

SERVER_PATH="./node_modules/omni-antigravity-remote-chat/src/server.js"
if [ -f "$SERVER_PATH" ]; then
    sed -i "s/const CONTAINER_IDS = \['cascade', 'conversation', 'chat'\];/const CONTAINER_IDS = ['cascade', 'conversation', 'chat', 'root', 'app', '__next'];/g" "$SERVER_PATH"
    
    # Replace "if (!cascade) { // Debug info" with our fallback using a multi-line sed or perl
    perl -pi -e 's/if \(\!cascade\) \{\s*\/\/\s*Debug info/if (\!cascade) cascade = document.body;\n        if (\!cascade) {\n            \/\/ Debug info/g' "$SERVER_PATH"
    
    # Replace the query selectors
    perl -pi -e 's/\[...document.querySelectorAll\('"'"'#conversation \[contenteditable="true"\], #chat \[contenteditable="true"\], #cascade \[contenteditable="true"\]'"'"'\)\]/\[...document.querySelectorAll('"'"'body [contenteditable="true"]'"'"'\)\]/g' "$SERVER_PATH"
fi

# 4. Start the Remote Chat UI and LocalTunnel
echo -e "\n\e[33m[1/2] Starting omni-antigravity-remote-chat...\e[0m"
# Kill existing instance if running
pkill -f "node ./node_modules/omni-antigravity-remote-chat/src/server.js"
node ./node_modules/omni-antigravity-remote-chat/src/server.js &
SERVER_PID=$!

sleep 5

if [ "$EXPOSE_INTERNET" = true ]; then
    echo -e "\n\e[33m[2/2] Exposing local port 4747 via LocalTunnel...\e[0m"
    HAS_SSL=false
    if [ -f "./node_modules/omni-antigravity-remote-chat/certs/server.key" ] && [ -f "./node_modules/omni-antigravity-remote-chat/certs/server.cert" ]; then
        HAS_SSL=true
    fi
    
    LT_ARGS="--port 4747"
    if [ "$HAS_SSL" = true ]; then
        echo -e "\e[32mDetected HTTPS configuration! Telling LocalTunnel to expect an HTTPS local server...\e[0m"
        LT_ARGS="$LT_ARGS --local-https --allow-invalid-cert"
    fi
    
    echo -e "\e[32mDONE! Keep this terminal open to keep the server and tunnel running.\e[0m"
    npx -y localtunnel $LT_ARGS
    
    # When localtunnel exits, kill the server
    kill $SERVER_PID
else
    echo -e "\n\e[32mDONE! Connect your phone to your computer's local IP address on port 4747.\e[0m"
    echo "Press Ctrl+C to stop the server."
    wait $SERVER_PID
fi
