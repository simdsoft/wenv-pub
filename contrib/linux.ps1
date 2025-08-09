<# Ubuntu Linux

Notice for Redis

modify port 0 in /etc/redis/redis.conf
 redis many tcp TIME_WAIT on aliyun
 reason: 
   ps -ef | grep pmlogger will write many keys into redis
 solution:
   1. sudo ss -K state TIME-WAIT
   2. sudo sysctl -w net.ipv4.tcp_tw_reuse=1
   3. sudo sysctl -w net.ipv4.tcp_fin_timeout=10
 modify default port 6379 to 6380
 config requirepass in redis.conf
 

Notice for logrotate
 /etc/logrotate.d
 /var/log/nginx/access.log {
    daily              # 每天轮转日志
    rotate 7          # 保留 7 天的日志，超过的自动删除
    compress          # 压缩旧日志以节省空间
    missingok         # 忽略不存在的日志文件，不报错
    notifempty        # 如果日志为空，则不处理
    create 0640 www-data adm  # 设定新日志的权限和所有者
    postrotate
        systemctl reload nginx > /dev/null 2>&1  # 轮转后重载 Nginx，使其继续记录日志
    endscript
}

postrotate
   invoke-rc.d nginx rotate >/dev/null 2>&1
endscript

logrotate -d /etc/logrotate.d/nginx
#>

$Script:nginx_user = 'nginx'
$Script:mysql_user = 'mysql' # DO NOT MODIFY
$Script:php_user = 'www-data' # DO NOT MODIFY

function Get-ServiceStatus($service_name) {
    if ($verbose) {
        sudo systemctl status $service_name
    } else {
        $verbose_status = "$(sudo systemctl status $service_name)"
        if ($verbose_status.Contains('Active: active (running)')) {
            $brief_status = 'running'
        } elseif($verbose_status.Contains('Active: inactive (dead)')) {
            $brief_status = 'dead'
        } elseif($verbose_status.Contains('Active: failed')) {
            $brief_status = 'failed'
        }
        else {
            $brief_status = 'unknown'
        }
        println "$service_name status: $brief_status"
    }
}

$actions.fetch = @{
    nginx   = {
        $nginx_dir = "$install_prefix/nginx/$nginx_ver"
        if (!(Test-Path $nginx_dir -PathType Container)) {
            sudo apt install --allow-unauthenticated --yes make
            fetch_pkg -url "https://nginx.org/download/nginx-${nginx_ver}.tar.gz" -prefix 'cache'
            $nginx_src = Join-Path $download_path "nginx-${nginx_ver}"
            Push-Location $nginx_src
            sudo apt install --allow-unauthenticated --yes gcc make libz-dev libpcre3 libpcre3-dev libssl-dev
            $nginx_conf_dir = Join-Path $wenv_root "etc/nginx/$nginx_base_ver"
            $nginx_logs_dir = Join-Path $wenv_root 'var/nginx/logs'
            $nginx_tmp_dir = "$wenv_root/var/nginx/temp"
            # refer: https://nginx.org/en/docs/configure.html
            ./configure --with-http_ssl_module `
                --with-http_v2_module `
                --with-http_v3_module `
                --prefix=$nginx_dir `
                --conf-path=$nginx_conf_dir/nginx.conf `
                --error-log-path=$nginx_logs_dir/error.log `
                --pid-path=$nginx_logs_dir/nginx.pid `
                --lock-path=$nginx_logs_dir/nginx.lock `
                --http-log-path=$nginx_logs_dir/access.log `
                --http-client-body-temp-path=$nginx_tmp_dir/client_body_temp `
                --http-proxy-temp-path=$nginx_tmp_dir/proxy_temp `
                --http-fastcgi-temp-path=$nginx_tmp_dir/fastcgi_temp `
                --http-uwsgi-temp-path=$nginx_tmp_dir/uwsgi_temp `
                --http-scgi-temp-path=$nginx_tmp_dir/scgi_temp
            make ; make install
            Pop-Location
        }
        if (!(Test-Path '/usr/lib/systemd/system/nginx.service')) {
            $nginx_service_in = Join-Path $wenv_root "etc/nginx/$nginx_base_ver/nginx.service.in"
            $nginx_service_content = [IO.File]::ReadAllText($nginx_service_in)
            $nginx_service_content = $nginx_service_content.Replace('@NGINX_INST_DIR@', $nginx_dir)
            $nginx_service_tmp_file = Join-Path $download_path 'nginx.service'
            [IO.File]::WriteAllText($nginx_service_tmp_file, $nginx_service_content)
            sudo cp $nginx_service_tmp_file '/usr/lib/systemd/system/nginx.service'
            sudo systemctl enable nginx
        }
        else {
            println 'nginx.service already exists'
        }
    }
    php     = {
        # ensure we can install old releases of php on ubuntu
        $php_ppa = $(grep -ri '^deb.*ondrej/php' /etc/apt/sources.list /etc/apt/sources.list.d/)
        if (!$php_ppa) {
            sudo LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php
            sudo apt update
        }

        $php_pkg = "php$php_base_ver"
        sudo apt install --allow-unauthenticated --yes $php_pkg-fpm $php_pkg-mysql $php_pkg-curl $php_pkg-gd $php_pkg-gmp php-pear
        sudo systemctl enable "php$php_base_ver-fpm"
    }
    mysql   = {
        # sudo apt install mysql-server
        # we use offical deb to install latest mysql version 9.1.0
        $os_info = $PSVersionTable.OS.Split(' ')
        $os_name = $os_info[0].ToLower()
        $os_ver = $os_info[1].Split('.')
        $os_id = "$os_name$($os_ver[0]).$($os_ver[1])"
        $mysql_server_deb_bundle = "mysql-server_$mysql_ver-1${os_id}_amd64.deb-bundle.tar"
        if ($mysql_ver -eq $mysql_latest) {
            fetch_pkg "https://cdn.mysql.com//Downloads/MySQL-$($mysql_ver.Major).$($mysql_ver.Minor)/$mysql_server_deb_bundle" -prefix "cache/mysql-$mysql_ver"
        }
        else {
            fetch_pkg "https://downloads.mysql.com/archives/get/p/23/file/$mysql_server_deb_bundle" -prefix "cache/mysql-$mysql_ver"
        }

        $mysqld_cmd = Get-Command mysqld -ErrorAction SilentlyContinue
        if (!$mysqld_cmd) {
            # old ubuntu 22.04 maybe libaio1 ?
            $aio_package_name = 'libaio-dev'
            Push-Location $download_path/mysql-$mysql_ver
            sudo apt install --allow-unauthenticated --yes $aio_package_name libnuma-dev libmecab2
            sudo dpkg -i mysql-common_*.deb
            sudo dpkg -i mysql-community-client-plugins*amd64.deb
            sudo dpkg -i mysql-community-client-core*amd64.deb
            sudo dpkg -i mysql-community-client_*amd64.deb
            sudo dpkg -i libmysqlclient*amd64.deb
            sudo dpkg -i mysql-community-server-core*amd64.deb
            sudo dpkg -i mysql-client_*amd64.deb
            sudo dpkg -i mysql-community-server_*amd64.deb
            sudo dpkg -i mysql-server_*amd64.deb
            sudo dpkg --configure -a
            sudo systemctl enable mysql
            Pop-Location
        }
    }
    mariadb = {
        # https://mariadb.com/kb/en/installing-mariadb-binary-tarballs/
        $desired_file_name = "mariadb-$mariadb_ver-linux-systemd-x86_64.tar.gz"
        $res = ConvertFrom-Json $(Invoke-WebRequest -Uri "https://downloads.mariadb.org/rest-api/mariadb/$mariadb_ver")
        $file_info = $null
        foreach($item in $res.release_data.$mariadb_ver.files) {
            if ($item.os -eq 'Linux' -and $item.cpu -eq 'x86_64' -and $item.file_name -eq $desired_file_name) {
                $file_info = $item
                break
            }
        }

        if(!$file_info) {
            throw "Request file download url for $desired_file_name fail!"
        }

        fetch_pkg $file_info.file_download_url -exrep "mariadb-$mariadb_ver-linux-systemd-x86_64=mariadb-$mariadb_ver" -prefix '/usr/local' -sudo $True -checksum $file_info.checksum.md5sum
        $mariadb_inst_dir = "/usr/local/mariadb-$mariadb_ver"
        if (!(Test-Path '/usr/local/mysql')) {
            sudo ln -s $mariadb_inst_dir '/usr/local/mysql'
        }
    }
    redis = {
        # config /etc/redis/redis.conf
        # maxmemory 33554432
        # bind 127.0.0.1
        sudo apt install redis-server --allow-unauthenticated --yes
    }
    certbot = {
        println 'certbot: TODO'
    }
}
$actions.init = @{
    php   = {
        println "php init: nothing need to do"
    }
    mysql = {
        # MySQL 9.0+
        $my_conf_dst_file = '/etc/mysql/mysql.conf.d/mysqld.cnf'
        $my_conf_lines = Get-Content $my_conf_dst_file
        if ($my_conf_lines.Contains('bind-address = 127.0.0.1')) {
            println 'mysql init: nothing need to do'
            return
        }
        $my_conf_file = "$wenv_root/etc/mysql/my.ini"
        $conf_lines = Get-Content $my_conf_file
        foreach ($line_text in $conf_lines) {
            if ($line_text -match '^\s*#') {
                continue
            }
            if ($line_text -match '^\s*\[mysqld\]') {
                continue
            }
            if (!$line_text) {
                continue
            }
            println "mysql init: add config: $line_text to mysqld.conf"
            $my_conf_lines += $line_text
        }
        $tmp_conf_file = Join-Path $download_path 'mysqld.cnf'
        Set-Content -Path $tmp_conf_file -Value $my_conf_lines -Encoding utf8
        sudo cp $tmp_conf_file $my_conf_dst_file
    }
    mariadb = {
        if (!$(cat /etc/passwd | grep $mysql_user)) {
            println "Creating mysql user: $mysql_user ..."
            sudo useradd -M -s /sbin/nologin $mysql_user
        }

        if(!(Test-Path '/etc/mariadb/my.cnf')) {
	    sudo mkdir -p /etc/mariadb
            sudo cp "$wenv_root/etc/mariadb/my.cnf" '/etc/mariadb/my.cnf'
        }

        if (!(Test-Path '/usr/lib/systemd/system/mariadb.service')) {
            $total_mods = 0
            $mariadb_inst_dir = "/usr/local/mariadb-$mariadb_ver"
            $lines = Get-Content "$mariadb_inst_dir/support-files/systemd/mariadb.service"
            for($i = 0; $i -lt $lines.Count ; ++$i) {
                $line_text = $lines[$i]
                $line_mods = 0
                if ($line_text.StartsWith('ExecStart=')) {
                    $line_text = $line_text.Replace('$MYSQLD_OPTS', '--defaults-file=/etc/mariadb/my.cnf')
                    ++$line_mods
                }
                if ($line_mods) {
                    $lines[$i] = $line_text
                    $total_mods += $line_mods
                }
            }
            $tmp_mariadb_service_file = "$download_path/mariadb.service"
            Set-Content -Path $tmp_mariadb_service_file  -Value $lines
            if (!(Test-Path '/usr/lib/systemd/system/mariadb.service' -PathType Leaf)) {
               println "Copy $tmp_mariadb_service_file ==> /usr/lib/systemd/system/mariadb.service ..."
	           sudo cp $tmp_mariadb_service_file '/usr/lib/systemd/system/mariadb.service'
            }
            
            sudo mkdir /var/run/mariadb
            sudo chown mysql:mysql /run/mariadb
            sudo systemctl enable mariadb
        }
        # refer: https://mariadb.com/kb/en/mariadb-install-db/
        # !!! must install to /usr/local or /opt/ and don't pass basedir and datadir, otherwise will report
        # Can't create/write to file '/home/adminx/wenv/cache/mariadb-11.7.2-linux-systemd-x86_64/data/aria_log_control' (Errcode: 13 "Permission denied")
        sudo bash -c "cd /usr/local/mysql; ./scripts/mariadb-install-db --user=$mysql_user --defaults-file=/etc/mariadb/my.cnf --skip-test-db --verbose ; chown -R root . ; chown -R mysql data ; cd -"
        
        println "execute mariadb-secure-installation ... , or you can skip via press Ctrl+C/Z and execute in the future"
        sudo systemctl start mariadb
        sudo /usr/local/mysql/bin/mariadb-secure-installation --basedir=/usr/local/mysql --defaults-file=/etc/mariadb/my.cnf
        sudo systemctl stop mariadb
        println "please consider add /usr/local/mysql/bin to your user profile: ~/.bashrc"
    }
}

$actions.start = @{
    nginx = {
        sudo systemctl start nginx
    }
    php   = {
        sudo systemctl start "php$php_base_ver-fpm"
    }
    mysql = {
        sudo systemctl start mysql
    }
    mariadb = {
        sudo systemctl start mariadb
    }
    redis = {
        sudo systemctl start redis
    }
}

$actions.status = @{
    php   = {
        Get-ServiceStatus "php$php_base_ver-fpm"
    }
    nginx = {
        Get-ServiceStatus nginx
    }
    mysql = {
        Get-ServiceStatus mysql
    }
    mariadb = {
        Get-ServiceStatus mariadb
    }
    redis = {
        Get-ServiceStatus redis
    }
}

$actions.reload = @{
    nginx = {
        sudo systemctl reload nginx
    }
}

$actions.enable = @{
    nginx = {
        sudo systemctl enable nginx
    }
    php   = {
        sudo systemctl enable "php$php_base_ver-fpm"
    }
    mysql = {
        sudo systemctl enable mysql
    }
    mariadb = {
        sudo systemctl enable mariadb
    }
    redis = {
        sudo systemctl enable redis
    }
}

$actions.disable = @{
    nginx = {
        sudo systemctl disable nginx
    }
    php   = {
        sudo systemctl disable "php$php_base_ver-fpm"
    }
    mysql = {
        sudo systemctl disable mysql
    }
    mariadb = {
        sudo systemctl disable mariadb
    }
    redis = {
        sudo systemctl disable redis
    }
}

$actions.stop = @{
    nginx = {
        sudo systemctl stop nginx
    }
    php   = {
        sudo systemctl stop "php$php_base_ver-fpm"
    }
    mysql = {
        sudo systemctl stop mysql
    }
    mariadb = {
        sudo systemctl stop mariadb
    }
    redis = {
        sudo systemctl stop redis
    }
}
