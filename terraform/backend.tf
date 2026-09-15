terraform {
  backend "s3" {
    bucket       = "streamforge-tfstate-879807128870-us-west-2"
    key          = "streamforge/dev/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}