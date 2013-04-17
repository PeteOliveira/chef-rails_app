Description
===========

This cookbook deploys a Rails Application. 

Requirements
============

**OS**:

- ubuntu 12.04

**Cookbooks:**

- **postgresql**: https://github.com/phlipper/chef-postgresql
- **nginx**: https://github.com/cookbooks/nginx.git
- **rvm**: https://github.com/fnichol/chef-rvm

**Other**:

- unicorn must be in the Gemfile

Attributes
==========

- `:rails_app => {:data_bags => %w()}``

Chef Callbacks
==============

The Rails recipe has a couple of chef callback which allow your app to customize the environment.
The following files will be included in the recipe at runtime:

```
/deploy/hooks/before_bundle_install.rb
/deploy/hooks/after_bundle_install.rb
/deploy/hooks/before_restart.rb
````

With it, you receive the `variables` variable, which is a hash looking like that: `variables['app']`.

You can use the callbacks for installing packages, running background jobs, etc.

Usage
=====

Fill the rails_app/data_bags attribute with the apps you want to deploy. Create data_bags according to this file:

```json
{
    "id": "same as file name",
    "repository": "git@bitbucket.org:your/repo.git",
    "precompile": true,
    "rails_env": "production",
    "databases": {
        "production": {
            "adapter": "postgresql",
            "username": "vagrant",
            "password": "vagrant",
            "database": "app_dev"
        }
    },
    "deploy_key": "id_rsa content as one line with \n",
    "authorized_key": "id_rsa.pub content"
}
```

optional attributes:

| Attributes | Default Value | Description |
| ---------- | ------------- | ----------- |
| name       | app['id']     | app name |
| user       | app['name']   | unix user name, should be uniq cause home directory is created |
| domains    | ['default']   | domains to which the app responds |
| seed       | false         | rake seed? |
| deploy_to  | /srv/www/#{app['name']} | home directory of user and parent dir of app (which resides in `current/` |
| shared_directories | see below | see below |
| additional_shared_directories | {} | additionally share this directories that are merged in shared_directories. Use this if you want to keep the default shared directories. |
| worker_count | 3 | unicorn worker count |
| revision | HEAD | The revision to be checked out. This can be symbolic, like HEAD or it can be a source control management-specific revision identifier. |

`shared_directories` and `additional_shared_directories` structure:

```json
{
    "config/database.yml": true,
    "config/database.yml": "database.yml",
    "config/database.yml": {"file": "database.yml", "on_exists": "raise"}
}
```

Values of the array can be either string or hash.
The `on_exists` value can be `raise`, `ignore`, `log`, `overwrite`. Default is `raise`.

# Troubleshooting

## Cannot find a resource for create_rvm_shell_chef_wrapper

On EC2 & Hetzner:

If you run into

    NameError: Cannot find a resource for create_rvm_shell_chef_wrapper on ubuntu version 12.04

Then see [here](https://github.com/fnichol/chef-rvm/issues/178). Seems only way right now is to downgrade the
chef gem.

## Deployment on Hetzner

After the user has been created and chef fails, login and do

    echo "insecure" > ~/.curlrc

Somehow the curl certificates are messed up. This disables https certificate checking.

## gems / rubies not set

Try logging into your machine as your user `sudo su - USER` and ensure rvm is installed.
If it isn't, try running the command from the chef log manually.
If it is, try installing the Ruby you want to install manually.

Basically, just try to reproduce the steps chef takes and observe anything suspicious.



