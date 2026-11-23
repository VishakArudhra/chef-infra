# Runs as the unprivileged `deploy` user, so every check here works without sudo.
port_num = input('app_port')
env      = input('expected_env')
version  = input('expected_version')
released = file('/opt/myapp/current.jar').exist? # false until the first app release

control 'smoke-01' do
  impact 1.0
  title 'myapp service is running and listening'
  only_if('no myapp release deployed to this node yet') { released }
  describe service('myapp') do
    it { should be_enabled }
    it { should be_running }
  end
  describe port(port_num) do
    it { should be_listening }
  end
end

control 'smoke-02' do
  impact 1.0
  title 'Health endpoint reports UP'
  only_if('no myapp release deployed to this node yet') { released }
  describe http("http://localhost:#{port_num}/actuator/health") do
    its('status') { should cmp 200 }
    its('body') { should match(/"status"\s*:\s*"UP"/) }
  end
end

control 'smoke-03' do
  impact 1.0
  title 'The right version is live in the right environment'
  only_if('no expected_version given') { released && !version.to_s.empty? }
  info = json(content: http("http://localhost:#{port_num}/").body)
  describe info do
    its('buildVersion')    { should cmp version }
    its('deployedVersion') { should cmp version }
    its('environment')     { should cmp env } unless env.to_s.empty?
  end
end

control 'smoke-04' do
  impact 0.7
  title 'Hardening and drift correction are in place'
  describe file('/etc/ssh/sshd_config.d/10-hardening.conf') do
    its('content') { should match(/^PermitRootLogin no$/) }
  end
  describe file('/opt/myapp/shared/application.properties') do
    its('mode')  { should cmp '0640' }
    its('owner') { should eq 'root' }
  end
  describe command('systemctl is-active cinc-client.timer') do
    its('stdout') { should match(/^active/) }
  end
end
