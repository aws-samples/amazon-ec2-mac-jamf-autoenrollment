TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -s -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo $JAMFURL
echo $computerInvitation
#Function to download and installs the Jamf binary from the $JAMFURL Server.

jamfinstall(){
    /usr/bin/curl -ks "https://$JAMFURL/bin/jamf" -o /tmp/jamf
    /bin/mkdir -p /usr/local/jamf/bin /usr/local/bin
    /bin/mv /tmp/jamf /usr/local/jamf/bin
    /bin/chmod +x /usr/local/jamf/bin/jamf
    /bin/ln -s /usr/local/jamf/bin/jamf /usr/local/bin
}

# check if jamf is installed
/usr/local/bin/jamf checkJSSConnection -retry 1
status=$?

if [ $status -eq 0 ]; then
  # `jamf` command was able to connect to the server correctly so we are enrolled.
  echo 'Already Jamf enrolled.'
  exit 0
elif [ $status -eq 127 ]; then
  # `jamf` command not found so we are definitely not enrolled.
  echo 'Not already Jamf enrolled.'
  shouldEnroll=true
else
  # `jamf` command exists, but had some other trouble contacting the server.
  echo 'Encountered a problem connecting to Jamf server.'

  if [[ "$jamfOutput" == *"Device Signature Error"* ]]; then
    echo 'Instance has likely moved to new physical hardware.'

    # Need to unenroll and then enroll as a new device.
    echo "Attempting to run 'jamf removeFramework'..."
    /usr/local/bin/jamf removeFramework
    removeStatus=${!}?

    if [ ${!removeStatus} -eq 0 ]; then
      echo 'Jamf enrollment removed.'
      shouldEnroll=true
    else
      echo "'jamf removeFramework' failed with exit code ${!removeStatus}."
      exit 1
    fi
  else
    echo "Run '/usr/local/bin/jamf checkJSSConnection' manually to troubleshoot."
    exit 1
  fi
fi
if $shouldEnroll ; then
  echo 'Attempting to enroll in Jamf Pro...'
    
    # Download binaries from public host
    jamfinstall

    ####################################################
    ## Create the configuration file at:
    ## /Library/Preferences/com.jamfsoftware.jamf.plist
    ####################################################
    jamfCLIPath=/usr/local/bin/jamf

    $jamfCLIPath createConf -url https://$JAMFURL/ -verifySSLCert always
    $jamfCLIPath setComputername --name $(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
    ####################################################
    ## Run enroll
    ####################################################
    $jamfCLIPath enroll -invitation $computerInvitation -noPolicy

    enrolled=$?
    if [ $enrolled -eq 0 ]
    then
    $jamfCLIPath update
    $jamfCLIPath policy -event enrollmentComplete
    enrolled=$?
    fi

    /bin/rm -rf /private/tmp/Binaries
    exit $enrolled