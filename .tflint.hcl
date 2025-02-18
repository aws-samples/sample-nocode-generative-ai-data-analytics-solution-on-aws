plugin "aws" {
    enabled = true
    version = "0.31.0"
    source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

plugin "terraform" {
  enabled = true
  version = "0.5.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

# rule "aws_lambda_function_invalid_runtime" {
#   enabled = false
# }

# rule "aws_s3_bucket_name" {
#   enabled = false
# }

rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_required_version" {
  enabled = false
}
