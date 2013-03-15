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
          _cset(:config_path_local) { File.expand_path(".") }
          _cset(:config_template_path) { File.expand_path("config/templates") }
          _cset(:config_files, [])

          _cset(:config_use_shared, false)
          _cset(:config_shared_path) { File.join(shared_path, "config") }

          _cset(:config_readable_mode, "444")
          _cset(:config_readable_files, [])
          _cset(:config_writable_mode, "644")
          _cset(:config_writable_files, [])
          _cset(:config_executable_mode, "755")
          _cset(:config_executable_files, [])
          _cset(:config_remove_files, [])
          _cset(:config_files_options, {:install => :if_modified})

          def _normalize_config_files(fs, options={})
            options = config_files_options.merge(options)
            case fs
            when Array
              fs = Hash[fs.map { |f|
                if config_executable_files.include?(f)
                  options[:mode] = config_executable_mode
                elsif config_writable_files.include?(f)
                  options[:mode] = config_writable_mode
                elsif config_readable_files.include?(f)
                  options[:mode] = config_readable_mode
                end
                [f, options]
              }]
            when Hash
              fs
            else
              raise TypeError.new("unexpected type: #{fs.class}")
            end
          end

          desc("Setup shared application config.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            if config_use_shared
              _normalize_config_files(config_files).each do |file, options|
                safe_put(template(file, :path => config_template_path), File.join(config_shared_path, file), options)
              end
            end
          }
          after "deploy:setup", "config:setup"

          desc("Update applicatin config.")
          task(:update, :roles => :app, :except => { :no_release => true }) {
            transaction {
              update_remotely if fetch(:config_update_remotely, true)
              update_locally if fetch(:config_update_locally, false)
            }
          }
          after "deploy:finalize_update", "config:update"

          task(:update_remotely, :roles => :app, :except => { :no_release => true }) {
            if config_use_shared
              execute = []
              _normalize_config_files(config_files).each do |file, options|
                execute << "( rm -f #{File.join(config_path, file).dump}; " +
                           "ln -sf #{File.join(config_shared_path, file).dump} #{File.join(config_path, file).dump} )"
              end
              run(execute.join(" && ")) unless execute.empty?
            else
              _normalize_config_files(config_files).each do |file, options|
                safe_put(template(file, :path => config_template_path), File.join(config_path, file), options)
              end
            end
          }

          task(:update_locally, :roles => :app, :except => { :no_release => true }) {
            execute = []
            _normalize_config_files(config_files).each do |file, options|
              File.write(File.join(config_path_local, file), template(file, :path => config_template_path))
              if options.key?(:mode)
                mode = options[:mode].is_a?(Numeric) ? options[:mode].to_s(8) : options[:mode].to_s
                execute << "chmod #{mode}  #{File.join(config_path_local, file).dump}"
              end
            end
            run_locally(execute.join(" && ")) unless execute.empty?
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::ConfigRecipe)
end

# vim:set ft=ruby sw=2 ts=2 :
