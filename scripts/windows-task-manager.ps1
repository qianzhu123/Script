[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $true)]
    [string]$ResultPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-JsonResult {
    param([Parameter(Mandatory = $true)]$Value)

    $json = $Value | ConvertTo-Json -Depth 8 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ResultPath, $json, $utf8)
}

function Write-ErrorResult {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Message,
        $Details = $null
    )

    $errorValue = @{ code = $Code; message = $Message }
    if ($null -ne $Details) {
        $errorValue.details = $Details
    }
    Write-JsonResult @{ ok = $false; error = $errorValue }
}

function Get-RequiredProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Missing request property: $Name"
    }
    return $property.Value
}

function Assert-TaskName {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    if ($TaskName -notmatch '^ScriptStudio-[a-f0-9]{16}$') {
        throw 'Invalid Script Studio task name.'
    }
}

function Test-AccessDenied {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.UnauthorizedAccessException]) {
            return $true
        }
        if (($exception -is [System.ComponentModel.Win32Exception]) -and ($exception.NativeErrorCode -eq 5)) {
            return $true
        }
        if ((([int64]$exception.HResult) -band 0xffff) -eq 5) {
            return $true
        }
        $exception = $exception.InnerException
    }
    return $false
}

function Convert-DateToIsoString {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    $date = [datetime]$Value
    if ($date -eq [datetime]::MinValue) {
        return $null
    }
    return $date.ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Convert-SecondsToDuration {
    param([Parameter(Mandatory = $true)][int]$Seconds)

    return [System.Xml.XmlConvert]::ToString([TimeSpan]::FromSeconds($Seconds))
}

function Get-RootTasks {
    return @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop)
}

function Find-Task {
    param(
        [Parameter(Mandatory = $true)][object[]]$Tasks,
        [Parameter(Mandatory = $true)][string]$TaskName
    )

    foreach ($task in $Tasks) {
        if ([string]::Equals([string]$task.TaskName, $TaskName, [System.StringComparison]::Ordinal)) {
            return $task
        }
    }
    return $null
}

function New-MissingTaskStatus {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    return [ordered]@{
        taskName = $TaskName
        exists = $false
        enabled = $false
        state = $null
        lastRunTime = $null
        lastTaskResult = $null
        nextRunTime = $null
        requiresElevation = $false
        principalUserId = $null
        principalLogonType = $null
        principalRunLevel = $null
    }
}

function Get-TaskStatus {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        $Task = $null
    )

    if ($null -eq $Task) {
        return New-MissingTaskStatus $TaskName
    }

    $info = Get-ScheduledTaskInfo -InputObject $Task -ErrorAction Stop
    $principalUserId = [string]$Task.Principal.UserId
    $principalLogonType = [string]$Task.Principal.LogonType
    $principalRunLevel = [string]$Task.Principal.RunLevel
    $requiresElevation = (
        $principalRunLevel -eq 'Highest' -or
        $principalLogonType -eq 'ServiceAccount' -or
        $principalUserId -eq 'SYSTEM' -or
        $principalUserId -eq 'S-1-5-18'
    )

    return [ordered]@{
        taskName = $TaskName
        exists = $true
        enabled = [bool]$Task.Settings.Enabled
        state = [string]$Task.State
        lastRunTime = Convert-DateToIsoString $info.LastRunTime
        lastTaskResult = [long]$info.LastTaskResult
        nextRunTime = Convert-DateToIsoString $info.NextRunTime
        requiresElevation = [bool]$requiresElevation
        principalUserId = $principalUserId
        principalLogonType = $principalLogonType
        principalRunLevel = $principalRunLevel
    }
}

function Get-TaskOrExit {
    param([Parameter(Mandatory = $true)][string]$TaskName)

    $task = Find-Task (Get-RootTasks) $TaskName
    if ($null -eq $task) {
        Write-ErrorResult 'TASK_NOT_FOUND' 'The scheduled task does not exist.'
        exit 2
    }
    return $task
}

try {
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
        throw 'The request file does not exist.'
    }

    Import-Module ScheduledTasks -ErrorAction Stop
    $requestText = [System.IO.File]::ReadAllText($RequestPath)
    $request = $requestText | ConvertFrom-Json
    $operation = [string](Get-RequiredProperty $request 'operation')

    switch ($operation) {
        'list' {
            $rootTasks = Get-RootTasks
            $statuses = @()
            $taskNamesProperty = $request.PSObject.Properties['taskNames']
            if (($null -ne $taskNamesProperty) -and (@($taskNamesProperty.Value).Count -gt 0)) {
                foreach ($taskNameValue in @($taskNamesProperty.Value)) {
                    $taskName = [string]$taskNameValue
                    Assert-TaskName $taskName
                    $statuses += ,(Get-TaskStatus $taskName (Find-Task $rootTasks $taskName))
                }
            } else {
                foreach ($task in $rootTasks) {
                    $taskName = [string]$task.TaskName
                    if ($taskName -match '^ScriptStudio-[a-f0-9]{16}$') {
                        $statuses += ,(Get-TaskStatus $taskName $task)
                    }
                }
            }
            Write-JsonResult @{ ok = $true; operation = $operation; tasks = @($statuses) }
            exit 0
        }

        'get' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        'upsert' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $nodePath = [string](Get-RequiredProperty $request 'nodePath')
            $actionArguments = [string](Get-RequiredProperty $request 'actionArguments')
            $workingDirectory = [string](Get-RequiredProperty $request 'workingDirectory')
            $settings = Get-RequiredProperty $request 'settings'
            $triggerType = [string](Get-RequiredProperty $settings 'trigger')
            $delayValue = Get-RequiredProperty $settings 'delaySeconds'
            $runElevatedValue = Get-RequiredProperty $settings 'runElevated'
            $restartValue = Get-RequiredProperty $settings 'restartOnFailure'
            $enabledValue = Get-RequiredProperty $settings 'enabled'

            if (($triggerType -ne 'logon') -and ($triggerType -ne 'startup')) {
                throw 'Invalid trigger type.'
            }
            if (($delayValue -isnot [int]) -and ($delayValue -isnot [long])) {
                throw 'delaySeconds must be an integer.'
            }
            $delaySeconds = [int]$delayValue
            if (($delaySeconds -lt 0) -or ($delaySeconds -gt 3600)) {
                throw 'delaySeconds is outside the allowed range.'
            }
            if (($runElevatedValue -isnot [bool]) -or ($restartValue -isnot [bool]) -or ($enabledValue -isnot [bool])) {
                throw 'Boolean task settings are invalid.'
            }
            if (-not [System.IO.Path]::IsPathRooted($nodePath)) {
                throw 'nodePath must be absolute.'
            }
            if (-not [System.IO.Path]::IsPathRooted($workingDirectory)) {
                throw 'workingDirectory must be absolute.'
            }
            if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
                throw 'nodePath does not exist.'
            }
            if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                throw 'workingDirectory does not exist.'
            }

            $action = New-ScheduledTaskAction -Execute $nodePath -Argument $actionArguments -WorkingDirectory $workingDirectory
            if ($triggerType -eq 'startup') {
                $trigger = New-ScheduledTaskTrigger -AtStartup
                $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            } else {
                $userId = [string](Get-RequiredProperty $request 'userId')
                if ([string]::IsNullOrWhiteSpace($userId)) {
                    throw 'userId is required for a logon trigger.'
                }
                $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
                $runLevel = 'Limited'
                if ([bool]$runElevatedValue) {
                    $runLevel = 'Highest'
                }
                $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel $runLevel
            }
            if ($delaySeconds -gt 0) {
                $trigger.Delay = Convert-SecondsToDuration $delaySeconds
            }

            $settingsParameters = @{
                AllowStartIfOnBatteries = $true
                DontStopIfGoingOnBatteries = $true
                ExecutionTimeLimit = [TimeSpan]::Zero
                MultipleInstances = 'IgnoreNew'
            }
            if ([bool]$restartValue) {
                $settingsParameters.RestartCount = 3
                $settingsParameters.RestartInterval = [TimeSpan]::FromMinutes(1)
            }
            if (-not [bool]$enabledValue) {
                $settingsParameters.Disable = $true
            }
            $taskSettings = New-ScheduledTaskSettingsSet @settingsParameters
            $definition = New-ScheduledTask `
                -Action $action `
                -Trigger $trigger `
                -Principal $principal `
                -Settings $taskSettings `
                -Description 'Script Studio autostart task.'

            Register-ScheduledTask -TaskName $taskName -TaskPath '\' -InputObject $definition -Force | Out-Null
            if ([bool]$enabledValue) {
                Enable-ScheduledTask -TaskName $taskName -TaskPath '\' | Out-Null
            } else {
                Disable-ScheduledTask -TaskName $taskName -TaskPath '\' | Out-Null
            }
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        'remove' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Find-Task (Get-RootTasks) $taskName
            if ($null -eq $task) {
                Write-JsonResult @{
                    ok = $true
                    operation = $operation
                    removed = $false
                    task = (New-MissingTaskStatus $taskName)
                }
                exit 0
            }
            Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false
            Write-JsonResult @{
                ok = $true
                operation = $operation
                removed = $true
                task = (New-MissingTaskStatus $taskName)
            }
            exit 0
        }

        'enable' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Get-TaskOrExit $taskName
            Enable-ScheduledTask -InputObject $task | Out-Null
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        'disable' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Get-TaskOrExit $taskName
            Disable-ScheduledTask -InputObject $task | Out-Null
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        'run' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Get-TaskOrExit $taskName
            Start-ScheduledTask -InputObject $task
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        'stop' {
            $taskName = [string](Get-RequiredProperty $request 'taskName')
            Assert-TaskName $taskName
            $task = Get-TaskOrExit $taskName
            Stop-ScheduledTask -InputObject $task
            $task = Find-Task (Get-RootTasks) $taskName
            Write-JsonResult @{ ok = $true; operation = $operation; task = (Get-TaskStatus $taskName $task) }
            exit 0
        }

        default {
            Write-ErrorResult 'INVALID_OPERATION' 'The requested scheduled task operation is not supported.'
            exit 2
        }
    }
} catch {
    $code = 'TASK_OPERATION_FAILED'
    $message = 'The scheduled task operation failed.'
    if (Test-AccessDenied $_) {
        $code = 'ADMIN_REQUIRED'
        $message = 'Administrator approval is required for this scheduled task operation.'
    }
    $details = @{
        errorId = [string]$_.FullyQualifiedErrorId
        exceptionType = [string]$_.Exception.GetType().FullName
        hresult = [long]$_.Exception.HResult
        nativeMessage = [string]$_.Exception.Message
    }
    Write-ErrorResult $code $message $details
    exit 1
}
