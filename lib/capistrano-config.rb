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

          _cset(:config_use_shared, false)
          _cset(:config_shared_path) { File.join(shared_path, 'config') }

          _cset(:config_readable_mode, "ug+r")
          _cset(:config_readable_files, [])
          _cset(:config_writable_mode, "ug+rw")
          _cset(:config_writable_files, [])
          _cset(:config_executable_mode, "ug+rx")
          _cset(:config_executable_files, [])
          _cset(:config_remove_files, [])

          def tempfile(name)
            f = Tempfile.new(name)
            path = f.path
            f.close(true) # close and remove tempfile immediately
            path
          end

          def template(config)
            if File.file?(config)
              File.read(config)
            elsif File.file?("#{config}.erb")
              ERB.new(File.read("#{config}.erb")).result(binding)
            else
              abort("config: no such template found: #{config} or #{config}.erb")
            end
          end

          def update_one(source, target, options={})
            try_sudo = options[:use_sudo] ? sudo : ""
            execute = []
            dirs = [ File.dirname(source), File.dirname(target) ].uniq
            execute << "#{try_sudo} mkdir -p #{dirs.map { |d| d.dump }.join(' ')}"
            execute << "( #{try_sudo} diff -u #{target.dump} #{source.dump} || #{try_sudo} mv -f #{source.dump} #{target.dump} )"

            execute << "#{try_sudo} chmod #{config_readable_mode} #{target.dump}" if options[:readable_file].include?(target)
            execute << "#{try_sudo} chmod #{config_writable_mode} #{target.dump}" if options[:writable_file].include?(target)
            execute << "#{try_sudo} chmod #{config_executable_mode} #{target.dump}" if options[:executable_file].include?(target)
            execute << "#{try_sudo} rm -f #{config_remove_files.map { |f| f.dump }.join(' ')}" if options[:remove_files].include?(target)

            execute.join(' && ')
          end

          def update_all(files={}, options={})
            srcs = files.map { |src, dst| src }
            tmps = files.map { tempfile("capistrano-config") }
            dsts = files.map { |src, dst| dst }
            begin
              srcs.zip(tmps).each do |src, tmp|
                put(template(src), tmp)
              end
              tmps.zip(dsts).each do |tmp, dst|
                run(update_one(tmp, dst, options.merge(:use_sudo => fetch(:config_use_sudo_remotely, false))))
              end
            ensure
              run("rm -f #{tmp.map { |f| f.dump }.join(' ')}") unless tmps.empty?
            end
          end

          def update_all_locally(files={})
            srcs = files.map { |src, dst| src }
            tmps = files.map { tempfile("capistrano-config") }
            dsts = files.map { |src, dst| dst }
            begin
              srcs.zip(tmps).each do |src, tmp|
                File.open(tmp, 'wb') { |fp| fp.write(template(src)) } unless dry_run
              end
              tmps.zip(dsts).each do |tmp, dst|
                run_locally(update_one(tmp, dst, options.merge(:use_sudo => fetch(:config_use_sudo_locally, false))))
              end
            ensure
              run_locally("rm -f #{tmp.map { |f| f.dump }.join(' ')}") unless tmps.empty?
            end
          end

          def symlink_all(files={})
            execute = []
            files.each do |src, dst|
              execute << "ln -s #{src.dump} #{dst.dump}"
            end
            run(execute.join(' && '))
          end

          desc("Setup shared application config.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            if config_use_shared
              srcs = config_files.map { |f| File.join(config_template_path, f) }
              dsts = config_files.map { |f| File.join(config_shared_path, f) }
              update_all(srcs.zip(dsts),
                :readable_files => config_readable_files.map { |f| File.join(config_shared_path, f) },
                :writable_files => config_writable_files.map { |f| File.join(config_shared_path, f) },
                :executable_files => config_executable_files.map { |f| File.join(config_shared_path, f) },
                :remove_files => config_remove_files.map { |f| File.join(config_shared_path, f) }
              )
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
              srcs = config_files.map { |f| File.join(config_shared_path, f) }
              dsts = config_files.map { |f| File.join(config_path, f) }
              symlink_all(srcs.zip(dsts))
            else
              srcs = config_files.map { |f| File.join(config_template_path, f) }
              dsts = config_files.map { |f| File.join(config_path, f) }
              update_all(srcs.zip(dsts),
                :readable_files => config_readable_files.map { |f| File.join(config_path, f) },
                :writable_files => config_writable_files.map { |f| File.join(config_path, f) },
                :executable_files => config_executable_files.map { |f| File.join(config_path, f) },
                :remove_files => config_remove_files.map { |f| File.join(config_path, f) }
              )
            end
          }

          task(:update_locally, :roles => :app, :except => { :no_release => true }) {
            srcs = config_files.map { |f| File.join(config_template_path, f) }
            dsts = config_files.map { |f| File.join(config_path_local, f) }
            update_all_locally(srcs.zip(dsts),
              :readable_files => config_readable_files.map { |f| File.join(config_path_local, f) },
              :writable_files => config_writable_files.map { |f| File.join(config_path_local, f) },
              :executable_files => config_executable_files.map { |f| File.join(config_path_local, f) },
              :remove_files => config_remove_files.map { |f| File.join(config_path_local, f) }
            )
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
