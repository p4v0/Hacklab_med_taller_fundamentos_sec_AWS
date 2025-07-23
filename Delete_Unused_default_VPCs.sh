#!/bin/bash

# Lista de regiones a excluir (donde sí uses VPCs por defecto y NO quieras que se borren) (separadas por espacios)
EXCLUDED_REGIONS="ap-northeast-3 ap-northeast-2 ap-northeast-1 ca-central-1 sa-east-1 ap-southeast-1 ap-southeast-2 eu-central-1 us-east-1 us-east-2 us-west-1 us-west-2"

# Obtener todas las regiones habilitadas en la cuenta
echo "Obteniendo regiones habilitadas en la cuenta AWS..."
ALL_REGIONS=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

# Mostrar todas las regiones habilitadas
echo "Todas las regiones habilitadas:"
echo "---------------------------------------------------"
echo "$ALL_REGIONS" | tr '\t' '\n'
echo "---------------------------------------------------"

# Inicializar variable para regiones filtradas
FILTERED_REGIONS=""

# Recorrer todas las regiones habilitadas y filtrar las excluidas
for region in $ALL_REGIONS; do
    # Verificar si la región está en la lista de excluidas
    if [[ ! " $EXCLUDED_REGIONS " =~ " $region " ]]; then
        FILTERED_REGIONS="$FILTERED_REGIONS $region"
    fi
done

# Mostrar regiones habilitadas sin las excluidas
echo "Regiones filtradas (excluyendo las especificadas en EXCLUDED_REGIONS):"
echo "---------------------------------------------------"
echo "$FILTERED_REGIONS" | tr ' ' '\n' | grep -v '^$'
echo "---------------------------------------------------"
echo "Regiones excluidas: $EXCLUDED_REGIONS" | tr ' ' '\n' | grep -v '^$'

# Solicitar confirmación al usuario antes de eliminar VPCs
echo "¡ADVERTENCIA! Se eliminarán las VPCs por defecto en las siguientes regiones:"
echo "$FILTERED_REGIONS" | tr ' ' '\n' | grep -v '^$'
echo "Esta acción es IRREVERSIBLE. ¿Desea continuar? (y/n): "
read -r CONFIRMATION

if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
    echo "Operación cancelada por el usuario."
    exit 0
fi

# Eliminar VPC por defecto en las regiones filtradas
echo "Eliminando VPCs por defecto en las regiones filtradas..."
echo "---------------------------------------------------"

for region in $FILTERED_REGIONS; do
    echo "Procesando región: $region"
    
    # Obtener IDs de las VPCs por defecto en la región
    DEFAULT_VPCS=$(aws ec2 describe-vpcs --region $region --filters Name=isDefault,Values=true --query "Vpcs[*].VpcId" --output text)
    
    if [ -z "$DEFAULT_VPCS" ]; then
        echo "  No se encontró VPC por defecto en $region"
        continue
    fi
    
    for vpc in $DEFAULT_VPCS; do
        echo "  Eliminando VPC por defecto $vpc en $region"
        
        # Eliminar subnets asociadas
        SUBNETS=$(aws ec2 describe-subnets --region $region --filters Name=vpc-id,Values=$vpc --query "Subnets[*].SubnetId" --output text)
        for subnet in $SUBNETS; do
            echo "    Eliminando subnet $subnet"
            aws ec2 delete-subnet --region $region --subnet-id $subnet
        done
        
        # Eliminar Internet Gateways asociados
        IGWs=$(aws ec2 describe-internet-gateways --region $region --filters Name=attachment.vpc-id,Values=$vpc --query "InternetGateways[*].InternetGatewayId" --output text)
        for igw in $IGWs; do
            echo "    Desvinculando y eliminando Internet Gateway $igw"
            aws ec2 detach-internet-gateway --region $region --internet-gateway-id $igw --vpc-id $vpc
            aws ec2 delete-internet-gateway --region $region --internet-gateway-id $igw
        done
        
        # Eliminar la VPC
        echo "    Eliminando VPC $vpc"
        aws ec2 delete-vpc --region $region --vpc-id $vpc
        echo "  VPC por defecto eliminada en $region"
    done
done

echo "---------------------------------------------------"
echo "Proceso completado"
