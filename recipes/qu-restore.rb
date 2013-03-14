path = 'queensunited/queensunited_magazine/2012.06.08.00.00.03.queensunited_magazine.tar.gz.enc'
tmp_file = '/tmp/qu.tar.gz.enc'
qu_folder = '/tmp/queensunited_magazine'

include_recipe 'rvm::system'
rvm_gem('aws-s3')
rvm_gem('backup')
rvm_gem('pg')

unless File.exists? tmp_file
  ruby_block "download backup" do
    block do
      Gem.clear_paths
      require 'aws/s3'

      AWS::S3::DEFAULT_HOST.replace "s3-eu-west-1.amazonaws.com"
      AWS::S3::Base.establish_connection!(
        :access_key_id     => 'AKIAJPOEFDWUMMT3AMRQ',
        :secret_access_key => 'RXElg55xCq+KnwzbbuAJu3CJwMD3BGwJ/NcbHd5h'
      )

      Chef::Log.info "S3 File exists?: #{AWS::S3::S3Object.exists? path, 'riotworks-backups'}"

      
        open(tmp_file, 'w') do |file|
          AWS::S3::S3Object.stream(path, 'riotworks-backups') do |chunk|
            file.write chunk
          end
        end
      end
    end
end

execute "decrypt backup" do
  cwd '/tmp'
  command <<-END
    histchars=
    openssl aes-256-cbc -d -base64 -pass pass:queensunitedftw!!! -salt -in #{tmp_file} -out #{tmp_file[0...-4]}
    END
  creates tmp_file[0...-4]
end

execute "untar backup" do
  cwd '/tmp'
  command "tar xzf #{tmp_file[0...-4]}"
  creates qu_folder
end

nb = Class.new.send(:extend, NodeBase)
qu_item = nb.symbolize_keys(data_bag_item('rails_apps', 'staging-www-queensunited-com').to_hash)
qu_item_db = qu_item[:databases][:production]

execute 'drop tables' do
  user 'postgres'
  command <<-END
  psql -t -d #{qu_item_db[:database]} -c "select 'DROP TABLE IF EXISTS ' || table_name || ' CASCADE;' from information_schema.tables where table_schema = 'public';" > /tmp/drop_all
  psql -d #{qu_item_db[:database]} -f /tmp/drop_all
  export PGPASSWORD=#{qu_item_db[:password]}
  psql -d #{qu_item_db[:database]} -U #{qu_item_db[:username]} < "#{qu_folder}/PostgreSQL/queensmagazine.sql"
  rm /tmp/drop_all
  END
end


execute "extract system folder" do
  command "tar xf #{qu_folder}/archive/system_folder.tar"
  cwd '/tmp'
  creates '/tmp/home'
end

execute 'move system folder' do
  command <<-END
    rm -rf #{qu_item[:deploy_to]}/shared/system
    mv /tmp/home/robin/domains/magazine.queensunited.com/httpdocs/shared/system #{qu_item[:deploy_to]}/shared/system
    chown -R #{qu_item[:escaped_name]}:www-data #{qu_item[:deploy_to]}/shared/system
  END
end

execute 'cleanup' do
  command "rm -rf #{tmp_file} /tmp/home /tmp/queensunited_magazine"
end

service qu_item[:escaped_name] do
  action :restart
end