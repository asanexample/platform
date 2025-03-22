/**
 * Get the public IP of the client making the API call
 */

data "http" "public_ip" {
  url = "https://api.ipify.org?format=text"
}

output "public_ip" {
  description = "The public IP address of the client"
  value       = trimspace(data.http.public_ip.response_body)
} 