# Terminal Chat - PowerShell TCP Chat Application

A simple terminal-based chat application for Windows PCs on the same local network, implemented in PowerShell.

## Features

- **Simple TCP-based communication** between two Windows PCs
- **Real-time bidirectional messaging**
- **Easy to use** terminal interface
- **No external dependencies** - uses native PowerShell and .NET classes
- **Graceful disconnect** handling
- **Color-coded messages** for better readability

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Both PCs on the same local network

## Quick Start

### 1. Setup Execution Policy (if needed)

If you get an execution policy error, run PowerShell as Administrator and execute:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Or run scripts with bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\server.ps1
```

### 2. Start the Server

On **PC 1** (the server):

```powershell
.\server.ps1
```

Or with a custom port:

```powershell
.\server.ps1 -Port 9999
```

Or with a custom IP file path (for network sharing):

```powershell
.\server.ps1 -IPFilePath "\\SharedFolder\chatrr"
```

The server will:
- Display your IP address prominently highlighted (e.g., `192.168.1.100`)
- **Automatically create IP files** in `%TEMP%\chatrr` (or your custom path)
- Each IP address gets its own file (filename = IP, content = port)
- Show the file location so clients can auto-detect

**Important:** The server IP address will be displayed in a highlighted box. The server also writes IP files that clients can automatically detect.

### 3. Connect the Client

On **PC 2** (the client):

#### Option A: Auto-Detection (Recommended)

If both PCs can access the same file path (e.g., shared network folder or same `%TEMP%` location):

```powershell
.\client.ps1
```

The client will:
- **Automatically scan for server IP files** in `%TEMP%\chatrr` (or custom path)
- If found, prompt: "Found server IP file: 192.168.1.100, Use this server? (Y/n)"
- Auto-detect the port from the file
- Connect automatically (no manual IP entry needed!)

#### Option B: Manual Entry

If auto-detection doesn't work or you want to specify manually:

```powershell
.\client.ps1 -ServerIP 192.168.1.100
```

Or with custom port:

```powershell
.\client.ps1 -ServerIP 192.168.1.100 -Port 9999
```

#### Option C: Custom IP File Path

If using a shared network folder:

```powershell
.\client.ps1 -IPFilePath "\\SharedFolder\chatrr"
```

This will scan that path for server IP files and auto-detect.

### 5. Start Chatting!

Once connected:
- Type your messages and press Enter
- Messages appear as:
  - `You: [your message]` (in cyan)
  - `Them: [their message]` (in yellow)
- Type `/quit` or `/exit` to disconnect gracefully

## IP File Sharing (Auto-Detection)

### How It Works

The server automatically creates files with IP addresses as filenames (no extension) in a specified directory. The client can scan this directory to automatically find and connect to servers.

**Default Location:** `%TEMP%\chatrr` (usually `C:\Users\YourName\AppData\Local\Temp\chatrr`)

**File Format:**
- **Filename:** IP address (e.g., `192.168.1.100`)
- **Content:** Port number (e.g., `12345`)

### Setting Up Shared Path

For best results, use a shared network folder that both PCs can access:

**On Server:**
```powershell
.\server.ps1 -IPFilePath "\\SharedFolder\chatrr"
```

**On Client:**
```powershell
.\client.ps1 -IPFilePath "\\SharedFolder\chatrr"
```

### Local Temp Folder

If both PCs are on the same machine or have synchronized temp folders, the default `%TEMP%\chatrr` works automatically. Otherwise, use a shared network path.

## Finding Your IP Address

### For Server Users

The server script automatically detects and displays your IP address when it starts. It will be shown in a highlighted box like:

```
----------------------------------------
  SERVER IP ADDRESS (share this!):
----------------------------------------
  >>> 192.168.1.100 <<<
----------------------------------------
```

The server also creates IP files automatically for client auto-detection.

### Manual IP Lookup

If the server doesn't show an IP or you need to verify it:

**Method 1: PowerShell**
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*"}
```

**Method 2: Command Prompt**
```cmd
ipconfig
```
Look for "IPv4 Address" under your active network adapter (usually not 127.0.0.1). It will look like `192.168.1.XXX` or `10.0.0.XXX`.

### For Client Users

The client will prompt you for the server IP. You need to get this from the person running the server. They can:
- Read it from the server terminal (it's displayed prominently)
- Run `ipconfig` on the server PC and share the IPv4 address

## Troubleshooting

### Connection Refused / Cannot Connect

1. **Check server is running**: Make sure server.ps1 is running on the other PC
2. **Verify IP address**: Double-check the server IP address
3. **Check port number**: Ensure both are using the same port (default: 12345)
4. **Firewall**: Windows Firewall may block the connection
   - Allow PowerShell through firewall, or
   - Allow the specific port through firewall:
     ```powershell
     New-NetFirewallRule -DisplayName "Terminal Chat" -Direction Inbound -LocalPort 12345 -Protocol TCP -Action Allow
     ```

### Port Already in Use

If you see "port already in use" error:
- Another application is using that port
- Choose a different port: `.\server.ps1 -Port 9999`

### Execution Policy Error

If you see "execution of scripts is disabled":
- Run as Administrator: `Set-ExecutionPolicy RemoteSigned`
- Or use: `powershell -ExecutionPolicy Bypass -File .\server.ps1`

### Messages Not Appearing

- Ensure both sides are connected (check connection status)
- Try disconnecting and reconnecting
- Check firewall settings

## Usage Examples

### Server on Default Port
```powershell
.\server.ps1
```

### Server on Custom Port
```powershell
.\server.ps1 -Port 5555
```

### Client with IP Parameter
```powershell
.\client.ps1 -ServerIP 192.168.1.100
```

### Client with IP and Port
```powershell
.\client.ps1 -ServerIP 192.168.1.100 -Port 5555
```

## Commands

- `/quit` or `/exit` - Disconnect gracefully
- `Ctrl+C` - Force disconnect (not recommended, use /quit instead)

## Technical Details

- **Protocol**: TCP/IP
- **Default Port**: 12345
- **Encoding**: UTF-8
- **Max Message Length**: ~4096 characters
- **Connection**: Persistent until disconnect

## Limitations

- **Single client per server** (one-to-one chat only)
- **No encryption** (plain text messages)
- **Local network only** (not designed for internet use)
- **No message history** (messages lost on disconnect)
- **Windows PowerShell only** (not cross-platform)

## Security Note

⚠️ **This application is for local network use only and sends messages in plain text. Do not use over untrusted networks or for sensitive communications.**

## Files

- `server.ps1` - Server script (runs on PC 1)
- `client.ps1` - Client script (runs on PC 2)
- `README.md` - This file
- `IMPLEMENTATION_PLAN.md` - Detailed implementation plan

## License

Free to use and modify.

