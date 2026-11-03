param(
    [switch]$System1Only,
    [switch]$System2Only
)

$ErrorActionPreference = "Stop"
if ($System1Only -and $System2Only) {
    throw "Choose at most one of -System1Only or -System2Only."
}

$workspaceRoot = $PSScriptRoot
$envFile = Join-Path $workspaceRoot ".env"
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Missing .env at $envFile"
}

foreach ($rawLine in Get-Content -LiteralPath $envFile) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        continue
    }

    if ($line -match "^(ANTHROPIC_API_KEY|ANTHROPIC_BASE_URL)\s*=\s*(.*)$") {
        $name = $Matches[1]
        $value = $Matches[2].Trim()
        if (
            $value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        Set-Item -Path "Env:$name" -Value $value
    }
}

if (-not $env:ANTHROPIC_API_KEY -or -not $env:ANTHROPIC_BASE_URL) {
    throw ".env must define non-empty ANTHROPIC_API_KEY and ANTHROPIC_BASE_URL values."
}

function Invoke-SystemRun {
    param(
        [string]$ProjectPath,
        [string]$EvidencePath,
        [string[]]$Arguments,
        [string]$LogName
    )

    $venvPath = Join-Path $ProjectPath ".venv"
    $venvItem = Get-Item -LiteralPath $venvPath
    if ($venvItem.LinkType -eq "Junction") {
        $venvPath = $venvItem.Target[0]
    }
    $python = Join-Path $venvPath "Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $python)) {
        throw "Missing project virtual environment: $python"
    }

    $previousPythonIoEncoding = $env:PYTHONIOENCODING
    $env:PYTHONIOENCODING = "utf-8"
    Push-Location $ProjectPath
    try {
        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $process = Start-Process `
                -FilePath $python `
                -ArgumentList $Arguments `
                -WorkingDirectory $ProjectPath `
                -NoNewWindow `
                -Wait `
                -PassThru `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath

            $stdout = [System.IO.File]::ReadAllText($stdoutPath)
            $stderr = [System.IO.File]::ReadAllText($stderrPath)
            $safeOutput = ($stdout + $stderr).Replace($env:ANTHROPIC_API_KEY, "[REDACTED]")
            $logPath = Join-Path $EvidencePath $LogName
            [System.IO.File]::WriteAllText($logPath, $safeOutput)
            if ($safeOutput) {
                Write-Output $safeOutput
            }

            if ($process.ExitCode -ne 0) {
                throw "Command failed for $ProjectPath with exit code $($process.ExitCode). See $logPath"
            }
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }

        $latestRun = Get-ChildItem -LiteralPath (Join-Path $ProjectPath "runs") -Directory |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if (-not $latestRun) {
            throw "No run directory was produced under $ProjectPath\runs"
        }

        $artifactParent = Join-Path $EvidencePath "run-artifacts"
        New-Item -ItemType Directory -Force -Path $artifactParent | Out-Null
        Copy-Item -LiteralPath $latestRun.FullName -Destination (Join-Path $artifactParent $latestRun.Name) -Recurse
        Write-Output "Captured run ID: $($latestRun.Name)"
    }
    finally {
        Pop-Location
        if ($null -eq $previousPythonIoEncoding) {
            Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
        }
        else {
            $env:PYTHONIOENCODING = $previousPythonIoEncoding
        }
    }
}

$claimsPath = Join-Path $workspaceRoot "Build a Claims Intake Agent with a stop_reason-Driven Loop\exercises\03-dynamic-decomposition\solution"
$contextPath = Join-Path $workspaceRoot "Engineer a Long-Conversation Context Strategy for a Retail Support Copilot\04-assemble-and-locate\solution"

if (-not $System2Only) {
    Invoke-SystemRun `
        -ProjectPath $claimsPath `
        -EvidencePath (Join-Path $workspaceRoot "submission\system1") `
        -Arguments @("-m", "claims_intake.run", "--all") `
        -LogName "run.log"
}

if (-not $System1Only) {
    Invoke-SystemRun `
        -ProjectPath $contextPath `
        -EvidencePath (Join-Path $workspaceRoot "submission\system2") `
        -Arguments @("-m", "retail_context.run", "--all") `
        -LogName "run.log"

    Push-Location $contextPath
    try {
        $venvPath = Join-Path $contextPath ".venv"
        $venvItem = Get-Item -LiteralPath $venvPath
        if ($venvItem.LinkType -eq "Junction") {
            $venvPath = $venvItem.Target[0]
        }
        $python = Join-Path $venvPath "Scripts\python.exe"
        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()
        try {
            $process = Start-Process `
                -FilePath $python `
                -ArgumentList @("-m", "pytest", "tests/", "-v") `
                -WorkingDirectory $contextPath `
                -NoNewWindow `
                -Wait `
                -PassThru `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath
            $stdout = [System.IO.File]::ReadAllText($stdoutPath)
            $stderr = [System.IO.File]::ReadAllText($stderrPath)
            $testOutput = ($stdout + $stderr).Replace($env:ANTHROPIC_API_KEY, "[REDACTED]")
            $testLog = Join-Path $workspaceRoot "submission\system2\tests.log"
            [System.IO.File]::WriteAllText($testLog, $testOutput)
            if ($testOutput) {
                Write-Output $testOutput
            }
            if ($process.ExitCode -ne 0) {
                throw "System 2 post-run tests failed with exit code $($process.ExitCode). See $testLog"
            }
        }
        finally {
            Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        Pop-Location
    }
}
