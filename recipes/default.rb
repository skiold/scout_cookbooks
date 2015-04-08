#
# Cookbook Name:: scout
# Recipe:: default

Chef::Log.info "Loading: #{cookbook_name}::#{recipe_name}"


# create group and user
group node[:scout][:group] do
  action [ :create, :manage ]
end.run_action(:create)

user node[:scout][:user] do
  comment "Scout Agent"
  gid node[:scout][:group]
  home "/home/#{node[:scout][:user]}"
  supports :manage_home => true
  action [ :create, :manage ]
  only_if do node[:scout][:user] != 'root' end
end.run_action(:create)

# wrap calls to the Scout library in ruby_block
# this prevents code that looks for binaries from being executed before the run_list
ruby_block "install the scout agent gem" do
  block do
    # install scout agent gem
    if node[:scout][:version]
      Scout.install_gem(node, ["scout", "--version", "#{node[:scout][:version]}"])
    else
      Scout.install_gem(node, ["scout"])
    end
  end
end

if node[:scout][:key]
  # wrap calls to the Scout library in ruby_block
  ruby_block "find the scout binary" do
    block do
      scout_bin = Scout.scout_binary(node)
      hostname_attr = node[:scout][:hostname] ? %{ --hostname "#{node[:scout][:hostname]}"} : ""
      name_attr = node[:scout][:name] ? %{ --name "#{node[:scout][:name]}"} : ""
      server_attr = node[:scout][:server] ? %{ --server "#{node[:scout][:server]}"} : ""
      roles_attr = node[:scout][:roles] ? %{ --roles "#{node[:scout][:roles].map(&:to_s).join(',')}"} : ""
      http_proxy_attr = node[:scout][:http_proxy] ? %{ --http-proxy "#{node[:scout][:http_proxy]}"} : ""
      https_proxy_attr = node[:scout][:https_proxy] ? %{ --https-proxy "#{node[:scout][:https_proxy]}"} : ""
      environment_attr = node[:scout][:environment] ? %{ --environment "#{node[:scout][:environment]}"} : ""

      if(File.exist?(scout_bin))
        # schedule scout agent to run via cron
        # need to instantiate the resource manually inside a ruby_block
        cron = Chef::Resource::Cron.new("scout_run", run_context)
        cron.user node[:scout][:user]
        cron.command "#{scout_bin} #{node[:scout][:key]}#{hostname_attr}#{name_attr}#{server_attr}#{roles_attr}#{http_proxy_attr}#{https_proxy_attr}#{environment_attr}"
        cron.run_action :create
      end
    end
  end
else
  Chef::Log.warn "The agent will not report to scoutapp.com as a key wasn't provided. Provide a [:scout][:key] attribute to complete the install."
end

if node[:scout][:public_key]
  home_dir = Dir.respond_to?(:home) ? Dir.home(node[:scout][:user]) : File.expand_path("~#{node[:scout][:user]}")
  data_dir = "#{home_dir}/.scout"
  # create the .scout directory
  directory data_dir do
    group node[:scout][:group]
    owner node[:scout][:user]
    mode "0755"
  end
  template "#{data_dir}/scout_rsa.pub" do
    source "scout_rsa.pub.erb"
    mode 0440
    owner node[:scout][:user]
    group node[:scout][:group]
    action :create
  end
end

if node[:scout][:delete_on_shutdown]
  gem_package 'scout_api'
  template "/etc/rc0.d/scout_shutdown" do
    source "scout_shutdown.erb"
    owner "root"
    group "root"
    mode 0755
  end
else
  bash "delete_scout_shutdown" do
    user "root"
    code "rm -f /etc/rc0.d/scout_shutdown"
  end
end

(node[:scout][:plugin_gems] || []).each do |gemname|
  # wrap calls to the Scout library in ruby_block
  ruby_block "install a gem" do
    block do
      Scout.install_gem(node, Array(gemname))
    end
  end
end

# Create plugin lookup properties
directory "/home/#{node[:scout][:user]}/.scout" do
  owner node[:scout][:user]
  group node[:scout][:group]
  recursive true
end
template "/home/#{node[:scout][:user]}/.scout/plugins.properties" do
  source "plugins.properties.erb"
  mode 0664
  owner node[:scout][:user]
  group node[:scout][:group]
  variables lazy {
    plugin_properties = {}
    node['scout']['plugin_properties'].each do |property, lookup_hash|
      plugin_properties[property] = Chef::EncryptedDataBagItem.load(lookup_hash[:encrypted_data_bag], lookup_hash[:item])[lookup_hash[:key]]
    end
    {
      :plugin_properties => plugin_properties
    }
  }
  action :create
end
