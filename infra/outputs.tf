output "artifact_bucket" {
  value = aws_s3_bucket.lab.id
}

output "server_host" {
  value = aws_instance.api.public_ip
}

output "server_user" {
  value = "ubuntu"
}

output "github_role_arn" {
  value = aws_iam_role.github.arn
}

output "security_group_id" {
  value = aws_security_group.api.id
}
# artifact_bucket = "income-lab-v1rtuos024-2026"
# github_role_arn = "arn:aws:iam::222408967204:role/income-github-ab1b5b0aa866d4ad3a94d02cb4"
# security_group_id = "sg-0aa31e6c05a8b6b3e"
# server_host = "100.58.172.102"
# server_user = "ubuntu"