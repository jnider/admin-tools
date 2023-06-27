#!/bin/bash

# 2021-05-13 J.Nider
# Create a user account on a local or remote host. Add an ssh public key for
# remote access. If the account already exists, add a new key for ssh
# authentication.

# exit if there is an error (such as 'cp' not being able to find a file)
set -e

function usage()
{
	echo "Create a user account on a remote machine and set it up for SSH access"
	echo "$0 -u <username> -k <key> [-a <admin>] [-c] [-i <identity>] [-p <password] [-r <remote>] [-s]"
	echo "Where:"
	echo "-a <admin>       The name of the administrator account on the remote machine (that has passwordless sudo access)"
	echo "-c               Clean up (i.e. remove) the temporary files when done"
	echo "-i <identity>    The identity file (private key) of the administrator account"
	echo "-k <key>         The name of the file containing the public key for the new account"
	echo "-p <password>    Password for the new account"
	echo "-r <remote>      The IP address or name of the remote machine. This can be omitted for creating a user on the local machine"
	echo "-s               Give the new account passwordless sudo privileges"
	echo "-u <username>    The name of the user account to create"
	echo "-v               Print additional details about what the script is doing"
}

function create_dir
{
	if [ ! -d $ssh_dir ]; then
		echo "Creating .ssh directory"
		mkdir -p $ssh_dir
	fi

	if [ ! -d $ssh_dir ]; then
		echo "Error $? creating home ssh directory $ssh_dir"
		exit
	fi
}

while getopts "a:chi:k:p:r:su:v" params; do
	case "$params" in
	a)
		admin=${OPTARG}
		;;

	c)
		cleanup=1
		;;

	h)
		usage
		exit
		;;

	i)
		identity=${OPTARG}
		;;

	k)
		key=${OPTARG}
		;;

	p)
		pw=${OPTARG}
		;;

	r)
		remote=${OPTARG}
		;;

	s)
		superuser=1
		;;

	u)
		user=${OPTARG}
		;;

	v)
		VERBOSE=1
		;;
	esac
done

if [[ "$VERBOSE" ]]; then
	echo "admin=$admin"
	echo "user=$user"
	echo "identity=$identity"
	echo "key=$key"
	echo "remote=$remote"
	echo "password=$pw"
	echo "superuser=$superuser"
fi

ssh_dir=/home/$user/.ssh

IDENTITY=${identity:+"-i $identity"}

if [[ ! -z $remote ]]; then
	if [[ -z $admin ]]; then
		echo "You must provide an admin account name (-a) for the remote machine"
		exit
	fi

	echo "copying script to $remote:/tmp"
	# copy myself to the remote machine
	cmd="scp $IDENTITY $0 $key $admin@$remote:/tmp"
	[[ "$VERBOSE" ]] && echo $cmd
	$cmd
	if [[ $? != 0 ]]; then
		echo "Error copying script to $remote:/tmp"
		exit
	fi

	# generate a random password if one has not been provided
	if [[ -z $pw ]]; then
		echo "Generating password locally"
		pw=$(pwgen -B -a 12 1)
	fi

	# execute myself on the remote machine
	[[ "$VERBOSE" ]] && echo "Executing on remote machine"
	exe_name=${0##*/}
	cmd="ssh $IDENTITY $admin@$remote sudo /tmp/$exe_name -a $admin ${cleanup:+\"-c\"} -u $user ${key:+\"-k /tmp/$key\"} ${pw:+\"-p $pw\"} ${superuser:+\"-s\"}"
	[[ "$VERBOSE" ]] && echo "$cmd"
	$cmd
	echo "Done!"
	exit
else
	# you must be root to run this locally
	if [ $EUID != 0 ]; then
		echo $(whoami)
		echo "ERROR: You are not sudo"
		usage
		exit
	fi

	# copy key to /tmp to match the remote procedure
	cmd="cp $key /tmp"
	[[ "$VERBOSE" ]] && echo "$cmd"
	$cmd
fi

# make sure the necessary parameters are present
if [[ -z $user ]]; then
	echo "Username is missing"
	usage
	exit
fi

ret=$(id -u $user)
if [[ $ret == 0 ]]; then
	# create the user account
	[[ "$VERBOSE" ]] && echo "Adding user account $user"
	ret=$(useradd -U -s /bin/bash -m $user 2> /dev/null)
	if [[ $ret == 0 ]]; then
		# generate a random password if one has not been provided
		if [[ -z $pw ]]; then
			echo "Generating password"
			pw=$(pwgen -B -a 12 1)
		fi
	else
		echo "Error $ret adding user"
		exit
	fi
else
	[[ "$VERBOSE" ]] && echo "Updating account"
fi

# set and print the password!
if [[ ! -z $pw ]]; then
	pw="${pw#"${pw%%[![:space:]]*}"}"
	chpasswd <<<"$user:$pw"
	echo "The password is: $pw"
fi

# Give superuser privileges (sudo)
if [[ "$superuser" == 1 ]]; then
	echo "Giving super user privileges"
	usermod -a -G sudo $user
	# set up passwordless sudo
	echo "$user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$user
	chmod 600 /etc/sudoers.d/$user
fi

# set up public key
if [[ -n $key ]]; then
	[[ $VERBOSE ]] && echo "Setting up public key"
	# make sure the ssh directory exists
	create_dir

	echo "Copying public key"
	key_name=${key##*/}
	cp /tmp/$key_name $ssh_dir

	# check to see if the key already exists in authorized_keys
	count=0
	if [[ -e $ssh_dir/authorized_keys ]]; then
		value=($(< /tmp/$key_name))
		keyname=${value[2]}
		count=$(grep -c $keyname $ssh_dir/authorized_keys)
	fi

	if [[ $count == 0 ]]; then
		# append the key to user's authorized keys (in case the file already exists)
		[[ $VERBOSE ]] && echo "Appending public key to authorized_keys"
		cat /tmp/$key_name >> $ssh_dir/authorized_keys
	fi
fi

# set owner on all the files
chown -R $user:$user $ssh_dir

if [[ -n $cleanup ]]; then
	[[ $VERBOSE ]] && echo "Cleaning up"
	rm -f /tmp/new-user.sh
	rm -f /tmp/$key_name
fi
