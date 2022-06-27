# set -x

function install_prerequisites() {
    sudo yum install -y jq
    sudo yum install -y wget
}

# Function to check if Terraform is installed already, if not, then download and installed the version of Terraform as required.
function install_terraform() {
    # Sticking to Terraform v1.1.7 as it was used for the development of this code-base
    TERRAFORM_VERSION="1.1.7"

    # Check if terraform is already installed and display the version of terraform as installed
    [[ -f ${HOME}/bin/terraform ]] && echo -e "\n`${HOME}/bin/terraform version` already installed at ${HOME}/bin/terraform" && return 0

    TERRAFORM_DOWNLOAD_URL=$(curl -sL https://releases.hashicorp.com/terraform/index.json | jq -r '.versions[].builds[].url' | egrep 'linux.*amd64' | egrep "${TERRAFORM_VERSION}" | egrep -v 'rc|beta|alpha')
    TERRAFORM_DOWNLOAD_FILE=$(basename $TERRAFORM_DOWNLOAD_URL)

    echo -e "\nDownloading Terraform v$TERRAFORM_VERSION from '$TERRAFORM_DOWNLOAD_URL'"

    # Download and install Terraform v1.1.7 as that is the version used for the development of this code-base.
    # TODO: Once Base and Ceiling versions have been validated, the code here will be modified to download the Ceiling version of terraform as required by the scripts in this code-base.
    mkdir -p ${HOME}/bin/ && cd ${HOME}/bin/ && wget $TERRAFORM_DOWNLOAD_URL && unzip $TERRAFORM_DOWNLOAD_FILE && rm $TERRAFORM_DOWNLOAD_FILE

    # Display an confirmation of the successful installation of Terraform.
    echo -e "\nInstalled: `${HOME}/bin/terraform version`"
}

function install_kubectl() {
    # We will use Kubectl v1.23.0 because we faced some issues with using the latest version (v1.24.0).
    KUBECTL_VERSION="1.23.0"

    # Check if kubectl is already installed and display the version as installed.
    [[ -f ${HOME}/bin/kubectl ]] && echo -e "\nkubectl is already installed at ${HOME}/bin/kubectl" && return 0

    KUBECTL_DOWNLOAD_URL="https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/linux/amd64/kubectl"

    echo -e "\nDownloading Kubectl v$KUBECTL_VERSION from '$KUBECTL_DOWNLOAD_URL'"

    # Download and install kubectl v1.23.0, move it to the bin folder
    mkdir -p ${HOME}/bin/ && cd ${HOME}/bin/ && curl -LO $KUBECTL_DOWNLOAD_URL && chmod +x kubectl
}

function install_aws_iam_authenticator() {
    # Using whatever was the latest stable version at the time of development.
    AWS_IAM_AUTH_VERSION="1.21.2"

    # Check if aws-iam-authenticator is already installed and display the version as installed.
    [[ -f ${HOME}/bin/aws-iam-authenticator ]] && echo -e "\naws-iam-authenticator is already installed at ${HOME}/bin/aws-iam-authenticator" && return 0

    AWS_IAM_AUTH_DOWNLOAD_URL="https://s3.us-west-2.amazonaws.com/amazon-eks/$AWS_IAM_AUTH_VERSION/2021-07-05/bin/linux/amd64/aws-iam-authenticator"

    # Download and install aws-iam-authenticator v1.21.2, move it to the bin folder
    mkdir -p ${HOME}/bin/ && cd ${HOME}/bin/ && curl -o aws-iam-authenticator $AWS_IAM_AUTH_DOWNLOAD_URL && chmod +x aws-iam-authenticator
}

function deploy_panorama() {
    cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/panorama"

    # Initialize terraform
    echo -e "\nInitializing directory for lab resource deployment"
    terraform init

    # Deploy resources
    echo -e "\nDeploying Panorama Resources required for Palo Alto Networks Reference Architecture for Zero Trust with VM-Series on AWS"
    terraform apply -auto-approve

    if [ $? -eq 0 ]; then
        echo -e "\nPanorama for AWS Zero Trust Reference Architecture with VM-Series Lab Deployment Completed successfully!"
    else
        echo -e "\nPanorama for AWS Zero Trust Reference Architecture with VM-Series Lab Deployment Failed!"
        exit 1
    fi
}

function get_panorama_ip() {
    cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/panorama"

    PANORAMA_IP=$(terraform output PANORAMA_IP_ADDRESS | sed -e 's/^"//' -e 's/"$//')
    echo $PANORAMA_IP
}

function deploy_cnseries_lab() {

    # Getting the public IP address of the newly deployed Panorama
    echo -e "\nUpdating the Panorama IP in CN-Series config file for deployment"
    HARD_CODED_PANORAMA_IP="35.182.55.251"
    NEW_PANORAMA_IP=$(get_panorama_ip)

    # Assuming that this setup script is being run from the cloned github repo, changing the current working directory to one from where Terraform will deploy the lab resources.
    cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries"

    # Initialize terraform
    echo -e "\nInitializing directory for lab resource deployment"
    terraform init

    # Deploy resources
    echo -e "\nDeploying Resources required for Palo Alto Networks Reference Architecture for Zero Trust with CN-Series on AWS"
    terraform apply -auto-approve

    if [ $? -eq 0 ]; then
        echo -e "\nAWS Zero Trust Reference Architecture with CN-Series Lab Deployment Completed successfully!"
    else
        echo -e "\nAWS Zero Trust Reference Architecture with CN-Series Lab Deployment Failed!"
        echo -e "\nPlease try updating the kubeconfig and run setup again. Check the Lab Guide for more details."
        exit 1
    fi

    # Updating the Panorama IP in CN-Series config file for deployment
    sed -i "s/$HARD_CODED_PANORAMA_IP/$NEW_PANORAMA_IP/" cn-series/pan-cn-mgmt-configmap.yaml

    KUBECTL_CONFIG_COMMAND=$(terraform output kubectl_config_command | sed -e 's/^"//' -e 's/"$//')
    KUBECTL_DEMO_APP_DEPLOYMENT_COMMAND=$(terraform output kubectl_demo_application_deployment_command | sed -e 's/^"//' -e 's/"$//')

    # Running the kubeconfig command as required for the lab
    echo -e "\nRunning the kubeconfig command as required for the lab"
    eval $KUBECTL_CONFIG_COMMAND

    if [ $? -ne 0 ]; then
        echo "There was an error seen while updating the kubeconfig."
        exit 1
    fi

    ####
    #### Commenting all the below lines because there is a manual step that needs to be performed in the Panorama 
    #### appliance before we can proceed to the below steps.
    ####
    # Deploying CN-Series firewalls
    # echo -e "\nDeploying CN-Series firewalls"
    # cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries/cn-series"
    # /bin/bash ./install-cn.sh

    # if [ $? -ne 0 ]; then
    #    echo -e "\nThere was an error seen while deploying the CN-Series firewalls."
    #    exit 1
    # fi

    # Running the demo application for the CN-Series to secure.
    # echo -e "\nRunning the demo application for the CN-Series to secure"
    # cd "${HOME}/lab-aws-cn-series-zero-trust/terraform/cnseries"
    # eval $KUBECTL_DEMO_APP_DEPLOYMENT_COMMAND

    # if [ $? -ne 0 ]; then
    #    echo "There was an error seen while deploying the demo application."
    #    exit 1
    # fi

    # Getting the credentials json file for configuring the cluster on Panorama.
    # echo -e "\nGetting the credentials json file for configuring the cluster on Panorama."
    # MY_TOKEN=`kubectl get serviceaccounts pan-plugin-user -n kube-system -o jsonpath='{.secrets[0].name}'`
    # kubectl get secret $MY_TOKEN -n kube-system -o json > ~/pan-plugin-user.json
}

install_prerequisites
install_terraform
install_kubectl
install_aws_iam_authenticator

deploy_panorama
deploy_cnseries_lab