default[:rails_app] = {
  :precompile => false,
  :seed => false,
  :rails_env => :production,
  :databases => {
    :production => {
      :adapter => "postgresql",
      :username => "rails_app",
      :password => "slkajgadsflkj",
      :database => "rails_app"
    }
  },
  :repository => "git@github.com:username/repository.git",
  :revision => "master",
  :deploy_key => nil, # specify only if required
  :bundle_install_cmd => "bundle install --deployment --without development test cucumber staging"
}

default[:postgresql][:password][:postgres] = "rootpwthatissecure"