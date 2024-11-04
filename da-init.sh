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

OS="Linux"

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
    # bash $INSTALLATION_PATH/scripts/install-asdf.sh
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
        read -p "How many validators you want create: " validator_count
        if [[ "$validator_count" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Please enter a valid number."
        fi
    done
    validator_count_file="$INSTALLATION_PATH/validator_count"
    if [ -f "$validator_count_file" ]; then
        echo "Last validator count: $(cat $validator_count_file)"
    else
        echo 0 > "$validator_count_file"
    fi
    validator_count_last=$(cat "$validator_count_file")
    docker run -it --rm -v $INSTALLATION_PATH/validator_keys:/app/validator_keys ghcr.io/davinchi-protocol/da-stake:main existing-mnemonic --num_validators=$validator_count --validator_start_index=$validator_count_last --chain=davinchi
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo $(expr $validator_count_last + $validator_count) > "$validator_count_file"
    read -p "Enter the password: " password
    echo "$password" > $INSTALLATION_PATH/metadata/password.txt
    return 0
}

davinci_validator_deposit(){
    amount=32000000000
    smin=validator_count
    smax=validator_latest_index

eth2-val-tools deposit-data \
  --source-min=$smin \
  --source-max=$smax \
  --amount=$amount \
  --fork-version=0x10000293 \
  --withdrawals-mnemonic="test test test test test test test test test test test junk" \
  --validators-mnemonic="test test test test test test test test test test test junk" > mainnet_deposit_$smin\_$smax.txt

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
fi

last_checkpoint=$(read_checkpoint)

if [ "$last_checkpoint" -eq "3" ]; then
    echo ""
    echo "Depositing Davinci Validator..."
    if davinci_validator_start; then
        echo "Davinci Validator started successfully."
    else
        echo ""
        echo "Davinci Validator start failed."
        exit 1
    fi
fi
