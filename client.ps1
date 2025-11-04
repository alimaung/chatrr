# Terminal Chat Client
# TCP Socket Client for Local Network Chat

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "",
    
    [int]$Port = 12345,
    
    [string]$IPFilePath = "$env:TEMP\chatrr"
)

# Configuration
$script:isRunning = $true
$script:client = $null
$script:stream = $null
$script:Port = $Port  # Store port in script scope

# Function to display client startup info
function Show-ClientInfo {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Terminal Chat Client" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Function to find server IP from files
function Find-ServerIPFromFiles {
    param([string]$FilePath)
    
    try {
        if (-not (Test-Path $FilePath)) {
            return $null
        }
        
        # Look for files named like IP addresses
        $ipFiles = Get-ChildItem -Path $FilePath -File -ErrorAction SilentlyContinue | 
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object LastWriteTime -Descending
        
        if ($ipFiles.Count -eq 0) {
            return $null
        }
        
        # Return the most recent IP file
        $latestFile = $ipFiles[0]
        $ip = $latestFile.Name
        $portFromFile = Get-Content -Path $latestFile.FullName -Raw -ErrorAction SilentlyContinue
        
        return @{
            IP = $ip
            Port = if ($portFromFile) { [int]$portFromFile.Trim() } else { 12345 }
            FilePath = $latestFile.FullName
        }
    } catch {
        return $null
    }
}

# Function to get server IP if not provided
function Get-ServerIP {
    # First try to find IP from files
    $fileInfo = Find-ServerIPFromFiles -FilePath $IPFilePath
    
    if ($fileInfo -and -not [string]::IsNullOrWhiteSpace($ServerIP)) {
        # Use provided IP, but check if port was in file
        if ($script:Port -eq 12345 -and $fileInfo.Port -ne 12345) {
            Write-Host "Found port $($fileInfo.Port) from IP file, using it." -ForegroundColor Green
            $script:Port = $fileInfo.Port
        }
        return $ServerIP.Trim()
    }
    
    if ($fileInfo) {
        Write-Host ""
        Write-Host "----------------------------------------" -ForegroundColor Gray
        Write-Host "  AUTO-DETECTED SERVER" -ForegroundColor White -BackgroundColor DarkGreen
        Write-Host "----------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Found server IP file: $($fileInfo.IP)" -ForegroundColor Green
        Write-Host "Port: $($fileInfo.Port)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Use this server? (Y/n):" -ForegroundColor Yellow
        $confirm = Read-Host
        if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match '^[Yy]') {
            $script:Port = $fileInfo.Port
            return $fileInfo.IP
        }
    }
    
    # Fallback to manual entry
    if ([string]::IsNullOrWhiteSpace($ServerIP)) {
        Write-Host ""
        Write-Host "----------------------------------------" -ForegroundColor Gray
        Write-Host "  CONNECTION SETUP" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "----------------------------------------" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To connect, you need the server's IP address." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "The server PC should show its IP address when started." -ForegroundColor Yellow
        Write-Host "It will look like: 192.168.1.XXX or 10.0.0.XXX" -ForegroundColor Gray
        Write-Host ""
        Write-Host "If you don't know the server IP:" -ForegroundColor Yellow
        Write-Host "  - Ask the person running the server" -ForegroundColor Gray
        Write-Host "  - Or they can run 'ipconfig' on the server PC" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Enter server IP address:" -ForegroundColor Yellow
        $input = Read-Host
        return $input.Trim()
    }
    return $ServerIP.Trim()
}

# Function to connect to server
function Connect-ToServer {
    param(
        [string]$IP,
        [int]$Port
    )
    
    try {
        Write-Host "Connecting to $IP`:$Port..." -ForegroundColor Yellow
        
        $script:client = New-Object System.Net.Sockets.TcpClient
        $script:client.ReceiveTimeout = 5000
        $script:client.Connect($IP, $Port)
        
        if ($script:client.Connected) {
            $script:stream = $script:client.GetStream()
            $script:stream.ReadTimeout = 500
            Write-Host "Connected successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Failed to connect." -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Connection error: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible issues:" -ForegroundColor Yellow
        Write-Host "  - Server is not running" -ForegroundColor Gray
        Write-Host "  - Wrong IP address" -ForegroundColor Gray
        Write-Host "  - Wrong port number" -ForegroundColor Gray
        Write-Host "  - Firewall blocking connection" -ForegroundColor Gray
        return $false
    }
}

# Function to handle disconnect
function Handle-Disconnect {
    Write-Host ""
    Write-Host "Disconnected from server." -ForegroundColor Yellow
    if ($script:stream) {
        try { $script:stream.Close() } catch {}
        $script:stream = $null
    }
    if ($script:client) {
        try { $script:client.Close() } catch {}
        $script:client = $null
    }
}

# Main client chat function
function Start-Chat {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "   CONNECTED TO SERVER!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Type your messages and press Enter." -ForegroundColor Cyan
    Write-Host "Type '/quit' or '/exit' to disconnect." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host ""
    
    # Create reader and writer
    $reader = New-Object System.IO.StreamReader($script:stream, [System.Text.Encoding]::UTF8)
    $writer = New-Object System.IO.StreamWriter($script:stream, [System.Text.Encoding]::UTF8)
    $writer.AutoFlush = $true
    
    # Create runspace for receiving messages
    $receiveRunspace = [runspacefactory]::CreateRunspace()
    $receiveRunspace.Open()
    $receivePS = [PowerShell]::Create()
    $receivePS.Runspace = $receiveRunspace
    
    $receiveScript = {
        param($stream, $reader)
        $messages = New-Object System.Collections.ArrayList
        while ($true) {
            try {
                if ($stream.DataAvailable) {
                    $line = $reader.ReadLine()
                    if ($line) {
                        [void]$messages.Add($line)
                    }
                } else {
                    Start-Sleep -Milliseconds 100
                }
                if (-not $stream.CanRead) {
                    break
                }
            } catch {
                break
            }
        }
        return $messages
    }
    
    $receivePS.AddScript($receiveScript).AddArgument($script:stream).AddArgument($reader) | Out-Null
    $receiveHandle = $receivePS.BeginInvoke()
    
    # Main chat loop
    while ($script:client.Connected -and $script:isRunning) {
        # Check for received messages (non-blocking)
        if ($receiveHandle.IsCompleted) {
            $received = $receivePS.EndInvoke($receiveHandle)
            if ($received) {
                foreach ($msg in $received) {
                    if ($msg) {
                        if ($msg -match "^(/quit|/exit)$") {
                            Write-Host "Server disconnected." -ForegroundColor Yellow
                            $script:isRunning = $false
                            break
                        }
                        Write-Host "Them: $msg" -ForegroundColor Yellow
                    }
                }
            }
            break
        }
        
        # Check if data is available (quick check)
        if ($script:stream.DataAvailable) {
            try {
                $line = $reader.ReadLine()
                if ($line) {
                    if ($line -match "^(/quit|/exit)$") {
                        Write-Host "Server disconnected." -ForegroundColor Yellow
                        $script:isRunning = $false
                        break
                    }
                    Write-Host "Them: $line" -ForegroundColor Yellow
                }
            } catch {
                # Connection lost
                break
            }
        }
        
        # Read user input (this will block, but we check receive above)
        try {
            $input = Read-Host
            if ($input.Trim() -eq "") {
                continue
            }
            
            # Check for quit command
            if ($input.Trim() -match "^(/quit|/exit)$") {
                try {
                    $writer.WriteLine("/quit")
                    Write-Host "Disconnecting..." -ForegroundColor Yellow
                } catch {
                    # Ignore write errors on disconnect
                }
                break
            }
            
            # Send message
            try {
                $writer.WriteLine($input)
                Write-Host "You: $input" -ForegroundColor Cyan
            } catch {
                Write-Host "Failed to send message. Connection lost?" -ForegroundColor Red
                break
            }
        } catch {
            # Input error (Ctrl+C handled separately)
            break
        }
        
        # Brief pause to allow receive processing
        Start-Sleep -Milliseconds 50
    }
    
    # Cleanup
    if ($receiveHandle) {
        try {
            $receivePS.Stop()
            $receiveRunspace.Close()
        } catch {}
    }
    try {
        $reader.Close()
        $writer.Close()
    } catch {}
    Handle-Disconnect
}

# Handle Ctrl+C gracefully
[Console]::TreatControlCAsInput = $false
$null = Register-ObjectEvent -InputObject ([System.Console]) -EventName "CancelKeyPress" -Action {
    $script:isRunning = $false
    Write-Host "`nDisconnecting..." -ForegroundColor Yellow
}

# Main execution
Show-ClientInfo

# Get server IP (this may auto-detect from files)
$serverIP = Get-ServerIP

# Validate IP format (basic check)
if ([string]::IsNullOrWhiteSpace($serverIP)) {
    Write-Host "Server IP address is required." -ForegroundColor Red
    exit 1
}

# Optional: Prompt for port if needed (only if port is still default and wasn't auto-detected)
if ($script:Port -eq 12345) {
    Write-Host "Enter port number (default: 12345, press Enter to use default):" -ForegroundColor Yellow
    $portInput = Read-Host
    if (-not [string]::IsNullOrWhiteSpace($portInput)) {
        if ([int]::TryParse($portInput, [ref]$script:Port)) {
            # Port parsed successfully
        } else {
            Write-Host "Invalid port, using default 12345" -ForegroundColor Yellow
            $script:Port = 12345
        }
    }
}

Write-Host ""

# Connect to server
if (Connect-ToServer -IP $serverIP -Port $script:Port) {
    Write-Host ""
    Start-Sleep -Seconds 1
    Start-Chat
} else {
    Write-Host ""
    Write-Host "Failed to connect. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Goodbye!" -ForegroundColor Cyan
