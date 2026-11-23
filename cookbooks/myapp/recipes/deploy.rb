#
# Cookbook:: myapp
# Recipe:: deploy
#
# The flow from your diagram:
#   create user + /opt/myapp -> download myapp-<version>.jar -> render
#   application.properties -> systemd unit -> restart only if something changed.

app      = node['myapp']
app_user = app['user']
base_dir = app['install_dir']
env_name = node.policy_group || 'local' # dev / uat / prod (or "local" in Test Kitchen)

# ---------------------------------------------------------------------------
# 1. Which version should this environment run?  (written by Jenkins)
# ---------------------------------------------------------------------------
release = begin
  data_bag_item(app['release_data_bag'], "myapp_#{env_name}")
rescue Net::HTTPClientException, Chef::Exceptions::InvalidDataBagPath, Chef::Exceptions::InvalidDataBagItemID
  nil
end

if release
  version  = release['version']
  checksum = release['sha256']
  url      = release['url'] || "#{app['artifact_base_url']}/myapp-#{version}.jar"
  log "myapp: policy group '#{env_name}' -> version #{version}"
else
  version = nil
  log "myapp: no release published for '#{env_name}' yet - preparing the server only" do
    level :warn
  end
end

# ---------------------------------------------------------------------------
# 2. Secrets from the encrypted data bag (decrypted on the node with
#    /etc/cinc/encrypted_data_bag_secret, which knife bootstrap installed).
# ---------------------------------------------------------------------------
secrets = begin
  data_bag_item(app['secrets_data_bag'], 'myapp')
rescue Net::HTTPClientException, Chef::Exceptions::InvalidDataBagPath, Chef::Exceptions::InvalidDataBagItemID
  raise 'Missing encrypted data bag item secrets/myapp - see walkthrough Part 5' if env_name != 'local'
  { 'api_key' => 'kitchen-test-key' }
end

# ---------------------------------------------------------------------------
# 3. Service account and directory layout
# ---------------------------------------------------------------------------
group app_user do
  system true
end

user app_user do
  gid app_user
  system true
  shell '/usr/sbin/nologin'
  home base_dir
  manage_home false
end

directory base_dir do
  owner 'root'
  group app_user
  mode '0755'
end

%w(releases shared).each do |sub|
  directory "#{base_dir}/#{sub}" do
    owner 'root'
    group app_user
    mode '0755'
  end
end

directory "#{base_dir}/logs" do
  owner app_user
  group app_user
  mode '0750'
end

# The service resource is declared once; other resources notify it.
service 'myapp' do
  action :nothing
end

# ---------------------------------------------------------------------------
# 4. Configuration file (template + attributes + secret)
# ---------------------------------------------------------------------------
template "#{base_dir}/shared/application.properties" do
  source 'application.properties.erb'
  owner 'root'
  group app_user
  mode '0640'        # readable by the app, not by other users
  sensitive true     # keep the api key out of Chef's diff output and logs
  variables(
    port:        app['port'],
    environment: env_name,
    version:     version || 'none',
    greeting:    app['greeting'],
    log_level:   app['log_level'],
    log_dir:     "#{base_dir}/logs",
    api_key:     secrets['api_key']
  )
  notifies :restart, 'service[myapp]', :delayed if version
end

# ---------------------------------------------------------------------------
# 5. systemd unit
# ---------------------------------------------------------------------------
systemd_unit 'myapp.service' do
  content(
    Unit: {
      Description: 'myapp Spring Boot service (managed by Chef)',
      After: 'network-online.target',
      Wants: 'network-online.target',
    },
    Service: {
      User: app_user,
      Group: app_user,
      WorkingDirectory: base_dir,
      # Quoted so the space inside JAVA_OPTS survives; systemd splits $JAVA_OPTS into args.
      Environment: "\"JAVA_OPTS=#{app['jvm_opts']}\"",
      ExecStart: "/usr/bin/java $JAVA_OPTS -jar #{base_dir}/current.jar " \
                 "--spring.config.additional-location=file:#{base_dir}/shared/application.properties",
      Restart: 'on-failure',
      RestartSec: 5,
      NoNewPrivileges: true,
      ProtectSystem: 'full',
      PrivateTmp: true,
    },
    Install: { WantedBy: 'multi-user.target' }
  )
  action [:create, :enable]
  notifies :restart, 'service[myapp]', :delayed if version
end

# ---------------------------------------------------------------------------
# 6. The artifact itself (only when a release exists for this group)
# ---------------------------------------------------------------------------
return unless version

jar = "#{base_dir}/releases/myapp-#{version}.jar"

remote_file jar do
  source url
  checksum checksum if checksum # verifies integrity AND skips the download if already present
  owner 'root'
  group app_user
  mode '0644'
end

link "#{base_dir}/current.jar" do
  to jar
  notifies :restart, 'service[myapp]', :delayed
end

# Make sure it's running even when nothing changed (e.g. someone stopped it by hand).
service 'myapp start' do
  service_name 'myapp'
  action :start
end

# Keep the 3 newest releases, delete older jars.
ruby_block 'prune old releases' do
  block do
    jars = Dir.glob("#{base_dir}/releases/myapp-*.jar").sort_by { |f| File.mtime(f) }
    (jars - [jar]).reverse.drop(2).each { |f| File.delete(f) }
  end
  only_if { Dir.glob("#{base_dir}/releases/myapp-*.jar").size > 3 }
end
