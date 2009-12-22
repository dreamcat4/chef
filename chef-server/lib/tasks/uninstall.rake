require 'rubygems'
require 'rake/gempackagetask'

def sudo_wrapper(command)
  `whoami`.strip! == "root" ? "sudo #{command}" : command
end

task :uninstall do
  sh sudo_wrapper(%{gem uninstall #{GEM} -x -v #{CHEF_SERVER_VERSION}})
end

