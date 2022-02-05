#Other implementation: https://gist.github.com/zerotag/cfc7d57eef5df9ae29ef8a56a367e6dc
function DownloadFilesFromRepo {
    Param(
        [string]$Owner,
        [string]$Repository,
        [string]$Path,
        [string]$DestinationPath,
        [string]$Pat
        )
    
        # Setup
        $baseUri = "https://api.github.com/"
        $uri = "repos/$Owner/$Repository/contents/$Path"
        $headers = @{Authorization = "token $($Pat)"}

        $wr = Invoke-WebRequest -Uri $($baseuri+$uri) -Headers $headers
        $objects = $wr.Content | ConvertFrom-Json
        $files = $objects | Where-Object {$_.type -eq "file"} | Select-Object -exp download_url
        $directories = $objects | Where-Object {$_.type -eq "dir"}
        
        $directories | ForEach-Object { 
            DownloadFilesFromRepo -Owner $Owner -Repository $Repository -Path $_.path -DestinationPath $($DestinationPath+$_.name) -Pat $Pat
        }
    
        if (-not (Test-Path $DestinationPath)) {
            # Destination path does not exist, let's create it
            try {
                New-Item -Path $DestinationPath -ItemType Directory -ErrorAction Stop
            } catch {
                throw "Could not create path '$DestinationPath'!"
            }
        }
    
        foreach ($file in $files) {
            $fileDestination = Join-Path $DestinationPath (Split-Path $file -Leaf)
            if($fileDestination.Contains("?token")) {
                $locationOfToken = $fileDestination.IndexOf("?token")
                $fileDestination = $fileDestination.Substring(0, $locationOfToken);
            }
            try {
                Invoke-WebRequest -Uri $file -OutFile $fileDestination -Headers $headers -ErrorAction Stop -Verbose
                "Grabbed '$($file)' to '$fileDestination'"
            } catch {
                throw "Unable to download '$($file.path)'"
            }
        }
    }