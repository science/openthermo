# run thermoclient repeatedly, try to turn off heater when thermoclient exits

# amount of time to re-run thermoclient before exiting
DEFAULT_RUN_TIME = '12 hours'
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
    #puts "Processing schedule"
    thermostat.process_schedule
    #puts "Sleeping"
    sleep(wait_time)
  end
# on any exception attempt to turn off heater
rescue Exception => e
  begin
    thermostat = nil
    thermo_rescue  = Thermo::Thermostat.new
    thermo_rescue.set_heater_state(false)
  ensure
    raise e
  end
end
puts "Ran to completion successfully at #{Time::now}"
puts "  started: #{start_time} // ended: #{end_time}"
