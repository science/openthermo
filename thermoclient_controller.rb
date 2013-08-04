# run thermoclient, try to turn off heater when thermoclient exits
ENV["thermo_run_mode"] = 'testing'

# amount of time to re-run thermoclient before exiting
DEFAULT_RUN_TIME = '12 hours'
DEFAULT_INTERVAL_BETWEEN_RUNS = '1 minute'

require './thermoclient.rb'
require 'chronic'

thermostat = Thermo::Thermostat.new
start_time = Time::now
end_time = Chronic.parse(DEFAULT_RUN_TIME+ " after now")
wait_time = (Time::now - Chronic.parse(DEFAULT_INTERVAL_BETWEEN_RUNS + " after now")).abs
begin
  while start_time < end_time
    puts "Processing schedule"
    thermostat.process_schedule
    puts "Sleeping"
    sleep(wait_time)
  end
# on any exception attempt to turn off heater
rescue Exception => e
  begin
    thermo_rescue  = Thermo::Thermostat.new
    thermo_rescue.set_heater_state(false)
  ensure
    raise e
  end
end
puts "Ran to completion successfully at #{Time::now}"
puts "  started: #{start_time} // ended: #{end_time}"
