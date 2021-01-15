variable "on_prem_ip_ranges" {
  description = "IP ranges for On-Prem networks"
  type = list(string)
  default = []
}