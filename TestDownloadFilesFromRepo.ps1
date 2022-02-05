# Include script
. ./DownloadFilesFromRepo.ps1

# Input for function:
# [string]$Owner,
# [string]$Repository,
# [string]$Path,
# [string]$DestinationPath,
# [string]$Pat

DownloadFilesFromRepo -Owner 'EwoutDBoer' -Repository 'MyRepo' -Path '.' -DestinationPath '.' -Pat 'INSERT_PAT_HERE'