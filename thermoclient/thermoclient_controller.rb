# copyright 2013 Steve Midgley 
# http://www.gnu.org/licenses/gpl-3.0.txt

#     This file is part of the Open Thermostat project.

#     The Open Thermostat project is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.

#     The Open Thermostat project is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.

#     You should have received a copy of the GNU General Public License
#     along with The Open Thermostat project.  
#     If not, see <http://www.gnu.org/licenses/>.

# run thermoclient repeatedly, try to turn off heater when thermoclient exits

# amount of time to re-run thermoclient before exiting
DEFAULT_RUN_TIME = '24 hours'
DEFAULT_INTERVAL_BETWEEN_RUNS = '15 seconds'
DEFAULT_WORKING_FOLDER = './config'

require './thermoclient.rb'
require 'chronic'

start_time = Time::now
end_time = Chronic.parse(DEFAULT_RUN_TIME+ " after now")
wait_time = (Time::now - Chronic.parse(DEFAULT_INTERVAL_BETWEEN_RUNS + " after now")).abs
working_dir = DEFAULT_WORKING_FOLDER

Dir.chdir(working_dir)
thermostat = Thermo::Thermostat.new
puts "Starting Thermoclient and processing remote schedule file..."
puts Time::now
begin
  while start_time < end_time
    begin
      thermostat.process_schedule
      sleep(wait_time)
    # rescue and alert from various exceptions
    # create a new thermostat object to try again
    rescue Thermo::ThermoRuntimeError => e
      puts "Runtime exception encountered. Retrying.."
      puts "  Exception class: #{e.class.to_s}. Msg: #{e.message}.\n  Backtrace: #{e.backtrace}"
      thermostat = Thermo::Thermostat.new
    rescue Thermo::ThermoCriticalError => e
      puts "***  Critical failure encountered. Retrying  ***"
      puts "  Exception class: #{e.class.to_s}. Msg: #{e.message}.\n  Backtrace: #{e.backtrace}"
      thermostat = Thermo::Thermostat.new
    rescue e
      puts "***  Unknown failure encountered. Retrying  ***"
      puts "  Exception class: #{e.class.to_s}. Msg: #{e.message}.\n  Backtrace: #{e.backtrace}"
      thermostat = Thermo::Thermostat.new
    end
  end
# on any exception or exit, attempt to turn off heater
ensure
  thermostat = nil
  thermo_rescue  = Thermo::Thermostat.new
  thermo_rescue.set_heater_state(false)
end
puts "Ran to completion successfully at #{Time::now}"
puts "  started: #{start_time} // ended: #{end_time}"
