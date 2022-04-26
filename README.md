# Terraform + ECS + RDS

This repo contains some non-expert configurations to get Terraform Working with ECS+RDS+HTTPS in a simple way.

Any expert help would be much appreciated!

## How it works:

- Define the environment vars:

	```sh
	# .env
	TF_VAR_project="project_name"
	TF_VAR_password_db="password"
	TF_VAR_ecs_acm_arn="arn:aws:acm:ZONE:NUMBER:certificate/UUID"
	```

- Import the vars:

	```sh
	export $(cat .env | xargs)
	```
- Start terraform

	```sh
	terraform init
	```

- Create your workspaces (environments):

	```sh
	terraform workspace new staging
	```

- Build the infrastructure:

	```sh
	terraform apply -auto-approve
	```

- After this, you must to upload your container environment variables into the S3 Bucket with the following path:

	_project_name_-backend-env/_workspace_.env

- Finally, go to the Elastic Container Registry, open the repository named _project_-_workspace_ and click over the "View push commands", follow these to set your first container and you are done!

Next steps:

	- Reorder the modules folder and refactor some things.
