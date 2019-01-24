# harbor-cleanup
This image is created to manage Harbor repositories via API call, effectively skipping work with UI which can be very slow in larger repositories.
At this moment, it is tested and working with Harbor v1.6.0

## usage
Image is expecting several environments variables in order to work.

List of variables is here:

Var Name | Required | Description | Notes 
------------- | ------------- | ------------- |------------- 
REPO | **yes** | repository name | format: {project}/{repository}
ACTION | **yes** | wanted action | list=just list tags meant for deletion / delete=delete tags 
DAYS_TOO_KEEP | **yes** | retention policy | Number of days worth of images to keep in repository (0 = full repo cleanup)
HARBOR_USERNAME | **yes** | Harbor login username | Needs RW rights to wanted project/repo 
HARBOR_PASSWORD | **yes** | Harbor login password | Needs RW rights to wanted project/repo 
REPOSITORY_DOMAIN | **yes** | domain name of Harbor | example: harbor.mycompany.net 
DEBUG | no | debug mode | true/false

DEBUG enables debug mode just in date comparison phase due to various intermittent errors I did encounter during testing of this. 
It is not enabled on another phases, where it was not needed so far.

## example usage command
```
docker run -it --rm \
-e REPO=test-project/testapp-db \
-e ACTION=list \
-e HARBOR_USERNAME=login \
-e HARBOR_PASSWORD=password \
-e REPOSITORY_DOMAIN="harbor.mycompany.net" \
-e DAYS_TOO_KEEP=90
zdenekvicar/harbor-cleanup:v0.1
```
