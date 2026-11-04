@echo off
rem Ativa Suporte - instalar no celular pelo cabo USB (uso do T.I.).
rem Deixe o arquivo .apk nesta mesma pasta e clique duas vezes aqui.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-por-cabo.ps1" %*
