# Terminal Chat Server
# TCP Socket Server for Local Network Chat

param(
    [int]$Port = 12345,
    [string]$IPFilePath = "$env:TEMP\chatrr"
)

# Load logging module
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$loggerPath = Join-Path $scriptPath "logger.ps1"
if (Test-Path $loggerPath) {
    . $loggerPath
    Initialize-Logger -LogDirectory "$env:TEMP\chatrr" -LogFileName "server.log"
    Write-Log "INFO" "Server script started" -Category "Startup" -AdditionalData @{
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
$script:listener = $null

# Function to get local IP addresses
function Get-LocalIP {
    try {
        $ips = @()
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
        foreach ($adapter in $adapters) {
            $ips += $adapter.IPAddress
        }
        return $ips
    } catch {
        # Fallback for systems without Get-NetIPAddress
        $hostIP = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | 
            Where-Object { $_.AddressFamily -eq "InterNetwork" -and $_.ToString() -notlike "127.*" }
        return $hostIP | ForEach-Object { $_.ToString() }
    }
}

# Function to write IP to file
function Write-IPFile {
    param(
        [string]$IP,
        [int]$Port,
        [string]$FilePath
    )
    
    try {
        # Create directory if it doesn't exist
        $dir = Split-Path -Path $FilePath -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        
        # Write IP file (filename is IP, content is port)
        $filePath = Join-Path $FilePath $IP
        $Port | Out-File -FilePath $filePath -Encoding ASCII -NoNewline
        
        return $filePath
    } catch {
        Write-Host "Warning: Could not write IP file: $_" -ForegroundColor Yellow
        return $null
    }
}

# Function to cleanup IP files
function Remove-IPFiles {
    param([string]$FilePath)
    
    try {
        if (Test-Path $FilePath) {
            $files = Get-ChildItem -Path $FilePath -File | Where-Object { 
                # Only remove files that look like IP addresses (contains dots and numbers)
                $_.Name -match '^\d+\.\d+\.\d+\.\d+$'
            }
            foreach ($file in $files) {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # Ignore cleanup errors
    }
}

# Function to display server startup info
function Show-ServerInfo {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Terminal Chat Server" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Server starting on port: $Port" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "  SERVER IP ADDRESS (share this!):" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "----------------------------------------" -ForegroundColor Gray
    $ips = Get-LocalIP
    if ($ips.Count -eq 0) {
        Write-Host "  Could not detect IP address" -ForegroundColor Red
        Write-Host "  Run 'ipconfig' in another terminal to find your IP" -ForegroundColor Gray
    } else {
        foreach ($ip in $ips) {
            Write-Host "  >>> $ip <<<" -ForegroundColor Yellow -BackgroundColor DarkGreen
        }
    }
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host ""
    
    # Write IP files
    $writtenFiles = @()
    foreach ($ip in $ips) {
        $filePath = Write-IPFile -IP $ip -Port $Port -FilePath $IPFilePath
        if ($filePath) {
            $writtenFiles += $filePath
        }
    }
    
    if ($writtenFiles.Count -gt 0) {
        Write-Host "IP address(es) written to:" -ForegroundColor Green
        foreach ($file in $writtenFiles) {
            Write-Host "  $file" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Client can auto-detect server IP from this location." -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Host "Share the IP address above with the client PC." -ForegroundColor Cyan
    Write-Host "Waiting for client connection..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Gray
    Write-Host ""
}

# Function to handle disconnect
function Handle-Disconnect {
    Write-Host ""
    Write-Host "Client disconnected." -ForegroundColor Yellow
    if ($script:stream) {
        try { $script:stream.Close() } catch {}
        $script:stream = $null
    }
    if ($script:client) {
        try { $script:client.Close() } catch {}
        $script:client = $null
    }
}

# Main server function
function Start-Server {
    Show-ServerInfo
    
    try {
        # Create TCP listener
        Write-Log "INFO" "Creating TCP listener" -Category "Server" -AdditionalData @{ "Port" = $Port }
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)
        $script:listener = New-Object System.Net.Sockets.TcpListener($endpoint)
        $script:listener.Start()
        
        Write-Host "Server is listening..." -ForegroundColor Green
        Write-Host ""
        Write-Log "INFO" "Server started and listening" -Category "Server" -AdditionalData @{ "Port" = $Port }
        
        # Accept client connection
        Write-Log "INFO" "Waiting for client connection" -Category "Server"
        $script:client = $script:listener.AcceptTcpClient()
        $script:stream = $script:client.GetStream()
        $script:stream.ReadTimeout = 500
        
        Write-LogConnection -Event "Client connected" -ConnectionInfo @{
            "ClientEndpoint" = $script:client.Client.RemoteEndPoint.ToString()
            "LocalEndpoint" = $script:client.Client.LocalEndPoint.ToString()
        }
        
        Clear-Host
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "   CLIENT CONNECTED!" -ForegroundColor Green
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
                                Write-Host "Client disconnected." -ForegroundColor Yellow
                                Write-LogConnection -Event "Client sent disconnect" -Details $line
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
                                Write-LogConnection -Event "Server disconnecting" -Details $input
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
                            Write-Host "Failed to send message." -ForegroundColor Red
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
        
    } catch {
        Write-Host "Server error: $_" -ForegroundColor Red
        Write-LogException -Exception $_ -Context "Start-Server function"
    } finally {
        Write-Log "INFO" "Server cleanup started" -Category "Cleanup"
        
        # Cleanup
        if ($script:stream) {
            try { 
                $script:stream.Close() 
                Write-Log "DEBUG" "Stream closed" -Category "Cleanup"
            } catch {
                Write-LogException -Exception $_ -Context "Closing stream in finally"
            }
        }
        if ($script:client) {
            try { 
                $script:client.Close() 
                Write-Log "DEBUG" "Client closed" -Category "Cleanup"
            } catch {
                Write-LogException -Exception $_ -Context "Closing client in finally"
            }
        }
        if ($script:listener) {
            try { 
                $script:listener.Stop() 
                Write-Log "DEBUG" "Listener stopped" -Category "Cleanup"
            } catch {
                Write-LogException -Exception $_ -Context "Stopping listener in finally"
            }
        }
        
        # Cleanup IP files
        try {
            Remove-IPFiles -FilePath $IPFilePath
            Write-Log "DEBUG" "IP files cleaned up" -Category "Cleanup"
        } catch {
            Write-LogException -Exception $_ -Context "Cleaning up IP files"
        }
        
        Write-Host ""
        Write-Host "Server stopped." -ForegroundColor Yellow
        Write-Log "INFO" "Server stopped" -Category "Shutdown"
    }
}

# Handle Ctrl+C gracefully
[Console]::TreatControlCAsInput = $false
$null = Register-ObjectEvent -InputObject ([System.Console]) -EventName "CancelKeyPress" -Action {
    $script:isRunning = $false
    Write-Host "`nShutting down server..." -ForegroundColor Yellow
    Write-Log "INFO" "Ctrl+C pressed - shutting down server" -Category "UserAction"
}

# Main execution with error handling
try {
    # Start the server
    Start-Server
} catch {
    Write-Host ""
    Write-Host "FATAL ERROR: Server crashed!" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Log file location: $(Get-LogFilePath)" -ForegroundColor Yellow
    
    Write-LogException -Exception $_ -Context "Main execution" -AdditionalData @{
        "Port" = $Port
        "IPFilePath" = $IPFilePath
    }
    Write-Log "FATAL" "Server crashed and is exiting" -Category "Crash"
    
    exit 1
}
