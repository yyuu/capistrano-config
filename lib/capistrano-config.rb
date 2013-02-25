require "capistrano-config/version"
require "capistrano/configuration/actions/file_transfer_ext"
require "capistrano/configuration/resources/file_resources"
require "erb"

module Capistrano
  module ConfigRecipe
    def self.extended(configuration)
      configuration.load {
        namespace(:config) {
          _cset(:config_path) { release_path }
          _cset(:config_path_local) { File.expand_path('.') }
          _cset(:config_template_path) { File.join(File.expand_path('.'), 'config', 'templates') }
          _cset(:config_files, [])

          _cset(:config_use_shared, false)
          _cset(:config_shared_path) { File.join(shared_path, 'config') }

          _cset(:config_readable_mode, "a+r")
          _cset(:config_readable_files, [])
          _cset(:config_writable_mode, "a+rw")
          _cset(:config_writable_files, [])
          _cset(:config_executable_mode, "a+rx")
          _cset(:config_executable_files, [])
          _cset(:config_remove_files, [])

          desc("Setup shared application config.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            if config_use_shared
              config_files.each do |f|
                safe_put(template(f, :path => config_template_path), File.join(config_shared_path, f), :place => :if_modified)
              end
              execute = []
              execute << "#{try_sudo} chmod #{config_readable_mode} #{config_readable_files.map { |f| File.join(config_shared_path, f).dump }.join(' ')}" unless config_readable_files.empty?
              execute << "#{try_sudo} chmod #{config_writable_mode} #{config_writable_files.map { |f| File.join(config_shared_path, f).dump }.join(' ')}" unless config_writable_files.empty?
              execute << "#{try_sudo} chmod #{config_executable_mode} #{config_executable_files.map { |f| File.join(config_shared_path, f).dump }.join(' ')}" unless config_executable_files.empty?
              execute << "#{try_sudo} rm -f #{config_remove_files.map { |f| File.join(config_shared_path, f).dump }.join(' ')}" unless config_remove_files.empty?
              run(execute.join(" && ")) unless execute.empty?
            end
          }
          after 'deploy:setup', 'config:setup'

          desc("Update applicatin config.")
          task(:update, :roles => :app, :except => { :no_release => true }) {
            transaction {
              update_remotely if fetch(:config_update_remotely, true)
              update_locally if fetch(:config_update_locally, false)
            }
          }
          after 'deploy:finalize_update', 'config:update'

          task(:update_remotely, :roles => :app, :except => { :no_release => true }) {
            if config_use_shared
              execute = []
              config_files.each do |f|
                execute << "( rm -f #{File.join(config_shared_path, f).dump}; " +
                           "ln -sf #{File.join(config_shared_path, f).dump} #{File.join(config_path, f).dump} )"
              end
              run(execute.join(" && ")) unless execute.empty?
            else
              config_files.each do |f|
                safe_put(template(f, :path => config_template_path), File.join(config_path, f), :place => :if_modified)
              end
              execute = []
              execute << "#{try_sudo} chmod #{config_readable_mode} #{config_readable_files.map { |f| File.join(config_path, f).dump }.join(' ')}" unless config_readable_files.empty?
              execute << "#{try_sudo} chmod #{config_writable_mode} #{config_writable_files.map { |f| File.join(config_path, f).dump }.join(' ')}" unless config_writable_files.empty?
              execute << "#{try_sudo} chmod #{config_executable_mode} #{config_executable_files.map { |f| File.join(config_path, f).dump }.join(' ')}" unless config_executable_files.empty?
              execute << "#{try_sudo} rm -f #{config_remove_files.map { |f| File.join(config_path, f).dump }.join(' ')}" unless config_remove_files.empty?
              run(execute.join(" && ")) unless execute.empty?
            end
          }

          task(:update_locally, :roles => :app, :except => { :no_release => true }) {
            config_files.each do |f|
              File.write(File.join(config_path_local, f), template(f, :path => config_template_path))
            end
            execute = []
            execute << "#{try_sudo} chmod #{config_readable_mode} #{config_readable_files.map { |f| File.join(config_path_local, f).dump }.join(' ')}" unless config_readable_files.empty?
            execute << "#{try_sudo} chmod #{config_writable_mode} #{config_writable_files.map { |f| File.join(config_path_local, f).dump }.join(' ')}" unless config_writable_files.empty?
            execute << "#{try_sudo} chmod #{config_executable_mode} #{config_executable_files.map { |f| File.join(config_path_local, f).dump }.join(' ')}" unless config_executable_files.empty?
            execute << "#{try_sudo} rm -f #{config_remove_files.map { |f| File.join(config_path_local, f).dump }.join(' ')}" unless config_remove_files.empty?
            run(execute.join(" && ")) unless execute.empty?
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::ConfigRecipe)
end

# vim:set ft=ruby :
