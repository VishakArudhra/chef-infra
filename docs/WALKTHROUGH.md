# On-prem Chef + Jenkins Lab: step-by-step walkthrough

You'll build a small version of the setup in Vishak's experience note. A Chef codebase hardens and configures on-prem Linux servers. A Jenkins pipeline tests every change before promoting it through dev → uat → prod. Servers fix their own drift on a schedule. A dependency check stops a wrong version pin from ever reaching a server. At the end, a `git push` of Java code builds the app and Chef rolls it out to every node.

**Time:** about 2 days. Parts 1–6 on day 1 (infrastructure and Chef), Parts 7–9 on day 2 (Jenkins, the end-to-end release, and the break/fix exercises).

---

## Part 0: What you're building

```
  MacBook (workstation)                       Windows laptop (on-prem "data centre")
  ─────────────────────                       ─────────────────────────────────────────
  VS Code, git, knife, cinc,                  VirtualBox VMs, bridged onto your Wi-Fi:
  cookstyle                                    ┌───────────────────────────────────────┐
        │  git push                            │ chef-server  .240  Cinc Infra Server  │
        ▼                                      │ jenkins      .241  Jenkins + Docker   │
  ┌──────────┐   polls every 2 min             │                    + artifact repo    │
  │  GitHub  │ ◄───────────────────────────────┤ app01        .251  policy group: dev  │
  │ chef-infra│                                │ app02        .252  policy group: uat  │
  │ myapp     │                                │ app03        .253  policy group: prod │
  └──────────┘                                 └───────────────────────────────────────┘
```

**The myapp release flow** (your diagram):

```
git push (myapp) → Jenkins: checkout → mvn package → mvn test → publish jar to :8081
  → Chef validation (are dev/uat/prod on approved cookbook versions?)
  → write data bag releases/myapp_dev = {version, sha256}
  → knife ssh "policy_group:dev" "sudo cinc-client"
        cinc-client: get policy → install Java → create /opt/myapp → download jar
                     → render application.properties → systemd unit → restart if changed
  → InSpec smoke tests over SSH → repeat for uat → [approve] → prod
```

**The cookbook flow** (Vishak's "tests each change before promoting it"):

```
git push (chef-infra) → Jenkins: Cookstyle → ChefSpec → Test Kitchen + InSpec (Docker)
  → cinc install (lock) → dependency gate → cinc push dev → converge → InSpec
  → same lock to uat → [approve] → prod
```

**Why two repos?** This is the common industry split. App code and infrastructure code change at different rates, often belong to different teams, and need different pipelines. A branch-per-purpose setup in one repo is rare and awkward.

**Why Cinc and not Chef?** Progress Chef binaries need a licence key. Cinc is the free community build of the same open-source code. Every command is the same apart from the binary names (`cinc-client` = `chef-client`, `cinc` = `chef`, `cinc-auditor` = `inspec`), and the `chef-*` names are also installed as wrappers. On a CV or in an interview, this is Chef.

**Why GitHub?** Neither GitHub nor Bitbucket is open source, but both are free for private repos. GitHub has the simplest token setup. The Jenkins side is identical for Bitbucket: only the repo URL and credential change. (Jenkins sits on your home network, so it polls for changes instead of receiving webhooks. Polling works the same with either service.)

---

## Part 1: Prepare the Windows laptop (about 45 min)

### 1.1 Install the software
1. **VirtualBox**: the latest 7.2.x from virtualbox.org (Windows hosts). Install it with "Run as administrator", then reboot.
2. **Vagrant**: the latest from developer.hashicorp.com/vagrant/install (AMD64). Use 2.4.9 or newer; older versions reject VirtualBox 7.2. Reboot again.
3. **Git for Windows**: from git-scm.com. Accept the defaults.

Check in **PowerShell**:
```powershell
vagrant --version
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
git --version
```

### 1.2 Make VirtualBox fast (Hyper-V check)
If Windows' Hyper-V layer is on, VirtualBox still runs, but slowly. You'll see a green turtle icon in the VM's status bar.
- **Windows Security → Device security → Core isolation → Memory integrity: Off**
- If you don't use WSL2 or Docker Desktop, run this in an admin PowerShell, then reboot:
  ```powershell
  bcdedit /set hypervisorlaunchtype off
  ```
  (`bcdedit /set hypervisorlaunchtype auto` undoes it.)

### 1.3 Keep the laptop awake
It's your data centre now.
- **Settings → System → Power**: when plugged in, set screen off to 30 min and sleep to **Never**.
- **Control Panel → Power Options → Choose what closing the lid does**: plugged in → **Do nothing**.

### 1.4 Collect the network values for `lab.yml`
```powershell
ipconfig
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list bridgedifs
```
Write down:
- From `ipconfig`, under *Wireless LAN adapter Wi-Fi*: the **IPv4 address**, e.g. `192.168.1.23`. Your subnet is the first three parts: `192.168.1`.
- From `list bridgedifs`: the **Name:** line of the adapter whose IP matches, e.g. `Intel(R) Wi-Fi 6 AX201 160MHz`. Copy it exactly.

Now pick five free addresses. The defaults are `.240 .241 .251 .252 .253`. Check that each one is unused (you want "Request timed out" or "Destination host unreachable"):
```powershell
240,241,251,252,253 | % { ping -n 1 -w 500 "192.168.1.$_" | Select-String "Reply from" }
```
No output means all five are free. If your router's admin page shows the DHCP range, stay outside it.

> **If your Wi-Fi blocks devices from talking to each other** (common on guest or corporate networks, called "AP/client isolation"), the Mac won't reach the VMs. Use your normal home network, or see Troubleshooting.

---

## Part 2: Prepare the MacBook (about 30 min)

### 2.1 Tools
```bash
# Homebrew (skip if you have it): https://brew.sh
brew install git gh
brew install --cask visual-studio-code        # optional but recommended

# Cinc Workstation 26: knife, cinc, cookstyle, chefspec, kitchen, cinc-auditor
curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-workstation -v 26
```
Open a **new** terminal and check:
```bash
cinc --version && knife --version && cookstyle --version && cinc-auditor version
```
Optional: add `eval "$(cinc shell-init zsh)"` to `~/.zshrc` so `ruby`/`rspec` use the workstation's embedded Ruby.

### 2.2 SSH keys
You need two key pairs. Keeping them separate is a real-world habit: people and CI never share keys.
```bash
mkdir -p ~/chef-lab-keys && chmod 700 ~/chef-lab-keys

# 1) YOUR key: you as admin (SSH as `vagrant`, knife bootstrap)
ssh-keygen -t ed25519 -f ~/.ssh/chef_lab -C "shruthi-mac"

# 2) JENKINS deploy key: may only run cinc-client as root on the nodes
ssh-keygen -t ed25519 -f ~/chef-lab-keys/jenkins_deploy -N "" -C "jenkins-deploy"
```

### 2.3 Name resolution and an SSH shortcut
Use your own subnet:
```bash
sudo tee -a /etc/hosts <<'EOF'
# chef-lab
192.168.1.240 chef-server.lab.internal chef-server
192.168.1.241 jenkins.lab.internal jenkins
192.168.1.251 app01.lab.internal app01
192.168.1.252 app02.lab.internal app02
192.168.1.253 app03.lab.internal app03
EOF

cat >> ~/.ssh/config <<'EOF'

Host *.lab.internal chef-server jenkins app01 app02 app03
  User vagrant
  IdentityFile ~/.ssh/chef_lab
  StrictHostKeyChecking accept-new
EOF
```

---

## Part 3: Put the code on GitHub (about 20 min)

### 3.1 Unpack the two repos
Unzip `chef-infra.zip` and `myapp.zip` into `~/code/`, so you have `~/code/chef-infra` and `~/code/myapp`.

### 3.2 Personalise before the first commit
```bash
cd ~/code/chef-infra
# a) Your Mac's PUBLIC key goes into the lab, so `vagrant up` authorises it.
#    (Public keys are safe to commit.)
cp ~/.ssh/chef_lab.pub lab/keys/shruthi-mac.pub

# b) Network values from Part 1.4
code lab/lab.yml           # set bridge_adapter and subnet (and the IPs if you changed them)
```
If you changed the subnet or IPs, also update the URLs that mention `lab.internal` (they use names, so usually nothing changes).

In `~/code/myapp/Jenkinsfile`, set `INFRA_REPO` to `https://github.com/<your-user>/chef-infra.git`.

### 3.3 Create the repos and push
```bash
gh auth login                       # GitHub.com → HTTPS → login with browser

cd ~/code/chef-infra
git init -b main && git add . && git commit -m "Initial chef-infra: cookbooks, policy, lab, CI"
gh repo create chef-infra --private --source=. --push

cd ~/code/myapp
git init -b main && git add . && git commit -m "Initial myapp service"
gh repo create myapp --private --source=. --push
```

### 3.4 Create a read-only token for Jenkins
On GitHub, go to **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**:
- Repository access: *Only select repositories* → `chef-infra`, `myapp`
- Permissions → Repository → **Contents: Read-only**

Save the token in your password manager. You'll need it in Part 7.

> **Bitbucket instead?** Create the two repos in a Bitbucket workspace, push with `git remote add origin … && git push -u origin main`, and give Jenkins a Bitbucket **API token** with read access to repositories. Everything else is the same.

---

## Part 4: Bring up the VMs on Windows (about 45–60 min, mostly waiting)

In PowerShell on the Windows laptop:
```powershell
cd $HOME
git clone https://github.com/<your-user>/chef-infra.git     # sign in when Git asks
cd chef-infra\lab

vagrant up chef-server      # ~15 min: downloads the Ubuntu box, installs Cinc Server
vagrant up jenkins          # ~15 min: Java, Maven, Docker, Jenkins, Cinc Workstation
vagrant up app01 app02 app03
vagrant status
```
- Allow VirtualBox through the Windows firewall if asked.
- At the end of `chef-server` and `jenkins`, the output prints a banner with URLs. The Jenkins one includes the **initial admin password**. Copy it.
- `.gitattributes` keeps the shell scripts in Linux line endings, so cloning on Windows is safe.

**Check from the Mac:**
```bash
for h in chef-server jenkins app01 app02 app03; do ping -c1 -t1 $h.lab.internal >/dev/null && echo "$h ok" || echo "$h UNREACHABLE"; done
ssh chef-server.lab.internal 'hostname -f; free -h | head -2'
open http://jenkins.lab.internal:8080
```

**Day-to-day:** `vagrant halt` stops everything and `vagrant up` brings it all back. When RAM is tight, run `vagrant halt app03` and only start prod when you need it.

---

## Part 5: Connect your Mac to the Chef Server (about 30 min)

Everything here runs in `~/code/chef-infra` on the Mac.

### 5.1 Keys and TLS trust
```bash
cd ~/code/chef-infra
scp chef-server.lab.internal:keys/admin.pem   .chef/admin.pem
scp chef-server.lab.internal:keys/jenkins.pem ~/chef-lab-keys/jenkins.pem

knife ssl fetch          # trust the server's self-signed cert (stored in .chef/trusted_certs)
knife ssl check
knife user list          # → admin, jenkins       (proves auth works)
knife config show        # shows which config.rb is in use
```
`.chef/config.rb` (also linked as `.cinc/`) reads these files. `.gitignore` keeps `*.pem` and the secret out of Git, so check with `git status` that no key ever appears there.

### 5.2 Secrets: encrypted data bag
The app needs an API key. It must never sit in Git or in plain attributes.
```bash
openssl rand -base64 512 | tr -d '\r\n' > .chef/encrypted_data_bag_secret
chmod 600 .chef/encrypted_data_bag_secret

cp data_bags/secrets/myapp.example.json data_bags/secrets/myapp.json
code data_bags/secrets/myapp.json            # set "api_key" to anything; file is git-ignored

knife data bag create secrets
knife data bag from file secrets data_bags/secrets/myapp.json --encrypt
knife data bag show secrets myapp                     # what the server sees: ciphertext
knife data bag show secrets myapp --secret-file .chef/encrypted_data_bag_secret   # decrypted

knife data bag create releases                        # Jenkins writes app versions here
```

### 5.3 The policy
Open `policyfiles/myapp.rb` and replace the `REPLACE-ME` line with your Jenkins **public** key:
```bash
cat ~/chef-lab-keys/jenkins_deploy.pub     # paste this whole line between the quotes
```
Then resolve, gate and push:
```bash
cinc install policyfiles/myapp.rb            # creates policyfiles/myapp.lock.json
python3 ci/check_versions.py --lock policyfiles/myapp.lock.json --approved approved-versions.json

for g in dev uat prod; do cinc push $g policyfiles/myapp.rb; done
cinc show-policy                             # myapp: dev, uat, prod → same revision id

git add policyfiles approved-versions.json && git commit -m "Lock myapp policy" && git push
```
**Concepts:** The *Policyfile* says what a node runs (its run list and exact cookbook versions). The *lock* is the resolved answer to that. A *policy group* (dev/uat/prod) is where a lock is active. Promotion means pushing the **same lock** to the next group, so uat runs byte-for-byte what was tested in dev.

---

## Part 6: Bootstrap the nodes (about 30 min)

`knife bootstrap` installs cinc-client on a server, registers it with the Chef Server, assigns its policy and group, copies the data bag secret, and runs Chef for the first time.

```bash
cd ~/code/chef-infra
bootstrap() {   # $1 = node name, $2 = policy group
  knife bootstrap "$1.lab.internal" -N "$1" \
    -U vagrant -i ~/.ssh/chef_lab --sudo \
    --policy-name myapp --policy-group "$2" \
    --secret-file .chef/encrypted_data_bag_secret \
    --bootstrap-install-command "curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc -v 19" \
    --ssh-verify-host-key accept_new
}
bootstrap app01 dev
bootstrap app02 uat
bootstrap app03 prod

knife node list
knife status                       # last check-in time for each node
knife node show app03 -a myapp     # prod got greeting "Hello from PROD", log_level WARN
```
Read the first converge output. You'll see the hardening, the deploy user, ufw, the cinc-client timer, Java, `/opt/myapp`, and a warning: *no release published for 'dev' yet - preparing the server only*. That's expected, because Jenkins hasn't built the app yet.

### 6.1 See idempotency and drift correction for yourself
```bash
ssh app01.lab.internal
sudo cinc-client                        # 2nd run → "0/NN resources updated"  ← idempotency
sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config.d/10-hardening.conf
sudo cinc-client                        # shows the diff, puts "no" back, restarts ssh
systemctl list-timers | grep cinc       # next scheduled run (every 30 min ± 5)
sudo ls /etc/cinc                       # client.rb, client.pem, encrypted_data_bag_secret
exit
```
This is the mechanism behind Vishak's "manual hotfixes pulling production servers out of line". Chef puts every server back to its intended state on a schedule.

---

## Part 7: Jenkins (about 45 min)

### 7.1 First login
Open http://jenkins.lab.internal:8080 and paste the initial admin password. If you lost it, run `ssh jenkins.lab.internal sudo cat /var/lib/jenkins/secrets/initialAdminPassword`. Then choose **Install suggested plugins** and create your admin user.

### 7.2 Credentials
Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**. The IDs must match exactly:

| Kind | ID | Value |
|---|---|---|
| Username with password | `github-pat` | your GitHub username + the token from Part 3.4 |
| Secret file | `chef-jenkins-key` | upload `~/chef-lab-keys/jenkins.pem` |
| SSH Username with private key | `deploy-ssh-key` | username `deploy`; *Enter directly*: paste the contents of `~/chef-lab-keys/jenkins_deploy` (the private key) |

(In Finder, press ⌘⇧. to show hidden folders, or run `open ~/chef-lab-keys`.)

### 7.3 Create the two pipeline jobs
For each repo: **New Item → name → Pipeline → OK**, then:
- *Pipeline → Definition:* **Pipeline script from SCM**
- *SCM:* Git. *Repository URL:* `https://github.com/<you>/chef-infra.git` (then `…/myapp.git`). *Credentials:* `github-pat`
- *Branch Specifier:* `*/main`. *Script Path:* `Jenkinsfile`
- Save.

### 7.4 Run the cookbook pipeline first
Open **chef-infra → Build Now**, then watch *Console Output* or the stage view.
- **Cookstyle → ChefSpec → Test Kitchen.** The first Kitchen run downloads the `dokken/ubuntu-24.04` and `cincproject/cinc:19` images (5–10 min). Kitchen converges the *real* policy in a container, and then InSpec checks the end state.
- **Deploy dev / uat**, each running `ci/deploy_policy.sh`: gate → `cinc push` → `knife ssh … sudo cinc-client` → InSpec smoke tests over SSH.
- **Approve prod**: hover over the paused stage and click **Promote**.

This first manual build also registers the `pollSCM` trigger. From now on, any push to chef-infra starts this pipeline within about 2 minutes.

---

## Part 8: The moment: push Java code, watch it reach every node

### 8.1 First myapp build
Open **myapp → Build Now** (this registers its trigger). Watch all the stages: checkout → build → tests → publish (`http://jenkins.lab.internal:8081/myapp/`) → Chef validation → dev → uat → approve → prod.

```bash
for h in app01 app02 app03; do curl -s http://$h.lab.internal:8080/; echo; done
```
Each node reports the same `buildVersion` and `deployedVersion` (e.g. `1.0.1`) but a different `environment` and `greeting`. That's one artifact with configuration per environment, all driven by Chef.

### 8.2 Now change the code and push
In `~/code/myapp/src/main/java/com/lab/myapp/InfoController.java`, add a field to `info()`:
```java
body.put("message", "Deployed by Jenkins + Chef");
```
Then push it:
```bash
cd ~/code/myapp
git commit -am "Add deploy message" && git push
```
Within about 2 minutes, Jenkins starts **build #2** by itself. When dev and uat are green, approve prod, then check:
```bash
for h in app01 app02 app03; do curl -s http://$h.lab.internal:8080/ | python3 -m json.tool | grep -E 'Version|message|environment'; done
ssh app03.lab.internal 'ls /opt/myapp/releases; readlink /opt/myapp/current.jar'
```
That's the whole chain from your diagrams: **Git → Jenkins → validate → Chef Server/policy → cinc-client → on-prem Linux → recipe → resources → package/config/service.**

---

## Part 9: Break it, fix it (this is where the experience comes from)

Do each exercise on a branch or as a normal commit. Watch where the pipeline catches it, then fix it.

### 9.1 Lint and unit tests catch mistakes in seconds
- In `cookbooks/myapp/attributes/default.rb`, change the port to `9090` and push. **ChefSpec fails** (`server.port=8080` expected). Revert.
- Write `package "curl"` with double quotes plus an unused variable in a recipe, then push. **Cookstyle fails**. Fix it locally with `cookstyle -a cookbooks/`.

### 9.2 Test Kitchen catches a security regression
In `deploy.rb`, change the template `mode '0640'` to `'0644'` and push. ChefSpec still passes (it only checks what you asked it to). **Kitchen's InSpec control `myapp-02` fails**: the config is world-readable. The lesson: unit tests check intent, and InSpec checks reality.

### 9.3 A runtime failure on the server: troubleshoot like on-call
In `policyfiles/myapp.rb`, add `default['dev']['myapp']['jvm_opts'] = '-Xmx64g'`. Then run `cinc update policyfiles/myapp.rb` and push. Kitchen passes, because no app runs in Kitchen. Dev converges, but the **smoke test fails**: the service won't start. Investigate exactly as in your notes:
```bash
ssh app01.lab.internal
systemctl status myapp
journalctl -u myapp -n 50 --no-pager        # "Could not reserve enough space for object heap"
sudo cat /opt/myapp/shared/application.properties
systemctl cat myapp                          # the unit Chef generated
```
Revert, run `cinc update`, and push. The pipeline goes green and **uat and prod were never touched**. That's why you promote step by step.

### 9.4 Reproduce Vishak's UAT incident, and the fix he built
*"A version pin left over from an earlier release was forcing an outdated dependency into that environment."*

1. **Release a new base cookbook.** Add `tree` to `default['base']['packages']`. Bump `cookbooks/base/metadata.rb` to `version '1.1.0'` and set `"base": "1.1.0"` in `approved-versions.json`. Run `cinc update policyfiles/myapp.rb`, then commit and push. The pipeline promotes base 1.1.0 to dev, uat and prod.
2. **Create the leftover pin.** Someone pushes an old lock to uat from a laptop. Simulate it from a checkout of the previous commit (the one before the base 1.1.0 bump):
   ```bash
   cd ~/code/chef-infra
   git worktree add /tmp/old-release HEAD~1
   (cd /tmp/old-release && cinc push uat policyfiles/myapp.rb -c ~/code/chef-infra/.chef/config.rb)
   git worktree remove /tmp/old-release
   knife raw /policy_groups/uat/policies/myapp \
     | python3 -c 'import json,sys; print(json.load(sys.stdin)["cookbook_locks"]["base"]["version"])'   # → 1.0.0
   ```
3. **Try to release the app.** Push any small change to myapp. Stage **5. Chef validation** fails:
   `base: group 'uat' runs 1.0.0, approved is '1.1.0'`. The mismatch is caught before anything reaches a server.
4. **Fix the root cause.** Re-run the chef-infra pipeline. It promotes the approved lock to uat again, and the gate shows `1.0.0 -> 1.1.0 (changed)`. Re-run myapp, and it's green.
5. **Also try the other kind of pin.** Set `depends 'base', '= 1.0.0'` in `cookbooks/myapp/metadata.rb` and run `cinc update policyfiles/myapp.rb`. The dependency solver refuses, because base 1.1.0 doesn't satisfy `= 1.0.0`. Read the error, then remove the pin.

### 9.5 Rotate a secret
Change `api_key` in `data_bags/secrets/myapp.json`, then run `knife data bag from file secrets data_bags/secrets/myapp.json --encrypt` and `DEPLOY_KEY=~/chef-lab-keys/jenkins_deploy ci/converge.sh dev`. The config changes, the diff is hidden (because of `sensitive true`), and the app restarts. Nothing touched Git.

### 9.6 Roll back prod
```bash
curl -s http://jenkins.lab.internal:8081/myapp/            # list available versions
V=1.0.1; SHA=$(curl -s http://jenkins.lab.internal:8081/myapp/myapp-$V.jar.sha256)
DEPLOY_KEY=~/chef-lab-keys/jenkins_deploy ci/release_app.sh prod $V $SHA
curl -s http://app03.lab.internal:8080/ | grep -o '"buildVersion":"[^"]*"'
```
Rollback is the same operation as a release: point the group at a version, then converge.

### 9.7 Fix drift without touching the server
On app03, edit `/opt/myapp/shared/application.properties` by hand and run `sudo systemctl restart myapp`. Then either wait for the timer or run `ci/converge.sh prod`. Chef restores the file and restarts the app. Run `knife status` to see when each node last checked in.

### 9.8 Stretch goals (more of the note)
- **Monitoring:** add a `base::monitoring` recipe that installs `prometheus-node-exporter`, enables the service, and opens port 9100 through `default['base']['firewall']['allow']['node_exporter'] = 9100`. Add an InSpec control for it.
- **Certificates:** put nginx in front of myapp on 443 with a certificate generated by Chef (`openssl_x509_certificate` resource), and keep the private key mode `0600`.
- **Access audit script** (the note mentions Bash and Python audits): write `ci/audit_access.sh`, which runs `knife ssh 'name:*' 'getent group sudo; sudo -l -U deploy'` and flags anything unexpected.

---

## Part 10: Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `vagrant up`: "not supported version of VirtualBox" | Vagrant older than your VirtualBox | Install the latest Vagrant |
| VMs very slow / turtle icon | Hyper-V active | Part 1.2 |
| `vagrant up` asks which interface to bridge | `bridge_adapter` doesn't match exactly | Copy the **Name:** from `VBoxManage list bridgedifs` |
| Mac can't ping VMs, but Windows can | Wi-Fi client isolation, or the IP clashes with another device | Use your home network or change the IPs. Fallback: VirtualBox NAT port forwarding plus your Mac's `ssh -L` |
| VMs lose their IP after the router reboots | DHCP gave a VM's IP to another device | Pick IPs outside the DHCP range, or reserve them on the router |
| `knife`: "SSL certificate verify failed" | Cert not trusted | `knife ssl fetch` from the repo root |
| `knife`: "No knife configuration file found" | Running outside the repo | `cd ~/code/chef-infra`, or add `-c .chef/config.rb` |
| Bootstrap installs but config is in `/etc/chef` | Older knife naming | `sudo ln -s /etc/chef /etc/cinc` on the node, then re-run `sudo cinc-client` |
| First converge: `Missing encrypted data bag item secrets/myapp` | Part 5.2 skipped | Upload it, then `sudo cinc-client` |
| Chef run: `Permission denied (publickey)` for `deploy` | Jenkins public key not in the policy | Part 5.3, then `cinc update` and push |
| Kitchen: "permission denied … docker.sock" | Jenkins started before the docker group change | `ssh jenkins.lab.internal sudo systemctl restart jenkins` |
| Kitchen can't pull images | No internet from the VM | `ssh jenkins.lab.internal curl -I https://registry-1.docker.io` |
| Jenkins doesn't start a build after a push | Trigger not yet registered | Run **Build Now** once; check *Polling Log* |
| Smoke test fails on `buildVersion` | The node didn't get the new release | `knife data bag show releases myapp_dev`, then `journalctl -u myapp` |
| `cinc install`: lock out of date | Cookbook version bumped | `cinc update policyfiles/myapp.rb` and commit the lock |
| Windows laptop sluggish | ~11 GB in VMs | `vagrant halt app03` (and `app02`) when you're not using them |

---

## Part 11: What you can now explain (the 10 concepts + the note)

| Concept | Where you used it |
|---|---|
| Cookbook | `cookbooks/base`, `cookbooks/myapp` (metadata, versions, dependencies) |
| Recipe | `base::ssh_hardening`, `myapp::deploy` …: ordered resources |
| Resource | `package`, `user`, `directory`, `template`, `remote_file`, `link`, `systemd_unit`, `service`, `sudo`, `sysctl`, `execute` with guards |
| Attribute | cookbook defaults → policy → policy-group hoisting (`prod` gets WARN) → Kitchen overrides |
| Template | `application.properties.erb`, `sshd-hardening.conf.erb` (with `sensitive true`) |
| Guards and notifications | `not_if` on ufw, `:restart … :delayed` (restart once, only on change) |
| Data bags | `releases` (which version runs where), encrypted `secrets` |
| Policyfile / policy groups | lock → dev → uat → prod promotion |
| Testing | Cookstyle (style), ChefSpec (unit), Test Kitchen + InSpec (integration), InSpec smoke (real servers) |
| chef-client / knife | bootstrap, `knife ssh`, `knife status`, systemd timer drift correction |

| The note says… | You did it in… |
|---|---|
| Owned a Chef codebase for hardening and application stacks | Parts 5–6, the base and myapp cookbooks |
| Automated pipeline that tests each change before promotion | Parts 7–8, both Jenkinsfiles |
| Chef brings every server back to its intended state on a schedule | Part 6.1, Part 9.7 |
| Version pin forced an outdated dependency into UAT; added a pipeline check | Part 9.4, `ci/check_versions.py --fail-on-drift` |
| Managing servers over SSH, scripting audits | `knife ssh`, `ci/*.sh`, Part 9.8 |
| Keeping secrets out of the code | Encrypted data bag, `.gitignore`, Jenkins credentials, `sensitive true` |
