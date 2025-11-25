#Requires -version 7

<#
.SYNOPSIS
Sync organization issues to a GitHub Project
.DESCRIPTION
Gets all repositories in an organization, retrieves all open issues, and adds any issues
not linked to the specified project to that project with status 'Todo'.
.PARAMETER Organization
The name of the organization where the repositories are defined in.
.PARAMETER ProjectName
The name of the project to sync issues to. Defaults to 'General'.
.PARAMETER PAT
The personal access token. It must have "repo", "read:org", and "project" scopes to be authorized for the operation.
.EXAMPLE
.\sync-issues-to-project.ps1 -Organization EwoutdBoer -ProjectName 'General' -PAT xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#>

param (
    [string] [Parameter(Mandatory=$true)] $Organization,
    [string] [Parameter(Mandatory=$false)] $ProjectName = 'General',
    [string] [Parameter(Mandatory=$true)] $PAT
)

Write-Host "Start script - Sync Issues to Project"
Write-Host "Organization: $Organization"
Write-Host "Project Name: $ProjectName"

$headers = @{
    "Accept" = "application/vnd.github.v3+json"
    "Authorization" = "Bearer $PAT"
}

$graphqlHeaders = @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "Bearer $PAT"
    "Content-Type" = "application/json"
}

$graphqlUrl = "https://api.github.com/graphql"

# Function to execute GraphQL queries
function Invoke-GraphQL {
    param (
        [string] $Query,
        [hashtable] $Variables = @{}
    )
    
    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 10
    
    $response = Invoke-RestMethod -Uri $graphqlUrl -Method Post -Headers $graphqlHeaders -Body $body -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck
    
    if ($StatusCode -ne 200) {
        Write-Host "> GraphQL Error! Status code: $StatusCode" -ForegroundColor 'red'
        Write-Host "> $($response | ConvertTo-Json -Depth 10)" -ForegroundColor 'red'
        return $null
    }
    
    if ($response.errors) {
        Write-Host "> GraphQL Error!" -ForegroundColor 'red'
        foreach ($error in $response.errors) {
            Write-Host "> $($error.message)" -ForegroundColor 'red'
        }
        return $null
    }
    
    return $response.data
}

# Get organization project by name
function Get-OrganizationProject {
    param (
        [string] $OrgName,
        [string] $ProjName
    )
    
    $query = @"
query(`$orgName: String!, `$cursor: String) {
  organization(login: `$orgName) {
    projectsV2(first: 100, after: `$cursor) {
      nodes {
        id
        title
        number
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
}
"@
    
    $cursor = $null
    do {
        $variables = @{
            orgName = $OrgName
            cursor = $cursor
        }
        
        $data = Invoke-GraphQL -Query $query -Variables $variables
        if (-not $data) { return $null }
        
        $project = $data.organization.projectsV2.nodes | Where-Object { $_.title -eq $ProjName }
        if ($project) {
            return $project
        }
        
        $cursor = $data.organization.projectsV2.pageInfo.endCursor
    } while ($data.organization.projectsV2.pageInfo.hasNextPage)
    
    return $null
}

# Get all repositories in organization
function Get-OrganizationRepositories {
    param (
        [string] $OrgName
    )
    
    $repos = @()
    $page = 1
    $perPage = 100
    
    do {
        $url = "https://api.github.com/orgs/$OrgName/repos?page=$page&per_page=$perPage"
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck
        
        if ($StatusCode -ne 200) {
            Write-Host "> Error getting repositories! Status code: $StatusCode" -ForegroundColor 'red'
            Write-Host "> $($response | ConvertTo-Json)" -ForegroundColor 'red'
            return @()
        }
        
        $repos += $response
        $page++
    } while ($response.Count -eq $perPage)
    
    return $repos
}

# Get all open issues for a repository
function Get-RepositoryIssues {
    param (
        [string] $OrgName,
        [string] $RepoName
    )
    
    $issues = @()
    $page = 1
    $perPage = 100
    
    do {
        $url = "https://api.github.com/repos/$OrgName/$RepoName/issues?state=open&page=$page&per_page=$perPage"
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck
        
        if ($StatusCode -ne 200) {
            Write-Host "> Error getting issues for $RepoName! Status code: $StatusCode" -ForegroundColor 'red'
            return @()
        }
        
        # Filter out pull requests (they also appear in issues endpoint)
        $issuesOnly = $response | Where-Object { -not $_.pull_request }
        $issues += $issuesOnly
        $page++
    } while ($response.Count -eq $perPage)
    
    return $issues
}

# Check if an issue is linked to a specific project
function Test-IssueInProject {
    param (
        [string] $OrgName,
        [string] $RepoName,
        [int] $IssueNumber,
        [string] $ProjectId
    )
    
    $query = @"
query(`$orgName: String!, `$repoName: String!, `$issueNumber: Int!) {
  repository(owner: `$orgName, name: `$repoName) {
    issue(number: `$issueNumber) {
      id
      projectItems(first: 100) {
        nodes {
          project {
            id
          }
        }
      }
    }
  }
}
"@
    
    $variables = @{
        orgName = $OrgName
        repoName = $RepoName
        issueNumber = $IssueNumber
    }
    
    $data = Invoke-GraphQL -Query $query -Variables $variables
    if (-not $data -or -not $data.repository -or -not $data.repository.issue) { 
        return @{
            InProject = $false
            IssueId = $null
        }
    }
    
    $inProject = $data.repository.issue.projectItems.nodes | Where-Object { $_.project.id -eq $ProjectId }
    
    return @{
        InProject = ($null -ne $inProject)
        IssueId = $data.repository.issue.id
    }
}

# Add issue to project
function Add-IssueToProject {
    param (
        [string] $ProjectId,
        [string] $IssueId
    )
    
    $mutation = @"
mutation(`$projectId: ID!, `$contentId: ID!) {
  addProjectV2ItemByContentId(input: {projectId: `$projectId, contentId: `$contentId}) {
    item {
      id
    }
  }
}
"@
    
    $variables = @{
        projectId = $ProjectId
        contentId = $IssueId
    }
    
    $data = Invoke-GraphQL -Query $mutation -Variables $variables
    if (-not $data) { return $null }
    
    return $data.addProjectV2ItemByContentId.item.id
}

# Get project's Status field and its Todo option
function Get-ProjectStatusField {
    param (
        [string] $ProjectId
    )
    
    $query = @"
query(`$projectId: ID!) {
  node(id: `$projectId) {
    ... on ProjectV2 {
      fields(first: 100) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
        }
      }
    }
  }
}
"@
    
    $variables = @{
        projectId = $ProjectId
    }
    
    $data = Invoke-GraphQL -Query $query -Variables $variables
    if (-not $data -or -not $data.node) { return $null }
    
    $statusField = $data.node.fields.nodes | Where-Object { $_.name -eq 'Status' }
    if (-not $statusField) { return $null }
    
    $todoOption = $statusField.options | Where-Object { $_.name -eq 'Todo' }
    
    return @{
        FieldId = $statusField.id
        TodoOptionId = if ($todoOption) { $todoOption.id } else { $null }
    }
}

# Set project item status to Todo
function Set-ProjectItemStatus {
    param (
        [string] $ProjectId,
        [string] $ItemId,
        [string] $FieldId,
        [string] $OptionId
    )
    
    $mutation = @"
mutation(`$projectId: ID!, `$itemId: ID!, `$fieldId: ID!, `$optionId: String!) {
  updateProjectV2ItemFieldValue(input: {projectId: `$projectId, itemId: `$itemId, fieldId: `$fieldId, value: {singleSelectOptionId: `$optionId}}) {
    projectV2Item {
      id
    }
  }
}
"@
    
    $variables = @{
        projectId = $ProjectId
        itemId = $ItemId
        fieldId = $FieldId
        optionId = $OptionId
    }
    
    $data = Invoke-GraphQL -Query $mutation -Variables $variables
    return ($null -ne $data)
}

# Main script execution
Write-Host ""
Write-Host "Looking for project '$ProjectName' in organization '$Organization'..."

$project = Get-OrganizationProject -OrgName $Organization -ProjName $ProjectName
if (-not $project) {
    Write-Host "Project '$ProjectName' not found in organization '$Organization'" -ForegroundColor 'red'
    Write-Host "Please verify that:" -ForegroundColor 'red'
    Write-Host "  1. The project name is correct (case-sensitive)" -ForegroundColor 'red'
    Write-Host "  2. Your PAT has 'project' scope to access organization projects" -ForegroundColor 'red'
    Write-Host "  3. The project exists in the organization" -ForegroundColor 'red'
    exit 1
}

Write-Host "Found project: $($project.title) (ID: $($project.id))" -ForegroundColor 'green'

# Get status field info
$statusField = Get-ProjectStatusField -ProjectId $project.id
if ($statusField -and $statusField.TodoOptionId) {
    Write-Host "Found Status field with 'Todo' option" -ForegroundColor 'green'
} else {
    Write-Host "Warning: Status field or 'Todo' option not found. Issues will be added without status." -ForegroundColor 'yellow'
}

Write-Host ""
Write-Host "Getting all repositories in organization '$Organization'..."

$repos = Get-OrganizationRepositories -OrgName $Organization
Write-Host "Found $($repos.Count) repositories" -ForegroundColor 'green'

$totalIssuesProcessed = 0
$totalIssuesAdded = 0

foreach ($repo in $repos) {
    Write-Host ""
    Write-Host "Processing repository: $($repo.name)" -ForegroundColor 'cyan'
    
    # Skip archived repositories
    if ($repo.archived) {
        Write-Host "  Skipping (archived)"
        continue
    }
    
    $issues = Get-RepositoryIssues -OrgName $Organization -RepoName $repo.name
    
    if ($issues.Count -eq 0) {
        Write-Host "  No open issues found"
        continue
    }
    
    Write-Host "  Found $($issues.Count) open issues"
    
    foreach ($issue in $issues) {
        $totalIssuesProcessed++
        Write-Host "    Checking issue #$($issue.number): $($issue.title)"
        
        $result = Test-IssueInProject -OrgName $Organization -RepoName $repo.name -IssueNumber $issue.number -ProjectId $project.id
        
        if ($result.InProject) {
            Write-Host "      Already in project" -ForegroundColor 'gray'
        } else {
            Write-Host "      Not in project - Adding..." -ForegroundColor 'yellow'
            
            $itemId = Add-IssueToProject -ProjectId $project.id -IssueId $result.IssueId
            
            if ($itemId) {
                Write-Host "      Added to project" -ForegroundColor 'green'
                $totalIssuesAdded++
                
                # Set status to Todo if available
                if ($statusField -and $statusField.TodoOptionId) {
                    $success = Set-ProjectItemStatus -ProjectId $project.id -ItemId $itemId -FieldId $statusField.FieldId -OptionId $statusField.TodoOptionId
                    if ($success) {
                        Write-Host "      Status set to 'Todo'" -ForegroundColor 'green'
                    } else {
                        Write-Host "      Warning: Could not set status to 'Todo'" -ForegroundColor 'yellow'
                    }
                }
            } else {
                Write-Host "      Failed to add to project" -ForegroundColor 'red'
            }
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor 'cyan'
Write-Host "Summary:" -ForegroundColor 'cyan'
Write-Host "  Repositories processed: $($repos.Count)"
Write-Host "  Issues processed: $totalIssuesProcessed"
Write-Host "  Issues added to project: $totalIssuesAdded"
Write-Host "========================================" -ForegroundColor 'cyan'
Write-Host "Script completed!" -ForegroundColor 'green'
