# Remote Session Setup Instructions

To connect your phone to the Antigravity session with a premium mobile UI, follow these simple steps:

## Step 1: Run the automated setup script
The automated script will handle all dependencies and configure the connection for you.

1. Open PowerShell and navigate to `${CODE_ROOT}\short_changes`.
2. Run the provided script:
   ```powershell
   .\start-remote-session.ps1
   ```
3. **Follow any on-screen prompts.** The script will automatically:
   - Check for and install Node.js if you don't have it.
   - Check if your Antigravity IDE is configured for remote debugging. If it's not, it will ask for your permission to restart the IDE with the correct settings. Simply press `Y` when prompted.
   - Start the remote UI server and the internet tunneling service (LocalTunnel).

## Step 2: Connect from your phone
1. Once the script finishes, you will see two new windows. Look at the LocalTunnel window. It will output a public URL looking like: `https://<random-words>.loca.lt`.
2. Open that URL on your phone's browser.
3. *Note:* LocalTunnel may show a "Friendly Reminder" warning screen on first load. Simply click "Click to Continue" to pass through to your session.
4. You will now see the well-designed Antigravity interface streaming to your phone. You can chat, view progress, and manage agents remotely!

## Optional: Local Network Only
If you only want to use it while on the same WiFi network (no internet exposure):
1. Run `.\start-remote-session.ps1 -ExposeInternet $false`.
2. Find your computer's local IP address (e.g., `192.168.1.5`).
3. Connect from your phone's browser via: `http://192.168.1.5:4747`.
