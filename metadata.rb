maintainer       "Robin Wenglewski"
maintainer_email "robin@wenglewski.de"
license          "All rights reserved"
description      "Installs/Configures a rails application"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.0.1"



depends 'postfix'

# https://github.com/phlipper/chef-postgresql, ref: ff499fcff50c1113f74cc32352ebfbede93a06cc
depends 'postgresql'

depends 'nginx'

supports 'ubuntu', "= 12.04"

attribute "deploy_key",
          :display_name => "key required to checkout the repository"

attribute "authorized_key",
          :display_name => "key to add to authorized_keys for the user to be created"
