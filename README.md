## wenv - An all in one web environment(nginx + mysql/mariadb + php) supporting both windows, ubuntu, macos

[![Latest Release](https://img.shields.io/github/v/release/simdsoft/wenv?label=release)](https://github.com/simdsoft/wenv/releases)

## Support platforms

- ✅ Windows
- ✅ Ubuntu
- ✅ macOS (You need install brew first)

## Quick Start

### install and start service
1. Install [powershell 7](https://github.com/PowerShell/PowerShell) and open pwsh terminal
2. Clone https://github.com/simdsoft/wenv.git and goto to root directory of wenv
3. `./wenv install`
4. `./etc/certs/gen.sh`, on windows, please enter wsl to execute script `gen.sh`
5. `./wenv start`

### visit local web

1. Add domain `sandbox.wenv.dev` to your system hosts
2. Install `./etc/certs/ca-cer.crt` to `Trusted Root Certificate Authorities` of current user
3. visit web on your browser
   - http:
      - http://localhost/phpinfo.php to check does php works
      - http://localhost/phpmyadmin to manage database
   - https
      - https://sandbox.wenv.dev/phpinfo.php to check does php works
      - https://sandbox.wenv.dev/phpmyadmin to manage database
   visit by curl.exe: `curl -v --ssl-no-revoke https://sandbox.wenv.dev/phpinfo.php`
Note:  

if wenv was moved to other location or you modify domain name in `local.properties`, 
then please re-run `wenv init nginx -f` and restart nginx by `wenv restart nginx`

## wenv-cmdline usage

`wenv action_name targets`

- *`action_name`*: `install`, `start`, `stop`, `restart`
- *`targets`*(optional): possible values: `all`, `nginx`, `php`, `phpmyadmin`, `mysql`

examples:  

- `wenv install`: install WNMP on windows or LNMP on ubuntu linux
- `wenv start`: start nginx, mysqld, php-cgi
- `wenv stop`: stop nginx, mysqld, php-cgi
- `wenv restart`: restart nginx, mysqld, php-cgi
- `wenv passwd mysql`: reset mysqld password

Note:  

- nginx, mysql runas current user
- php runas root

## Export DB from aliyun

1. Use aliyun DMS, ensure follow option was checked

   - Data And Structure
   - Compress insert statements


2. Aliyun website control console

   - Delete: `FOREIGN_KEY_CHECKS` statements at HAED and tail
   - Delete UTF-8 BOM of file
