output "attacker_access_key_id" {
  description = "Attacker AWS access key ID - starting credentials for the scenario"
  value       = aws_iam_access_key.attacker.id
  sensitive   = false
}

output "attacker_secret_access_key" {
  description = "Attacker AWS secret access key"
  value       = aws_iam_access_key.attacker.secret
  sensitive   = true
}

output "knowledge_base_bucket" {
  description = "Name of the misconfigured knowledge base S3 bucket"
  value       = aws_s3_bucket.knowledge_base.bucket
}

output "sensitive_data_bucket" {
  description = "Name of the sensitive data bucket (pivot target)"
  value       = aws_s3_bucket.sensitive_data.bucket
}

output "bedrock_agent_id" {
  description = "Bedrock agent ID"
  value       = aws_bedrockagent_agent.assistant.agent_id
}

output "bedrock_agent_alias_id" {
  description = "Bedrock agent alias ID - needed to invoke the agent"
  value       = aws_bedrockagent_agent_alias.live.agent_alias_id
}

output "knowledge_base_id" {
  description = "Bedrock knowledge base ID"
  value       = aws_bedrockagent_knowledge_base.main.id
}

output "data_source_id" {
  description = "Bedrock knowledge base data source ID - needed to start ingestion"
  value       = aws_bedrockagent_data_source.s3_docs.data_source_id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret (pivot target)"
  value       = aws_secretsmanager_secret.internal_api_key.arn
}

output "scenario_summary" {
  description = "Quick reference for the scenario"
  value       = <<-EOT
    =============================================
    CloudGoat: RAG Injection via AI Knowledge Base
    =============================================
    Starting credentials have been provisioned.
    Run: terraform output -raw attacker_secret_access_key

    Your goal: pivot from the knowledge base bucket
    into sensitive AWS resources using indirect
    prompt injection against the Bedrock agent.

    Hint: What happens when the agent retrieves
    a document that contains instructions?
    =============================================
  EOT
}
