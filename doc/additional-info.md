Commands to create certificates. Run them from the project root.

In Git Bash, first run `export MSYS_NO_PATHCONV=1`. Otherwise Git Bash turns
`-subj "/CN=..."` into a Windows path.

# CA

```
openssl req -x509 -newkey rsa:2048 -nodes -keyout common/ca.key -out common/ca.crt -days 365 -subj "/CN=MyLocalCA"
```

# Server: key + signing request, then sign it with the CA

The CA adds extensions to the certificate when it signs it. They are read from
a small text file, the "extension file", passed with `-extfile`. Each line of
that file is one extension. First create `server.ext` with these two lines:

```
subjectAltName=DNS:kadaster,DNS:localhost
extendedKeyUsage=serverAuth
```

- `subjectAltName`: the host names this certificate is valid for. A client
  checks that the host it connects to is in this list.
- `extendedKeyUsage=serverAuth`: this certificate may only be used by a TLS
  server.

Then create the key and signing request, and sign it:

```
openssl req -newkey rsa:2048 -nodes -keyout kadaster/certs/server.key -out server.csr -subj "/CN=kadaster"
openssl x509 -req -in server.csr -CA common/ca.crt -CAkey common/ca.key -CAcreateserial \
  -out kadaster/certs/server.crt -days 365 -extfile server.ext
```

# Client: same steps, other extension file

Create `client.ext` with this one line. A client certificate needs no host
names; `clientAuth` means it may only be used to identify a TLS client:

```
extendedKeyUsage=clientAuth
```

```
openssl req -newkey rsa:2048 -nodes -keyout gate/certs/client.key -out client.csr -subj "/CN=my-test-client"
openssl x509 -req -in client.csr -CA common/ca.crt -CAkey common/ca.key -CAcreateserial \
  -out gate/certs/client.crt -days 365 -extfile client.ext
```

# Clean up and check

The `.csr` and `.ext` files and `common/ca.srl` are only needed while signing:

```
rm server.csr server.ext client.csr client.ext common/ca.srl
openssl verify -CAfile common/ca.crt -verify_hostname kadaster kadaster/certs/server.crt
openssl verify -CAfile common/ca.crt gate/certs/client.crt
```

To see the extensions in a finished certificate:

```
openssl x509 -in kadaster/certs/server.crt -noout -ext subjectAltName,extendedKeyUsage
```

# Background: extensions in the extension file

## What if `extendedKeyUsage` is left out?

The certificate then has no EKU extension, which (RFC 5280) means it is not
restricted to a purpose.

- Most verifiers accept it: OpenSSL (and so nginx), Java and Go treat a missing
  EKU as "any purpose". The same certificate then works as server and client
  certificate.
- Some verifiers are stricter. Apple platforms want `serverAuth` in TLS server
  certificates, and public CAs must include an EKU (CA/Browser Forum rules).
- Adding an EKU restricts the certificate. With only `serverAuth`, the
  certificate fails when it is presented as a client certificate in mTLS.
- `keyUsage`, if present, is still enforced without an EKU.
- An EKU on a CA certificate limits what it can issue. Some verifiers (Windows,
  NSS) apply it to the whole chain.

For a demo, leaving it out is fine. Otherwise set it explicitly.

## Allowing both server and client usage

Separate the values with a comma. Add `critical,` to make verifiers reject the
certificate if they do not understand the extension:

```
extendedKeyUsage = serverAuth, clientAuth
extendedKeyUsage = critical, serverAuth, clientAuth
```

A typical extension file for a leaf certificate that is used both ways:

```
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = DNS:example.local
```

The result shows as `TLS Web Server Authentication, TLS Web Client
Authentication` under "X509v3 Extended Key Usage" in
`openssl x509 -in cert.pem -noout -text`.

## `basicConstraints` and `keyUsage`

`basicConstraints` says whether the certificate may act as a CA.

- `CA:FALSE`: end-entity (leaf) certificate. It cannot sign other certificates,
  so a stolen key cannot be used to issue trusted certificates.
- `CA:TRUE`: root or intermediate CA. `pathlen:N` limits how many intermediate
  CAs may sit below it, for example `CA:TRUE, pathlen:0`.
- A certificate that signed another one must be `CA:TRUE`, or verification
  fails.

`keyUsage` limits which cryptographic operations the key may be used for. It is
lower-level than EKU.

- `digitalSignature`: the key may sign data. TLS needs this for the handshake
  signature.
- `keyEncipherment`: the key may encrypt other keys. Only needed for RSA key
  exchange in TLS 1.2 and older. Harmless for RSA keys, can be dropped for EC
  keys.
- `keyCertSign`, `cRLSign`: CA only. They allow signing certificates and
  revocation lists, for example `keyUsage = critical, keyCertSign, cRLSign`.

`keyUsage` says what the key can do, and `extendedKeyUsage` narrows that to
what the application protocol may use it for. Verifiers check both, so a
certificate needs a matching `keyUsage` and EKU for its purpose.
