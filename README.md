# capistrano-config

a capistrano recipe to manage configurations files.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-config'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-config

## Usage

This recipes will try to update application config during Capistrano `deploy` tasks.

To enable this recipe, add following in your `config/deploy.rb`.

The configuration file `config/config.yml` will be generated from template in `config/templates` by default.
(The template will be used is either `config/templates/config/config.yml.erb` or `config/templates/config/config.yml`.)

    # config/deploy.rb
    require "capistrano-config"
    set :config_files, ["config/config.yml"]

## Examples

### Setting up shared configuration

You might not want to generate configuration files on everytime of deployment.
There is _shared_ mode to generate configuration files just once during `deploy:setup`.

This is the configuration example for shared configuration mode.

    # config/deploy.rb
    set :config_use_shared, true
    set :config_files, ["config/config.yml"]

The generated configuration files will be installed in `#{shared_path}/config/config.yml` during `deploy:setup`.
After the setup of shared configuration, symlink will be created at `#{release_path}/config/config.yml` during `deploy`.

If you want to update the shared configuration files, invoke `config:setup` will do that.

    % cap config:setup

### Setting up local configuration

With some build system, you might need to update some of local files during deployment.
There is _local_ mode to help you.

This is the configuration example for local configuration mode.

    # config/deploy.rb
    set :config_update_locally, true
    set :config_files, ["config/config.yml"]

The local configuration files will be updated during `deploy`.

### Setting up files with special parameters

You can set file parameters for each files with defining `:config_files` as a Hash.
The value of Hash will be passed to `safe_put` of [capistrano-file-transfer-ext](https://github.com/yyuu/capistran-file-transfer-ext).

    # config/deploy.rb
    set :config_files do
      {
        "config/secret.yml" => { :owner => "user", :group => "user", :mode => "640" }
      }
    end

If you want to apply for all configuration files, you can use `:config_files_options`.

   # config/deploy.rb
    set :config_files, ["config/secret.yml", "config/credentials.yml"]
    set :config_files_options, :owner => "user", :group => "user", :mode => "640"

### Setting up files with absolute paths

If the configuration file name starts with "/", it will be treated as absolute path.

    # config/deploy.rb
    set :config_files do
      {
        "/etc/init/foo.cnf" => { :configure_except => :local, :owner => "root", :group => "root", :mode => "644", :run_method => :sudo },
      }
    end


## Reference

These options are available to manage your configuration files.

 * `:config_files` - the definition of configuration files as in an array or a hash.
    if given as hash, the key should be the value should be the file options.
 * `:config_update_remotely` - specify whether update config files on remote machines or not. `true` by default.
 * `:config_update_locally` - specify whether update config files on local machines or not. `false` by default.
 * `:config_use_shared` - set `true` if you want to use _shared_ config. `false` by default.
 * `:config_path` - specify configuration base directory on remote machines. use `release_path` by default.
 * `:config_path_local` - specify configuration base directory on local machine. use `.` by default.
 * `:config_template_path` - specify configuration template directory on local machine. use `config/templates` by default.
 * `:config_files_options` - the hash to be used as parameters for configuration files.


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
