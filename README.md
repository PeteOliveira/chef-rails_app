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
| shared_directories | {'vendor/bundle' => 'vendor_bundle',
                              "config/database.yml" => 'database.yml',
                              "config/unicorn.conf" => 'unicorn.conf',
                              "log" => 'log'} | overwrite if you'd like to define custom shared directories.
                              The value of the Hash can be a string or a hash that looks like this: {'file': ..., 'on_exists' => ('raise' (default) | 'ignore' | 'log' | 'overwrite')} |
| additional_shared_directories | {} | additionally share this directories that are merged in shared_directories. Use this if you want to keep the default shared directories. |
| worker_count | 3 | unicorn worker count |
| revision | HEAD | The revision to be checked out. This can be symbolic, like HEAD or it can be a source control management-specific revision identifier. |

