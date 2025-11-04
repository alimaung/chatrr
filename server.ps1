# Terminal Chat Server
# TCP Socket Server for Local Network Chat

param(
    [int]$Port = 12345,
    [string]$IPFilePath = "$env:TEMP\chatrr"
)

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
        $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, $Port)
        $script:listener = New-Object System.Net.Sockets.TcpListener($endpoint)
        $script:listener.Start()
        
        Write-Host "Server is listening..." -ForegroundColor Green
        Write-Host ""
        
        # Accept client connection
        $script:client = $script:listener.AcceptTcpClient()
        $script:stream = $script:client.GetStream()
        $script:stream.ReadTimeout = 500
        
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
                                Write-Host "Client disconnected." -ForegroundColor Yellow
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
                            Write-Host "Client disconnected." -ForegroundColor Yellow
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
            
            # Read user input (this will block, but that's okay)
            # We check for received messages above before reading
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
                    } catch {}
                    break
                }
                
                # Send message
                try {
                    $writer.WriteLine($input)
                    Write-Host "You: $input" -ForegroundColor Cyan
                } catch {
                    Write-Host "Failed to send message." -ForegroundColor Red
                    break
                }
            } catch {
                # Input error (Ctrl+C handled separately)
                break
            }
            
            # Brief pause to allow receive thread to process
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
        
    } catch {
        Write-Host "Server error: $_" -ForegroundColor Red
    } finally {
        # Cleanup
        if ($script:stream) {
            try { $script:stream.Close() } catch {}
        }
        if ($script:client) {
            try { $script:client.Close() } catch {}
        }
        if ($script:listener) {
            try { $script:listener.Stop() } catch {}
        }
        
        # Cleanup IP files
        Remove-IPFiles -FilePath $IPFilePath
        
        Write-Host ""
        Write-Host "Server stopped." -ForegroundColor Yellow
    }
}

# Handle Ctrl+C gracefully
[Console]::TreatControlCAsInput = $false
$null = Register-ObjectEvent -InputObject ([System.Console]) -EventName "CancelKeyPress" -Action {
    $script:isRunning = $false
    Write-Host "`nShutting down server..." -ForegroundColor Yellow
}

# Start the server
Start-Server
