# Automate k8s cluster creation!

In the following text we'll go through and explain how you can create your own on-prem k8s cluster using **vagrant**, **ansible** and **kubeadm**.


# Vagrant
**Vagrant** is a tool for building and managing virtual machine environments in a single workflow. With an easy-to-**use** workflow and focus on automation, **Vagrant** lowers development environment setup time, increases production parity, and makes the "works on my machine" excuse a relic of the past. All configuration is done in the file called **Vagrantfile**.

To create specific box, do the following:

```
  config.vm.define "worker" do |worker1|
    worker1.vm.box = "ubuntu/xenial64"
    worker1.vm.network "public_network", ip: "192.168.1.3", bridge: "wlan0"
    worker1.vm.provider "virtualbox" do |v|
      v.name = "worker"
      v.memory = 1500
      v.cpus = 1
    end
  end
```
This will create a new box from "ubuntu/xenial64" base image. We want to give it a static ip address so it will become much easier to write ansible playbooks. Also, we will give it **1.5GB** of memory and **1** VCPU.

Same for our master box:
```
  config.vm.define "master" do |master|
    master.vm.box = "ubuntu/xenial64"
    master.vm.network "public_network", ip: "192.168.1.2", bridge: "wlan0"
    master.vm.provider "virtualbox" do |v1|
      v1.name = "master"
      v1.memory = 2000
      v1.cpus = 2
    end
  end
```
The only difference is that we need **2** VCPU's and **2GB** of memory for our master node.

Next important part of Vagrant file is provisioning. We we'll be using tool called ansible to do all the provisioning for machines.

```
  config.vm.provision "ansible" do |ansible|
    ansible.playbook = "initial.yaml"
    ansible.groups = {
      "masters" => ["master"],
      "workers" => ["worker"],
      "all:vars" => {"ansible_user" => "root", "ansible_python_interpreter" => "/usr/bin/python3"}
    }
  end

```
Vagrant will automatically create hosts file based on properties we define in this section. That hosts file will be stored in .vagrant/provisioners/ansible/inventory folder and we will be using that inventory file for our playbooks.

# Ansible

**Ansible** is an open source IT Configuration Management, Deployment & Orchestration tool. It aims to provide large productivity gains to a wide variety of automation challenges. This tool is very simple to use yet powerful enough to automate complex multi-tier IT application environments.
**Ansible** itself is **written in Python** and has a fairly minimal learning curve. **Ansible** follows a simple setup procedure and does not depend on any additional software, servers or client daemons. It manages nodes over SSH and is parallel by default. **Ansible** uses files called playbooks to provision remote (or local) machines.

### Playbook 1.
Now, we'll explain structure of "**initial.yaml**" playbook.

```
```---
- name: Add ubuntu user
  hosts: all
  become: yes
  tasks:
    - name: Create user
      user:
        name: ubuntu
        shell: /bin/bash
        state: present
        create_home: yes
    - name: Allow ubuntu to perform sudo without passwd
      lineinfile:
        path: /etc/sudoers
        line: 'ubuntu ALL=(ALL) NOPASSWD: ALL'
```
### Playbook 2.

Next playbook is **tools.yaml**.

```
- name: Install tools
  hosts: all
  become: yes
  tasks:
    - name: Add k8s apt key
      apt_key:
        url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
        state: present
    - name: Add k8s repo
      apt_repository:
        repo: deb http://apt.kubernetes.io/ kubernetes-xenial main
        state: present
        filename: 'kubernetes'
        update_cache: true
    - name: Install dependencies
      apt:
        name: kubernetes-cni
        state: present
        update_cache: true
    - name: Install kubelet on all boxes
      apt:
        name: kubelet
        state: present
        update_cache: true
    - name: Install kubeadm
      apt:
        name: kubeadm
        state: present
        update_cache: true
- name: Install kubectl only on master
  hosts: masters
  become: yes
  tasks:
    - name: install kubectl
      apt:
        name: kubectl=1.14.0-00
        state: present
        force: yes
```

In the playbook we install **kubeadm**, **kubectl** and **kubelet**. 

### Playbook 3.

Nexe playbook is used for installing docker on both machines. File that we are looking for is **docker.yaml**.

```
- name: Install docker
  hosts: all
  become: yes
  any_errors_fatal: true # If one task on eny server fails, ansible will stop execution on all servers
  tasks:
    - name: Update and upgrade packages
      meta: flush_handlers
    - name: Install packages
      apt:
        name: "{{ item }}"
        state: present
      loop:
         - apt-transport-https
         - ca-certificates
         - curl
         - software-properties-common
         - gnupg2
    - name: Import repository key
      apt_key: 
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present 
    - name: Get release
      shell: "lsb_release -cs"
      register: release
    - name: Add APT repository
      apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable
        update_cache: yes
        state: present
      when: '"Mint" in ansible_distribution'
    - name: Add APT repository
      apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/debian buster stable
        update_cache: yes
        state: present
      when: '"Kali" in ansible_distribution'
    - name: Add APT repository
      apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu "{{ release.stdout  }}" stable
        update_cache: yes
        state: present
      when: '"Ubuntu" in ansible_distribution'
    - name: Install docker
      apt:
        name: "{{ item }}"
        state: present
      loop:
        - docker-ce
        - docker-ce-cli
        - containerd.io
      notify:
        - Update
    - name: Start docker
      systemd:
        name: docker
        state: restarted
        enabled: yes
    - name: Add user to docker group
      user:
        user: "ubuntu"
        groups: docker
        append: yes
    # We need to reset connection for changes to be applied
    - name: Reset ssh 
      meta: reset_connection
    - name: Validate installation
      shell: "docker info"
      register: "info"
    - name: Print docker info
      debug:
        msg: "{{ info.stdout_lines }}"
  handlers:
    - name: Update
      apt:
        update_cache: yes
        upgrade: dist
        force_apt_get: yes
```

We are not going to explain it in detail here. What's important here is that this playbook will install docker along with all prerequisites. Also, our **ubuntu** user will be added to **docker** group so he can issue commands to dockerd without using **sudo**.

### Playbook 4.

Now, let's start with creating our k8s cluster.

```
--- 
- name: Initialize cluster
  become: yes
  hosts: masters
  tasks:
    - name: Make sure the swap is off
      shell: 'swapoff -a'
    - name: Init cluster
      shell: kubeadm init --apiserver-advertise-address "{{ ansible_enp0s8.ipv4.address }}" --pod-network-cidr=10.244.0.0/16 >> cluster_init.txt
      args:
        chdir: $HOME
        creates: cluster_init.txt
    - name: Create .kube dir in home directory
      become_user: ubuntu
      file:
        path: "$HOME/.kube"
        state: directory
        owner: "ubuntu"
        group: "ubuntu"
        mode: 0755
    - name: Create config
      become_user: "ubuntu"
      file:
        path: "$HOME/.kube/config"
        state: touch
        mode: 0755
        owner: "ubuntu"
        group: "ubuntu"
    - name: Copy admin.conf to .kube dir
      copy:
        dest: '/home/ubuntu/.kube/config'
        src: '/etc/kubernetes/admin.conf'
        owner: ubuntu
        remote_src: yes
    - name: Get network pod
      become_user: "ubuntu"
      get_url:
        url: https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
        dest: '$HOME/pod_network.yaml'
    - name: Change api version
      become_user: "ubuntu"
      replace:
        path: $HOME/pod_network.yaml
        regexp: "apiVersion: extensions/v1beta1"
        replace: "apiVersion: apps/v1"
        
    - name: Install flannel pod network
      become_user: ubuntu
      shell: kubectl create -f $HOME/pod_network.yaml
      args:
        chdir: '$HOME'
        creates: pod_network_setup.txt
```
Ansible will run this playbook only on our master and not on worker machine.
This is because this playbook is used to initialize control plane of our cluster. After initializing our control plane, we will create flannel daemon set along with  service account, cluster role, cluster role binding and config map to establish networking for our cluster.

### Playbook 5.

It is now time to join our worker node to the cluster.
```
---
- name: Playbook for joining worker nodes to the cluster
  hosts: masters
  become: yes
  tasks:
    - name: Create join token
      shell: kubeadm token create --print-join-command
      register: output
    - name: Set fact
      set_fact:
        join_command: "{{ output.stdout_lines[0] }}"

- name: Join workers
  become: yes
  hosts: workers
  tasks:
    - name: Join cluster
      shell: "{{ hostvars['master'].join_command }} --node-name worker >> node_joined.txt"
      args:
        chdir: "$HOME"
        creates: node_joined.txt
```

Finally, to test if the cluster is working we are going to create a deplyoment that will create 5 nginx containers only on our worker node. Then we will curl it to see if it works.

```
---
- name: Test if cluster is working
  hosts: masters
  tasks:
    - name: Deploy 5 nginx pods on worker node and open port 30003 on worker
      become: yes
      copy:
        src: deploy-nginx.yaml
        dest: /home/ubuntu/deploy-nginx.yaml
        owner: ubuntu
        group: ubuntu
        mode: '0644'
    - name: Deploy manifest
      become: yes
      become_user: "ubuntu"
      shell: kubectl --kubeconfig /home/ubuntu/.kube/config create -f /home/ubuntu/deploy-nginx.yaml
    - name: Wait for pods to start
      pause:
        seconds: 30
```
 
 If it all goes as it's should be, you should see output like this:
```
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```



#### Congratulations on your multi-node k8s cluster! Enjoy playing with it.

