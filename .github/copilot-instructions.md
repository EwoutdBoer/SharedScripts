# Copilot Instructions for SharedScripts

## Repository Overview
This repository contains shared PowerShell scripts and CI/CD YAML files that can be reused across multiple repositories. The main scripts include:
- **DownloadFilesFromRepo.ps1**: Downloads files from GitHub repositories using the GitHub API
- **cleanup-workflow-runs.ps1**: Cleans up outdated GitHub Actions workflow runs based on retention policies

## Code Style and Conventions

### PowerShell
- Use PowerShell 7+ syntax and features
- Follow PowerShell best practices for cmdlet naming (Verb-Noun)
- Use approved PowerShell verbs (Get, Set, New, Remove, etc.)
- Include comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, and `.EXAMPLE` sections
- Use proper parameter validation attributes (e.g., `[Parameter(Mandatory=$true)]`)
- Prefer `Write-Host` for user-facing messages with appropriate color coding:
  - Green for success messages
  - Red for error messages
- Use meaningful variable names in PascalCase for parameters and camelCase for local variables
- Include error handling with try-catch blocks where appropriate

### JSON Configuration
- Use consistent indentation (2 spaces)
- Follow the structure defined in `workflow-retention.json` for workflow retention policies
- Ensure JSON is valid and properly formatted

## Key Patterns

### GitHub API Integration
- Use GitHub REST API v3 with proper authentication headers
- Structure: `Authorization = "token $($PAT)"`
- Include Accept header: `"Accept" = "application/vnd.github.v3+json"`
- Use `Invoke-RestMethod` or `Invoke-WebRequest` with proper error handling
- Include `-StatusCodeVariable` and `-SkipHttpErrorCheck` for better error management

### Workflow Retention Policy
- Retention policies are defined in `.github/workflows/workflow-retention.json`
- Supports branch-specific retention (main vs. other branches)
- Differentiates between success and failure run retention
- Supports wildcard patterns (*) for action names and branches
- Can target specific actors (e.g., dependabot[bot])
- Feature: `deleteFailureRunsWhenFollowedBySuccess` to auto-cleanup failed runs

## Testing
- Test scripts are prefixed with "Test" (e.g., `TestDownloadFilesFromRepo.ps1`)
- Test scripts should include placeholders for credentials (e.g., `'ADD_YOUR_PAT_HERE'`)
- Ensure test scripts demonstrate proper usage of the main scripts

## Security
- Never hardcode Personal Access Tokens (PATs) or credentials
- Use parameter inputs for sensitive data
- Include clear documentation about required token scopes
- For cleanup script: Requires "admin:org" scope for GitHub PAT

## Documentation
- Keep README.md concise and up-to-date
- Include proper comment-based help in all PowerShell scripts
- Document any dependencies or prerequisites
- Provide usage examples in test scripts or documentation

## GitHub Actions
- This repository may be used as a source for shared workflow configurations
- Scripts may interact with GitHub Actions APIs
- Be mindful of API rate limits when working with workflow runs
