#!/bin/bash

# 2021-05-13 J.Nider
# Create a user account on a local or remote host. Add an ssh public key for
# remote access. If the account already exists, add a new key for ssh
# authentication.

function usage()
{
	echo "Create a user account on a remote machine and set it up for SSH access"
	echo "$0 -u <username> -k <key> [-a <admin>] [-c] [-i <identity>] [-p <password] [-r <remote>]"
	echo "Where:"
	echo "username    The name of the user account to create"
	echo "key         The name of the file containing the public key for the new account"
	echo "admin       The name of the administrator account on the remote machine (that has passwordless sudo access)"
	echo "cleanup     Remove the temporary files when done"
	echo "password    Password for the new account"
	echo "remote      The IP address or name of the remote machine. This can be omitted for creating a user on the local machine"
	echo "identity    The identity file (private key) of the administrator account"
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

while getopts "a:cu:i:k:p:r:" params; do
	case "$params" in
	a)
		admin=${OPTARG}
		;;

	c)
		cleanup=true
		;;

	u)
		user=${OPTARG}
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
	esac
done

#echo "admin=$admin"
#echo "user=$user"
#echo "identity=$identity"
#echo "key=$key"
#echo "remote=$remote"
#echo "password=$pw"

ssh_dir=/home/$user/.ssh

IDENTITY=${identity:+"-i $identity"}

# generate a random password if one has not been provided
if [[ -z $pw ]]; then
	echo "Generating password"
	pw=$(pwgen -B -a 12 1)
fi

if [[ ! -z $remote ]]; then
	echo "copying script to $remote:/tmp"
	# copy myself to the remote machine
	scp $IDENTITY $0 $key $admin@$remote:/tmp

	# execute myself on the remote machine
	exe_name=${0##*/}
	ssh $IDENTITY $admin@$remote sudo /tmp/$exe_name -a $admin -c -u $user -k /tmp/$key -p $pw
	echo "Done!"
	exit
fi

# you must be root to run this
echo "$admin: Creating account $user"
if [ $EUID != 0 ]; then
	echo $(whoami)
	echo "ERROR: You are not sudo"
   usage
	exit
fi

# make sure the necessary parameters are present
if [[ -z $user || -z $key ]]; then
	usage
	exit
fi

# create the user account
echo "Adding user account $user"
useradd -U -s /bin/bash -m $user 2> /dev/null
ret=$?
if [[ $ret == 0 ]]; then
	# set and print the password!
	echo $user:$pw | chpasswd
	echo "The password is: $pw"
elif [[ $ret == 9 ]]; then
	echo "Account already exists - updating"
else
	echo "Error $ret adding user"
	exit
fi

# make sure the ssh directory exists
create_dir

echo "Copying public key"
key_name=${key##*/}
cp /tmp/$key_name $ssh_dir

# append the key to user's authorized keys (in case the file already exists)
cat /tmp/$key_name >> $ssh_dir/authorized_keys

# set owner on all the files
chown -R $user:$user $ssh_dir

if [[ ! -z $cleanup ]]; then
	echo "Cleaning up"
	rm /tmp/new-user.sh
	rm /tmp/$key_name
fi
