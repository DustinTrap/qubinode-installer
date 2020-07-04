#!/bin/bash

function setup_required_paths () {
    current_dir="`dirname \"$0\"`"
    project_dir="$(dirname ${current_dir})"
    project_dir="`( cd \"$project_dir\" && pwd )`"
    if [ -z "$project_dir" ] ; then
        config_err_msg; exit 1
    fi

    if [ ! -d "${project_dir}/playbooks/vars" ] ; then
        config_err_msg; exit 1
    fi
}

check_if_cluster_deployed () {

    # Establish OpenShift variables
    openshift4_variables
    if [[ -f /usr/local/bin/qubinode-ocp4-status ]] && [[ -f /usr/local/bin/oc ]]\
       && [[ -f $HOME/.kube/config ]] || [[ -d ${project_dir}/ocp4/auth ]]
    then

	if [ "A${cluster_vm_running}" == "Ayes" ]
        then
            /usr/local/bin/oc get nodes 2>&1| grep -qi ctrlplane
	    RESULT=$?
            if [ "A${RESULT}" != 'A1' ]
            then 
	        # Ensure bootstrap node has been removed
                ansible-playbook "${deploy_product_playbook}" -e '{ check_existing_cluster: False }' -e '{ deploy_cluster: False }' -e '{ cluster_deployed_msg: "deployed" }' -t bootstrap_shut > /dev/null 2>&1 || exit $?
                printf "%s\n\n\n" " "
                /usr/local/bin/qubinode-ocp4-status
                printf "%s\n\n" " ${grn}    OpenShift Cluster is up!${end}"
                exit 0
	    else
                printf "%s\n\n" " ${grn}    OpenShift Cluster is not up or the deployment is incomplete.${end}"
            fi
        fi
    fi
}


function qubinode_deploy_ocp4 () {
    product_in_use="ocp4" # Tell the installer which release of OCP
    openshift_product="${product_in_use}"
    qubinode_product_opt="${product_in_use}"

    # Ensure project paths are setup correctly
    setup_required_paths
    [[ -f ${project_dir}/lib/qubinode_kvmhost.sh ]] && . ${project_dir}/lib/qubinode_kvmhost.sh || exit 1
    [[ -f ${project_dir}/lib/qubinode_ocp4_utils.sh ]] && . ${project_dir}/lib/qubinode_ocp4_utils.sh || exit 1

    # Check if openshift cluster is already deployed and running
    check_if_cluster_deployed

    # load required files from samples to playbooks/vars/
    qubinode_required_prereqs

    # Add current user to sudoers, setup global variables, run additional
    # prereqs, setup current user ssh key, ask user if they want to
    # deploy a qubinode system.
    qubinode_installer_setup

    # Ensure the KVM host is setup
    # System is attached to the OpenShift subscription
    # Get the version number for the lastest openshift
    openshift4_prechecks

    # Ensure host system is setup as a KVM host
    if [[ "A${KVM_IN_GOOD_HEALTH}" != "Aready"  ]]; then
        qubinode_setup_kvm_host
    fi

    # Ensure the system meets the requirement for a standard OCP deployment
    check_openshift4_size_yml

    # make sure no old VMs from previous deployments are still around
    state_check

    # Deploy IdM Server
    openshift4_idm_health_check
    if [[  "A${IDM_IN_GOOD_HEALTH}" != "Aready"  ]]; then
      
        # Download rhel qcow image if rhsm token provided
        download_files
      
        # Deploy IdM
        qubinode_deploy_idm
    fi

    # Deploy OCP4
    #ansible-playbook "${deploy_product_playbook}" -e '{ check_existing_cluster: False }'  -e '{ deploy_cluster: True }' || exit $?
    ansible-playbook "${deploy_product_playbook}" -e '{ check_existing_cluster: False }'  -e '{ deploy_cluster: True }'
    RESULT=$?

    if [ $RESULT -eq 0 ]
    then
        # Check the OpenSHift status
        check_if_cluster_deployed
    else
        printf "%s\n\n" " "
        printf "%s\n\n" " ${red}Cluster deployment return a nonzero exit code.${end}"
        # Check the OpenSHift status
        check_if_cluster_deployed
    fi

}

function openshift4_qubinode_teardown () {
    confirm " ${yel}Are you sure you want to delete the${end} ${grn}$product_opt${end} ${yel}cluster${end}? yes/no"
    if [ "A${response}" == "Ayes" ]
    then
        ansible-playbook "${deploy_product_playbook}" -e '{ tear_down: True }' || exit $?
        test -f "${ocp_vars_file}" && rm -f "${ocp_vars_file}"
        printf "%s\n\n\n\n" " }"
        printf "%s\n\n" " ${grn}OpenShift Cluster destroyed!${end}"
        
    else
        exit 0
    fi
}
