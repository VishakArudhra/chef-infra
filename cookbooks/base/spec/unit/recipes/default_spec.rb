require 'spec_helper'

describe 'base::default' do
  let(:chef_run) do
    ChefSpec::SoloRunner.new do |node|
      node.normal['base']['deploy_user']['authorized_keys'] = ['ssh-ed25519 AAAATEST jenkins-deploy']
    end.converge(described_recipe)
  end

  before do
    # `execute` guards are shell commands; ChefSpec makes you decide their result.
    stub_command("ufw show added | grep -qx 'ufw allow 22/tcp'").and_return(false)
    stub_command("ufw status | grep -q 'Status: active'").and_return(false)
  end

  it 'installs baseline packages' do
    expect(chef_run).to install_package('baseline packages')
      .with(package_name: %w(curl vim htop unattended-upgrades))
  end

  it 'writes the SSH hardening drop-in and restarts ssh only via notification' do
    expect(chef_run).to render_file('/etc/ssh/sshd_config.d/10-hardening.conf')
      .with_content('PermitRootLogin no')
      .with_content('PasswordAuthentication no')
    tpl = chef_run.template('/etc/ssh/sshd_config.d/10-hardening.conf')
    expect(tpl).to notify('service[ssh]').to(:restart).delayed
  end

  it 'opens ssh before enabling the firewall' do
    expect(chef_run).to run_execute('ufw allow ssh (22/tcp)')
    expect(chef_run).to run_execute('ufw enable')
  end

  it 'creates a deploy user that may only run cinc-client as root' do
    expect(chef_run).to create_user('deploy')
    expect(chef_run).to render_file('/home/deploy/.ssh/authorized_keys').with_content('jenkins-deploy')
    expect(chef_run).to create_sudo('deploy').with(
      nopasswd: true,
      commands: %w(/usr/bin/cinc-client /usr/bin/chef-client /opt/cinc/bin/cinc-client)
    )
  end

  it 'schedules cinc-client every 30 minutes' do
    expect(chef_run).to add_chef_client_systemd_timer('cinc-client').with(interval: '30min')
  end

  context 'when the firewall is switched off (e.g. in containers)' do
    let(:chef_run) do
      ChefSpec::SoloRunner.new { |n| n.normal['base']['firewall']['enabled'] = false }.converge(described_recipe)
    end

    it 'does not touch ufw' do
      expect(chef_run).not_to run_execute('ufw enable')
    end
  end
end
