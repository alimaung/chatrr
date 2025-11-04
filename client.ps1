# Terminal Chat Client
# TCP Socket Client for Local Network Chat

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "",
    
    [int]$Port = 12345
)

# Configuration
$script:isRunning = $true
$script:client = $null
$script:stream = $null

# Function to display client startup info
function Show-ClientInfo {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Terminal Chat Client" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Function to get server IP if not provided
function Get-ServerIP {
    if ([string]::IsNullOrWhiteSpace($ServerIP)) {
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

# Get server IP
$serverIP = Get-ServerIP

# Validate IP format (basic check)
if ([string]::IsNullOrWhiteSpace($serverIP)) {
    Write-Host "Server IP address is required." -ForegroundColor Red
    exit 1
}

# Optional: Prompt for port if needed
if ($Port -eq 12345) {
    Write-Host "Enter port number (default: 12345, press Enter to use default):" -ForegroundColor Yellow
    $portInput = Read-Host
    if (-not [string]::IsNullOrWhiteSpace($portInput)) {
        if ([int]::TryParse($portInput, [ref]$Port)) {
            # Port parsed successfully
        } else {
            Write-Host "Invalid port, using default 12345" -ForegroundColor Yellow
            $Port = 12345
        }
    }
}

Write-Host ""

# Connect to server
if (Connect-ToServer -IP $serverIP -Port $Port) {
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
