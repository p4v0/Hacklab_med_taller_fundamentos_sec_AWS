#!/bin/bash

# Regiones que NO quieres afectar, OJITO!!!
EXCLUIR_REGIONES=("us-east-1" "us-west-2")

# Obtener todas las regiones habilitadas en la cuenta (opt-in-not-required u opted-in)
TODAS_REGIONES=$(aws ec2 describe-regions \
  --filters "Name=opt-in-status,Values=opt-in-not-required,opted-in" \
  --query "Regions[].RegionName" --output text)

# Filtrar regiones excluidas
REGIONES_FILTRADAS=()
for REGION in $TODAS_REGIONES; do
  if [[ ! " ${EXCLUIR_REGIONES[*]} " =~ " ${REGION} " ]]; then
    REGIONES_FILTRADAS+=("$REGION")
  fi
done

# Loop principal: eliminar VPC por defecto y sus dependencias
for REGION in "${REGIONES_FILTRADAS[@]}"; do
  echo "Procesando región: $REGION"

  # Obtener VPC por defecto
  VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
    --filters Name=isDefault,Values=true \
    --query "Vpcs[0].VpcId" --output text)

  if [[ "$VPC_ID" == "None" ]]; then
    echo "No hay VPC por defecto en $REGION"
    continue
  fi

  echo "VPC por defecto encontrada: $VPC_ID"

  # Eliminar subnets
  SUBNETS=$(aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "Subnets[].SubnetId" --output text)

  for SUBNET in $SUBNETS; do
    echo "Eliminando subnet: $SUBNET"
    aws ec2 delete-subnet --subnet-id "$SUBNET" --region "$REGION"
  done

  # Eliminar gateways (Internet Gateways)
  GATEWAYS=$(aws ec2 describe-internet-gateways --region "$REGION" \
    --filters Name=attachment.vpc-id,Values="$VPC_ID" \
    --query "InternetGateways[].InternetGatewayId" --output text)

  for GW in $GATEWAYS; do
    echo "Desasociando y eliminando IGW: $GW"
    aws ec2 detach-internet-gateway --internet-gateway-id "$GW" --vpc-id "$VPC_ID" --region "$REGION"
    aws ec2 delete-internet-gateway --internet-gateway-id "$GW" --region "$REGION"
  done

  # Eliminar grupos de seguridad (excepto el default)
  SG_IDS=$(aws ec2 describe-security-groups --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)

  for SG in $SG_IDS; do
    echo "Eliminando SG: $SG"
    aws ec2 delete-security-group --group-id "$SG" --region "$REGION"
  done

  # Eliminar tablas de rutas (excepto las asociadas automáticamente)
  RTB_IDS=$(aws ec2 describe-route-tables --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "RouteTables[?Associations[?Main!=true]].RouteTableId" --output text)

  for RTB in $RTB_IDS; do
    echo "Eliminando tabla de rutas: $RTB"
    aws ec2 delete-route-table --route-table-id "$RTB" --region "$REGION"
  done

  # Finalmente, eliminar la VPC
  echo "Eliminando VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION"
done
