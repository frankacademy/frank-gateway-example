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
