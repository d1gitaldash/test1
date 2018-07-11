#!/bin/bash

UPDATE_NAME='Aegeus-1.2.0.1-Linux-64-bit'
TMP_FOLDER='/tmp/aegeus-install/'
CONFIG_FILE='aegeus.conf'
CONFIGFOLDER='/root/.aegeus'
COIN_DAEMON='aegeusd'
COIN_CLI='aegeus-cli'
COIN_PATH='/usr/local/bin/'
COIN_TGZ='https://www.dropbox.com/s/7e46rsdlr06k1oh/Aegeus-1.2.0.1-Linux-64-bit.tar.gz'
COIN_BOOTSTRAP='https://www.dropbox.com/s/fnj8dc1cpbzxpwf/bootstrap.dat.tar.gz'
COIN_BOOTSTRAP_ZIP=$(echo $COIN_BOOTSTRAP | awk -F'/' '{print $NF}')
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='Aegeus'
COIN_PORT=29328
RPC_PORT=56661

NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    #kill wallet daemon
    systemctl stop $COIN_NAME.service > /dev/null 2>&1
    sudo killall $COIN_DAEMON > /dev/null 2>&1
	# Save Key 
	OLDKEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
	if [ "$?" -eq "0" ]; then
    		echo -e "${CYAN}Saving Old Installation Genkey${NC}"
		echo -e $OLDKEY
	fi
    #remove old ufw port allow
    sudo ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
    #remove old files
    sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    sudo rm -rf /tmp/*
    echo -e "${GREEN}* Done${NONE}";
}


function download_node() {
  mkdir $TMP_FOLDER
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  rm $TMP_FOLDER$COIN_ZIP > /dev/null 2>&1
  wget -q $COIN_TGZ -P $TMP_FOLDER
  compile_error
  tar -xzf $TMP_FOLDER$COIN_ZIP -C $TMP_FOLDER
  chmod +x $TMP_FOLDER/$UPDATE_NAME/*
  cp $TMP_FOLDER/$UPDATE_NAME/$COIN_DAEMON $TMP_FOLDER/$UPDATE_NAME/$COIN_CLI $COIN_PATH
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=root
Group=root
Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid
ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
    COINKEY=$OLDKEY
	if [ -z $OLDKEY ]; then 
		echo -e "${YELLOW}Enter your ${RED}$COIN_NAME Masternode GEN Key${NC}."
		read -e COINKEY
		if [[ -z "$COINKEY" ]]; then
			$COIN_PATH$COIN_DAEMON -daemon
			sleep 30
			if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
				echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
				exit 1
			fi
			COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
			if [ "$?" -gt "0" ]; then
				
				echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the GEN Key${NC}"
				sleep 30
				COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
			  fi
			  $COIN_PATH$COIN_CLI stop
		  fi
	fi
	
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY
#ADDNODES
EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi
}

function prepare_system() {
echo -e "Preparing the VPS to setup. ${CYAN}$COIN_NAME${NC} ${RED}Masternode${NC}"
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${PURPLE}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install libzmq3-dev -y >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  libdb5.3++ unzip libzmq5 >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev libdb5.3++ unzip libzmq5"
 exit 1
fi
clear
}

function important_information() {
 echo
 echo -e "${RED} Minivan 1.2.0.1 Update${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${PURPLE}Windows Wallet Guide. https://github.com/Aegeus/master/README.md${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}$COIN_NAME Masternode is up and running listening on port${NC}${PURPLE}$COIN_PORT${NC}."
 echo -e "${GREEN}Configuration file is:${NC}${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "${GREEN}Start:${NC}${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "${GREEN}Stop:${NC}${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "${GREEN}VPS_IP:PORT${NC}${GREEN}$NODEIP:$COIN_PORT${NC}"
 echo -e "${GREEN}MASTERNODE GENKEY is:${NC}${PURPLE}$COINKEY${NC}"
 if [[ -n $SENTINEL_REPO  ]]; then
 echo -e "${RED}Sentinel${NC} is installed in ${RED}/root/sentinel_$COIN_NAME${NC}"
 echo -e "Sentinel logs is: ${RED}$CONFIGFOLDER/sentinel.log${NC}"
 fi
 echo -e "${BLUE}================================================================================================================================"
 echo -e "${CYAN}Follow twitter to stay updated.  https://twitter.com/Real_Bit_Yoda${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${CYAN}Ensure Node is fully SYNCED with BLOCKCHAIN.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}Usage Commands.${NC}"
 echo -e "${GREEN}aegeus-cli masternode status${NC}"
 echo -e "${GREEN}aegeus-cli getinfo.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${RED}Donations always accepted gratefully.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${YELLOW}Bit Yoda Aegeus: AKRbTXnbd9qXFSRavYsg9uC4r9Ktkkm5t9${NC}"
 echo -e "${YELLOW}Minivan Aegeus: ANm7NHzwry9dEHT8pcRE3HKrU5vbZXiAaz${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
}

function bootstrap() {
  #systemctl status Aegeus.service
  cd $CONFIGFOLDER
  rm -rf blocks chainstate sporks banlist.dat peers.dat 2>/dev/null
  cd $TMP_FOLDER
  echo -e "${CYAN}Downloading Bootstrap...${NC}"
  wget -q $COIN_BOOTSTRAP
  tar -xvzf $COIN_ZIP >/dev/null 2>&1
  tar -xvzf $COIN_BOOTSTRAP_ZIP -C $CONFIGFOLDER >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  cd ~
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  bootstrap
  enable_firewall
  #install_sentinel
  important_information
  configure_systemd
}

##### Main #####
clear
purgeOldInstallation
checks
prepare_system
download_node
setup_node


# bash <(curl https://raw.githubusercontent.com/dmaxjm/Aegeus/master/Aegeus-1.2.0.1-Linux-64bit)
