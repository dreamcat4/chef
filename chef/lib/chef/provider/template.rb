#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider/file'
require 'chef/mixin/template'
require 'chef/mixin/checksum'
require 'chef/mixin/find_preferred_file'
require 'chef/rest'
require 'chef/file_cache'
require 'uri'
require 'tempfile'

class Chef
  class Provider
    class Template < Chef::Provider::File
      
      include Chef::Mixin::Checksum
      include Chef::Mixin::Template
      include Chef::Mixin::FindPreferredFile
      
      def action_create
        raw_template_file = nil
        
        cookbook_name = @new_resource.cookbook || @new_resource.cookbook_name
        
        Chef::Log.debug("looking for template #{@new_resource.source} in cookbook #{cookbook_name.inspect}")
        
        cache_file_name = "cookbooks/#{cookbook_name}/templates/default/#{@new_resource.source}"
        template_cache_name = "#{cookbook_name}_#{@new_resource.source}"
        
        if Chef::Config[:solo]
          filename = find_preferred_file(
            cookbook_name,
            :template,
            @new_resource.source,
            @node[:fqdn],
            @node[:platform],
            @node[:platform_version]
          )
          Chef::Log.debug("Using local file for template:#{filename}")
          cache_file_name = Pathname.new(filename).relative_path_from(Pathname.new(Chef::Config[:file_cache_path])).to_s
        elsif @node.run_state[:template_cache].has_key?(template_cache_name)
          Chef::Log.debug("I have already fetched the template for #{@new_resource} once this run, not checking again.")
          template_updated = false
        else
          r = Chef::REST.new(Chef::Config[:template_url])
          
          current_checksum = nil
          
          if Chef::FileCache.has_key?(cache_file_name)
            current_checksum = self.checksum(Chef::FileCache.load(cache_file_name, false))
          else
            Chef::Log.debug("Template #{@new_resource} is not in the template cache")
          end
          
          template_url = generate_url(
            @new_resource.source, 
            "templates",
            {
              :checksum => current_checksum
            }
          )
          
          template_updated = true
          begin
            raw_template_file = r.get_rest(template_url, true)
          rescue Net::HTTPRetriableError => e
            if e.response.kind_of?(Net::HTTPNotModified)
              template_updated = false
              Chef::Log.debug("Cached template for #{@new_resource} is unchanged")
            else
              raise e
            end
          end
          
          # We have checked the cache for this template this run
          @node.run_state[:template_cache][template_cache_name] = true
        end  
        
        if template_updated
          Chef::Log.debug("Updating template for #{@new_resource} in the cache")
          Chef::FileCache.move_to(raw_template_file.path, cache_file_name)
        end

        context = {}
        context.merge!(@new_resource.variables)
        context[:node] = @node
        template_file = render_template(Chef::FileCache.load(cache_file_name), context)

        update = false
      
        if ::File.exists?(@new_resource.path)
          @new_resource.checksum(self.checksum(template_file.path))
          if @new_resource.checksum != @current_resource.checksum
            Chef::Log.debug("#{@new_resource} changed from #{@current_resource.checksum} to #{@new_resource.checksum}")
            Chef::Log.info("Updating #{@new_resource} at #{@new_resource.path}")
            update = true
          end
        else
          Chef::Log.info("Creating #{@new_resource} at #{@new_resource.path}")
          update = true
        end
      
        if update
          backup
          FileUtils.cp(template_file.path, @new_resource.path)
          @new_resource.updated = true
        else
          Chef::Log.debug("#{@new_resource} is unchanged")
        end
              
        set_owner if @new_resource.owner != nil
        set_group if @new_resource.group != nil
        set_mode if @new_resource.mode != nil
      end
      
      def action_create_if_missing
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug("Template #{@new_resource} exists, taking no action.")
        else
          action_create
        end
      end
      
    end
  end
end
