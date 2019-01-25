#!/bin/bash

###############################################
#                   VARIABLES                 #
###############################################
# env variables
# $REPO
# $HARBOR_USERNAME
# $HARBOR_PASSWORD
# $REPOSITORY_DOMAIN
# $ACTION
# $DAYS_TOO_KEEP
start=$(date +%s)
url="https://$REPOSITORY_DOMAIN"
project=$(echo $REPO | cut -f1 -d"/")
repo=$(echo $REPO | cut -f2 -d"/")
# echo variables
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'

###############################################
# Check existence of mandatory env vars       #
# On failure -> exit 1                        #
###############################################
missing_env=false
if [[ -z $REPO ]]; then 
    echo -e "${RED}ERROR: Env variable 'REPO' was not set. Please provide repository information in format {project}/{repository}."
    missing_env=true
    if [[ -z $HARBOR_USERNAME ]]; then 
        echo -e "${RED}ERROR: Env variable 'HARBOR_USERNAME' was not set. Please provide an username with write access to wanted repository."
        missing_env=true
        if [[ -z $HARBOR_PASSWORD ]]; then
            echo -e "${RED}ERROR: Env variable 'HARBOR_PASSWORD' was not set. Please provide correct password for HARBOR_USERNAME."
            missing_env=true
            if [[ -z $REPOSITORY_DOMAIN ]]; then 
                echo -e "${RED}ERROR: Env variable 'REPOSITORY_DOMAIN' was not set. Please provide correct domain of wanted Harbor instance."
                missing_env=true
                if [[ -z $ACTION ]]; then 
                    echo -e "${RED}ERROR: Env variable 'ACTION' was not set. Please provide select what action do you need (list/delete)."
                    missing_env=true
                    if [[ -z $DAYS_TOO_KEEP ]]; then 
                        echo -e "${RED}ERROR: Env variable 'DAYS_TOO_KEEP' was not set. Please provide how many days worth of tags do you need to keep undeleted."
                        missing_env=true
                    fi
                fi
            fi
        fi
    fi
fi

if $missing_env; then
    exit 1
fi

###############################################
#                Welcome message              #
###############################################
echo -e "${NC}$(date) --------------------------- "
echo -e "${NC}$(date) --- Harbor cleanup tool --- "
echo -e "${NC}$(date) --------------------------- "
echo -e "${NC}$(date) --- Selected repository domain:   ${ORANGE}$REPOSITORY_DOMAIN ${NC}"
echo -e "${NC}$(date) --- Selected repo for cleanup:    ${ORANGE}$REPO ${NC}"
if [[ "$ACTION" = "delete" ]]; then
    echo -e "${NC}$(date) --- ${NC}Selected action:              ${RED}$ACTION --- deleting tags for $project/$repo${NC}"
else 
    echo -e "${NC}$(date) --- ${NC}Selected action:              ${GREEN}$ACTION --- skipping delete task.${NC}"
fi
if [[ "$DAYS_TOO_KEEP" = "0" ]]; then
    echo -e "${NC}$(date) --- Retention period selected:    ${RED}0 days ${NC}-> ${RED}FULL REPOSITORY DELETE${NC}"
else
    echo -e "${NC}$(date) --- Retention period selected:    ${RED}$DAYS_TOO_KEEP days${NC}"
fi

###############################################
# Getting list of tags from given repository  #
###############################################
# getting token
token=$(curl -s -k -u $HARBOR_USERNAME:$HARBOR_PASSWORD $url/service/token?service=harbor-registry\&scope=repository:$project/$repo:pull,push | jq .token | sed 's/"//g')

# getting tags
output=$(curl -s -k -H "Content-Type: application/json" -H "Authorization:  Bearer $token" -X GET $url/v2/$project/$repo/tags/list | jq .tags)
if [[ "$output" = "null" ]]; then
    echo -e "${NC}$(date) --- ${GREEN}SKIPPED - Selected repository ${ORANGE}$project/$repo${GREEN} is already empty - there is nothing to be deleted."
    end=$(date +%s)
    echo -e "${NC}$(date) --- Runtime for ${ORANGE}$REPO${NC} cleanup: $((end-start)) seconds${NC}"
    exit 0
fi
tags=$(echo $output | jq .[] | sed 's/"//g' | tr " " "\n")

###############################################
#                 MAIN PART                   #
###############################################
if [[ "$DAYS_TOO_KEEP" = "0" ]]; then

    ###############################################
    #       RETENTION 0 = FULL DELETE             #
    ###############################################
    echo -e "${NC}$(date) --- Intiating full repository cleanup ${NC}"

    # loop over all tags 
    for tag in $tags
    do
        # error catch section before deletion
        # 404 = tag already deleted (for some reason registry API returns already deleted tags in a list call)
        # 401 = token is issued for 1800s, therefore it has to be renewed in case it expires
        http_code=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" -X GET $url/v2/$project%2F$repo/manifests/$tag -w "%{http_code}" -o /dev/null | sed '/^$/d')
        case $http_code in
            401) 
                # token renewal
                token=$(curl -s -k -u $HARBOR_USERNAME:$HARBOR_PASSWORD $url/service/token?service=harbor-registry\&scope=repository:$project/$repo:pull,push | jq .token | sed 's/"//g')
                ;;
            404) 
                echo -e "${NC}$(date) --- ${NC}SKIPPED - tag $tag is already deleted.${NC}"
                continue
                ;;
        esac

        # cleaning part
        if [[ "$ACTION" = "delete" ]]; then
            echo -n -e "${NC}$(date) --- ${ORANGE}DELETE action - Removing tag: $tag ${NC}--- "
            http_code=$(curl -sX DELETE "$url/api/repositories/$project%2F$repo/tags/$tag" -H  "accept: application/json" -u $HARBOR_USERNAME:$HARBOR_PASSWORD -w "%{http_code}" -o /dev/null | sed '/^$/d')
            case $http_code in
                200) echo -e "${GREEN}OK: Delete successfull.${NC}" ;;
                400) echo -e "${RED}ERROR: $http_code - Invalid repo_name.${NC}" ;;
                401) echo -e "${RED}ERROR: $http_code - User is not authorized to perform this action.${NC}" ;;
                403) echo -e "${RED}ERROR: $http_code - Forbidden.${NC}" ;;
                404) echo -e "${RED}ERROR: $http_code - Repository or tag not found.${NC}" ;;
                *) echo -e "${RED}ERROR: $http_code - description is not available.${NC}" ;;
            esac
        else
            echo  -e "${NC}$(date) --- ${GREEN}LIST action - tag marked for deletion: $tag${NC}"
        fi
    done

else
    ###############################################
    #       RETENTION >0 = date check delete      #
    ###############################################
    echo -e "${NC}$(date) --- Filtering tags based on selected retention ${NC}"

    comparison_date=$(date -d $(date -d "now - $DAYS_TOO_KEEP days" +"%Y-%m-%d") +%s)
    IFS=$'\n'

    # loop over all tags
    for tag in $tags
    do
        # error catch section before deletion
        # 404 = tag already deleted (for some reason registry API returns already deleted tags in a list call)
        # 401 = token is issued for 1800s, therefore it has to be renewed in case it expires
        http_code=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" -X GET $url/v2/$project%2F$repo/manifests/$tag -w "%{http_code}" -o /dev/null | sed '/^$/d')
        case $http_code in
            401) 
                # token renewal
                token=$(curl -s -k -u $HARBOR_USERNAME:$HARBOR_PASSWORD $url/service/token?service=harbor-registry\&scope=repository:$project/$repo:pull,push | jq .token | sed 's/"//g')
                ;;
            404) 
                echo -e "${NC}$(date) --- ${NC}SKIPPED - tag $tag is already deleted.${NC}"
                continue 
                ;;
        esac
        
        # get creation date of tag (prepare for date comparison)
        created=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" -X GET $url/v2/$project%2F$repo/manifests/$tag | jq -r '.history[].v1Compatibility' | jq '.created' | sort | tail -n1 | sed 's/"//g')
        tag_date=$(date -d $(echo $created | cut -f1 -d"T") +%s)
        
        # debug part (handled by DEBUG environment variable - optional)
        # used to catch unexpected errors when getting created date of the tag
        if [[ "$DEBUG" = "true" ]]; then
            echo -e "${NC}"$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer $token" -X GET $url/v2/$project%2F$repo/manifests/$tag -w "%{http_code}")
            echo -e "${NC}-----------------------------------------"
	        echo -e "${NC}DEBUG --- created: $created --- tag_date: $tag_date --- comparison_date: $comparison_date${NC}"
        fi
        
        # cleaning part (with date comparison)
        if [ $comparison_date -ge $tag_date ]; 
        then
            if [[ "$ACTION" = "delete" ]]; then
                echo -n -e "${NC}$(date) --- ${ORANGE}DELETE action - Removing tag: $tag ${NC}--- "
                http_code=$(curl -sX DELETE "$url/api/repositories/$project%2F$repo/tags/$tag" -H  "accept: application/json" -u $HARBOR_USERNAME:$HARBOR_PASSWORD -w "%{http_code}" -o /dev/null | sed '/^$/d')
                case $http_code in
                    200) echo -e "${GREEN}OK: Delete successfull.${NC}" ;;
                    400) echo -e "${RED}ERROR: $http_code - Invalid repo_name.${NC}" ;;
                    401) echo -e "${RED}ERROR: $http_code - User is not authorized to perform this action.${NC}" ;;
                    403) echo -e "${RED}ERROR: $http_code - Forbidden.${NC}" ;;
                    404) echo -e "${RED}ERROR: $http_code - Repository or tag not found.${NC}" ;;
                    *) echo -e "${RED}ERROR: $http_code - description is not available.${NC}" ;;
                esac
            else
                echo  -e "${NC}$(date) --- ${GREEN}LIST action - tag marked for deletion: $tag${NC}"
            fi
        else
            echo  -e "${NC}$(date) --- ${GREEN}SKIPPED - tag is newer than $DAYS_TOO_KEEP days: $tag${NC}"
        fi  
    done
    unset IFS
fi

end=$(date +%s)
echo -e "${NC}$(date) --- Runtime for ${ORANGE}$REPO${NC} cleanup: $((end-start)) seconds${NC}"
