output "instance_id" {
  description = "ID de la instancia EC2"
  value       = aws_instance.n8n.id
}

output "instance_public_ip" {
  description = "Elastic IP de n8n"
  value       = aws_eip.n8n.public_ip
}

output "n8n_url" {
  description = "URL pública de n8n"
  value       = "https://${var.subdomain}.${var.root_domain}"
}

output "ssm_session_command" {
  description = "Comando para conectarte por SSM"
  value       = "aws ssm start-session --target ${aws_instance.n8n.id} --profile ${var.aws_profile} --region ${var.aws_region}"
}

output "post_deploy_steps" {
  description = "Pasos después del deploy"
  value       = <<-EOT

    ====================================================
    PASOS DESPUÉS DEL DESPLIEGUE
    ====================================================

    1. Esperar 3-5 minutos a que user_data termine.

    2. Conectarse por SSM y ver progreso:
       aws ssm start-session --target ${aws_instance.n8n.id} --profile ${var.aws_profile}
       sudo tail -f /var/log/user-data.log

    3. Verificar contenedores arriba:
       cd /opt/n8n && sudo docker compose ps

    4. Visitar:
       https://${var.subdomain}.${var.root_domain}

    5. Crear la cuenta Owner (TÚ).
       Activa 2FA inmediatamente: Settings → Personal.

    6. Invitar al equipo:
       Settings → Users → Invite users.

    ====================================================
  EOT
}
