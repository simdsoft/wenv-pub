function Get-ServiceStatus($service_name, $exec_name = $null) {
    if (!$exec_name) {
        $status_ret = tasklist | findstr $service_name
    }
    else {
        $status_ret = tasklist | findstr $exec_name
    }
    if ($status_ret) {
        $brief_status = 'running'
    }
    else {
        $brief_status = 'dead'
    }
    println "$service_name status: $brief_status"
}

$actions.fetch = @{
    nginx   = {
        fetch_pkg "https://nginx.org/download/nginx-${nginx_ver}.zip" -exrep "nginx-${nginx_ver}=${nginx_ver}" -prefix 'opt/nginx'
    }
    php     = {
        if ($php_ver -eq $php_latset) {
            fetch_pkg "https://windows.php.net/downloads/releases/php-${php_ver}-Win32-$php_vs-x64.zip" -exrep "opt/php/${php_ver}"
        }
        else {
            fetch_pkg "https://windows.php.net/downloads/releases/archives/php-${php_ver}-Win32-$php_vs-x64.zip" -exrep "opt/php/${php_ver}"
        }
    }
    mysql   = {
        if ($mysql_ver -eq $mysql_latest) {
            fetch_pkg "https://cdn.mysql.com//Downloads/MySQL-$($mysql_ver.Major).$($mysql_ver.Minor)/mysql-$mysql_ver-winx64.zip" -exrep "mysql-${mysql_ver}-winx64=${mysql_ver}" -prefix 'opt/mysql'
        }
        else {
            fetch_pkg "https://downloads.mysql.com/archives/get/p/23/file/mysql-${mysql_ver}-winx64.zip" -exrep "mysql-${mysql_ver}-winx64=${mysql_ver}" -prefix 'opt/mysql'
        }
    }
    mariadb = {
        $desired_file_name = "mariadb-$mariadb_ver-winx64.zip"
        $res = ConvertFrom-Json $(Invoke-WebRequest -Uri "https://downloads.mariadb.org/rest-api/mariadb/$mariadb_ver")
        $file_info = $null
        foreach ($item in $res.release_data.$mariadb_ver.files) {
            if ($item.os -eq 'Windows' -and $item.cpu -eq 'x86_64' -and $item.file_name -eq $desired_file_name) {
                $file_info = $item
                break
            }
        }

        if (!$file_info) {
            throw "Request file download url for $desired_file_name fail!"
        }

        fetch_pkg $file_info.file_download_url -exrep "mariadb-$mariadb_ver-winx64=$mariadb_ver" -prefix 'opt/mariadb' -checksum $file_info.checksum.md5sum
        # fetch_pkg "https://mirrors.tuna.tsinghua.edu.cn/mariadb/mariadb-$mariadb_ver/winx64-packages/mariadb-$mariadb_ver-winx64.zip" -exrep "mariadb-$mariadb_ver-winx64=$mariadb_ver" -prefix 'opt/mariadb'
    }
    redis   = {
        fetch_pkg "https://github.com/microsoftarchive/redis/releases/download/win-3.0.504/Redis-x64-3.0.504.zip" -prefix 'opt/redis/3.0.504'
    }
}

function mysql_init_db($provider) {
    # enable plugin mysql_native_password, may don't required
    $mysql_dir = Join-Path $install_prefix $(eval "$provider/`$${provider}_ver")
    if ($provider -eq 'mariadb') {
        $data_dir = $mariadb_data
        $work_dir = $mariadb_cwd
    }
    else {
        $data_dir = $mysqld_data
        $work_dir = $mysqld_cwd
    }
    
    if (Test-Path $data_dir -PathType Container) {
        $anwser = if ($force) { Read-Host "Are you sure force reinit $provider db, will lost all database(Y/n)?" } else { 'Y' }
        if ($anwser -ilike 'y*') {
            println "$provider init: nothing need to do"
            return
        }
        
        println "Deleting $data_dir"
        taskkill /f /im mysqld.exe 2>$null
        Remove-Item $data_dir -Recurse -Force
    }

    mkdirs $data_dir

    $mysql_bin = Join-Path $mysql_dir 'bin'
    $mysqld_prog = Join-Path $mysql_bin 'mysqld.exe'
    $mysql_prog = Join-Path $mysql_bin 'mysql.exe'
    
    $mysql_pass = $local_props['mysql_pass']
    $my_conf_file = Join-Path $wenv_root "etc/$provider/my.ini"
    Copy-Item $my_conf_file $mysql_dir -Force

    Push-Location $work_dir
    if ($provider -eq 'mariadb') {
        $set_pass_cmds = "use mysql; ALTER user 'root'@'localhost' IDENTIFIED BY '$mysql_pass'; FLUSH PRIVILEGES;"
        $mariadb_installer = Join-Path $mysql_bin 'mariadb-install-db.exe'
        & $mariadb_installer --datadir $data_dir | Out-Host
    }
    else {
        $set_pass_cmds = "use mysql; UPDATE user SET authentication_string='' WHERE user='root'; ALTER user 'root'@'localhost' IDENTIFIED BY '$mysql_pass'; FLUSH PRIVILEGES;"
        & $mysqld_prog --initialize-insecure --datadir $mysqld_data | Out-Host
    }

    Start-Process $mysqld_prog -ArgumentList "--console --datadir `"$data_dir`"" -WorkingDirectory $work_dir
    println "Wait mysqld ready ..."
    Start-Sleep -Seconds 3

    & $mysql_prog -u root -e $set_pass_cmds | Out-Host
    if ($?) {
        taskkill /f /im mysqld.exe 2>$null
    }
    Pop-Location
}
$actions.init = @{
    php     = {
        $php_dir = Join-Path $install_prefix "php/$php_ver"
        $php_ini = (Join-Path $php_dir 'php.ini')
    
        if (!(Test-Path $php_ini -PathType Leaf) -or $force) {
            $lines, $_ = mod_php_ini (Join-Path $php_dir 'php.ini-production') $true
    
            # xdebug ini
            $lines += '`n'
            $xdebug_lines = Get-Content -Path (Join-Path $wenv_root 'etc/php/xdebug.ini')
            foreach ($line_text in $xdebug_lines) {
                $lines += $line_text
            }
    
            Set-Content -Path $php_ini -Value $lines
        }
    
        # xdebug
        $xdebug_php_ver = "$($php_ver.Major).$($php_ver.Minor)"
        $xdebug_ver = $xdebug_ver_map[$xdebug_php_ver]
        if ([Version]$xdebug_ver -ge [Version]'3.4.1') {
            $xdebug_file_name = "php_xdebug-$xdebug_ver-$xdebug_php_ver-ts-$php_vs-x86_64.dll"
        }
        else {
            $xdebug_file_name = "php_xdebug-$xdebug_ver-$xdebug_php_ver-$php_vs-x86_64.dll"
        }
        download_file -url "https://xdebug.org/files/$xdebug_file_name" -out $(Join-Path $download_path $xdebug_file_name)
        $xdebug_src = Join-Path $download_path $xdebug_file_name
        $xdebug_dest = Join-Path $php_dir 'ext/php_xdebug.dll'
        Copy-Item $xdebug_src $xdebug_dest -Force
    }
    mysql   = {
        mysql_init_db 'mysql'
    }
    mariadb = {
        mysql_init_db 'mariadb'
    }
    redis   = {
        $redis_conf = Join-Path $wenv_root 'etc/redis/redis.windows.conf'
        $redis_conf_in = "$redis_conf.in"
        if (!(Test-Path $redis_conf)) {
            Copy-Item $redis_conf_in $redis_conf -Force
        }
    }
}

function mysql_reset_pass($provider) {
    taskkill /f /im mysqld.exe 2>$null
    $mysql_dir = Join-Path $install_prefix $(eval "$provider/`$${provider}_ver")
    $mysql_bin = Join-Path $mysql_dir 'bin'
    $mysqld_prog = Join-Path $mysql_bin 'mysqld.exe'
    $mysql_prog = Join-Path $mysql_bin 'mysql.exe'

    if ($provider -eq 'mariadb') {
        $data_dir = $mariadb_data
        $work_dir = $mariadb_cwd
    }
    else {
        $data_dir = $mysqld_data
        $work_dir = $mysqld_cwd
    }

    Start-Process $mysqld_prog -ArgumentList "--console --skip-grant-tables --datadir `"$data_dir`"" -WorkingDirectory $work_dir
    println "Wait mysqld ready ..."
    Start-Sleep -Seconds 3
    $mysql_pass1 = Read-Host "Please input new password"
    $mysql_pass2 = Read-Host "input again"
    if ($mysql_pass1 -ne $mysql_pass2) {
        throw "two input passwd mismatch!"
        return
    }

    $set_pass_cmds = "use mysql; FLUSH PRIVILEGES; ALTER user 'root'@'localhost' IDENTIFIED BY '$mysql_pass1'; FLUSH PRIVILEGES;"
    & $mysql_prog -u root -e $set_pass_cmds | Out-Host
    if ($?) {
        taskkill /f /im mysqld.exe 2>$null
    }

    $Global:LASTEXITCODE = 0
}

$actions.passwd = @{
    mysql   = {
        mysql_reset_pass 'mysql'
    }
    mariadb = {
        mysql_reset_pass 'mariadb'
    }
}
$actions.start = @{
    nginx   = {
        $nginx_dir = Join-Path $install_prefix "nginx/$nginx_ver"
        $nginx_prog = Join-Path $nginx_dir 'nginx.exe'
        $nginx_conf = Join-Path $wenv_root "etc/nginx/$nginx_base_ver/nginx.conf"
        $nginx_cwd = Join-Path $wenv_root 'var/nginx'
        Push-Location $nginx_cwd
        &$nginx_prog -t -c $nginx_conf | Out-Host
        Pop-Location
        Start-Process $nginx_prog -ArgumentList "-c `"$nginx_conf`"" -WorkingDirectory $nginx_cwd -WindowStyle Hidden
    }
    php     = {
        $php_dir = Join-Path $install_prefix "php/$php_ver"
        $php_cgi_prog = Join-Path $php_dir 'php-cgi.exe'
        $php_cgi_cwd = Join-Path $wenv_root 'var/php-cgi'
        Start-Process $php_cgi_prog -ArgumentList "-b 127.0.0.1:9000" -WorkingDirectory $php_cgi_cwd -WindowStyle Hidden
    }
    mysql   = {
        $mysql_dir = Join-Path $install_prefix "mysql/$mysql_ver"
        $myslqd_prog = Join-Path $mysql_dir 'bin/mysqld.exe'
        Start-Process $myslqd_prog -ArgumentList "--datadir `"$mysqld_data`"" -WorkingDirectory $mysqld_cwd -WindowStyle Hidden
    }
    mariadb = {
        $mariadb_dir = Join-Path $install_prefix "mariadb/$mariadb_ver"
        $myslqd_prog = Join-Path $mariadb_dir 'bin/mysqld.exe'
        Start-Process $myslqd_prog -ArgumentList "--datadir `"$mariadb_data`"" -WorkingDirectory $mariadb_cwd -WindowStyle Hidden
    }
    redis   = {
        $redis_dir = Join-Path $install_prefix "redis/3.0.504"
        $redis_prog = Join-Path $redis_dir 'redis-server.exe'
        $redis_conf = Join-Path $wenv_root 'etc/redis/redis.windows.conf'
        Start-Process $redis_prog -ArgumentList "$redis_conf" -WorkingDirectory $redis_dir -WindowStyle Hidden
    }
}
$actions.reload = @{
    nginx = {
        $nginx_dir = Join-Path $install_prefix "nginx/$nginx_ver"
        $nginx_prog = Join-Path $nginx_dir 'nginx.exe'
        $nginx_conf = Join-Path $wenv_root "etc/nginx/$nginx_base_ver/nginx.conf"
        $nginx_cwd = Join-Path $wenv_root 'var/nginx'
        Push-Location $nginx_cwd
        &$nginx_prog -s reload -c $nginx_conf | Out-Host
        println "nginx reload done"
        Pop-Location
    }
}
$actions.stop = @{
    nginx   = {
        taskkill /f /im nginx.exe 2>$null
        $Global:LASTEXITCODE = 0
    }
    php     = {
        taskkill /f /im php-cgi.exe 2>$null
        taskkill /f /im intelliphp.ls.exe 2>$null
        $Global:LASTEXITCODE = 0
    }
    mysql   = {
        taskkill /f /im mysqld.exe 2>$null
        $Global:LASTEXITCODE = 0
    }
    mariadb = {
        taskkill /f /im mysqld.exe 2>$null
        $Global:LASTEXITCODE = 0
    }
    redis   = {
        taskkill /f /im redis-server.exe 2>$null
        $Global:LASTEXITCODE = 0
    }
}

$actions.status = @{
    php     = {
        Get-ServiceStatus php-cgi
    }
    nginx   = {
        Get-ServiceStatus nginx
    }
    mysql   = {
        Get-ServiceStatus mysql
    }
    mariadb = {
        Get-ServiceStatus mariadb mysqld
    }
    redis   = {
        Get-ServiceStatus redis
    }
}
