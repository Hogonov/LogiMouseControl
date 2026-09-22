#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

identity="${LOGI_MOUSE_CONTROL_SIGNING_IDENTITY:-Logi Mouse Control Local Signing}"
keychain="$(security default-keychain -d user | tr -d ' \"')"

find_identity_hash() {
    security find-identity -v -p codesigning "$keychain" 2>/dev/null |
        awk -v name="\"$identity\"" 'index($0, name) { print $2; exit }'
}

if [[ -n "$(find_identity_hash)" ]]; then
    printf 'Постоянная подпись уже настроена: %s\n' "$identity"
    exit 0
fi

tmp_dir="$(mktemp -d /tmp/logimouse-signing.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
umask 077

# A previous interrupted setup may have imported the identity before applying
# its code-signing trust setting. Reuse it instead of creating a new key.
if security find-certificate -c "$identity" -p "$keychain" > "$tmp_dir/certificate.pem" 2>/dev/null; then
    printf 'Найден существующий сертификат; восстанавливаю доверие для подписи кода.\n'
else
    passphrase="$(openssl rand -hex 32)"

    openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
        -subj "/CN=$identity/O=Local Development" \
        -addext 'basicConstraints=critical,CA:FALSE' \
        -addext 'keyUsage=critical,digitalSignature' \
        -addext 'extendedKeyUsage=codeSigning' \
        -keyout "$tmp_dir/private-key.pem" \
        -out "$tmp_dir/certificate.pem"

    openssl pkcs12 -export \
        -name "$identity" \
        -inkey "$tmp_dir/private-key.pem" \
        -in "$tmp_dir/certificate.pem" \
        -out "$tmp_dir/identity.p12" \
        -passout "pass:$passphrase"

    security import "$tmp_dir/identity.p12" \
        -k "$keychain" \
        -f pkcs12 \
        -P "$passphrase" \
        -T /usr/bin/codesign >/dev/null
fi

# User-level trust is enough for this local development identity. macOS may
# show a one-time authorization dialog while this setting is applied.
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$keychain" \
    "$tmp_dir/certificate.pem"

signing_hash="$(find_identity_hash)"
if [[ -z "$signing_hash" ]]; then
    printf '%s\n' 'Не удалось создать действительную локальную подпись.' >&2
    printf '%s\n' 'Откройте «Связку ключей» и проверьте сертификат Logi Mouse Control Local Signing.' >&2
    exit 1
fi

printf 'Готово. Постоянная подпись: %s (%s)\n' "$identity" "$signing_hash"
printf '%s\n' 'Теперь ./scripts/build.sh будет сохранять идентичность приложения между сборками.'
