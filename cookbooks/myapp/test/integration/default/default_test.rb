# InSpec: checks the END STATE of the server, not how Chef got there.
# Runs inside the Test Kitchen container (no app release there, so this checks
# that the server is fully *prepared*; test/smoke checks the live app on real VMs).

control 'base-01' do
  impact 1.0
  title 'SSH is hardened'
  describe file('/etc/ssh/sshd_config.d/10-hardening.conf') do
    it { should exist }
    its('content') { should match(/^PermitRootLogin no$/) }
    its('content') { should match(/^PasswordAuthentication no$/) }
  end
end

control 'base-02' do
  impact 1.0
  title 'Jenkins deploy user exists with least-privilege sudo'
  describe user('deploy') do
    it { should exist }
  end
  describe file('/home/deploy/.ssh/authorized_keys') do
    its('mode') { should cmp '0600' }
    its('content') { should include 'kitchen' }
  end
  describe file('/etc/sudoers.d/deploy') do
    its('content') { should include 'cinc-client' }
    its('content') { should_not match(/ALL\s*$/) } # no blanket "ALL" commands
  end
end

control 'myapp-01' do
  impact 1.0
  title 'Java runtime and service account'
  describe command('java -version') do
    its('exit_status') { should eq 0 }
    its('stderr') { should match(/version "21/) }
  end
  describe user('myapp') do
    it { should exist }
    its('shell') { should eq '/usr/sbin/nologin' }
  end
end

control 'myapp-02' do
  impact 1.0
  title 'Directory layout and protected config'
  %w(/opt/myapp /opt/myapp/releases /opt/myapp/shared /opt/myapp/logs).each do |d|
    describe directory(d) do
      it { should exist }
    end
  end
  describe file('/opt/myapp/shared/application.properties') do
    its('mode') { should cmp '0640' }
    its('owner') { should eq 'root' }
    its('group') { should eq 'myapp' }
    its('content') { should match(/^server\.port=8080$/) }
    its('content') { should match(/^app\.api-key=kitchen-fixture-key$/) }
  end
end

control 'myapp-03' do
  impact 0.7
  title 'systemd unit installed and enabled'
  describe file('/etc/systemd/system/myapp.service') do
    its('content') { should include 'User=myapp' }
    its('content') { should include 'NoNewPrivileges=true' }
  end
  describe service('myapp') do
    it { should be_enabled }
  end
end
