terraform {
  backend "s3" {
    key          = "n8n/pflondon/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    profile      = "pflondon"
    region       = "us-east-1"
  }
}
