Description
===========

This cookbook deploys a Rails Application. 

Requirements
============

**OS**:

- ubuntu 12.04

**Cookbooks:**

- **postfix**: https://github.com/cookbooks/postfix.git
- **postgresql**: https://github.com/phlipper/chef-postgresql
- **nginx**: https://github.com/cookbooks/nginx.git
- **rvm**: https://github.com/fnichol/chef-rvm

**Other**:

- unicorn must be in the Gemfile

Attributes
==========

- `:rails_app => {:data_bags => %w()}``

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

| Attributes | Default Value |
| ---------- | ------------- |
| name       | app['id']     |
| user       | app['name']   |
| domains    | ['default']   |
| seed       | false         |
| deploy_to  | /srv/www/#{app['name']} |

