#
# Copyright (c) 2024-present Simdsoft Limited.
#
# wenv - An all in one web environment(nginx + mysql/mariadb + php) supporting both windows, ubuntu, macos
#
param(
    $op = 'start',
    $target = 'default',
    [switch]$verbose,
    [switch]$force,
    [switch]$version
)

$wenv_ver = '2.0.1'

$global:wenv_host_cpu = [System.Runtime.InteropServices.RuntimeInformation, mscorlib]::OSArchitecture.ToString().ToLower()

Set-Alias println Write-Host

println "wenv version $wenv_ver-$(git rev-parse --short=7 HEAD)"

if ($version) { return }

$Global:IsWin = $IsWindows -or ("$env:OS" -eq 'Windows_NT')
$Global:IsUbuntu = !$IsWin -and ($PSVersionTable.OS -like 'Ubuntu *')

. (Join-Path $PSScriptRoot 'manifest.ps1')

$download_path = Join-Path $PSScriptRoot 'cache'
$install_prefix = Join-Path $PSScriptRoot 'opt'

function eval($str, $raw = $false) {
    if (!$raw) {
        return Invoke-Expression "`"$str`""
    }
    else {
        return Invoke-Expression $str
    }
}

function parse_prop($line_text) {
    if ($line_text -match "^#.*$") {
        return $null
    }
    if ($line_text -match "^(.+?)\s*=\s*(.*)$") {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        return $key, $value
    }
    return $null
}

function ConvertFrom-Props {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    $props = @{}

    foreach ($_ in $InputObject) {
        $key, $val = parse_prop $_
        if ($key) {
            $props[$key] = $val
        }
    }

    return $props
}

function gen_random_key {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Length
    )

    $charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@$%^&*~'
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $key = [System.Text.StringBuilder]::new($Length)

    $byte = New-Object Byte[] 1
    for ($i = 0; $i -lt $Length; $i++) {
        $random.GetBytes($byte)
        $index = [convert]::ToInt32($byte[0]) % $charset.Length
        $key.Append($charset[$index]) | Out-Null
    }

    return $key.ToString()
}

function mkdirs($path) {
    if (!(Test-Path $path)) { New-Item $path -ItemType Directory 1>$null }
}

function download_file($url, $out) {
    if (Test-Path $out -PathType Leaf) { return }
    println "Downloading $url to $out ..."
    Invoke-WebRequest -Uri $url -OutFile $out -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"
}

function download_and_expand($url, $out, $dest, $sudo, $checksum) {

    download_file $url $out

    if ($checksum) {
        $realsum = (Get-FileHash $out -Algorithm MD5).Hash.ToLower()
        if($checksum -ne $realsum) {
            throw "Verify file integrity fail, realsum:$realsum, desired:$checksum"
        }
    }

    try {
        if($sudo) { 
            sudo mkdir -p $dest 
        } 
        else {
          mkdirs $dest
        }
        if ($out.EndsWith('.zip')) {
            if ($IsWin) {
                Expand-Archive -Path $out -DestinationPath $dest -Force
            }
            else {
                unzip -d $dest $out | Out-Null
            }
        }
        elseif ($out.EndsWith('.tar.gz') -or $out.EndsWith('.tar')) {
            if ($sudo) {
                bash -c "sudo tar xf $out -C $dest" | Out-Host 
            } else {
                tar xf "$out" -C $dest | Out-Host
            }
        }
        elseif ($out.EndsWith('.7z') -or $out.EndsWith('.exe')) {
            7z x "$out" "-o$dest" -bsp1 -snld -y | Out-Host
        }
        elseif ($out.EndsWith('.sh')) {
            chmod 'u+x' "$out" | Out-Host
        }
        if (!$?) { throw "1kiss: Expand fail" }
    }
    catch {
        Remove-Item $out -Force
        throw "1kiss: Expand archive $out fail, please try again"
    }
}

function resolve_path ($path, $prefix = $null) { 
    if ([IO.Path]::IsPathRooted($path)) { 
        return $path 
    }
    else {
        if (!$prefix) { $prefix = $PSScriptRoot }
        return Join-Path $prefix $path
    }
}

function fetch_pkg($url, $out = $null, $exrep = $null, $prefix = $null, $sudo = $false, $checksum = $null) {
    if (!$out) { $out = Join-Path $download_path $(Split-Path $url.Split('?')[0] -Leaf) }
    else { $out = resolve_path $out $download_path }

    $pfn_rename = $null

    if ($exrep) {
        $exrep = $exrep.Split('=')
        if ($exrep.Count -eq 1) {
            # single file
            if (!$prefix) {
                $prefix = resolve_path $exrep[0]
            }
            else {
                $prefix = resolve_path $prefix
            }
        }
        else {
            $prefix = resolve_path $prefix
            $inst_dst = Join-Path $prefix $exrep[1]
            $pfn_rename = {
                # move to plain folder name
                $full_path = (Get-ChildItem -Path $prefix -Filter $exrep[0]).FullName
                if ($full_path) {
                    if ($sudo) {
                        sudo mv $full_path $inst_dst
                    } else {
                        Move-Item $full_path $inst_dst
                    }
                }
                else {
                    throw "1kiss: rename $($exrep[0]) to $inst_dst fail"
                }
            }
            if (Test-Path $inst_dst -PathType Container) {
                if ($sudo) {
                    sudo rm -rf $inst_dst
                }
                else {
                    Remove-Item $inst_dst -Recurse -Force
                }
            }
        }
    }
    else {
        if (!$prefix) {
            $prefix = $install_prefix
        }
        else {
            $prefix = resolve_path $prefix
        }
    }
    
    download_and_expand $url $out $prefix $sudo $checksum

    if ($pfn_rename) { &$pfn_rename }
}

if ($IsWin) {
    $wenv_root = $PSScriptRoot.Replace('\', '/')
}
else {
    $wenv_root = $PSScriptRoot
}

$Script:local_props = $null
$actions = @{
    setup_env = {
        if ($IsLinux -and !(Get-Command 'unzip' -ErrorAction SilentlyContinue)) {
            sudo apt update
            sudo apt install --allow-unauthenticated --yes unzip
        }

        # load local.properties
        $prop_file = (Join-Path $PSScriptRoot 'local.properties')
        if (Test-Path $prop_file -PathType Leaf) {
            $props_lines = (Get-Content -Path $prop_file)
        }
        else {
            $mysql_pass = gen_random_key -Length 32
            $props_lines = @(
                "mysql_pass=$mysql_pass",
                'domain_list=local.wenv.dev'
                'service_list=nginx,php,mariadb'
            )
            Set-Content -Path $prop_file -Value $props_lines
        }
        $Script:local_props = ConvertFrom-Props $props_lines
        $Script:service_list = $local_props['service_list'].Split(',')

        if ($target -eq 'default') {
            $Script:evaluated_targets = $Script:service_list
        }
        elseif ($targets -isnot [array]) {
            $Script:evaluated_targets = "$target".Split(',')
        } else {
            $Script:evaluated_targets = $target
        }

        $Script:nginx_base_ver = "$($nginx_ver.Major).$($nginx_ver.Minor)"

        mkdirs $install_prefix
        mkdirs $download_path
        # windows prebuilt nginx require 'var/nginx/logs' and 'var/nginx/temp'
        mkdirs $(Join-Path $PSScriptRoot 'var/nginx/logs')
        mkdirs $(Join-Path $PSScriptRoot 'var/nginx/temp')
        mkdirs $(Join-Path $PSScriptRoot 'var/php-cgi')
        mkdirs $(Join-Path $PSScriptRoot 'var/mysqld')
        

        if ($IsWin) {
            $is_php8 = $php_ver -ge [Version]'8.0.0'
            $Script:php_vs = @('vc15', 'vs17')[$is_php8]
        }

        if ($IsWin -or $IsMacOS) {
            $Script:mysqld_cwd = Join-Path $PSScriptRoot 'var/mysqld'
            $Script:mysqld_data = Join-Path $PSScriptRoot 'var/mysqld/data'

            $Script:mariadb_cwd = Join-Path $PSScriptRoot 'var/mariadb'
            $Script:mariadb_data = Join-Path $PSScriptRoot 'var/mariadb/data'
        }
    }
}

function mod_php_ini($php_ini_file, $do_setup) {
    $match_ext = {
        param($ext, $exts)
        foreach ($item in $exts) {
            if ($ext -like $item) {
                return $true
            }
        }
        return $false
    }

    $upload_props = @{upload_max_filesize = '64M'; post_max_size = '64M'; memory_limit = '128M' }

    $exclude_exts = @('*=oci8_12c*', '*=pdo_firebird*', '*=pdo_oci*', '*=snmp*')

    $lines = Get-Content -Path $php_ini_file
    $line_index = 0
    $mods = 0
    foreach ($line_text in $lines) {
        if ($line_text -like ';extension_dir = "ext"') {
            if ($do_setup) {
                $lines[$line_index] = 'extension_dir = "ext"'
                ++$mods
            }
        } 
        elseif ($line_text -like '*extension=*') {
            if ($do_setup) {
                if ($line_text -like ';extension=*') {
                    if (-not (&$match_ext $line_text $exclude_exts)) {
                        $line_text = $line_text.Substring(1)
                        $lines[$line_index] = $line_text
                        ++$mods
                    }
                }

                $match_info = [Regex]::Match($line_text, '(?<!;)\bextension=([^;]+)')
                if ($match_info.Success -and $line_text.StartsWith('extension=')) {
                    println "php.ini: $($match_info.value)"
                }
            }
        }
        else {
            $key, $val = parse_prop $line_text
            if ($key -and $upload_props.Contains($key)) {
                $new_val = $upload_props[$key]
                $lines[$line_index] = "$key = $new_val"
                ++$mods
            }
        }
        ++$line_index
    }

    return $lines, $mods
}

if ($IsWin) {
    . $(Join-Path $PSScriptRoot 'contrib/windows.ps1')
}
elseif ($IsUbuntu) {
    . $(Join-Path $PSScriptRoot 'contrib/linux.ps1')
}
elseif ($IsMacOS) {
    . $(Join-Path $PSScriptRoot 'contrib/macos.ps1')
}
else {
    throw "Unsupported OS: $($PSVersionTable.OS)"
}

$actions.fetch.phpmyadmin = {
    fetch_pkg "https://files.phpmyadmin.net/phpMyAdmin/${phpmyadmin_ver}/phpMyAdmin-${phpmyadmin_ver}-all-languages.zip" -exrep "phpMyAdmin-${phpmyadmin_ver}-all-languages=${phpmyadmin_ver}" -prefix 'opt/phpmyadmin'
    fetch_pkg "https://files.phpmyadmin.net/themes/boodark-nord/1.1.0/boodark-nord-1.1.0.zip" -prefix "opt/phpmyadmin/${phpmyadmin_ver}/themes/"
}

$actions.init.phpmyadmin = {
    $phpmyadmin_dir = Join-Path $install_prefix "phpmyadmin/$phpmyadmin_ver"
    $phpmyadmin_conf = (Join-Path $phpmyadmin_dir 'config.inc.php')

    if (!(Test-Path $phpmyadmin_conf -PathType Leaf) -or $force) {
        $blowfish_secret = gen_random_key -Length 32
        $lines = Get-Content -Path (Join-Path $phpmyadmin_dir 'config.sample.inc.php')
        $line_index = 0
        $has_theme_manager = $false
        $has_theme_default = $false
        foreach ($line_text in $lines) {
            if ($line_text -like "*blowfish_secret*") {
                $lines[$line_index] = $line_text.Replace("''", "'$blowfish_secret'")
            }
            elseif ($line_text -like '*ThemeManager*') {
                $lines[$line_index] = $line_text.Replace("false", "true")
                $has_theme_manager = $true
            }
            elseif ($line_text -like '*ThemeDefault*') {
                $lines[$line_index] = $line_text -replace "'.*'", "'boodark-nord'"
                $has_theme_default = $true
            }
            ++$line_index
        }
        if (!$has_theme_manager) {
            $lines += "`$cfg['ThemeManager'] = true;"
            $lines += "`$cfg['ShowAll'] = true;"
        }
        if (!$has_theme_default) {
            if ([Version]$phpmyadmin_ver -lt [Version]'6.0.0') {
                $lines += "`$cfg['ThemeDefault'] = 'boodark-nord';"
            }
        }
        Set-Content -Path $phpmyadmin_conf -Value $lines
    }
}

$actions.init.nginx = {
    $nginx_conf_file_tmp = Join-Path $download_path 'nginx.conf'
    $nginx_conf_dir = Join-Path $PSScriptRoot "etc/nginx/$nginx_base_ver"

    # check symlink
    $mods = 0
    if($IsWin) {
        $nginx_conf_src = Join-Path $wenv_root "opt/nginx/$nginx_ver/conf"
        $paths = Get-ChildItem $nginx_conf_src
        foreach ($path in $paths) {
            if($path.FullName.EndsWith('nginx.conf')) {
                continue
            }
            $filename = Split-Path $path.FullName -Leaf
            $dest_path = Join-Path $nginx_conf_dir $filename
            if (Test-Path $dest_path) {
                $dest_item = Get-Item $dest_path
                if ($dest_item.Target -eq $path.FullName) {
                    continue
                }
                println "nginx init: recreate symlink $($path.FullName)==>$dest_path"
                Remove-Item $dest_path
            }
            # Note: you need Enable developer mode on windows 10/11 developer settings
            # otherwise, need administrator proviliedge
            New-Item -ItemType SymbolicLink -Path $dest_path -Target $path.FullName
            ++$mods
        }
    }

    $nginx_conf_file = Join-Path $nginx_conf_dir 'nginx.conf'
    if ((Test-Path $nginx_conf_file_tmp -PathType Leaf) -and (Test-Path $nginx_conf_file)) {
        $anwser = if ($force) { Read-Host "Are you want force reinit nginx, will lost conf?(Y/n)" } else { 'N' }
        if ($anwser -ilike 'n*') {
            if (!$mods) {
                println "nginx init: nothing need to do"
            }
            return
        }
    }

    if ($IsUbuntu) {
        $nginx_grp = $(cat /etc/passwd | grep $nginx_user)
        if (!$nginx_grp) {
            println "Creating nginx user: $nginx_user ..."
            sudo useradd -M -s /sbin/nologin $nginx_user
        }
        sudo chown -R ${php_user}:${php_user} $wenv_root/htdocs
        sudo chown -R ${nginx_user}:${nginx_user} $wenv_root/var/nginx
        sudo chmod 755 $wenv_root/htdocs $wenv_root/etc/nginx `
            $nginx_conf_dir `
            $wenv_root/var/nginx `
            $wenv_root/var/nginx/logs `
            $wenv_root/var/nginx/temp
        # sudo chmod 644 $nginx_conf_dir/* $wenv_root/var/nginx/logs/*
    }

    $lines = Get-Content -Path (Join-Path $nginx_conf_dir 'nginx.conf.in')
    $line_index = 0
    
    $wenv_cert_dir = Join-Path $PSScriptRoot 'etc/certs'
    if (!(Test-Path (Join-Path $wenv_cert_dir 'server.crt') -PathType Leaf) -or
        !(Test-Path (Join-Path $wenv_cert_dir 'server.key') -PathType Leaf)
    ) {
        $wenv_cert_dir = (Join-Path $wenv_cert_dir 'sample').Replace('\', '/')
        $wenv_rel_cert_dir = '../../certs/sample'
        $wenv_server_crt_file = Join-Path $wenv_cert_dir 'server.crt'
        if (!(Test-Path $wenv_server_crt_file -PathType Leaf)) {
            Copy-Item "$wenv_server_crt_file.default" $wenv_server_crt_file
        }
        $wenv_server_key_file = Join-Path $wenv_cert_dir 'server.key'
        if (!(Test-Path $wenv_server_key_file -PathType Leaf)) {
            Copy-Item "$wenv_server_key_file.default" $wenv_server_key_file
        }
        Write-Warning "Using sample certs in dir $wenv_cert_dir"
    }
    else {
        $wenv_rel_cert_dir = '../../certs'
    }

    if ($IsWin) {
        $wenv_fastcgi_pass = "127.0.0.1:9000"
    } else {
        $wenv_fastcgi_pass = "unix:/run/php/php$php_base_ver-fpm.sock"
    }
    $wenv_cert_dir = $wenv_cert_dir.Replace('\', '/')
    foreach ($line_text in $lines) {
        if ($line_text.Contains('@wenv_root@')) {
            $lines[$line_index] = $line_text.Replace('@wenv_root@', $wenv_root)
        }
        elseif ($line_text.Contains('@wenv_domain_list@')) {
            $lines[$line_index] = $line_text.Replace('@wenv_domain_list@', $local_props['domain_list'])
        }
        elseif ($line_text.Contains('@wenv_cert_dir@')) {
            $lines[$line_index] = $line_text.Replace('@wenv_cert_dir@', $wenv_rel_cert_dir)
        }
        elseif ($line_text.Contains('@phpmyadmin_ver@')) {
            $lines[$line_index] = $line_text.Replace('@phpmyadmin_ver@', $phpmyadmin_ver)
        }
        elseif ($line_text.Contains(('@wenv_fastcgi_pass@'))) {
            $lines[$line_index] = $line_text.Replace('@wenv_fastcgi_pass@', $wenv_fastcgi_pass)
        }
        elseif (!$IsWin -and !$IsMacOS -and $line_text.Contains('nobody')) {
            $line_text = $line_text.Replace('nobody', "$nginx_user")
            if ($line_text.StartsWith('#')) { $line_text = $line_text.TrimStart('#') }
            $lines[$line_index] = $line_text
        }
        ++$line_index
    }
    Set-Content -Path $nginx_conf_file_tmp -Value $lines
    if ($IsLinux) {
        sudo cp $nginx_conf_file_tmp $nginx_conf_file
        sudo chmod 644 $nginx_conf_file

        # if certbot cert exist, create symlink for live
        $link_live_certs = @"
cd $wenv_cert_dir
if [ -f '../letsencrypt/live/simdsoft.com/fullchain.pem' ]; then
  ln -s ../letsencrypt/live/simdsoft.com/fullchain.pem ./server.crt
fi
if [ -f '../letsencrypt/live/simdsoft.com/privkey.pem' ]; then
  ln -s ../letsencrypt/live/simdsoft.com/privkey.pem ./server.key
fi
cd -
"@
        bash -c $link_live_certs
    }
    else {
        Copy-Item $nginx_conf_file_tmp $nginx_conf_file
    }
}

function run_action($name, $targets) {
    $action = $actions[$name]
    foreach ($target in $targets) {
        $action_comp = $action.$target
        if ($action_comp) {
            & $action_comp
        }
        else {
            println "The $target not support action: $name"
        }
    }
}

& $actions.setup_env

switch ($op) {
    'fetch' {
        run_action 'fetch' $evaluated_targets
    }
    'init' {
        run_action 'init' $evaluated_targets
    }
    'install' {
        println 'Installing server ...'
        run_action 'fetch' $evaluated_targets
        run_action 'init' $evaluated_targets
    }
    'start' {
        println "Starting server ..."
        run_action 'start' $evaluated_targets
    }
    'restart' {
        println "Restarting server ..."
        run_action 'stop' $evaluated_targets
        run_action 'start' $evaluated_targets
    }
    'enable' {
        println "Enabling server ..."
        run_action 'enable' $evaluated_targets
    }
    'disable' {
        println "Disabling server ..."
        run_action 'disable' $evaluated_targets
    }
    'stop' {
        println "Stopping server ..."
        run_action 'stop' $evaluated_targets
    }
    'passwd' {
        run_action 'passwd' $evaluated_targets
    }
    'status' {
        run_action 'status' $evaluated_targets
    }
    'gen_pass' {
        $rand_pass = gen_random_key -Length 32
        echo $rand_pass
    }
    'reload' {
        run_action 'reload' $evaluated_targets
    }
    'dist' {
        $dist_script = Join-Path $wenv_root 'contrib/dist.ps1'
        &$dist_script -target $target -fullup:$force
    }
    'up' {
        $up_script = Join-Path $wenv_root 'contrib/up.ps1'
        &$up_script -target $target -fullup:$force
    }
}

if ($?) {
    println "The operation successfully."
}
else {
    throw "The operation fail!"
}
