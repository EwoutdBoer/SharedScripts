# Test script for sync-issues-to-project.ps1
# 
# Prerequisites:
# - PowerShell 7+
# - A GitHub Personal Access Token with the following scopes:
#   - repo (to read issues from repositories)
#   - read:org (to read organization repositories)
#   - project (to read/write organization projects)
#
# Usage:
# 1. Replace 'FILL_IN_YOUR_PAT_HERE' with your actual PAT
# 2. Run this script from the repository root directory

# Execute script
./sync-issues-to-project.ps1 -Organization 'EwoutdBoer' -ProjectName 'General' -PAT 'FILL_IN_YOUR_PAT_HERE'
