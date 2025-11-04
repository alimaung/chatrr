# Logging Module for Terminal Chat
# Provides logging functionality for debugging crashes and errors

# Configuration
$script:LogPath = "$env:TEMP\chatrr"
$script:LogFile = "chat.log"
$script:MaxLogSize = 1MB  # 1 MB max log size

# Function to initialize logging
function Initialize-Logger {
    param(
        [string]$LogDirectory = "$env:TEMP\chatrr",
        [string]$LogFileName = "chat.log"
    )
    
    $script:LogPath = $LogDirectory
    $script:LogFile = $LogFileName
    
    try {
        # Create log directory if it doesn't exist
        if (-not (Test-Path $script:LogPath)) {
            New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
        }
        
        $logFilePath = Join-Path $script:LogPath $script:LogFile
        
        # Rotate log if it's too large
        if (Test-Path $logFilePath) {
            $logSize = (Get-Item $logFilePath).Length
            if ($logSize -gt $script:MaxLogSize) {
                $backupFile = "$logFilePath.old"
                if (Test-Path $backupFile) {
                    Remove-Item $backupFile -Force
                }
                Move-Item $logFilePath $backupFile -Force
            }
        }
        
        # Write initial log entry
        Write-Log "INFO" "Logger initialized" -Category "System"
    } catch {
        Write-Host "Warning: Could not initialize logger: $_" -ForegroundColor Yellow
    }
}

# Function to write log entry
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [string]$Category = "General",
        [string]$Exception = "",
        [hashtable]$AdditionalData = @{}
    )
    
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logFilePath = Join-Path $script:LogPath $script:LogFile
        
        $logEntry = "$timestamp [$Level] [$Category] $Message"
        
        if ($Exception) {
            $logEntry += "`n  Exception: $Exception"
        }
        
        if ($AdditionalData.Count -gt 0) {
            $logEntry += "`n  Additional Data:"
            foreach ($key in $AdditionalData.Keys) {
                $logEntry += "`n    $key = $($AdditionalData[$key])"
            }
        }
        
        $logEntry += "`n"
        
        # Write to file
        Add-Content -Path $logFilePath -Value $logEntry -ErrorAction SilentlyContinue
        
        # Also write errors/warnings to console
        if ($Level -eq "ERROR" -or $Level -eq "FATAL") {
            Write-Host "[LOG ERROR] $Message" -ForegroundColor Red
            if ($Exception) {
                Write-Host "  Exception: $Exception" -ForegroundColor Red
            }
        } elseif ($Level -eq "WARN") {
            Write-Host "[LOG WARN] $Message" -ForegroundColor Yellow
        }
    } catch {
        # Can't log if logging fails - just show to console
        Write-Host "Logging error: $_" -ForegroundColor Red
    }
}

# Function to log exception with full stack trace
function Write-LogException {
    param(
        [Parameter(Mandatory=$true)]
        [Exception]$Exception,
        
        [string]$Context = "",
        [hashtable]$AdditionalData = @{}
    )
    
    $exceptionData = @{
        "Message" = $Exception.Message
        "Type" = $Exception.GetType().FullName
        "Stack Trace" = $Exception.StackTrace
    }
    
    if ($Exception.InnerException) {
        $exceptionData["Inner Exception"] = $Exception.InnerException.Message
    }
    
    if ($AdditionalData.Count -gt 0) {
        foreach ($key in $AdditionalData.Keys) {
            $exceptionData[$key] = $AdditionalData[$key]
        }
    }
    
    $message = if ($Context) { "Exception in $Context" } else { "Exception occurred" }
    
    Write-Log -Level "ERROR" -Message $message -Exception ($Exception | Out-String) -AdditionalData $exceptionData
}

# Function to log connection events
function Write-LogConnection {
    param(
        [string]$Event,
        [string]$Details = "",
        [hashtable]$ConnectionInfo = @{}
    )
    
    $data = @{
        "Event" = $Event
    }
    
    if ($Details) {
        $data["Details"] = $Details
    }
    
    if ($ConnectionInfo.Count -gt 0) {
        foreach ($key in $ConnectionInfo.Keys) {
            $data[$key] = $ConnectionInfo[$key]
        }
    }
    
    Write-Log -Level "INFO" -Message "Connection: $Event" -Category "Connection" -AdditionalData $data
}

# Function to get log file path
function Get-LogFilePath {
    return Join-Path $script:LogPath $script:LogFile
}

# Export functions
Export-ModuleMember -Function Initialize-Logger, Write-Log, Write-LogException, Write-LogConnection, Get-LogFilePath

