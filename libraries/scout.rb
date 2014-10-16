# Helper functions for the chef-scout cookbook
include Chef::Mixin::ShellOut

module Scout
  def self.gem_binary(node)
    gem_binary = if node[:scout][:rvm_wrapper]
      File.join(node[:scout][:rvm_wrapper],"gem")
    else # Shell out to see if we can get the ruby bindir. Ruby > 1.8.7 will raise ENOENT if there is no command found
      ruby_cmd = Mixlib::ShellOut.new("ruby", "-e", "require 'rbconfig'; puts RbConfig::CONFIG['bindir']", {}.merge(node[:scout][:gem_shell_opts]||{}))
      ruby_cmd.run_command
      ruby_cmd.error!
      File.join(ruby_cmd.stdout.chop,"gem") rescue nil
    end

    if !File.exist?(gem_binary)
      # Default to chef's built-in gem
      ruby_binary = File.join(RbConfig::CONFIG['bindir'],"gem")
    end

    Chef::Application.fatal!("Cannot find any gem_binary.") if !File.exist?(gem_binary)
    Chef::Log.info "Using gem_binary: #{gem_binary}"
    return gem_binary
  end

  def self.scout_binary(node)
    scout_binary = if node[:scout][:rvm_wrapper]
      File.join(node[:scout][:rvm_wrapper],"scout")
    elsif node[:scout][:bin]
      node[:scout][:bin]
    else
      gem_cmd = Mixlib::ShellOut.new("#{gem_binary(node)}", "env", {}.merge(node[:scout][:gem_shell_opts]||{}))
      gem_cmd.run_command
      gem_cmd.error!
      File.join(gem_cmd.stdout.split("\n").grep(/EXECUTABLE DIRECTORY/).first.split.last, "scout") rescue scout_binary = "scout"
    end
    Chef::Log.info "Using scout_binary: #{scout_binary}"
    return scout_binary
  end

  def self.install_gem(node, name_array)
    # name_array can be any array with:
    #   - a single element, e.g. ["scout"]
    #   - multiple elements accepted by 'gem install', e.g. ["scout", "--version", "5.9.5"]
    gem_cmd = Mixlib::ShellOut.new("#{gem_binary(node)}","install", *name_array, {}.merge(node[:scout][:gem_shell_opts]||{}))
    gem_cmd.run_command
    gem_cmd.error!
  end
end