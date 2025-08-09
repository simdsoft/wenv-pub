param(
    $target_ver = 'default',
    [switch]$fullup
)

function realpath($path) {
    return $Global:ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
}

$dist_root = realpath $PSScriptRoot/../dist
$site_root = realpath $PSScriptRoot/../htdocs

if (!(Test-Path $dist_root)) {
    Write-Host "The $dist_root not found."
    return
}

if ($target_ver -eq 'default') {
    $pkg_list = Get-ChildItem $dist_root -Filter 'htdocs-*.zip'
    if (!$pkg_list) {
        Write-Host "No package found in $dist_root."
        return
    }
    $ver_list = @()
    foreach($pkg_item in $pkg_list) {
        $pkg_name = $pkg_item.Name
        if ($pkg_name -match 'htdocs-(\d+\.\d+\.\d+)\.zip') {
            $ver_list += [Version]$matches[1]
        }
    }

    $ver_list = $ver_list | Sort-Object -Descending
    $target_ver = $ver_list[0].ToString()
    Write-Host "Will update to $target_ver found in $dist_root automatically."
}

Push-Location $dist_root

Write-Host "Perform update to version $target_ver"
$new_site_dir = Join-Path $dist_root "htdocs-$target_ver"
$new_site_pkg = Join-Path $dist_root "htdocs-$target_ver.zip"
if (Test-Path $new_site_pkg -PathType Leaf) {
    unzip $new_site_pkg
    sudo chown -R www-data:www-data $new_site_dir
    if ($fullup) {
        Write-Host "Perform full upgrade"
        sudo rm -rf $site_root
        sudo mv $new_site_dir $site_root
    } else {
        Write-Host "Perform partial upgrade"
        Get-ChildItem $new_site_dir -Recurse | ForEach-Object {
            if (!$_.PSIsContainer) {
                $src_path = $_.FullName
                $rel_path = [IO.Path]::GetRelativePath($new_site_dir, $_.FullName)
                $dest_path = Join-Path $site_root $rel_path
                $dest_dir = Split-Path $dest_path -Parent
                if (!(Test-Path $dest_dir -PathType Container)) {
                    Write-Host "Create directory $dest_dir"
                    sudo mkdir -p $dest_dir
                }
                Write-Host "Copy file $src_path ==> $dest_path"
                sudo cp --preserve=all -f $src_path $dest_path
            }
        }

        $delete_list_path = "deleted-$target_ver.json"
        if (Test-Path $delete_list_path -PathType Leaf) {
            $delete_list = Get-Content $delete_list_path | ConvertFrom-Json
            foreach ($item in $delete_list) {
                $path = Join-Path $site_root "$item"
                if (Test-Path $path -PathType Leaf) {
                    Write-Host "Remove file $path"
                    sudo rm -rf $path
                } else {
                    Write-Host "File $path not found, skip remove"
                }
            }
        } else {
            Write-Host "Delete list file $delete_list_path not found, skip remove"
        }
        sudo rm -rf $new_site_dir
    }
    Write-Host "Upgrade site to $target_ver done."
} else {
    Write-Host "Package $pkg_path not found, skip remove"
}

Pop-Location
