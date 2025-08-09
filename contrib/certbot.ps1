# Not used yet, TODO
$actions.req = @{
    'cert' = {
        # certbot-2.x (2.11.1)
        # certbot renew --force-renewal

        $cert_req = 'certbot certonly'
        $cert_req += ' --dns-aliyun-credentials /etc/letsencrypt/aliyun.ini'
        $cert_req += ' --dns-aliyun-propagation-seconds 120'
        $cert_req += ' --preferred-challenges dns-01'
        $cert_req += ' -d simdsoft.com -d *.simdsoft'
        $cert_req += ' -d x-studio.net -d *.x-studio.net'

        bash -c $cert_req
    }
}
