@echo off
rem Recreates all certificates of this project. Run from any directory.
rem
rem ca     : self-signed root CA                    -> common\ca.crt, common\ca.key
rem server : signed by ca, for rotterdam            -> rotterdam\certs\server.crt, .key
rem client : signed by ca, for gate                 -> gate\certs\client.crt, .key
rem bad    : self-signed, not trusted by anything   -> bad\bad.crt, bad\bad.key
rem
rem bad is valid for both server and client use and has the same host names as
rem server. Replacing server or client by bad should therefore only fail
rem because bad is not signed by ca.

setlocal
set "EXT=%~dp0"
cd /d "%~dp0.." || exit /b 1

set "WORK=%TEMP%\recreate-certs-%RANDOM%"
mkdir "%WORK%" || exit /b 1
if not exist bad mkdir bad || exit /b 1

rem The self-signed certificates are made in two steps (request, then sign with
rem its own key) instead of with "openssl req -x509". That way all extensions
rem come from the .ext files in this folder, and the v3_ca section of the
rem default openssl.cnf is not needed.

echo === ca
openssl req -newkey rsa:2048 -nodes -keyout common/ca.key -out "%WORK%/ca.csr" -subj "/CN=MyLocalCA" || goto :fail
openssl x509 -req -in "%WORK%/ca.csr" -key common/ca.key ^
  -out common/ca.crt -days 365 -extfile "%EXT%ca.ext" || goto :fail

echo === server
openssl req -newkey rsa:2048 -nodes -keyout rotterdam/certs/server.key -out "%WORK%/server.csr" -subj "/CN=rotterdam" || goto :fail
openssl x509 -req -in "%WORK%/server.csr" -CA common/ca.crt -CAkey common/ca.key -CAserial "%WORK%/ca.srl" -CAcreateserial ^
  -out rotterdam/certs/server.crt -days 365 -extfile "%EXT%server.ext" || goto :fail

echo === client
openssl req -newkey rsa:2048 -nodes -keyout gate/certs/client.key -out "%WORK%/client.csr" -subj "/CN=gate" || goto :fail
openssl x509 -req -in "%WORK%/client.csr" -CA common/ca.crt -CAkey common/ca.key -CAserial "%WORK%/ca.srl" -CAcreateserial ^
  -out gate/certs/client.crt -days 365 -extfile "%EXT%client.ext" || goto :fail

echo === bad
openssl req -newkey rsa:2048 -nodes -keyout bad/bad.key -out "%WORK%/bad.csr" -subj "/CN=bad" || goto :fail
openssl x509 -req -in "%WORK%/bad.csr" -key bad/bad.key ^
  -out bad/bad.crt -days 365 -extfile "%EXT%bad.ext" || goto :fail

echo === check
openssl verify -CAfile common/ca.crt -verify_hostname rotterdam -purpose sslserver rotterdam/certs/server.crt || goto :fail
openssl verify -CAfile common/ca.crt -purpose sslclient gate/certs/client.crt || goto :fail
openssl verify -CAfile common/ca.crt bad/bad.crt >nul 2>&1 && (
  echo bad\bad.crt is trusted by ca, it should not be
  goto :fail
)
echo bad\bad.crt: not trusted by ca, as intended

rmdir /s /q "%WORK%"
echo Done. Restart with: docker compose up --build --force-recreate
exit /b 0

:fail
rmdir /s /q "%WORK%"
echo FAILED
exit /b 1
