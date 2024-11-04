#!/bin/bash

davinci_banner(){
    echo " ____              _            _ "
    echo "|  _ \  __ ___   _(_)_ __   ___(_)"
    echo "| | | |/ _' \ \ / / | '_ \ / __| |"
    echo "| |_| | (_| |\ V /| | | | | (__| |"
    echo "|____/ \__,_| \_/ |_|_| |_|\___|_|"
    echo "                                  "
}

text_yellow(){
    echo -e "\e[33m$1\e[0m"
}

OS="Linux Ubuntu"

# ====================== VERSION AND BUILT ====================== #

VERSION="v1.0"
BUILT="2024.11"
INSTALLATION_PATH="$HOME/davinci"

# ====================== VERSION AND BUILT ====================== #


davinci_banner

echo "Welcome to Davinci Node Validator"
echo "Version: $VERSION"
echo "Built: $BUILT"
echo "OS: $OS"
echo ""

installing_dependencies() {
    echo "Davinci Node Validator needs dependencies below:"

    docker_installed=false
    docker_compose_installed=false
    git_installed=false
    curl_installed=false

    echo -n "- Docker"
    if ! [ -x "$(command -v docker)" ]; then
        echo "[NOT INSTALLED]"
    else
        echo "[INSTALLED]"
        docker_installed=true
    fi

    echo -n "- Docker Compose"
    if ! [ -x "$(command -v docker-compose)" ]; then
        echo "[NOT INSTALLED]"
    else
        echo "[INSTALLED]"
        docker_compose_installed=true
    fi

    echo -n "- Git"
    if ! [ -x "$(command -v git)" ]; then
        echo "[NOT INSTALLED]"
    else
        echo "[INSTALLED]"
        git_installed=true
    fi

    echo -n "- Curl"
    if ! [ -x "$(command -v curl)" ]; then
        echo "[NOT INSTALLED]"
    else
        echo "[INSTALLED]"
        curl_installed=true
    fi

    if [ "$docker_installed" = false ] || [ "$docker_compose_installed" = false ] || [ "$git_installed" = false ] || [ "$curl_installed" = false ]; then
        echo "The dependencies above are not installed. Processing to install the dependencies..."
        read -p "Are you sure to install the dependencies above? (y/n)? " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1 

        if [ "$curl_installed" = false ]; then
            text_yellow "Installing Curl..."
            sudo apt-get install curl -y -qq
        fi
        if [ "$git_installed" = false ]; then
            text_yellow "Installing Git..."
            sudo apt-get install git -y -qq
        fi
        if [ "$docker_installed" = false ]; then
            text_yellow "Installing Docker..."
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            sudo systemctl enable docker
            sudo systemctl start docker
        fi
        if [ "$docker_compose_installed" = false ]; then
            text_yellow "Installing Docker Compose..."
            sudo apt-get install docker-compose -y
        fi
    fi
    return 0
}

davinci_init() {
    echo "Initializing Davinci Node Validator..."
    echo "Cloning Davinci Node Validator repository..."
    git clone https://github.com/davinchi-protocol/da-validator $INSTALLATION_PATH
    bash $INSTALLATION_PATH/scripts/install-asdf.sh
    return 0
}

davinci_mnemonic(){
    echo "Generating Davinci Validator Mnemonic..."
    eth2-val-tools mnemonic > $INSTALLATION_PATH/mnemonic.txt
    return 0
}

davinci_validator_build(){
    echo "Creating Davinci Validator Keystore..."
    echo ""

    if [ -f "$INSTALLATION_PATH/mnemonic.txt" ]; then
        echo "Davinci Validator Mnemonic:"
        cat $INSTALLATION_PATH/mnemonic.txt
    else
        davinci_mnemonic
        echo "Davinci Validator Mnemonic:"
        cat $INSTALLATION_PATH/mnemonic.txt
    fi

    while true; do
        echo ""
        echo 
        read -p "How many validators you want create: " validator_max
        if [[ "$validator_max" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Please enter a valid number."
        fi
    done
    read -p "Enter your Ethereum address for withdrawal: " ethereum_address
    validator_min_file="$INSTALLATION_PATH/validator_min"
    validator_max_file="$INSTALLATION_PATH/validator_max"
    echo 0 > $validator_min_file
    echo $validator_max > $validator_max_file
    echo ""
    echo "In this step, you will create your validator keys."
    echo "Information for creating validator keys:"
    echo -n "- Your mnemonic: "
    cat $INSTALLATION_PATH/mnemonic.txt
    echo
    echo "- Your Validator Start Index: 0"
    echo "- Your Validator Count: $validator_max"
    echo "- Your Ethereum Address: $ethereum_address"
    echo ""
    read -p "Continue installation? (y/n)? " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1 
    mkdir -p $INSTALLATION_PATH/validator_keys
    docker run -it --rm --user $(id -u):$(id -g) -v $INSTALLATION_PATH/validator_keys:/app/validator_keys ghcr.io/davinchi-protocol/da-stake:main existing-mnemonic --num_validators=$validator_max --validator_start_index=0 --eth1_withdrawal_address=$ethereum_address
    if [ $? -ne 0 ]; then
        return 1
    fi
    read -p "Enter the password again: " password
    echo "$password" > $INSTALLATION_PATH/metadata/password.txt
    return 0
}

davinci_validator_deposit(){
    read -p "Enter your Ethereum address funder: " funder_address
    read -p "Enter the private key of the funder: " funder_private_key
    latest_file=$(ls $INSTALLATION_PATH/validator_keys/deposit_data-*.json | sort -t '-' -k 3 -n | tail -n 1)
    
    array_length=$(jq '. | length' $latest_file)
    for (( i=0; i<$array_length; i++ )); do
        amount=$(jq -r ".[$i].amount" $latest_file)
        pubkey=$(jq -r ".[$i].pubkey" $latest_file)
        jq 'map(del(.fork_version))' "$latest_file" > $INSTALLATION_PATH/temp_validator
        data=$(jq -r ".[$i]" $INSTALLATION_PATH/temp_validator)
        echo "Sending deposit for validator $i with pubkey $pubkey"
        ethereal beacon deposit \
            --allow-unknown-contract=true \
            --address="0xdeadbeef00000000000000000000000000000000" \
            --connection="https://rpc.davinci.bz" \
            --data="$data" \
            --allow-excessive-deposit \
            --value="$amount" \
            --from="$funder_address" \
            --privatekey="$funder_private_key" \
            --wait="true" \
            --verbose
        sleep 2
        rm -rf $INSTALLATION_PATH/temp_validator

    done
}

checkpoint_file="/tmp/davinci-node-validator-checkpoint"

update_checkpoint() {
    echo "$1" > "$checkpoint_file"
}

read_checkpoint() {
    if [ -f "$checkpoint_file" ]; then
        cat "$checkpoint_file"
    else
        echo "0"
    fi
}

last_checkpoint=$(read_checkpoint)

if [ "$last_checkpoint" -eq "0" ]; then
    if installing_dependencies; then
        echo "All dependencies are installed."
    else
        echo "Failed to install dependencies."
        exit 1
    fi
    update_checkpoint "1"
fi

last_checkpoint=$(read_checkpoint)

if [ "$last_checkpoint" -eq "1" ]; then
    echo ""
    echo "Initializing Davinci Node Validator..."
    if davinci_init; then
        echo "Davinci Node Validator initialized successfully."
    else
        echo ""
        echo "Davinci Node Validator initialization failed."
        exit 1
    fi
    update_checkpoint "2"
fi

last_checkpoint=$(read_checkpoint)

if [ "$last_checkpoint" -eq "2" ]; then
    echo ""
    echo "Creating Davinci Validator..."
    if davinci_validator_build; then
        echo "Davinci Validator created."
    else
        echo ""
        echo "Davinci Validator failed."
        exit 1
    fi
    update_checkpoint "3"
fi

last_checkpoint=$(read_checkpoint)

if [ "$last_checkpoint" -eq "3" ]; then
    echo ""
    echo "Depositing Davinci Validator..."
    if davinci_validator_deposit; then
        echo "Please check manually if the deposit is successful."
        echo ""
    else
        echo ""
        echo "Deposit failed, please check manually."
        exit 1
    fi
    update_checkpoint "4"
fi

echo "Davinci Node Validator installation completed successfully."
