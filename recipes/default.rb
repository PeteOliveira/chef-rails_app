#
# Cookbook Name:: rails_app
# Recipe:: default
#
# Copyright 2012, Robin Wenglewski
#
# All rights reserved - Do Not Redistribute
#
nb = Class.new.send(:extend, NodeBase)
extend RailsApp

node['rails_app']['bag_items'].each do |id|
  app = nb.symbolize_keys(data_bag_item('rails_apps', id).to_hash)

  # default values
  app[:group] ||= app[:user] # group required by deploy_revision
  app[:bundle_install_cmd] ||= 'bundle install --deployment --without development test'
  app[:rails_env] = app[:rails_env].to_sym
  
  Chef::Log.info "configuring app: #{app.inspect}"

  %w(node-base apt nginx postgresql::server postfix).each do |r|
  	include_recipe r
  end

  %w(libpq5 libpq-dev git-core libmagickwand-dev build-essential imagemagick).each {|p| package p}

  postgresql_user app[:databases][app[:rails_env]][:username] do
    password app[:databases][app[:rails_env]][:password]
    privileges :superuser => false, :createdb => false, :inherit => true, :login => true
  end

  postgresql_database app[:databases][app[:rails_env]][:database] do
    owner app[:databases][app[:rails_env]][:username]
  end

  # give user cool shell and default settings
  # we can change the defaults later, for now we take rweng
  user = Rweng::User.new(
    :username => app[:user],
    :key => (app[:authorized_key] || raise("key for authorization required")),
    :home => app[:deploy_to],
    :groups => %w(www-data),
    :create_home_recursively => true
  )
  Rweng.new(self).install(user)

  file "#{app[:deploy_to]}/.localrc" do
    owner app[:user]
    group app[:group]
    content <<-END
    export RAILS_ENV=#{app[:rails_env].to_s}
    END
  end

  # create deploy directory
  directory app[:deploy_to] do
    owner app[:user]
    group app[:group]
    mode '0755'
    recursive true
  end

  # create shared directory
  directory "#{app[:deploy_to]}/shared" do
    owner app[:user]
    group app[:group]
    mode '0755'
    recursive true
  end

  %w{ log pids system vendor_bundle }.each do |dir|
    directory "#{app[:deploy_to]}/shared/#{dir}" do
      owner app[:user]
      group app[:group]
      mode '0755'
      recursive true
    end
  end


  Chef::Log.info "databases: #{app[:databases].inspect}"
  template "#{app[:deploy_to]}/shared/database.yml" do
    source "database.yml.erb"
    owner app[:user]
    group app[:group]
    mode "644"
    variables(
      :host => 'localhost',
      'databases' => app[:databases]
    )
  end

  if app.has_key?(:deploy_key)
    #TODO: check if we can do this with the file resource
    file "#{app[:deploy_to]}/id_deploy" do
      user app[:user]
      group app[:group]
      content app[:deploy_key]
      mode '0600'
    end

    # ruby_block "write_key" do
    #   block do
    #     f = ::File.open("#{app[:deploy_to]}/id_deploy", "w")
    #     f.print(app[:deploy_key])
    #     f.close
    #   end
    #   not_if do ::File.exists?("#{app[:deploy_to]}/id_deploy"); end
    # end

    # file "#{app[:deploy_to]}/id_deploy" do
    #   owner app[:user]
    #   group app[:group]
    #   mode '0600'
    # end

    template "#{app[:deploy_to]}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner app[:user]
      group app[:group]
      mode "0755"
      variables app
    end
  end

  template "#{app[:deploy_to]}/shared/unicorn.conf" do
    source 'unicorn.rb.erb'
    owner app[:user]
    group app[:group]
    variables('deploy_to' => app[:deploy_to])
  end


  deploy_revision app[:domain] do
  	repository app[:repository]
    revision app[:revision]
    deploy_to app[:deploy_to]
    user app[:user]
    group app[:group]
    deploy_to app[:deploy_to]
    environment 'RAILS_ENV' => app[:rails_env].to_s
    action :force_deploy
    ssh_wrapper "#{app[:deploy_to]}/deploy-ssh-wrapper" if app[:deploy_key]

    before_migrate do
      @app = app # make app available in here
      blast = app
      extend RailsApp

      app[:release_path] = release_path

      # remove log directory, gets linked later
      # using directory command did not work
      if File.directory?("#{release_path}/log")
        Chef::Log.info "removing log dir: #{release_path}/log"
        FileUtils.rm_rf "#{release_path}/log"
      else
        Chef::Log.info "no directory: #{release_path}/log"
      end

      
      # create vendor directory
      directory "#{release_path}/vendor" do
        owner app[:user]
        group app[:group]
      end

      # links to shared
      {
        'vendor/bundle' => 'vendor_bundle',
        "config/database.yml" => 'database.yml',
        "config/unicorn.conf" => 'unicorn.conf',
        "log" => 'log'
      }.each_pair do |k, v|

        if File.exists? "#{release_path}/#{k}"
          Chef::Log.warn "link will not be rendered because file already exists: #{release_path}/#{k}"
        else
          link "#{release_path}/#{k}" do
            to "#{app[:deploy_to]}/shared/#{v}"
            owner app[:user].to_s
            group app[:group].to_s
          end
        end
      end

      run_callback(
        :file => "#{release_path}/config/chef/before_bundle_install.rb",
        :variables => {:app => app}
      )

      rvm_gem 'bundler' do
        user app[:user]
      end

      rvm_gem 'chef' do
        user app[:user]
      end

      rvm_shell "run bundle install" do
        code app[:bundle_install_cmd]
        user app[:user]
        group app[:group]
        cwd release_path
        environment 'RAILS_ENV' => app[:rails_env].to_s
      end

      # run_callback"#{release_path}/config/chef/after_bundle_install.rb"
      
      rvm_shell 'run rake db:migrate' do
        code "bundle exec rake db:migrate"
        user app[:user]
        group app[:group]
        cwd release_path
        environment 'RAILS_ENV' => app[:rails_env].to_s
      end
    end

    migrate false
    migration_command "bundle exec rake db:schema:load"

    # we do the symlinking in before_migrate
    symlinks({})
    symlink_before_migrate({})

    before_restart do

      if app[:seed]
        rvm_shell "seed data" do
          code "bundle exec rake db:seed"
          user app[:user]
          group app[:group]
          environment 'RAILS_ENV' => app[:rails_env].to_s
          cwd release_path
        end
      end

      if app[:precompile]
        rvm_shell "precompile assets" do
          code "bundle exec rake assets:precompile"
          user app[:user]
          group app[:group]
          cwd release_path
        end
      end

      link "#{app[:deploy_to]}/current" do
        to "#{release_path}"
      end
    end
  end


  file "/etc/nginx/sites-enabled/default" do
    action :delete
  end

  link "/etc/nginx/sites-enabled/#{app[:domain]}" do
    to "#{app[:deploy_to]}/nginx.conf"
  end

  template "/etc/init.d/#{app[:service_name]}" do
    source 'init.sh.erb'
    owner app[:user]
    group app[:group]
    mode "0750"
    variables(
      'deploy_to' => app[:deploy_to],
      'rails_env' => app[:rails_env],
      'desc' => app[:domain],
      'user' => app[:user]
    )  
  end

  # make the app start automatically on boot
  execute "add #{app[:service_name]} to defaults" do
    command "update-rc.d #{app[:service_name]} defaults"
  end

  # restart the app now
  service app[:service_name] do
    action :restart
  end

  template "#{app[:deploy_to]}/nginx.conf" do
    source "nginx.conf.erb"
    owner app[:user]
    group app[:group]
    notifies :reload, 'service[nginx]'
    variables('deploy_to' => app[:deploy_to], 'server_name' => app[:domain], 'name' => app[:domain])
  end

  # the notifies above doesn't seem to trigger
  execute "nginx reload for app #{app[:domain]}" do
    command 'service nginx reload'
  end
end