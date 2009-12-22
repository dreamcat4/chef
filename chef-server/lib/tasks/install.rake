require 'rubygems'
require 'rake/gempackagetask'

def sudo_wrapper(command)
  `whoami`.strip! == "root" ? "sudo #{command}" : command
end

task :install => :package do
  sh sudo_wrapper(%{gem install pkg/#{GEM}-#{CHEF_SERVER_VERSION} --no-rdoc --no-ri})
end

