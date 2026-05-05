terraform {
  backend "s3" {
    bucket         = "wirfo-moodle-tfstate-288761747885"
    key            = "pilot/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "wirfo-moodle-tflock"
    encrypt        = true
  }
}
