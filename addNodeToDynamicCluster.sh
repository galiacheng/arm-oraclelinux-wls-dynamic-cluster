#!/bin/bash

#Function to output message to StdErr
function echo_stderr ()
{
    echo "$@" >&2
}

#Function to display usage message
function usage()
{
  echo_stderr "./addNodeToDynamicCluster.sh <acceptOTNLicenseAgreement> <otnusername> <otnpassword> <wlsDomainName> <wlsAdminURL> <wlsUserName> <wlsPassword>"
}

function setupInstallPath()
{
    JDK_PATH="/u01/app/jdk"
    WLS_PATH="/u01/app/wls"
    DOMAIN_PATH="/u01/domains"

    #create custom directory for setting up wls and jdk
    sudo mkdir -p $JDK_PATH
    sudo mkdir -p $WLS_PATH
    sudo mkdir -p $DOMAIN_PATH
    sudo rm -rf $JDK_PATH/*
    sudo rm -rf $WLS_PATH/*
    sudo rm -rf $DOMAIN_PATH/*
}

function installUtilities()
{
    echo "Installing zip unzip wget vnc-server rng-tools"
    sudo yum install -y zip unzip wget vnc-server rng-tools

    #Setting up rngd utils
    sudo systemctl status rngd
    sudo systemctl start rngd
    sudo systemctl status rngd
}

function addOracleGroupAndUser()
{
    #add oracle group and user
    echo "Adding oracle user and group..."
    groupname="oracle"
    username="oracle"
    user_home_dir="/u01/oracle"
    USER_GROUP=${groupname}
    sudo groupadd $groupname
    sudo useradd -d ${user_home_dir} -g $groupname $username
}

function validateInput()
{

    if [ -z "$acceptOTNLicenseAgreement" ];
    then
            echo _stderr "acceptOTNLicenseAgreement is required. Value should be either Y/y or N/n"
            exit 1
    fi
    if [[ ! ${acceptOTNLicenseAgreement} =~ ^[Yy]$ ]];
    then
        echo "acceptOTNLicenseAgreement value not specified as Y/y (yes). Exiting installation Weblogic Server process."
        exit 1
    fi

    if [[ -z "$otnusername" || -z "$otnpassword" ]]
    then
        echo_stderr "otnusername or otnpassword is required. "
        exit 1
    fi	

    if [ -z "$wlsDomainName" ];
    then
        echo_stderr "wlsDomainName is required. "
    fi

    if [[ -z "$wlsUserName" || -z "$wlsPassword" ]]
    then
        echo_stderr "wlsUserName or wlsPassword is required. "
        exit 1
    fi	

    if [ -z "$wlsAdminURL" ];
    then
        echo_stderr "wlsAdminURL is required. "
    else
        status=`curl --insecure -ILs http://${wlsAdminURL}/weblogic/ready | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
        if [[ "$status" != "200" ]];
        then
          echo_stderr "Admin Server not accessible on URL: $wlsAdminURL. Please check and retry again."
          exit 1
        fi
    fi
}

#download jdk from OTN
function downloadJDK()
{
   echo "Downloading jdk from OTN..."

   for in in {1..5}
   do
     curl -s https://raw.githubusercontent.com/typekpb/oradown/master/oradown.sh  | bash -s -- --cookie=accept-weblogicserver-server --username="${otnusername}" --password="${otnpassword}" https://download.oracle.com/otn/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz
     tar -tzf jdk-8u131-linux-x64.tar.gz 
     if [ $? != 0 ];
     then
        echo "Download failed. Trying again..."
        rm -f jdk-8u131-linux-x64.tar.gz
     else 
        echo "Downloaded JDK successfully"
        break
     fi
   done
}

function setupJDK()
{
    sudo cp $BASE_DIR/jdk-8u131-linux-x64.tar.gz $JDK_PATH/jdk-8u131-linux-x64.tar.gz

    echo "extracting and setting up jdk..."
    sudo tar -zxvf $JDK_PATH/jdk-8u131-linux-x64.tar.gz --directory $JDK_PATH
    sudo chown -R $username:$groupname $JDK_PATH

    export JAVA_HOME=$JDK_PATH/jdk1.8.0_131
    export PATH=$JAVA_HOME/bin:$PATH

    java -version

    if [ $? == 0 ];
    then
        echo "JAVA HOME set succesfully."
    else
        echo_stderr "Failed to set JAVA_HOME. Please check logs and re-run the setup"
        exit 1
    fi
}

function setupWLS()
{
    sudo cp $BASE_DIR/fmw_12.2.1.3.0_wls_Disk1_1of1.zip $WLS_PATH/fmw_12.2.1.3.0_wls_Disk1_1of1.zip
    echo "unzipping fmw_12.2.1.3.0_wls_Disk1_1of1.zip..."
    sudo unzip -o $WLS_PATH/fmw_12.2.1.3.0_wls_Disk1_1of1.zip -d $WLS_PATH

    export SILENT_FILES_DIR=$WLS_PATH/silent-template
    sudo mkdir -p $SILENT_FILES_DIR
    sudo rm -rf $WLS_PATH/silent-template/*
    sudo chown -R $username:$groupname $WLS_PATH

    export INSTALL_PATH="$WLS_PATH/install"
    export WLS_JAR="$WLS_PATH/fmw_12.2.1.3.0_wls.jar"

    mkdir -p $INSTALL_PATH
    sudo chown -R $username:$groupname $INSTALL_PATH

    create_oraInstlocTemplate
    create_oraResponseTemplate
    create_oraUninstallResponseTemplate

}

#Download Weblogic install jar from OTN
function downloadWLS()
{
  echo "Downloading weblogic install kit from OTN..."

  for in in {1..5}
  do
     curl -s https://raw.githubusercontent.com/typekpb/oradown/master/oradown.sh  | bash -s -- --cookie=accept-weblogicserver-server --username="${otnusername}" --password="${otnpassword}" http://download.oracle.com/otn/nt/middleware/12c/12213/fmw_12.2.1.3.0_wls_Disk1_1of1.zip
     unzip -l fmw_12.2.1.3.0_wls_Disk1_1of1.zip
     if [ $? != 0 ];
     then
        echo "Download failed. Trying again..."
        rm -f fmw_12.2.1.3.0_wls_Disk1_1of1.zip
     else 
        echo "Downloaded WLS successfully"
        break
     fi
  done
}

function validateJDKZipCheckSum()
{
  jdkZipFile="$BASE_DIR/jdk-8u131-linux-x64.tar.gz"
  jdk18u131Sha256Checksum="62b215bdfb48bace523723cdbb2157c665e6a25429c73828a32f00e587301236"

  downloadedJDKZipCheckSum=$(sha256sum $jdkZipFile | cut -d ' ' -f 1)

  if [ "${jdk18u131Sha256Checksum}" == "${downloadedJDKZipCheckSum}" ];
  then
    echo "Checksum match successful. Proceeding with Weblogic Install Kit Zip Download from OTN..."
  else
    echo "Checksum match failed. Please check the supplied OTN credentials and try again."
    exit 1
  fi
}


#Function to cleanup all temporary files
function cleanup()
{
    echo "Cleaning up temporary files..."
	
    rm -f $BASE_DIR/jdk-8u131-linux-x64.tar.gz
    rm -f $BASE_DIR/fmw_12.2.1.3.0_wls_Disk1_1of1.zip
	
    rm -rf $JDK_PATH/jdk-8u131-linux-x64.tar.gz
    rm -rf $WLS_PATH/fmw_12.2.1.3.0_wls_Disk1_1of1.zip
    
    rm -rf $WLS_PATH/silent-template
    	
    rm -rf $WLS_JAR

    rm -rf $DOMAIN_PATH/managed-domain.yaml
    rm -rf $DOMAIN_PATH/weblogic-deploy.zip
    rm -rf $DOMAIN_PATH/weblogic-deploy
    rm -rf $DOMAIN_PATH/deploy-app.yaml
    rm -rf $DOMAIN_PATH/shoppingcart.zip
    rm -rf $DOMAIN_PATH/*.py
    echo "Cleanup completed."
}

#Function to create Weblogic Installation Location Template File for Silent Installation
function create_oraInstlocTemplate()
{
    echo "creating Install Location Template..."

    cat <<EOF >$WLS_PATH/silent-template/oraInst.loc.template
inventory_loc=[INSTALL_PATH]
inst_group=[GROUP]
EOF
}

#Function to create Weblogic Installation Response Template File for Silent Installation
function create_oraResponseTemplate()
{

    echo "creating Response Template..."

    cat <<EOF >$WLS_PATH/silent-template/response.template
[ENGINE]

#DO NOT CHANGE THIS.
Response File Version=1.0.0.0.0

[GENERIC]

#Set this to true if you wish to skip software updates
DECLINE_AUTO_UPDATES=false

#My Oracle Support User Name
MOS_USERNAME=

#My Oracle Support Password
MOS_PASSWORD=<SECURE VALUE>

#If the Software updates are already downloaded and available on your local system, then specify the path to the directory where these patches are available and set SPECIFY_DOWNLOAD_LOCATION to true
AUTO_UPDATES_LOCATION=

#Proxy Server Name to connect to My Oracle Support
SOFTWARE_UPDATES_PROXY_SERVER=

#Proxy Server Port
SOFTWARE_UPDATES_PROXY_PORT=

#Proxy Server Username
SOFTWARE_UPDATES_PROXY_USER=

#Proxy Server Password
SOFTWARE_UPDATES_PROXY_PASSWORD=<SECURE VALUE>

#The oracle home location. This can be an existing Oracle Home or a new Oracle Home
ORACLE_HOME=[INSTALL_PATH]/Oracle/Middleware/Oracle_Home

#Set this variable value to the Installation Type selected. e.g. WebLogic Server, Coherence, Complete with Examples.
INSTALL_TYPE=WebLogic Server

#Provide the My Oracle Support Username. If you wish to ignore Oracle Configuration Manager configuration provide empty string for user name.
MYORACLESUPPORT_USERNAME=

#Provide the My Oracle Support Password
MYORACLESUPPORT_PASSWORD=<SECURE VALUE>

#Set this to true if you wish to decline the security updates. Setting this to true and providing empty string for My Oracle Support username will ignore the Oracle Configuration Manager configuration
DECLINE_SECURITY_UPDATES=true

#Set this to true if My Oracle Support Password is specified
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false

#Provide the Proxy Host
PROXY_HOST=

#Provide the Proxy Port
PROXY_PORT=

#Provide the Proxy Username
PROXY_USER=

#Provide the Proxy Password
PROXY_PWD=<SECURE VALUE>

#Type String (URL format) Indicates the OCM Repeater URL which should be of the format [scheme[Http/Https]]://[repeater host]:[repeater port]
COLLECTOR_SUPPORTHUB_URL=


EOF
}

#Function to create Weblogic Uninstallation Response Template File for Silent Uninstallation
function create_oraUninstallResponseTemplate()
{
    echo "creating Uninstall Response Template..."

    cat <<EOF >$WLS_PATH/silent-template/uninstall-response.template
[ENGINE]

#DO NOT CHANGE THIS.
Response File Version=1.0.0.0.0

[GENERIC]

#This will be blank when there is nothing to be de-installed in distribution level
SELECTED_DISTRIBUTION=WebLogic Server~[WLSVER]

#The oracle home location. This can be an existing Oracle Home or a new Oracle Home
ORACLE_HOME=[INSTALL_PATH]/Oracle/Middleware/Oracle_Home/

EOF
}

#Creates weblogic deployment model for managed server domain
function create_managed_server_domain()
{
    echo "Creating managed server domain"
    cat <<EOF >$DOMAIN_PATH/managed-domain.yaml
domainInfo:
   AdminUserName: "$wlsUserName"
   AdminPassword: "$wlsPassword"
   ServerStartMode: prod
topology:
   Name: "$wlsDomainName"
   Machine:
     '$machineName':
         NodeManager:
            ListenAddress: "$nmHost"
            ListenPort: $nmPort
            NMType : ssl  
   Cluster:
        '$wlsClusterName':
            MigrationBasis: 'consensus'
            DynamicServers:
                ServerTemplate: '${dynamicServerTemplate}'
                MachineNameMatchExpression: "$MATCH_EXPRESSION"
   ServerTemplate:
        '${dynamicServerTemplate}' :
            ListenPort: ${wlsManagedPort}
            Cluster: '${wlsClusterName}'
   SecurityConfiguration:
        NodeManagerUsername: "$wlsUserName"
        NodeManagerPasswordEncrypted: "$wlsPassword"
EOF
}

#This function create py Script to create Machine on the Domain
function createMachinePyScript()
{
    echo "Creating machine name model: $machineName"
    cat <<EOF >$DOMAIN_PATH/add-machine.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
shutdown('$wlsClusterName', 'Cluster')
edit("$machineName")
startEdit()
cd('/')
cmo.createMachine('$machineName')
cd('/Machines/$machineName/NodeManager/$machineName')
cmo.setListenPort(int($nmPort))
cmo.setListenAddress('$nmHost')
cmo.setNMType('ssl')
save()
resolve()
activate()
destroyEditSession("$machineName")
disconnect()
EOF
}


#This function creates py Script to enroll Node Manager to the Domain
function createEnrollServerPyScript()
{
    echo "Creating managed server model"
    cat <<EOF >$DOMAIN_PATH/enroll-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
nmEnroll('$DOMAIN_PATH/$wlsDomainName','$DOMAIN_PATH/$wlsDomainName/nodemanager')
disconnect()
EOF
}

function getMachineMatchExpression()
{

    cat <<EOF >$DOMAIN_PATH/getMachineMatchExpression.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
cd('Clusters/$wlsClusterName/DynamicServers/NO_NAME_0')
matchExpression=cmo.getMachineNameMatchExpression()
print('MatchExpression='+matchExpression)
disconnect()
EOF

RESULT=$($INSTALL_PATH/Oracle/Middleware/Oracle_Home/oracle_common/common/bin/wlst.sh $DOMAIN_PATH/getMachineMatchExpression.py)
MATCH_EXPRESSION=$(echo $RESULT|grep MatchExpression=|cut -d'=' -f 2)
echo $MATCH_EXPRESSION

}


#This function to wait for admin server 
function wait_for_admin()
{
 #wait for admin to start
count=1
export CHECK_URL="http://$wlsAdminURL/weblogic/ready"
status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
while [[ "$status" != "200" ]]
do
  echo "Waiting for admin server to start"
  count=$((count+1))
  if [ $count -le 30 ];
  then
      sleep 1m
  else
     echo "Error : Maximum attempts exceeded while starting admin server"
     exit 1
  fi
  status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
  if [ "$status" == "200" ];
  then
     echo "Admin Server started succesfully..."
     break
  fi
done  
}

#This function to start managed server
function start_cluster()
{
    echo "Starting Cluster $wlsClusterName"
    cat <<EOF >$DOMAIN_PATH/start-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
try:
   start('$wlsClusterName', 'Cluster')
except:
   print "Failed starting Cluster $wlsClusterName"
   dumpStack()
disconnect()   
EOF
sudo chown -R $username:$groupname $DOMAIN_PATH
runuser -l oracle -c "export JAVA_HOME=$JDK_PATH/jdk1.8.0_131 ; $INSTALL_PATH/Oracle/Middleware/Oracle_Home/oracle_common/common/bin/wlst.sh $DOMAIN_PATH/start-server.py"
if [[ $? != 0 ]]; then
  echo "Error : Failed in starting cluster"
  exit 1
fi
}

#Function to start nodemanager
function start_nm()
{
   runuser -l oracle -c "export JAVA_HOME=$JDK_PATH/jdk1.8.0_131 ; \"$DOMAIN_PATH/$wlsDomainName/bin/startNodeManager.sh\" &"
   sleep 1m
}

function create_managedSetup(){

    echo "Creating Managed Server Setup"
    echo "Creating domain path /u01/domains"
    echo "Downloading weblogic-deploy-tool"
    cd $DOMAIN_PATH
    wget -q $WEBLOGIC_DEPLOY_TOOL  
    if [[ $? != 0 ]]; then
       echo "Error : Downloading weblogic-deploy-tool failed"
       exit 1
    fi
    sudo unzip -o weblogic-deploy.zip -d $DOMAIN_PATH
    echo "Creating managed server model files"
    
    create_managed_server_domain
    
    createMachinePyScript
    
    createEnrollServerPyScript
    
    echo "Completed managed server model files"
    sudo chown -R $username:$groupname $DOMAIN_PATH
    
    runuser -l oracle -c "export JAVA_HOME=$JDK_PATH/jdk1.8.0_131 ; $DOMAIN_PATH/weblogic-deploy/bin/createDomain.sh -oracle_home $INSTALL_PATH/Oracle/Middleware/Oracle_Home -domain_parent $DOMAIN_PATH  -domain_type WLS -model_file $DOMAIN_PATH/managed-domain.yaml" 
    
    if [[ $? != 0 ]]; then
       echo "Error : Managed setup failed"
       exit 1
    fi
    
    wait_for_admin
    
    echo "Adding Machine $machineName"
    runuser -l oracle -c "export JAVA_HOME=$JDK_PATH/jdk1.8.0_131 ; $INSTALL_PATH/Oracle/Middleware/Oracle_Home/oracle_common/common/bin/wlst.sh $DOMAIN_PATH/add-machine.py"
    if [[ $? != 0 ]]; then
         echo "Error : Adding machine $machineName failed"
         exit 1
    fi
    
    echo "Enrolling Domain for Machine $machineName"
    runuser -l oracle -c "export JAVA_HOME=$JDK_PATH/jdk1.8.0_131 ; $INSTALL_PATH/Oracle/Middleware/Oracle_Home/oracle_common/common/bin/wlst.sh $DOMAIN_PATH/enroll-server.py"
    if [[ $? != 0 ]]; then
         echo "Error : Enrolling machine $machineName failed"
         exit 1
    fi
}

# Create systemctl service for nodemanager
function create_nodemanager_service()
{
 echo "Creating services for Nodemanager"
 echo "Setting CrashRecoveryEnabled true at $DOMAIN_PATH/$wlsDomainName/nodemanager/nodemanager.properties"
 sed -i.bak -e 's/CrashRecoveryEnabled=false/CrashRecoveryEnabled=true/g'  $DOMAIN_PATH/$wlsDomainName/nodemanager/nodemanager.properties
 if [ $? != 0 ];
 then
   echo "Warning : Failed in setting option CrashRecoveryEnabled=true. Continuing without the option."
   mv $DOMAIN_PATH/nodemanager/nodemanager.properties.bak $DOMAIN_PATH/$wlsDomainName/nodemanager/nodemanager.properties
 fi
 sudo chown -R $username:$groupname $DOMAIN_PATH/$wlsDomainName/nodemanager/nodemanager.properties*
 echo "Creating NodeManager service"
 cat <<EOF >/etc/systemd/system/wls_nodemanager.service
 [Unit]
Description=WebLogic nodemanager service
 
[Service]
Type=simple
# Note that the following three parameters should be changed to the correct paths
# on your own system
WorkingDirectory="$DOMAIN_PATH/$wlsDomainName"
ExecStart="$DOMAIN_PATH/$wlsDomainName/bin/startNodeManager.sh"
ExecStop="$DOMAIN_PATH/$wlsDomainName/bin/stopNodeManager.sh"
User=oracle
Group=oracle
KillMode=process
LimitNOFILE=65535
 
[Install]
WantedBy=multi-user.target
EOF
echo "Created service for Nodemanager"
}



#Install Weblogic Server using Silent Installation Templates
function installWLS()
{
    # Using silent file templates create silent installation required files
    echo "Creating silent files for installation from silent file templates..."

    sed 's@\[INSTALL_PATH\]@'"$INSTALL_PATH"'@' ${SILENT_FILES_DIR}/uninstall-response.template > ${SILENT_FILES_DIR}/uninstall-response
    sed -i 's@\[WLSVER\]@'"$WLS_VER"'@' ${SILENT_FILES_DIR}/uninstall-response
    sed 's@\[INSTALL_PATH\]@'"$INSTALL_PATH"'@' ${SILENT_FILES_DIR}/response.template > ${SILENT_FILES_DIR}/response
    sed 's@\[INSTALL_PATH\]@'"$INSTALL_PATH"'@' ${SILENT_FILES_DIR}/oraInst.loc.template > ${SILENT_FILES_DIR}/oraInst.loc
    sed -i 's@\[GROUP\]@'"$USER_GROUP"'@' ${SILENT_FILES_DIR}/oraInst.loc

    echo "Created files required for silent installation at $SILENT_FILES_DIR"

    export UNINSTALL_SCRIPT=$INSTALL_PATH/Oracle/Middleware/Oracle_Home/oui/bin/deinstall.sh
    if [ -f "$UNINSTALL_SCRIPT" ]
    then
            currentVer=`. $INSTALL_PATH/Oracle/Middleware/Oracle_Home/wlserver/server/bin/setWLSEnv.sh 1>&2 ; java weblogic.version |head -2`
            echo "#########################################################################################################"
            echo "Uninstalling already installed version :"$currentVer
            runuser -l oracle -c "$UNINSTALL_SCRIPT -silent -responseFile ${SILENT_FILES_DIR}/uninstall-response"
            sudo rm -rf $INSTALL_PATH/*
            echo "#########################################################################################################"
    fi

    echo "---------------- Installing WLS ${WLS_JAR} ----------------"
    echo $JAVA_HOME/bin/java -d64 -jar  ${WLS_JAR} -silent -invPtrLoc ${SILENT_FILES_DIR}/oraInst.loc -responseFile ${SILENT_FILES_DIR}/response -novalidation
    runuser -l oracle -c "$JAVA_HOME/bin/java -d64 -jar  ${WLS_JAR} -silent -invPtrLoc ${SILENT_FILES_DIR}/oraInst.loc -responseFile ${SILENT_FILES_DIR}/response -novalidation"

    # Check for successful installation and version requested
    if [[ $? == 0 ]];
    then
      echo "Weblogic Server Installation is successful"
    else

      echo_stderr "Installation is not successful"
      exit 1
    fi
    echo "#########################################################################################################"

}

function enabledAndStartNodeManagerService()
{
  sudo systemctl enable wls_nodemanager
  sudo systemctl daemon-reload
  echo "Starting nodemanager service"
  sudo systemctl start wls_nodemanager
}


#main script starts here

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export BASE_DIR="$(readlink -f ${CURR_DIR})"

if [ $# -ne 7 ]
then
    usage
    exit 1
fi

export acceptOTNLicenseAgreement="${1}"
export otnusername="${2}"
export otnpassword="${3}"
export wlsDomainName="${4}"
export wlsAdminURL="${5}"
export wlsUserName="${6}"
export wlsPassword="${7}"

echo "Arguments passed: acceptOTNLicenseAgreement=${1}, otnusername=${2},otnpassword=${3},wlsDomainName=${4},wlsAdminURL=${5},wlsUserName=${6},wlsPassword=${7}"

validateInput

addOracleGroupAndUser

export WLS_VER="12.2.1.3.0"
export nmHost=`hostname`
export nmPort=5556
export wlsAdminPort=7001
export wlsSSLAdminPort=7002
export wlsManagedPort=8001
export wlsClusterName="cluster1"
export dynamicServerTemplate="myServerTemplate"
export nmHost=`hostname`
export machineNamePrefix="machine"
export machineName="$machineNamePrefix-$nmHost"
export WLS_VER="12.2.1.3.0"
export WEBLOGIC_DEPLOY_TOOL=https://github.com/oracle/weblogic-deploy-tooling/releases/download/weblogic-deploy-tooling-1.1.1/weblogic-deploy.zip

JDK_PATH="/u01/app/jdk"
WLS_PATH="/u01/app/wls"
DOMAIN_PATH="/u01/domains"
export WEBLOGIC_DEPLOY_TOOL=https://github.com/oracle/weblogic-deploy-tooling/releases/download/weblogic-deploy-tooling-1.1.1/weblogic-deploy.zip

setupInstallPath

cleanup

installUtilities

downloadJDK

validateJDKZipCheckSum 

downloadWLS

setupJDK

setupWLS

installWLS

getMachineMatchExpression

create_managedSetup

create_nodemanager_service

enabledAndStartNodeManagerService

start_cluster

cleanup
