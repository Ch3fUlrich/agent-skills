param (
    [switch]$ExposeInternet = $true
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Antigravity Remote UI Session Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# 1. Check for Node.js and install if missing
if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
    Write-Host "Node.js (npm) is not installed. Attempting to install automatically..." -ForegroundColor Yellow
    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        Write-Host "Using winget to install Node.js..."
        Start-Process -FilePath "winget" -ArgumentList "install", "-e", "--id", "OpenJS.NodeJS", "--accept-source-agreements", "--accept-package-agreements" -Wait -NoNewWindow
    } else {
        Write-Host "winget not found. Downloading Node.js MSI..."
        $msiPath = "$env:TEMP\nodejs.msi"
        Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi" -OutFile $msiPath
        Write-Host "Installing Node.js... Please wait."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$msiPath`"", "/quiet", "/norestart" -Wait
    }
    Write-Host "Refreshing environment variables..."
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
        Write-Host "Node.js installation completed, but npm is still not found in PATH. Please run script again." -ForegroundColor Red
        exit
    }
}

# 1.5 Setup and Load Environment Variables (.env)
Write-Host "`nChecking environment configuration..." -ForegroundColor Yellow
$envPath = ".\.env"

if (-not (Test-Path $envPath)) {
    Write-Host "No .env file found. Let's set up your APP_PASSWORD for Omni Remote Chat." -ForegroundColor Cyan
    $newPassword = Read-Host "Enter a passcode (leave blank to use the default 'antigravity')"
    if ([string]::IsNullOrWhiteSpace($newPassword)) {
        $newPassword = "antigravity"
    }
    Set-Content -Path $envPath -Value "APP_PASSWORD=$newPassword"
    Write-Host "Created .env file with your configured APP_PASSWORD." -ForegroundColor Green
}

# Load .env variables into the current PowerShell session
Write-Host "Loading .env file into session..."
foreach ($line in Get-Content $envPath) {
    if ($line -match "^([^#=]+)=(.*)$") {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

# 2. Check Antigravity process and its command line
Write-Host "`nChecking Antigravity configuration..." -ForegroundColor Yellow
$antigravityProcs = Get-CimInstance Win32_Process -Filter "Name = 'Antigravity.exe'"
$hasDebugPort = $false
$exePath = ""
$foundPort = ""
$isRunning = ($null -ne $antigravityProcs) -and ($antigravityProcs.Count -gt 0 -or $antigravityProcs.Name -eq 'Antigravity.exe')

foreach ($proc in $antigravityProcs) {
    if ($proc.CommandLine -match "--remote-debugging-port=(\d+)") {
        $hasDebugPort = $true
        $foundPort = $matches[1]
    }
    if ($proc.ExecutablePath) {
        $exePath = $proc.ExecutablePath
    }
}

if ($isRunning) {
    Write-Host "Antigravity is running." -ForegroundColor Green
    if ($hasDebugPort) {
        Write-Host "Remote debugging is enabled on port $foundPort." -ForegroundColor Green
    }
} else {
    Write-Host "Antigravity is NOT currently running." -ForegroundColor Yellow
}

if (-not $exePath) {
    $exePath = "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"
    if (-not (Test-Path $exePath)) { $exePath = "C:\Program Files\Antigravity\Antigravity.exe" }
}

if (-not $hasDebugPort) {
    Write-Host "`n[Action Required] Antigravity needs to be restarted with remote debugging enabled (--remote-debugging-port=7800)." -ForegroundColor Red
    Write-Host "If you have unsaved work, please save it now." -ForegroundColor Yellow
    $response = Read-Host "Do you want to automatically restart Antigravity now? (Y/N)"
    if ($response -match "^[yY]") {
        Write-Host "Restarting Antigravity..."
        Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        if (Test-Path $exePath) {
            Start-Process -FilePath $exePath -ArgumentList "--remote-debugging-port=7800"
            Write-Host "Antigravity restarted successfully." -ForegroundColor Green
            Start-Sleep -Seconds 5
        } else {
            Write-Host "Could not find Antigravity executable at $exePath." -ForegroundColor Red
            exit
        }
    } else { exit }
}

# 3. Ensure local dependencies are installed and patched
Write-Host "`nPreparing Omni Remote Chat..." -ForegroundColor Yellow
if (-not (Test-Path ".\node_modules\omni-antigravity-remote-chat")) {
    Write-Host "Installing omni-antigravity-remote-chat locally..."
    npm install omni-antigravity-remote-chat --no-save | Out-Null
}

Write-Host "Applying compatibility patches for Antigravity Web UI..."
$connPath = ".\node_modules\omni-antigravity-remote-chat\src\cdp\connection.js"
if (Test-Path $connPath) {
    $c1 = Get-Content $connPath -Raw
    $c1 = $c1 -replace "t\.url\?\.includes\('workbench\.html'\) \|\| \(t\.title && t\.title\.includes\('workbench'\)\)", "t.type === 'page'"
    $c1 = $c1 -replace "t\.url\?\.includes\('workbench\.html'\) && \!t\.url\?\.includes\('jetski'\)", "t.type === 'page'"
    Set-Content -Path $connPath -Value $c1
}

$serverPath = ".\node_modules\omni-antigravity-remote-chat\src\server.js"
if (Test-Path $serverPath) {
    $c2 = Get-Content $serverPath -Raw
    $c2 = $c2 -replace "const CONTAINER_IDS = \['cascade', 'conversation', 'chat'\];", "const CONTAINER_IDS = ['cascade', 'conversation', 'chat', 'root', 'app', '__next'];"
    $c2 = $c2 -replace "if \(\!cascade\) \{\s+// Debug info", "if (!cascade) cascade = document.body;`n        if (!cascade) {`n            // Debug info"
    $c2 = $c2 -replace "'#conversation \\\[contenteditable=""true""\\\], #chat \\\[contenteditable=""true""\\\], #cascade \\\[contenteditable=""true""\\\]'", "'body [contenteditable=""true""]'"
    Set-Content -Path $serverPath -Value $c2
}

# 4. Start the Remote Chat UI and LocalTunnel
Write-Host "`n[1/2] Starting omni-antigravity-remote-chat..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "node .\node_modules\omni-antigravity-remote-chat\src\server.js" -WindowStyle Normal

Start-Sleep -Seconds 5

if ($ExposeInternet) {
    Write-Host "`n[2/2] Exposing local port 4747 via LocalTunnel..." -ForegroundColor Yellow
    $hasSSL = (Test-Path ".\node_modules\omni-antigravity-remote-chat\certs\server.key") -and (Test-Path ".\node_modules\omni-antigravity-remote-chat\certs\server.cert")
    $ltArgs = "localtunnel --port 4747"
    if ($hasSSL) {
        Write-Host "Detected HTTPS configuration! Telling LocalTunnel to expect an HTTPS local server..." -ForegroundColor Green
        $ltArgs += " --local-https --allow-invalid-cert"
    }
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "npx -y $ltArgs" -WindowStyle Normal
    Write-Host "`nDONE! Check the two new PowerShell windows." -ForegroundColor Green
} else {
    Write-Host "`nDONE! Connect your phone to your computer's local IP address on port 4747." -ForegroundColor Green
}
