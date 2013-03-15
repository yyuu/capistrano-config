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

def assert_file_mode(mode, file, options={})
  mode = mode.to_i(8) if mode.is_a?(String)
  smode = "%c%c%c%c%c%c%c%c%c%c" % [
    ?-,
    mode & 0400 == 0 ? ?- : ?r, mode & 0200 == 0 ? ?- : ?w, mode & 0100 == 0 ? ?- : ?x,
    mode & 0040 == 0 ? ?- : ?r, mode & 0020 == 0 ? ?- : ?w, mode & 0010 == 0 ? ?- : ?x,
    mode & 0004 == 0 ? ?- : ?r, mode & 0002 == 0 ? ?- : ?w, mode & 0001 == 0 ? ?- : ?x,
  ]
  begin
    _invoke_command("test #{smode.dump} = $(ls -l #{file.dump} | cut -d ' ' -f 1)", options)
  rescue
    logger.debug("assert_file_mode(#{mode.to_s(8)}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

def assert_file_owner(uid, file, options={})
  uid = uid.to_i
  # `stat -c` => GNU, `stat -f` => BSD
  begin
    _invoke_command("test #{uid} -eq $( stat -c '%u' #{file.dump} || stat -f '%u' #{file.dump} )", options)
  rescue
    logger.debug("assert_file_owner(#{uid}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

def assert_file_group(gid, file, options={})
  gid = gid.to_i
  # `stat -c` => GNU, `stat -f` => BSD
  begin
    _invoke_command("test #{gid} -eq $( stat -c '%g' #{file.dump} || stat -f '%g' #{file.dump} )", options)
  rescue
    logger.debug("assert_file_group(#{gid}, #{file}) failed.")
    _invoke_command("ls -l #{file.dump}", options)
    raise
  end
end

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_options")
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
    assert_file_content(File.join(config_shared_path, "foo"), File.read("tmp/foo"))

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

namespace(:test_with_options) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_options", "test_with_options:setup"
  after "test_with_options", "test_with_options:teardown"

  task(:setup) {
    sudo("rm -f /etc/__privileged__")
    run("rm -rf #{deploy_to.dump}")
    run_locally("mkdir -p tmp/local")
    set(:config_template_path, "tmp")
    set(:config_files, {
      "secret" => {:mode => 0640},
      "/etc/__privileged__" => { :run_method => :sudo, :owner => 0, :group => 0 },
    })
    set(:config_path_local, "tmp/local")
    set(:config_use_shared, false)
    set(:config_update_remotely, true)
    set(:config_update_locally, false)
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    run_locally("rm -rf tmp")
    run("rm -rf #{deploy_to.dump}")
    sudo("rm -f /etc/__privileged__")
  }

  task(:test_deploy) {
    run_locally("rm -f tmp/secret; echo secret > tmp/secret")
    run_locally("rm -f tmp/etc/__privileged__; mkdir -p tmp/etc; echo __privileged__ > tmp/etc/__privileged__")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path, "secret"), File.read("tmp/secret"))
    assert_file_mode(0640, File.join(config_path, "secret"))

    assert_file_content("/etc/__privileged__", File.read("tmp/etc/__privileged__"))
    assert_file_owner(0, "/etc/__privileged__")
    assert_file_group(0, "/etc/__privileged__")
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
    assert_file_content(File.join(config_path, "foo"), File.read("tmp/foo"))
    assert_file_content(File.join(config_path, "bar"), File.read("tmp/bar"))
    assert_file_content(File.join(config_path, "baz"), File.read("tmp/baz"))
  }

  task(:test_redeploy) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path, "foo"), File.read("tmp/foo"))
    assert_file_content(File.join(config_path, "bar"), File.read("tmp/bar"))
    assert_file_content(File.join(config_path, "baz"), File.read("tmp/baz"))
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
    assert_file_content(File.join(config_path_local, "foo"), File.read("tmp/foo"), :via => :run_locally)
    assert_file_content(File.join(config_path_local, "bar"), File.read("tmp/bar"), :via => :run_locally)
    assert_file_content(File.join(config_path_local, "baz"), File.read("tmp/baz"), :via => :run_locally)
  }

  task(:test_redeploy) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy")
    assert_file_content(File.join(config_path_local, "foo"), File.read("tmp/foo"), :via => :run_locally)
    assert_file_content(File.join(config_path_local, "bar"), File.read("tmp/bar"), :via => :run_locally)
    assert_file_content(File.join(config_path_local, "baz"), File.read("tmp/baz"), :via => :run_locally)
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
    assert_file_content(File.join(config_shared_path, "foo"), File.read("tmp/foo"))
    assert_file_content(File.join(config_shared_path, "bar"), File.read("tmp/bar"))
    assert_file_content(File.join(config_shared_path, "baz"), File.read("tmp/baz"))
  }

  task(:test_resetup) {
    run_locally("rm -f tmp/foo; echo bar > tmp/foo")
    run_locally("rm -f tmp/bar; echo baz > tmp/bar")
    run_locally("rm -f tmp/baz; echo foo > tmp/baz")
    find_and_execute_task("deploy:setup")
    assert_file_content(File.join(config_shared_path, "foo"), File.read("tmp/foo"))
    assert_file_content(File.join(config_shared_path, "bar"), File.read("tmp/bar"))
    assert_file_content(File.join(config_shared_path, "baz"), File.read("tmp/baz"))
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
    assert_file_content(File.join(config_path, "foo"), File.read("tmp/foo"))
    assert_file_content(File.join(config_path, "bar"), File.read("tmp/bar"))
    assert_file_content(File.join(config_path, "baz"), File.read("tmp/baz"))
  }
}

# vim:set ft=ruby sw=2 ts=2 :
