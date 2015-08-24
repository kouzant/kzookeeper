#
# DO NOT EDIT THIS FILE DIRECTLY - UNLESS YOU KNOW WHAT YOU ARE DOING
#

user node[:kzookeeper][:user] do
  action :create
  supports :manage_home => true
  home "/home/#{node[:kzookeeper][:user]}"
  shell "/bin/bash"
  not_if "getent passwd #{node[:kzookeeper]['user']}"
end

group node[:kzookeeper][:group] do
  action :modify
  members ["#{node[:kzookeeper][:user]}"]
  append true
end


# Pre-Experiment Code

require 'json'

include_recipe 'build-essential::default'
include_recipe 'java::default'

zookeeper node[:zookeeper][:version] do
  user        node[:kzookeeper][:user]
  mirror      node[:zookeeper][:mirror]
  checksum    node[:zookeeper][:checksum]
  install_dir node[:zookeeper][:install_dir]
  data_dir    node[:zookeeper][:config][:dataDir]
  action      :install
end

zk_ip = private_recipe_ip("kzookeeper", "default")

include_recipe "zookeeper::config_render"

template "#{node[:zookeeper][:base_dir]}/bin/zookeeper-start.sh" do
  source "zookeeper-start.sh.erb"
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:user]
  mode 0770
  variables({ :zk_ip => zk_ip })
end

template "#{node[:zookeeper][:base_dir]}/bin/zookeeper-stop.sh" do
  source "zookeeper-stop.sh.erb"
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:user]
  mode 0770
end

directory "#{node[:zookeeper][:base_dir]}/data" do
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:group]
  mode "755"
  action :create
  recursive true
end

config_hash = {
  clientPort: 2181, 
  dataDir: "#{node[:zookeeper][:base_dir]}/data", 
  tickTime: 2000,
  syncLimit: 3,
  initLimit: 60,
  autopurge: {
    snapRetainCount: 1,
    purgeInterval: 1
  }
}


node[:kzookeeper][:default][:private_ips].each_with_index do |ipaddress, index|
config_hash["server.#{index}"]="#{ipaddress}:2888:3888"
end

zookeeper_config "/opt/zookeeper/zookeeper-#{node[:zookeeper][:version]}/conf/zoo.cfg" do
  config config_hash
  user   node[:kzookeeper][:user]
  action :render
end

template '/etc/default/zookeeper' do
  source 'environment-defaults.erb'
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:group]
  action :create
  mode '0644'
  cookbook 'zookeeper'
  notifies :restart, 'service[zookeeper]', :delayed
end

template '/etc/init.d/zookeeper' do
  source 'zookeeper.initd.erb'
  owner 'root'
  group 'root'
  action :create
  mode '0755'
  notifies :restart, 'service[zookeeper]', :delayed
end

service 'zookeeper' do
  supports :status => true, :restart => true, :reload => true, :start => true, :stop => true
  action :enable
end

found_id=-1
id=1
my_ip = my_private_ip()

for zk in node[:kzookeeper][:default][:private_ips]
  if my_ip.eql? zk
    Chef::Log.info "Found matching IP address in the list of zkd nodes: #{zk}. ID= #{id}"
    found_id = id
  end
  id += 1

end 
Chef::Log.info "Found ID IS: #{found_id}"
if found_id == -1
  raise "Could not find matching IP address #{my_ip} in the list of zkd nodes: " + node[:kzookeeper][:default][:private_ips].join(",")
end



template "#{node[:zookeeper][:base_dir]}/data/myid" do
  source 'zookeeper.id.erb'
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:group]
  action :create
  mode '0755'
  variables({ :id => found_id })
  notifies :restart, 'service[zookeeper]', :delayed
end

list_zks=node[:kzookeeper][:default][:private_ips].join(",")

template "#{node[:zookeeper][:base_dir]}/bin/zkConnect.sh" do
  source 'zkClient.sh.erb'
  owner node[:kzookeeper][:user]
  group node[:kzookeeper][:group]
  action :create
  mode '0755'
  variables({ :servers => list_zks })
  notifies :restart, 'service[zookeeper]', :delayed
end
