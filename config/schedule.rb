# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

set :environment, "production"
set :output, {:error => "log/midwest_error_log.log", :standard => "log/midwest_error_log.log"}

every :saturday, :at => '1am' do
  rake "scraper:midwest"
end

# every 1.minutes do
#   rake "scraper:pike"
# end


# Learn more: http://github.com/javan/whenever
