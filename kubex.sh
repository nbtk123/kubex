#!/bin/bash

# Copyright (c) 2018 Tal Yaniv


########################
#   internal methods   #
########################

# setup does the following:
# 1. Configures AWS with your global credentials, or with a profile if given to the '--profile' parameter.
# 2. Downloads aws-iam-authenticator into '/usr/local/bin/' and gives it running permissions
# 3. Calling the 'aws eks' commands for all environments

function setup
{
    for arg in "$@"
    do
        case $arg in
            --profile=*)
            PROFILE="${arg#*=}"
            shift
            ;;
        esac
    done

    if [[ -z "$PROFILE" ]]; then
        echo "No Profile given, using defaults"
        printf 'AKIAIKG452VK6YA2CJXA\nk9pQp1iKRSy+H+J77XLltGnRecBZkOktY9d9vkuF\nus-east-1\n\n' | aws configure
    else
        echo "Cofiguring according to $PROFILE"
        aws configure --profile $PROFILE
    fi

    echo "Downloading aws-iam-authenticator to /usr/local/bin/aws-iam-authenticator..."
    curl https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/darwin/amd64/aws-iam-authenticator --output /usr/local/bin/aws-iam-authenticator
    chmod 755 /usr/local/bin/aws-iam-authenticator

    echo "Updateing kubeconfig for dev, qa, staging, production..."
    aws eks update-kubeconfig --name develop
    aws eks update-kubeconfig --name qa
    aws eks update-kubeconfig --name staging
    aws eks update-kubeconfig --name production --region us-west-2
}


# get_kube_token will get your kubernetes (may take a few seconds) and copy it to your clipboard

function get_kube_token {
    echo "getting token..."
    RES=`kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')`
    echo ${RES#*token: } | cut -f1 -d" " | pbcopy
    echo "token copied to clipboard"
}


# get_contexts will scan your ~/.kube/config file, prepare a list of contexts and will store them in contexts variable

function get_contexts {

    contexts=() # stores an array of contexts
    found_contexts=false # flags finding the "contexts" label
    contexts_count=0

    # iterating over the config file
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [ "$found_contexts" = true ]; then
            if [[ $line == *"  name: "* ]]; then
                line_content=${line#*"  name: "}
                contexts+=("$line_content")
                contexts_count=$(( $contexts_count + 1 ))
            fi
        fi
        if [ "$line" = users: ]; then
            break
        fi
        if [ "$line" = contexts: ]; then
            found_contexts=true
        fi
    done < ~/.kube/config

}



##########################
#   commands execution   #
##########################

# ./kubex.sh s
# or
# ./kubex.sh --setup
if [ "$1" == "s" ] || [ "$1" == "--setup" ]; then
    setup
fi

# ./kubex.sh t
# or
# ./kubex.sh --token

# gets a token and stores in clipboard

if [ "$1" == "t" ] || [ "$1" == "--token" ]; then
    get_kube_token
fi


# ./kubex.sh p
# or
# ./kubex.sh --proxy

# gets a token
# stores in clipboard
# opens a Chrome (Mac) browser page and navigates to the login screen
# starts a proxt session

if [ "$1" == "p" ] || [ "$1" == "--proxy" ]; then
    get_kube_token
    /usr/bin/open -a "/Applications/Google Chrome.app" "http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login"
    kubectl proxy
fi


# ./kubex.sh c <conext index>
# or
# ./kubex.sh --context <context index>

# switches context
# to list all contexts use:
# ./kubex.sh --list-contexts 

# example - to list contexts and switch to production:
# $ ./kubex.sh --list-contexts
# 1 - arn:aws:eks:us-east-1:439989238490:cluster/staging
# 2 - arn:aws:eks:us-east-1:439989238490:cluster/production
# $ ./kubex.sh --context 2

if [[ "$2" != "" && ( "$1" == "c" || "$1" == "--context" ) ]]; then
    get_contexts
    CONTEXT=${contexts[$(( $2 - 1 ))]}
    if [ "$CONTEXT" == "" ]; then
        echo "context out of scope (1~$contexts_count)"
    else
        kubectl config use-context "$CONTEXT"
    fi
fi



# ./kubex.sh l
# or
# ./kubex.sh --list-contexts

# lists all context in ~/.kube/config

# example
# $ ./kubex.sh --list-contexts
# 1 - arn:aws:eks:us-east-1:439989238490:cluster/staging
# 2 - arn:aws:eks:us-east-1:439989238490:cluster/production

if [ "$1" == "l" ] || [ "$1" == "--list-contexts" ]; then
    get_contexts

    context_index=0
    while [ "$context_index" -lt "$contexts_count" ]
    do
        echo $(( $context_index + 1 )) - ${contexts[$context_index]}
        context_index=$(( $context_index + 1 ))
    done
fi

if [ $# -eq 0 ]; then
    echo "kubex is a lightweight shell script for daily kubernetes jobs"
    echo
    echo "usage:"
    echo "./kubex.sh <arg1> <optional arg2>"
    echo "example:"
    echo ".kubex.sh l"
    echo
    echo "l or --list-contexts         list all kubernetes contexts"
    echo "                             use the index numbers to switch conexts with --context command"
    echo
    echo "t or --token                 generates a login token and copies to clipboard"
    echo
    echo "c <context index>"
    echo "or --context <context index> switches to a context from the list"
    echo "                             use l or --list to see the list"
    echo
    echo "p or --proxy                 gets a token and copies to clipboard"
    echo "                             opens Mac Chrome app with the login page"
    echo "                             starts a proxy session"
    echo
    echo "s [--profile=profile_name]"
    echo "or --setup [--profile=profile_name]"
    echo "                             Configures aws to the given profile or to the global credentials if --profile is missing,"
    echo "                             downloads aws-iam-authenticator into /usr/local/bin, and runs 'aws eks' commands for all the environments"
fi
