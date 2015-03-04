function __mass_gitlab_utils_generate_request() {
    # build a simple curl with the right auth header and repo url
    gitlab_api_key=`git config mass-gitlab-utils.api-key`
    gitlab_api_url=`git config mass-gitlab-utils.repo`
 
    gitlab_auth_header="PRIVATE-TOKEN: ${gitlab_api_key}"
    gitlab_api_prefix="${gitlab_api_url%/}/api/v3"
    curl -qs "${3-}" -X "${1}" --header "${gitlab_auth_header}" "${gitlab_api_prefix}/${2}${4-}"
}

function __mass_gitlab_utils_get_last_pagination_page_of_object() {
    # gitlab apis are paginated. Grab the first page of an object and extract the "last" page number
    paginated_object="$1"
    object_pages=`__mass_gitlab_utils_generate_request "GET" "${paginated_object}" "-I" | egrep "^Link:.*"`
    # Regex to match the "last page"
    regex_pattern='^Link:.+page=([0-9]+)&per_page=0>\; rel="last".*$'

    # Grab the "last page"
    [[ $object_pages =~ $regex_pattern ]]
    echo "${BASH_REMATCH[1]-'1'}"
}

function __mass_gitlab_utils_concatenate_request_object() {
    # Fetch all pages of a requested object and concat them into a single array
    max_pages="$2"
    requested_object="$1"

    # Fetch and concatenate all pages of groups
    all_objects="[]"
    for ((i=1;i<=$max_pages;i++)); do
        this_request=`__mass_gitlab_utils_generate_request "GET" "${requested_object}" "" \?page=${i}`
	all_objects=`__mass_gitlab_utils_flatten_json "$this_request" "$all_objects"`
    done
     
    echo "$all_objects"
}

function __mass_gitlab_utils_flatten_json() {
    # jq comes with a flatten function in an alpha build, define it here if it's not available...
    jqflat='def flatten: reduce .[] as $i ([]; if $i | type == "array" then . + ($i | flatten) else . + [$i] end); flatten'
    echo "[$1,$2]" | jq "$jqflat"
}

function __mass_gitlab_utils_get_all_gids() {
    max_group_page=`__mass_gitlab_utils_get_last_pagination_page_of_object "groups"`
    __mass_gitlab_utils_concatenate_request_object "groups" "${max_group_page}"
}

function __mass_gitlab_utils_get_gid_from_name() {
    # search function is broken in our old gitlab api
    __mass_gitlab_utils_get_all_gids | jq ".[] | select(.path==\"$1\") | .id"
}

function __mass_gitlab_utils_get_name_from_gid() {
    # search function is broken in our old gitlab api
    __mass_gitlab_utils_get_all_gids | jq ".[] | select(.id==\"$1\") | .path"
}

function __mass_gitlab_utils_get_projects_from_group() {
    # Take a group name or gid and get all projects under it available to your user
    if [[ -z $1 ]]; then
        echo "Specify a group to fetch projects for"
	exit 1
    fi
    if [[ "$1" =~ [0-9]+ ]]; then
         group_id="$1"
    else
         group_id=`__mass_gitlab_utils_get_gid_from_name "$1"`
    fi
    projects_pagination=`__mass_gitlab_utils_get_last_pagination_page_of_object "projects"`
    all_projects=`__mass_gitlab_utils_concatenate_request_object "projects" $projects_pagination `
    echo $all_projects | jq -c ".[] |select(.namespace.id==$group_id)"
}

function __mass_gitlab_utils_update_project() {
echo "asdf"    
}

function __mass_gitlab_utils_update() {
   local_path=`git config mass-gitlab-utils.local-path`
   git_groups=( $(git config --get-all mass-gitlab-utils.group ) )
   IFS=$'\n'
   set -f
   for group in ${git_groups[@]}; do
       if [[ ! -d "${local_path}/${group}" ]]; then
           mkdir -p "${local_path}/${group}"
       fi
       group_projects=( $(__mass_gitlab_utils_get_projects_from_group "sddc") )
       for project in ${group_projects[@]}; do
           repo_path=`echo $group | jq -r ".path_with_namespace"`
           repo_url=`echo $group | jq -r ".ssh_url_to_repo"`
           echo "updating repo at ${local_path}/${repo_url}..."
	   if [[ ! -d "${local_path}/${repo_path}" ]]; then
               echo "updating repo at ${local_path}/${group}..."
	       pushd "${local_path}/${group}"
	       git clone $repo_url
	       popd
           else 
               pushd "${local_path}/${repo_path}"
	       git pull --all
	       popd
	   fi
       done
   done
}
