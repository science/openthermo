@echo off
REM We start the thermoserver using the config file from this folder
start /min "Test server" ..\..\thermoserver\thermoserver.rb .\boot-server.json
