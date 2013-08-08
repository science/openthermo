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
    rescue ThermoRuntimeError => e
      puts "Runtime exception encountered. Retrying.."
      puts "  Exception class: #{e.class.to_s}. Msg: #{e.message}.\n  Backtrace: #{e.backtrace}"
    rescue ThermoCriticalError => e
      puts "***  Critical failure encountered. Retrying  ***"
      puts "  Exception class: #{e.class.to_s}. Msg: #{e.message}.\n  Backtrace: #{e.backtrace}"
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
