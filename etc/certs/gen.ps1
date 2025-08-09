# PowerShell version of the certificate generation script
# References:
#   - https://www.baeldung.com/openssl-self-signed-cert
#   - https://gist.github.com/Barakat/675c041fd94435b270a25b5881987a30
#   - https://stackoverflow.com/questions/18233835/creating-an-x509-v3-user-certificate-by-signing-csr
#   - https://certificatetools.com/


# Accept an optional argument for is_v1 (default is "false")
param (
    [switch]$is_v1
)

function YearsToDays {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$years
    )
    $now = Get-Date
    $expire = $now.AddYears($years)
    # TotalDays returns a double so we floor it for whole days
    $days = [math]::Floor(($expire - $now).TotalDays)
    return $days
}

# Certificate settings
$key_bits    = 2048
$common_name = "*.simdsoft.com"
$hash_alg    = "-sha384"
$issued_org  = "Simdsoft Limited"

# Issuer information
$issuer_valid_years = 1001
$issuer_org         = "Simdsoft Limited"
$issuer_name        = "Simdsoft RSA CA $issuer_valid_years"
$issuer_subj        = "/C=CN/O=$issuer_org/CN=$issuer_name"

$valid_years = $issuer_valid_years

# Create Self-Signed Root CA (Certificate Authority)
$issuer_valid_days = YearsToDays -years $issuer_valid_years

if (-Not (Test-Path "ca-prk.pem")) {
    if (!$is_v1) {
        # Generate new key and self-signed certificate in one step
        & openssl req -newkey "rsa:$key_bits" $hash_alg -nodes -keyout "ca-prk.pem" -x509 -days $issuer_valid_days -out "ca-cer.pem" -subj "$issuer_subj"
        Copy-Item "ca-cer.pem" -Destination "ca-cer.crt"
    }
    else {
        # Generate separate key, CSR, and then sign the certificate
        & openssl genrsa -out "ca-prk.pem" $key_bits
        & openssl req -new $hash_alg -key "ca-prk.pem" -out "ca-csr.pem" -subj "$issuer_subj"
        & openssl x509 -req -signkey "ca-prk.pem" -in "ca-csr.pem" -out "ca-cer.pem" -days $issuer_valid_days
    }
}

# Server certificate generation
$valid_days = YearsToDays -years $valid_years

# 1. Generate unencrypted 2048-bit RSA private key for the server and CSR
& openssl req -newkey "rsa:$key_bits" $hash_alg -nodes -keyout "server.key" -out "server.csr" -subj "/C=CN/O=$issued_org/CN=$common_name"

# 2. Sign the server certificate with our RootCA
if (!$is_v1) {
    # For browser compatibility, include subjectAltName via an extfile.
    $v3ext_file = Join-Path (Get-Location) "v3.ext"
    & openssl x509 -req $hash_alg -in "server.csr" -CA "ca-cer.pem" -CAkey "ca-prk.pem" -CAcreateserial -out "server.crt" -days $valid_days -extfile $v3ext_file
}
else {
    & openssl x509 -req $hash_alg -in "server.csr" -CA "ca-cer.pem" -CAkey "ca-prk.pem" -CAcreateserial -out "server.crt" -days $valid_days
}

# Check if the certificate is signed properly
& openssl x509 -in "server.crt" -noout -text
