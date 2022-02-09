#Requires -version 7

<#
.SYNOPSIS
Cleanup worflow runs
.DESCRIPTION
Clean outdated workflowruns. Uses a json files which states the retention policy for each action and for specific branches if needed 
.PARAMETER Organization
The name of the organization where the repositories are defined in.
.PARAMETER Repository
The name of the Repository where the jobs needs cleaning.
.PARAMETER PAT
The personal access token. It must have "admin:org" scope to be authorized for the operation.
.EXAMPLE
.\cleanup-workflow-runs.ps1 -Organization EwoutdBoer -Repository 'Shop-Web-Gatsby' -PAT xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#>

param (
 [string] [Parameter(Mandatory=$true)] $Organization,
 [string] [Parameter(Mandatory=$true)] $Repository,
 [string] [Parameter(Mandatory=$true)] $PAT
)

function Reset-Countedvalues {
    #currentCountedValues
    foreach ($item in $currentCountedValues) {
        $item.Value = 0
    }
}

Write-Host "Start script"
Write-Host $Organization
Write-Host $Repository

$url = "https://api.github.com/repos/${Organization}/${Repository}/actions/runs"
Write-Host $url
$deleteUrl = "https://api.github.com/repos/${Organization}/${Repository}/actions/runs/"
Write-Host $deleteUrl

# ToDo: Set working folder
$workflowRetention = Get-Content -Raw -Path .\.github\workflows\workflow-retention.json | ConvertFrom-Json
# $workflowRetention = Get-Content -Raw -Path .\workflow-retention.json | ConvertFrom-Json
$retentionPolicies = $workflowRetention.actions;

$currentCountedValues = New-Object System.Collections.ArrayList
foreach ($action in $retentionPolicies)
{
    foreach ($branch in $action.branches)
    {
        # Create 2 objects one for sucess and one for failure
        $tempSuccess = New-Object System.Object
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Action" -Value $action.name
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Branch" -Value $branch.name
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Status" -Value "success"
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Value" -Value 0
        $currentCountedValues.Add($tempSuccess) | Out-Null

        $tempError = New-Object System.Object
        $tempError | Add-Member -MemberType NoteProperty -Name "Action" -Value $action.name
        $tempError | Add-Member -MemberType NoteProperty -Name "Branch" -Value $branch.name
        $tempError | Add-Member -MemberType NoteProperty -Name "Status" -Value "failure"
        $tempError | Add-Member -MemberType NoteProperty -Name "Value" -Value 0
        $currentCountedValues.Add($tempError) | Out-Null
    }
}

$headers = @{
    "Accept" = "application/vnd.github.v3+json"
    "Authorization" = "token $($PAT)"
}

$areItemsDeleted = $true
while ($areItemsDeleted) {  #Note when enabeling the while loop, reset all values first
    $areItemsDeleted = $false
    Reset-Countedvalues

    # ToDo: Split code to functions
    $jobs = Invoke-RestMethod -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck -Uri $url -Method Get -Headers $headers
    if ($StatusCode -eq 200) {
    Write-Host "> Success!" -ForegroundColor 'green'
        Write-Host $jobs
    } else {
        Write-Host "> Error!" -ForegroundColor 'red'
        Write-Host "> Status code: $($StatusCode)" -ForegroundColor 'red'
        Write-Host "> $($InvitationRequest | ConvertTo-Json)" -ForegroundColor 'red'
    }

    $runIdsToDelete = New-Object System.Collections.ArrayList

    foreach ($run in $jobs.workflow_runs) 
    {
        Write-Host 'Process run with id:' $run.id
        Write-Host 'Name: ' + $run.name
        Write-Host 'Status: ' + $run.status
        Write-Host 'Concusion': $run.conclusion

        if($run.status -ne 'completed') {
            continue # run is still ongoing, so skip it and don't count it
        }

        $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq $run.name -and $_.Branch -eq $run.head_branch -and $_.Status -eq $run.conclusion}  #.Where(_ => _.Action eq $run.name)
        if($correspondingValues.Count -eq 0) {
            $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq $run.name -and $_.Branch -eq '*' -and $_.Status -eq $run.conclusion}
        }

        if($correspondingValues.Count -eq 0) {
            continue
        }
        $correspondingValue = $correspondingValues  # There should be only a single result, so not needed to get the first here
        $correspondingValue.Value++ # Value found so add an occurence

        $correspondingPolicies = $retentionPolicies | Where-Object {$_.name -eq $run.name}
        if($correspondingPolicies.Count -eq 0) {
            continue
        }
        $correspondingPolicy = $correspondingPolicies[0]
        $correspondingPolicyValues = $correspondingPolicy.branches | Where-Object {$_.name -eq $run.head_branch}
        if($correspondingPolicyValues.Count -eq 0) {
            $correspondingPolicyValues = $correspondingPolicy.branches | Where-Object {$_.name -eq '*'}
            if($correspondingPolicyValues.Count -eq 0) {
                continue
            }
        }
        $correspondingPolicyValue = $correspondingPolicyValues[0]

        $policyValue = 0
        if($run.conclusion -eq 'success') {
            $policyValue = $correspondingPolicyValue.success
        }
        else {
            $policyValue = $correspondingPolicyValue.error
        }

        if($correspondingValue.Value -gt $policyValue) {
            $runIdsToDelete.Add($run.id)
        }
    }

    foreach ($idToDelete in $runIdsToDelete) {
        Write-Host 'Start Deletion of run id: ' + $idToDelete
        $completeDeleurl = $deleteUrl + $idToDelete
        Invoke-RestMethod -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck -Uri $completeDeleurl -Method Delete -Headers $headers
        if ($StatusCode -eq 204) {
            Write-Host "> Success! Deleted Run id: " + $idToDelete -ForegroundColor 'green'
            $areItemsDeleted = $true # deleted at least a single item, so do another run, see while loop
        } else {
            Write-Host "> Error!" -ForegroundColor 'red'
            Write-Host "> Status code: $($StatusCode)" -ForegroundColor 'red'
            Write-Host "> $($InvitationRequest | ConvertTo-Json)" -ForegroundColor 'red'
        }
    }
}