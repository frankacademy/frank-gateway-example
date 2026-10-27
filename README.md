# frank-gateway-example

Two Frank!Gateway instances that talk to each other over mutual TLS (mTLS).

```
curl ──http──> gate ──https + client cert──> rotterdam ──http──> rotterdam-impl
     :80                                     :9443
```

- `gate` receives requests on `http://localhost/rotterdam`. It forwards them
  to `rotterdam` over HTTPS. It sends a client certificate, and it only
  accepts a server certificate that is signed by the CA.
- `rotterdam` only accepts clients that show a certificate signed by the CA.
  It forwards requests to `rotterdam-impl`.
- `rotterdam-impl` is an nginx container that answers
  `Rotterdam implementation reached`.

## Certificates

| File                                 | What                                          | Used by    |
|--------------------------------------|-----------------------------------------------|------------|
| `common/ca.crt`, `common/ca.key`     | Self-signed CA                                | both       |
| `gate/certs/client.crt`, `.key`      | Client certificate, signed by the CA          | gate       |
| `rotterdam/certs/server.crt`, `.key` | Server certificate for `rotterdam`, signed by the CA | rotterdam |
| `bad/bad.crt`, `bad/bad.key`         | Self-signed, so not trusted by the CA         | tests only |

`bad.crt` may be used as a server and as a client certificate, and it has the
same host names as `server.crt`. When it replaces one of the good
certificates, the connection can only fail because the CA did not sign it.

The certificates are valid for 365 days. To create new ones, run
`recreate-certs\run.bat`. It needs `openssl` on the `PATH`.

The containers get the certificates as Docker secrets.
[common/entrypoint.sh](common/entrypoint.sh) turns each secret into an
environment variable, and [gate/apisix.yaml](gate/apisix.yaml) and
[rotterdam/apisix.yaml](rotterdam/apisix.yaml) use those variables.

## Start

```
docker compose up -d --force-recreate
```

`-d` runs the containers in the background, so you can do the tests below in
the same shell. `--force-recreate` makes sure the containers pick up new
certificates, for example after `recreate-certs\run.bat`: Compose does not
notice when only the contents of a secret file change.

Test it:

```
curl.exe http://localhost/rotterdam
```

The response is `Rotterdam implementation reached`.

To see the logs, for example to find out why a connection failed:

```
docker compose logs -f gate rotterdam
```

Leave out `-f` to print the logs once instead of following them.

## Test with bad certificates

Each secret has an environment variable that can point to a different file:
`CA_CRT_FILE`, `CLIENT_CRT_FILE`, `CLIENT_KEY_FILE`, `SERVER_CRT_FILE` and
`SERVER_KEY_FILE`. If a variable is not set, the file in this repository is
used. See the `secrets:` section of [docker-compose.yml](docker-compose.yml).

A container reads its certificates only when it starts. After you change a
variable, recreate that one container with `docker compose up -d
--force-recreate <service>` while the rest keeps running. Run the commands
below from the project root in PowerShell. Use `curl.exe`, because in
Windows PowerShell `curl` is an alias for `Invoke-WebRequest`.

### Bad client certificate

`gate` sends `bad.crt` as its client certificate, and `rotterdam` rejects it.

```powershell
$env:CLIENT_CRT_FILE="./bad/bad.crt"; $env:CLIENT_KEY_FILE="./bad/bad.key"
docker compose up -d --force-recreate gate
curl.exe http://localhost/rotterdam
```

Expected: `502 Bad Gateway`. `docker compose logs rotterdam` shows
`certificate verify failed`. `docker compose logs gate` shows
`tlsv1 alert unknown ca`.

### Bad server certificate

`rotterdam` presents `bad.crt` as its server certificate, and `gate` rejects
it.

```powershell
$env:SERVER_CRT_FILE="./bad/bad.crt"; $env:SERVER_KEY_FILE="./bad/bad.key"
docker compose up -d --force-recreate rotterdam
curl.exe http://localhost/rotterdam
```

Expected: `502 Bad Gateway`. `docker compose logs gate` shows
`upstream SSL certificate verify error: (18:self-signed certificate)`.

### Back to the good certificates

Remove the variables and recreate the containers:

```powershell
Remove-Item Env:CLIENT_CRT_FILE, Env:CLIENT_KEY_FILE, Env:SERVER_CRT_FILE, Env:SERVER_KEY_FILE -ErrorAction SilentlyContinue
docker compose up -d --force-recreate gate rotterdam
curl.exe http://localhost/rotterdam
```

The response is `Rotterdam implementation reached` again.

In Git Bash you can set a variable for one command only:

```sh
CLIENT_CRT_FILE=./bad/bad.crt CLIENT_KEY_FILE=./bad/bad.key docker compose up -d --force-recreate gate
```

## Stop

```
docker compose down
```
