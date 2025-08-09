#Requires -RunAsAdministrator

<#
.SYNOPSIS
    PowerShell Driver Update Web Server - Fixed Version

.DESCRIPTION
    HTTP server that provides REST API endpoints for the driver update web interface.
    Fixed response handling and race condition issues.

.PARAMETER Port
    Port number for the web server (default: 8080)

.PARAMETER WebRoot
    Path to web files directory (default: current directory)

.EXAMPLE
    .\DriverUpdateServer.ps1 -Port 8080
#>

param(
    [int]$Port = 8080,
    [string]$WebRoot = $PSScriptRoot,
    [switch]$AutoOpen
)

# Global variables for session management
$Global:Sessions = @{}
$Global:Server = $null

function Write-ServerLog {
    param($Message, $Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

function Test-ResponseValid {
    param($Response)
    
    if (-not $Response) {
        Write-ServerLog "Response object is null" "ERROR"
        return $false
    }
    
    try {
        # Check if response is already sent/closed
        if ($Response.OutputStream -eq $null) {
            Write-ServerLog "Response OutputStream is null" "ERROR"
            return $false
        }
        
        # Check if we can write to the stream
        if (-not $Response.OutputStream.CanWrite) {
            Write-ServerLog "Response OutputStream is not writable" "ERROR"
            return $false
        }
        
        return $true
    }
    catch {
        Write-ServerLog "Error checking response validity: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Start-DriverUpdateServer {
    param($Port, $WebRoot)
    
    try {
        # Create HTTP listener
        $Global:Server = New-Object System.Net.HttpListener
        $Global:Server.Prefixes.Add("http://localhost:$Port/")
        $Global:Server.Prefixes.Add("http://127.0.0.1:$Port/")
        
        $Global:Server.Start()
        
        Write-ServerLog "Driver Update Web Server started successfully" "SUCCESS"
        Write-ServerLog "Server URL: http://localhost:$Port" "INFO"
        Write-ServerLog "Web Root: $WebRoot" "INFO"
        Write-ServerLog "Press Ctrl+C to stop the server" "INFO"
        
        # Auto-open browser if requested
        if ($AutoOpen) {
            Start-Process "http://localhost:$Port"
        }
        
        # Main server loop
        while ($Global:Server.IsListening) {
            try {
                # Wait for incoming request
                $context = $Global:Server.GetContext()
                $request = $context.Request
                $response = $context.Response
                
                # Process request
                Process-HttpRequest -Context $context -Request $request -Response $response -WebRoot $WebRoot
                
            }
            catch [System.Net.HttpListenerException] {
                if ($_.Exception.ErrorCode -eq 995) {
                    # Server was stopped
                    break
                }
                Write-ServerLog "HTTP Listener error: $($_.Exception.Message)" "ERROR"
            }
            catch {
                Write-ServerLog "Server error: $($_.Exception.Message)" "ERROR"
            }
        }
    }
    catch {
        Write-ServerLog "Failed to start server: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Process-HttpRequest {
    param($Context, $Request, $Response, $WebRoot)

    # Validate response object early
    if (-not (Test-ResponseValid -Response $Response)) {
        Write-ServerLog "Invalid or closed response object received" "ERROR"
        return
    }
    
    $url = $Request.Url.LocalPath.ToLower()
    $method = $Request.HttpMethod.ToUpper()
    
    Write-ServerLog "$method $url from $($Request.RemoteEndPoint)" "INFO"
    
    try {
        # Set CORS headers early
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        # Handle preflight requests
        if ($method -eq "OPTIONS") {
            $Response.StatusCode = 200
            $Response.Close()
            return
        }
        
        # Route requests
        switch -Regex ($url) {
            "^/api/system-info$" {
                Handle-SystemInfo -Response $Response
            }
            "^/api/driver-scan$" {
                Handle-DriverScan -Request $Request -Response $Response
            }
            "^/api/driver-update$" {
                Handle-DriverUpdate -Request $Request -Response $Response
            }
            "^/api/windows-update$" {
                Handle-WindowsUpdate -Request $Request -Response $Response
            }
            "^/api/status/(.+)$" {
                $sessionId = $Matches[1]
                Handle-StatusRequest -SessionId $sessionId -Response $Response
            }
            "^/api/cancel/(.+)$" {
                $sessionId = $Matches[1]
                Handle-CancelRequest -SessionId $sessionId -Response $Response
            }
            "^/$" {
                # Serve main page
                Serve-StaticFile -FilePath (Join-Path $WebRoot "index.html") -Response $Response
            }
            default {
                # Serve static files
                $filePath = Join-Path $WebRoot $url.TrimStart('/')
                if (Test-Path $filePath -PathType Leaf) {
                    Serve-StaticFile -FilePath $filePath -Response $Response
                } else {
                    Send-NotFound -Response $Response
                }
            }
        }
    }
    catch {
        Write-ServerLog "Error processing request: $($_.Exception.Message)" "ERROR"
        if (Test-ResponseValid -Response $Response) {
            Send-InternalServerError -Response $Response -Message $_.Exception.Message
        }
    }
}

function Handle-SystemInfo {
    param($Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    try {
        $computerInfo = Get-ComputerInfo -ErrorAction SilentlyContinue
        $systemInfo = @{
            computerName = $env:COMPUTERNAME
            operatingSystem = if ($computerInfo) { $computerInfo.WindowsProductName } else { "Windows" }
            version = if ($computerInfo) { $computerInfo.WindowsVersion } else { "Unknown" }
            totalRAM = if ($computerInfo) { [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2) } else { 0 }
            processor = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name
            lastBootTime = if ($computerInfo) { $computerInfo.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Unknown" }
            currentUser = $env:USERNAME
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
        }
        
        Send-JsonResponse -Response $Response -Data $systemInfo
    }
    catch {
        if (Test-ResponseValid -Response $Response) {
            Send-InternalServerError -Response $Response -Message $_.Exception.Message
        }
    }
}

function Handle-DriverScan {
    param($Request, $Response)
    
    # Validate response object first
    if (-not (Test-ResponseValid -Response $Response)) {
        Write-ServerLog "Response object invalid in Handle-DriverScan" "ERROR"
        return
    }
    
    $sessionId = [Guid]::NewGuid().ToString()
    
    try {
        # Get request body
        $requestBody = Get-RequestBody -Request $Request
        $settings = if ($requestBody) { 
            try { $requestBody | ConvertFrom-Json } 
            catch { @{} }
        } else { @{} }
        
        # Create session data BEFORE sending response
        $Global:Sessions[$sessionId] = @{
            Id = $sessionId
            Status = "Starting"
            Progress = 0
            StartTime = Get-Date
            Settings = $settings
            Results = @{}
            Logs = @()
            Job = $null
        }
        
        Write-ServerLog "Created session $sessionId for driver scan" "INFO"
        
        # Prepare immediate response
        $immediateResponse = @{
            sessionId = $sessionId
            status = "started"
            message = "Driver scan initiated"
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        # Send response immediately and ensure it's sent before continuing
        $success = Send-JsonResponse -Response $Response -Data $immediateResponse
        
        if (-not $success) {
            Write-ServerLog "Failed to send initial response for session $sessionId" "ERROR"
            # Clean up session if response failed
            $Global:Sessions.Remove($sessionId)
            return
        }
        
        Write-ServerLog "Sent initial response for session $sessionId, starting background job" "INFO"
        
        # Start background job AFTER successful response
        $job = Start-Job -ScriptBlock {
            param($Settings, $SessionId)
            
            try {
                $results = @{
                    devices = @()
                    windowsUpdates = @()
                    systemInfo = @{}
                    executionTime = 0
                    scanTime = Get-Date
                }
                
                # Simulate initial progress
                Start-Sleep -Seconds 1
                
                # Get device information
                $devices = Get-CimInstance -ClassName Win32_PnPEntity -Property Name,DeviceID,Manufacturer,Status,ConfigManagerErrorCode -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -and $_.Name -notlike "*Generic*" } |
                    ForEach-Object {
                        @{
                            name = $_.Name
                            deviceId = $_.DeviceID
                            manufacturer = $_.Manufacturer
                            status = $_.Status
                            errorCode = if ($_.ConfigManagerErrorCode) { $_.ConfigManagerErrorCode } else { 0 }
                            hasProblem = ($_.ConfigManagerErrorCode -gt 0)
                            needsUpdate = ($_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne $null)
                        }
                    }
                
                $results.devices = $devices
                $results.systemInfo = @{
                    totalDevices = $devices.Count
                    problemDevices = ($devices | Where-Object { $_.hasProblem }).Count
                    workingDevices = ($devices | Where-Object { !$_.hasProblem }).Count
                    scanCompleted = Get-Date
                }
                
                return @{
                    success = $true
                    results = $results
                    sessionId = $SessionId
                    completedAt = Get-Date
                }
            }
            catch {
                return @{
                    success = $false
                    error = $_.Exception.Message
                    sessionId = $SessionId
                    errorAt = Get-Date
                }
            }
        } -ArgumentList $settings, $sessionId
        
        # Update session with job and mark as running
        $Global:Sessions[$sessionId].Job = $job
        $Global:Sessions[$sessionId].Status = "Running"
        
        Write-ServerLog "Background job started for session $sessionId" "INFO"
        
    }
    catch {
        Write-ServerLog "Error in Handle-DriverScan: $($_.Exception.Message)" "ERROR"
        
        # Clean up session on error
        if ($Global:Sessions.ContainsKey($sessionId)) {
            $Global:Sessions.Remove($sessionId)
        }
        
        # Only try to send error response if we haven't already sent a response
        if (Test-ResponseValid -Response $Response) {
            try {
                $errorResponse = @{ 
                    error = $_.Exception.Message
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                Send-JsonResponse -Response $Response -Data $errorResponse -StatusCode 500
            }
            catch {
                Write-ServerLog "Could not send error response: $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Handle-DriverUpdate {
    param($Request, $Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    $sessionId = [Guid]::NewGuid().ToString()
    
    try {
        $requestBody = Get-RequestBody -Request $Request
        $settings = if ($requestBody) { 
            try { $requestBody | ConvertFrom-Json } 
            catch { @{} }
        } else { @{} }
        
        # Create session data BEFORE sending response
        $Global:Sessions[$sessionId] = @{
            Id = $sessionId
            Status = "Starting"
            Progress = 0
            StartTime = Get-Date
            Settings = $settings
            Results = @{}
            Logs = @()
            Job = $null
        }
        
        Write-ServerLog "Created session $sessionId for driver update" "INFO"
        
        # Prepare immediate response
        $immediateResponse = @{
            sessionId = $sessionId
            status = "started"
            message = "Driver update initiated"
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        # Send response immediately
        $success = Send-JsonResponse -Response $Response -Data $immediateResponse
        
        if (-not $success) {
            Write-ServerLog "Failed to send initial response for session $sessionId" "ERROR"
            $Global:Sessions.Remove($sessionId)
            return
        }
        
        Write-ServerLog "Sent initial response for session $sessionId, starting background job" "INFO"
        
        # Start driver update job AFTER successful response
        $job = Start-Job -ScriptBlock {
            param($Settings, $SessionId)
            
            try {
                $results = @{
                    devicesUpdated = @()
                    updateResults = @()
                    executionTime = 0
                }
                
                # Simulate driver update process
                Start-Sleep -Seconds 5
                
                # Return results
                return @{
                    success = $true
                    results = $results
                    sessionId = $SessionId
                }
            }
            catch {
                return @{
                    success = $false
                    error = $_.Exception.Message
                    sessionId = $SessionId
                }
            }
        } -ArgumentList $settings, $sessionId
        
        $Global:Sessions[$sessionId].Job = $job
        $Global:Sessions[$sessionId].Status = "Running"
        
        Write-ServerLog "Background job started for session $sessionId" "INFO"
    }
    catch {
        Write-ServerLog "Error in Handle-DriverUpdate: $($_.Exception.Message)" "ERROR"
        
        if ($Global:Sessions.ContainsKey($sessionId)) {
            $Global:Sessions.Remove($sessionId)
        }
        
        if (Test-ResponseValid -Response $Response) {
            try {
                $errorResponse = @{ 
                    error = $_.Exception.Message
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                Send-JsonResponse -Response $Response -Data $errorResponse -StatusCode 500
            }
            catch {
                Write-ServerLog "Could not send error response: $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Handle-WindowsUpdate {
    param($Request, $Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    $sessionId = [Guid]::NewGuid().ToString()
    
    try {
        $requestBody = Get-RequestBody -Request $Request
        $settings = if ($requestBody) { 
            try { $requestBody | ConvertFrom-Json } 
            catch { @{} }
        } else { @{} }
        
        # Create session data BEFORE sending response
        $Global:Sessions[$sessionId] = @{
            Id = $sessionId
            Status = "Starting"
            Progress = 0
            StartTime = Get-Date
            Settings = $settings
            Results = @{}
            Logs = @()
            Job = $null
        }
        
        Write-ServerLog "Created session $sessionId for Windows Update scan" "INFO"
        
        # Prepare immediate response
        $immediateResponse = @{
            sessionId = $sessionId
            status = "started"
            message = "Windows Update scan initiated"
            timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        # Send response immediately
        $success = Send-JsonResponse -Response $Response -Data $immediateResponse
        
        if (-not $success) {
            Write-ServerLog "Failed to send initial response for session $sessionId" "ERROR"
            $Global:Sessions.Remove($sessionId)
            return
        }
        
        Write-ServerLog "Sent initial response for session $sessionId, starting background job" "INFO"
        
        # Start Windows Update scan AFTER successful response
        $job = Start-Job -ScriptBlock {
            param($Settings, $SessionId)
            
            try {
                # Scan for Windows Updates
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $searchResult = $searcher.Search("IsInstalled=0 and Type='Driver'")
                
                $updates = @()
                foreach ($update in $searchResult.Updates) {
                    $updates += @{
                        title = $update.Title
                        description = $update.Description
                        sizeMB = [math]::Round($update.MaxDownloadSize / 1MB, 1)
                        isMandatory = $update.IsMandatory
                        updateId = $update.Identity.UpdateID
                        categories = ($update.Categories | ForEach-Object { $_.Name }) -join ", "
                    }
                }
                
                return @{
                    success = $true
                    results = @{
                        updates = $updates
                        totalCount = $updates.Count
                        totalSize = ($updates | Measure-Object -Property sizeMB -Sum).Sum
                    }
                    sessionId = $SessionId
                }
            }
            catch {
                return @{
                    success = $false
                    error = $_.Exception.Message
                    sessionId = $SessionId
                }
            }
        } -ArgumentList $settings, $sessionId
        
        $Global:Sessions[$sessionId].Job = $job
        $Global:Sessions[$sessionId].Status = "Running"
        
        Write-ServerLog "Background job started for session $sessionId" "INFO"
    }
    catch {
        Write-ServerLog "Error in Handle-WindowsUpdate: $($_.Exception.Message)" "ERROR"
        
        if ($Global:Sessions.ContainsKey($sessionId)) {
            $Global:Sessions.Remove($sessionId)
        }
        
        if (Test-ResponseValid -Response $Response) {
            try {
                $errorResponse = @{ 
                    error = $_.Exception.Message
                    sessionId = $sessionId
                    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }
                Send-JsonResponse -Response $Response -Data $errorResponse -StatusCode 500
            }
            catch {
                Write-ServerLog "Could not send error response: $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

function Handle-StatusRequest {
    param($SessionId, $Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    try {
        if (-not $Global:Sessions.ContainsKey($SessionId)) {
            Send-NotFound -Response $Response
            return
        }
        
        $session = $Global:Sessions[$SessionId]
        $job = $session.Job
        
        if ($job) {
            # Check job status
            if ($job.State -eq "Completed") {
                $results = Receive-Job -Job $job
                Remove-Job -Job $job
                
                $session.Status = "Completed"
                $session.Progress = 100
                $session.Results = $results.results
                $session.Job = $null
                
                if ($results.success) {
                    $session.Success = $true
                } else {
                    $session.Success = $false
                    $session.Error = $results.error
                }
            }
            elseif ($job.State -eq "Failed") {
                $session.Status = "Failed"
                $session.Success = $false
                $session.Error = "Job execution failed"
                Remove-Job -Job $job
                $session.Job = $null
            }
            else {
                # Job still running, estimate progress
                $elapsed = (Get-Date) - $session.StartTime
                $session.Progress = [math]::Min(90, $elapsed.TotalSeconds * 10)
            }
        }
        
        # Return status
        $status = @{
            sessionId = $SessionId
            status = $session.Status
            progress = $session.Progress
            startTime = $session.StartTime.ToString("yyyy-MM-dd HH:mm:ss")
            elapsedTime = [math]::Round(((Get-Date) - $session.StartTime).TotalSeconds, 2)
        }
        
        if ($session.Status -eq "Completed") {
            $status.results = $session.Results
            $status.success = $session.Success
            if ($session.Error) {
                $status.error = $session.Error
            }
        }
        
        Send-JsonResponse -Response $Response -Data $status
    }
    catch {
        if (Test-ResponseValid -Response $Response) {
            Send-InternalServerError -Response $Response -Message $_.Exception.Message
        }
    }
}

function Handle-CancelRequest {
    param($SessionId, $Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    try {
        if (-not $Global:Sessions.ContainsKey($SessionId)) {
            Send-NotFound -Response $Response
            return
        }
        
        $session = $Global:Sessions[$SessionId]
        
        if ($session.Job -and $session.Job.State -eq "Running") {
            Stop-Job -Job $session.Job
            Remove-Job -Job $session.Job
            $session.Status = "Cancelled"
            $session.Job = $null
        }
        
        $response = @{
            sessionId = $SessionId
            status = "cancelled"
            message = "Operation cancelled successfully"
        }
        
        Send-JsonResponse -Response $Response -Data $response
    }
    catch {
        if (Test-ResponseValid -Response $Response) {
            Send-InternalServerError -Response $Response -Message $_.Exception.Message
        }
    }
}

function Get-RequestBody {
    param($Request)
    
    try {
        $reader = New-Object System.IO.StreamReader($Request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Close()
        return $body
    }
    catch {
        Write-ServerLog "Error reading request body: $($_.Exception.Message)" "ERROR"
        return ""
    }
}

function Serve-StaticFile {
    param($FilePath, $Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    if (-not (Test-Path $FilePath)) {
        Send-NotFound -Response $Response
        return
    }
    
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $contentType = switch ($extension) {
        ".html" { "text/html; charset=utf-8" }
        ".css" { "text/css" }
        ".js" { "application/javascript" }
        ".json" { "application/json" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".gif" { "image/gif" }
        ".ico" { "image/x-icon" }
        default { "application/octet-stream" }
    }
    
    try {
        $content = [System.IO.File]::ReadAllBytes($FilePath)
        $Response.ContentType = $contentType
        $Response.ContentLength64 = $content.Length
        $Response.StatusCode = 200
        $Response.OutputStream.Write($content, 0, $content.Length)
        $Response.Close()
    }
    catch {
        Write-ServerLog "Error serving file ${FilePath}: $($_.Exception.Message)" "ERROR"
        if (Test-ResponseValid -Response $Response) {
            Send-InternalServerError -Response $Response -Message "Error serving file"
        }
    }
}

function Send-JsonResponse {
    param($Response, $Data, $StatusCode = 200)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return $false
    }
    
    try {
        $json = $Data | ConvertTo-Json -Depth 10
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        
        $Response.ContentType = "application/json; charset=utf-8"
        $Response.StatusCode = $StatusCode
        $Response.ContentLength64 = $buffer.Length
        
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.OutputStream.Flush()
        $Response.Close()
        
        return $true
        
    }
    catch {
        Write-ServerLog "Error in Send-JsonResponse: $($_.Exception.Message)" "ERROR"
        try {
            if ($Response -and $Response.OutputStream -ne $null) {
                $Response.Close()
            }
        }
        catch {
            # Ignore close errors
        }
        return $false
    }
}

function Send-NotFound {
    param($Response)
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    try {
        $Response.StatusCode = 404
        $message = "Resource not found"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.Close()
    }
    catch {
        Write-ServerLog "Error sending 404 response: $($_.Exception.Message)" "ERROR"
        if ($Response -and $Response.OutputStream) {
            try { $Response.Close() } catch { }
        }
    }
}

function Send-InternalServerError {
    param($Response, $Message = "Internal server error")
    
    if (-not (Test-ResponseValid -Response $Response)) {
        return
    }
    
    try {
        $Response.StatusCode = 500
        $error = @{ 
            error = $Message
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        } | ConvertTo-Json
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($error)
        $Response.ContentType = "application/json; charset=utf-8"
        $Response.ContentLength64 = $buffer.Length
        $Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $Response.Close()
    }
    catch {
        Write-ServerLog "Error sending 500 response: $($_.Exception.Message)" "ERROR"
        if ($Response -and $Response.OutputStream) {
            try { $Response.Close() } catch { }
        }
    }
}

function Stop-DriverUpdateServer {
    if ($Global:Server -and $Global:Server.IsListening) {
        Write-ServerLog "Stopping Driver Update Web Server..." "INFO"
        $Global:Server.Stop()
        $Global:Server.Close()
        
        # Clean up running jobs
        foreach ($session in $Global:Sessions.Values) {
            if ($session.Job -and $session.Job.State -eq "Running") {
                Stop-Job -Job $session.Job
                Remove-Job -Job $session.Job
            }
        }
        
        Write-ServerLog "Server stopped successfully" "SUCCESS"
    }
}

# Handle Ctrl+C gracefully
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-DriverUpdateServer
}

# Trap for handling termination
trap {
    Stop-DriverUpdateServer
    break
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        Write-Host "`nDRIVER UPDATE WEB SERVER - FIXED VERSION" -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Green
        
        # Check admin privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-ServerLog "WARNING: Not running as Administrator. Some functions may be limited." "WARN"
        }
        
        # Start the server
        Start-DriverUpdateServer -Port $Port -WebRoot $WebRoot
    }
    catch {
        Write-ServerLog "Failed to start server: $($_.Exception.Message)" "ERROR"
        exit 1
    }
    finally {
        Stop-DriverUpdateServer
    }
}