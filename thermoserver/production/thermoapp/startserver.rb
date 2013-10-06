#!/usr/bin/env ruby
#We start the thermoserver using the config file from this folder
Kernel.exec("ruby ../../thermoserver.rb ./boot-server.json")
