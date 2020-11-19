#!/bin/bash


function create_cluster {
export ANSIBLE_HOST_KEY_CHECKING=False
vagrant up --provision

 ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory tools.yaml
 ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory docker.yaml
 ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory create_cluster.yaml
 ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory join_nodes.yaml
 ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory test-cluster.yaml

output=`curl 192.168.1.3:31113`
echo $output
}

function destroy_cluster {
vagrant destroy
}


if [[ $# -ne 1 ]]; then
	echo "Usage: ./start.sh up|down"
else
	if [ "$1" = "up" ]; then
	       echo "Creating cluster"	
		create_cluster
	elif [ "$1" = "down" ]; then
		echo "Destroying cluster"
		destroy_cluster
	else 
		echo "Usage: ./start.sh up|down"
	fi

fi


