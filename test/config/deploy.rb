set :application, "capistrano-config"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options, {:user_known_hosts_file => "/dev/null"}

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-config"
require "tempfile"

def _invoke_command(cmdline, options={})
  via = options.delete(:via)
  if via == :run_locally
    run_locally(cmdline)
  else
    invoke_command(cmdline, options)
  end
end

def assert_file_content(file, content, options={})
  begin
    if options[:via] == :run_locally
      remote_content = File.read(file)
    else
      tempfile = Tempfile.new("tmp")
      download(file, tempfile.path)
      remote_content = tempfile.read
    end
    abort if content != remote_content
  rescue
    logger.debug("assert_file_content(#{file}, #{content}) failed.")
    _invoke_command("cat #{file.dump}", options)
    raise
  end
end

def assert_symlink(file, link_to, options={})
  begin
    _invoke_command("test -h #{file.dump} && test #{link_to.dump} = $(readlink #{file.dump})")
  rescue
    logger.debug("assert_symlink(#{file}, #{link_to}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_remote")
  find_and_execute_task("test_with_local")
  find_and_execute_task("test_with_shared")
}

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    run("rm -rf #{deploy_to.dump}")
    run_locally("mkdir -p tmp/local")
    set(:config_template_path, "tmp")
    set(:config_files, %w(foo bar baz))
    set(:config_executable_files, %w(foo))
    set(:config_path_local, "tmp/local")
    set(:config_use_shared, true)
    set(:config_update_remotely, true)
    set(:config_update_locally, true)
#   find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    run("rm -rf #{deploy_to.dump}")
  }

  task(:test_deploy) {
    # xxx
    run_locally("rm -f tmp/foo; echo xxx > tmp/foo")
    run_locally("rm -f tmp/bar; echo xxx > tmp/bar")
    run_locally("rm -f tmp/baz; echo xxx > tmp/baz")
    find_and_execute_task("deploy:setup")
    assert_file_content(File.join(config_shared_path, "foo"), "xxx\n")

    # yyy
    run_locally("rm -f tmp/foo; echo yyy > tmp/foo")
    run_locally("rm -f tmp/bar; echo yyy > tmp/bar")
    run_locally("rm -f tmp/baz; echo yyy > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_shared_path, "foo"), "xxx\n")
    assert_symlink(File.join(config_path, "foo"), File.join(config_shared_path, "foo"))
    assert_file_content(File.join(config_path_local, "foo"), "yyy\n", :via => :run_locally)

    # executable?
    run("test -x #{File.join(config_shared_path, "foo").dump}")
    run_locally("test -x #{File.join(config_path_local, "foo").dump}")
  }
}

namespace(:test_with_remote) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_remote", "test_with_remote:setup"
  after "test_with_remote", "test_with_remote:teardown"

  task(:setup) {
    run("rm -rf #{deploy_to.dump}")
    run_locally("mkdir -p tmp/local")
    set(:config_template_path, "tmp")
    set(:config_files, %w(foo bar baz))
    set(:config_executable_files, %w(foo))
    set(:config_path_local, "tmp/local")
    set(:config_use_shared, false)
    set(:config_update_remotely, true)
    set(:config_update_locally, false)
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    run("rm -rf #{deploy_to.dump}")
  }

  task(:test_deploy) {
    run_locally("rm -f tmp/foo; echo foo > tmp/foo")
    run_locally("rm -f tmp/bar; echo bar > tmp/bar")
    run_locally("rm -f tmp/baz; echo baz > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path, "foo"), "foo\n")
    assert_file_content(File.join(config_path, "bar"), "bar\n")
    assert_file_content(File.join(config_path, "baz"), "baz\n")
  }

  task(:test_redeploy) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path, "foo"), "bar\n")
    assert_file_content(File.join(config_path, "bar"), "baz\n")
    assert_file_content(File.join(config_path, "baz"), "foo\n")
  }
}

namespace(:test_with_local) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_local", "test_with_local:setup"
  after "test_with_local", "test_with_local:teardown"

  task(:setup) {
    run("rm -rf #{deploy_to.dump}")
    run_locally("mkdir -p tmp/local")
    set(:config_template_path, "tmp")
    set(:config_files, %w(foo bar baz))
    set(:config_executable_files, %w(foo))
    set(:config_path_local, "tmp/local")
    set(:config_use_shared, false)
    set(:config_update_remotely, false)
    set(:config_update_locally, true)
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    run("rm -rf #{deploy_to.dump}")
  }

  task(:test_deploy) {
    run_locally("rm -f tmp/foo; echo foo > tmp/foo")
    run_locally("rm -f tmp/bar; echo bar > tmp/bar")
    run_locally("rm -f tmp/baz; echo baz > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path_local, "foo"), "foo\n", :via => :run_locally)
    assert_file_content(File.join(config_path_local, "bar"), "bar\n", :via => :run_locally)
    assert_file_content(File.join(config_path_local, "baz"), "baz\n", :via => :run_locally)
  }

  task(:test_redeploy) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path_local, "foo"), "bar\n", :via => :run_locally)
    assert_file_content(File.join(config_path_local, "bar"), "baz\n", :via => :run_locally)
    assert_file_content(File.join(config_path_local, "baz"), "foo\n", :via => :run_locally)
  }
}

namespace(:test_with_shared) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_shared", "test_with_shared:setup"
  after "test_with_shared", "test_with_shared:teardown"

  task(:setup) {
    run("rm -rf #{deploy_to.dump}")
    run_locally("mkdir -p tmp/local")
    set(:config_template_path, "tmp")
    set(:config_files, %w(foo bar baz))
    set(:config_executable_files, %w(foo))
    set(:config_path_local, "tmp/local")
    set(:config_use_shared, true)
    set(:config_update_remotely, true)
    set(:config_update_locally, false)
#   find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    run("rm -rf #{deploy_to.dump}")
  }

  task(:test_setup) {
    run_locally("rm -f tmp/foo; echo foo > tmp/foo")
    run_locally("rm -f tmp/bar; echo bar > tmp/bar")
    run_locally("rm -f tmp/baz; echo baz > tmp/baz")
    find_and_execute_task("deploy:setup")
    assert_file_content(File.join(config_shared_path, "foo"), "foo\n")
    assert_file_content(File.join(config_shared_path, "bar"), "bar\n")
    assert_file_content(File.join(config_shared_path, "baz"), "baz\n")
  }

  task(:test_resetup) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy:setup")
    assert_file_content(File.join(config_shared_path, "foo"), "bar\n")
    assert_file_content(File.join(config_shared_path, "bar"), "baz\n")
    assert_file_content(File.join(config_shared_path, "baz"), "foo\n")
  }

  task(:test_deploy) {
    find_and_execute_task("deploy")
    assert_symlink(File.join(config_path, "foo"), File.join(config_shared_path, "foo"))
    assert_symlink(File.join(config_path, "bar"), File.join(config_shared_path, "bar"))
    assert_symlink(File.join(config_path, "baz"), File.join(config_shared_path, "baz"))
  }

  task(:test_redeploy) {
    find_and_execute_task("deploy")
    assert_symlink(File.join(config_path, "foo"), File.join(config_shared_path, "foo"))
    assert_symlink(File.join(config_path, "bar"), File.join(config_shared_path, "bar"))
    assert_symlink(File.join(config_path, "baz"), File.join(config_shared_path, "baz"))
  }

  task(:test_update_config) {
    run_locally("rm -f tmp/foo; echo unu > tmp/foo")
    run_locally("rm -f tmp/bar; echo du  > tmp/bar")
    run_locally("rm -f tmp/baz; echo tri > tmp/baz")
    find_and_execute_task("config:setup")
    assert_file_content(File.join(config_path, "foo"), "unu\n")
    assert_file_content(File.join(config_path, "bar"), "du\n")
    assert_file_content(File.join(config_path, "baz"), "tri\n")
  }
}

# vim:set ft=ruby sw=2 ts=2 :
