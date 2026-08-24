variable "name" {
  description = "Prefixo de nomes dos recursos de rede."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidade utilizadas pelas subnets."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (mesma ordem de availability_zones)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (mesma ordem de availability_zones)."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway(s) para saída de internet das subnets privadas."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT Gateway compartilhado (reduz custo)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
