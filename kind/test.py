from botocore.exceptions import ClientError


def process_rds_instances(rds_client):
    """Processa e desliga instâncias RDS standalone"""
    stopped = []
    try:
        paginator = rds_client.get_paginator('describe_db_instances')
        page_iterator = paginator.paginate()
        for page in page_iterator:
            for instance in page['DBInstances']:
                try:
                    db_id = instance['DBInstanceIdentifier']
                    status = instance['DBInstanceStatus']
                    if status != 'available':
                        print(f"[SKIP] {db_id} - Status: {status}")
                        continue
                    # CORREÇÃO: Buscar tags explicitamente via ARN
                    tags = []
                    if instance.get('DBInstanceArn'):
                        try:
                            tags = rds_client.list_tags_for_resource(
                                ResourceName=instance['DBInstanceArn']
                            ).get('TagList', [])
                        except ClientError as e:
                            print(f"[WARN] {db_id} - Erro ao buscar tags: {e.response['Error']['Code']}")
                    # Debug: verificar tags carregadas
                    print(f"[DEBUG] {db_id} - Tags encontradas: {tags}")
                    # Verificar tag de exclusão
                    if has_tag(tags, 'shutdown', 'never'):
                        print(f"[SKIP] {db_id} - Tag 'shutdown=never' presente")
                        continue
                    # Verificar tag de controle
                    if not has_tag(tags, 'start_stop', 'true'):
                        print(f"[SKIP] {db_id} - Tag 'start_stop=true' ausente")
                        continue
                    # Desligar instância
                    rds_client.stop_db_instance(DBInstanceIdentifier=db_id)
                    print(f"[STOPPED] Instância RDS: {db_id}")
                    stopped.append(db_id)
                except ClientError as e:
                    error_code = e.response['Error']['Code']
                    # Tratar erros específicos
                    if error_code == 'InvalidDBInstanceState':
                        print(f"[WARN] {db_id} - Instância já está em processo de parada")
                    elif error_code == 'InvalidParameterCombination':
                        print(f"[WARN] {db_id} - Instância não pode ser parada (ex: réplica de leitura)")
                    else:
                        print(f"[ERROR] {db_id} - {error_code}: {e.response['Error']['Message']}")
                except Exception as e:
                    print(f"[ERROR] {db_id} - Erro inesperado: {str(e)}")
    except Exception as e:
        print(f"Erro ao listar instâncias RDS: {str(e)}")

def has_tag(tags, key, value):
    """Verifica se a lista de tags contém uma tag específica com valor específico"""
    for tag in tags:
        if tag['Key'] == key and tag['Value'] == value:
            return True
    return False