# Terminal Chat Client
# TCP Socket Client for Local Network Chat

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "",
    
    [int]$Port = 12345,
    
    [string]$IPFilePath = "$env:TEMP\chatrr"
)

# Load logging module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$loggerPath = Join-Path $scriptPath "logger.ps1"
if (Test-Path $loggerPath) {
    . $loggerPath
    Initialize-Logger -LogDirectory "$env:TEMP\chatrr" -LogFileName "client.log"
    Write-Log "INFO" "Client script started" -Category "Startup" -AdditionalData @{
        "ServerIP" = $ServerIP
        "Port" = $Port
        "IPFilePath" = $IPFilePath
    }
} else {
    # Fallback logging if module not found
    function Write-Log { param($Level, $Message, $Category, $Exception, $AdditionalData) }
    function Write-LogException { param($Exception, $Context, $AdditionalData) }
    function Write-LogConnection { param($Event, $Details, $ConnectionInfo) }
}

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
        Write-LogConnection -Event "Attempting connection" -ConnectionInfo @{
            "ServerIP" = $IP
            "Port" = $Port
        }
        
        $script:client = New-Object System.Net.Sockets.TcpClient
        $script:client.ReceiveTimeout = 5000
        $script:client.Connect($IP, $Port)
        
        if ($script:client.Connected) {
            $script:stream = $script:client.GetStream()
            $script:stream.ReadTimeout = 500
            Write-Host "Connected successfully!" -ForegroundColor Green
            Write-LogConnection -Event "Connected successfully" -ConnectionInfo @{
                "ServerIP" = $IP
                "Port" = $Port
                "LocalEndpoint" = $script:client.Client.LocalEndPoint.ToString()
                "RemoteEndpoint" = $script:client.Client.RemoteEndPoint.ToString()
            }
            return $true
        } else {
            Write-Host "Failed to connect." -ForegroundColor Red
            Write-Log "ERROR" "Connection failed - client not connected" -Category "Connection" -AdditionalData @{
                "ServerIP" = $IP
                "Port" = $Port
            }
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
        
        Write-LogException -Exception $_ -Context "Connect-ToServer" -AdditionalData @{
            "ServerIP" = $IP
            "Port" = $Port
            "ErrorType" = $_.GetType().Name
        }
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
    
    Write-Log "INFO" "Entering main chat loop" -Category "Chat"
    
    # Main chat loop - simplified polling approach
    while ($script:client.Connected -and $script:isRunning) {
        try {
            # Check if data is available (non-blocking check)
            if ($script:stream.DataAvailable) {
                try {
                    $line = $reader.ReadLine()
                    if ($line) {
                        if ($line -match "^(/quit|/exit)$") {
                            Write-Host "Server disconnected." -ForegroundColor Yellow
                            Write-LogConnection -Event "Server sent disconnect" -Details $line
                            $script:isRunning = $false
                            break
                        }
                        Write-Host "Them: $line" -ForegroundColor Yellow
                        Write-Log "DEBUG" "Received message" -Category "Chat" -AdditionalData @{ "Message" = $line }
                    }
                } catch {
                    Write-LogException -Exception $_ -Context "Reading incoming message" -AdditionalData @{
                        "StreamAvailable" = $script:stream.DataAvailable
                        "ClientConnected" = $script:client.Connected
                    }
                    break
                }
            }
            
            # Check for user input (non-blocking check)
            if ([Console]::KeyAvailable) {
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
                            Write-LogConnection -Event "Client disconnecting" -Details $input
                        } catch {
                            Write-LogException -Exception $_ -Context "Sending quit message"
                        }
                        break
                    }
                    
                    # Send message
                    try {
                        $writer.WriteLine($input)
                        Write-Host "You: $input" -ForegroundColor Cyan
                        Write-Log "DEBUG" "Sent message" -Category "Chat" -AdditionalData @{ "Message" = $input }
                    } catch {
                        Write-Host "Failed to send message. Connection lost?" -ForegroundColor Red
                        Write-LogException -Exception $_ -Context "Sending message" -AdditionalData @{
                            "Message" = $input
                            "ClientConnected" = $script:client.Connected
                        }
                        break
                    }
                } catch {
                    Write-LogException -Exception $_ -Context "Reading user input"
                    break
                }
            } else {
                # No input ready, brief pause to allow receive processing
                Start-Sleep -Milliseconds 50
            }
            
            # Check connection status
            if (-not $script:client.Connected) {
                Write-Log "WARN" "Client connection lost detected in loop" -Category "Connection"
                break
            }
        } catch {
            Write-LogException -Exception $_ -Context "Main chat loop" -AdditionalData @{
                "ClientConnected" = $script:client.Connected
                "IsRunning" = $script:isRunning
            }
            break
        }
    }
    
    Write-Log "INFO" "Exiting main chat loop" -Category "Chat"
    
    # Cleanup
    try {
        $reader.Close()
        $writer.Close()
        Write-Log "DEBUG" "Stream reader/writer closed" -Category "Cleanup"
    } catch {
        Write-LogException -Exception $_ -Context "Closing streams"
    }
    Handle-Disconnect
}

# Handle Ctrl+C gracefully
[Console]::TreatControlCAsInput = $false
$null = Register-ObjectEvent -InputObject ([System.Console]) -EventName "CancelKeyPress" -Action {
    $script:isRunning = $false
    Write-Host "`nDisconnecting..." -ForegroundColor Yellow
    Write-Log "INFO" "Ctrl+C pressed - disconnecting" -Category "UserAction"
}

# Main execution with error handling
try {
    Show-ClientInfo

    # Get server IP (this may auto-detect from files)
    $serverIP = Get-ServerIP

    # Validate IP format (basic check)
    if ([string]::IsNullOrWhiteSpace($serverIP)) {
        Write-Host "Server IP address is required." -ForegroundColor Red
        Write-Log "ERROR" "Server IP address is empty" -Category "Validation"
        exit 1
    }

    # Optional: Prompt for port if needed (only if port is still default and wasn't auto-detected)
    if ($script:Port -eq 12345) {
        Write-Host "Enter port number (default: 12345, press Enter to use default):" -ForegroundColor Yellow
        $portInput = Read-Host
        if (-not [string]::IsNullOrWhiteSpace($portInput)) {
            if ([int]::TryParse($portInput, [ref]$script:Port)) {
                Write-Log "INFO" "Port changed by user" -Category "Configuration" -AdditionalData @{ "Port" = $script:Port }
            } else {
                Write-Host "Invalid port, using default 12345" -ForegroundColor Yellow
                Write-Log "WARN" "Invalid port input, using default" -Category "Configuration" -AdditionalData @{ "Input" = $portInput }
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
        Write-Log "ERROR" "Failed to connect to server - exiting" -Category "Connection"
        exit 1
    }

    Write-Host ""
    Write-Host "Goodbye!" -ForegroundColor Cyan
    Write-Log "INFO" "Client exiting normally" -Category "Shutdown"
} catch {
    Write-Host ""
    Write-Host "FATAL ERROR: Client crashed!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file location: $(Get-LogFilePath)" -ForegroundColor Yellow
    
    Write-LogException -Exception $_ -Context "Main execution" -AdditionalData @{
        "ServerIP" = $serverIP
        "Port" = $script:Port
    }
    Write-Log "FATAL" "Client crashed and is exiting" -Category "Crash"
    
    exit 1
}
