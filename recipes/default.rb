#
# Cookbook Name:: rails_app
# Recipe:: default
#
# Copyright 2012, Robin Wenglewski
#
# All rights reserved - Do Not Redistribute
#

extend RailsApp


def ensure_all_in(hash, keys, &block)
  keys.each do |key|
    yield(key) unless hash.has_key? key
  end
end

def get_verified_databag!(id)
  Chef::Log.info "bag item: #{id}"
  app = data_bag_item('rails_apps', id).to_hash

  required = %w(rails_env databases precompile repository deploy_key)
  ensure_all_in(app, required) { |missing| raise "databag must define key: #{missing}" }

  raise "databag[databases][#{app['rails_env']}] must be defined" unless app['databases'].has_key? app['rails_env']

  required = %w(adapter username password database)
  ensure_all_in(app['databases'][app['rails_env']], required) { |missing| raise "databag[databases][#{app['rails_env']}] must define key: #{missing}" }

  # default values
  app['name'] ||= id
  app['user'] ||= app['name']
  app['group'] ||= app['user'] # group required by deploy_revision
  app['bundle_install_cmd'] ||= 'bundle install --deployment --without development test'
  app['domains'] ||= 'default'
  app['domains'] = [*(app['domains'])] # ensure array
  app['seed'] ||= false
  app['deploy_to'] ||= "/srv/www/#{app['name']}"

  app['service_name'] ||= "app.#{app['name']}"
  app['worker_count'] ||= 3



  app['shared_directories'] ||= {
      'vendor/bundle' => 'vendor_bundle',
      "config/database.yml" => 'database.yml',
      "config/unicorn.conf" => 'unicorn.conf',
      "log" => true
  }

  app['shared_directories'].merge!(app['additional_shared_directories'] || {})

  # transform shared_directories
  app['shared_directories'].each do |k, v|

    app['shared_directories'][k] = k if app['shared_directories'][k] == true

    app['shared_directories'][k] = {"file" => app['shared_directories'][k], 'on_exists' => 'raise' } if app['shared_directories'][k].is_a?(String)
  end

  app
end


def create_db app
  pg_user app['databases'][app['rails_env']]['username'] do
    password app['databases'][app['rails_env']]['password']
    privileges :superuser => false, :createdb => false, :inherit => true, :login => true
  end

  pg_database app['databases'][app['rails_env']]['database'] do
    owner app['databases'][app['rails_env']]['username']
  end
end


(node['rails_app']['bag_items'] || []).each do |id|
  app = get_verified_databag!(id)

  Chef::Log.info "configuring app: #{app.inspect}"

  # load some default recipes
  %w(nginx postgresql::server).each do |r|
    Chef::Log.info "including recipe: #{r}"
    include_recipe r
  end

  # install some default packages
  %w(libpq5 libpq-dev git-core libmagickwand-dev build-essential imagemagick).each { |p| package p }

  # create parent of deploy directory
  directory File.expand_path("..", app['deploy_to']) do
    mode '0771'
    owner 'root'
    group 'root'
    recursive true
  end

  # setup user
  group app['user'] do
  end
  user app['user'] do
    action :create
    gid app['user']
    home app['deploy_to']
    shell '/bin/bash'
    comment "Rails App"
    supports({
                 :manage_home => true
             })
  end

  # create authorized_key file so that the user can login as this user
  if(app['deploy_to'])
    directory File.expand_path(".ssh", app['deploy_to']) do
      mode '0600'
      recursive true
    end

    file File.expand_path(".ssh/authorized_keys", app['deploy_to']) do
      owner app['user']
      group app['group']
      mode '0600'
      content app['authorized_key']
    end
  end

  # install rvm for user
  node.default['rvm']['user_installs'] << {
      'user' => app['user'],
      'home' => app['deploy_to'],
      'default_ruby' => '2.0.0',
      'default_gems' => %w(bundler rake unicorn)
  }
  include_recipe "rvm::user"

  create_db app



  # all is required: log for nginx logs, pids for unicorn pids, shared anyway for linking
  %w(shared shared/log shared/pids).each do |dir|
    directory "#{app['deploy_to']}/#{dir}" do
      owner app['user']
      group app['group']
      mode '0755'
      recursive true
    end
  end


  # database.yml
  Chef::Log.info "creating database.yml: #{app['databases'].inspect}"
  template "#{app['deploy_to']}/shared/database.yml" do
    source "database.yml.erb"
    owner app['user']
    group app['group']
    mode "644"
    variables(
        'host' => 'localhost',
        'databases' => app['databases']
    )
  end

  # setup deploy-ssh-wrapper
  if app.has_key?('deploy_key')
    #TODO: check if we can do this with the file resource
    file "#{app['deploy_to']}/id_deploy" do
      user app['user']
      group app['group']
      content app['deploy_key']
      mode '0600'
    end

    file "#{app['deploy_to']}/id_deploy" do
      owner app['user']
      group app['group']
      mode '0600'
      content app['deploy_key']
    end

    template "#{app['deploy_to']}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner app['user']
      group app['group']
      mode "0755"
      variables app
    end
  end

  # unicorn.conf
  template "#{app['deploy_to']}/shared/unicorn.conf" do
    source 'unicorn.rb.erb'
    owner app['user']
    group app['group']
    variables('app' => app)
  end

  # deploy the app
  deploy_revision app['name'] do
    repository app['repository']
    revision app['revision']
    deploy_to app['deploy_to']
    user app['user']
    group app['group']
    deploy_to app['deploy_to']
    environment 'RAILS_ENV' => app['rails_env']
    action :force_deploy
    ssh_wrapper "#{app['deploy_to']}/deploy-ssh-wrapper" if app['deploy_key']

    before_migrate do
      @app = app # make app available in here
      blast = app
      extend RailsApp

      # enrich app information for callbacks
      app['release_path'] = release_path

      # create vendor directory
      directory "#{release_path}/vendor" do
        owner app['user']
        group app['group']
      end

      # links to shared
      (app['shared_directories']).each_pair do |k, v|
        Chef::Log.info "processing shared directory: #{k} with value #{v.inspect}"
        do_link = true
        do_remove_first = false

        if File.exists? "#{release_path}/#{k}"
          msg = "link will not be rendered because file already exists: #{release_path}/#{k}"
          case v['on_exists']
            when 'ignore'
              do_link = false
            when 'raise'
              raise msg
            when 'log'
              Chef::Log.warn msg
              do_link = false
            when 'overwrite'
              do_remove_first = true
            else
              raise "unknown on_exists value: #{v['on_exists']}"
          end
        else

        end

        # create shared directories
        unless v['file']['.']
          dir = v['file']
          directory "#{app['deploy_to']}/shared/#{dir}" do
            owner app['user']
            group app['group']
            mode '0755'
            recursive true
          end
        end

        if do_link
          if do_remove_first
            directory "#{release_path}/#{k}" do
              action :delete
              recursive true
            end
          end

          link "#{release_path}/#{k}" do
            to "#{app['deploy_to']}/shared/#{v['file']}"
            owner app['user']
            group app['group']
          end
        end
      end

      run_callback(
          :file => "#{release_path}/deploy/hooks/before_bundle_install.rb",
          :variables => {'app' => app}
      )

      rvm_shell "run bundle install" do
        code app['bundle_install_cmd']
        user app['user']
        group app['group']
        cwd release_path
        environment 'RAILS_ENV' => app['rails_env']
      end

      run_callback(
          :file => "#{release_path}/deploy/hooks/after_bundle_install.rb",
          :variables => {'app' => app}
      )

      Chef::Log.info "#{release_path}/log exists? #{File.exists? "#{release_path}/log"}"

      rvm_shell 'run rake db:migrate' do
        code "bundle exec rake db:migrate"
        user app['user']
        group app['group']
        cwd release_path
        environment 'RAILS_ENV' => app['rails_env'].to_s
      end
    end

    migrate false
    migration_command "bundle exec rake db:schema:load"

    # we do the symlinking in before_migrate
    purge_before_symlink []
    create_dirs_before_symlink []
    symlinks({})
    symlink_before_migrate({})

    before_restart do
      run_callback(
          :file => "#{release_path}/deploy/hooks/before_restart.rb",
          :variables => {'app' => app}
      )

      Chef::Log.info "#{release_path}/log exists? #{File.exists? "#{release_path}/log"}"


      if app['seed']
        rvm_shell "seed data" do
          code "bundle exec rake db:seed"
          user app['user']
          group app['group']
          environment 'RAILS_ENV' => app['rails_env'].to_s
          cwd release_path
        end
      end

      if app['precompile']
        rvm_shell "precompile assets" do
          code "bundle exec rake assets:precompile"
          user app['user']
          group app['group']
          environment 'RAILS_ENV' => app['rails_env'].to_s
          cwd release_path
        end
      end

      Chef::Log.info "#{release_path}/log exists? #{File.exists? "#{release_path}/log"}"

      link "#{app['deploy_to']}/current" do
        to "#{release_path}"
      end
    end
  end

  link "/etc/nginx/sites-enabled/#{app['name']}" do
    to "#{app['deploy_to']}/nginx.conf"
  end

  template "/etc/init.d/#{app['service_name']}" do
    source 'init.sh.erb'
    owner app['user']
    group app['group']
    mode "0750"
    variables(
        'deploy_to' => app['deploy_to'],
        'rails_env' => app['rails_env'],
        'desc' => "Rails Application: #{app['name']}",
        'user' => app['user']
    )
  end

  # make the app start automatically on boot
  execute "add #{app['service_name']} to defaults" do
    command "update-rc.d #{app['service_name']} defaults"
  end

  # restart the app now
  service app['service_name'] do
    action :restart
  end

  template "#{app['deploy_to']}/nginx.conf" do
    source "nginx.conf.erb"
    owner app['user']
    group app['group']
    notifies :reload, 'service[nginx]'
    variables('deploy_to' => app['deploy_to'], 'server_name' => app['domains'].join(" "), 'name' => app['name'])
  end

  # the notifies above doesn't seem to trigger
  execute "nginx reload for app #{app['name']}" do
    command 'service nginx reload'
  end
end
