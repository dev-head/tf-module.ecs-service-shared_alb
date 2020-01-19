.PHONY: README.md
documentation:
	@echo "Removing everything from the Inputs section onwards"
	printf '%s\n' "`awk '/## Inputs/{exit}1' README.md`" > README.tmp
	@echo "Adding terraform-docs generated Inputs and Outputs to the end of README.md"
	printf '%s\n' "`terraform-docs md .`" >> README.tmp
	mv README.tmp README.md

init: config
	terraform init

init-upgrade:
	terraform init -upgrade=true

config:
	@if [[ ! -f local.ini ]]; then cp local.ini.dist local.ini; fi

plan: init
	terraform plan -var-file=local.ini

apply:
	terraform apply -var-file=local.ini

destroy-plan:
	terraform plan -destroy -var-file=local.ini

destroy:
	terraform destroy -var-file=local.ini
