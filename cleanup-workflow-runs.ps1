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
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "ActorLogin" -Value $action.actorLogin
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Status" -Value "success"
        $tempSuccess | Add-Member -MemberType NoteProperty -Name "Value" -Value 0
        $currentCountedValues.Add($tempSuccess) | Out-Null

        $tempError = New-Object System.Object
        $tempError | Add-Member -MemberType NoteProperty -Name "Action" -Value $action.name
        $tempError | Add-Member -MemberType NoteProperty -Name "Branch" -Value $branch.name
        $tempError | Add-Member -MemberType NoteProperty -Name "ActorLogin" -Value $action.actorLogin
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
        Write-Host ''
        Write-Host 'Process run with id:' $run.id
        Write-Host 'Name: ' $run.name
        Write-Host 'Status: ' $run.status
        Write-Host 'Conclusion': $run.conclusion

        $runConclusionToUse = $run.conclusion
        if($runConclusionToUse -ne 'success') {
            $runConclusionToUse = 'failure'
        }

        if($run.status -ne 'completed') {
            Write-Host 'status is not completed yet => skip this run': $run.status
            continue # run is still ongoing, so skip it and don't count it
        }
        
        # Delete cancelled runs by default
        if($run.conclusion -eq 'cancelled') {
            Write-Host 'concusion is cancelled => Mark for deletion': $run.id
            $runIdsToDelete.Add($run.id)  # run was cancelled delete all cancelled runs by default
            continue
        }

        # Delete skipped runs by default
        if($run.conclusion -eq 'skipped') {
            Write-Host 'concusion is skipped => Mark for deletion': $run.id
            $runIdsToDelete.Add($run.id)  # run was cancelled delete all cancelled runs by default
            continue
        }

        # Check run name and branch
        $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq $run.name -and $_.Branch -eq $run.head_branch -and $_.Status -eq $runConclusionToUse}  #.Where(_ => _.Action eq $run.name)
        
        # Check run name * and branch and actorLogin
        if($correspondingValues.Count -eq 0) {
            $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq '*' -and $_.ActorLogin -eq $run.actor.login -and $_.Branch -eq $run.head_branch -and $_.Status -eq $runConclusionToUse}
        }

        # Check run name * and branch * and actorLogin
        if($correspondingValues.Count -eq 0) {
            $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq '*' -and $_.ActorLogin -eq $run.actor.login -and $_.Branch -eq '*' -and $_.Status -eq $runConclusionToUse}
        }

        # Check the Name and branch *
        if($correspondingValues.Count -eq 0) {
            $correspondingValues = $currentCountedValues | Where-Object {$_.Action -eq $run.name -and $_.Branch -eq '*' -and $_.Status -eq $runConclusionToUse}
        }

        if($correspondingValues.Count -eq 0) {
            Write-Host "No value set up in workflow-retention => Item is skipped. Run name: $($run.name), Branch: $($run.head_branch), Status: $($run.conclusion)"
            continue
        }

        $correspondingValue = $correspondingValues  # There should be only a single result, so not needed to get the first here
        $correspondingValue.Value++ # Value found so add an occurence

        $correspondingPolicies = $retentionPolicies | Where-Object {$_.name -eq $run.name}
        if($correspondingPolicies.Count -eq 0) {
            if($_.name -eq '*' -and $_.actorLogin -eq $run.actor.login) {
                $correspondingPolicies = $retentionPolicies | Where-Object {$_.name -eq $run.name}
            }
            $correspondingPolicies = $retentionPolicies | Where-Object {$_.name -eq '*' -and $_.actorLogin -eq $run.actor.login}

            if($correspondingPolicies.Count -eq 0) {
                Write-Host "No policy set up in workflow-retention => Item is skipped. Run name: $($run.name), Branch: $($run.head_branch), Status: $($run.conclusion)"
                continue
            }
        }
        $correspondingPolicy = $correspondingPolicies[0]
        $correspondingPolicyValues = $correspondingPolicy.branches | Where-Object {$_.name -eq $run.head_branch}
        if($correspondingPolicyValues.Count -eq 0) {
            $correspondingPolicyValues = $correspondingPolicy.branches | Where-Object {$_.name -eq '*'}
            if($correspondingPolicyValues.Count -eq 0) {
                Write-Host "No policy value set up for branch * in workflow-retention => Item is skipped. Run name: $($run.name), Branch: $($run.head_branch), Status: $($run.conclusion)"
                continue
            }
        }
        $correspondingPolicyValue = $correspondingPolicyValues[0]

        $policyValue = 0
        if($runConclusionToUse -eq 'success') {
            $policyValue = $correspondingPolicyValue.success
        }
        else {
            $policyValue = $correspondingPolicyValue.failure
        }

        # Check if the policy is set to delete failure runs when followed by success runs, then remove all failed items. This works while the newest is always processed first
        if($correspondingPolicy.deleteFailureRunsWhenFollowedBySuccess -eq $true -and $correspondingPolicyValue.success -gt 0 -and $runConclusionToUse -ne 'success')
        {
            Write-Host "deleteFailureRunsWhenFollowedBySuccess is set to true, number of success runs is greater than 0, value = $($correspondingPolicyValues.success) => Mark for deletion"
            $runIdsToDelete.Add($run.id)
            continue
        }

        if($correspondingValue.Value -gt $policyValue) {
            Write-Host "Value: $($correspondingValue.Value) is greater than policy value : $policyValue, for policy: $($correspondingPolicyValue.name) => Mark for deletion"
            $runIdsToDelete.Add($run.id)
        }
        else
        {
            Write-Host "Value: $($correspondingValue.Value) is less than or equal to policy value : $policyValue, for policy: $($correspondingPolicyValue.name) => Keep"
        }
    }

    Write-Host ''
    
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
