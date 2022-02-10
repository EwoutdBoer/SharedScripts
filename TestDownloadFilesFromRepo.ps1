# Include script
. ./DownloadFilesFromRepo.ps1

# Input for function:
# [string]$Owner,
# [string]$Repository,
# [string]$Path,
# [string]$DestinationPath,
# [string]$Pat

DownloadFilesFromRepo -Owner 'EwoutDBoer' -Repository 'Gateway' -Path '.' -DestinationPath '.' -Pat 'ADD_YOUR_PAT_HERE'