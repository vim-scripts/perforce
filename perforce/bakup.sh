#!/bin/bash
# Author: Hari Krishna Dara ( hari_vim at yahoo dot com ) 
# Last Change: 17-Oct-2003 @ 10:36
# Requires:
#   - bash or ksh (tested on cygwin and MKS respectively).
#   - Info Zip for the -z option to work (comes with linux/cygwin). Download for
#     free from:
#       http://www.info-zip.org/
#   - GNU tar for the -a option to work (comes with linux/cygwin).
# Version: 1.2.1
# Licence: This program is free software; you can redistribute it and/or
#          modify it under the terms of the GNU General Public License.
#          See http://www.gnu.org/copyleft/gpl.txt 
# Description:
#   Shell script to take backup of all the open files in perforce SCM.
#
#TODO:
#   - Option to generate a diff at the end.
#   - Option to restrict by type (useful to avoid huge binary files).
#   - Support to run zip from a different directory (to avoid certain path
#     component from getting into zipfile).

usage()
{
cat <<END
$0 [<backup dir>] [<source dir>] ...
$0 -h -n -q -v -z -zz [-c <change number>] [-t <backup dir>] [-r <backup root>] [[-s <source dir>] ...]
    -t specify full path name to the target directory. If -z is specified this
       becomes the path to the zip file name.
    -r set the root for creating the default backup dir/zip file. Not used if
       "backup dir" is specified. You can also set BAKUP_ROOT environmental
       variable. Defaults to p: (p drive), because that is what it is on my
       system :).
    -a create a tar file instead of copying the files. You can specify the
       tar file name using -t option.
    -a[-|--]<taropt>
       Pass -taropt to tar command.
       Ex: Pass "-aC <dir>" or "-adirectory=<dir>" to cd to a directory before
           creating the tar file.
    -z create a zip file instead of copying the files. You can specify the
       zip file name using -t option.
    -z[-]<zipopt>
       Pass -zipopt to zip command.
       Ex: Pass -zz for a prompt from zip to enter a comment.
    -s limit to open files matching the given wildcard (local or depot). This
       can be repeated multiple times to specify multiple source directories.
       You can pass in anything that the 'p4 opened' command itself accepts.
    -c limit the files to those specified in the change number, in addition to
       the -s option. This can't be repeated multiple times though.
    -n don't execute any commands, just show what is going to be done. Does not
       work with -z option (yet).
    -q quite mode, no messages
    -v verbose mode, print messages (the default).
    -h print help message (this message) and exit
  The first unspecified directory is treated as target directory, and the
  remaining directories are treated as source directories. The '-n' option can
  be used to generate a batch script that can be run later. The source
  directory can be in depot or local format (NO BACKSLASHES PLEASE). Do not
  combine multiple options into one argument.
Examples:
     bakup.sh
         - Backup all the open files into a default generated backup dir. in p:
           drive (p: driver is the default backup directory).
     bakup.sh mybak c:/dev/branch/src
         - Backup open files only under 'c:/dev/branch/src' into 'mybak'
	   directory.
     bakup.sh -s //depot/branch/src -s //depot/branch/cfg
         - Backup open files only under 'src' and 'cfg' into the default bakup
           dir.

     You could add -z option to all the above usages to create a zip file
     instead of creating a directory. You need to have Info-Zip installed in the
     path for this to work.

     bakup.sh -n > mybackup.bat
         - Generates a 'mybackup.bat' batch file that can be run at a later
           time to take a backup.
END
exit 1
}

generateTargetDirName()
{
    today=`date +"%d-%b-%Y"`
    inc=1
    #echo "---first time"
    tDir="$targetRoot/bakup-$today"
    while [ -d $tDir -o -f $tDir.zip ]; do
        inc=$[inc + 1]
        tDir="$targetRoot/bakup-${today}_$inc"
        #echo "---subsequent time inc=$inc tDir=$tDir"
    done
    echo "$tDir"
}

getExtOpt()
{
    archiveOpt=${1/[-+]$2/}
    case $archiveOpt in
    --*)
	;;
    -*)
	;;
    ??*) # Long option.
	archiveOpt="--$archiveOpt"
	;;
    *)
	archiveOpt="-$archiveOpt"
	;;
    esac
    echo $archiveOpt
}

getOptArg()
{
    case $1 in
    --*)
	changeNumber=${1/*=}
	;;
    -*)
        shift
        if [ $# -eq 0 ]; then
            usage
        fi
        changeNumber=$1
    esac
    echo $changeNumber
}

testMode=0
archiveOpts=''
chDirectory='' # If set, the listing is generated relative to this dir.
archiveMode=0
verboseMode=1
targetDir=""
targetRoot=""
sourceDirs=""
changeNumber=""
compressedTar=0
until [ $# -eq 0 ]; do
    case $1 in
    -h)
        usage
        ;;
    -v)
        verboseMode=1
        ;;
    -q)
        verboseMode=0
        ;;
    -a)
        archiveMode=2 # Tar.
	verboseMode=0 # Turn on quite mode, as zip will anyway show the files.
        testMode=1 # Turn on test mode, so we won't copy files.
        ;;
    -a*)
	# Need to take care of options with optional args.
	extOpt=`getExtOpt $1 a`
	if [ $extOpt = -z ]; then
	    compressedTar=1
	fi
	archiveOpts="${archiveOpts} $extOpt"
	case $extOpt in
	--directory)
	    chDirectory=`getOptArg $extOpt`
	    ;;
	-C)
	    chDirectory=`getOptArg $extOpt`
	    archiveOpts="${archiveOpts} $chDirectory"
	    ;;
	esac
	;;
    -z)
        archiveMode=1 # Zip.
	verboseMode=0 # Turn on quite mode, as zip will anyway show the files.
        testMode=1 # Turn on test mode, so we won't copy files.
        ;;
    -z*)
	# Need to take care of options with optional args.
	archiveOpts="${archiveOpts} `getExtOpt $1 z`"
	;;
    -n)
        testMode=1
	verboseMode=0
        ;;
    -c)
	changeNumber=`getOptArg $1`
        ;;
    -t)
        targetDir=`getOptArg $1`
        ;;
    -r)
        targetRoot=`getOptArg $1`
        ;;
    -s)
        sourceDirs="$sourceDirs `getOptArg $1`"
        ;;
    -?)
        usage
        ;;
    *)
        if [ "$targetDir" = "" ]; then
            #echo "---setting targetDir=$targetDir"
            targetDir=$1
        else
            #echo "---appending sourceDirs=$1"
            sourceDirs="$sourceDirs $1"
        fi
        ;;
    esac
    shift
done

if [ x${targetDir}x = xx -a x${targetRoot}x = xx ]; then
    targetRoot=$BAKUP_ROOT
    if [ "$targetRoot" = "" ]; then
        targetRoot="p:"
    fi
fi

if [ "$targetDir" = "" ]; then
    targetDir=`generateTargetDirName`
fi

if [ "$sourceDirs" = "" ]; then
    # By default backup all the open files.
    sourceDirs="//..."
fi


# Create a dir if it doesn't exist, exit on error.
createDir()
{
    if ! [ -d "$1" ]; then

        if [ $testMode -eq 1 -o $verboseMode -eq 1 ]; then
            echo "mkdir -p $1" 1>&4
        fi

        if [ $testMode -eq 0 ]; then
            mkdir -p "$1"
            if [ $? -ne 0 ]; then
                echo "Error creating $1" 1>&2
                exit 1
            fi
        fi
    fi
}


#if [ $testMode -eq 1 ]; then
#    echo "Running in test mode"
#fi

if [ $archiveMode -eq 0 ]; then
    createDir $targetDir 4>&1
fi

if [ $verboseMode -eq 1 ]; then
    echo "Copying to target directory: $targetDir"
fi

# Testing for $BASH will not work, if you happen to use the cygwin sh instead of
#   bash.
unset PWD
codelineRoot=`p4 info | sed -n -e 's;\\\\;/;g' -e 's/Client root: //p'`
#echo "---codelineRoot=$codelineRoot"
rootDirLength=${#codelineRoot}

if [ $archiveMode -eq 1 ]; then
    pipeCmd="zip ${archiveOpts} -@ ${targetDir}.zip"
    echo "Using: '${pipeCmd}' to create zip archive"
elif [ $archiveMode -eq 2 ]; then
    if [ $compressedTar -eq 1 ]; then
	fileExt='tar.gz'
    else
	fileExt='tar'
    fi
    pipeCmd="tar -cvf ${targetDir}.${fileExt} ${archiveOpts} -T -"
    echo "Using: '${pipeCmd}' to create zip archive"
else
    pipeCmd="cat"
fi

exec 4>&1; {
    for sourceDir in $sourceDirs; do
	if [ ! -f $sourceDir ]; then
	    case $sourceDir in
		*...)
		    ;;
		*/)
		    sourceDir="${sourceDir}..."
		    ;;
		*)
		    sourceDir="${sourceDir}/..."
		    ;;
	    esac
	fi
	if [ "$changeNumber" = "" ]; then
	    openedCmd="p4 opened $sourceDir"
	else
	    openedCmd="p4 opened -c $changeNumber $sourceDir"
	fi
	if [ $verboseMode -eq 1 ]; then
	    echo "Collecing list of open files using: $openedCmd" 1>&4
	fi

	# FIXME: I couldn't get it working with the following IFS, don't know
	# why. So as a temp. work-around, I am temporarily substituting spaces
	# with '|' in sed and converting them back to spaces in the start of the
	# loop.
	#IFS="\n\r"
	openedFiles=`$openedCmd| sed -e '/- delete [^ ]\+ change /d' -e 's/ /|/g' -e 's;#.*;;' -e "s;//depot/;$codelineRoot/;" -e "s;^${chDirectory}/*;;"`
        for file in `echo $openedFiles`; do
	    file=${file//\|/ }
	    #echo "---file = $file" 1>&4
	    dir=`dirname "$file"`
	    # Relative to the codeline root.
	    tgtDir="${targetDir}/${dir:$rootDirLength}"
	    #echo "---tgtDir = $tgtDir" 1>&4

	    if [ $archiveMode -eq 0 ]; then
		createDir "$tgtDir"
	    fi

	    if [ $archiveMode -ne 0 ]; then
	    	echo $file 1>&3
	    elif [ $testMode -eq 1 -o $verboseMode -eq 1 ]; then
		echo "cp $file $tgtDir" 1>&4
	    fi
	    if [ $testMode -eq 0 ]; then
		cp "$file" "$tgtDir"
		if [ $? -ne 0 ]; then
		    echo "Error copying $1" 1>&2
		    exit 1
		fi
	    fi
	done
    done
} 3>&1 | $pipeCmd
