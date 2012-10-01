require "capistrano-config/version"
require 'erb'
require 'tempfile'

module Capistrano
  module ConfigRecipe
    def self.extended(configuration)
      configuration.load {
        namespace(:config) {
          _cset(:config_path) { release_path }
          _cset(:config_path_local) { File.expand_path('.') }
          _cset(:config_template_path) { File.join(File.expand_path('.'), 'config', 'templates') }
          _cset(:config_files, [])
          _cset(:config_source_files) {
            config_files.map { |file| File.join(config_template_path, file) }
          }
          _cset(:config_temporary_files) {
            config_files.map { |file|
              f = Tempfile.new('config'); t = f.path
              f.close(true) # remote tempfile immediately
              t
            }
          }
          _cset(:config_readable_mode, "ug+r")
          _cset(:config_readable_files, [])
          _cset(:config_writable_mode, "ug+rw")
          _cset(:config_writable_files, [])
          _cset(:config_executable_mode, "ug+rx")
          _cset(:config_executable_files, [])
          _cset(:config_remove_files, [])

          desc("Update applicatin config.")
          task(:update, :roles => :app, :except => { :no_release => true }) {
            transaction {
              update_locally if fetch(:config_update_locally, false)
              update_remotely if fetch(:config_update_remotely, true)
            }
          }
          after 'deploy:finalize_update', 'config:update'

          def _read_config(config)
            if File.file?(config)
              File.read(config)
            elsif File.file?("#{config}.erb")
              ERB.new(File.read("#{config}.erb")).result(binding)
            else
              abort("config: no such template found: #{config} or #{config}.erb")
            end
          end

          def _do_update(src_tmp_tgt, options={})
            options = {
              :readable_files => [], :writable_files => [], :executable_files => [],
              :remove_files => [],
              :use_sudo => true,
            }.merge(options)
            dirs = src_tmp_tgt.map { |src, tmp, tgt| File.dirname(tgt) }.uniq
            try_sudo = options[:use_sudo] ? sudo : ""
            execute = []
            execute << "mkdir -p #{dirs.join(' ')}" unless dirs.empty?
            src_tmp_tgt.map { |src, tmp, tgt|
              execute << "( diff -u #{tgt} #{tmp} || #{try_sudo} mv -f #{tmp} #{tgt} )"
            }
            execute << "#{try_sudo} chmod #{config_readable_mode} #{options[:readable_files].join(' ')}" unless options[:readable_files].empty?
            execute << "#{try_sudo} chmod #{config_writable_mode} #{options[:writable_files].join(' ')}" unless options[:writable_files].empty?
            execute << "#{try_sudo} chmod #{config_executable_mode} #{options[:executable_files].join(' ')}" unless options[:executable_files].empty?
            execute << "#{try_sudo} rm -f #{options[:remove_files].join(' ')}" unless options[:remove_files].empty?

            execute.join(' && ')
          end

          task(:update_locally, :roles => :app, :except => { :no_release => true }) {
            begin
              target_files = config_files.map { |f| File.join(config_path_local, f) }
              src_tmp_tgt = config_source_files.zip(config_temporary_files, target_files)
              src_tmp_tgt.each { |src, tmp, tgt|
                File.open(tmp, 'wb') { |fp| fp.write(_read_config(src)) } unless dry_run
              }
              run_locally(_do_update(src_tmp_tgt,
                :use_sudo => fetch(:config_use_sudo_locally, false),
                :readable_files => config_readable_files.map { |f| File.join(config_path_local, f) },
                :writable_files => config_writable_files.map { |f| File.join(config_path_local, f) },
                :executable_files => config_executable_files.map { |f| File.join(config_path_local, f) },
                :remove_files => config_remove_files.map { |f| File.join(config_path_local, f) }))
            ensure
              run_locally("rm -f #{config_temporary_files.join(' ')}") unless config_temporary_files.empty?
            end
          }

          task(:update_remotely, :roles => :app, :except => { :no_release => true }) {
            begin
              target_files = config_files.map { |f| File.join(config_path, f) }
              src_tmp_tgt = config_source_files.zip(config_temporary_files, target_files)
              src_tmp_tgt.each { |src, tmp, tgt|
                put(_read_config(src), tmp)
              }
              run(_do_update(src_tmp_tgt,
                :use_sudo => fetch(:config_use_sudo_remotely, true),
                :readable_files => config_readable_files.map { |f| File.join(config_path, f) },
                :writable_files => config_writable_files.map { |f| File.join(config_path, f) },
                :executable_files => config_executable_files.map { |f| File.join(config_path, f) },
                :remove_files => config_remove_files.map { |f| File.join(config_path, f) }))
            ensure
              run("rm -f #{config_temporary_files.join(' ')}") unless config_temporary_files.empty?
            end
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
