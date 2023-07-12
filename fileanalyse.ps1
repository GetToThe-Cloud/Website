



$path = "C:\Program Files (Arm)"

function Add-Item {
    param(
        [string]$folder,
        [string]$level,
        [string]$SizeMb,
        [string]$sizeGb,
        [int]$itemCount
    )

    $item = [PSCustomObject]@{
        Folder = $folder
        Level = $level
        SizeMB = $SizeMb
        SizeGB = $sizeGb
        ItemCount = $itemCount
    }

    return $item
}

$DirStats = @()

$Level1 = Get-ChildItem -Path $Path 
forEach ($Folder in $Level1){
    $Level2 = Get-ChildItem -Path $Folder.fullname -Directory
    $file = Get-ChildItem -Path $Folder.fullname -File -Recurse | Measure-Object -Property Length -sum
    $Mb = "{0:N2}" -f ($file.sum / 1Mb)
    $Gb = "{0:N2}" -f ($file.sum / 1Gb)
    $item = Add-Item -folder $Folder.Fullname -level 1 -SizeMb $mb -sizeGb $gb -itemCount $File.Count

    $Dirstats += $item
    ForEach ($Folder in $Level2){
        $Level3 = Get-ChildItem -Path $Folder.fullname -Directory
        $file = Get-ChildItem -Path $Folder.fullname -File -Recurse | Measure-Object -Property Length -sum
        $Mb = "{0:N2}" -f ($file.sum / 1Mb)
        $Gb = "{0:N2}" -f ($file.sum / 1Gb)
        $item = Add-Item -folder $Folder.Fullname -level 2 -SizeMb $mb -sizeGb $gb -itemCount $File.Count
        $Dirstats += $item

        ForEach ($Folder in $level3){
            $Level4 = Get-ChildItem -Path $Folder.fullname -Directory
            $file = Get-ChildItem -Path $Folder.fullname -File -Recurse | Measure-Object -Property Length -sum
            $Mb = "{0:N2}" -f ($file.sum / 1Mb)
            $Gb = "{0:N2}" -f ($file.sum / 1Gb)
            $item = Add-Item -folder $Folder.Fullname -level 3 -SizeMb $mb -sizeGb $gb -itemCount $File.Count
            $Dirstats += $item

            ForEach ($Folder in $level4){
                $Level5 = Get-ChildItem -Path $Folder.fullname -Directory
                $file = Get-ChildItem -Path $Folder.fullname -File -Recurse | Measure-Object -Property Length -sum
                $Mb = "{0:N2}" -f ($file.sum / 1Mb)
                $Gb = "{0:N2}" -f ($file.sum / 1Gb)
                $item = Add-Item -folder $Folder.Fullname -level 4 -SizeMb $mb -sizeGb $gb -itemCount $File.Count
                $Dirstats += $item
            }
        }
    }
}