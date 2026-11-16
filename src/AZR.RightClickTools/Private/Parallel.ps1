function Invoke-AZRParallel {
    <#
    .SYNOPSIS
        Runs a script block once per target with throttled concurrency and returns one result object per target.
    .DESCRIPTION
        PS 5.1 compatible (runspace pool, no ForEach-Object -Parallel). The script block receives the target
        as its first parameter, followed by -ArgumentList. In parallel mode the AZR module is imported in every
        runspace, so exported AZR functions can be called; variables from the caller are NOT visible.
        With a throttle of 1 (or a single target) it runs serially in the caller's scope.
        Result: Target, Success, Output, Error, DurationMs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Target,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [ValidateRange(0, 64)][int]$ThrottleLimit = 0,
        [string]$ProgressActivity = 'AZR bulk run'
    )
    if ($ThrottleLimit -le 0) { $ThrottleLimit = (Get-AZRSettings).MaxParallel }
    $targets = @($Target)
    if ($targets.Count -eq 0) { return }

    $newResult = {
        param($t, $ok, $out, $err, $ms)
        [pscustomobject]@{ Target = $t; Success = $ok; Output = $out; Error = $err; DurationMs = $ms }
    }

    if ($ThrottleLimit -eq 1 -or $targets.Count -eq 1) {
        $i = 0
        foreach ($t in $targets) {
            $i++
            Write-Progress -Activity $ProgressActivity -Status "$t ($i of $($targets.Count))" -PercentComplete (100 * $i / $targets.Count)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $out = @(& $ScriptBlock $t @ArgumentList)
                & $newResult $t $true $out '' $sw.ElapsedMilliseconds
            }
            catch { & $newResult $t $false @() $_.Exception.Message $sw.ElapsedMilliseconds }
        }
        Write-Progress -Activity $ProgressActivity -Completed
        return
    }

    $iss = [initialsessionstate]::CreateDefault()
    # Runspaces start with their own execution policy; the module files must be loadable in every worker.
    if ($env:OS -eq 'Windows_NT') { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass }
    $moduleInfo = $ExecutionContext.SessionState.Module
    if ($moduleInfo) { $iss.ImportPSModule(@(Join-Path $moduleInfo.ModuleBase ($moduleInfo.Name + '.psd1'))) }
    $pool = [runspacefactory]::CreateRunspacePool(1, [math]::Min($ThrottleLimit, $targets.Count), $iss, $Host)
    $pool.Open()
    $jobs = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($t in $targets) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($ScriptBlock.ToString()).AddArgument($t)
            foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }
            $jobs.Add([pscustomobject]@{ Target = $t; Ps = $ps; Handle = $ps.BeginInvoke(); Sw = [System.Diagnostics.Stopwatch]::StartNew() })
        }
        $done = 0
        $reported = @{}
        while ($done -lt $jobs.Count) {
            foreach ($j in $jobs) {
                if (-not $reported.ContainsKey($j.Target) -and $j.Handle.IsCompleted) {
                    $reported[$j.Target] = $true
                    $done++
                    $ok = $true; $out = @(); $err = ''
                    try {
                        $out = @($j.Ps.EndInvoke($j.Handle))
                        if ($j.Ps.Streams.Error.Count -gt 0) { $ok = $false; $err = ($j.Ps.Streams.Error | ForEach-Object { $_.ToString() }) -join '; ' }
                    }
                    catch { $ok = $false; $err = $_.Exception.Message }
                    & $newResult $j.Target $ok $out $err $j.Sw.ElapsedMilliseconds
                }
            }
            Write-Progress -Activity $ProgressActivity -Status "$done of $($jobs.Count) finished" -PercentComplete (100 * $done / $jobs.Count)
            if ($done -lt $jobs.Count) { Start-Sleep -Milliseconds 100 }
        }
    }
    finally {
        # Also runs on Ctrl+C / window close: stop anything still running and release the pool.
        foreach ($j in $jobs) { try { if (-not $j.Handle.IsCompleted) { $j.Ps.Stop() } $j.Ps.Dispose() } catch { Write-Verbose "cleanup: $_" } }
        $pool.Close(); $pool.Dispose()
        Write-Progress -Activity $ProgressActivity -Completed
    }
}
